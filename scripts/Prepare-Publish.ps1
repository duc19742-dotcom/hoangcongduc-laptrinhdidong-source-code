$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$settings=Get-Content -LiteralPath (Join-Path $projectRoot '.local\secrets.json') -Raw | ConvertFrom-Json
if (!$settings.Hosting -or !$settings.Smtp) { throw 'Configure Hosting and Email first.' }
Push-Location $projectRoot
try {
 dotnet publish backend\Attendance.Api\Attendance.Api.csproj --configuration Release --no-self-contained --output .local\publish --verbosity quiet
 if($LASTEXITCODE -ne 0){throw 'Publish build failed.'}
 $connection=[System.Data.Common.DbConnectionStringBuilder]::new()
 $connection['Server']=$settings.Hosting.SqlHost; $connection['Database']=$settings.Hosting.SqlDatabase
 $connection['User ID']=$settings.Hosting.SqlUser; $connection['Password']=$settings.Hosting.SqlPassword
 $connection['Encrypt']=$true; $connection['TrustServerCertificate']=$false
 $production=@{ConnectionStrings=@{DefaultConnection=$connection.ConnectionString};Jwt=$settings.Jwt;Otp=$settings.Otp;Smtp=$settings.Smtp;Swagger=@{Enabled=$true};Logging=@{LogLevel=@{Default='Warning';'Microsoft.AspNetCore'='Warning'}}}
 if($settings.Twilio){$production.Twilio=$settings.Twilio}
 if($settings.SpeedSms){$production.SpeedSms=$settings.SpeedSms}
 if($settings.Firebase){$production.Firebase=$settings.Firebase}
 if($settings.Sms){$production.Sms=$settings.Sms}
 $production | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath '.local\publish\appsettings.Production.json' -Encoding UTF8
 Write-Output 'Publish directory prepared. Production settings include application credentials only; no Admin/FTP password or local signing key.'
} finally {Pop-Location}
