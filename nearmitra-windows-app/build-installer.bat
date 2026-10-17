@echo off
setlocal
cd /d "%~dp0"
set GOOS=windows
set GOARCH=amd64
set "RELEASE_DIR=%CD%\build\windows-release"
if not exist "%RELEASE_DIR%" mkdir "%RELEASE_DIR%"
echo Building NearMitra Desktop...
go build -trimpath -ldflags="-H windowsgui -s -w" -o "%RELEASE_DIR%\NearMitra.exe" .
if errorlevel 1 exit /b 1
copy /Y "%RELEASE_DIR%\NearMitra.exe" installer\NearMitra.exe >nul
if errorlevel 1 exit /b 1
echo Building NearMitra Setup 2.1.2...
go build -trimpath -ldflags="-H windowsgui -s -w" -o "%RELEASE_DIR%\NearMitra_Setup_2.1.2_x64.exe" ./installer
if errorlevel 1 exit /b 1
echo Setup ready: %RELEASE_DIR%\NearMitra_Setup_2.1.2_x64.exe
endlocal
