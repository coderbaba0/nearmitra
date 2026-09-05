# NearMitra Windows App Uninstaller Script
$ErrorActionPreference = "SilentlyContinue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "     Uninstalling NearMitra Desktop...  " -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

# 1. Terminate running NearMitra processes
Stop-Process -Name "NearMitra" -Force -ErrorAction SilentlyContinue

# 2. Remove Shortcuts
$DesktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
$StartMenuPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Programs)

Remove-Item (Join-Path $DesktopPath "NearMitra.lnk") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $StartMenuPath "NearMitra.lnk") -Force -ErrorAction SilentlyContinue

# 3. Remove Registry Entries
Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\NearMitra" -Recurse -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "NearMitra" -Force -ErrorAction SilentlyContinue

# 4. Remove Installation Files
$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\NearMitra"
if (Test-Path $InstallDir) {
    # Remove files inside $InstallDir
    Get-ChildItem -Path $InstallDir -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item $InstallDir -Force -ErrorAction SilentlyContinue
}

Write-Host "`nNearMitra uninstalled cleanly from system." -ForegroundColor Green
