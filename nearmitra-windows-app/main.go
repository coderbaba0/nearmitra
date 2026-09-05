// NearMitra Desktop Application (Windows 11 Fluent UI Engine)
// Ultra-fast P2P File & Folder Transfer, Emoji Chat, Live CCTV, Dual-Tier AI Mesh, IoT Peripherals
package main

import (
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
	"time"

	"nearmitra-windows-app/internal/ai"
	"nearmitra-windows-app/internal/calling"
	"nearmitra-windows-app/internal/chat"
	"nearmitra-windows-app/internal/config"
	"nearmitra-windows-app/internal/iot"
	"nearmitra-windows-app/internal/network"
	"nearmitra-windows-app/internal/streaming"
	"nearmitra-windows-app/internal/transfer"
	"nearmitra-windows-app/internal/ui"
)

type syncWriter struct {
	file *os.File
}

func (s *syncWriter) Write(p []byte) (n int, err error) {
	n, err = s.file.Write(p)
	_ = s.file.Sync()
	return
}

func main() {
	// Setup persistent logging
	logDir := filepath.Join(os.Getenv("LOCALAPPDATA"), "NearMitra")
	_ = os.MkdirAll(logDir, 0755)
	logFile, err := os.OpenFile(filepath.Join(logDir, "app.log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err == nil {
		log.SetOutput(io.MultiWriter(os.Stdout, &syncWriter{file: logFile}))
		defer logFile.Close()
	}

	defer func() {
		if r := recover(); r != nil {
			log.Printf("FATAL PANIC RECOVERED: %v", r)
		}
	}()

	log.Println("=== NearMitra Windows 11 Fluent App Starting ===")

	// 0. Single Instance Check: if already running, just focus GUI window and exit
	conn, err := net.DialTimeout("tcp", "127.0.0.1:43880", 250*time.Millisecond)
	if err == nil {
		conn.Close()
		log.Println("[Main] Existing NearMitra instance is already running. Opening GUI window...")
		ui.LaunchStandaloneWindow("http://127.0.0.1:43880")
		return
	}

	// 1. Initialize Configuration
	cfgMgr := config.Get()

	// 2. Initialize Chat History
	chatMgr := chat.GetHistory()

	// 3. Initialize AI Service
	aiService := ai.Get()

	// 4. Initialize Network Discovery Service
	discovery := network.GetDiscovery()
	discovery.Start()
	defer discovery.Stop()

	// 5. Initialize TCP Transfer Server
	server := transfer.GetServer()
	if err := server.Start(); err != nil {
		log.Printf("Warning: TCP Transfer server start error: %v", err)
	}
	defer server.Stop()

	// 6. Initialize CCTV Streamer & WebRTC Calling Signaling
	cctv := streaming.GetStream()
	signaling := calling.GetCall()

	// 7. Initialize IoT & Hardware Peripherals Hub
	iotMgr := iot.NewManager()
	defer iotMgr.Close()

	var appLauncher *ui.AppLauncher
	iotAuto := iot.NewAutomationEngine(iotMgr, func(eventLog string) {
		if appLauncher != nil {
			log.Printf("[IoT Event] %s", eventLog)
		}
	})
	defer iotAuto.Close()

	// 8. Launch Windows 11 Fluent Application Launcher
	appLauncher = ui.NewAppLauncher(
		cfgMgr,
		discovery,
		server,
		chatMgr,
		aiService,
		cctv,
		signaling,
		iotMgr,
		iotAuto,
	)

	log.Println("Starting Application Launcher...")
	if err := appLauncher.Run(); err != nil {
		log.Fatalf("Application runtime error: %v", err)
		_ = os.WriteFile(filepath.Join(logDir, "panic.log"), []byte(fmt.Sprintf("%v", err)), 0644)
	}
}
