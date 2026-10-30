using System.Security.Cryptography;
using System.Text;
using Attendance.Api.Data;
using Attendance.Api.Services;
using Attendance.Api.Middleware;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace Attendance.Api.Tests;
public sealed partial class IntegrationTests
{
 [Fact] public async Task Fingerprint_RequiresSignedSingleUseChallenge_AndSupportsRevoke()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var service=scope.ServiceProvider.GetRequiredService<BiometricService>();
  using var key=ECDsa.Create(ECCurve.NamedCurves.nistP256);
  string Sign(string nonce)=>Convert.ToBase64String(key.SignData(Encoding.UTF8.GetBytes(nonce),HashAlgorithmName.SHA256,DSASignatureFormat.Rfc3279DerSequence));
  var enroll=Json(await service.Challenge(seed.User.Id,null,default));
  var device=Json(await service.EnrollFingerprint(seed.User.Id,new(enroll.GetProperty("id").GetGuid(),Convert.ToBase64String(key.ExportSubjectPublicKeyInfo()),Sign(enroll.GetProperty("nonce").GetString()!)),default));
  var id=device.GetProperty("id").GetGuid();var challenge=Json(await service.Challenge(null,id,default));
  var dto=new FingerprintVerifyDto(challenge.GetProperty("id").GetGuid(),Sign(challenge.GetProperty("nonce").GetString()!));
  Assert.False(string.IsNullOrWhiteSpace(Json(await service.LoginFingerprint(dto,default)).GetProperty("accessToken").GetString()));
  Assert.Equal(410,(await Assert.ThrowsAsync<ApiException>(()=>service.LoginFingerprint(dto,default))).Status);
  var bad=Json(await service.Challenge(null,id,default));
  Assert.Equal(401,(await Assert.ThrowsAsync<ApiException>(()=>service.LoginFingerprint(new(bad.GetProperty("id").GetGuid(),Sign("wrong nonce")),default))).Status);
  await service.Remove(seed.User.Id,id,default);
  Assert.Equal(401,(await Assert.ThrowsAsync<ApiException>(()=>service.Challenge(null,id,default))).Status);
 }
 [Fact] public async Task Face_MatchesIdentity_RotatesToken_AndCannotBypassViaQuickLogin()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var service=scope.ServiceProvider.GetRequiredService<BiometricService>();var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
  var face=new float[192];face[0]=1;var other=new float[192];other[1]=1;
  Assert.Equal(400,(await Assert.ThrowsAsync<ApiException>(()=>service.EnrollFace(seed.User.Id,new(face,other,true),default))).Status);
  var enrolled=Json(await service.EnrollFace(seed.User.Id,new(face,face,true),default));var token=enrolled.GetProperty("token").GetString()!;
  Assert.Equal(401,(await Assert.ThrowsAsync<ApiException>(()=>scope.ServiceProvider.GetRequiredService<RememberedDeviceService>().Resume(token,default))).Status);
  Assert.Equal(401,(await Assert.ThrowsAsync<ApiException>(()=>service.LoginFace(new(token,other),default))).Status);
  var logged=Json(await service.LoginFace(new(token,face),default));var next=logged.GetProperty("deviceToken").GetString()!;Assert.NotEqual(token,next);
  Assert.Equal(401,(await Assert.ThrowsAsync<ApiException>(()=>service.LoginFace(new(token,face),default))).Status);
  var id=enrolled.GetProperty("id").GetGuid();await service.Remove(seed.User.Id,id,default);
  Assert.Null((await db.Set<RememberedDevice>().FindAsync(id))!.FaceTemplateJson);
  Assert.Equal(401,(await Assert.ThrowsAsync<ApiException>(()=>service.LoginFace(new(next,face),default))).Status);
 }
 [Fact] public async Task Enrollment_RequiresFreshOtp_NotRememberedSession()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var auth=scope.ServiceProvider.GetRequiredService<AuthService>();var service=scope.ServiceProvider.GetRequiredService<BiometricService>();
  var code=await EmailCode(auth,await auth.Login(new(seed.User.UserName,Password),default));var session=Json(await auth.Verify(new(code.Flow.FlowId,code.Flow.FlowToken,code.Challenge,code.Code),"Login",default));
  string Jti(string token)=>new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler().ReadJwtToken(token).Id;
  await service.RecentOtp(seed.User.Id,Jti(session.GetProperty("accessToken").GetString()!),default);
  var quick=scope.ServiceProvider.GetRequiredService<RememberedDeviceService>();var device=Json(await quick.Enroll(seed.User.Id,default));var resumed=Json(await quick.Resume(device.GetProperty("token").GetString()!,default));
  Assert.Equal(403,(await Assert.ThrowsAsync<ApiException>(()=>service.RecentOtp(seed.User.Id,Jti(resumed.GetProperty("session").GetProperty("accessToken").GetString()!),default))).Status);
 }
 [Fact] public async Task Profile_SeparatesDisplayName_FromApprovedLegalName()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var service=scope.ServiceProvider.GetRequiredService<ProfileService>();
  var legal=seed.User.FullName;await service.Save(seed.User.Id,new("Display only",null),default);Assert.Equal(legal,seed.User.FullName);
  Assert.Equal(400,(await Assert.ThrowsAsync<ApiException>(()=>service.Save(seed.User.Id,new("Display only","data:image/jpeg;base64,AAAA"),default))).Status);
  var request=Json(await service.RequestName(seed.User.Id,new("Approved legal name"),default));Assert.Equal(legal,seed.Employee.FullName);
  await service.ReviewName(seed.Admin.Id,request.GetProperty("id").GetGuid(),true,"Verified",default);Assert.Equal("Approved legal name",seed.User.FullName);Assert.Equal(seed.User.FullName,seed.Employee.FullName);
 }
 [Fact] public async Task ContactChange_RequiresBothCodes_AndRevokesSavedDevices()
 {
  using var scope=fixture.Factory.Services.CreateScope();var seed=await Seed(scope.ServiceProvider);var service=scope.ServiceProvider.GetRequiredService<ProfileService>();var devices=scope.ServiceProvider.GetRequiredService<RememberedDeviceService>();
  var saved=Json(await devices.Enroll(seed.User.Id,default));var original=seed.User.Email;var next=Guid.NewGuid()+"@example.invalid";
  var started=Json(await service.Start(seed.User.Id,new("Email",next,Password),default));var id=started.GetProperty("id").GetGuid();var oldCode=fixture.Sender.Codes[original];var newCode=fixture.Sender.Codes[next];
  Assert.Equal(400,(await Assert.ThrowsAsync<ApiException>(()=>service.Confirm(seed.User.Id,new(id,oldCode,newCode=="000000"?"111111":"000000"),default))).Status);Assert.Equal(original,seed.User.Email);
  await service.Confirm(seed.User.Id,new(id,oldCode,newCode),default);Assert.Equal(next,seed.User.Email);Assert.Equal(next,seed.Employee.InvitationEmail);
  using var fresh=fixture.Factory.Services.CreateScope();Assert.Equal(401,(await Assert.ThrowsAsync<ApiException>(()=>fresh.ServiceProvider.GetRequiredService<RememberedDeviceService>().Resume(saved.GetProperty("token").GetString()!,default))).Status);
 }
}
