using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using MailKit.Net.Smtp;
using MailKit.Security;
using MimeKit;
namespace Attendance.Api.Services;

public sealed record DeliveryResult(bool Accepted, string Status, string? MessageId = null, string? ErrorCode = null);
public interface IMessageSender { Task<DeliveryResult> SendAsync(string channel,string destination,string code,CancellationToken ct); }
public sealed class MessageSender(IConfiguration config,IHttpClientFactory clients,ILogger<MessageSender>? logger=null) : IMessageSender
{
    public async Task<DeliveryResult> SendAsync(string channel,string destination,string code,CancellationToken ct)
    {
        try
        {
            if (channel=="Email")
            {
                var host=config["Smtp:Host"]; var username=config["Smtp:Username"]; var password=config["Smtp:Password"]; var from=config["Smtp:From"]??username;
                if (string.IsNullOrWhiteSpace(host)||string.IsNullOrWhiteSpace(username)||string.IsNullOrWhiteSpace(password)||string.IsNullOrWhiteSpace(from)) return new(false,"NotConfigured",ErrorCode:"EmailNotConfigured");
                var message=new MimeMessage(); message.From.Add(new MailboxAddress("Đức Attendance",from)); message.To.Add(MailboxAddress.Parse(destination));
                message.Subject="Mã xác minh Đức Attendance";
                message.Body=new TextPart("plain") { Text=$"Mã xác minh của bạn: {code}\nMã hết hạn sau 5 phút. Không chia sẻ mã. Nếu không yêu cầu, hãy bỏ qua email này." };
                using var smtp=new SmtpClient { Timeout=20000 }; var port=config.GetValue("Smtp:Port",587);
                await smtp.ConnectAsync(host,port,port==465?SecureSocketOptions.SslOnConnect:SecureSocketOptions.StartTls,ct);
                await smtp.AuthenticateAsync(username,password,ct); await smtp.SendAsync(message,ct); await smtp.DisconnectAsync(true,ct);
                return new(true,"ProviderAccepted",message.MessageId);
            }
            if (channel!="Sms") return new(false,"Failed",ErrorCode:"UnsupportedChannel");
            if(!string.IsNullOrWhiteSpace(config["SpeedSms:AccessToken"]))return await SpeedSms(destination,code,ct);
            var sid=config["Twilio:AccountSid"]; var token=config["Twilio:AuthToken"]; var sender=config["Twilio:From"];
            if (string.IsNullOrWhiteSpace(sid)||string.IsNullOrWhiteSpace(token)||string.IsNullOrWhiteSpace(sender)) return new(false,"NotConfigured",ErrorCode:"SmsNotConfigured");
            using var request=new HttpRequestMessage(HttpMethod.Post,$"https://api.twilio.com/2010-04-01/Accounts/{Uri.EscapeDataString(sid)}/Messages.json");
            request.Headers.Authorization=new AuthenticationHeaderValue("Basic",Convert.ToBase64String(Encoding.UTF8.GetBytes($"{sid}:{token}")));
            request.Content=new FormUrlEncodedContent(new Dictionary<string,string> { ["To"]=destination,["From"]=sender,["Body"]=$"Duc Attendance: {code} la ma xac minh cua ban. Ma het han sau 5 phut. Khong chia se ma." });
            using var response=await clients.CreateClient("Messaging").SendAsync(request,ct);
            using var json=JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
            if (!response.IsSuccessStatusCode||!json.RootElement.TryGetProperty("sid",out var id)) return new(false,"Failed",ErrorCode:"SmsProviderRejected");
            return new(true,"ProviderAccepted",id.GetString());
        }
        catch(Exception ex) when(ex is not OperationCanceledException||!ct.IsCancellationRequested)
        { return new(false,"Failed",ErrorCode:channel=="Email"?"EmailProviderRejected":"SmsProviderUnavailable"); }
    }

    private async Task<DeliveryResult> SpeedSms(string destination,string code,CancellationToken ct)
    {
        var apiToken=config["SpeedSms:AccessToken"]!;
        var smsType=config.GetValue("SpeedSms:SmsType",4);
        if(smsType is not(3 or 4 or 6))return new(false,"Failed",ErrorCode:"InvalidSmsType");
        using var request=new HttpRequestMessage(HttpMethod.Post,"https://api.speedsms.vn/index.php/sms/send");
        request.Headers.Authorization=new AuthenticationHeaderValue("Basic",Convert.ToBase64String(Encoding.UTF8.GetBytes(apiToken+":x")));
        request.Content=JsonContent.Create(new{to=new[]{destination},content=$"Ma xac minh Duc Attendance: {code}. Ma het han sau 5 phut. Khong chia se ma.",sms_type=smsType,sender=config["SpeedSms:Sender"]??""});
        using var response=await clients.CreateClient("Messaging").SendAsync(request,ct);
        using var result=JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));var root=result.RootElement;
        // Log diagnostic metadata only, never the provider body or SMS contents.
        var statusText=root.TryGetProperty("status",out var diagnosticStatus)?diagnosticStatus.ToString():"missing";
        var codeText=root.TryGetProperty("code",out var diagnosticCode)?diagnosticCode.ToString():"missing";
        var totalText=root.TryGetProperty("data",out var diagnosticData)&&diagnosticData.TryGetProperty("totalSMS",out var diagnosticTotal)?diagnosticTotal.ToString():"missing";
        static string Safe(string value)=>new(value.Where(char.IsAsciiLetterOrDigit).Take(20).ToArray());
        logger?.LogInformation("SpeedSMS HTTP {HttpStatus}, status {ProviderStatus}, code {ProviderCode}, totalSMS {Total}",(int)response.StatusCode,Safe(statusText),Safe(codeText),Safe(totalText));
        // Return only the provider's numeric diagnostic code. Never surface its raw
        // response, destination, access token, or OTP in an API error or log.
        if(root.TryGetProperty("status",out var providerStatus)&&providerStatus.GetString()=="error")
        {
            if(root.TryGetProperty("message",out var message)&&message.ValueKind==JsonValueKind.String&&message.GetString()=="sender not found")
                return new(false,"Failed",ErrorCode:"SmsSenderNotConfigured");
            var providerCode=root.TryGetProperty("code",out var error)?error.ToString():"";
            return new(false,"Failed",ErrorCode:providerCode.Length is >=1 and <=4&&providerCode.All(char.IsAsciiDigit)?"SpeedSmsRejected_"+providerCode:"SmsProviderRejected");
        }
        if(!response.IsSuccessStatusCode||!root.TryGetProperty("status",out var status)||status.GetString()!="success"||!root.TryGetProperty("data",out var data)||!data.TryGetProperty("tranId",out var id)||data.TryGetProperty("totalSMS",out var total)&&total.TryGetInt32(out var count)&&count<1)
            return new(false,"Failed",ErrorCode:"SmsProviderRejected");
        return new(true,"ProviderAccepted",id.ToString());
    }
}
