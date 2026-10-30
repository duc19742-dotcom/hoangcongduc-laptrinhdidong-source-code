using Attendance.Api.Data;
using Attendance.Api.Middleware;
using Attendance.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
namespace Attendance.Api.Controllers;
[ApiController,Route("api/v1/work-schedules"),Authorize(Roles="Admin")]
public sealed class WorkSchedulesController(AttendanceDbContext db,WorkScheduleService service,AuditService audit):ControllerBase {
 [HttpGet]public Task<object> List(int page=1,int pageSize=100,CancellationToken ct=default)=>Paging.Page(db.Set<WorkSchedule>().OrderByDescending(x=>x.CreatedAtUtc).Select(x=>new{x.Id,x.EmployeeId,employeeName=x.EmployeeId==null?"Mặc định toàn công ty":x.Employee!.FullName,shiftName=x.Shift.Name,locationName=x.WorkLocation.Name,x.WeekdaysMask,x.FromDate,x.ToDate,x.IsActive}),page,pageSize,ct);
 [HttpPost]public Task<object> Create(WorkScheduleDto d,CancellationToken ct)=>service.Create(d,User.UserId(),ct);
 [HttpDelete("{id:guid}")]public async Task<IActionResult> Stop(Guid id,CancellationToken ct){var s=await db.Set<WorkSchedule>().FindAsync([id],ct)??throw CatalogService.Missing();s.IsActive=false;audit.Add(User.UserId(),"WorkSchedule",id,"Stopped");await db.SaveChangesAsync(ct);return NoContent();}
}
