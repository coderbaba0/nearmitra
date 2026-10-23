package main

import (
	"bytes"
	"os"
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
	for _, name := range []string{"nearmitra.ico", "Uninstall.exe"} {
		info, err := os.Stat(filepath.Join(dir, name))
		if err != nil || info.Size() == 0 {
			t.Fatalf("missing setup component %s: %v", name, err)
		}
	}
}
func TestNativeShortcutHandlesSpacesAndApostrophes(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "O'Brien Folder")
	if err := os.MkdirAll(dir, 0755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "NearMitra.lnk")
	if err := createShortcut(path, filepath.Join(dir, "NearMitra.exe"), dir, filepath.Join(dir, "nearmitra.ico")); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil || len(data) < 76 {
		t.Fatalf("invalid Windows shortcut: %v", err)
	}
	if data[0] != 0x4c {
		t.Fatal("not a native Shell Link")
	}
	value := startupValue(filepath.Join(dir, "NearMitra.exe"))
	if !strings.HasPrefix(value, `"`) || !strings.HasSuffix(value, `" --minimized`) {
		t.Fatalf("incorrect startup command: %s", value)
	}
}
func TestFirewallRulesRemainPrivateAndLocal(t *testing.T) {
	exe := `C:\Users\O'Brien\Programs\NearMitra\NearMitra.exe`
	for _, protocol := range []string{"TCP", "UDP"} {
		args := strings.Join(firewallRuleArguments(exe, protocol), "|")
		for _, want := range []string{"profile=private", "remoteip=localsubnet", "program=" + exe, "protocol=" + protocol} {
			if !strings.Contains(args, want) {
				t.Fatalf("missing firewall scope %s", want)
			}
		}
		if strings.Contains(args, "profile=any") {
			t.Fatal("public network firewall access granted")
		}
	}
}
func TestInstallerUsesNoPowerShell(t *testing.T) {
	for _, name := range []string{"install.go", "native_windows.go", "main.go"} {
		data, err := os.ReadFile(name)
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(strings.ToLower(string(data)), "powershell.exe") || strings.Contains(string(data), "runInstallerScript") {
			t.Fatalf("PowerShell still required by %s", name)
		}
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
