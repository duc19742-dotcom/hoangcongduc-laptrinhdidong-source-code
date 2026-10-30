param([string]$FlutterPath='D:\duc_attendance\.toolchains\flutter\bin\flutter.bat',[string]$JavaHome='D:\Androi Studio - Git - Flutter SDK\AndroidStudio\jbr')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$tempRoot=Join-Path $projectRoot '.local\tmp'
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$env:TEMP=$tempRoot; $env:TMP=$tempRoot; $env:JAVA_HOME=$JavaHome
$env:JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$tempRoot -Djdk.net.unixdomain.tmpdir=$tempRoot"
$env:GRADLE_OPTS='-Dorg.gradle.daemon=false'
Push-Location (Join-Path $projectRoot 'mobile\hoang_cong_duc')
try {
 & $FlutterPath pub get
 if($LASTEXITCODE -ne 0){throw 'Flutter dependency restore failed.'}
 & $FlutterPath build apk --release
 if($LASTEXITCODE -ne 0){throw 'Android APK build failed.'}
} finally {Pop-Location}
