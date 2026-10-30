$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$private=Join-Path $root '.local'
$settings=Get-Content -LiteralPath (Join-Path $private 'secrets.json') -Raw|ConvertFrom-Json
$fix=Get-Content -LiteralPath (Join-Path $private 'device-position-to-apply.json') -Raw|ConvertFrom-Json
if([DateTimeOffset]$fix.receivedAtUtc -lt [DateTimeOffset]::UtcNow.AddMinutes(-30) -or $fix.accuracyMeters -gt 50){throw 'Phone GPS evidence is too old or not accurate enough. Take a fresh GPS fix on Android first.'}
$base=$settings.Hosting.ApiBaseUrl+'/api/v1'
$script:jwt=$null
function Api([string]$method,[string]$path,$body=$null,[bool]$authenticated=$true){
 $options=@{Method=$method;Uri=$base+$path;ContentType='application/json; charset=utf-8'}
 if($authenticated){$options.Headers=@{Authorization='Bearer '+$script:jwt}}
 if($null -ne $body){$options.Body=[System.Text.Encoding]::UTF8.GetBytes(($body|ConvertTo-Json -Depth 8))}
 try{Invoke-RestMethod @options}catch{throw ('API failed with HTTP '+[int]$_.Exception.Response.StatusCode+'. No location was changed by this script after that failure.')}
}
$sessionPath=Join-Path $private 'admin-session.json'
if(Test-Path -LiteralPath $sessionPath){$session=Get-Content -LiteralPath $sessionPath -Raw|ConvertFrom-Json}
if(!$session -or [DateTimeOffset]$session.expiresAtUtc -lt [DateTimeOffset]::UtcNow.AddMinutes(2)){
 $flow=Api POST '/auth/login' @{username='admin';password=$settings.Bootstrap.Password} $false
 $sent=Api POST '/auth/otp/send' @{flowId=$flow.flowId;flowToken=$flow.flowToken;channel='Email'} $false
 Write-Host 'Check your Admin email. Enter the actual OTP privately below.'
 $code=[System.Net.NetworkCredential]::new('',(Read-Host 'Admin Email OTP' -AsSecureString)).Password
 $session=Api POST '/auth/login/otp/verify' @{flowId=$flow.flowId;flowToken=$flow.flowToken;challengeId=$sent.challengeId;code=$code} $false
 $session|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $sessionPath -Encoding UTF8
}
$script:jwt=$session.accessToken
if($session.user.role -ne 'Admin'){throw 'Admin role required.'}
$location=Api GET ('/work-locations/'+$fix.locationId)
$updated=Api PUT ('/work-locations/'+$fix.locationId) @{name=$location.name;latitude=$fix.latitude;longitude=$fix.longitude;radiusMeters=$location.radiusMeters;maxAccuracyMeters=$location.maxAccuracyMeters;isActive=$location.isActive;rowVersion=$location.rowVersion}
[pscustomobject]@{updatedAtUtc=[DateTimeOffset]::UtcNow.ToString('o');locationId=$location.id;oldPolicyVersion=$location.policyVersion;newPolicyVersion=$updated.policyVersion;source='Real Android GPS from the authenticated attendance attempt';sampleAccuracyMeters=$fix.accuracyMeters}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $private 'demo-location-fix.json') -Encoding UTF8
Write-Host 'SAVED: demo location now uses the real Android GPS evidence. Radius/accuracy limits were preserved; the old attempt snapshot was not edited.' -ForegroundColor Green
