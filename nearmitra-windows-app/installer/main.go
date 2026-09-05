// Package main provides the standalone NearMitra Windows 11 GUI Installer Setup.
package main

import (
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

//go:embed web/*
var webFS embed.FS

//go:embed NearMitra.exe
var appBinary []byte

//go:embed nearmitra.ico
var appIcon []byte

//go:embed uninstall.ps1
var uninstallerScript []byte

const (
	AppName      = "NearMitra Desktop (Windows 11)"
	AppVersion   = "2.0.0"
	Publisher    = "NearMitra Ecosystem"
	InstallerPort = 43899
)

var (
	kernel32        = syscall.NewLazyDLL("kernel32.dll")
	user32          = syscall.NewLazyDLL("user32.dll")
	shell32         = syscall.NewLazyDLL("shell32.dll")
	pShellExecute   = shell32.NewProc("ShellExecuteW")
)

func UTF16Ptr(s string) *uint16 {
	ptr, _ := syscall.UTF16PtrFromString(s)
	return ptr
}

func main() {
	logDir := filepath.Join(os.Getenv("LOCALAPPDATA"), "NearMitra")
	_ = os.MkdirAll(logDir, 0755)
	logFile, err := os.OpenFile(filepath.Join(logDir, "installer.log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err == nil {
		log.SetOutput(io.MultiWriter(os.Stdout, logFile))
		defer logFile.Close()
	}

	log.Println("=== NearMitra Windows 11 GUI Installer Starting ===")

	// 1. Setup HTTP Server for Wizard Web UI
	mux := http.NewServeMux()

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate")
		path := strings.TrimPrefix(r.URL.Path, "/")
		if path == "" || path == "index.html" {
			data, err := fs.ReadFile(webFS, "web/index.html")
			if err == nil {
				w.Header().Set("Content-Type", "text/html; charset=utf-8")
				_, _ = w.Write(data)
				return
			}
		} else if path == "style.css" {
			data, err := fs.ReadFile(webFS, "web/style.css")
			if err == nil {
				w.Header().Set("Content-Type", "text/css; charset=utf-8")
				_, _ = w.Write(data)
				return
			}
		} else if path == "app.js" {
			data, err := fs.ReadFile(webFS, "web/app.js")
			if err == nil {
				w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
				_, _ = w.Write(data)
				return
			}
		} else if path == "logo.png" {
			data, err := fs.ReadFile(webFS, "web/logo.png")
			if err == nil {
				w.Header().Set("Content-Type", "image/png")
				_, _ = w.Write(data)
				return
			}
		} else if path == "favicon.ico" {
			data, err := fs.ReadFile(webFS, "web/favicon.ico")
			if err == nil {
				w.Header().Set("Content-Type", "image/x-icon")
				_, _ = w.Write(data)
				return
			}
		}
		http.NotFound(w, r)
	})

	installDir := filepath.Join(os.Getenv("LOCALAPPDATA"), "Programs", "NearMitra")

	mux.HandleFunc("/api/installer/info", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]interface{}{
			"app_name":     AppName,
			"app_version":  AppVersion,
			"publisher":    Publisher,
			"install_path": installDir,
		})
	})

	mux.HandleFunc("/api/installer/execute", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			DesktopShortcut bool `json:"desktop_shortcut"`
			StartMenu       bool `json:"start_menu"`
			Autostart       bool `json:"autostart"`
		}
		_ = json.NewDecoder(r.Body).Decode(&req)

		// 1. Stop any currently running NearMitra process
		_ = exec.Command("powershell.exe", "-NoProfile", "-Command", "Stop-Process -Name 'NearMitra', 'nearmitra-windows-app' -Force -ErrorAction SilentlyContinue").Run()
		time.Sleep(500 * time.Millisecond)

		// 2. Create Destination Directory
		if err := os.MkdirAll(installDir, 0755); err != nil {
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": false, "error": err.Error()})
			return
		}

		exePath := filepath.Join(installDir, "NearMitra.exe")
		iconPath := filepath.Join(installDir, "nearmitra.ico")
		uninstPath := filepath.Join(installDir, "uninstall.ps1")

		// 3. Extract NearMitra.exe
		if err := os.WriteFile(exePath, appBinary, 0755); err != nil {
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": false, "error": fmt.Sprintf("Failed to write NearMitra.exe: %v", err)})
			return
		}

		// 4. Extract nearmitra.ico & uninstaller script
		if len(appIcon) > 0 {
			_ = os.WriteFile(iconPath, appIcon, 0644)
		}
		if len(uninstallerScript) > 0 {
			_ = os.WriteFile(uninstPath, uninstallerScript, 0644)
		}

		// 5. Create Desktop and Start Menu Shortcuts via PowerShell
		var psScript strings.Builder
		psScript.WriteString("$WshShell = New-Object -ComObject WScript.Shell;\n")

		if req.DesktopShortcut {
			desktopPath := filepath.Join(os.Getenv("USERPROFILE"), "Desktop")
			if _, err := os.Stat(filepath.Join(os.Getenv("USERPROFILE"), "OneDrive", "Desktop")); err == nil {
				desktopPath = filepath.Join(os.Getenv("USERPROFILE"), "OneDrive", "Desktop")
			}
			shortcutPath := filepath.Join(desktopPath, "NearMitra.lnk")
			psScript.WriteString(fmt.Sprintf(`$s1 = $WshShell.CreateShortcut('%s'); $s1.TargetPath = '%s'; $s1.WorkingDirectory = '%s'; $s1.IconLocation = '%s,0'; $s1.Description = 'NearMitra - Local AI & High-Speed P2P Mesh'; $s1.Save();`+"\n", shortcutPath, exePath, installDir, iconPath))
		}

		if req.StartMenu {
			startMenuPath := filepath.Join(os.Getenv("APPDATA"), "Microsoft", "Windows", "Start Menu", "Programs")
			shortcutPath := filepath.Join(startMenuPath, "NearMitra.lnk")
			psScript.WriteString(fmt.Sprintf(`$s2 = $WshShell.CreateShortcut('%s'); $s2.TargetPath = '%s'; $s2.WorkingDirectory = '%s'; $s2.IconLocation = '%s,0'; $s2.Description = 'NearMitra - Local AI & High-Speed P2P Mesh'; $s2.Save();`+"\n", shortcutPath, exePath, installDir, iconPath))
		}

		// 6. Register in Windows Add / Remove Programs
		regPath := `HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\NearMitra`
		uninstCmd := fmt.Sprintf(`powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%s"`, uninstPath)
		psScript.WriteString(fmt.Sprintf(`if (!(Test-Path '%s')) { New-Item -Path '%s' -Force | Out-Null };`+"\n", regPath, regPath))
		psScript.WriteString(fmt.Sprintf(`Set-ItemProperty -Path '%s' -Name 'DisplayName' -Value '%s';`+"\n", regPath, AppName))
		psScript.WriteString(fmt.Sprintf(`Set-ItemProperty -Path '%s' -Name 'DisplayVersion' -Value '%s';`+"\n", regPath, AppVersion))
		psScript.WriteString(fmt.Sprintf(`Set-ItemProperty -Path '%s' -Name 'Publisher' -Value '%s';`+"\n", regPath, Publisher))
		psScript.WriteString(fmt.Sprintf(`Set-ItemProperty -Path '%s' -Name 'DisplayIcon' -Value '%s';`+"\n", regPath, iconPath))
		psScript.WriteString(fmt.Sprintf(`Set-ItemProperty -Path '%s' -Name 'InstallLocation' -Value '%s';`+"\n", regPath, installDir))
		psScript.WriteString(fmt.Sprintf(`Set-ItemProperty -Path '%s' -Name 'UninstallString' -Value '%s';`+"\n", regPath, uninstCmd))
		psScript.WriteString(fmt.Sprintf(`Set-ItemProperty -Path '%s' -Name 'QuietUninstallString' -Value '%s';`+"\n", regPath, uninstCmd))

		if req.Autostart {
			psScript.WriteString(fmt.Sprintf(`Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'NearMitra' -Value '"%s" --minimized';`+"\n", exePath))
		}

		_ = exec.Command("powershell.exe", "-NoProfile", "-Command", psScript.String()).Run()

		log.Println("[Installer] Core extraction & registration completed successfully.")
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true})
	})

	mux.HandleFunc("/api/installer/finish", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			LaunchNow bool `json:"launch_now"`
		}
		_ = json.NewDecoder(r.Body).Decode(&req)

		if req.LaunchNow {
			exePath := filepath.Join(installDir, "NearMitra.exe")
			_ = exec.Command(exePath).Start()
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true})

		go func() {
			time.Sleep(500 * time.Millisecond)
			os.Exit(0)
		}()
	})

	mux.HandleFunc("/api/installer/cancel", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		go func() {
			time.Sleep(300 * time.Millisecond)
			os.Exit(0)
		}()
	})

	// Start local wizard server
	listener, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", InstallerPort))
	if err != nil {
		listener, err = net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			log.Fatalf("Failed to bind installer port: %v", err)
		}
	}
	actualPort := listener.Addr().(*net.TCPAddr).Port

	go func() {
		_ = http.Serve(listener, mux)
	}()

	wizardURL := fmt.Sprintf("http://127.0.0.1:%d", actualPort)
	log.Printf("[Installer] Wizard server running at %s", wizardURL)

	// Launch Standalone Wizard Window
	openWizardWindow(wizardURL)

	// Keep installer alive until finished
	select {}
}

func openWizardWindow(appURL string) {
	edgePaths := []string{
		`C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`,
		`C:\Program Files\Microsoft\Edge\Application\msedge.exe`,
		filepath.Join(os.Getenv("LOCALAPPDATA"), `Microsoft\Edge\Application\msedge.exe`),
	}

	for _, p := range edgePaths {
		if _, err := os.Stat(p); err == nil {
			args := []string{
				fmt.Sprintf("--app=%s", appURL),
				"--new-window",
				"--window-size=650,560",
				"--no-first-run",
				"--no-default-browser-check",
			}
			cmd := exec.Command(p, args...)
			if err := cmd.Start(); err == nil {
				return
			}
		}
	}

	chromePaths := []string{
		`C:\Program Files\Google\Chrome\Application\chrome.exe`,
		`C:\Program Files (x86)\Google\Chrome\Application\chrome.exe`,
		filepath.Join(os.Getenv("LOCALAPPDATA"), `Google\Chrome\Application\chrome.exe`),
	}
	for _, p := range chromePaths {
		if _, err := os.Stat(p); err == nil {
			args := []string{
				fmt.Sprintf("--app=%s", appURL),
				"--new-window",
				"--window-size=650,560",
			}
			cmd := exec.Command(p, args...)
			if err := cmd.Start(); err == nil {
				return
			}
		}
	}

	verb := UTF16Ptr("open")
	path := UTF16Ptr(appURL)
	pShellExecute.Call(0, uintptr(unsafe.Pointer(verb)), uintptr(unsafe.Pointer(path)), 0, 0, 1)
}
