$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$private=Join-Path $root '.local'
$settings=Get-Content -LiteralPath (Join-Path $private 'secrets.json') -Raw|ConvertFrom-Json
$base=$settings.Hosting.ApiBaseUrl+'/api/v1'
$script:jwt=$null
function Api([string]$method,[string]$path,$body=$null,[bool]$authenticated=$true){
 $options=@{Method=$method;Uri=$base+$path;ContentType='application/json; charset=utf-8'}
 if($authenticated){$options.Headers=@{Authorization='Bearer '+$script:jwt}}
 if($null -ne $body){$options.Body=[System.Text.Encoding]::UTF8.GetBytes(($body|ConvertTo-Json -Depth 8))}
 try{Invoke-RestMethod @options}catch{
  $raw=$_.ErrorDetails.Message
  if(!$raw -and $_.Exception.Response){try{$reader=[System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream());$raw=$reader.ReadToEnd();$reader.Dispose()}catch{}}
  $problem=$null;if($raw){try{$problem=$raw|ConvertFrom-Json}catch{}}
  if($problem.code){throw ($problem.code+': '+$problem.detail)};throw 'API request failed. Please check HTTPS health and retry.'
 }
}
function Private-Code{[System.Net.NetworkCredential]::new('',(Read-Host 'Enter the email OTP actually received (not in chat)' -AsSecureString)).Password}
function Verify-EmailFlow($flow,[string]$route){
 $sent=Api POST '/auth/otp/send' @{flowId=$flow.flowId;flowToken=$flow.flowToken;channel='Email'} $false
 Write-Host ('Check email for '+$flow.maskedEmail)
 Api POST $route @{flowId=$flow.flowId;flowToken=$flow.flowToken;challengeId=$sent.challengeId;code=(Private-Code)} $false
}
try{
 $sessionPath=Join-Path $private 'admin-session.json'
 if(Test-Path -LiteralPath $sessionPath){$session=Get-Content -LiteralPath $sessionPath -Raw|ConvertFrom-Json}
 if(!$session -or [DateTimeOffset]$session.expiresAtUtc -lt [DateTimeOffset]::UtcNow.AddMinutes(3)){
  $flow=Api POST '/auth/login' @{username='admin';password=$settings.Bootstrap.Password} $false
  $session=Verify-EmailFlow $flow '/auth/login/otp/verify'
  $session|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $sessionPath -Encoding UTF8
 }
 $script:jwt=$session.accessToken
 if($session.user.role -ne 'Admin'){throw 'Admin authorization is required.'}
 $locations=(Api GET '/work-locations?pageSize=100').items|Where-Object {$_.isActive}
 if(!$locations){throw 'Create a real work location using the GPS button in the Android app first.'}
 $location=@($locations|Where-Object {$_.name -match 'demo'})[0]
 if(!$location){$location=@($locations)[0]}
 $userPath=Join-Path $private 'demo-user.json'
 if(Test-Path -LiteralPath $userPath){$employeeAccount=Get-Content -LiteralPath $userPath -Raw|ConvertFrom-Json}
 else{
  $parts=$settings.Bootstrap.Email.Split('@')
  if($parts[1] -notin @('gmail.com','googlemail.com')){throw 'Enter a separate real Employee email by creating .local/demo-user.json locally; automatic alias is only available for Gmail.'}
  do{
   $password=[System.Net.NetworkCredential]::new('',(Read-Host 'Set Employee password: 12-128 chars, upper/lower/digit/symbol' -AsSecureString)).Password
   $strong=$password.Length -ge 12 -and $password.Length -le 128 -and $password -cmatch '[A-Z]' -and $password -cmatch '[a-z]' -and $password -match '[0-9]' -and $password -match '[^a-zA-Z0-9]'
   if(!$strong){Write-Host 'Password does not meet requirements. Enter again.'}
  }while(!$strong)
  $employeeAccount=[pscustomobject]@{username='duc_employee';email=$parts[0]+'+ducemployee@'+$parts[1];phone=$settings.Bootstrap.Phone;password=$password;fullName=$session.user.fullName}
  $employeeAccount|ConvertTo-Json|Set-Content -LiteralPath $userPath -Encoding UTF8
 }
 Write-Host ('Employee username: '+$employeeAccount.username+'; email uses your own Gmail inbox.')
 $pending=@((Api GET '/users/pending?pageSize=100').items|Where-Object {$_.email -eq $employeeAccount.email})[0]
 $setupPath=Join-Path $private 'demo-setup.json'
 if(!$pending -and !(Test-Path -LiteralPath $setupPath)){
  $flow=Api POST '/auth/register' @{fullName=$employeeAccount.fullName;username=$employeeAccount.username;email=$employeeAccount.email;phone=$employeeAccount.phone;password=$employeeAccount.password;confirmPassword=$employeeAccount.password} $false
  Verify-EmailFlow $flow '/auth/email-verification/verify'|Out-Null
 }elseif($pending -and !$pending.emailConfirmed){
  $flow=Api POST '/auth/login' @{username=$employeeAccount.username;password=$employeeAccount.password} $false
  Verify-EmailFlow $flow '/auth/email-verification/verify'|Out-Null
 }
 $department=@((Api GET '/departments?pageSize=100').items|Where-Object {$_.code -eq 'DEMO'})[0]
 if(!$department){$department=Api POST '/departments' @{code='DEMO';name='Phong demo do an'}}
 $employee=@((Api GET '/employees?search=DEMO_DUC&pageSize=100').items|Where-Object {$_.employeeCode -eq 'DEMO_DUC'})[0]
 $today=[DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(7)).ToString('yyyy-MM-dd')
 if(!$employee){$employee=Api POST '/employees' @{employeeCode='DEMO_DUC';fullName=$employeeAccount.fullName;email=$employeeAccount.email;phone=$employeeAccount.phone;departmentId=$department.id;jobTitle='Sinh vien demo';hireDate=$today;isActive=$true}}
 $pending=@((Api GET '/users/pending?pageSize=100').items|Where-Object {$_.email -eq $employeeAccount.email})[0]
 if($pending){Api POST ('/users/'+$pending.id+'/approve') @{employeeId=$employee.id}|Out-Null}
 $shift=@((Api GET '/shifts?pageSize=100').items|Where-Object {$_.code -eq 'DEMO'})[0]
 if(!$shift){$shift=Api POST '/shifts' @{code='DEMO';name='Ca demo trong ngay';startLocalTime='08:00:00';endLocalTime='23:59:00';endsNextDay=$false;lateGraceMinutes=5;isActive=$true}}
 $assignment=@((Api GET ('/employee-shifts?employeeId='+$employee.id+'&from='+$today+'&to='+$today)).items|Where-Object {$_.shiftId -eq $shift.id})[0]
 if(!$assignment){$assignment=Api POST '/employee-shifts' @{employeeId=$employee.id;shiftId=$shift.id;workLocationId=$location.id;workDate=$today}}
 [pscustomobject]@{createdAtUtc=[DateTimeOffset]::UtcNow.ToString('o');username=$employeeAccount.username;employeeId=$employee.id;shiftId=$shift.id;workLocationId=$location.id;employeeShiftId=$assignment.id;workDate=$today}|ConvertTo-Json|Set-Content -LiteralPath $setupPath -Encoding UTF8
 Write-Host 'READY: real email-verified Employee, Admin approval, profile, shift and GPS-based assignment saved to hosting SQL.' -ForegroundColor Green
 Write-Host 'On Android: log out Admin, log in as duc_employee with the Employee password you entered, then use Email OTP.'
}catch{Write-Host ('Setup stopped: '+$_.Exception.Message) -ForegroundColor Red}
