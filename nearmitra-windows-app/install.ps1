# NearMitra Windows App Installer Script
$ErrorActionPreference = "Stop"

$AppName = "NearMitra"
$AppVersion = "2.0.0"
$Publisher = "NearMitra Ecosystem"
$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\NearMitra"
$ExePath = Join-Path $InstallDir "NearMitra.exe"
$IconPath = Join-Path $InstallDir "nearmitra.ico"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "     Installing NearMitra Desktop...    " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

# Stop any running instances first
Stop-Process -Name "NearMitra", "nearmitra-windows-app" -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

# 1. Create installation directory
if (!(Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# 2. Copy Executable, Uninstaller and Branding Assets
Copy-Item (Join-Path $SourceDir "NearMitra.exe") -Destination $ExePath -Force
Copy-Item (Join-Path $SourceDir "nearmitra.ico") -Destination $IconPath -Force
if (Test-Path (Join-Path $SourceDir "uninstall.ps1")) {
    Copy-Item (Join-Path $SourceDir "uninstall.ps1") -Destination (Join-Path $InstallDir "uninstall.ps1") -Force
}

if (Test-Path (Join-Path $SourceDir "assets")) {
    $DestAssets = Join-Path $InstallDir "assets"
    Copy-Item (Join-Path $SourceDir "assets") -Destination $DestAssets -Recurse -Force
}

# 3. Create Desktop Shortcut
$WshShell = New-Object -ComObject WScript.Shell
$DesktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
$DesktopShortcut = $WshShell.CreateShortcut((Join-Path $DesktopPath "NearMitra.lnk"))
$DesktopShortcut.TargetPath = $ExePath
$DesktopShortcut.WorkingDirectory = $InstallDir
$DesktopShortcut.IconLocation = "$IconPath,0"
$DesktopShortcut.Description = "NearMitra - Local AI & High-Speed P2P Transfer"
$DesktopShortcut.Save()

# 4. Create Start Menu Shortcut
$StartMenuPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Programs)
$StartShortcut = $WshShell.CreateShortcut((Join-Path $StartMenuPath "NearMitra.lnk"))
$StartShortcut.TargetPath = $ExePath
$StartShortcut.WorkingDirectory = $InstallDir
$StartShortcut.IconLocation = "$IconPath,0"
$StartShortcut.Description = "NearMitra - Local AI & High-Speed P2P Transfer"
$StartShortcut.Save()

# 5. Register in Windows Add / Remove Programs
$RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\NearMitra"
if (!(Test-Path $RegPath)) {
    New-Item -Path $RegPath -Force | Out-Null
}
$UninstCmd = "powershell.exe -ExecutionPolicy Bypass -NoProfile -File `"$InstallDir\uninstall.ps1`""
Set-ItemProperty -Path $RegPath -Name "DisplayName" -Value "NearMitra Desktop (Windows 11)"
Set-ItemProperty -Path $RegPath -Name "DisplayVersion" -Value $AppVersion
Set-ItemProperty -Path $RegPath -Name "Publisher" -Value $Publisher
Set-ItemProperty -Path $RegPath -Name "DisplayIcon" -Value $IconPath
Set-ItemProperty -Path $RegPath -Name "InstallLocation" -Value $InstallDir
Set-ItemProperty -Path $RegPath -Name "UninstallString" -Value $UninstCmd
Set-ItemProperty -Path $RegPath -Name "QuietUninstallString" -Value $UninstCmd

Write-Host "`nNearMitra installed successfully!" -ForegroundColor Green
Write-Host "Desktop Shortcut: $DesktopPath\NearMitra.lnk" -ForegroundColor Yellow
Write-Host "Start Menu: $StartMenuPath\NearMitra.lnk" -ForegroundColor Yellow

# 6. Launch Application
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $ExePath
$psi.WorkingDirectory = $InstallDir
$psi.UseShellExecute = $true
[System.Diagnostics.Process]::Start($psi) | Out-Null
