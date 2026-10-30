using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text.Json;
using Attendance.Api.Controllers;
using Attendance.Api.Data;
using Attendance.Api.DTOs;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Attendance.Api.Services;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Attendance.Api.Tests;

// These tests use an isolated real SQL Server LocalDB database. Only message transport
// is captured in memory. Passing tests is NOT evidence of real SMS/email delivery.
public sealed class CapturingSender : IMessageSender
{
 public string LastCode {get;private set;}="";
 public readonly Dictionary<string,string> Codes=new();
 public bool Reject {get;set;}
 public Task<DeliveryResult>SendAsync(string channel,string destination,string code,CancellationToken ct)
 {LastCode=code;Codes[destination]=code;return Task.FromResult(Reject?new DeliveryResult(false,"Failed",ErrorCode:"TestTransportRejected"):new DeliveryResult(true,"ProviderAccepted","test-only"));}
}
public sealed class ApiFixture : IAsyncLifetime
{
 public readonly CapturingSender Sender=new();
 public readonly string DatabaseName="DucAttendance_Test_"+Guid.NewGuid().ToString("N");
 public WebApplicationFactory<Program>Factory {get;private set;}=null!;
 public async Task InitializeAsync()
 {
  var connection=$"Server=(localdb)\\MSSQLLocalDB;Database={DatabaseName};Integrated Security=True;Encrypt=True;TrustServerCertificate=True";
  Factory=new WebApplicationFactory<Program>().WithWebHostBuilder(b=>b.UseEnvironment("Development").ConfigureServices(services=> {
   services.RemoveAll<DbContextOptions<AttendanceDbContext>>();services.RemoveAll<AttendanceDbContext>();
   services.AddDbContext<AttendanceDbContext>(o=>o.UseSqlServer(connection));
   services.RemoveAll<IMessageSender>();services.AddSingleton<IMessageSender>(Sender);
  }));
  using var scope=Factory.Services.CreateScope();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
  Assert.Equal(DatabaseName,db.Database.GetDbConnection().Database);
  await db.Database.MigrateAsync();
 }
 public async Task DisposeAsync()
 {
  using(var scope=Factory.Services.CreateScope()) {var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();if(db.Database.GetDbConnection().Database==DatabaseName&&DatabaseName.StartsWith("DucAttendance_Test_"))await db.Database.EnsureDeletedAsync();}
  await Factory.DisposeAsync();
 }
}
public sealed partial class IntegrationTests(ApiFixture fixture) : IClassFixture<ApiFixture>
{
 private const string Password="AutomatedTestOnly!518";
 private static JsonElement Json(object value)=>JsonSerializer.SerializeToElement(value);
 private static FlowDto Flow(object value){var j=Json(value);return new(j.GetProperty("flowId").GetGuid(),j.GetProperty("flowToken").GetString()!);}
 private async Task<(FlowDto Flow,Guid Challenge,string Code)>EmailCode(AuthService auth,object flow)
 {var f=Flow(flow);var sent=Json(await auth.Send(new(f.FlowId,f.FlowToken,"Email"),default));return(f,sent.GetProperty("challengeId").GetGuid(),fixture.Sender.LastCode);}
 private static ClaimsPrincipal Principal(Guid id,string role)=>new(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier,id.ToString()),new Claim(ClaimTypes.Role,role)],"tests"));
 private static T Controller<T>(T controller,Guid user,string role)where T:ControllerBase {controller.ControllerContext=new ControllerContext{HttpContext=new DefaultHttpContext{User=Principal(user,role)}};return controller;}

 [Fact]public async Task Registration_EmailOtp_ConsumesOnce_AndNeverGrantsAdmin()
 {
  using var scope=fixture.Factory.Services.CreateScope();var auth=scope.ServiceProvider.GetRequiredService<AuthService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
  var suffix=Guid.NewGuid().ToString("N")[..12];var flow=await auth.Register(new("Test registration","u"+suffix,suffix+"@example.invalid","+84901234567",Password,Password),default);
  var code=await EmailCode(auth,flow);var verify=new VerifyOtpDto(code.Flow.FlowId,code.Flow.FlowToken,code.Challenge,code.Code);
  await auth.Verify(verify,"VerifyEmail",default);
  var user=await db.Users.SingleAsync(x=>x.NormalizedUserName==("u"+suffix).ToUpperInvariant());Assert.Equal("Employee",user.Role);Assert.Equal("Pending",user.ApprovalStatus);Assert.True(user.EmailConfirmed);Assert.NotEqual(Password,user.PasswordHash);
  var challenge=await db.OtpChallenges.FindAsync(code.Challenge);Assert.NotNull(challenge);Assert.NotEqual(code.Code,challenge.CodeMac);Assert.NotNull(challenge.ConsumedAtUtc);
  Assert.Equal(410,(await Assert.ThrowsAsync<ApiException>(()=>auth.Verify(verify,"VerifyEmail",default))).Status);
 }
 [Fact]public async Task WrongOtp_IsBounded_AndResendCooldownSurvivesNewServiceScope()
 {
  using var scope=fixture.Factory.Services.CreateScope();var auth=scope.ServiceProvider.GetRequiredService<AuthService>();var suffix=Guid.NewGuid().ToString("N")[..12];
  var code=await EmailCode(auth,await auth.Register(new("Test wrong OTP","u"+suffix,suffix+"@example.invalid","+84901234567",Password,Password),default));
  var bad=code.Code=="000000"?"111111":"000000";var verify=new VerifyOtpDto(code.Flow.FlowId,code.Flow.FlowToken,code.Challenge,bad);
  for(var i=0;i<5;i++)Assert.Equal(400,(await Assert.ThrowsAsync<ApiException>(()=>auth.Verify(verify,"VerifyEmail",default))).Status);
  Assert.Equal(429,(await Assert.ThrowsAsync<ApiException>(()=>auth.Verify(verify,"VerifyEmail",default))).Status);
  using var second=fixture.Factory.Services.CreateScope();var fresh=second.ServiceProvider.GetRequiredService<AuthService>();
  Assert.Equal(429,(await Assert.ThrowsAsync<ApiException>(()=>fresh.Send(new(code.Flow.FlowId,code.Flow.FlowToken,"Email"),default))).Status);
 }
 [Fact]public async Task ProviderFailure_IsNotReportedAsSent_AndCannotBeVerified()
 {
  using var scope=fixture.Factory.Services.CreateScope();var auth=scope.ServiceProvider.GetRequiredService<AuthService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();var suffix=Guid.NewGuid().ToString("N")[..12];
  var flow=Flow(await auth.Register(new("Test provider failure","u"+suffix,suffix+"@example.invalid","+84901234567",Password,Password),default));
  fixture.Sender.Reject=true;try{Assert.Equal(503,(await Assert.ThrowsAsync<ApiException>(()=>auth.Send(new(flow.FlowId,flow.FlowToken,"Email"),default))).Status);}finally{fixture.Sender.Reject=false;}
  var challenge=await db.OtpChallenges.SingleAsync(x=>x.FlowId==flow.FlowId);Assert.Equal("Failed",challenge.DeliveryStatus);
  Assert.Equal(400,(await Assert.ThrowsAsync<ApiException>(()=>auth.Verify(new(flow.FlowId,flow.FlowToken,challenge.Id,fixture.Sender.LastCode),"VerifyEmail",default))).Status);
 }
 [Fact]public async Task ExpiredOtp_IsRejectedByServerTime()
 {
  using var scope=fixture.Factory.Services.CreateScope();var auth=scope.ServiceProvider.GetRequiredService<AuthService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();var suffix=Guid.NewGuid().ToString("N")[..12];
  var code=await EmailCode(auth,await auth.Register(new("Test expiry","u"+suffix,suffix+"@example.invalid","+84901234567",Password,Password),default));
  var challenge=await db.OtpChallenges.FindAsync(code.Challenge);challenge!.CreatedAtUtc=DateTimeOffset.UtcNow.AddMinutes(-10);challenge.ExpiresAtUtc=DateTimeOffset.UtcNow.AddMinutes(-1);await db.SaveChangesAsync();
  Assert.Equal(410,(await Assert.ThrowsAsync<ApiException>(()=>auth.Verify(new(code.Flow.FlowId,code.Flow.FlowToken,code.Challenge,code.Code),"VerifyEmail",default))).Status);
 }
 [Fact]public async Task SmsFailuresDoNotExhaustTheEmailChannelQuota()
 {
  using var scope=fixture.Factory.Services.CreateScope();var auth=scope.ServiceProvider.GetRequiredService<AuthService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();var suffix=Guid.NewGuid().ToString("N")[..12];
  var flow=Flow(await auth.Register(new("Test separate quotas","u"+suffix,suffix+"@example.invalid","+84901234567",Password,Password),default));
  var user=await db.Users.SingleAsync(x=>x.NormalizedUserName==("u"+suffix).ToUpperInvariant());
  for(var i=0;i<10;i++){
   var oldFlow=new AuthFlow{UserId=user.Id,TokenHash=Secrets.Hash(Secrets.NewToken()),Purpose="VerifyPhone",ExpiresAtUtc=DateTimeOffset.UtcNow.AddMinutes(5),SendCount=1};db.AuthFlows.Add(oldFlow);
   db.OtpChallenges.Add(new(){UserId=user.Id,FlowId=oldFlow.Id,Purpose="VerifyPhone",Channel="Sms",CodeMac=Secrets.Hash(Secrets.NewToken()),DestinationDigest=Secrets.Hash(user.PhoneNumber),ExpiresAtUtc=DateTimeOffset.UtcNow.AddMinutes(5),DeliveryStatus="Failed"});
  }
  await db.SaveChangesAsync();
  try{var sent=Json(await auth.Send(new(flow.FlowId,flow.FlowToken,"Email"),default));Assert.Equal("ProviderAccepted",sent.GetProperty("status").GetString());}
  finally{await db.OtpChallenges.Where(x=>x.UserId==user.Id&&x.Channel=="Sms").ExecuteDeleteAsync();}
 }
 private static async Task<(AppUser Admin,AppUser User,Employee Employee,EmployeeShift Assignment)>Seed(IServiceProvider services)
 {
  var db=services.GetRequiredService<AttendanceDbContext>();var hasher=services.GetRequiredService<IPasswordHasher<AppUser>>();var id=Guid.NewGuid().ToString("N")[..12];
  AppUser User(string prefix,string role){var u=new AppUser{FullName="Automated test "+prefix,UserName=prefix+id,NormalizedUserName=(prefix+id).ToUpperInvariant(),Email=prefix+id+"@example.invalid",NormalizedEmail=(prefix+id+"@example.invalid").ToUpperInvariant(),PhoneNumber="+84901234567",Role=role,ApprovalStatus="Approved",EmailConfirmed=true};u.PasswordHash=hasher.HashPassword(u,Password);return u;}
  var admin=User("admin","Admin");var user=User("employee","Employee");var dep=new Department{Code="D"+id,Name="Test only"};var emp=new Employee{EmployeeCode="E"+id,FullName=user.FullName,DepartmentId=dep.Id,UserId=user.Id,InvitationEmail=user.Email,InvitationPhone=user.PhoneNumber,HireDate=DateOnly.FromDateTime(DateTime.UtcNow)};
  var shift=new Shift{Code="S"+id,Name="Test shift",StartLocalTime=new(8,0),EndLocalTime=new(17,0)};var location=new WorkLocation{Name="Test coordinates only",Latitude=10.7769,Longitude=106.7009,RadiusMeters=150,MaxAccuracyMeters=50};var now=DateTimeOffset.UtcNow;
  var assignment=new EmployeeShift{EmployeeId=emp.Id,ShiftId=shift.Id,WorkLocationId=location.Id,WorkDate=DateOnly.FromDateTime(now.AddHours(7).DateTime),StartUtc=now.AddHours(-1),EndUtc=now.AddHours(6),GraceMinutesSnapshot=5};
  db.AddRange(admin,user,dep,emp,shift,location,assignment);await db.SaveChangesAsync();return(admin,user,emp,assignment);
 }
 [Fact]public async Task SiteQrAttendance_UsesServerTime_RejectsDuplicates_AndPreservesReview()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var s=scope.ServiceProvider.GetRequiredService<AttendanceService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
  var sites=scope.ServiceProvider.GetRequiredService<SiteQrService>();var qr=Json(await sites.Create(seed.Assignment.WorkLocationId,seed.Admin.Id,default)).GetProperty("qrToken").GetString();
  var result=Json(await s.Submit(new(seed.Assignment.Id,qr,10.7769,106.7009,10),"CheckIn",Guid.NewGuid(),seed.User.Id,default));
  Assert.Equal("Accepted",result.GetProperty("status").GetString());Assert.Equal("Late",result.GetProperty("punctuality").GetString());
  var error=await Assert.ThrowsAsync<ApiException>(()=>s.Submit(new(seed.Assignment.Id,qr,10.7769,106.7009,10),"CheckIn",Guid.NewGuid(),seed.User.Id,default));Assert.Equal(409,error.Status);
  var review=Json(await s.Submit(new(seed.Assignment.Id,qr,11,107,10),"CheckOut",Guid.NewGuid(),seed.User.Id,default));Assert.Equal("NeedsReview",review.GetProperty("status").GetString());Assert.True(review.GetProperty("canCreateRequest").GetBoolean());
  Assert.Single(await db.AttendanceRecords.Where(x=>x.EmployeeShiftId==seed.Assignment.Id).ToListAsync());
 }
 [Fact]public async Task RememberedDevice_RotatesToken_AndRevokePreventsLogin()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var s=scope.ServiceProvider.GetRequiredService<RememberedDeviceService>();
  var saved=Json(await s.Enroll(seed.User.Id,default));var old=saved.GetProperty("token").GetString()!;
  var resumed=Json(await s.Resume(old,default));Assert.Equal(seed.User.Id.ToString(),resumed.GetProperty("session").GetProperty("user").GetProperty("Id").GetString());
  await Assert.ThrowsAsync<ApiException>(()=>s.Resume(old,default));var next=resumed.GetProperty("deviceToken").GetString()!;
  await s.Revoke(next,default);await Assert.ThrowsAsync<ApiException>(()=>s.Resume(next,default));
 }
 [Fact]public async Task RememberedDevice_ExpiredAndInactiveUsersCannotResume()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var s=scope.ServiceProvider.GetRequiredService<RememberedDeviceService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
  var token=Json(await s.Enroll(seed.User.Id,default)).GetProperty("token").GetString()!;
  seed.User.IsActive=false;await db.SaveChangesAsync();Assert.Equal(403,(await Assert.ThrowsAsync<ApiException>(()=>s.Resume(token,default))).Status);
  seed.User.IsActive=true;var device=await db.Set<RememberedDevice>().SingleAsync(x=>x.UserId==seed.User.Id);device.ExpiresAtUtc=DateTimeOffset.UtcNow.AddSeconds(-1);await db.SaveChangesAsync();Assert.Equal(401,(await Assert.ThrowsAsync<ApiException>(()=>s.Resume(token,default))).Status);
 }
 [Fact]public async Task SiteQr_RequiresValidLocationTokenAndRejectsExpiredCode()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var sites=scope.ServiceProvider.GetRequiredService<SiteQrService>();var attendance=scope.ServiceProvider.GetRequiredService<AttendanceService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
  Assert.Equal("QrRequired",(await Assert.ThrowsAsync<ApiException>(()=>attendance.Submit(new(seed.Assignment.Id,null,10.7769,106.7009,10),"CheckIn",Guid.NewGuid(),seed.User.Id,default))).Code);
  var qr=Json(await sites.Create(seed.Assignment.WorkLocationId,seed.Admin.Id,default));var token=qr.GetProperty("qrToken").GetString()!;
  var session=await db.Set<SiteQrSession>().SingleAsync(x=>x.TokenHash==Secrets.Hash(token));session.ExpiresAtUtc=DateTimeOffset.UtcNow.AddSeconds(-1);await db.SaveChangesAsync();
  Assert.Equal("QrExpired",(await Assert.ThrowsAsync<ApiException>(()=>attendance.Submit(new(seed.Assignment.Id,token,10.7769,106.7009,10),"CheckIn",Guid.NewGuid(),seed.User.Id,default))).Code);
  Assert.False(await db.AttendanceRecords.AnyAsync(x=>x.EmployeeShiftId==seed.Assignment.Id));
 }
 [Fact]public async Task DisplayCredential_IsScopedToOneSite_AndExpires()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var sites=scope.ServiceProvider.GetRequiredService<SiteQrService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
  var token=Json(await sites.BeginDisplay(seed.Assignment.WorkLocationId,seed.Admin.Id,default)).GetProperty("displayToken").GetString()!;
  var qr=Json(await sites.FromDisplay(token,default));var hash=Secrets.Hash(qr.GetProperty("qrToken").GetString()!);Assert.Equal(seed.Assignment.WorkLocationId,(await db.Set<SiteQrSession>().SingleAsync(x=>x.TokenHash==hash)).WorkLocationId);
  var display=await db.Set<SiteDisplay>().SingleAsync(x=>x.TokenHash==Secrets.Hash(token));display.ExpiresAtUtc=DateTimeOffset.UtcNow.AddSeconds(-1);await db.SaveChangesAsync();Assert.Equal(401,(await Assert.ThrowsAsync<ApiException>(()=>sites.FromDisplay(token,default))).Status);
 }
 [Fact]public async Task RecurringSchedule_IndividualOverridesDefault_AndDailyOverrideIsPreserved()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var schedules=scope.ServiceProvider.GetRequiredService<WorkScheduleService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();var day=seed.Assignment.WorkDate;
  db.EmployeeShifts.Remove(seed.Assignment);await db.SaveChangesAsync();
  var other=new Shift{Code="R"+Guid.NewGuid().ToString("N"),Name="Individual test schedule",StartLocalTime=new(9,0),EndLocalTime=new(18,0),LateGraceMinutes=7};db.Shifts.Add(other);await db.SaveChangesAsync();
  await schedules.Create(new(null,seed.Assignment.ShiftId,seed.Assignment.WorkLocationId,127,day,day),seed.Admin.Id,default);
  await schedules.Create(new(seed.Employee.Id,other.Id,seed.Assignment.WorkLocationId,127,day,day),seed.Admin.Id,default);
  await schedules.Materialize(seed.User.Id,default);var assigned=await db.EmployeeShifts.SingleAsync(x=>x.EmployeeId==seed.Employee.Id&&x.WorkDate==day);Assert.Equal(other.Id,assigned.ShiftId);Assert.Equal(7,assigned.GraceMinutesSnapshot);
  await schedules.Materialize(seed.User.Id,default);Assert.Single(await db.EmployeeShifts.Where(x=>x.EmployeeId==seed.Employee.Id&&x.WorkDate==day).ToListAsync());
  other.StartLocalTime=new(10,0);other.LateGraceMinutes=9;await db.SaveChangesAsync();await schedules.Materialize(seed.User.Id,default);Assert.Equal(9,assigned.GraceMinutesSnapshot);Assert.Equal(Geo.Utc(day,new(10,0)),assigned.StartUtc);
  assigned.SourceScheduleId=null;assigned.ShiftId=seed.Assignment.ShiftId;await db.SaveChangesAsync();await schedules.Materialize(seed.User.Id,default);Assert.Equal(seed.Assignment.ShiftId,assigned.ShiftId);
 }
 [Fact]public async Task ScheduleRange_CreatesDailySnapshots_AndRejectsOverlaps()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var s=scope.ServiceProvider.GetRequiredService<CatalogService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();var from=seed.Assignment.WorkDate.AddDays(2);
  var dto=new AssignmentRangeDto(seed.Employee.Id,seed.Assignment.ShiftId,seed.Assignment.WorkLocationId,from,from.AddDays(2));
  var result=Json(await s.AssignRange(dto,seed.Admin.Id,default));Assert.Equal(3,result.GetProperty("created").GetInt32());await Assert.ThrowsAsync<ApiException>(()=>s.AssignRange(dto,seed.Admin.Id,default));
  Assert.Equal(4,await db.EmployeeShifts.CountAsync(x=>x.EmployeeId==seed.Employee.Id));
 }
 [Fact]public async Task MissingCheckout_AdminCorrectionRequiresOwnRequest_AndDoesNotInventGps()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();var s=scope.ServiceProvider.GetRequiredService<AttendanceService>();var audit=scope.ServiceProvider.GetRequiredService<AuditService>();
  var qr=Json(await scope.ServiceProvider.GetRequiredService<SiteQrService>().Create(seed.Assignment.WorkLocationId,seed.Admin.Id,default)).GetProperty("qrToken").GetString();
  await s.Submit(new(seed.Assignment.Id,qr,10.7769,106.7009,10),"CheckIn",Guid.NewGuid(),seed.User.Id,default);
  var support=new AttendanceSupport{UserId=seed.User.Id,Kind="MissingCheckOut",Reason="Test missing checkout request"};db.Add(support);await db.SaveChangesAsync();
  var controller=Controller(new AttendanceSupportController(db,audit),seed.Admin.Id,"Admin");
  await controller.CorrectCheckout(support.Id,new(seed.Assignment.Id,DateTimeOffset.UtcNow,"Test evidence accepted by admin"),default);
  var checkout=await db.AttendanceRecords.SingleAsync(x=>x.EmployeeShiftId==seed.Assignment.Id&&x.Action=="CheckOut");Assert.Null(checkout.AttemptId);Assert.Equal("AdminCorrection",checkout.Source);Assert.Equal("Resolved",support.Status);
  await Assert.ThrowsAsync<ApiException>(()=>controller.CorrectCheckout(support.Id,new(seed.Assignment.Id,DateTimeOffset.UtcNow,"Duplicate correction rejected"),default));
  var history=Json(await s.History(seed.Employee.Id,seed.Assignment.WorkDate,seed.Assignment.WorkDate,1,100,default));Assert.Equal(2,history.GetProperty("items").GetArrayLength());
 }
 [Fact]public async Task Attendance_IsIdempotent_AndRejectsDuplicateFromANewQr()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var service=scope.ServiceProvider.GetRequiredService<AttendanceService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
  var qr=Json(await service.CreateQr(new(seed.Assignment.ShiftId,seed.Assignment.WorkLocationId,seed.Assignment.WorkDate,"CheckIn"),seed.Admin.Id,default));var token=qr.GetProperty("qrToken").GetString()!;
  var dto=new AttendanceSubmitDto(seed.Assignment.Id,token,10.7769,106.7009,10);var key=Guid.NewGuid();
  var first=Json(await service.Submit(dto,"CheckIn",key,seed.User.Id,default));var again=Json(await service.Submit(dto,"CheckIn",key,seed.User.Id,default));Assert.Equal(first.GetProperty("attemptId").GetGuid(),again.GetProperty("attemptId").GetGuid());
  Assert.Equal(1,await db.AttendanceRecords.CountAsync(x=>x.EmployeeShiftId==seed.Assignment.Id));
  Assert.Equal(409,(await Assert.ThrowsAsync<ApiException>(()=>service.Submit(dto with{Latitude=10.8},"CheckIn",key,seed.User.Id,default))).Status);
  var secondQr=Json(await service.CreateQr(new(seed.Assignment.ShiftId,seed.Assignment.WorkLocationId,seed.Assignment.WorkDate,"CheckIn"),seed.Admin.Id,default));
  Assert.Equal(409,(await Assert.ThrowsAsync<ApiException>(()=>service.Submit(dto with{QrToken=secondQr.GetProperty("qrToken").GetString()!},"CheckIn",Guid.NewGuid(),seed.User.Id,default))).Status);
 }
 [Fact]public async Task GpsException_DoesNotCreateWorkUntilApproval_AndKeepsOriginalPolicy()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var service=scope.ServiceProvider.GetRequiredService<AttendanceService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();var audit=scope.ServiceProvider.GetRequiredService<AuditService>();
  var qr=Json(await service.CreateQr(new(seed.Assignment.ShiftId,seed.Assignment.WorkLocationId,seed.Assignment.WorkDate,"CheckIn"),seed.Admin.Id,default));
  var submitted=Json(await service.Submit(new(seed.Assignment.Id,qr.GetProperty("qrToken").GetString()!,11,107,80),"CheckIn",Guid.NewGuid(),seed.User.Id,default));var attemptId=submitted.GetProperty("attemptId").GetGuid();
  Assert.Equal("NeedsReview",submitted.GetProperty("status").GetString());Assert.False(await db.AttendanceRecords.AnyAsync(x=>x.EmployeeShiftId==seed.Assignment.Id));
  Assert.Equal(11,submitted.GetProperty("position").GetProperty("latitude").GetDouble());Assert.Equal(107,submitted.GetProperty("position").GetProperty("longitude").GetDouble());
  var employeeController=Controller(new RequestsController(db,service,audit),seed.User.Id,"Employee");await employeeController.Create(new(attemptId,"GPS không đủ chính xác trong ca thử nghiệm."),default);
  var request=await db.AttendanceRequests.SingleAsync(x=>x.AttemptId==attemptId);var original=(await db.AttendanceAttempts.FindAsync(attemptId))!.PolicySnapshotJson;
  var location=await db.WorkLocations.FindAsync(seed.Assignment.WorkLocationId);location!.RadiusMeters=20;location.PolicyVersion++;await db.SaveChangesAsync();
  var adminController=Controller(new RequestsController(db,service,audit),seed.Admin.Id,"Admin");await adminController.Approve(request.Id,new("Đã đối chiếu bằng chứng thử nghiệm.",Convert.ToBase64String(request.RowVersion)),default);
  var record=await db.AttendanceRecords.SingleAsync(x=>x.AttemptId==attemptId);Assert.Equal("AdminApproved",record.Source);Assert.Equal((await db.AttendanceAttempts.FindAsync(attemptId))!.ReceivedAtUtc,record.EffectiveAtUtc);Assert.Equal(original,(await db.AttendanceAttempts.FindAsync(attemptId))!.PolicySnapshotJson);Assert.Equal(2,await db.AttendanceRequestEvents.CountAsync(x=>x.RequestId==request.Id));
 }
 [Fact]public async Task CheckoutRequiresConfirmedCheckin()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var service=scope.ServiceProvider.GetRequiredService<AttendanceService>();var qr=Json(await service.CreateQr(new(seed.Assignment.ShiftId,seed.Assignment.WorkLocationId,seed.Assignment.WorkDate,"CheckOut"),seed.Admin.Id,default));
  var error=await Assert.ThrowsAsync<ApiException>(()=>service.Submit(new(seed.Assignment.Id,qr.GetProperty("qrToken").GetString()!,10.7769,106.7009,10),"CheckOut",Guid.NewGuid(),seed.User.Id,default));Assert.Equal("CheckInRequired",error.Code);
 }
 [Fact]public async Task InvalidAndExpiredQrNeverCreateAttendance()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var service=scope.ServiceProvider.GetRequiredService<AttendanceService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
  var dto=new AttendanceSubmitDto(seed.Assignment.Id,"unissued-token",10.7769,106.7009,10);
  Assert.Equal("InvalidQr",(await Assert.ThrowsAsync<ApiException>(()=>service.Submit(dto,"CheckIn",Guid.NewGuid(),seed.User.Id,default))).Code);
  var qr=Json(await service.CreateQr(new(seed.Assignment.ShiftId,seed.Assignment.WorkLocationId,seed.Assignment.WorkDate,"CheckIn"),seed.Admin.Id,default));
  var row=await db.QrSessions.FindAsync(qr.GetProperty("id").GetGuid());row!.CreatedAtUtc=DateTimeOffset.UtcNow.AddMinutes(-3);row.ExpiresAtUtc=DateTimeOffset.UtcNow.AddMinutes(-2);await db.SaveChangesAsync();
  Assert.Equal("QrExpired",(await Assert.ThrowsAsync<ApiException>(()=>service.Submit(dto with{QrToken=qr.GetProperty("qrToken").GetString()!},"CheckIn",Guid.NewGuid(),seed.User.Id,default))).Code);
  Assert.False(await db.AttendanceRecords.AnyAsync(x=>x.EmployeeShiftId==seed.Assignment.Id));
 }
 [Fact]public async Task NeedsReviewQrCannotBeReplayedToGetAnotherAttempt()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var service=scope.ServiceProvider.GetRequiredService<AttendanceService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
  var qr=Json(await service.CreateQr(new(seed.Assignment.ShiftId,seed.Assignment.WorkLocationId,seed.Assignment.WorkDate,"CheckIn"),seed.Admin.Id,default));var dto=new AttendanceSubmitDto(seed.Assignment.Id,qr.GetProperty("qrToken").GetString()!,11,107,80);
  Assert.Equal("NeedsReview",Json(await service.Submit(dto,"CheckIn",Guid.NewGuid(),seed.User.Id,default)).GetProperty("status").GetString());
  Assert.Equal("QrAlreadyUsed",(await Assert.ThrowsAsync<ApiException>(()=>service.Submit(dto,"CheckIn",Guid.NewGuid(),seed.User.Id,default))).Code);
  Assert.Equal(1,await db.AttendanceAttempts.CountAsync(x=>x.EmployeeShiftId==seed.Assignment.Id));
 }
 [Fact]public async Task ValidCheckoutPersistsSecondRecordAndStatistics()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var service=scope.ServiceProvider.GetRequiredService<AttendanceService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
  foreach(var action in new[]{"CheckIn","CheckOut"}){
   var qr=Json(await service.CreateQr(new(seed.Assignment.ShiftId,seed.Assignment.WorkLocationId,seed.Assignment.WorkDate,action),seed.Admin.Id,default));
   Assert.Equal("Accepted",Json(await service.Submit(new(seed.Assignment.Id,qr.GetProperty("qrToken").GetString()!,10.7769,106.7009,10),action,Guid.NewGuid(),seed.User.Id,default)).GetProperty("status").GetString());
  }
  var rows=await db.AttendanceRecords.Where(x=>x.EmployeeShiftId==seed.Assignment.Id).OrderBy(x=>x.EffectiveAtUtc).ToListAsync();Assert.Equal(2,rows.Count);Assert.True(rows[1].EffectiveAtUtc>=rows[0].EffectiveAtUtc);
  var stats=Json(await service.Statistics(seed.Assignment.WorkDate,seed.Assignment.WorkDate,seed.Employee.DepartmentId,default));Assert.Equal(1,stats.GetProperty("checkIns").GetInt32());Assert.Equal(1,stats.GetProperty("checkOuts").GetInt32());Assert.Equal(0,stats.GetProperty("openShifts").GetInt32());
 }
 [Fact]public async Task SmsLoginRequiresPhoneVerificationAndConsumesTheBackendChallenge()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var auth=scope.ServiceProvider.GetRequiredService<AuthService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
  var login=Flow(await auth.Login(new(seed.User.UserName,Password),default));
  Assert.Equal("PhoneNotVerified",(await Assert.ThrowsAsync<ApiException>(()=>auth.Send(new(login.FlowId,login.FlowToken,"Sms"),default))).Code);
  var phone=Flow(await auth.StartPhone(login,default));var sent=Json(await auth.Send(new(phone.FlowId,phone.FlowToken,"Sms"),default));var code=fixture.Sender.LastCode;
  await auth.Verify(new(phone.FlowId,phone.FlowToken,sent.GetProperty("challengeId").GetGuid(),code),"VerifyPhone",default);
  Assert.True((await db.Users.FindAsync(seed.User.Id))!.PhoneNumberConfirmed);
  var next=Flow(await auth.Login(new(seed.User.UserName,Password),default));var challenge=Json(await auth.Send(new(next.FlowId,next.FlowToken,"Sms"),default));
  var token=Json(await auth.Verify(new(next.FlowId,next.FlowToken,challenge.GetProperty("challengeId").GetGuid(),fixture.Sender.LastCode),"Login",default));Assert.False(string.IsNullOrWhiteSpace(token.GetProperty("accessToken").GetString()));
 }
 [Fact]public async Task Http_AuthorizationAndLogoutAreEnforcedOnServer()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var auth=scope.ServiceProvider.GetRequiredService<AuthService>();
  using var client=fixture.Factory.CreateClient(new(){BaseAddress=new Uri("https://localhost")});Assert.Equal(HttpStatusCode.Unauthorized,(await client.GetAsync("/api/v1/employees")).StatusCode);
  var code=await EmailCode(auth,await auth.Login(new(seed.User.UserName,Password),default));var result=Json(await auth.Verify(new(code.Flow.FlowId,code.Flow.FlowToken,code.Challenge,code.Code),"Login",default));
  client.DefaultRequestHeaders.Authorization=new AuthenticationHeaderValue("Bearer",result.GetProperty("accessToken").GetString());
  Assert.Equal(HttpStatusCode.Forbidden,(await client.GetAsync("/api/v1/employees")).StatusCode);Assert.Equal(HttpStatusCode.OK,(await client.GetAsync("/api/v1/auth/me")).StatusCode);
  Assert.Equal(HttpStatusCode.NoContent,(await client.PostAsync("/api/v1/auth/logout",null)).StatusCode);Assert.Equal(HttpStatusCode.Unauthorized,(await client.GetAsync("/api/v1/auth/me")).StatusCode);
 }
 [Fact]public async Task PasswordReset_RevokesExistingSessionsAndRejectsTheOldPassword()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var auth=scope.ServiceProvider.GetRequiredService<AuthService>();
  var login=await EmailCode(auth,await auth.Login(new(seed.User.UserName,Password),default));
  var logged=Json(await auth.Verify(new(login.Flow.FlowId,login.Flow.FlowToken,login.Challenge,login.Code),"Login",default));
  var remembered=Json(await scope.ServiceProvider.GetRequiredService<RememberedDeviceService>().Enroll(seed.User.Id,default)).GetProperty("token").GetString()!;
  using var client=fixture.Factory.CreateClient(new(){BaseAddress=new Uri("https://localhost")});client.DefaultRequestHeaders.Authorization=new AuthenticationHeaderValue("Bearer",logged.GetProperty("accessToken").GetString());
  Assert.Equal(HttpStatusCode.OK,(await client.GetAsync("/api/v1/auth/me")).StatusCode);
  var reset=await EmailCode(auth,await auth.Forgot(new(seed.User.Email),default));const string changed="ResetTestOnly!New528";
  await auth.Verify(new(reset.Flow.FlowId,reset.Flow.FlowToken,reset.Challenge,reset.Code),"ResetPassword",default,changed);
  Assert.Equal(HttpStatusCode.Unauthorized,(await client.GetAsync("/api/v1/auth/me")).StatusCode);
  Assert.Equal("InvalidCredentials",(await Assert.ThrowsAsync<ApiException>(()=>auth.Login(new(seed.User.UserName,Password),default))).Code);
  using var fresh=fixture.Factory.Services.CreateScope();await Assert.ThrowsAsync<ApiException>(()=>fresh.ServiceProvider.GetRequiredService<RememberedDeviceService>().Resume(remembered,default));
  Assert.Equal("Login",Json(await auth.Login(new(seed.User.UserName,changed),default)).GetProperty("purpose").GetString());
 }
 private async Task<AppUser> VerifiedPending(IServiceProvider services)
 {
  var auth=services.GetRequiredService<AuthService>();var suffix=Guid.NewGuid().ToString("N")[..12];
  var registration=await auth.Register(new("Registered staff","u"+suffix,suffix+"@example.invalid","+84901234567",Password,Password),default);
  var email=await EmailCode(auth,registration);await auth.Verify(new(email.Flow.FlowId,email.Flow.FlowToken,email.Challenge,email.Code),"VerifyEmail",default);
  return await services.GetRequiredService<AttendanceDbContext>().Users.SingleAsync(x=>x.NormalizedUserName==("u"+suffix).ToUpperInvariant());
 }
 [Fact]public async Task OneApprovalCreatesAndLinksTheRegisteredEmployeeWithoutReentry()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var user=await VerifiedPending(scope.ServiceProvider);
  var service=scope.ServiceProvider.GetRequiredService<EmployeeApprovalService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
  await service.ApproveRegistration(user.Id,new(seed.Employee.DepartmentId),seed.Admin.Id,default);
  var employee=await db.Employees.SingleAsync(x=>x.UserId==user.Id);
  Assert.Equal(user.FullName,employee.FullName);Assert.Equal(user.Email,employee.InvitationEmail);Assert.Equal(user.PhoneNumber,employee.InvitationPhone);
  Assert.Equal("Employee",user.Role);Assert.Equal("Approved",user.ApprovalStatus);Assert.StartsWith("NV_",employee.EmployeeCode);
  Assert.Equal(1,await db.AuditLogs.CountAsync(x=>x.EntityId==employee.Id&&x.Action=="CreatedFromRegistration"));
  Assert.Equal("Login",Json(await scope.ServiceProvider.GetRequiredService<AuthService>().Login(new(user.UserName,Password),default)).GetProperty("purpose").GetString());
  Assert.Equal(409,(await Assert.ThrowsAsync<ApiException>(()=>service.ApproveRegistration(user.Id,new(seed.Employee.DepartmentId),seed.Admin.Id,default))).Status);
  Assert.Equal(1,await db.Employees.CountAsync(x=>x.UserId==user.Id));
 }
 [Fact]public async Task InvalidDepartmentDoesNotPartiallyCreateOrApproveAnEmployee()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var user=await VerifiedPending(scope.ServiceProvider);
  var service=scope.ServiceProvider.GetRequiredService<EmployeeApprovalService>();
  Assert.Equal(400,(await Assert.ThrowsAsync<ApiException>(()=>service.ApproveRegistration(user.Id,new(Guid.NewGuid()),seed.Admin.Id,default))).Status);
  using var verify=fixture.Factory.Services.CreateScope();var db=verify.ServiceProvider.GetRequiredService<AttendanceDbContext>();
  Assert.Equal("Pending",(await db.Users.FindAsync(user.Id))!.ApprovalStatus);Assert.False(await db.Employees.AnyAsync(x=>x.UserId==user.Id));
 }
 [Fact]public async Task UnverifiedRegistrationCannotCreateAnActiveEmployeeThroughApproval()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var auth=scope.ServiceProvider.GetRequiredService<AuthService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();var suffix=Guid.NewGuid().ToString("N")[..12];
  await auth.Register(new("Unverified staff","u"+suffix,suffix+"@example.invalid","+84901234567",Password,Password),default);
  var user=await db.Users.SingleAsync(x=>x.NormalizedUserName==("u"+suffix).ToUpperInvariant());
  Assert.Equal(409,(await Assert.ThrowsAsync<ApiException>(()=>scope.ServiceProvider.GetRequiredService<EmployeeApprovalService>().ApproveRegistration(user.Id,new(seed.Employee.DepartmentId),seed.Admin.Id,default))).Status);
  Assert.False(await db.Employees.AnyAsync(x=>x.UserId==user.Id));
 }
}
