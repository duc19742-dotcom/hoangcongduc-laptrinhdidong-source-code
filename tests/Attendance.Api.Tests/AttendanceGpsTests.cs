using System.Text.Json;
using Attendance.Api.Data;
using Attendance.Api.DTOs;
using Attendance.Api.Services;
using Attendance.Api.Middleware;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
namespace Attendance.Api.Tests;
public sealed partial class IntegrationTests
{
 [Fact] public async Task NewGpsSubmission_RejectsStaleAndFutureFixes_ButAcceptsFreshFix()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var service=scope.ServiceProvider.GetRequiredService<AttendanceService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
  var token=Json(await scope.ServiceProvider.GetRequiredService<SiteQrService>().Create(seed.Assignment.WorkLocationId,seed.Admin.Id,default)).GetProperty("qrToken").GetString()!;
  var dto=new AttendanceSubmitDto(seed.Assignment.Id,token,10.7769,106.7009,10,DateTimeOffset.UtcNow.AddMinutes(-5));
  foreach(var captured in new[]{DateTimeOffset.UtcNow.AddMinutes(-5),DateTimeOffset.UtcNow.AddMinutes(5)})
   Assert.Equal("StaleGps",(await Assert.ThrowsAsync<ApiException>(()=>service.Submit(dto with{CapturedAtUtc=captured},"CheckIn",Guid.NewGuid(),seed.User.Id,default))).Code);
  Assert.False(await db.AttendanceAttempts.AnyAsync(x=>x.EmployeeShiftId==seed.Assignment.Id));
  var fresh=dto with{CapturedAtUtc=DateTimeOffset.UtcNow};var key=Guid.NewGuid();
  Assert.Equal("Accepted",Json(await service.Submit(fresh,"CheckIn",key,seed.User.Id,default)).GetProperty("status").GetString());
  Assert.Equal("Accepted",Json(await service.Submit(fresh,"CheckIn",key,seed.User.Id,default)).GetProperty("status").GetString());
  Assert.Single(await db.AttendanceRecords.Where(x=>x.EmployeeShiftId==seed.Assignment.Id).ToListAsync());
 }
 [Fact] public async Task ConfirmedRetry_IsReturnedBeforeGpsFreshnessCheck()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var service=scope.ServiceProvider.GetRequiredService<AttendanceService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
  var qr=Json(await scope.ServiceProvider.GetRequiredService<SiteQrService>().Create(seed.Assignment.WorkLocationId,seed.Admin.Id,default)).GetProperty("qrToken").GetString()!;
  var dto=new AttendanceSubmitDto(seed.Assignment.Id,qr,10.7769,106.7009,10,DateTimeOffset.UtcNow);var key=Guid.NewGuid();
  await service.Submit(dto,"CheckIn",key,seed.User.Id,default);
  // Represent a previously confirmed request whose acquisition time has aged.
  var aged=dto with{CapturedAtUtc=DateTimeOffset.UtcNow.AddMinutes(-5)};var attempt=await db.AttendanceAttempts.SingleAsync(x=>x.EmployeeShiftId==seed.Assignment.Id);
  attempt.PayloadHash=Secrets.Hash("CheckIn"+JsonSerializer.Serialize(aged));await db.SaveChangesAsync();
  Assert.Equal(attempt.Id,Json(await service.Submit(aged,"CheckIn",key,seed.User.Id,default)).GetProperty("attemptId").GetGuid());
  Assert.Single(await db.AttendanceRecords.Where(x=>x.EmployeeShiftId==seed.Assignment.Id).ToListAsync());
 }
 [Fact] public async Task GpsUncertainty_DoesNotExpandTheCompanyRadius()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var service=scope.ServiceProvider.GetRequiredService<AttendanceService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
  var qr=Json(await scope.ServiceProvider.GetRequiredService<SiteQrService>().Create(seed.Assignment.WorkLocationId,seed.Admin.Id,default)).GetProperty("qrToken").GetString()!;
  var result=Json(await service.Submit(new(seed.Assignment.Id,qr,10.7789,106.7009,100,DateTimeOffset.UtcNow),"CheckIn",Guid.NewGuid(),seed.User.Id,default));
  Assert.Equal("NeedsReview",result.GetProperty("status").GetString());Assert.Contains(result.GetProperty("reasonCodes").EnumerateArray(),x=>x.GetString()=="OutsideGeofence");Assert.Contains(result.GetProperty("reasonCodes").EnumerateArray(),x=>x.GetString()=="LowGpsAccuracy");
  Assert.False(await db.AttendanceRecords.AnyAsync(x=>x.EmployeeShiftId==seed.Assignment.Id));
 }
 [Fact] public void GeodesicDistance_UsesMeters_AndHandlesDateLine()
 {
  Assert.InRange(Geo.Distance(0,0,0,1),111194,111196);Assert.Equal(0,Geo.Distance(10,106,10,106));
  Assert.InRange(Geo.Distance(0,179.999,0,-179.999),222,223);
  Assert.True(double.IsFinite(Geo.Distance(90,0,-90,180)));
 }
}
