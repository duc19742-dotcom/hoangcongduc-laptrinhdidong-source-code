using System.Data;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;
using Attendance.Api.Data;
using Attendance.Api.DTOs;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.IdentityModel.Tokens;

namespace Attendance.Api.Services;

public sealed record FirebasePhoneProof(string ProofHash,string SubjectDigest,string Phone,DateTimeOffset AuthenticatedAtUtc);
public interface IFirebasePhoneVerifier
{
 Task<FirebasePhoneProof> Verify(string token,string expectedPhone,DateTimeOffset requestedAtUtc,CancellationToken ct);
}

// Firebase's documented third-party JWT verification path. Only Google's public
// signing certificates are needed; no service-account private key is shipped.
public sealed class FirebasePhoneVerifier(IConfiguration config,IHttpClientFactory clients,IMemoryCache cache):IFirebasePhoneVerifier
{
 private sealed record Keys(DateTimeOffset FetchedAt,List<SecurityKey> Items);
 private static readonly SemaphoreSlim RefreshLock=new(1,1);
 private const string CacheKey="FirebaseSigningCertificates";
 private async Task<Keys> SigningKeys(bool refresh,CancellationToken ct)
 {
  if(cache.TryGetValue<Keys>(CacheKey,out var existing)&&existing is not null&&(!refresh||existing.FetchedAt>DateTimeOffset.UtcNow.AddMinutes(-1)))return existing;
  await RefreshLock.WaitAsync(ct);
  try{
   if(cache.TryGetValue<Keys>(CacheKey,out existing)&&existing is not null&&(!refresh||existing.FetchedAt>DateTimeOffset.UtcNow.AddMinutes(-1)))return existing;
   using var response=await clients.CreateClient("FirebaseKeys").GetAsync("https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com",ct);
   response.EnsureSuccessStatusCode();
   var certificates=JsonSerializer.Deserialize<Dictionary<string,string>>(await response.Content.ReadAsStringAsync(ct))??throw new InvalidOperationException("Missing Firebase public certificates.");
   var keys=new List<SecurityKey>();
   foreach(var (kid,pem) in certificates){using var cert=X509Certificate2.CreateFromPem(pem);using var rsa=cert.GetRSAPublicKey()??throw new InvalidOperationException("Missing RSA key.");keys.Add(new RsaSecurityKey(rsa.ExportParameters(false)){KeyId=kid});}
   if(keys.Count==0)throw new InvalidOperationException("Missing Firebase public keys.");
   var entry=new Keys(DateTimeOffset.UtcNow,keys);var ttl=response.Headers.CacheControl?.MaxAge??TimeSpan.FromHours(1);
   cache.Set(CacheKey,entry,ttl<=TimeSpan.Zero?TimeSpan.FromSeconds(1):TimeSpan.FromSeconds(Math.Min(ttl.TotalSeconds,3600)));return entry;
  }finally{RefreshLock.Release();}
 }
 public async Task<FirebasePhoneProof> Verify(string token,string expectedPhone,DateTimeOffset requestedAtUtc,CancellationToken ct)
 {
  var project=config["Firebase:ProjectId"];
  if(string.IsNullOrWhiteSpace(project))throw new ApiException(503,"FirebaseNotConfigured","Chưa cấu hình dự án Firebase.");
  try{
   var handler=new JwtSecurityTokenHandler{MapInboundClaims=false};
   if(token.Length>8192||!handler.CanReadToken(token))throw new SecurityTokenException();
   var header=handler.ReadJwtToken(token).Header;
   if(header.Alg!=SecurityAlgorithms.RsaSha256||string.IsNullOrEmpty(header.Kid))throw new SecurityTokenException();
   var keys=await SigningKeys(false,ct);if(!keys.Items.Any(x=>x.KeyId==header.Kid))keys=await SigningKeys(true,ct);
   var principal=handler.ValidateToken(token,new TokenValidationParameters{
    ValidateIssuer=true,ValidIssuer="https://securetoken.google.com/"+project,ValidateAudience=true,ValidAudience=project,
    ValidateIssuerSigningKey=true,IssuerSigningKeys=keys.Items,ValidAlgorithms=[SecurityAlgorithms.RsaSha256],
    ValidateLifetime=true,RequireExpirationTime=true,RequireSignedTokens=true,ClockSkew=TimeSpan.FromSeconds(15)
   },out _);
   var subject=principal.FindFirst("sub")?.Value;var phone=principal.FindFirst("phone_number")?.Value;
   if(string.IsNullOrWhiteSpace(subject)||subject.Length>128||string.IsNullOrWhiteSpace(phone)||Secrets.Phone(phone)!=expectedPhone)throw new SecurityTokenException();
   if(!long.TryParse(principal.FindFirst("auth_time")?.Value,out var authSeconds)||!long.TryParse(principal.FindFirst("iat")?.Value,out var issuedSeconds))throw new SecurityTokenException();
   var authenticated=DateTimeOffset.FromUnixTimeSeconds(authSeconds);var issued=DateTimeOffset.FromUnixTimeSeconds(issuedSeconds);
   if(authenticated<requestedAtUtc.AddSeconds(-5)||authenticated>DateTimeOffset.UtcNow.AddSeconds(15)||issued<DateTimeOffset.FromUnixTimeSeconds(authSeconds)||issued>DateTimeOffset.UtcNow.AddSeconds(15))throw new SecurityTokenException();
   using var firebase=JsonDocument.Parse(principal.FindFirst("firebase")?.Value??"{}");
   if(!firebase.RootElement.TryGetProperty("sign_in_provider",out var provider)||provider.GetString()!="phone")throw new SecurityTokenException();
   return new(Secrets.Hash(project+"|"+subject+"|"+authSeconds),Secrets.Hash(subject),Secrets.Phone(phone),authenticated);
  }catch(Exception ex)when(ex is SecurityTokenException or ArgumentException or JsonException or ApiException){throw new ApiException(401,"FirebaseTokenInvalid","Xác minh SMS chưa hợp lệ hoặc đã cũ. Hãy yêu cầu mã SMS mới.");}
  catch(Exception ex)when(ex is HttpRequestException||ex is TaskCanceledException&&!ct.IsCancellationRequested){throw new ApiException(503,"FirebaseUnavailable","Chưa kiểm tra được chữ ký Firebase. Hãy thử lại.");}
 }
}

public sealed class FirebasePhoneFlowService(AttendanceDbContext db,AuthService auth,IFirebasePhoneVerifier verifier,IConfiguration config,AuditService audit)
{
 private void Configured(){if(config["Sms:Provider"]!="Firebase"||string.IsNullOrWhiteSpace(config["Firebase:ProjectId"]))throw new ApiException(503,"FirebaseNotConfigured","Chưa cấu hình SMS Firebase. Bạn vẫn có thể dùng Email OTP.");}
 private static void Purpose(AuthFlow flow){if(flow.Purpose is not("Login" or "VerifyPhone"))throw new ApiException(400,"InvalidPurpose","Phiên này không dùng để xác minh điện thoại.");AuthService.RequireApproved(flow.User);}
 public async Task<object> Start(FlowDto d,CancellationToken ct)
 {
  Configured();await using var tx=await db.Database.BeginTransactionAsync(IsolationLevel.Serializable,ct);var flow=await auth.LoadFlow(d,ct);Purpose(flow);var now=DateTimeOffset.UtcNow;
  if(flow.LastSentAtUtc>now.AddSeconds(-60))throw new ApiException(429,"ResendCooldown","Hãy chờ 60 giây giữa hai lần yêu cầu mã.");
  if(flow.SendCount>=3||await db.AuthFlows.Where(x=>x.UserId==flow.UserId&&x.CreatedAtUtc>now.AddHours(-1)).SumAsync(x=>x.SendCount,ct)>=10)throw new ApiException(429,"OtpLimit","Bạn đã yêu cầu quá nhiều mã. Hãy thử lại sau.");
  flow.ExternalChallengeId=Guid.NewGuid();flow.ExternalChallengeStartedAtUtc=now;flow.ExternalChallengeExpiresAtUtc=now.AddMinutes(5);flow.ExternalVerificationAttempts=0;flow.SendCount++;flow.LastSentAtUtc=now;
  audit.Add(flow.UserId,"AuthFlow",flow.Id,"FirebasePhoneRequested");await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);
  return new{challengeId=flow.ExternalChallengeId,provider="Firebase",status="Ready",phoneNumber=flow.User.PhoneNumber,expiresAtUtc=flow.ExternalChallengeExpiresAtUtc,retryAfterSeconds=60};
 }
 private static void Challenge(AuthFlow flow,Guid challenge)
 {if(flow.ExternalChallengeId!=challenge||!flow.ExternalChallengeStartedAtUtc.HasValue||!flow.ExternalChallengeExpiresAtUtc.HasValue||flow.ExternalChallengeExpiresAtUtc<=DateTimeOffset.UtcNow)throw new ApiException(410,"OtpExpired","Phiên SMS đã hết hạn hoặc đã thay thế. Hãy yêu cầu mã mới.");}
 public async Task<object> Complete(FirebaseVerifyDto d,CancellationToken ct)
 {
  Configured();AuthFlow initial;
  await using(var tx=await db.Database.BeginTransactionAsync(IsolationLevel.Serializable,ct)){
   initial=await auth.LoadFlow(d,ct);Purpose(initial);Challenge(initial,d.ChallengeId);
   if(initial.ExternalVerificationAttempts>=5)throw new ApiException(429,"OtpLocked","Đã vượt số lần kiểm tra SMS. Hãy yêu cầu phiên mới.");
   initial.ExternalVerificationAttempts++;await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);
  }
  var proof=await verifier.Verify(d.IdToken,initial.User.PhoneNumber,initial.ExternalChallengeStartedAtUtc!.Value,ct);
  db.ChangeTracker.Clear();await using var finalTx=await db.Database.BeginTransactionAsync(IsolationLevel.Serializable,ct);
  // Serialize consumption of a single flow. ProofHash is also globally unique.
  await db.AuthFlows.FromSqlInterpolated($"SELECT * FROM AuthFlows WITH (UPDLOCK, ROWLOCK) WHERE Id={d.FlowId}").SingleOrDefaultAsync(ct);
  var flow=await auth.LoadFlow(d,ct);Purpose(flow);Challenge(flow,d.ChallengeId);
  if(flow.User.PhoneNumber!=proof.Phone||await db.ExternalAuthProofs.AnyAsync(x=>x.ProofHash==proof.ProofHash,ct))throw new ApiException(409,"FirebaseProofAlreadyUsed","Bằng chứng SMS đã dùng hoặc thông tin liên hệ đã đổi. Hãy xác minh lại.");
  flow.UsedAtUtc=DateTimeOffset.UtcNow;flow.User.PhoneNumberConfirmed=true;
  db.ExternalAuthProofs.Add(new(){UserId=flow.UserId,ProofHash=proof.ProofHash,SubjectDigest=proof.SubjectDigest,AuthenticatedAtUtc=proof.AuthenticatedAtUtc});
  object result=flow.Purpose=="Login"?auth.IssueToken(flow.User):new{status="PhoneVerified"};
  audit.Add(flow.UserId,"User",flow.UserId,flow.Purpose+"VerifiedByFirebase");await db.SaveChangesAsync(ct);await finalTx.CommitAsync(ct);return result;
 }
}
