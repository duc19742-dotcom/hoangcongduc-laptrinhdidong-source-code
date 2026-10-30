using Attendance.Api.Data;
using Attendance.Api.DTOs;
using Attendance.Api.Middleware;
using Attendance.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
namespace Attendance.Api.Controllers;

[ApiController,Route("api/v1/employees"),Authorize]
public sealed class EmployeesController(CatalogService service,AttendanceDbContext db):ControllerBase
{
 [HttpGet,Authorize(Roles="Admin")] public Task<object> List(string? search,Guid? departmentId,bool? isActive,int page=1,int pageSize=20,CancellationToken ct=default)=>service.ListEmployees(search,departmentId,isActive,page,pageSize,ct);
 [HttpGet("{id:guid}"),Authorize(Roles="Admin")] public Task<object> Detail(Guid id,CancellationToken ct)=>service.EmployeeView(id,ct);
 [HttpGet("me"),Authorize(Roles="Employee")] public async Task<object> Me(CancellationToken ct)=>await service.EmployeeView(await db.Employees.Where(x=>x.UserId==User.UserId()).Select(x=>x.Id).SingleAsync(ct),ct);
 [HttpPost,Authorize(Roles="Admin")] public async Task<IActionResult> Create(EmployeeDto d,CancellationToken ct)=>StatusCode(201,await service.SaveEmployee(null,d,User.UserId(),ct));
 [HttpPut("{id:guid}"),Authorize(Roles="Admin")] public Task<object> Update(Guid id,EmployeeDto d,CancellationToken ct)=>service.SaveEmployee(id,d,User.UserId(),ct);
 [HttpPatch("{id:guid}/status"),Authorize(Roles="Admin")] public async Task<IActionResult> Status(Guid id,EmployeeStatusDto d,CancellationToken ct){await service.Status(id,d,User.UserId(),ct);return Ok(await service.EmployeeView(id,ct));}
 [HttpDelete("{id:guid}"),Authorize(Roles="Admin")] public async Task<IActionResult> Delete(Guid id,CancellationToken ct){await service.DeleteEmployee(id,User.UserId(),ct);return NoContent();}
}
[ApiController,Route("api/v1/departments"),Authorize(Roles="Admin")]
public sealed class DepartmentsController(CatalogService s,AttendanceDbContext db):ControllerBase
{
 [HttpGet] public Task<object> List(int page=1,int pageSize=100,CancellationToken ct=default)=>s.Departments(page,pageSize,ct);
 [HttpGet("{id:guid}")] public async Task<object> Detail(Guid id,CancellationToken ct)=>await db.Departments.Where(x=>x.Id==id).Select(x=>new{x.Id,x.Code,x.Name,rowVersion=x.RowVersion}).FirstOrDefaultAsync(ct)??throw CatalogService.Missing();
 [HttpPost] public async Task<IActionResult> Create(DepartmentDto d,CancellationToken ct)=>StatusCode(201,await s.SaveDepartment(null,d,User.UserId(),ct));
 [HttpPut("{id:guid}")] public Task<object> Update(Guid id,DepartmentDto d,CancellationToken ct)=>s.SaveDepartment(id,d,User.UserId(),ct);
 [HttpDelete("{id:guid}")] public async Task<IActionResult> Delete(Guid id,CancellationToken ct){await s.DeleteDepartment(id,User.UserId(),ct);return NoContent();}
}
[ApiController,Route("api/v1/shifts"),Authorize(Roles="Admin")]
public sealed class ShiftsController(CatalogService s,AttendanceDbContext db):ControllerBase
{
 [HttpGet] public Task<object> List(int page=1,int pageSize=100,CancellationToken ct=default)=>s.Shifts(page,pageSize,ct);
 [HttpGet("{id:guid}")] public async Task<object> Detail(Guid id,CancellationToken ct)=>await db.Shifts.Where(x=>x.Id==id).Select(x=>new{x.Id,x.Code,x.Name,x.StartLocalTime,x.EndLocalTime,x.EndsNextDay,x.LateGraceMinutes,x.IsActive,rowVersion=x.RowVersion}).FirstOrDefaultAsync(ct)??throw CatalogService.Missing();
 [HttpPost] public async Task<IActionResult> Create(ShiftDto d,CancellationToken ct)=>StatusCode(201,await s.SaveShift(null,d,User.UserId(),ct));
 [HttpPut("{id:guid}")] public Task<object> Update(Guid id,ShiftDto d,CancellationToken ct)=>s.SaveShift(id,d,User.UserId(),ct);
 [HttpDelete("{id:guid}")] public async Task<IActionResult> Delete(Guid id,CancellationToken ct){await s.DeleteShift(id,User.UserId(),ct);return NoContent();}
}
[ApiController,Route("api/v1/work-locations"),Authorize]
public sealed class LocationsController(CatalogService s,AttendanceDbContext db):ControllerBase
{
 [HttpGet,Authorize(Roles="Admin")] public Task<object> List(int page=1,int pageSize=100,CancellationToken ct=default)=>s.Locations(page,pageSize,ct);
 [HttpGet("{id:guid}"),Authorize(Roles="Admin")] public async Task<object> Detail(Guid id,CancellationToken ct)=>await db.WorkLocations.Where(x=>x.Id==id).Select(x=>new{x.Id,x.Name,x.Latitude,x.Longitude,x.RadiusMeters,x.MaxAccuracyMeters,x.PolicyVersion,x.IsActive,rowVersion=x.RowVersion}).FirstOrDefaultAsync(ct)??throw CatalogService.Missing();
 [HttpGet("me"),Authorize(Roles="Employee")] public async Task<object> Mine(CancellationToken ct)=>await db.EmployeeShifts.Where(x=>x.Employee.UserId==User.UserId()).Select(x=>new{x.WorkLocation.Id,x.WorkLocation.Name,x.WorkLocation.Latitude,x.WorkLocation.Longitude,x.WorkLocation.RadiusMeters,x.WorkLocation.MaxAccuracyMeters,x.WorkLocation.PolicyVersion}).Distinct().ToListAsync(ct);
 [HttpPost,Authorize(Roles="Admin")] public async Task<IActionResult> Create(LocationDto d,CancellationToken ct)=>StatusCode(201,await s.SaveLocation(null,d,User.UserId(),ct));
 [HttpPut("{id:guid}"),Authorize(Roles="Admin")] public Task<object> Update(Guid id,LocationDto d,CancellationToken ct)=>s.SaveLocation(id,d,User.UserId(),ct);
 [HttpDelete("{id:guid}"),Authorize(Roles="Admin")] public async Task<IActionResult> Delete(Guid id,CancellationToken ct){await s.DeleteLocation(id,User.UserId(),ct);return NoContent();}
 [HttpPost("{id:guid}/verify")] public async Task<object> Verify(Guid id,PositionDto d,CancellationToken ct)
 {
  if(!User.Admin()&&!await db.EmployeeShifts.AnyAsync(x=>x.Employee.UserId==User.UserId()&&x.WorkLocationId==id,ct))throw CatalogService.Missing();
  var x=await db.WorkLocations.FindAsync([id],ct)??throw CatalogService.Missing();Geo.Validate(d.Latitude,d.Longitude,d.AccuracyMeters);var distance=Geo.Distance(d.Latitude,d.Longitude,x.Latitude,x.Longitude);return new{distanceMeters=distance,accuracyAccepted=d.AccuracyMeters<=x.MaxAccuracyMeters,insideRadius=distance<=x.RadiusMeters,x.PolicyVersion};
 }
}
[ApiController,Route("api/v1/employee-shifts"),Authorize]
public sealed class AssignmentsController(CatalogService s,AttendanceDbContext db,AuditService audit,WorkScheduleService schedules):ControllerBase
{
 [HttpGet,Authorize(Roles="Admin")] public Task<object> All(Guid? employeeId,DateOnly? from,DateOnly? to,int page=1,int pageSize=100,CancellationToken ct=default)=>List(employeeId,false,from,to,page,pageSize,ct);
 [HttpGet("me"),Authorize(Roles="Employee")] public async Task<object> Mine(DateOnly? from,DateOnly? to,int page=1,int pageSize=100,CancellationToken ct=default){await schedules.Materialize(User.UserId(),ct);return await List(null,true,from,to,page,pageSize,ct);}
 private Task<object> List(Guid? employeeId,bool own,DateOnly? from,DateOnly? to,int page,int size,CancellationToken ct)
 {var range=Paging.Dates(from,to);var q=db.EmployeeShifts.Where(x=>x.StartUtc>=range.Start&&x.StartUtc<range.End);if(own)q=q.Where(x=>x.Employee.UserId==User.UserId());if(employeeId.HasValue)q=q.Where(x=>x.EmployeeId==employeeId);return Paging.Page(q.OrderByDescending(x=>x.StartUtc).Select(x=>new{x.Id,x.EmployeeId,employeeName=x.Employee.FullName,x.ShiftId,shiftName=x.Shift.Name,x.WorkLocationId,locationName=x.WorkLocation.Name,x.WorkDate,x.StartUtc,x.EndUtc,rowVersion=x.RowVersion}),page,size,ct);}
 [HttpPost,Authorize(Roles="Admin")] public async Task<IActionResult> Create(AssignmentDto d,CancellationToken ct)=>StatusCode(201,await s.Assign(null,d,User.UserId(),ct));
 [HttpPost("range"),Authorize(Roles="Admin")] public async Task<IActionResult> CreateRange(AssignmentRangeDto d,CancellationToken ct)=>StatusCode(201,await s.AssignRange(d,User.UserId(),ct));
 [HttpPut("{id:guid}"),Authorize(Roles="Admin")] public Task<object> Update(Guid id,AssignmentDto d,CancellationToken ct)=>s.Assign(id,d,User.UserId(),ct);
 [HttpDelete("{id:guid}"),Authorize(Roles="Admin")] public async Task<IActionResult> Delete(Guid id,CancellationToken ct)
 {var x=await db.EmployeeShifts.FindAsync([id],ct)??throw CatalogService.Missing();if(await db.AttendanceAttempts.AnyAsync(a=>a.EmployeeShiftId==id,ct))throw new ApiException(409,"AssignmentInUse","Ca đã có chấm công, không được xóa.");db.EmployeeShifts.Remove(x);audit.Add(User.UserId(),"EmployeeShift",id,"Deleted");await db.SaveChangesAsync(ct);return NoContent();}
}
[ApiController,Route("api/v1/users"),Authorize(Roles="Admin")]
public sealed class UsersController(AttendanceDbContext db,AuditService audit,EmployeeApprovalService approval):ControllerBase
{
 [HttpGet("pending")] public Task<object> Pending(int page=1,int pageSize=100,CancellationToken ct=default)=>Paging.Page(db.Users.Where(x=>x.Role=="Employee"&&x.ApprovalStatus=="Pending").OrderBy(x=>x.CreatedAtUtc).Select(x=>new{x.Id,x.FullName,username=x.UserName,x.Email,x.PhoneNumber,x.EmailConfirmed,x.CreatedAtUtc}),page,pageSize,ct);
 [HttpPost("{id:guid}/approve-registration")] public Task<object> ApproveRegistration(Guid id,ApproveRegistrationDto d,CancellationToken ct)=>approval.ApproveRegistration(id,d,User.UserId(),ct);
 [HttpPost("{id:guid}/approve")] public async Task<IActionResult> Approve(Guid id,ApproveUserDto d,CancellationToken ct)
 {await using var tx=await db.Database.BeginTransactionAsync(ct);var u=await db.Users.FindAsync([id],ct)??throw CatalogService.Missing();var e=await db.Employees.FindAsync([d.EmployeeId],ct)??throw CatalogService.Missing();if(u.Role!="Employee"||u.ApprovalStatus!="Pending"||!u.EmailConfirmed||!e.IsActive||e.UserId.HasValue||Secrets.Normalize(e.InvitationEmail)!=u.NormalizedEmail)throw new ApiException(409,"CannotApprove","Cần tài khoản chờ duyệt đã xác minh email và hồ sơ chưa liên kết, cùng email.");e.UserId=u.Id;u.ApprovalStatus="Approved";audit.Add(User.UserId(),"User",id,"Approved",new{employeeId=e.Id});await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);return Ok(new{u.Id,u.ApprovalStatus,employeeId=e.Id});}
 [HttpPost("{id:guid}/reject")] public async Task<IActionResult> Reject(Guid id,DecisionDto d,CancellationToken ct)
 {var u=await db.Users.FindAsync([id],ct)??throw CatalogService.Missing();if(u.Role!="Employee"||u.ApprovalStatus!="Pending")throw new ApiException(409,"CannotReject","Tài khoản không còn chờ duyệt.");u.ApprovalStatus="Rejected";u.IsActive=false;audit.Add(User.UserId(),"User",id,"Rejected",new{d.Reason});await db.SaveChangesAsync(ct);return Ok(new{u.Id,u.ApprovalStatus});}
}
