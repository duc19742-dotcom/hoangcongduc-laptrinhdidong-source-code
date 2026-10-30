using System.ComponentModel.DataAnnotations;
using System.Data;
using Attendance.Api.Data;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Microsoft.EntityFrameworkCore;
namespace Attendance.Api.Services;

public sealed class WorkSchedule:Entity {
 public Guid? EmployeeId {get;set;}
 public Employee? Employee {get;set;}
 public Guid ShiftId {get;set;}
 public Shift Shift {get;set;}=null!;
 public Guid WorkLocationId {get;set;}
 public WorkLocation WorkLocation {get;set;}=null!;
 public int WeekdaysMask {get;set;}=62;
 public DateOnly FromDate {get;set;}
 public DateOnly ToDate {get;set;}
 public bool IsActive {get;set;}=true;
}
public sealed record WorkScheduleDto(Guid? EmployeeId,Guid ShiftId,Guid WorkLocationId,[Range(1,127)] int WeekdaysMask,DateOnly FromDate,DateOnly ToDate);
public sealed class WorkScheduleService(AttendanceDbContext db,AuditService audit) {
 public async Task<object> Create(WorkScheduleDto d,Guid actor,CancellationToken ct) {
  if(d.FromDate>d.ToDate||d.ToDate.DayNumber-d.FromDate.DayNumber>1095)throw new ApiException(400,"InvalidDateRange","Khoảng lịch không hợp lệ, tối đa 3 năm.");
  if(d.EmployeeId.HasValue&&!await db.Employees.AnyAsync(x=>x.Id==d.EmployeeId&&x.IsActive,ct)||!await db.Shifts.AnyAsync(x=>x.Id==d.ShiftId&&x.IsActive,ct)||!await db.WorkLocations.AnyAsync(x=>x.Id==d.WorkLocationId&&x.IsActive,ct))throw CatalogService.Missing();
  await using var tx=await db.Database.BeginTransactionAsync(IsolationLevel.Serializable,ct);await TimesheetGuard.Lock(db,ct);
  // An individual schedule overrides the default; same-level overlaps must be resolved explicitly.
  if(await db.Set<WorkSchedule>().AnyAsync(x=>x.IsActive&&x.EmployeeId==d.EmployeeId&&x.FromDate<=d.ToDate&&x.ToDate>=d.FromDate&&(x.WeekdaysMask&d.WeekdaysMask)!=0,ct))throw new ApiException(409,"ScheduleOverlap","Đã có lịch định kỳ trùng ngày. Ngừng lịch cũ trước khi tạo lịch thay thế.");
  var schedule=new WorkSchedule{EmployeeId=d.EmployeeId,ShiftId=d.ShiftId,WorkLocationId=d.WorkLocationId,WeekdaysMask=d.WeekdaysMask,FromDate=d.FromDate,ToDate=d.ToDate};db.Add(schedule);audit.Add(actor,"WorkSchedule",schedule.Id,"Created");await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);return new{id=schedule.Id};
 }
 public async Task Materialize(Guid user,CancellationToken ct) {
  await using var tx=await db.Database.BeginTransactionAsync(IsolationLevel.Serializable,ct);await TimesheetGuard.Lock(db,ct);
  var employee=await db.Employees.FromSqlInterpolated($"SELECT * FROM Employees WITH (UPDLOCK, ROWLOCK) WHERE UserId={user}").SingleOrDefaultAsync(ct);
  if(employee is null||!employee.IsActive)throw new ApiException(403,"NoEmployee","Chưa có hồ sơ nhân viên đang hoạt động.");
  var today=DateOnly.FromDateTime(DateTime.UtcNow.AddHours(7));
  for(var day=today.AddDays(-1);day<=today;day=day.AddDays(1)) {
   if(await db.TimesheetPeriods.AnyAsync(x=>x.Year==day.Year&&x.Month==day.Month&&x.Status=="Closed",ct))continue;
   var existing=await db.EmployeeShifts.Where(x=>x.EmployeeId==employee.Id&&x.WorkDate==day).ToListAsync(ct);
   if(existing.Any(x=>!x.SourceScheduleId.HasValue))continue;
   var ids=existing.Select(x=>x.Id).ToList();
   if(await db.AttendanceAttempts.AnyAsync(x=>ids.Contains(x.EmployeeShiftId),ct)||await db.AttendanceRecords.AnyAsync(x=>ids.Contains(x.EmployeeShiftId),ct))continue;
   var bit=1<<(int)day.DayOfWeek;
   var candidates=await db.Set<WorkSchedule>().Include(x=>x.Shift).Include(x=>x.WorkLocation).Where(x=>x.IsActive&&x.FromDate<=day&&x.ToDate>=day&&(x.WeekdaysMask&bit)!=0&&(x.EmployeeId==employee.Id||x.EmployeeId==null)&&x.Shift.IsActive&&x.WorkLocation.IsActive).OrderByDescending(x=>x.EmployeeId.HasValue).ToListAsync(ct);
   var schedule=candidates.FirstOrDefault();
   var start=schedule is null?default:Geo.Utc(day,schedule.Shift.StartLocalTime);var end=schedule is null?default:Geo.Utc(day.AddDays(schedule.Shift.EndsNextDay?1:0),schedule.Shift.EndLocalTime);
   if(schedule is not null&&existing.Count==1&&existing[0].SourceScheduleId==schedule.Id&&existing[0].StartUtc==start&&existing[0].EndUtc==end&&existing[0].GraceMinutesSnapshot==schedule.Shift.LateGraceMinutes)continue;
   if(schedule is null){db.EmployeeShifts.RemoveRange(existing);continue;}
   var assignment=existing.Count==1?existing[0]:new EmployeeShift();
   if(existing.Count!=1){db.EmployeeShifts.RemoveRange(existing);db.EmployeeShifts.Add(assignment);}
   assignment.SourceScheduleId=schedule.Id;assignment.EmployeeId=employee.Id;assignment.ShiftId=schedule.ShiftId;assignment.WorkLocationId=schedule.WorkLocationId;assignment.WorkDate=day;assignment.StartUtc=start;assignment.EndUtc=end;assignment.GraceMinutesSnapshot=schedule.Shift.LateGraceMinutes;
  }
  await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);
 }
}
