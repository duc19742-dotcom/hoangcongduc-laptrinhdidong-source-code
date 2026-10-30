using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Attendance.Api.Data;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Microsoft.EntityFrameworkCore;
namespace Attendance.Api.Services;

public sealed class BiometricChallenge:Entity {
 public Guid UserId {get;set;}
 public Guid? DeviceId {get;set;}
 public string Nonce {get;set;}="";
 public string Purpose {get;set;}="Enroll";
 public DateTimeOffset ExpiresAtUtc {get;set;}
 public DateTimeOffset? UsedAtUtc {get;set;}
}
public sealed record FingerprintEnrollDto(Guid ChallengeId,string PublicKey,string Signature);
public sealed record FingerprintVerifyDto(Guid ChallengeId,string Signature);
public sealed record FaceEnrollDto(float[] First,float[] Second,bool AcceptDemoRisk);
public sealed record FaceLoginDto(string Token,float[] Embedding);
public sealed class BiometricService(AttendanceDbContext db,AuthService auth,AuditService audit,IConfiguration config) {
 public async Task RecentOtp(Guid user,string jti,CancellationToken ct) {
  var hash=Secrets.Hash(jti);
  if(!await db.AuthSessions.AnyAsync(x=>x.UserId==user&&x.JtiHash==hash&&x.AuthenticationMethod=="Otp"&&x.CreatedAtUtc>DateTimeOffset.UtcNow.AddMinutes(-5)&&!x.RevokedAtUtc.HasValue,ct))throw new ApiException(403,"RecentOtpRequired","Đăng xuất và đăng nhập bằng mật khẩu + OTP trong 5 phút trước khi thay đổi sinh trắc học.");
 }
 public async Task<object> Challenge(Guid? user,Guid? deviceId,CancellationToken ct) {
  Guid userId;
  if(user.HasValue)userId=user.Value;
  else {
   var device=await db.Set<RememberedDevice>().Include(x=>x.User).ThenInclude(x=>x.Employee).SingleOrDefaultAsync(x=>x.Id==deviceId,ct);
   CheckDevice(device,"Fingerprint");AuthService.RequireApproved(device!.User);userId=device.UserId;
  }
  var challenge=new BiometricChallenge{UserId=userId,DeviceId=deviceId,Nonce=Secrets.NewToken(),Purpose=user.HasValue?"Enroll":"Login",ExpiresAtUtc=DateTimeOffset.UtcNow.AddMinutes(2)};
  db.Add(challenge);await db.SaveChangesAsync(ct);return new{id=challenge.Id,nonce=challenge.Nonce,challenge.ExpiresAtUtc};
 }
 private async Task<BiometricChallenge> Load(Guid id,string purpose,CancellationToken ct) {
  var c=await db.Set<BiometricChallenge>().FromSqlInterpolated($"SELECT * FROM BiometricChallenges WITH (UPDLOCK, ROWLOCK) WHERE Id={id}").SingleOrDefaultAsync(ct);
  if(c is null||c.UsedAtUtc.HasValue||c.ExpiresAtUtc<=DateTimeOffset.UtcNow||c.Purpose!=purpose)throw new ApiException(410,"BiometricExpired","Phiên xác thực đã hết hạn hoặc đã sử dụng.");
  return c;
 }
 private static void CheckDevice(RememberedDevice? d,string method) {
  if(d is null||d.AuthenticationMethod!=method||d.RevokedAtUtc.HasValue||d.ExpiresAtUtc<=DateTimeOffset.UtcNow)throw new ApiException(401,"InvalidDevice","Thiết bị hết hạn hoặc bị thu hồi. Đăng nhập bằng mật khẩu + OTP.");
  if(d.LockedUntilUtc>DateTimeOffset.UtcNow)throw new ApiException(429,"BiometricLocked","Xác thực đã tạm khóa. Thử lại sau 5 phút hoặc dùng mật khẩu + OTP.");
 }
 private static bool VerifySignature(string key,string nonce,string signature) {
  if(key.Length>2048||signature.Length>2048)return false;
  try{using var ec=ECDsa.Create();ec.ImportSubjectPublicKeyInfo(Convert.FromBase64String(key),out _);return ec.KeySize==256&&ec.VerifyData(Encoding.UTF8.GetBytes(nonce),Convert.FromBase64String(signature),HashAlgorithmName.SHA256,DSASignatureFormat.Rfc3279DerSequence);}catch(Exception e)when(e is CryptographicException or FormatException or ArgumentException){return false;}
 }
 public async Task<object> EnrollFingerprint(Guid user,FingerprintEnrollDto d,CancellationToken ct) {
  await using var tx=await db.Database.BeginTransactionAsync(IsolationLevel.Serializable,ct);var c=await Load(d.ChallengeId,"Enroll",ct);
  if(c.UserId!=user)throw CatalogService.Missing();c.UsedAtUtc=DateTimeOffset.UtcNow;
  if(!VerifySignature(d.PublicKey,c.Nonce,d.Signature)){await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);throw new ApiException(400,"InvalidSignature","Chữ ký vân tay không hợp lệ.");}
  var device=new RememberedDevice{UserId=user,AuthenticationMethod="Fingerprint",PublicKey=d.PublicKey,TokenHash=Secrets.Hash(Secrets.NewToken()),ExpiresAtUtc=DateTimeOffset.UtcNow.AddDays(30)};db.Add(device);audit.Add(user,"User",user,"FingerprintEnrolled");await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);return new{id=device.Id,device.ExpiresAtUtc};
 }
 public async Task<object> LoginFingerprint(FingerprintVerifyDto d,CancellationToken ct) {
  await using var tx=await db.Database.BeginTransactionAsync(IsolationLevel.Serializable,ct);var c=await Load(d.ChallengeId,"Login",ct);
  var device=await db.Set<RememberedDevice>().Include(x=>x.User).ThenInclude(x=>x.Employee).SingleOrDefaultAsync(x=>x.Id==c.DeviceId,ct);CheckDevice(device,"Fingerprint");AuthService.RequireApproved(device!.User);c.UsedAtUtc=DateTimeOffset.UtcNow;
  if(!VerifySignature(device.PublicKey!,c.Nonce,d.Signature)){await Failed(device,ct);await tx.CommitAsync(ct);throw new ApiException(401,"InvalidSignature","Xác thực vân tay không hợp lệ.");}
  device.FailedAttempts=0;var session=auth.IssueToken(device.User,"Fingerprint");audit.Add(device.UserId,"User",device.UserId,"FingerprintLogin");await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);return session;
 }
 private async Task Failed(RememberedDevice d,CancellationToken ct){d.FailedAttempts++;if(d.FailedAttempts>=5){d.LockedUntilUtc=DateTimeOffset.UtcNow.AddMinutes(5);d.FailedAttempts=0;}await db.SaveChangesAsync(ct);}
 public static float[] Normalize(float[] values) {
  if(values is null||values.Length!=192||values.Any(x=>!float.IsFinite(x)))throw new ApiException(400,"InvalidFace","Mẫu khuôn mặt không hợp lệ.");
  var norm=Math.Sqrt(values.Sum(x=>(double)x*x));if(norm<0.00001||norm>100000)throw new ApiException(400,"InvalidFace","Không đọc được khuôn mặt. Hãy chụp lại.");return values.Select(x=>(float)(x/norm)).ToArray();
 }
 private string Encrypt(float[] values){var nonce=RandomNumberGenerator.GetBytes(12);var data=JsonSerializer.SerializeToUtf8Bytes(values);var output=new byte[data.Length];var tag=new byte[16];using var aes=new AesGcm(SHA256.HashData(Encoding.UTF8.GetBytes("FaceTemplate:v1|"+config["Jwt:SigningKey"])),16);aes.Encrypt(nonce,data,output,tag);return Convert.ToBase64String(nonce.Concat(tag).Concat(output).ToArray());}
 private float[] Decrypt(string value){var b=Convert.FromBase64String(value);var output=new byte[b.Length-28];using var aes=new AesGcm(SHA256.HashData(Encoding.UTF8.GetBytes("FaceTemplate:v1|"+config["Jwt:SigningKey"])),16);aes.Decrypt(b.AsSpan(0,12),b.AsSpan(28),b.AsSpan(12,16),output);return Normalize(JsonSerializer.Deserialize<float[]>(output)!);}
 public async Task<object> EnrollFace(Guid user,FaceEnrollDto d,CancellationToken ct) {
  if(!d.AcceptDemoRisk)throw new ApiException(400,"FaceConsentRequired","Cần đồng ý giới hạn xác thực khuôn mặt bản demo.");
  var first=Normalize(d.First);var second=Normalize(d.Second);if(first.Zip(second).Sum(p=>p.First*p.Second)<0.80)throw new ApiException(400,"FaceEnrollmentMismatch","Hai ảnh không khớp. Chụp chính diện cùng một người, đủ sáng.");
  var template=Normalize(first.Zip(second).Select(p=>(p.First+p.Second)/2).ToArray());var token=Secrets.NewToken();var device=new RememberedDevice{UserId=user,AuthenticationMethod="Face",TokenHash=Secrets.Hash(token),FaceTemplateJson=Encrypt(template),ExpiresAtUtc=DateTimeOffset.UtcNow.AddDays(30)};db.Add(device);audit.Add(user,"User",user,"DemoFaceEnrolled");await db.SaveChangesAsync(ct);return new{id=device.Id,token,device.ExpiresAtUtc};
 }
 public async Task<object> LoginFace(FaceLoginDto d,CancellationToken ct) {
  var embedding=Normalize(d.Embedding);if(string.IsNullOrWhiteSpace(d.Token)||d.Token.Length>256)throw new ApiException(401,"InvalidDevice","Thiết bị không hợp lệ.");
  await using var tx=await db.Database.BeginTransactionAsync(IsolationLevel.Serializable,ct);var hash=Secrets.Hash(d.Token);
  var device=await db.Set<RememberedDevice>().FromSqlInterpolated($"SELECT * FROM RememberedDevices WITH (UPDLOCK, ROWLOCK) WHERE TokenHash={hash}").Include(x=>x.User).ThenInclude(x=>x.Employee).SingleOrDefaultAsync(ct);CheckDevice(device,"Face");AuthService.RequireApproved(device!.User);
  var template=Decrypt(device.FaceTemplateJson!);if(template.Zip(embedding).Sum(p=>p.First*p.Second)<0.80){await Failed(device,ct);await tx.CommitAsync(ct);throw new ApiException(401,"FaceMismatch","Khuôn mặt không khớp. Thử lại hoặc dùng mật khẩu + OTP.");}
  device.FailedAttempts=0;var next=Secrets.NewToken();device.TokenHash=Secrets.Hash(next);var session=auth.IssueToken(device.User,"Face");audit.Add(device.UserId,"User",device.UserId,"DemoFaceLogin");await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);return new{session,deviceToken=next};
 }
 public async Task Remove(Guid user,Guid id,CancellationToken ct) {var device=await db.Set<RememberedDevice>().SingleOrDefaultAsync(x=>x.Id==id&&x.UserId==user,ct)??throw CatalogService.Missing();device.RevokedAtUtc=DateTimeOffset.UtcNow;device.FaceTemplateJson=null;device.PublicKey=null;audit.Add(user,"User",user,"BiometricRemoved");await db.SaveChangesAsync(ct);}
}
