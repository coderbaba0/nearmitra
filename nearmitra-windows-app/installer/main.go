// Package main provides the standalone NearMitra Windows 11 GUI Installer Setup.
package main

import (
	"crypto/sha256"
	"embed"
	"encoding/json"
	"fmt"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
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

//go:embed setup-network.ps1
var networkScript []byte

//go:embed assets/*
var assetsFS embed.FS

const (
	AppName       = "NearMitra Desktop"
	AppVersion    = "2.1.2"
	Publisher     = "NearMitra Ecosystem"
	InstallerPort = 43899
)

var (
	kernel32      = syscall.NewLazyDLL("kernel32.dll")
	user32        = syscall.NewLazyDLL("user32.dll")
	shell32       = syscall.NewLazyDLL("shell32.dll")
	pShellExecute = shell32.NewProc("ShellExecuteW")
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
		log.SetOutput(logFile)
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
	var installMu sync.Mutex
	installed := false

	mux.HandleFunc("/api/installer/info", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]interface{}{
			"app_name":       AppName,
			"app_version":    AppVersion,
			"publisher":      Publisher,
			"payload_sha256": fmt.Sprintf("%x", sha256.Sum256(appBinary)),
			"install_path":   installDir,
		})
	})

	mux.HandleFunc("/api/installer/execute", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "POST required", 405)
			return
		}
		if !installMu.TryLock() {
			http.Error(w, "Installation already in progress", 409)
			return
		}
		defer installMu.Unlock()
		var options InstallOptions
		w.Header().Set("Content-Type", "application/json")
		if json.NewDecoder(r.Body).Decode(&options) != nil {
			w.WriteHeader(400)
			_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": false, "error": "Invalid installation options"})
			return
		}
		fail := func(err error) {
			log.Printf("[Installer] %v", err)
			w.WriteHeader(500)
			_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": false, "error": err.Error()})
		}
		if err := runInstallerScript("$ErrorActionPreference='Stop';$running=Get-Process -Name NearMitra,nearmitra-windows-app -ErrorAction SilentlyContinue;foreach($p in $running){Stop-Process -Id $p.Id -Force -ErrorAction Stop};exit 0"); err != nil {
			fail(err)
			return
		}
		if err := writeInstallFiles(installDir); err != nil {
			fail(err)
			return
		}
		if err := runInstallerScript(registrationScript(installDir, options)); err != nil {
			fail(err)
			return
		}
		warning := ""
		if options.PrivateNetwork {
			if err := configurePrivateNetwork(installDir); err != nil {
				warning = "App installed. Private-network access was not configured: " + err.Error()
			}
		}
		installed = true
		_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true, "warning": warning, "message": "NearMitra installed successfully"})
	})

	mux.HandleFunc("/api/installer/finish", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "POST required", 405)
			return
		}
		installMu.Lock()
		ready := installed
		installMu.Unlock()
		if !ready {
			http.Error(w, "Complete installation first", 409)
			return
		}
		var req struct {
			LaunchNow bool `json:"launch_now"`
		}
		_ = json.NewDecoder(r.Body).Decode(&req)

		if req.LaunchNow {
			exePath := filepath.Join(installDir, "NearMitra.exe")
			cmd := exec.Command(exePath)
			cmd.Dir = installDir
			if err := cmd.Start(); err != nil {
				http.Error(w, "Cannot start NearMitra: "+err.Error(), 500)
				return
			}
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true})

		go func() {
			time.Sleep(500 * time.Millisecond)
			os.Exit(0)
		}()
	})

	mux.HandleFunc("/api/installer/cancel", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "POST required", 405)
			return
		}
		if !installMu.TryLock() {
			http.Error(w, "Wait for installation to finish", 409)
			return
		}
		installMu.Unlock()
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
