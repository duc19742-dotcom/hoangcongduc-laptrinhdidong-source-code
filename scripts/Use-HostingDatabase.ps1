param([ValidateSet('Migrate','Bootstrap')][string]$Action='Migrate')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$settings=Get-Content -LiteralPath (Join-Path $projectRoot '.local\secrets.json') -Raw | ConvertFrom-Json
if (!$settings.Hosting) { throw 'Configure Hosting first.' }
$connection=[System.Data.Common.DbConnectionStringBuilder]::new()
$connection['Server']=$settings.Hosting.SqlHost
$connection['Database']=$settings.Hosting.SqlDatabase
$connection['User ID']=$settings.Hosting.SqlUser
$connection['Password']=$settings.Hosting.SqlPassword
$connection['Encrypt']=$true
$connection['TrustServerCertificate']=$false
$env:ConnectionStrings__DefaultConnection=$connection.ConnectionString
Push-Location (Join-Path $projectRoot 'backend\Attendance.Api')
try {
 if ($Action -eq 'Migrate') { dotnet ef database update -- --Logging:LogLevel:Microsoft.EntityFrameworkCore.Database.Command=Warning }
 else { dotnet run --no-build --launch-profile http -- --bootstrap-admin }
 if ($LASTEXITCODE -ne 0) { throw 'Hosting database operation failed. Credentials were not printed.' }
} finally { Pop-Location; Remove-Item Env:\ConnectionStrings__DefaultConnection -ErrorAction SilentlyContinue }
