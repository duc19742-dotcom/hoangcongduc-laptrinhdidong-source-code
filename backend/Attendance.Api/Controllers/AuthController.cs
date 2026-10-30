using System.IdentityModel.Tokens.Jwt;
using Attendance.Api.Data;
using Attendance.Api.DTOs;
using Attendance.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
namespace Attendance.Api.Controllers;
[ApiController,Route("api/v1/auth"),EnableRateLimiting("auth")]
public sealed class AuthController(AuthService auth,AttendanceDbContext db,FirebasePhoneFlowService firebase,RememberedDeviceService devices):ControllerBase
{
    [HttpPost("devices"),Authorize] public Task<object> Remember(CancellationToken ct)=>devices.Enroll(User.UserId(),ct);
    [HttpPost("devices/resume"),AllowAnonymous] public Task<object> Resume(RememberedLoginDto d,CancellationToken ct)=>devices.Resume(d.Token,ct);
    [HttpPost("devices/forget"),AllowAnonymous] public async Task<IActionResult> Forget(RememberedLoginDto d,CancellationToken ct){await devices.Revoke(d.Token,ct);return NoContent();}
    [HttpPost("register"),AllowAnonymous] public async Task<IActionResult> Register(RegisterDto d,CancellationToken ct)=>Accepted(await auth.Register(d,ct));
    [HttpPost("login"),AllowAnonymous] public async Task<IActionResult> Login(LoginDto d,CancellationToken ct)=>Ok(await auth.Login(d,ct));
    [HttpPost("otp/send"),AllowAnonymous] public async Task<IActionResult> Send(SendOtpDto d,CancellationToken ct)=>Accepted(await auth.Send(d,ct));
    [HttpPost("sms/firebase/start"),AllowAnonymous] public async Task<IActionResult> FirebaseStart(FlowDto d,CancellationToken ct)=>Ok(await firebase.Start(d,ct));
    [HttpPost("sms/firebase/verify"),AllowAnonymous] public async Task<IActionResult> FirebaseVerify(FirebaseVerifyDto d,CancellationToken ct)=>Ok(await firebase.Complete(d,ct));
    [HttpPost("email-verification/verify"),AllowAnonymous] public async Task<IActionResult> Email(VerifyOtpDto d,CancellationToken ct)=>Ok(await auth.Verify(d,"VerifyEmail",ct));
    [HttpPost("login/otp/verify"),AllowAnonymous] public async Task<IActionResult> Verify(VerifyOtpDto d,CancellationToken ct)=>Ok(await auth.Verify(d,"Login",ct));
    [HttpPost("phone-verification/start"),AllowAnonymous] public async Task<IActionResult> PhoneStart(FlowDto d,CancellationToken ct)=>Ok(await auth.StartPhone(d,ct));
    [HttpPost("phone-verification/verify"),AllowAnonymous] public async Task<IActionResult> Phone(VerifyOtpDto d,CancellationToken ct)=>Ok(await auth.Verify(d,"VerifyPhone",ct));
    [HttpPost("forgot-password"),AllowAnonymous] public async Task<IActionResult> Forgot(ForgotDto d,CancellationToken ct)=>Accepted(await auth.Forgot(d,ct));
    [HttpPost("reset-password"),AllowAnonymous] public async Task<IActionResult> Reset(ResetPasswordDto d,CancellationToken ct) {Secrets.Password(d.NewPassword,d.ConfirmPassword);await auth.Verify(d,"ResetPassword",ct,d.NewPassword);return NoContent();}
    [HttpGet("me"),Authorize] public async Task<IActionResult> Me(CancellationToken ct)=>Ok(AuthService.UserView(await db.Users.Include(x=>x.Employee).SingleAsync(x=>x.Id==User.UserId(),ct)));
    [HttpPost("logout"),Authorize] public async Task<IActionResult> Logout(CancellationToken ct) {var hash=Secrets.Hash(User.FindFirst(JwtRegisteredClaimNames.Jti)!.Value);await db.AuthSessions.Where(x=>x.UserId==User.UserId()&&x.JtiHash==hash).ExecuteUpdateAsync(s=>s.SetProperty(x=>x.RevokedAtUtc,(DateTimeOffset?)DateTimeOffset.UtcNow),ct);return NoContent();}
}
