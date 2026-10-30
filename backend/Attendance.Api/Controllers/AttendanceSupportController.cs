using System.ComponentModel.DataAnnotations;
using System.Data;
using Attendance.Api.Data;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Attendance.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
namespace Attendance.Api.Controllers;
public sealed class AttendanceSupport:Entity {
 public Guid UserId {get;set;}
 public AppUser User {get;set;}=null!;
 public string Kind {get;set;}="MissingSchedule";
 public string Reason {get;set;}="";
 public string Status {get;set;}="Pending";
 public string? DecisionReason {get;set;}
 public DateTimeOffset? ReviewedAtUtc {get;set;}
}
public sealed record SupportDto([Required] string Kind,[Required,StringLength(1000,MinimumLength=10)]string Reason);
public sealed record SupportDecisionDto([Required,StringLength(1000,MinimumLength=5)]string Reason);
public sealed record MissingCheckoutDecisionDto(Guid EmployeeShiftId,DateTimeOffset EffectiveAtUtc,[Required,StringLength(1000,MinimumLength=5)]string Reason);
[ApiController,Route("api/v1/attendance-support"),Authorize]
public sealed class AttendanceSupportController(AttendanceDbContext db,AuditService audit):ControllerBase {
 [HttpGet]public Task<object> List(int page=1,int pageSize=100,CancellationToken ct=default,string? status=null,Guid? departmentId=null){var q=db.Set<AttendanceSupport>().AsQueryable();if(!string.IsNullOrEmpty(status))q=q.Where(x=>x.Status==status);if(User.Admin()&&departmentId.HasValue)q=q.Where(x=>db.Employees.Any(e=>e.UserId==x.UserId&&e.DepartmentId==departmentId));if(!User.Admin())q=q.Where(x=>x.UserId==User.UserId());return Paging.Page(q.OrderByDescending(x=>x.CreatedAtUtc).Select(x=>new{x.Id,x.Kind,x.Reason,x.Status,x.DecisionReason,x.CreatedAtUtc,x.ReviewedAtUtc,employeeName=x.User.FullName,employeeId=db.Employees.Where(e=>e.UserId==x.UserId).Select(e=>(Guid?)e.Id).FirstOrDefault()}),page,pageSize,ct);}
 [HttpPost("{id:guid}/checkout"),Authorize(Roles="Admin")]public async Task<object> CorrectCheckout(Guid id,MissingCheckoutDecisionDto d,CancellationToken ct){
  await using var tx=await db.Database.BeginTransactionAsync(IsolationLevel.Serializable,ct);await TimesheetGuard.Lock(db,ct);
  var item=await db.Set<AttendanceSupport>().FromSqlInterpolated($"SELECT * FROM AttendanceSupports WITH (UPDLOCK, ROWLOCK) WHERE Id={id}").SingleOrDefaultAsync(ct)??throw CatalogService.Missing();
  if(item.Kind!="MissingCheckOut"||item.Status!="Pending")throw new ApiException(409,"InvalidRequest","Yêu cầu không còn chờ bổ sung giờ ra.");
  var a=await db.EmployeeShifts.FromSqlInterpolated($"SELECT * FROM EmployeeShifts WITH (UPDLOCK, ROWLOCK) WHERE Id={d.EmployeeShiftId}").Include(x=>x.Employee).SingleOrDefaultAsync(ct)??throw CatalogService.Missing();
  if(a.Employee.UserId!=item.UserId)throw CatalogService.Missing();
  var checkIn=await db.AttendanceRecords.SingleOrDefaultAsync(x=>x.EmployeeShiftId==a.Id&&x.Action=="CheckIn",ct);
  if(checkIn is null||d.EffectiveAtUtc<checkIn.EffectiveAtUtc||d.EffectiveAtUtc>DateTimeOffset.UtcNow||d.EffectiveAtUtc>a.EndUtc.AddHours(6))throw new ApiException(400,"InvalidCheckoutTime","Giờ ra phải sau giờ vào, không ở tương lai và trong 6 giờ sau kết thúc ca.");
  if(await db.AttendanceRecords.AnyAsync(x=>x.EmployeeShiftId==a.Id&&x.Action=="CheckOut",ct))throw new ApiException(409,"AttendanceAlreadyExists","Ca đã có giờ ra.");
  var record=new AttendanceRecord{EmployeeShiftId=a.Id,AttemptId=null,Action="CheckOut",EffectiveAtUtc=d.EffectiveAtUtc,RecordedAtUtc=DateTimeOffset.UtcNow,Source="AdminCorrection"};db.AttendanceRecords.Add(record);
  item.Status="Resolved";item.DecisionReason=d.Reason.Trim();item.ReviewedAtUtc=DateTimeOffset.UtcNow;
  audit.Add(User.UserId(),"AttendanceSupport",id,"CheckoutCorrected",new{recordId=record.Id,d.EmployeeShiftId,d.EffectiveAtUtc,d.Reason});await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);return new{id=record.Id,item.Status,record.Source,record.EffectiveAtUtc};
 }
 [HttpPost,Authorize(Roles="Employee")]public async Task<object> Create(SupportDto d,CancellationToken ct){
  if(d.Kind is not("MissingSchedule" or "MissingCheckOut"))throw new ApiException(400,"InvalidKind","Loại yêu cầu không hợp lệ.");
  if(await db.Set<AttendanceSupport>().CountAsync(x=>x.UserId==User.UserId()&&x.Status=="Pending",ct)>=5)throw new ApiException(409,"PendingRequests","Bạn có 5 yêu cầu đang chờ xử lý.");
  var item=new AttendanceSupport{UserId=User.UserId(),Kind=d.Kind,Reason=d.Reason.Trim()};db.Add(item);audit.Add(User.UserId(),"AttendanceSupport",item.Id,"Created");await db.SaveChangesAsync(ct);return new{id=item.Id,item.Status};
 }
 [HttpPost("{id:guid}/resolve"),Authorize(Roles="Admin")]public async Task<object> Resolve(Guid id,SupportDecisionDto d,CancellationToken ct){var item=await db.Set<AttendanceSupport>().FindAsync([id],ct)??throw CatalogService.Missing();if(item.Status!="Pending")throw new ApiException(409,"AlreadyReviewed","Yêu cầu đã được xử lý.");item.Status="Resolved";item.DecisionReason=d.Reason.Trim();item.ReviewedAtUtc=DateTimeOffset.UtcNow;audit.Add(User.UserId(),"AttendanceSupport",id,"Resolved",new{d.Reason});await db.SaveChangesAsync(ct);return new{item.Status};}
}
