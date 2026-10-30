$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$settings=Get-Content -LiteralPath (Join-Path $root '.local\secrets.json') -Raw | ConvertFrom-Json
$session=Get-Content -LiteralPath (Join-Path $root '.local\admin-session.json') -Raw | ConvertFrom-Json
$headers=@{Authorization='Bearer '+$session.accessToken}
$base=$settings.Hosting.ApiBaseUrl+'/api/v1'
function Api([string]$method,[string]$path,$body=$null){
 $args=@{Method=$method;Uri=$base+$path;Headers=$headers;ContentType='application/json; charset=utf-8'}
 if($null -ne $body){$args.Body=$body|ConvertTo-Json -Depth 8}
 Invoke-RestMethod @args
}
$tag='QA'+[guid]::NewGuid().ToString('N').Substring(0,8)
$results=[System.Collections.Generic.List[string]]::new()
$dep=Api POST '/departments' @{code=$tag;name='QA CRUD temporary department'}
$dep=Api PUT ('/departments/'+$dep.id) @{code=$tag;name='QA CRUD department updated';rowVersion=$dep.rowVersion}
$loaded=Api GET ('/departments/'+$dep.id)
if($loaded.name -ne 'QA CRUD department updated'){throw 'Department update/read mismatch.'}
$results.Add('Public Department Create/Read/Update: PASS')
$emp=Api POST '/employees' @{employeeCode=$tag;fullName='QA CRUD temporary profile';email=($tag+'@example.invalid');phone='+84901234567';departmentId=$dep.id;jobTitle='Temporary API QA';hireDate='2026-10-29';isActive=$true}
$emp=Api PUT ('/employees/'+$emp.id) @{employeeCode=$tag;fullName='QA CRUD profile updated';email=($tag+'@example.invalid');phone='+84901234567';departmentId=$dep.id;jobTitle='API QA updated';hireDate='2026-10-29';isActive=$true;rowVersion=$emp.rowVersion}
$found=Api GET ('/employees?search='+$tag+'&departmentId='+$dep.id)
if($found.totalCount -ne 1){throw 'Employee search/filter mismatch.'}
$results.Add('Public Employee Create/Read/Update/Search/DepartmentFilter: PASS')
$blocked=$false
try{Api DELETE ('/departments/'+$dep.id)|Out-Null}catch{if([int]$_.Exception.Response.StatusCode -eq 409){$blocked=$true}else{throw}}
if(!$blocked){throw 'Used department deletion must fail.'}
$results.Add('Department foreign-key deletion guard: PASS (409)')
$shift=Api POST '/shifts' @{code=$tag;name='QA CRUD temporary shift';startLocalTime='08:00:00';endLocalTime='17:00:00';endsNextDay=$false;lateGraceMinutes=5;isActive=$true}
$shift=Api PUT ('/shifts/'+$shift.id) @{code=$tag;name='QA CRUD shift updated';startLocalTime='08:30:00';endLocalTime='17:30:00';endsNextDay=$false;lateGraceMinutes=10;isActive=$true;rowVersion=$shift.rowVersion}
$loadedShift=Api GET ('/shifts/'+$shift.id)
if($loadedShift.name -ne 'QA CRUD shift updated'){throw 'Shift update/read mismatch.'}
$results.Add('Public Shift Create/Read/Update: PASS')
# Confirm that the API-created records are actually persisted in the hosting SQL Server.
$connectionBuilder=[System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$connectionBuilder['Data Source']=$settings.Hosting.SqlHost;$connectionBuilder['Initial Catalog']=$settings.Hosting.SqlDatabase
$connectionBuilder['User ID']=$settings.Hosting.SqlUser;$connectionBuilder['Password']=$settings.Hosting.SqlPassword
$connectionBuilder['Encrypt']=$true;$connectionBuilder['TrustServerCertificate']=$false
$connection=[System.Data.SqlClient.SqlConnection]::new($connectionBuilder.ConnectionString)
try{
 $connection.Open();$command=$connection.CreateCommand()
 $command.CommandText='SELECT (SELECT COUNT(*) FROM Departments WHERE Code=@tag)+(SELECT COUNT(*) FROM Employees WHERE EmployeeCode=@tag)+(SELECT COUNT(*) FROM Shifts WHERE Code=@tag)'
 [void]$command.Parameters.AddWithValue('@tag',$tag)
 if([int]$command.ExecuteScalar() -ne 3){throw 'Hosting SQL persistence check failed.'}
 $results.Add('Direct hosting SQL Server persistence: PASS (3 API-created rows)')
}finally{$connection.Dispose()}
Api DELETE ('/employees/'+$emp.id)|Out-Null
Api DELETE ('/shifts/'+$shift.id)|Out-Null
Api DELETE ('/departments/'+$dep.id)|Out-Null
$results.Add('Employee/Shift/Department valid Delete: PASS; temporary QA rows removed through API, audit retained')
$report=[pscustomobject]@{checkedAtUtc=[DateTimeOffset]::UtcNow.ToString('o');baseUrl=$settings.Hosting.ApiBaseUrl;results=@($results)}
$report|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $root '.local\public-crud-verification.json') -Encoding UTF8
$results
