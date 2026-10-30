using System.Text.Json;
using Attendance.Api.Data;
using Attendance.Api.DTOs;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Attendance.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using QRCoder;
namespace Attendance.Api.Controllers;

[ApiController,Route("api/v1/qr-sessions"),Authorize]
public sealed class QrController(AttendanceService s,AttendanceDbContext db,AuditService audit,SiteQrService sites):ControllerBase
{
 [HttpPost("site"),Authorize(Roles="Admin")]public Task<object>Site(SiteQrDto d,CancellationToken ct)=>sites.Create(d.WorkLocationId,User.UserId(),ct);
 [HttpPost("display"),Authorize(Roles="Admin")]public Task<object>Display(SiteQrDto d,CancellationToken ct)=>sites.BeginDisplay(d.WorkLocationId,User.UserId(),ct);
 [HttpPost("display/refresh"),AllowAnonymous]public Task<object>Refresh(SiteDisplayDto d,CancellationToken ct)=>sites.FromDisplay(d.DisplayToken,ct);
 [HttpPost("render"),AllowAnonymous]public async Task<IActionResult>Render(QrRenderDto d,CancellationToken ct)
 {var hash=Secrets.Hash(d.QrToken);if(!await db.QrSessions.AnyAsync(x=>x.TokenHash==hash&&!x.RevokedAtUtc.HasValue&&x.ExpiresAtUtc>DateTimeOffset.UtcNow,ct)&&!await db.Set<SiteQrSession>().AnyAsync(x=>x.TokenHash==hash&&!x.RevokedAtUtc.HasValue&&x.ExpiresAtUtc>DateTimeOffset.UtcNow,ct))throw new ApiException(410,"QrExpired","QR đã hết hạn hoặc không hợp lệ.");using var generator=new QRCodeGenerator();using var data=generator.CreateQrCode(d.QrToken,QRCodeGenerator.ECCLevel.M);using var png=new PngByteQRCode(data);return File(png.GetGraphic(10),"image/png");}
 [HttpPost,Authorize(Roles="Admin")]public async Task<IActionResult>Create(QrCreateDto d,CancellationToken ct)=>StatusCode(201,await s.CreateQr(d,User.UserId(),ct));
 [HttpPost("verify"),Authorize(Roles="Employee")]public Task<object>Verify(QrVerifyDto d,CancellationToken ct)=>s.VerifyQr(d,User.UserId(),ct);
 [HttpDelete("{id:guid}"),Authorize(Roles="Admin")]public async Task<IActionResult>Revoke(Guid id,CancellationToken ct){var q=await db.QrSessions.FindAsync([id],ct)??throw CatalogService.Missing();q.RevokedAtUtc=DateTimeOffset.UtcNow;audit.Add(User.UserId(),"QrSession",id,"Revoked");await db.SaveChangesAsync(ct);return NoContent();}
}
[ApiController,Route("api/v1/attendance"),Authorize]
public sealed class AttendanceController(AttendanceService s,AttendanceDbContext db,WorkScheduleService schedules):ControllerBase
{
 [HttpGet("options"),Authorize(Roles="Employee")]public async Task<object> Options(string action="CheckIn",CancellationToken ct=default){
  await schedules.Materialize(User.UserId(),ct);var employee=await s.EmployeeId(User.UserId(),ct);var now=DateTimeOffset.UtcNow;
  var q=db.EmployeeShifts.Where(x=>x.EmployeeId==employee&&x.Shift.IsActive&&x.WorkLocation.IsActive&&x.StartUtc<=now.AddHours(2)&&x.EndUtc>=now.AddHours(action=="CheckOut"?-6:0));
  if(action=="CheckOut")q=q.Where(x=>db.AttendanceRecords.Any(r=>r.EmployeeShiftId==x.Id&&r.Action=="CheckIn")&&!db.AttendanceRecords.Any(r=>r.EmployeeShiftId==x.Id&&r.Action=="CheckOut"));
  var items=await q.OrderBy(x=>x.StartUtc).Select(x=>new{x.Id,shiftName=x.Shift.Name,locationName=x.WorkLocation.Name,latitude=x.WorkLocation.Latitude,longitude=x.WorkLocation.Longitude,maxAccuracyMeters=x.WorkLocation.MaxAccuracyMeters,radiusMeters=x.WorkLocation.RadiusMeters,x.WorkDate,x.StartUtc,x.EndUtc,hasCheckIn=db.AttendanceRecords.Any(r=>r.EmployeeShiftId==x.Id&&r.Action=="CheckIn"),hasCheckOut=db.AttendanceRecords.Any(r=>r.EmployeeShiftId==x.Id&&r.Action=="CheckOut")}).ToListAsync(ct);
  return new{items,totalCount=items.Count,page=1,pageSize=100,serverTimeUtc=now};
 }
 [HttpPost("check-in"),Authorize(Roles="Employee")]public Task<IActionResult>In(AttendanceSubmitDto d,CancellationToken ct)=>Submit(d,"CheckIn",ct);
 [HttpPost("check-out"),Authorize(Roles="Employee")]public Task<IActionResult>Out(AttendanceSubmitDto d,CancellationToken ct)=>Submit(d,"CheckOut",ct);
 private async Task<IActionResult>Submit(AttendanceSubmitDto d,string action,CancellationToken ct)
 {if(!Guid.TryParse(Request.Headers["Idempotency-Key"],out var key))throw new ApiException(400,"MissingIdempotencyKey","Cần header Idempotency-Key dạng UUID.");var result=await s.Submit(d,action,key,User.UserId(),ct);var status=JsonSerializer.SerializeToElement(result).GetProperty("status").GetString();return StatusCode(status=="Accepted"?201:202,result);}
 [HttpGet("me"),Authorize(Roles="Employee")]public async Task<object>Mine(DateOnly? from,DateOnly? to,int page=1,int pageSize=20,CancellationToken ct=default)=>await s.History(await s.EmployeeId(User.UserId(),ct),from,to,page,pageSize,ct);
 [HttpGet,Authorize(Roles="Admin")]public Task<object>All(Guid? employeeId,DateOnly? from,DateOnly? to,int page=1,int pageSize=20,CancellationToken ct=default)=>s.History(employeeId,from,to,page,pageSize,ct);
 [HttpGet("employees/{employeeId:guid}"),Authorize(Roles="Admin")]public Task<object>Employee(Guid employeeId,DateOnly? from,DateOnly? to,int page=1,int pageSize=20,CancellationToken ct=default)=>s.History(employeeId,from,to,page,pageSize,ct);
 [HttpGet("statistics"),Authorize(Roles="Admin")]public Task<object>Stats(DateOnly? from,DateOnly? to,Guid? departmentId,CancellationToken ct)=>s.Statistics(from,to,departmentId,ct);
 [HttpGet("attempts"),Authorize(Roles="Employee")]public async Task<object>Attempts(DateOnly? from,DateOnly? to,int page=1,int pageSize=20,CancellationToken ct=default)
 {var e=await s.EmployeeId(User.UserId(),ct);var range=Paging.Dates(from,to);return await Paging.Page(db.AttendanceAttempts.Where(x=>x.EmployeeId==e&&x.ReceivedAtUtc>=range.Start&&x.ReceivedAtUtc<range.End).OrderByDescending(x=>x.ReceivedAtUtc).Select(x=>new{x.Id,x.Action,x.Outcome,x.ReasonCode,x.ReceivedAtUtc,x.DistanceMeters,x.AccuracyMeters,hasRequest=db.AttendanceRequests.Any(r=>r.AttemptId==x.Id)}),page,pageSize,ct);}
 [HttpGet("attempts/{id:guid}")]public async Task<object>Attempt(Guid id,CancellationToken ct){var a=await db.AttendanceAttempts.Include(x=>x.Employee).FirstOrDefaultAsync(x=>x.Id==id,ct)??throw CatalogService.Missing();if(!User.Admin()&&a.Employee.UserId!=User.UserId())throw CatalogService.Missing();return await s.Result(a,ct);}
}
[ApiController,Route("api/v1/attendance-requests"),Authorize]
public sealed class RequestsController(AttendanceDbContext db,AttendanceService s,AuditService audit):ControllerBase
{
 [HttpGet]public Task<object>List(string? status,int page=1,int pageSize=20,CancellationToken ct=default,Guid? departmentId=null)
 {var q=db.AttendanceRequests.AsQueryable();if(User.Admin()&&departmentId.HasValue)q=q.Where(x=>x.Employee.DepartmentId==departmentId);if(!User.Admin())q=q.Where(x=>x.Employee.UserId==User.UserId());if(!string.IsNullOrWhiteSpace(status))q=q.Where(x=>x.Status==status);return Paging.Page(q.OrderByDescending(x=>x.CreatedAtUtc).Select(x=>new{x.Id,x.AttemptId,x.Reason,x.Status,x.CreatedAtUtc,x.ReviewedAtUtc,x.DecisionReason,employeeName=x.Employee.FullName,action=x.Attempt.Action,receivedAtUtc=x.Attempt.ReceivedAtUtc,rowVersion=x.RowVersion}),page,pageSize,ct);}
 private async Task<AttendanceRequest>Own(Guid id,CancellationToken ct)
 {var x=await db.AttendanceRequests.Include(x=>x.Employee).Include(x=>x.Attempt).FirstOrDefaultAsync(x=>x.Id==id,ct)??throw CatalogService.Missing();if(!User.Admin()&&x.Employee.UserId!=User.UserId())throw CatalogService.Missing();return x;}
 [HttpGet("{id:guid}")]public async Task<object>Detail(Guid id,CancellationToken ct)
 {var x=await Own(id,ct);return new{x.Id,x.Reason,x.Status,x.CreatedAtUtc,x.ReviewedAtUtc,x.DecisionReason,rowVersion=x.RowVersion,employeeName=x.Employee.FullName,evidence=await s.Result(x.Attempt,ct),events=await EventsQuery(id).ToListAsync(ct)};}
 private IQueryable<object>EventsQuery(Guid id)=>from e in db.AttendanceRequestEvents where e.RequestId==id orderby e.CreatedAtUtc join u in db.Users on e.ActorUserId equals u.Id select(object)new{e.Id,e.OldStatus,e.NewStatus,e.Note,occurredAtUtc=e.CreatedAtUtc,actorName=u.FullName};
 [HttpGet("{id:guid}/events")]public async Task<object>Events(Guid id,CancellationToken ct){await Own(id,ct);return await EventsQuery(id).ToListAsync(ct);}
 [HttpPost,Authorize(Roles="Employee")]public async Task<IActionResult>Create(RequestCreateDto d,CancellationToken ct)
 {var emp=await s.EmployeeId(User.UserId(),ct);var a=await db.AttendanceAttempts.FirstOrDefaultAsync(x=>x.Id==d.AttemptId&&x.EmployeeId==emp,ct)??throw CatalogService.Missing();if(a.Outcome!="NeedsReview")throw new ApiException(409,"NoException","Lần chấm công không thuộc diện chờ xác minh.");var r=new AttendanceRequest{AttemptId=a.Id,EmployeeId=emp,Reason=d.Reason.Trim()};db.AttendanceRequests.Add(r);Event(r,null,"Pending",d.Reason);audit.Add(User.UserId(),"AttendanceRequest",r.Id,"Created");await db.SaveChangesAsync(ct);return StatusCode(201,new{r.Id,r.Status,rowVersion=r.RowVersion});}
 [HttpPut("{id:guid}"),Authorize(Roles="Employee")]public async Task<object>Update(Guid id,RequestEditDto d,CancellationToken ct)
 {var x=await Own(id,ct);Pending(x);Secrets.Version(db,x,d.RowVersion);x.Reason=d.Reason.Trim();Event(x,"Pending","Pending","Sửa lý do: "+d.Reason);audit.Add(User.UserId(),"AttendanceRequest",id,"ReasonUpdated");await db.SaveChangesAsync(ct);return new{x.Id,x.Status,rowVersion=x.RowVersion};}
 [HttpPost("{id:guid}/cancel"),Authorize(Roles="Employee")]public Task<object>Cancel(Guid id,DecisionDto d,CancellationToken ct)=>Decide(id,d,"Cancelled",ct);
 [HttpPost("{id:guid}/approve"),Authorize(Roles="Admin")]public Task<object>Approve(Guid id,DecisionDto d,CancellationToken ct)=>Decide(id,d,"Approved",ct);
 [HttpPost("{id:guid}/reject"),Authorize(Roles="Admin")]public Task<object>Reject(Guid id,DecisionDto d,CancellationToken ct)=>Decide(id,d,"Rejected",ct);
 private async Task<object>Decide(Guid id,DecisionDto d,string status,CancellationToken ct)
 {
  await using var tx=await db.Database.BeginTransactionAsync(ct);await TimesheetGuard.Lock(db,ct);var x=await Own(id,ct);Pending(x);Secrets.Version(db,x,d.RowVersion);
  if(status=="Approved")
  {
   var a=x.Attempt;await db.EmployeeShifts.FromSqlInterpolated($"SELECT * FROM EmployeeShifts WITH (UPDLOCK, ROWLOCK) WHERE Id={a.EmployeeShiftId}").SingleAsync(ct);
   if(await db.AttendanceRecords.AnyAsync(r=>r.EmployeeShiftId==a.EmployeeShiftId&&r.Action==a.Action,ct))throw new ApiException(409,"AttendanceAlreadyExists","Ca đã có bản ghi cho thao tác này.");
   if(a.Action=="CheckOut"&&!await db.AttendanceRecords.AnyAsync(r=>r.EmployeeShiftId==a.EmployeeShiftId&&r.Action=="CheckIn"&&r.EffectiveAtUtc<=a.ReceivedAtUtc,ct))throw new ApiException(409,"CheckInRequired","Cần xác nhận giờ vào hợp lệ trước giờ ra.");
   db.AttendanceRecords.Add(new AttendanceRecord{EmployeeShiftId=a.EmployeeShiftId,AttemptId=a.Id,Action=a.Action,EffectiveAtUtc=a.ReceivedAtUtc,RecordedAtUtc=DateTimeOffset.UtcNow,Source="AdminApproved",ApprovedRequestId=x.Id});
  }
  x.Status=status;x.DecisionReason=d.Reason.Trim();if(status!="Cancelled"){x.ReviewedByUserId=User.UserId();x.ReviewedAtUtc=DateTimeOffset.UtcNow;}
  Event(x,"Pending",status,d.Reason);audit.Add(User.UserId(),"AttendanceRequest",id,status,new{d.Reason});await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);return new{x.Id,x.Status,rowVersion=x.RowVersion};
 }
 private static void Pending(AttendanceRequest x){if(x.Status!="Pending")throw new ApiException(409,"RequestClosed","Yêu cầu đã được xử lý hoặc đã hủy.");}
 private void Event(AttendanceRequest r,string? before,string after,string note)=>db.AttendanceRequestEvents.Add(new AttendanceRequestEvent{RequestId=r.Id,ActorUserId=User.UserId(),OldStatus=before,NewStatus=after,Note=note.Trim()});
}
[ApiController,Route("api/v1/audit-logs"),Authorize(Roles="Admin")]
public sealed class AuditController(AttendanceDbContext db):ControllerBase
{
 [HttpGet]public Task<object>List(string? entityType,Guid? entityId,int page=1,int pageSize=20,CancellationToken ct=default)
 {var q=db.AuditLogs.AsQueryable();if(!string.IsNullOrWhiteSpace(entityType))q=q.Where(x=>x.EntityType==entityType);if(entityId.HasValue)q=q.Where(x=>x.EntityId==entityId);return Paging.Page(q.OrderByDescending(x=>x.CreatedAtUtc).Select(x=>new{x.Id,x.ActorUserId,x.EntityType,x.EntityId,x.Action,x.DetailsJson,x.CreatedAtUtc}),page,pageSize,ct);}
}

