using System.Net;
using System.Text;
using System.Text.Json;
using Attendance.Api.Services;
using Microsoft.Extensions.Configuration;

namespace Attendance.Api.Tests;

// Contract tests only: these never contact a real SMS provider or prove delivery.
public sealed class MessageSenderTests
{
 private sealed class Transport(string body) : HttpMessageHandler, IHttpClientFactory
 {
  public int Calls;
  public HttpClient CreateClient(string name)=>new(this,false);
  protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken ct)
  {
   Calls++;
   Assert.Equal("https://api.speedsms.vn/index.php/sms/send",request.RequestUri!.AbsoluteUri);
   Assert.Equal("Basic",request.Headers.Authorization!.Scheme);
   Assert.Equal("test-token:x",Encoding.UTF8.GetString(Convert.FromBase64String(request.Headers.Authorization.Parameter!)));
   using var json=JsonDocument.Parse(await request.Content!.ReadAsStringAsync(ct));
   Assert.Equal(4,json.RootElement.GetProperty("sms_type").GetInt32());
   Assert.Contains("123456",json.RootElement.GetProperty("content").GetString());
   Assert.Equal("+84901234567",json.RootElement.GetProperty("to")[0].GetString());
   return new(HttpStatusCode.OK){Content=new StringContent(body,Encoding.UTF8,"application/json")};
  }
 }
 private static IConfiguration Config(int type=4)=>new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>{{"SpeedSms:AccessToken","test-token"},{"SpeedSms:SmsType",type.ToString()}}).Build();
 [Theory]
 [InlineData("{\"status\":\"success\",\"data\":{\"tranId\":123,\"totalSMS\":1}}",true)]
 [InlineData("{\"status\":\"error\",\"code\":\"009\"}",false)]
 [InlineData("{\"status\":\"success\",\"data\":{\"tranId\":123,\"totalSMS\":0}}",false)]
 [InlineData("{\"status\":\"success\",\"data\":{\"totalSMS\":1}}",false)]
 [InlineData("<html>Service unavailable</html>",false)]
 public async Task ProviderResponseMustAcceptAtLeastOneMessage(string body,bool accepted)
 {
  var transport=new Transport(body);var result=await new MessageSender(Config(),transport).SendAsync("Sms","+84901234567","123456",default);
  Assert.Equal(accepted,result.Accepted);Assert.Equal(1,transport.Calls);
  if(accepted)Assert.Equal("ProviderAccepted",result.Status);
 }
 [Fact]public async Task AndroidGatewayTypeIsNotAllowed()
 {
  var transport=new Transport("{}");var result=await new MessageSender(Config(5),transport).SendAsync("Sms","+84901234567","123456",default);
  Assert.False(result.Accepted);Assert.Equal("InvalidSmsType",result.ErrorCode);Assert.Equal(0,transport.Calls);
 }
 [Fact]public async Task MissingProviderSenderIsReportedWithoutClaimingDelivery()
 {
  var transport=new Transport("{\"status\":\"error\",\"message\":\"sender not found\"}");
  var result=await new MessageSender(Config(),transport).SendAsync("Sms","+84901234567","123456",default);
  Assert.False(result.Accepted);Assert.Equal("SmsSenderNotConfigured",result.ErrorCode);Assert.Null(result.MessageId);
 }
 [Fact]public async Task OnlyNumericProviderCodeCanBeReturnedToTheCaller()
 {
  var transport=new Transport("{\"status\":\"error\",\"code\":\"009\",\"message\":\"test-token 123456\"}");
  var result=await new MessageSender(Config(),transport).SendAsync("Sms","+84901234567","123456",default);
  Assert.False(result.Accepted);Assert.Equal("SpeedSmsRejected_009",result.ErrorCode);
 }
}
