using System.ComponentModel.DataAnnotations;
using System.Security.Cryptography;
using System.Text;
using Attendance.Api.Data;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
namespace Attendance.Api.Services;

public sealed class ProfileChange:Entity {
 public Guid UserId{get;set;}
 public AppUser User{get;set;}=null!;
 public string Kind{get;set;}="Email";
 public string Value{get;set;}="";
 public string OldValue{get;set;}="";
 public string? CurrentCodeMac{get;set;}
 public string? NewCodeMac{get;set;}
 public string Status{get;set;}="Pending";
 public int FailedAttempts{get;set;}
 public DateTimeOffset ExpiresAtUtc{get;set;}
 public string? DecisionReason{get;set;}
}
public sealed record ProfileDto([Required,StringLength(80,MinimumLength=2)]string DisplayName,[StringLength(140000)]string? AvatarDataUrl);
public sealed record ContactChangeDto([Required]string Kind,[Required,StringLength(254)]string Value,[Required]string Password);
public sealed record ContactConfirmDto(Guid Id,[Required,RegularExpression("^\\d{6}$")]string CurrentCode,[Required,RegularExpression("^\\d{6}$")]string NewCode);
public sealed record LegalNameDto([Required,StringLength(120,MinimumLength=2)]string FullName);
public sealed class ProfileService(AttendanceDbContext db,AuditService audit,IMessageSender messages,IPasswordHasher<AppUser> hasher,IConfiguration config) {
 public async Task<object> Save(Guid userId,ProfileDto d,CancellationToken ct){
  var user=await db.Users.Include(x=>x.Employee).SingleAsync(x=>x.Id==userId,ct);
  if(d.DisplayName.Trim().Length<2)throw new ApiException(400,"InvalidName","Tên hiển thị cần ít nhất 2 ký tự.");
  if(!string.IsNullOrWhiteSpace(d.AvatarDataUrl)){
   if(!d.AvatarDataUrl.StartsWith("data:image/jpeg;base64,"))throw new ApiException(400,"InvalidAvatar","Ảnh đại diện cần định dạng JPEG.");
   byte[] bytes;try{bytes=Convert.FromBase64String(d.AvatarDataUrl[23..]);}catch(FormatException){throw new ApiException(400,"InvalidAvatar","Ảnh không hợp lệ.");}
   if(bytes.Length<4||bytes.Length>100000||bytes[0]!=255||bytes[1]!=216||bytes[^2]!=255||bytes[^1]!=217)throw new ApiException(400,"InvalidAvatar","Ảnh cần là JPEG, tối đa 100KB.");
  }
  user.DisplayName=d.DisplayName.Trim();user.AvatarDataUrl=string.IsNullOrWhiteSpace(d.AvatarDataUrl)?null:d.AvatarDataUrl;audit.Add(userId,"User",userId,"ProfileUpdated");await db.SaveChangesAsync(ct);return AuthService.UserView(user);
 }
 private string Mac(ProfileChange c,string side,string code)=>Convert.ToHexString(HMACSHA256.HashData(Encoding.UTF8.GetBytes(config["Otp:HmacKey"]!),Encoding.UTF8.GetBytes($"Profile|{c.Id}|{c.UserId}|{c.Kind}|{c.Value}|{side}|{code}")));
 public async Task<object> Start(Guid userId,ContactChangeDto d,CancellationToken ct){
  var user=await db.Users.SingleAsync(x=>x.Id==userId,ct);
  if(hasher.VerifyHashedPassword(user,user.PasswordHash,d.Password)==PasswordVerificationResult.Failed)throw new ApiException(400,"InvalidPassword","Mật khẩu hiện tại không đúng.");
  if(d.Kind is not("Email" or "Phone"))throw new ApiException(400,"InvalidKind","Loại thay đổi không hợp lệ.");
  var value=d.Kind=="Email"?d.Value.Trim():Secrets.Phone(d.Value);
  if(d.Kind=="Email"&&(!new EmailAddressAttribute().IsValid(value)||value.Length>254))throw new ApiException(400,"InvalidEmail","Email chưa hợp lệ.");
  if(d.Kind=="Email"&&await db.Users.AnyAsync(x=>x.NormalizedEmail==Secrets.Normalize(value),ct))throw new ApiException(409,"EmailExists","Email đã được sử dụng.");
  if(await db.Set<ProfileChange>().AnyAsync(x=>x.UserId==userId&&x.CreatedAtUtc>DateTimeOffset.UtcNow.AddSeconds(-60),ct))throw new ApiException(429,"Cooldown","Chờ 60 giây trước khi gửi yêu cầu mới.");
  var change=new ProfileChange{UserId=userId,Kind=d.Kind,Value=value,OldValue=d.Kind=="Email"?user.Email:user.PhoneNumber,ExpiresAtUtc=DateTimeOffset.UtcNow.AddMinutes(5)};
  var current=RandomNumberGenerator.GetInt32(1000000).ToString("D6");var next=RandomNumberGenerator.GetInt32(1000000).ToString("D6");
  var sent=await messages.SendAsync(d.Kind=="Email"?"Email":"Sms",value,next,ct);
  if(!sent.Accepted)throw new ApiException(503,"VerificationUnavailable",d.Kind=="Phone"?"Chưa gửi được SMS xác minh số mới. Số hiện tại được giữ nguyên.":"Không gửi được mã đến email mới. Email hiện tại được giữ nguyên.");
  var old=await messages.SendAsync("Email",user.Email,current,ct);if(!old.Accepted)throw new ApiException(503,"VerificationUnavailable","Không gửi được mã xác nhận đến email hiện tại. Chưa thay đổi hồ sơ.");
  change.CurrentCodeMac=Mac(change,"current",current);change.NewCodeMac=Mac(change,"new",next);db.Add(change);audit.Add(userId,"User",userId,"ContactChangeRequested",new{d.Kind});await db.SaveChangesAsync(ct);return new{id=change.Id,change.ExpiresAtUtc,currentDestination="Email hiện tại",newDestination=d.Kind=="Email"?"Email mới":"Số điện thoại mới"};
 }
 public async Task<object> Confirm(Guid userId,ContactConfirmDto d,CancellationToken ct){
  await using var tx=await db.Database.BeginTransactionAsync(System.Data.IsolationLevel.Serializable,ct);
  var change=await db.Set<ProfileChange>().FromSqlInterpolated($"SELECT * FROM ProfileChanges WITH (UPDLOCK, ROWLOCK) WHERE Id={d.Id}").SingleOrDefaultAsync(x=>x.UserId==userId,ct)??throw CatalogService.Missing();
  if(change.Status!="Pending"||change.Kind=="LegalName"||change.ExpiresAtUtc<=DateTimeOffset.UtcNow)throw new ApiException(410,"ChangeExpired","Yêu cầu hết hạn hoặc đã xử lý.");
  if(change.FailedAttempts>=5)throw new ApiException(429,"OtpLocked","Đã nhập sai quá số lần cho phép.");
  if(!Secrets.Equal(change.CurrentCodeMac!,Mac(change,"current",d.CurrentCode))||!Secrets.Equal(change.NewCodeMac!,Mac(change,"new",d.NewCode))){change.FailedAttempts++;await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);throw new ApiException(400,"InvalidOtp","Mã xác nhận không đúng.");}
  var user=await db.Users.Include(x=>x.Employee).SingleAsync(x=>x.Id==userId,ct);
  if((change.Kind=="Email"?user.Email:user.PhoneNumber)!=change.OldValue)throw new ApiException(409,"ContactChanged","Thông tin liên hệ vừa thay đổi. Hãy tạo yêu cầu mới.");
  if(change.Kind=="Email") {if(await db.Users.AnyAsync(x=>x.Id!=userId&&x.NormalizedEmail==Secrets.Normalize(change.Value),ct))throw new ApiException(409,"EmailExists","Email đã được sử dụng.");user.Email=change.Value;user.NormalizedEmail=Secrets.Normalize(change.Value);user.EmailConfirmed=true;if(user.Employee is not null)user.Employee.InvitationEmail=change.Value;}
  else{user.PhoneNumber=change.Value;user.PhoneNumberConfirmed=true;if(user.Employee is not null)user.Employee.InvitationPhone=change.Value;}
  change.Status="Completed";change.CurrentCodeMac=null;change.NewCodeMac=null;
  await db.AuthSessions.Where(x=>x.UserId==userId).ExecuteUpdateAsync(x=>x.SetProperty(y=>y.RevokedAtUtc,(DateTimeOffset?)DateTimeOffset.UtcNow),ct);
  await db.Set<RememberedDevice>().Where(x=>x.UserId==userId).ExecuteUpdateAsync(x=>x.SetProperty(y=>y.RevokedAtUtc,(DateTimeOffset?)DateTimeOffset.UtcNow),ct);
  audit.Add(userId,"User",userId,"ContactChanged",new{change.Kind});await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);return new{status="Completed",requiresLogin=true};
 }
 public async Task<object> RequestName(Guid user,LegalNameDto d,CancellationToken ct){
  if(d.FullName.Trim().Length<2)throw new ApiException(400,"InvalidName","Họ tên chưa hợp lệ.");
  if(await db.Set<ProfileChange>().AnyAsync(x=>x.UserId==user&&x.Kind=="LegalName"&&x.Status=="Pending",ct))throw new ApiException(409,"NameRequestPending","Bạn đã có yêu cầu đổi họ tên chờ duyệt.");
  var item=new ProfileChange{UserId=user,Kind="LegalName",Value=d.FullName.Trim(),ExpiresAtUtc=DateTimeOffset.UtcNow.AddDays(30)};db.Add(item);audit.Add(user,"User",user,"NameChangeRequested");await db.SaveChangesAsync(ct);return new{id=item.Id,item.Status};
 }
 public async Task<object> ReviewName(Guid actor,Guid id,bool approve,string reason,CancellationToken ct){
  await using var tx=await db.Database.BeginTransactionAsync(System.Data.IsolationLevel.Serializable,ct);var item=await db.Set<ProfileChange>().FromSqlInterpolated($"SELECT * FROM ProfileChanges WITH (UPDLOCK, ROWLOCK) WHERE Id={id}").Include(x=>x.User).ThenInclude(x=>x.Employee).SingleOrDefaultAsync(ct)??throw CatalogService.Missing();
  if(item.Kind!="LegalName"||item.Status!="Pending"||item.ExpiresAtUtc<=DateTimeOffset.UtcNow)throw new ApiException(409,"AlreadyReviewed","Yêu cầu không còn chờ duyệt.");
  if(approve){item.User.FullName=item.Value;if(item.User.Employee is not null)item.User.Employee.FullName=item.Value;}item.Status=approve?"Approved":"Rejected";item.DecisionReason=reason.Trim();audit.Add(actor,"ProfileChange",id,item.Status);await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);return new{item.Status};
 }
}
