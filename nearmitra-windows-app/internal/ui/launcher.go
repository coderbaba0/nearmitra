// Package ui provides modern native Windows 11 standalone application launcher.
package ui

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"syscall"
	"unsafe"

	"nearmitra-windows-app/internal/ai"
	"nearmitra-windows-app/internal/calling"
	"nearmitra-windows-app/internal/chat"
	"nearmitra-windows-app/internal/config"
	"nearmitra-windows-app/internal/iot"
	"nearmitra-windows-app/internal/models"
	"nearmitra-windows-app/internal/network"
	"nearmitra-windows-app/internal/streaming"
	"nearmitra-windows-app/internal/transfer"
	"nearmitra-windows-app/internal/wan"
)

// AppLauncher coordinates the backend services, local embedded HTTP server, and Windows 11 App Window.
type AppLauncher struct {
	httpServer *HTTPServer
	cfgMgr     *config.ConfigManager
	server     *transfer.TransferServer
	chatMgr    *chat.HistoryManager
	cctv       *streaming.StreamState
	signaling  *calling.CallState
	tray       *TrayManager
}

var globalLauncher *AppLauncher

// NewAppLauncher creates the application orchestrator.
func NewAppLauncher(
	cfgMgr *config.ConfigManager,
	discovery *network.DiscoveryService,
	server *transfer.TransferServer,
	chatMgr *chat.HistoryManager,
	aiService *ai.AIService,
	cctv *streaming.StreamState,
	signaling *calling.CallState,
	iotMgr *iot.Manager,
	iotAuto *iot.AutomationEngine,
) *AppLauncher {
	httpServer := NewHTTPServer(
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

	al := &AppLauncher{
		httpServer: httpServer,
		cfgMgr:     cfgMgr,
		server:     server,
		chatMgr:    chatMgr,
		cctv:       cctv,
		signaling:  signaling,
	}
	globalLauncher = al
	return al
}

// Run starts embedded server, registers the System Tray, and launches the Windows 11 Fluent App Window.
func (al *AppLauncher) Run() error {
	log.Println("[Launcher] Starting HTTPServer...")
	if err := al.httpServer.Start(); err != nil {
		log.Printf("[Launcher] HTTPServer Start failed: %v", err)
		return err
	}
	log.Printf("[Launcher] HTTPServer listening on port %d", al.httpServer.port)

	// 1. Setup Server Callbacks
	al.setupCallbacks()

	appURL := fmt.Sprintf("http://127.0.0.1:%d", al.httpServer.port)

	// 2. Start Windows System Tray in Background Thread
	al.StartTray(appURL)

	// 3. Check if launched in minimized / startup mode
	isMinimized := false
	for _, arg := range os.Args[1:] {
		if arg == "--minimized" || arg == "--tray" || arg == "--startup" {
			isMinimized = true
			break
		}
	}

	if !isMinimized {
		al.OpenAppWindow(appURL)
	} else {
		log.Println("[Launcher] Started in background System Tray on Windows startup.")
	}

	log.Println("[Launcher] Entering main event loop (select {})...")
	select {}
}

// StartTray creates a background message window and registers NearMitra in Windows Notification Tray.
func (al *AppLauncher) StartTray(appURL string) {
	go func() {
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()

		className := UTF16Ptr("NearMitraTrayWindowClass")
		windowName := UTF16Ptr("NearMitra Tray")
		taskbarCreated, _, _ := user32.NewProc("RegisterWindowMessageW").Call(uintptr(unsafe.Pointer(UTF16Ptr("TaskbarCreated"))))

		var wc WNDCLASSEX
		wc.CbSize = uint32(unsafe.Sizeof(wc))
		wc.LpfnWndProc = syscall.NewCallback(func(hwnd, msg, wParam, lParam uintptr) uintptr {
			if msg == taskbarCreated && taskbarCreated != 0 {
				if al.tray != nil {
					al.tray.Add()
				}
				return 0
			}
			switch msg {
			case WM_TIMER:
				if al.tray != nil && !al.tray.active {
					al.tray.Add()
				}
				return 0
			case WM_TRAYICON:
				if lParam == 0x0202 { // WM_LBUTTONUP - Click on tray icon directly opens app window!
					al.OpenAppWindow(appURL)
				} else if lParam == 0x0205 { // WM_RBUTTONUP - Right click shows context menu
					if al.tray != nil {
						al.tray.ShowContextMenu(
							func() { al.OpenAppWindow(appURL) },
							func() { OpenFolderInExplorer(al.cfgMgr.GetConfig().SaveDirectory) },
							func() {
								theme := "dark"
								if al.cfgMgr.GetConfig().ThemeMode == "dark" {
									theme = "light"
								}
								al.cfgMgr.SetThemeMode(theme)
							},
							func() {
								al.tray.Remove()
								go func() { wan.GetWanService().Stop(); os.Exit(0) }()
							},
						)
					}
				} else if lParam == 0x0203 { // WM_LBUTTONDBLCLK
					al.OpenAppWindow(appURL)
				}
				return 0
			case WM_DESTROY:
				if al.tray != nil {
					al.tray.Remove()
				}
				return 0
			}
			r, _, _ := pDefWindowProc.Call(hwnd, msg, wParam, lParam)
			return r
		})
		hInstance, _, _ := kernel32.NewProc("GetModuleHandleW").Call(0)
		pLoadIcon := user32.NewProc("LoadIconW")
		hIcon := loadEmbeddedTrayIcon()
		if hIcon == 0 {
			hIcon, _, _ = pLoadIcon.Call(hInstance, 1)
		}
		if hIcon == 0 {
			pLoadImage := user32.NewProc("LoadImageW")
			hIcon, _, _ = pLoadImage.Call(0, uintptr(unsafe.Pointer(UTF16Ptr(filepath.Join(filepath.Dir(mustExecutable()), "nearmitra.ico")))), 1, 32, 32, 0x0010)
		}
		if hIcon == 0 {
			hIcon, _, _ = pLoadIcon.Call(0, 32512) // IDI_APPLICATION
		}

		wc.HInstance = hInstance
		wc.HIcon = hIcon
		wc.HIconSm = hIcon
		wc.LpszClassName = className

		if result, _, err := pRegisterClassEx.Call(uintptr(unsafe.Pointer(&wc))); result == 0 {
			log.Printf("[Tray] Cannot register tray window class: %v", err)
			return
		}

		hwnd, _, _ := pCreateWindowEx.Call(
			0,
			uintptr(unsafe.Pointer(className)),
			uintptr(unsafe.Pointer(windowName)),
			0,
			0, 0, 0, 0,
			0, 0, hInstance, 0,
		)

		if hwnd == 0 {
			log.Printf("[Tray] Cannot create notification message window")
			return
		}
		al.tray = NewTrayManager(hwnd, hIcon)
		user32.NewProc("SetTimer").Call(hwnd, 1, 5000, 0)

		var msg MSG
		for {
			r, _, _ := pGetMessage.Call(uintptr(unsafe.Pointer(&msg)), 0, 0, 0)
			if r == 0 || int32(r) == -1 {
				break
			}
			pTranslateMessage.Call(uintptr(unsafe.Pointer(&msg)))
			pDispatchMessage.Call(uintptr(unsafe.Pointer(&msg)))
		}
	}()
}

// LaunchStandaloneWindow opens or focuses the standalone app window.
func LaunchStandaloneWindow(appURL string) {
	edgePath := findEdgeExecutable()
	if edgePath != "" {
		args := []string{
			fmt.Sprintf("--app=%s", appURL),
			"--new-window",
			"--window-size=1200,780",
			"--no-first-run",
			"--no-default-browser-check",
		}

		log.Printf("[Launcher] Spawning standalone app window: %s %v", edgePath, args)
		cmd := exec.Command(edgePath, args...)
		err := cmd.Start()
		if err == nil {
			log.Println("[Launcher] Standalone GUI window process launched successfully.")
			return
		}
		log.Printf("[Launcher] cmd.Start error: %v. Fallback to Chrome / Default Browser.", err)
	}

	chromePath := findChromeExecutable()
	if chromePath != "" {
		args := []string{
			fmt.Sprintf("--app=%s", appURL),
			"--new-window",
			"--window-size=1200,780",
		}
		cmd := exec.Command(chromePath, args...)
		if err := cmd.Start(); err == nil {
			log.Println("[Launcher] Chrome standalone window launched successfully.")
			return
		}
	}

	// Direct Windows ShellExecute to open in default browser in foreground
	verb := UTF16Ptr("open")
	path := UTF16Ptr(appURL)
	pShellExecute.Call(0, uintptr(unsafe.Pointer(verb)), uintptr(unsafe.Pointer(path)), 0, 0, 1)
}

// OpenAppWindow launches or brings to foreground the Microsoft Edge/Chrome Standalone App Window.
func (al *AppLauncher) OpenAppWindow(appURL string) {
	LaunchStandaloneWindow(appURL)
}

func (al *AppLauncher) setupCallbacks() {
	if al.server != nil {
		al.server.SetCallbacks(transfer.TransferCallbacks{
			OnIncomingMessage: func(msg models.ChatMessage) error {
				if err := al.chatMgr.AddMessage(msg); err != nil {
					return err
				}
				al.httpServer.AddLog(fmt.Sprintf("Incoming Chat from %s: %s", msg.Sender, msg.Text))
				if al.cfgMgr.IsNotificationsEnabled() && al.tray != nil {
					al.tray.ShowNotification("NearMitra - New Message", fmt.Sprintf("%s: %s", msg.Sender, msg.Text))
				}
				return nil
			},
			OnIncomingReaction: func(id, emoji, peerID string) {
				aliases := []string{peerID}
				for _, p := range al.httpServer.discovery.GetPeers() {
					if p.ID == peerID || p.InternetDeviceID == peerID {
						aliases = append(aliases, p.ID, p.InternetDeviceID, p.IP)
					}
				}
				al.chatMgr.SetPeerReaction(id, emoji, aliases...)
			},
			OnTypingStatus: func(peerID string, isTyping bool) {
				al.httpServer.SetPeerTyping(peerID, isTyping)
			},
			OnCallInvite: func(senderID string, senderName string, isVideo bool) {
				callType := "Voice"
				if isVideo {
					callType = "Video"
				}
				al.httpServer.AddLog(fmt.Sprintf("Incoming %s Call from %s", callType, senderName))
				if al.cfgMgr.IsNotificationsEnabled() && al.tray != nil {
					al.tray.ShowNotification("NearMitra - Incoming Call", fmt.Sprintf("%s is calling (%s)", senderName, callType))
				}
			},
			OnTransferProgress: func(prog models.TransferProgress) {
				al.httpServer.mu.Lock()
				updated := false
				for i, t := range al.httpServer.transfers {
					if (prog.ID != "" && t.ID == prog.ID && t.PeerID == prog.PeerID) || (prog.ID == "" && t.ID == "" && t.FileName == prog.FileName && t.PeerIP == prog.PeerIP) {
						al.httpServer.transfers[i] = prog
						updated = true
						break
					}
				}
				if !updated {
					al.httpServer.transfers = append(al.httpServer.transfers, prog)
				}
				al.httpServer.mu.Unlock()

				if prog.Complete && al.cfgMgr.IsNotificationsEnabled() && al.tray != nil {
					al.tray.ShowNotification("NearMitra - Transfer Complete", fmt.Sprintf("Finished receiving %s", prog.FileName))
				}
			},
			OnStreamSignal: func(peerIP string, header models.WireHeader) {
				al.httpServer.PushStreamSignal(peerIP, header)
			},
		})
	}
}

func findEdgeExecutable() string {
	paths := []string{
		`C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`,
		`C:\Program Files\Microsoft\Edge\Application\msedge.exe`,
		filepath.Join(os.Getenv("LOCALAPPDATA"), `Microsoft\Edge\Application\msedge.exe`),
	}

	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}

	if runtime.GOOS == "windows" {
		if out, err := exec.Command("where", "msedge.exe").Output(); err == nil && len(out) > 0 {
			return filepath.Clean(string(out))
		}
	}

	return ""
}

func findChromeExecutable() string {
	paths := []string{
		`C:\Program Files\Google\Chrome\Application\chrome.exe`,
		`C:\Program Files (x86)\Google\Chrome\Application\chrome.exe`,
		filepath.Join(os.Getenv("LOCALAPPDATA"), `Google\Chrome\Application\chrome.exe`),
	}

	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}

	if runtime.GOOS == "windows" {
		if out, err := exec.Command("where", "chrome.exe").Output(); err == nil && len(out) > 0 {
			return filepath.Clean(string(out))
		}
	}

	return ""
}

func mustExecutable() string {
	path, err := os.Executable()
	if err != nil {
		return "."
	}
	return path
}
