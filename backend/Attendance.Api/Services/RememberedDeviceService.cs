using System.Data;
using Attendance.Api.Data;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Microsoft.EntityFrameworkCore;
namespace Attendance.Api.Services;

public sealed class RememberedDevice : Entity
{
 public string AuthenticationMethod {get;set;}="Quick";
 public string? PublicKey {get;set;}
 public string? FaceTemplateJson {get;set;}
 public int FailedAttempts {get;set;}
 public DateTimeOffset? LockedUntilUtc {get;set;}
 public Guid UserId {get;set;}
 public AppUser User {get;set;}=null!;
 public string TokenHash {get;set;}="";
 public DateTimeOffset ExpiresAtUtc {get;set;}
 public DateTimeOffset? RevokedAtUtc {get;set;}
}
public sealed record RememberedLoginDto(string Token);
public sealed class RememberedDeviceService(AttendanceDbContext db,AuthService auth,AuditService audit)
{
 public async Task<object> Enroll(Guid userId,CancellationToken ct) {
  var user=await db.Users.Include(x=>x.Employee).SingleAsync(x=>x.Id==userId,ct);AuthService.RequireApproved(user);
  var token=Secrets.NewToken();var expires=DateTimeOffset.UtcNow.AddDays(30);
  db.Set<RememberedDevice>().Add(new(){UserId=userId,TokenHash=Secrets.Hash(token),ExpiresAtUtc=expires});
  audit.Add(userId,"User",userId,"DeviceRemembered");await db.SaveChangesAsync(ct);
  return new{token,expiresAtUtc=expires,username=user.UserName};
 }
 public async Task<object> Resume(string token,CancellationToken ct) {
  if(string.IsNullOrWhiteSpace(token)||token.Length>256)throw new ApiException(401,"InvalidDevice","Tài khoản đã lưu hết hạn. Hãy đăng nhập lại.");
  await using var tx=await db.Database.BeginTransactionAsync(IsolationLevel.Serializable,ct);
  var hash=Secrets.Hash(token);
  var device=await db.Set<RememberedDevice>().FromSqlInterpolated($"SELECT * FROM RememberedDevices WITH (UPDLOCK, ROWLOCK) WHERE TokenHash={hash}").Include(x=>x.User).ThenInclude(x=>x.Employee).SingleOrDefaultAsync(ct);
  if(device is null||device.AuthenticationMethod!="Quick"||device.RevokedAtUtc.HasValue||device.ExpiresAtUtc<=DateTimeOffset.UtcNow)throw new ApiException(401,"InvalidDevice","Tài khoản đã lưu hết hạn. Hãy đăng nhập lại.");
  AuthService.RequireApproved(device.User);var next=Secrets.NewToken();device.TokenHash=Secrets.Hash(next);
  var session=auth.IssueToken(device.User,"Device");audit.Add(device.UserId,"User",device.UserId,"RememberedLogin");await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);
  return new{session,deviceToken=next,device.ExpiresAtUtc,username=device.User.UserName};
 }
 public async Task Revoke(string token,CancellationToken ct) {
  var hash=Secrets.Hash(token??"");var device=await db.Set<RememberedDevice>().SingleOrDefaultAsync(x=>x.TokenHash==hash,ct);
  if(device is not null){device.RevokedAtUtc=DateTimeOffset.UtcNow;await db.SaveChangesAsync(ct);}
 }
}
