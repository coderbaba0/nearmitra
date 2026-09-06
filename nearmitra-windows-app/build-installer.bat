@echo off
echo ========================================================
echo        Building NearMitra Standalone Setup v2.0
echo ========================================================

echo [1/3] Compiling core application binary (GUI Subsystem - No CMD window)...
go build -ldflags="-H windowsgui -s -w" -o NearMitra.exe .
if %errorlevel% neq 0 (
    echo Error compiling NearMitra.exe!
    pause
    exit /b %errorlevel%
)

echo [2/3] Syncing assets to installer package...
copy /Y NearMitra.exe installer\NearMitra.exe >nul
copy /Y nearmitra.ico installer\nearmitra.ico >nul
copy /Y uninstall.ps1 installer\uninstall.ps1 >nul
copy /Y rsrc_windows_amd64.syso installer\rsrc_windows_amd64.syso >nul
xcopy /E /I /Y assets installer\assets >nul

echo [3/3] Compiling standalone Windows Setup Wizard...
cd installer
go build -ldflags="-H windowsgui -s -w" -o ..\NearMitra_Setup_v2.0.exe .
cd ..

if %errorlevel% equ 0 (
    echo.
    echo ========================================================
    echo  SUCCESS! NearMitra_Setup_v2.0.exe generated cleanly!
    echo  File location: %CD%\NearMitra_Setup_v2.0.exe
    echo ========================================================
) else (
    echo.
    echo Failed to generate setup installer.
)
pause
