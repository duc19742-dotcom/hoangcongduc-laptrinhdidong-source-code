using Attendance.Api.Data;
using Attendance.Api.DTOs;
using Attendance.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
namespace Attendance.Api.Controllers;
[ApiController,Route("api/v1/profile"),Authorize,EnableRateLimiting("auth")]
public sealed class ProfileController(ProfileService service,AttendanceDbContext db):ControllerBase {
 [HttpPut]public Task<object> Save(ProfileDto d,CancellationToken ct)=>service.Save(User.UserId(),d,ct);
 [HttpPost("contact/start")]public Task<object> Start(ContactChangeDto d,CancellationToken ct)=>service.Start(User.UserId(),d,ct);
 [HttpPost("contact/confirm")]public Task<object> Confirm(ContactConfirmDto d,CancellationToken ct)=>service.Confirm(User.UserId(),d,ct);
 [HttpPost("name")]public Task<object> RequestName(LegalNameDto d,CancellationToken ct)=>service.RequestName(User.UserId(),d,ct);
 [HttpGet("name-requests")]public Task<object> Names(int page=1,int pageSize=100,CancellationToken ct=default){var q=db.Set<ProfileChange>().Where(x=>x.Kind=="LegalName");if(!User.Admin())q=q.Where(x=>x.UserId==User.UserId());return Paging.Page(q.OrderByDescending(x=>x.CreatedAtUtc).Select(x=>new{x.Id,currentName=x.User.FullName,requestedName=x.Value,x.Status,x.DecisionReason,x.CreatedAtUtc}),page,pageSize,ct);}
 [HttpPost("name-requests/{id:guid}/approve"),Authorize(Roles="Admin")]public Task<object> Approve(Guid id,DecisionDto d,CancellationToken ct)=>service.ReviewName(User.UserId(),id,true,d.Reason,ct);
 [HttpPost("name-requests/{id:guid}/reject"),Authorize(Roles="Admin")]public Task<object> Reject(Guid id,DecisionDto d,CancellationToken ct)=>service.ReviewName(User.UserId(),id,false,d.Reason,ct);
}
