using System.Data;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Attendance.Api.Data;
using Attendance.Api.DTOs;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
namespace Attendance.Api.Services;

public sealed class AuthService(AttendanceDbContext db,IPasswordHasher<AppUser> hasher,IConfiguration config,IMessageSender sender,AuditService audit)
{
    private static DateTimeOffset Now=>DateTimeOffset.UtcNow;
    private static string MaskEmail(string email) { var at=email.IndexOf('@'); return at>0?email[..1]+"***"+email[at..]:"***"; }
    private static string MaskPhone(string phone)=>phone.Length>=4?"***"+phone[^4..]:"***";
    public static object UserView(AppUser u)=>new { u.Id,u.FullName,u.DisplayName,u.AvatarDataUrl,username=u.UserName,u.Email,maskedPhone=MaskPhone(u.PhoneNumber),u.Role,u.ApprovalStatus,u.EmailConfirmed,u.PhoneNumberConfirmed,employeeId=u.Employee?.Id };
    private object NewFlow(AppUser user,string purpose)
    {
        var token=Secrets.NewToken(); var flow=new AuthFlow { UserId=user.Id,TokenHash=Secrets.Hash(token),Purpose=purpose,ExpiresAtUtc=Now.AddMinutes(15) }; db.AuthFlows.Add(flow);
        return new { flowId=flow.Id,flowToken=token,purpose,expiresAtUtc=flow.ExpiresAtUtc,
            smsProvider=config["Sms:Provider"]??"Backend",
            availableChannels=purpose=="VerifyPhone"?new[]{"Sms"}:purpose=="Login"&&(user.PhoneNumberConfirmed||config["Sms:Provider"]=="Firebase")?new[]{"Email","Sms"}:new[]{"Email"},
            maskedEmail=MaskEmail(user.Email),maskedPhone=MaskPhone(user.PhoneNumber),phoneVerified=user.PhoneNumberConfirmed };
    }
    public async Task<object> Register(RegisterDto dto,CancellationToken ct)
    {
        Secrets.Password(dto.Password,dto.ConfirmPassword); var name=Secrets.Normalize(dto.Username); var email=Secrets.Normalize(dto.Email);
        if(await db.Users.AnyAsync(x=>x.NormalizedUserName==name||x.NormalizedEmail==email,ct)) throw new ApiException(409,"AccountExists","Tên đăng nhập hoặc email đã tồn tại.");
        var user=new AppUser { FullName=dto.FullName.Trim(),UserName=dto.Username.Trim(),NormalizedUserName=name,Email=dto.Email.Trim(),NormalizedEmail=email,PhoneNumber=Secrets.Phone(dto.Phone) };
        user.PasswordHash=hasher.HashPassword(user,dto.Password); db.Users.Add(user); var result=NewFlow(user,"VerifyEmail"); audit.Add(user.Id,"User",user.Id,"Registered"); await db.SaveChangesAsync(ct); return result;
    }
    public async Task<object> Login(LoginDto dto,CancellationToken ct)
    {
        var name=Secrets.Normalize(dto.Username); var user=await db.Users.Include(x=>x.Employee).FirstOrDefaultAsync(x=>x.NormalizedUserName==name,ct);
        if(user is null||hasher.VerifyHashedPassword(user,user.PasswordHash,dto.Password)==PasswordVerificationResult.Failed) throw new ApiException(401,"InvalidCredentials","Tên đăng nhập hoặc mật khẩu không đúng.");
        if(!user.IsActive) throw new ApiException(403,"AccountInactive","Tài khoản đã bị khóa.");
        var purpose=user.EmailConfirmed?"Login":"VerifyEmail"; if(purpose=="Login") RequireApproved(user);
        var result=NewFlow(user,purpose); await db.SaveChangesAsync(ct); return result;
    }
    public async Task<object> Forgot(ForgotDto dto,CancellationToken ct)
    {
        var email=Secrets.Normalize(dto.Email); var user=await db.Users.FirstOrDefaultAsync(x=>x.NormalizedEmail==email&&x.EmailConfirmed&&x.IsActive,ct);
        if(user is null) return new {flowId=Guid.NewGuid(),flowToken=Secrets.NewToken(),purpose="ResetPassword",expiresAtUtc=Now.AddMinutes(15),availableChannels=new[]{"Email"},maskedEmail=MaskEmail(dto.Email),maskedPhone="***",phoneVerified=false};
        var result=NewFlow(user,"ResetPassword"); await db.SaveChangesAsync(ct); return result;
    }
    public async Task<AuthFlow> LoadFlow(FlowDto dto,CancellationToken ct)
    {
        var flow=await db.AuthFlows.Include(x=>x.User).ThenInclude(x=>x.Employee).FirstOrDefaultAsync(x=>x.Id==dto.FlowId,ct);
        if(flow is null||!Secrets.Equal(flow.TokenHash,Secrets.Hash(dto.FlowToken))) throw new ApiException(400,"InvalidFlow","Phiên xác minh không hợp lệ. Hãy thực hiện lại.");
        if(flow.ExpiresAtUtc<=Now||flow.UsedAtUtc.HasValue) throw new ApiException(410,"FlowExpired","Phiên xác minh đã hết hạn hoặc đã sử dụng.");
        if(!flow.User.IsActive) throw new ApiException(403,"AccountInactive","Tài khoản đã bị khóa."); return flow;
    }
    public async Task<object> StartPhone(FlowDto dto,CancellationToken ct)
    {
        var flow=await LoadFlow(dto,ct); if(flow.Purpose!="Login"||!flow.User.EmailConfirmed) throw new ApiException(403,"InvalidPurpose","Cần xác minh email và đăng nhập trước khi xác minh điện thoại.");
        RequireApproved(flow.User); var result=NewFlow(flow.User,"VerifyPhone"); await db.SaveChangesAsync(ct); return result;
    }
    public async Task<object> Send(SendOtpDto dto,CancellationToken ct)
    {
        if(dto.Channel is not("Email" or "Sms")) throw new ApiException(400,"InvalidChannel","Chỉ hỗ trợ Email hoặc SMS.");
        if(dto.Channel=="Sms"&&config["Sms:Provider"]=="Firebase")throw new ApiException(400,"UseFirebaseSms","Ứng dụng cần xác minh SMS qua Firebase.");
        AuthFlow flow; OtpChallenge challenge; string code;
        await using(var tx=await db.Database.BeginTransactionAsync(IsolationLevel.Serializable,ct))
        {
            flow=await LoadFlow(dto,ct);
            if(dto.Channel=="Sms"&&flow.Purpose!="VerifyPhone"&&(flow.Purpose!="Login"||!flow.User.PhoneNumberConfirmed)) throw new ApiException(403,"PhoneNotVerified","Cần xác minh số điện thoại trước khi đăng nhập SMS.");
            if(flow.Purpose=="VerifyPhone"&&dto.Channel!="Sms") throw new ApiException(400,"InvalidChannel","Xác minh điện thoại cần SMS.");
            if(flow.LastSentAtUtc.HasValue&&flow.LastSentAtUtc.Value.AddSeconds(60)>Now) throw new ApiException(429,"ResendCooldown","Hãy chờ 60 giây giữa hai lần gửi mã.");
            var since=Now.AddHours(-1);
            var dayStart=new DateTimeOffset(Now.UtcDateTime.Date,TimeSpan.Zero);
            if(dto.Channel=="Sms"&&await db.OtpChallenges.CountAsync(x=>x.Channel=="Sms"&&x.CreatedAtUtc>=dayStart,ct)>=config.GetValue("Sms:DailyLimit",10))throw new ApiException(429,"SmsDailyLimit","Đã đạt giới hạn SMS trong ngày. Hãy dùng Email OTP hoặc liên hệ quản trị viên.");
            if(flow.SendCount>=3||await db.OtpChallenges.CountAsync(x=>x.UserId==flow.UserId&&x.Channel==dto.Channel&&x.CreatedAtUtc>since,ct)>=10) throw new ApiException(429,"OtpLimit","Bạn đã yêu cầu quá nhiều mã qua kênh này. Hãy thử lại sau.");
            code=RandomNumberGenerator.GetInt32(0,1000000).ToString("D6"); var target=dto.Channel=="Email"?flow.User.Email:flow.User.PhoneNumber;
            challenge=new OtpChallenge {FlowId=flow.Id,UserId=flow.UserId,Purpose=flow.Purpose,Channel=dto.Channel,DestinationDigest=Secrets.Hash(target),ExpiresAtUtc=Now.AddMinutes(5)};
            challenge.CodeMac=Mac(challenge,code); flow.SendCount++; flow.LastSentAtUtc=Now; db.OtpChallenges.Add(challenge); await db.SaveChangesAsync(ct); await tx.CommitAsync(ct);
        }
        var destination=dto.Channel=="Email"?flow.User.Email:flow.User.PhoneNumber;
        var delivery=await sender.SendAsync(dto.Channel,destination,code,ct); challenge.DeliveryStatus=delivery.Status; challenge.ProviderMessageId=delivery.MessageId;
        if(delivery.Accepted) await db.OtpChallenges.Where(x=>x.FlowId==flow.Id&&x.Id!=challenge.Id&&!x.ConsumedAtUtc.HasValue&&!x.SupersededAtUtc.HasValue).ExecuteUpdateAsync(s=>s.SetProperty(x=>x.SupersededAtUtc,(DateTimeOffset?)Now),ct);
        await db.SaveChangesAsync(ct);
        if(!delivery.Accepted) throw new ApiException(503,delivery.ErrorCode??"DeliveryFailed",dto.Channel=="Email"?"Chưa gửi được email. Cần kiểm tra cấu hình SMTP/dịch vụ email.":"Chưa gửi được SMS. Cần kiểm tra tài khoản, sender và quyền gửi tới số nhận.");
        return new {challengeId=challenge.Id,channel=challenge.Channel,status=delivery.Status,expiresAtUtc=challenge.ExpiresAtUtc,retryAfterSeconds=60};
    }
    private string Mac(OtpChallenge challenge,string code)
    {
        var key=config["Otp:HmacKey"]??throw new InvalidOperationException("OTP key missing.");
        return Convert.ToHexString(HMACSHA256.HashData(Encoding.UTF8.GetBytes(key),Encoding.UTF8.GetBytes($"{challenge.Id}|{challenge.UserId}|{challenge.Purpose}|{challenge.Channel}|{challenge.DestinationDigest}|{code}")));
    }
    public async Task<object> Verify(VerifyOtpDto dto,string purpose,CancellationToken ct,string? newPassword=null)
    {
        await using var tx=await db.Database.BeginTransactionAsync(IsolationLevel.Serializable,ct); var flow=await LoadFlow(dto,ct);
        if(flow.Purpose!=purpose) throw new ApiException(400,"InvalidPurpose","Mã xác minh không thuộc thao tác này.");
        var challenge=await db.OtpChallenges.FirstOrDefaultAsync(x=>x.Id==dto.ChallengeId&&x.FlowId==flow.Id,ct)??throw new ApiException(400,"InvalidOtp","Mã xác minh không hợp lệ.");
        if(challenge.ConsumedAtUtc.HasValue||challenge.SupersededAtUtc.HasValue||challenge.ExpiresAtUtc<=Now) throw new ApiException(410,"OtpExpired","Mã đã hết hạn, đã dùng hoặc đã được thay thế.");
        if(challenge.FailedAttempts>=5) throw new ApiException(429,"OtpLocked","Đã nhập sai quá số lần cho phép.");
        if(challenge.DeliveryStatus!="ProviderAccepted") throw new ApiException(400,"OtpNotDelivered","Mã chưa được dịch vụ gửi chấp nhận.");
        if(!Secrets.Equal(challenge.CodeMac,Mac(challenge,dto.Code))) {challenge.FailedAttempts++;await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);throw new ApiException(400,"InvalidOtp","Mã xác minh không đúng.");}
        var user=flow.User; var destination=challenge.Channel=="Email"?user.Email:user.PhoneNumber;
        if(!Secrets.Equal(challenge.DestinationDigest,Secrets.Hash(destination))) throw new ApiException(400,"DestinationChanged","Thông tin liên hệ đã thay đổi.");
        challenge.ConsumedAtUtc=Now; flow.UsedAtUtc=Now; object result;
        switch(purpose)
        {
            case "VerifyEmail": user.EmailConfirmed=true;result=new {status="EmailVerified",approvalStatus=user.ApprovalStatus};break;
            case "VerifyPhone": user.PhoneNumberConfirmed=true;result=new {status="PhoneVerified"};break;
            case "ResetPassword":
                await db.Set<RememberedDevice>().Where(x=>x.UserId==user.Id&&!x.RevokedAtUtc.HasValue).ExecuteUpdateAsync(s=>s.SetProperty(x=>x.RevokedAtUtc,(DateTimeOffset?)Now),ct);
                if(newPassword is null) throw new ApiException(400,"MissingPassword","Thiếu mật khẩu mới."); user.PasswordHash=hasher.HashPassword(user,newPassword);
                await db.AuthSessions.Where(x=>x.UserId==user.Id&&!x.RevokedAtUtc.HasValue).ExecuteUpdateAsync(s=>s.SetProperty(x=>x.RevokedAtUtc,(DateTimeOffset?)Now),ct);
                await db.AuthFlows.Where(x=>x.UserId==user.Id&&x.Id!=flow.Id&&!x.UsedAtUtc.HasValue).ExecuteUpdateAsync(s=>s.SetProperty(x=>x.UsedAtUtc,(DateTimeOffset?)Now),ct);
                result=new {status="PasswordReset"};break;
            case "Login": RequireApproved(user);result=IssueToken(user);break;
            default: throw new ApiException(400,"InvalidPurpose","Thao tác xác minh không hợp lệ.");
        }
        audit.Add(user.Id,"User",user.Id,purpose+"Verified");await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);return result;
    }
    internal object IssueToken(AppUser user,string method="Otp")
    {
        var jti=Secrets.NewToken();var expires=Now.AddMinutes(15);db.AuthSessions.Add(new AuthSession {UserId=user.Id,JtiHash=Secrets.Hash(jti),ExpiresAtUtc=expires,AuthenticationMethod=method});
        var claims=new[]{new Claim(ClaimTypes.NameIdentifier,user.Id.ToString()),new Claim(ClaimTypes.Name,user.UserName),new Claim(ClaimTypes.Role,user.Role),new Claim(JwtRegisteredClaimNames.Jti,jti)};
        var token=new JwtSecurityToken(config["Jwt:Issuer"],config["Jwt:Audience"],claims,expires:expires.UtcDateTime,signingCredentials:new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(config["Jwt:SigningKey"]!)),SecurityAlgorithms.HmacSha256));
        return new {accessToken=new JwtSecurityTokenHandler().WriteToken(token),tokenType="Bearer",expiresAtUtc=expires,user=UserView(user)};
    }
    public static void RequireApproved(AppUser user)
    { if(!user.IsActive||!user.EmailConfirmed||user.ApprovalStatus!="Approved"||user.Role=="Employee"&&(user.Employee is null||!user.Employee.IsActive)) throw new ApiException(403,"AccountNotApproved","Tài khoản cần được xác minh email, Admin duyệt và gắn hồ sơ nhân viên đang hoạt động."); }
    public async Task Bootstrap(CancellationToken ct)
    {
        var email=config["Bootstrap:Email"];var password=config["Bootstrap:Password"];var phone=config["Bootstrap:Phone"];
        if(string.IsNullOrWhiteSpace(email)||string.IsNullOrWhiteSpace(password)||string.IsNullOrWhiteSpace(phone)) throw new InvalidOperationException("Configure Bootstrap Email, Phone, Password first.");
        Secrets.Password(password,password);if(await db.Users.AnyAsync(x=>x.Role=="Admin",ct)) throw new InvalidOperationException("Admin already exists; bootstrap disabled.");
        var user=new AppUser {FullName="Hoàng Công Đức",UserName="admin",NormalizedUserName="ADMIN",Email=email.Trim(),NormalizedEmail=Secrets.Normalize(email),PhoneNumber=Secrets.Phone(phone),Role="Admin",ApprovalStatus="Approved"};
        user.PasswordHash=hasher.HashPassword(user,password);db.Users.Add(user);audit.Add(null,"User",user.Id,"AdminBootstrapped");await db.SaveChangesAsync(ct);
    }
}
