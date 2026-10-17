package main

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestPayloadExtractsOfflineWithoutInstalling(t *testing.T) {
	dir := t.TempDir()
	if err := writeInstallFiles(dir); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(dir, "NearMitra.exe"))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(data, appBinary) {
		t.Fatal("extracted app differs from embedded payload")
	}
	for _, name := range []string{"nearmitra.ico", "uninstall.ps1", "setup-network.ps1"} {
		info, err := os.Stat(filepath.Join(dir, name))
		if err != nil || info.Size() == 0 {
			t.Fatalf("missing setup component %s: %v", name, err)
		}
	}
}
func TestRegistrationQuotesPathsAndUsesPerUserLocations(t *testing.T) {
	path := `C:\Users\O'Brien\AppData\Local\Programs\NearMitra`
	script := registrationScript(path, InstallOptions{DesktopShortcut: true, StartMenu: true})
	if !strings.Contains(script, "O''Brien") || !strings.Contains(script, "GetFolderPath('Desktop')") || !strings.Contains(script, "GetFolderPath('Programs')") {
		t.Fatal("paths are not safely quoted or redirected folders ignored")
	}
	if !strings.Contains(script, "Remove-ItemProperty") || strings.Contains(script, "HKLM:") {
		t.Fatal("per-user autostart preference not respected")
	}
	if !strings.Contains(script, "DisplayVersion") {
		t.Fatal("missing app version registration")
	}
}
func TestReleasePayloadIsCurrent(t *testing.T) {
	release := filepath.Join("..", "build", "windows-release", "NearMitra.exe")
	current, err := os.ReadFile(release)
	if os.IsNotExist(err) {
		t.Skip("release not built")
	}
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(current, appBinary) {
		t.Fatal("setup embeds an outdated app; rebuild with build-installer.bat")
	}
	if !bytes.Contains(appBinary, []byte("NearMitraCall.resolvePeer")) {
		t.Fatal("setup missing direct Nearby call routing")
	}
}

func TestRegistrationScriptParsesInPowerShell(t *testing.T) {
	path := filepath.Join(t.TempDir(), "registration.ps1")
	script := registrationScript(`C:\Users\O'Brien\AppData\Local\Programs\NearMitra`, InstallOptions{DesktopShortcut: true, StartMenu: true, Autostart: true})
	if err := os.WriteFile(path, []byte(script), 0600); err != nil {
		t.Fatal(err)
	}
	parser := "$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile(" + psLiteral(path) + ",[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){$errors|ForEach-Object{Write-Output $_.Message};exit 1};exit 0"
	if output, err := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-Command", parser).CombinedOutput(); err != nil {
		t.Fatalf("invalid registration script: %s %v", output, err)
	}
}
