@echo off
setlocal
if not defined NEARMITRA_SIGN_THUMBPRINT (
  echo NOTICE: No code-signing certificate configured. This build remains unsigned; Windows UAC may show Unknown publisher.
  exit /b 0
)
if "%~1"=="" exit /b 1
set "SIGNTOOL_EXE=signtool.exe"
if defined NEARMITRA_SIGNTOOL set "SIGNTOOL_EXE=%NEARMITRA_SIGNTOOL%"
set "SIGN_TIMESTAMP=http://timestamp.digicert.com"
if defined NEARMITRA_SIGN_TIMESTAMP set "SIGN_TIMESTAMP=%NEARMITRA_SIGN_TIMESTAMP%"
"%SIGNTOOL_EXE%" sign /s My /sha1 "%NEARMITRA_SIGN_THUMBPRINT%" /fd SHA256 /tr "%SIGN_TIMESTAMP%" /td SHA256 /d "NearMitra" /du "https://flutterfever.com" "%~1"
if errorlevel 1 exit /b 1
"%SIGNTOOL_EXE%" verify /pa /all "%~1"
if errorlevel 1 exit /b 1
endlocal
