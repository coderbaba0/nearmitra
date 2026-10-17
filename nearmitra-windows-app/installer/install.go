package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

type InstallOptions struct {
	DesktopShortcut bool `json:"desktop_shortcut"`
	StartMenu       bool `json:"start_menu"`
	Autostart       bool `json:"autostart"`
	PrivateNetwork  bool `json:"private_network"`
}

func psLiteral(value string) string { return "'" + strings.ReplaceAll(value, "'", "''") + "'" }
func runInstallerScript(script string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("Windows setup failed: %s (%w)", strings.TrimSpace(string(output)), err)
	}
	return nil
}
func writeInstallFiles(dir string) error {
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	files := map[string][]byte{"NearMitra.exe": appBinary, "nearmitra.ico": appIcon, "uninstall.ps1": uninstallerScript, "setup-network.ps1": networkScript}
	if !bytes.HasPrefix(appBinary, []byte("MZ")) {
		return fmt.Errorf("setup payload is not a Windows executable")
	}
	for name, data := range files {
		path := filepath.Join(dir, name)
		tmp := path + ".installing"
		if err := os.WriteFile(tmp, data, 0644); err != nil {
			return err
		}
		if err := os.Rename(tmp, path); err != nil {
			_ = os.Remove(tmp)
			return fmt.Errorf("cannot update %s; close NearMitra and retry: %w", name, err)
		}
	}
	return fs.WalkDir(assetsFS, "assets", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		rel, err := filepath.Rel("assets", path)
		if err != nil {
			return err
		}
		target := filepath.Join(dir, "assets", rel)
		if err = os.MkdirAll(filepath.Dir(target), 0755); err != nil {
			return err
		}
		data, err := assetsFS.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(target, data, 0644)
	})
}
func registrationScript(dir string, options InstallOptions) string {
	exe := filepath.Join(dir, "NearMitra.exe")
	icon := filepath.Join(dir, "nearmitra.ico")
	uninstall := filepath.Join(dir, "uninstall.ps1")
	var script strings.Builder
	script.WriteString("$ErrorActionPreference='Stop'; $shell=New-Object -ComObject WScript.Shell;\n")
	script.WriteString("$desktop=[Environment]::GetFolderPath('Desktop');$programs=[Environment]::GetFolderPath('Programs');\n")
	if options.DesktopShortcut {
		script.WriteString("$links=@((Join-Path $desktop 'NearMitra.lnk'));\n")
	} else {
		script.WriteString("$links=@();\n")
	}
	if options.StartMenu {
		script.WriteString("$links+=Join-Path $programs 'NearMitra.lnk';\n")
	}
	script.WriteString("foreach($path in $links){$s=$shell.CreateShortcut($path);$s.TargetPath=" + psLiteral(exe) + ";$s.WorkingDirectory=" + psLiteral(dir) + ";$s.IconLocation=" + psLiteral(icon+",0") + ";$s.Description='NearMitra - Nearby chat, calls and device sharing';$s.Save()};\n")
	reg := `HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\NearMitra`
	uninstallCmd := `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "` + uninstall + `"`
	props := map[string]interface{}{"DisplayName": AppName, "DisplayVersion": AppVersion, "Publisher": Publisher, "DisplayIcon": icon, "InstallLocation": dir, "UninstallString": uninstallCmd, "NoModify": 1, "NoRepair": 1, "EstimatedSize": len(appBinary) / 1024}
	payload, _ := json.Marshal(props)
	script.WriteString("$key=" + psLiteral(reg) + ";New-Item -Path $key -Force | Out-Null;\n$props=ConvertFrom-Json " + psLiteral(string(payload)) + ";foreach($p in $props.PSObject.Properties){Set-ItemProperty -Path $key -Name $p.Name -Value $p.Value};\n")
	if options.Autostart {
		script.WriteString("Set-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run' -Name NearMitra -Value " + psLiteral(`"`+exe+`" --minimized`) + ";\n")
	} else {
		script.WriteString("Remove-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run' -Name NearMitra -ErrorAction SilentlyContinue;\n")
	}
	script.WriteString("exit 0\n")
	return script.String()
}
func configurePrivateNetwork(dir string) error {
	// Only this optional step needs Windows elevation; the app installs per-user.
	scriptPath := filepath.Join(dir, "setup-network.ps1")
	exe := filepath.Join(dir, "NearMitra.exe")
	args := `-NoProfile -ExecutionPolicy Bypass -File "` + scriptPath + `" -ProgramPath "` + exe + `"`
	return runInstallerScript("$ErrorActionPreference='Stop';$p=Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList " + psLiteral(args) + ";if($p.ExitCode -ne 0){throw 'Private-network configuration failed'}")
}
