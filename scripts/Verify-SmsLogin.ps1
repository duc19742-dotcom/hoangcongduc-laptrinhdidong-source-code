$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$settings=Get-Content -LiteralPath (Join-Path $root '.local\secrets.json') -Raw | ConvertFrom-Json
$base=$settings.Hosting.ApiBaseUrl+'/api/v1'
function Post-Api([string]$path,$body){
 try{return Invoke-RestMethod -Method Post -Uri ($base+$path) -ContentType 'application/json; charset=utf-8' -Body ($body|ConvertTo-Json -Depth 6)}
 catch{
  $raw=$_.ErrorDetails.Message;$httpStatus=0
  if($_.Exception.Response){$httpStatus=[int]$_.Exception.Response.StatusCode;if(!$raw){try{$reader=[System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream());$raw=$reader.ReadToEnd();$reader.Dispose()}catch{}}}
  $problem=$null;if($raw){try{$problem=$raw|ConvertFrom-Json}catch{}}
  if($problem.code){throw ('HTTP '+$httpStatus+' '+$problem.code+': '+$problem.detail)}
  throw ('HTTP '+$httpStatus+' API temporarily unavailable. No automatic SMS retry was made.')
 }
}
function Receive-Code($flow,[string]$route){
 $sent=Post-Api '/auth/otp/send' @{flowId=$flow.flowId;flowToken=$flow.flowToken;channel='Sms'}
 Write-Host ('SMS accepted by provider for '+$flow.maskedPhone+'. Check the actual phone; acceptance alone does not prove receipt.')
 for($attempt=0;$attempt -lt 5;$attempt++){
  $secureCode=Read-Host 'Enter the six-digit OTP actually received by SMS' -AsSecureString
  $code=[System.Net.NetworkCredential]::new('',$secureCode).Password
  try{return Post-Api $route @{flowId=$flow.flowId;flowToken=$flow.flowToken;challengeId=$sent.challengeId;code=$code}}
  catch{if($_.Exception.Message -like '*InvalidOtp*' -and $attempt -lt 4){Write-Host 'Incorrect code. Try again without requesting a new SMS.';continue};throw}
 }
}
try{
 $flow=Post-Api '/auth/login' @{username='admin';password=$settings.Bootstrap.Password}
 if(!$flow.phoneVerified){
  $phoneFlow=Post-Api '/auth/phone-verification/start' @{flowId=$flow.flowId;flowToken=$flow.flowToken}
  $verified=Receive-Code $phoneFlow '/auth/phone-verification/verify'
  Write-Host 'Phone verification through a real received SMS: SUCCESS' -ForegroundColor Green
  $flow=Post-Api '/auth/login' @{username='admin';password=$settings.Bootstrap.Password}
 }
 $session=Receive-Code $flow '/auth/login/otp/verify'
 if(!$session.accessToken){throw 'JWT was not issued.'}
 $session|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $root '.local\admin-session.json') -Encoding UTF8
 [pscustomobject]@{verifiedAtUtc=[DateTimeOffset]::UtcNow.ToString('o');channel='Sms';phoneConfirmed=$session.user.phoneNumberConfirmed;role=$session.user.role;receivedOtpVerified=$true}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root '.local\sms-verification.json') -Encoding UTF8
 Write-Host 'Real SMS OTP login SUCCESS. JWT saved locally; no code/token was printed.' -ForegroundColor Green
}catch{Write-Host ('SMS verification failed: '+$_.Exception.Message) -ForegroundColor Red}
Read-Host 'Press Enter to close this window'
