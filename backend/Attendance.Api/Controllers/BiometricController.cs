using System.IdentityModel.Tokens.Jwt;
using Attendance.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
namespace Attendance.Api.Controllers;
[ApiController,Route("api/v1/auth/biometric"),EnableRateLimiting("auth")]
public sealed class BiometricController(BiometricService service):ControllerBase {
 [HttpPost("enroll/check"),Authorize]public async Task<object> Check(CancellationToken ct){await Recent(ct);return new{ready=true};}
 [HttpPost("fingerprint/enroll/challenge"),Authorize]public async Task<object> EnrollChallenge(CancellationToken ct){await Recent(ct);return await service.Challenge(User.UserId(),null,ct);}
 [HttpPost("fingerprint/enroll"),Authorize]public async Task<object> EnrollFingerprint(FingerprintEnrollDto d,CancellationToken ct){await Recent(ct);return await service.EnrollFingerprint(User.UserId(),d,ct);}
 [HttpPost("fingerprint/challenge"),AllowAnonymous]public Task<object> Challenge(FingerprintDeviceDto d,CancellationToken ct)=>service.Challenge(null,d.DeviceId,ct);
 [HttpPost("fingerprint/verify"),AllowAnonymous]public Task<object> Verify(FingerprintVerifyDto d,CancellationToken ct)=>service.LoginFingerprint(d,ct);
 [HttpPost("face/enroll"),Authorize]public async Task<object> EnrollFace(FaceEnrollDto d,CancellationToken ct){await Recent(ct);return await service.EnrollFace(User.UserId(),d,ct);}
 [HttpPost("face/verify"),AllowAnonymous]public Task<object> Face(FaceLoginDto d,CancellationToken ct)=>service.LoginFace(d,ct);
 [HttpDelete("{id:guid}"),Authorize]public async Task<IActionResult> Remove(Guid id,CancellationToken ct){await service.Remove(User.UserId(),id,ct);return NoContent();}
 private Task Recent(CancellationToken ct)=>service.RecentOtp(User.UserId(),User.FindFirst(JwtRegisteredClaimNames.Jti)!.Value,ct);
}
public sealed record FingerprintDeviceDto(Guid DeviceId);
