// Package ui implements the native Windows 11 Fluent UI application window and event router.
package ui

import (
	"fmt"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"
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
)

const (
	IDC_CHAT_INPUT = 101
	IDC_AI_INPUT   = 102
	WM_APP_REFRESH = 0x8000 + 8
)

type MainWindow struct {
	mu         sync.RWMutex
	hwnd       uintptr
	hEditChat  uintptr
	hEditAI    uintptr
	currentTab int
	isDarkMode bool
	theme      FluentPalette
	hitboxes   []HitBox

	fontTitle   uintptr
	fontSubhead uintptr
	fontBody    uintptr
	fontSmall   uintptr

	cfgMgr    *config.ConfigManager
	discovery *network.DiscoveryService
	server    *transfer.TransferServer
	chatMgr   *chat.HistoryManager
	aiService *ai.AIService
	cctv      *streaming.StreamState
	signaling *calling.CallState
	iotMgr    *iot.Manager
	iotAuto   *iot.AutomationEngine
	tray      *TrayManager

	activePeer *models.Peer
	typingPeer string
	logs       []string
	transfers  []models.TransferProgress
}

var globalWindow *MainWindow

// NewMainWindow initializes the main window controller and font handles.
func NewMainWindow(
	cfgMgr *config.ConfigManager,
	discovery *network.DiscoveryService,
	server *transfer.TransferServer,
	chatMgr *chat.HistoryManager,
	aiService *ai.AIService,
	cctv *streaming.StreamState,
	signaling *calling.CallState,
	iotMgr *iot.Manager,
	iotAuto *iot.AutomationEngine,
) *MainWindow {
	mw := &MainWindow{
		currentTab: 0,
		isDarkMode: cfgMgr.GetConfig().ThemeMode == "dark",
		theme:      DarkTheme,
		cfgMgr:     cfgMgr,
		discovery:  discovery,
		server:     server,
		chatMgr:    chatMgr,
		aiService:  aiService,
		cctv:       cctv,
		signaling:  signaling,
		iotMgr:     iotMgr,
		iotAuto:    iotAuto,
		logs:       make([]string, 0),
		transfers:  make([]models.TransferProgress, 0),
	}
	if !mw.isDarkMode {
		mw.theme = LightTheme
	}

	globalWindow = mw
	return mw
}

// AddLog appends a timestamped log to the UI console.
func (mw *MainWindow) AddLog(msg string) {
	mw.mu.Lock()
	defer mw.mu.Unlock()
	entry := fmt.Sprintf("[%s] %s", time.Now().Format("15:04:05"), msg)
	mw.logs = append(mw.logs, entry)
	if len(mw.logs) > 200 {
		mw.logs = mw.logs[len(mw.logs)-200:]
	}
	mw.RequestRepaint()
}

// RequestRepaint triggers a repaint of the window client rect.
func (mw *MainWindow) RequestRepaint() {
	if mw.hwnd != 0 {
		pInvalidateRect.Call(mw.hwnd, 0, 0)
	}
}

// CreateFonts initializes Segoe UI fonts with ClearType rendering and Per-Monitor DPI scaling.
func (mw *MainWindow) CreateFonts() {
	mw.fontTitle = createFont("Segoe UI", Scale(22), FW_BOLD)
	mw.fontSubhead = createFont("Segoe UI", Scale(15), FW_SEMIBOLD)
	mw.fontBody = createFont("Segoe UI", Scale(13), FW_NORMAL)
	mw.fontSmall = createFont("Segoe UI", Scale(11), FW_NORMAL)
}

func createFont(name string, height int32, weight int32) uintptr {
	h, _, _ := pCreateFont.Call(
		uintptr(-height),
		0, 0, 0,
		uintptr(weight),
		0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0,
		uintptr(unsafe.Pointer(UTF16Ptr(name))),
	)
	return h
}

// Run creates the Win32 window, registers message loop, and enters event dispatch.
func (mw *MainWindow) Run() error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	className := UTF16Ptr("NearMitraMainWindowClass")
	hInstance, _, _ := kernel32.NewProc("GetModuleHandleW").Call(0)

	var wc WNDCLASSEX
	wc.CbSize = uint32(unsafe.Sizeof(wc))
	wc.Style = 0x0002 | 0x0001 // CS_HREDRAW | CS_VREDRAW
	wc.LpfnWndProc = syscall.NewCallback(wndProc)
	wc.HInstance = hInstance
	wc.LpszClassName = className
	pLoadCursor := user32.NewProc("LoadCursorW")
	hCursor, _, _ := pLoadCursor.Call(0, 32512) // IDC_ARROW
	wc.HCursor = hCursor

	pLoadIcon := user32.NewProc("LoadIconW")
	hIcon, _, _ := pLoadIcon.Call(hInstance, 1) // Resource ID 1 from rsrc.syso
	if hIcon == 0 {
		pLoadImage := user32.NewProc("LoadImageW")
		hIcon, _, _ = pLoadImage.Call(0, uintptr(unsafe.Pointer(UTF16Ptr("nearmitra.ico"))), 1, 32, 32, 0x0010) // LR_LOADFROMFILE
	}
	if hIcon == 0 {
		pLoadImage := user32.NewProc("LoadImageW")
		hIcon, _, _ = pLoadImage.Call(0, uintptr(unsafe.Pointer(UTF16Ptr("assets/nearmitra.ico"))), 1, 32, 32, 0x0010)
	}
	wc.HIcon = hIcon
	wc.HIconSm = hIcon

	pRegisterClassEx.Call(uintptr(unsafe.Pointer(&wc)))

	title := UTF16Ptr("NearMitra - Local AI & High-Speed P2P")
	hwnd, _, _ := pCreateWindowEx.Call(
		0,
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(title)),
		WS_OVERLAPPEDWINDOW|WS_VISIBLE|WS_CLIPCHILDREN,
		100, 100, 1040, 680,
		0, 0, hInstance, 0,
	)

	if hwnd == 0 {
		return fmt.Errorf("failed to create main window")
	}
	mw.hwnd = hwnd

	if hIcon != 0 {
		pSendMessage.Call(hwnd, WM_SETICON, ICON_BIG, hIcon)
		pSendMessage.Call(hwnd, WM_SETICON, ICON_SMALL, hIcon)
	}

	// Enable Windows 11 Dark Mode Titlebar if dark mode
	if mw.isDarkMode {
		enableDarkMode := 1
		pDwmSetWindowAttribute.Call(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, uintptr(unsafe.Pointer(&enableDarkMode)), 4)
	}

	mw.CreateFonts()

	// Create Chat Input Edit Box
	hEditChat, _, _ := pCreateWindowEx.Call(
		0,
		uintptr(unsafe.Pointer(UTF16Ptr("EDIT"))),
		0,
		WS_CHILD|WS_VISIBLE|ES_AUTOHSCROLL|0x0080,
		0, 0, 0, 0,
		hwnd,
		IDC_CHAT_INPUT,
		hInstance,
		0,
	)
	mw.hEditChat = hEditChat
	pSendMessage.Call(hEditChat, WM_SETFONT, mw.fontBody, 1)

	// Setup Tray Icon with NearMitra brand icon
	mw.tray = NewTrayManager(hwnd, hIcon)

	// Set 1-second refresh timer
	pSetTimer.Call(hwnd, 1, 1000, 0)

	mw.AddLog("NearMitra Windows App initialized. Local Wi-Fi radar active.")

	// Wire Transfer Server Callbacks
	mw.setupServerCallbacks()

	// Show Window
	pShowWindow.Call(hwnd, SW_SHOW)
	pUpdateWindow.Call(hwnd)

	// Win32 Message Loop
	var msg MSG
	for {
		r, _, _ := pGetMessage.Call(uintptr(unsafe.Pointer(&msg)), 0, 0, 0)
		if r == 0 || int32(r) == -1 {
			break
		}
		pTranslateMessage.Call(uintptr(unsafe.Pointer(&msg)))
		pDispatchMessage.Call(uintptr(unsafe.Pointer(&msg)))
	}

	return nil
}

func (mw *MainWindow) setupServerCallbacks() {
	if mw.server != nil {
		mw.server.SetCallbacks(transfer.TransferCallbacks{
			OnIncomingMessage: func(msg models.ChatMessage) error {
				if err := mw.chatMgr.AddMessage(msg); err != nil {
					return err
				}
				mw.AddLog(fmt.Sprintf("Chat from %s: %s", msg.Sender, msg.Text))
				if mw.tray != nil {
					mw.tray.ShowNotification("NearMitra Chat", fmt.Sprintf("%s: %s", msg.Sender, msg.Text))
				}
				mw.RequestRepaint()
				return nil
			},
			OnIncomingReaction: func(targetMsgID, reaction, peerID string) {
				mw.chatMgr.AddReaction(targetMsgID, reaction)
				mw.RequestRepaint()
			},
			OnTypingStatus: func(peerID string, isTyping bool) {
				mw.mu.Lock()
				if isTyping {
					mw.typingPeer = "Peer is typing..."
				} else {
					mw.typingPeer = ""
				}
				mw.mu.Unlock()
				mw.RequestRepaint()
			},
			OnTransferProgress: func(prog models.TransferProgress) {
				mw.mu.Lock()
				updated := false
				for i, t := range mw.transfers {
					if t.FileName == prog.FileName {
						mw.transfers[i] = prog
						updated = true
						break
					}
				}
				if !updated {
					mw.transfers = append(mw.transfers, prog)
				}
				mw.mu.Unlock()
				mw.RequestRepaint()
			},
		})
	}

	if mw.signaling != nil {
		mw.signaling.OnStateChange = func() {
			mw.RequestRepaint()
		}
	}
}

// WndProc window message handler
func wndProc(hwnd, msg, wParam, lParam uintptr) uintptr {
	mw := globalWindow
	if mw == nil {
		r, _, _ := pDefWindowProc.Call(hwnd, msg, wParam, lParam)
		return r
	}

	switch uint32(msg) {
	case WM_PAINT:
		var ps PAINTSTRUCT
		hdc, _, _ := pBeginPaint.Call(hwnd, uintptr(unsafe.Pointer(&ps)))

		var clientRect RECT
		pGetClientRect.Call(hwnd, uintptr(unsafe.Pointer(&clientRect)))

		// Double Buffering
		memDC, _, _ := pCreateCompatibleDC.Call(hdc)
		memBitmap, _, _ := pCreateCompatibleBitmap.Call(hdc, uintptr(clientRect.Right), uintptr(clientRect.Bottom))
		oldBmp, _, _ := pSelectObject.Call(memDC, memBitmap)

		// Fill Background
		bgBrush, _, _ := pCreateSolidBrush.Call(uintptr(mw.theme.BgMain))
		pFillRect.Call(memDC, uintptr(unsafe.Pointer(&clientRect)), bgBrush)
		pDeleteObject.Call(bgBrush)

		// Clear hitboxes
		mw.mu.Lock()
		mw.hitboxes = mw.hitboxes[:0]
		mw.mu.Unlock()

		// Sidebar bounds
		sidebarW := Scale(210)
		sidebarR := RECT{Left: 0, Top: 0, Right: sidebarW, Bottom: clientRect.Bottom}
		RenderSidebar(memDC, sidebarR, mw.currentTab, mw.theme, mw.fontTitle, mw.fontBody, mw.fontSmall, mw.fontSubhead, &mw.hitboxes)

		// Content bounds
		contentR := RECT{Left: sidebarW, Top: 0, Right: clientRect.Right, Bottom: clientRect.Bottom}

		// Hide / Position Chat Edit Box
		if mw.currentTab == 1 {
			inputLeft := contentR.Left + Scale(60)
			inputTop := contentR.Bottom - Scale(58)
			inputW := contentR.Right - contentR.Left - Scale(160)
			inputH := Scale(30)
			pMoveWindow.Call(mw.hEditChat, uintptr(inputLeft), uintptr(inputTop), uintptr(inputW), uintptr(inputH), 1)
			pShowWindow.Call(mw.hEditChat, SW_SHOW)
		} else {
			pShowWindow.Call(mw.hEditChat, SW_HIDE)
		}

		// Render Tab Views
		switch mw.currentTab {
		case 0: // Radar & Peers
			peers := mw.discovery.GetPeers()
			router := network.GetRouterDiagnostics()
			RenderRadarView(memDC, contentR, peers, router, mw.theme, mw.fontTitle, mw.fontBody, mw.fontSmall, mw.fontSubhead, &mw.hitboxes)
		case 1: // P2P Chat
			messages := mw.chatMgr.GetMessages()
			RenderChatView(memDC, contentR, mw.activePeer, messages, mw.typingPeer, mw.theme, mw.fontTitle, mw.fontBody, mw.fontSmall, mw.fontSubhead, &mw.hitboxes)
		case 2: // CCTV Stream & Computer Vision AI
			RenderCCTVView(memDC, contentR, mw.cctv, mw.theme, mw.fontTitle, mw.fontBody, mw.fontSmall, mw.fontSubhead, &mw.hitboxes)
		case 3: // Voice & Walkie-Talkie Calling
			RenderCallView(memDC, contentR, mw.signaling, mw.theme, mw.fontTitle, mw.fontBody, mw.fontSmall, mw.fontSubhead, &mw.hitboxes)
		case 4: // AI Fleet Hub
			aiCfg := mw.cfgMgr.GetConfig().AIConfig
			hw := models.HardwareComputeInfo{
				LoadPercent: 18,
				RAM:         "16 GB DDR4",
				GPU:         "NVIDIA RTX / Intel Xe",
			}
			RenderAIFleetView(memDC, contentR, aiCfg, hw, mw.theme, mw.fontTitle, mw.fontBody, mw.fontSmall, mw.fontSubhead, &mw.hitboxes)
		case 5: // IoT & Hardware Peripherals
			support := mw.iotMgr.GetSupportMatrix()
			devices := mw.iotMgr.GetDevices()
			schedules := mw.iotAuto.GetSchedules()
			RenderIoTView(memDC, contentR, support, devices, schedules, mw.theme, mw.fontTitle, mw.fontBody, mw.fontSmall, mw.fontSubhead, &mw.hitboxes)
		case 6: // Transfers & Logs
			mw.mu.RLock()
			tList := append([]models.TransferProgress(nil), mw.transfers...)
			lList := append([]string(nil), mw.logs...)
			mw.mu.RUnlock()
			RenderLogsView(memDC, contentR, tList, lList, mw.theme, mw.fontTitle, mw.fontBody, mw.fontSmall, mw.fontSubhead, &mw.hitboxes)
		case 7: // Settings & About NearMitra
			cfg := mw.cfgMgr.GetConfig()
			RenderSettingsView(memDC, contentR, cfg, mw.isDarkMode, mw.theme, mw.fontTitle, mw.fontBody, mw.fontSmall, mw.fontSubhead, &mw.hitboxes)
		}

		// Blit to screen
		pBitBlt.Call(hdc, 0, 0, uintptr(clientRect.Right), uintptr(clientRect.Bottom), memDC, 0, 0, SRCCOPY)

		pSelectObject.Call(memDC, oldBmp)
		pDeleteObject.Call(memBitmap)
		pDeleteDC.Call(memDC)
		pEndPaint.Call(hwnd, uintptr(unsafe.Pointer(&ps)))
		return 0

	case WM_LBUTTONDOWN:
		x := int32(int16(lParam & 0xFFFF))
		y := int32(int16((lParam >> 16) & 0xFFFF))
		mw.handleMouseClick(x, y)
		return 0

	case WM_TIMER:
		mw.RequestRepaint()
		return 0

	case WM_TRAYICON:
		if lParam == 0x0205 { // WM_RBUTTONUP
			mw.tray.ShowContextMenu(
				func() {
					pShowWindow.Call(hwnd, SW_RESTORE)
					pSetForegroundWindow.Call(hwnd)
				},
				func() {
					OpenFolderInExplorer(mw.cfgMgr.GetConfig().SaveDirectory)
				},
				func() {
					mw.toggleTheme()
				},
				func() {
					pPostQuitMessage.Call(0)
				},
			)
		} else if lParam == 0x0201 { // WM_LBUTTONDOWN
			pShowWindow.Call(hwnd, SW_RESTORE)
			pSetForegroundWindow.Call(hwnd)
		}
		return 0

	case WM_CLOSE:
		pShowWindow.Call(hwnd, SW_HIDE)
		if mw.tray != nil {
			mw.tray.ShowNotification("NearMitra Minimized", "NearMitra is running in background system tray.")
		}
		return 0

	case WM_DESTROY:
		if mw.tray != nil {
			mw.tray.Remove()
		}
		pPostQuitMessage.Call(0)
		return 0
	}

	r, _, _ := pDefWindowProc.Call(hwnd, uintptr(msg), wParam, lParam)
	return r
}

func (mw *MainWindow) handleMouseClick(x, y int32) {
	mw.mu.RLock()
	boxes := append([]HitBox(nil), mw.hitboxes...)
	mw.mu.RUnlock()

	for _, b := range boxes {
		if x >= b.Rect.Left && x <= b.Rect.Right && y >= b.Rect.Top && y <= b.Rect.Bottom {
			mw.dispatchAction(b.Key)
			return
		}
	}
}

func (mw *MainWindow) dispatchAction(key string) {
	switch {
	case strings.HasPrefix(key, "TAB_"):
		var tab int
		fmt.Sscanf(key, "TAB_%d", &tab)
		mw.currentTab = tab
		mw.RequestRepaint()

	case key == "BTN_SEND_FILE":
		path, err := OpenFileDialog(mw.hwnd, "Select File to Send")
		if err == nil && path != "" {
			mw.sendSelectedFile(path)
		}

	case key == "BTN_SEND_FOLDER":
		folder, err := SelectFolderDialog(mw.cfgMgr.GetConfig().SaveDirectory)
		if err == nil && folder != "" {
			mw.sendSelectedFolder(folder)
		}

	case strings.HasPrefix(key, "PEER_CHAT_"):
		peerID := strings.TrimPrefix(key, "PEER_CHAT_")
		peers := mw.discovery.GetPeers()
		for _, p := range peers {
			if p.ID == peerID {
				mw.activePeer = p
				mw.currentTab = 1
				mw.RequestRepaint()
				break
			}
		}

	case strings.HasPrefix(key, "PEER_SEND_"):
		peerID := strings.TrimPrefix(key, "PEER_SEND_")
		peers := mw.discovery.GetPeers()
		for _, p := range peers {
			if p.ID == peerID {
				mw.activePeer = p
				path, err := OpenFileDialog(mw.hwnd, fmt.Sprintf("Select File for %s", p.Name))
				if err == nil && path != "" {
					go transfer.SendFile(p.IP, path, nil)
				}
				break
			}
		}

	case strings.HasPrefix(key, "COPY_MSG_"):
		msgID := strings.TrimPrefix(key, "COPY_MSG_")
		msgs := mw.chatMgr.GetMessages()
		for _, m := range msgs {
			if m.ID == msgID {
				CopyToClipboard(mw.hwnd, m.Text)
				mw.AddLog("Copied message to clipboard.")
				break
			}
		}

	case strings.HasPrefix(key, "REACT_"):
		parts := strings.Split(strings.TrimPrefix(key, "REACT_"), "_")
		if len(parts) >= 2 {
			msgID := parts[0]
			emoji := parts[1]
			mw.chatMgr.AddReaction(msgID, emoji)
			if mw.activePeer != nil {
				go transfer.SendReaction(mw.activePeer.IP, msgID, emoji)
			}
			mw.RequestRepaint()
		}

	case key == "BTN_CHAT_SEND":
		mw.sendChatMessage()

	case key == "BTN_CHAT_ATTACH":
		path, err := OpenFileDialog(mw.hwnd, "Select Attachment")
		if err == nil && path != "" {
			mw.sendSelectedFile(path)
		}

	case strings.HasPrefix(key, "PEER_CALL_"):
		peerID := strings.TrimPrefix(key, "PEER_CALL_")
		peers := mw.discovery.GetPeers()
		for _, p := range peers {
			if p.ID == peerID {
				mw.activePeer = p
				mw.signaling.InviteCall(p.IP, p.ID, p.Name, false)
				mw.currentTab = 3
				mw.AddLog(fmt.Sprintf("Initiated P2P Voice Call with %s (%s)", p.Name, p.IP))
				mw.RequestRepaint()
				break
			}
		}

	case strings.HasPrefix(key, "SET_CV_FILTER_"):
		filterStr := strings.TrimPrefix(key, "SET_CV_FILTER_")
		if mw.cctv != nil {
			mw.cctv.SetFilter(streaming.CVFilter(filterStr))
			mw.AddLog(fmt.Sprintf("Computer Vision Filter switched to: %s", filterStr))
		}
		mw.RequestRepaint()

	case key == "BTN_CCTV_RECORD":
		if mw.cctv != nil {
			if !mw.cctv.IsRecording {
				path, _ := mw.cctv.StartRecording()
				mw.AddLog(fmt.Sprintf("🔴 Live CCTV Recording Started: %s", path))
			} else {
				path, dur := mw.cctv.StopRecording()
				mw.AddLog(fmt.Sprintf("⏹ CCTV Recording Saved: %s (Duration: %v)", path, dur.Round(time.Second)))
			}
		}
		mw.RequestRepaint()

	case key == "BTN_CCTV_SNAPSHOT":
		if mw.cctv != nil {
			path, err := mw.cctv.SaveSnapshot()
			if err == nil {
				mw.AddLog(fmt.Sprintf("📸 Snapshot captured & saved: %s", path))
			}
		}
		mw.RequestRepaint()

	case key == "CALL_TOGGLE_PTT":
		if mw.signaling != nil {
			mw.signaling.SetPTT(!mw.signaling.PTTActive)
		}
		mw.RequestRepaint()

	case key == "CALL_TOGGLE_MUTE":
		if mw.signaling != nil {
			isMuted := mw.signaling.ToggleMute()
			status := "Unmuted"
			if isMuted {
				status = "Muted"
			}
			mw.AddLog(fmt.Sprintf("Microphone %s", status))
		}
		mw.RequestRepaint()

	case key == "CALL_TOGGLE_NOISE":
		if mw.signaling != nil {
			ns := mw.signaling.ToggleNoiseSuppression()
			status := "Disabled"
			if ns {
				status = "Enabled (Active AI Filter)"
			}
			mw.AddLog(fmt.Sprintf("AI Voice Noise Suppression %s", status))
		}
		mw.RequestRepaint()

	case key == "CALL_END":
		if mw.signaling != nil {
			mw.signaling.EndCall()
			mw.AddLog("Voice call session terminated.")
		}
		mw.RequestRepaint()

	case strings.HasPrefix(key, "SET_AI_MODEL_"):
		modelName := strings.TrimPrefix(key, "SET_AI_MODEL_")
		cfg := mw.cfgMgr.GetConfig().AIConfig
		if strings.Contains(modelName, "Gemini") {
			cfg.Provider = "gemini"
		} else if strings.Contains(modelName, "ChatGPT") {
			cfg.Provider = "openai"
		} else {
			cfg.Provider = "ollama"
		}
		mw.cfgMgr.SetAIConfig(cfg)
		mw.AddLog(fmt.Sprintf("Active AI Reasoning Model set to: %s", modelName))
		mw.RequestRepaint()

	case strings.HasPrefix(key, "RUN_AI_PRESET_"):
		var idx int
		fmt.Sscanf(key, "RUN_AI_PRESET_%d", &idx)
		presets := mw.aiService.GetPresets()
		if idx >= 0 && idx < len(presets) {
			p := presets[idx]
			mw.AddLog(fmt.Sprintf("Running AI Diagnostic: %s...", p.Title))
			go func() {
				_, _ = mw.aiService.GenerateResponse(p.PromptText)
				mw.RequestRepaint()
			}()
		}
		mw.RequestRepaint()

	case key == "BTN_CLEAR_LOGS":
		mw.mu.Lock()
		mw.logs = mw.logs[:0]
		mw.transfers = mw.transfers[:0]
		mw.mu.Unlock()
		mw.RequestRepaint()

	case key == "BTN_OPEN_SAVE_DIR":
		OpenFolderInExplorer(mw.cfgMgr.GetConfig().SaveDirectory)

	case key == "BTN_TOGGLE_THEME":
		mw.toggleTheme()

	case key == "IOT_PROBE_HW":
		mat := mw.iotMgr.RefreshDiagnostics()
		mw.AddLog(fmt.Sprintf("Hardware Re-probe: Wi-Fi: %v, BT: %v, LAN: %v, NFC: %v", mat.WiFiActive, mat.BluetoothActive, mat.LANActive, mat.NFCActive))
		mw.RequestRepaint()

	case strings.HasPrefix(key, "IOT_TOGGLE_"):
		devID := strings.TrimPrefix(key, "IOT_TOGGLE_")
		newState, err := mw.iotMgr.ToggleRelay(devID)
		if err == nil {
			statusStr := "OFF"
			if newState {
				statusStr = "ON"
			}
			mw.AddLog(fmt.Sprintf("Smart Irrigation Relay [%s] switched %s", devID, statusStr))
		}
		mw.RequestRepaint()

	case strings.HasPrefix(key, "IOT_PRINT_"):
		devID := strings.TrimPrefix(key, "IOT_PRINT_")
		if err := mw.iotMgr.TriggerTestPrint(devID); err != nil {
			mw.AddLog(err.Error())
		}
		mw.RequestRepaint()

	case strings.HasPrefix(key, "IOT_SCAN_"):
		devID := strings.TrimPrefix(key, "IOT_SCAN_")
		if err := mw.iotMgr.TriggerScan(devID); err != nil {
			mw.AddLog(err.Error())
		}
		mw.RequestRepaint()

	case strings.HasPrefix(key, "IOT_POLL_"):
		mw.AddLog("Use configured sensor polling in the IoT hub.")
		mw.RequestRepaint()

	case key == "IOT_ADD_AI_SCHEDULE":
		task, err := mw.iotAuto.ParseAIPromptSchedule("Auto-irrigate pump for 15 mins if soil moisture < 35%")
		if err == nil && task != nil {
			mw.AddLog(fmt.Sprintf("AI Automation Scheduled: %s for %d mins", task.DeviceName, task.DurationMinutes))
		}
		mw.RequestRepaint()
	}
}

func (mw *MainWindow) sendChatMessage() {
	var buf [1024]uint16
	pGetWindowText.Call(mw.hEditChat, uintptr(unsafe.Pointer(&buf[0])), 1024)
	text := syscall.UTF16ToString(buf[:])
	text = strings.TrimSpace(text)
	if text == "" {
		return
	}

	pSetWindowText.Call(mw.hEditChat, uintptr(unsafe.Pointer(UTF16Ptr(""))))

	msg := models.ChatMessage{
		ID:     fmt.Sprintf("msg_%d", time.Now().UnixNano()),
		Sender: mw.cfgMgr.GetConfig().DeviceName,
		PeerID: mw.cfgMgr.GetConfig().DeviceID,
		Text:   text,
		At:     time.Now(),
		Mine:   true,
		Status: "Sent",
	}
	mw.chatMgr.AddMessage(msg)

	if mw.activePeer != nil {
		go transfer.SendTextMessage(mw.activePeer.IP, msg.ID, text)
	}
	mw.RequestRepaint()
}

func (mw *MainWindow) sendSelectedFile(path string) {
	if mw.activePeer != nil {
		mw.AddLog(fmt.Sprintf("Initiating transfer of %s to %s", path, mw.activePeer.Name))
		go transfer.SendFile(mw.activePeer.IP, path, nil)
	} else {
		peers := mw.discovery.GetPeers()
		if len(peers) > 0 {
			mw.activePeer = peers[0]
			mw.AddLog(fmt.Sprintf("Sending %s to peer %s", path, peers[0].Name))
			go transfer.SendFile(peers[0].IP, path, nil)
		} else {
			mw.AddLog("No nearby peers online to receive file.")
		}
	}
}

func (mw *MainWindow) sendSelectedFolder(folder string) {
	if mw.activePeer != nil {
		mw.AddLog(fmt.Sprintf("Initiating folder transfer of %s to %s", folder, mw.activePeer.Name))
		go transfer.SendFolder(mw.activePeer.IP, folder, nil)
	} else {
		peers := mw.discovery.GetPeers()
		if len(peers) > 0 {
			mw.activePeer = peers[0]
			mw.AddLog(fmt.Sprintf("Sending folder %s to peer %s", folder, peers[0].Name))
			go transfer.SendFolder(peers[0].IP, folder, nil)
		} else {
			mw.AddLog("No nearby peers online to receive folder.")
		}
	}
}

func (mw *MainWindow) toggleTheme() {
	mw.isDarkMode = !mw.isDarkMode
	themeMode := "light"
	if mw.isDarkMode {
		mw.theme = DarkTheme
		themeMode = "dark"
	} else {
		mw.theme = LightTheme
	}
	mw.cfgMgr.SetThemeMode(themeMode)

	enableDarkMode := 0
	if mw.isDarkMode {
		enableDarkMode = 1
	}
	pDwmSetWindowAttribute.Call(mw.hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, uintptr(unsafe.Pointer(&enableDarkMode)), 4)
	mw.RequestRepaint()
}
