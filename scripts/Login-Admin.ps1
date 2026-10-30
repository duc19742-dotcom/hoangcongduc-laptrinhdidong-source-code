$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$settings=Get-Content -LiteralPath (Join-Path $projectRoot '.local\secrets.json') -Raw | ConvertFrom-Json
if (!$settings.Bootstrap -or !$settings.Hosting) {throw 'Configure Admin and Hosting first.'}
$base=$settings.Hosting.ApiBaseUrl.TrimEnd('/')+'/api/v1'
function Post-Api([string]$path,$body) {
 try {return Invoke-RestMethod -Method Post -Uri ($base+$path) -ContentType 'application/json; charset=utf-8' -Body ($body|ConvertTo-Json -Depth 6)}
 catch {if($_.ErrorDetails.Message){try{$problem=$_.ErrorDetails.Message|ConvertFrom-Json;if($problem.detail){throw $problem.detail}}catch{throw $_}};throw 'API request failed. Check the server and try again.'}
}
try {
 for($stage=0;$stage -lt 2;$stage++) {
  $flow=Post-Api '/auth/login' @{username='admin';password=$settings.Bootstrap.Password}
  $delivery=Post-Api '/auth/otp/send' @{flowId=$flow.flowId;flowToken=$flow.flowToken;channel='Email'}
  Write-Host ('Email OTP accepted by provider. Check '+$flow.maskedEmail+' including Spam.')
  $secureOtp=Read-Host 'Enter the six-digit OTP received in your email' -AsSecureString
  $otp=[System.Net.NetworkCredential]::new('',$secureOtp).Password
  $route=if($flow.purpose -eq 'VerifyEmail'){'/auth/email-verification/verify'}else{'/auth/login/otp/verify'}
  $result=Post-Api $route @{flowId=$flow.flowId;flowToken=$flow.flowToken;challengeId=$delivery.challengeId;code=$otp}
  if($flow.purpose -eq 'VerifyEmail'){Write-Host 'Admin email verified. One more OTP will complete the login.';continue}
  if($result.user.role -ne 'Admin'){throw 'The authenticated account is not an Admin.'}
  $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $projectRoot '.local\admin-session.json') -Encoding UTF8
  Write-Host 'Real OTP login SUCCESS. The short-lived session was saved locally; token not printed.' -ForegroundColor Green
  break
 }
} catch {Write-Host ('Login failed: '+$_.Exception.Message) -ForegroundColor Red}
Read-Host 'Press Enter to close this window'
