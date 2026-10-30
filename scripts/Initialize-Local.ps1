$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$localPath = Join-Path $projectRoot '.local'
New-Item -ItemType Directory -Path $localPath -Force | Out-Null
$secretPath = Join-Path $localPath 'secrets.json'
if (Test-Path -LiteralPath $secretPath) { Write-Output 'Local settings preserved.'; exit 0 }
$settings = @{
    ConnectionStrings = @{ DefaultConnection = 'Server=(localdb)\MSSQLLocalDB;Database=DucAttendance;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;MultipleActiveResultSets=False' }
    Jwt = @{ Issuer='DucAttendance'; Audience='DucAttendance.Mobile'; SigningKey='' }
    Otp = @{ HmacKey='' }
}
$random = [Security.Cryptography.RandomNumberGenerator]::Create()
$jwtBytes = New-Object byte[] 48; $random.GetBytes($jwtBytes)
$otpBytes = New-Object byte[] 48; $random.GetBytes($otpBytes)
$random.Dispose()
$settings.Jwt.SigningKey = [Convert]::ToBase64String($jwtBytes)
$settings.Otp.HmacKey = [Convert]::ToBase64String($otpBytes)
$settings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $secretPath -Encoding UTF8
Write-Output 'Configured LocalDB and random security keys. No credentials printed.'
