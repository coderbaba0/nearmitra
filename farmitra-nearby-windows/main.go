//go:build windows

package main

import (
	"archive/zip"
	"bufio"
	"bytes"
	"crypto/rand"
	"embed"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"
)

const (
	appName      = "Farmitra Nearby"
	discoverPort = 43888
	transferPort = 43889
	multicastIP  = "239.255.43.88"
	wmAppTray    = 0x8000 + 7
	wmAppUI      = 0x8000 + 8
	trayID       = 1001

	WS_OVERLAPPEDWINDOW = 0x00CF0000
	WS_VISIBLE          = 0x10000000
	WS_CHILD            = 0x40000000
	WS_CLIPCHILDREN     = 0x02000000
	ES_AUTOHSCROLL      = 0x0080
	WM_DESTROY          = 0x0002
	WM_PAINT            = 0x000F
	WM_CLOSE            = 0x0010
	WM_SIZE             = 0x0005
	WM_COMMAND          = 0x0111
	WM_CTLCOLOREDIT     = 0x0133
	WM_TIMER            = 0x0113
	WM_MOUSEMOVE        = 0x0200
	WM_LBUTTONDOWN      = 0x0201
	WM_LBUTTONDBLCLK    = 0x0203
	WM_MOUSEWHEEL       = 0x020A
	WM_RBUTTONUP        = 0x0205
	WM_CONTEXTMENU      = 0x007B
	WM_DROPFILES        = 0x0233
	WM_SETFONT          = 0x0030
	WM_SETICON          = 0x0080
	ICON_SMALL          = 0
	ICON_BIG            = 1
	WM_KEYDOWN          = 0x0100
	VK_RETURN           = 0x0D
	VK_CONTROL          = 0x11
	VK_V                = 0x56

	SW_HIDE            = 0
	SW_SHOW            = 5
	SW_RESTORE         = 9
	MB_OK              = 0
	MB_ICONINFORMATION = 0x40
	MB_ICONERROR       = 0x10
	NIM_ADD            = 0
	NIM_MODIFY         = 1
	NIM_DELETE         = 2
	NIF_MESSAGE        = 0x1
	NIF_ICON           = 0x2
	NIF_TIP            = 0x4
	NIF_INFO           = 0x10
	NIIF_INFO          = 0x1
	TPM_RIGHTBUTTON    = 0x0002
	MF_STRING          = 0
	MF_SEPARATOR       = 0x0800
	IMAGE_ICON         = 1
	LR_LOADFROMFILE    = 0x0010
	LR_DEFAULTSIZE     = 0x0040
	IDC_ARROW          = 32512
	IDI_APPLICATION    = 32512
	COLOR_WINDOW       = 5
	DT_LEFT            = 0
	DT_CENTER          = 1
	DT_RIGHT           = 2
	DT_VCENTER         = 4
	DT_WORDBREAK       = 0x10
	DT_SINGLELINE      = 0x20
	DT_END_ELLIPSIS    = 0x8000
	DT_CALCRECT        = 0x400
	TRANSPARENT        = 1
	SRCCOPY            = 0x00CC0020
	PS_SOLID           = 0
	FW_NORMAL          = 400
	FW_SEMIBOLD        = 600
	FW_BOLD            = 700
	CF_UNICODETEXT     = 13
	CF_DIB             = 8
	CF_HDROP           = 15
	GMEM_MOVEABLE      = 0x0002
)

const (
	idInput    = 103
	idTrayShow = 201
	idTrayExit = 202
)

//go:embed farmitra.ico
var assets embed.FS

type POINT struct{ X, Y int32 }
type RECT struct{ Left, Top, Right, Bottom int32 }
type SIZE struct{ CX, CY int32 }
type MSG struct {
	Hwnd           uintptr
	Message        uint32
	WParam, LParam uintptr
	Time           uint32
	Pt             POINT
}
type PAINTSTRUCT struct {
	Hdc         uintptr
	FErase      int32
	RcPaint     RECT
	FRestore    int32
	FIncUpdate  int32
	RgbReserved [32]byte
}
type WNDCLASSEX struct {
	CbSize, Style                            uint32
	LpfnWndProc                              uintptr
	CbClsExtra, CbWndExtra                   int32
	HInstance, HIcon, HCursor, HbrBackground uintptr
	LpszMenuName, LpszClassName              *uint16
	HIconSm                                  uintptr
}
type NOTIFYICONDATA struct {
	CbSize                        uint32
	HWnd                          uintptr
	UID, UFlags, UCallbackMessage uint32
	HIcon                         uintptr
	SzTip                         [128]uint16
	DwState, DwStateMask          uint32
	SzInfo                        [256]uint16
	UTimeoutOrVersion             uint32
	SzInfoTitle                   [64]uint16
	DwInfoFlags                   uint32
	GuidItem                      [16]byte
	HBalloonIcon                  uintptr
}

type peer struct {
	ID         string    `json:"id"`
	Name       string    `json:"name"`
	IP         string    `json:"ip,omitempty"`
	LastSeen   time.Time `json:"-"`
	AIHost     bool      `json:"ai_host,omitempty"`
	AIProvider string    `json:"ai_provider,omitempty"`
	AIModel    string    `json:"ai_model,omitempty"`
}
type wireHeader struct {
	Type     string `json:"type"`
	Sender   string `json:"sender"`
	SenderID string `json:"sender_id"`
	Message  string `json:"message,omitempty"`
	Name     string `json:"name,omitempty"`
	Size     int64  `json:"size,omitempty"`
	Folder   bool   `json:"folder,omitempty"`
	AIHost   bool   `json:"ai_host,omitempty"`
	Provider string `json:"provider,omitempty"`
	Model    string `json:"model,omitempty"`
	Done     bool   `json:"done,omitempty"`
}
type ChatMessage struct {
	ID                   string
	PeerID, Sender, Text string
	Mine                 bool
	At                   time.Time
	Kind                 string // text, file, folder, ai
	FileName             string
	FileSize             int64
	FilePath             string
	Status               string
}
type AIConfig struct {
	ShareAI     bool     `json:"share_ai"`
	AllowedAI   []string `json:"allowed_ai_devices,omitempty"`
	Provider    string   `json:"provider"`
	Model       string   `json:"model"`
	OllamaURL   string   `json:"ollama_url"`
	GroqModel   string   `json:"groq_model"`
	OpenAIModel string   `json:"openai_model"`
	GeminiModel string   `json:"gemini_model"`
	APIKey      string   `json:"-"`
}

type P2PConfig struct {
	SSID     string `json:"ssid"`
	Password string `json:"password"`
}

type P2PPeer struct {
	Name         string
	ID           string
	Connecting   bool
	Connected    bool
	Error        string
	DiscoveredAt time.Time
}

type P2PState struct {
	Active    bool
	Starting  bool
	Supported bool
	Checked   bool
	Status    string
	HostIP    string
	LastError string
}

type RouterInfo struct {
	Interface, Description, IPv4, Gateway, DNS, MAC, LinkSpeed, SSID, BSSID, Signal, RxRate, TxRate string
	Neighbors                                                                                       int
	RouterReachable                                                                                 bool
	Updated                                                                                         time.Time
}
type hitRect struct {
	key string
	r   RECT
}

var (
	user32                      = syscall.NewLazyDLL("user32.dll")
	shell32                     = syscall.NewLazyDLL("shell32.dll")
	kernel32                    = syscall.NewLazyDLL("kernel32.dll")
	gdi32                       = syscall.NewLazyDLL("gdi32.dll")
	comctl32                    = syscall.NewLazyDLL("comctl32.dll")
	dwmapi                      = syscall.NewLazyDLL("dwmapi.dll")
	pRegisterClassEx            = user32.NewProc("RegisterClassExW")
	pCreateWindowEx             = user32.NewProc("CreateWindowExW")
	pDefWindowProc              = user32.NewProc("DefWindowProcW")
	pShowWindow                 = user32.NewProc("ShowWindow")
	pUpdateWindow               = user32.NewProc("UpdateWindow")
	pGetMessage                 = user32.NewProc("GetMessageW")
	pTranslateMessage           = user32.NewProc("TranslateMessage")
	pDispatchMessage            = user32.NewProc("DispatchMessageW")
	pPostQuitMessage            = user32.NewProc("PostQuitMessage")
	pPostMessage                = user32.NewProc("PostMessageW")
	pSendMessage                = user32.NewProc("SendMessageW")
	pSetWindowText              = user32.NewProc("SetWindowTextW")
	pSetWindowLongPtr           = user32.NewProc("SetWindowLongPtrW")
	pCallWindowProc             = user32.NewProc("CallWindowProcW")
	pGetWindowTextLength        = user32.NewProc("GetWindowTextLengthW")
	pGetWindowText              = user32.NewProc("GetWindowTextW")
	pMessageBox                 = user32.NewProc("MessageBoxW")
	pDestroyWindow              = user32.NewProc("DestroyWindow")
	pLoadCursor                 = user32.NewProc("LoadCursorW")
	pLoadIcon                   = user32.NewProc("LoadIconW")
	pLoadImage                  = user32.NewProc("LoadImageW")
	pSetForegroundWindow        = user32.NewProc("SetForegroundWindow")
	pCreatePopupMenu            = user32.NewProc("CreatePopupMenu")
	pAppendMenu                 = user32.NewProc("AppendMenuW")
	pTrackPopupMenu             = user32.NewProc("TrackPopupMenu")
	pDestroyMenu                = user32.NewProc("DestroyMenu")
	pGetCursorPos               = user32.NewProc("GetCursorPos")
	pMoveWindow                 = user32.NewProc("MoveWindow")
	pInvalidateRect             = user32.NewProc("InvalidateRect")
	pGetClientRect              = user32.NewProc("GetClientRect")
	pBeginPaint                 = user32.NewProc("BeginPaint")
	pEndPaint                   = user32.NewProc("EndPaint")
	pFillRect                   = user32.NewProc("FillRect")
	pDrawText                   = user32.NewProc("DrawTextW")
	pTextOut                    = gdi32.NewProc("TextOutW")
	pGetTextExtentPoint32       = gdi32.NewProc("GetTextExtentPoint32W")
	pSetTimer                   = user32.NewProc("SetTimer")
	pKillTimer                  = user32.NewProc("KillTimer")
	pGetFocus                   = user32.NewProc("GetFocus")
	pGetKeyState                = user32.NewProc("GetKeyState")
	pIsClipboardFormatAvailable = user32.NewProc("IsClipboardFormatAvailable")
	pOpenClipboard              = user32.NewProc("OpenClipboard")
	pCloseClipboard             = user32.NewProc("CloseClipboard")
	pEmptyClipboard             = user32.NewProc("EmptyClipboard")
	pSetClipboardData           = user32.NewProc("SetClipboardData")
	pCreateFont                 = gdi32.NewProc("CreateFontW")
	pCreateSolidBrush           = gdi32.NewProc("CreateSolidBrush")
	pCreatePen                  = gdi32.NewProc("CreatePen")
	pDeleteObject               = gdi32.NewProc("DeleteObject")
	pSelectObject               = gdi32.NewProc("SelectObject")
	pSetBkMode                  = gdi32.NewProc("SetBkMode")
	pSetTextColor               = gdi32.NewProc("SetTextColor")
	pSetBkColor                 = gdi32.NewProc("SetBkColor")
	pGetStockObject             = gdi32.NewProc("GetStockObject")
	pRoundRect                  = gdi32.NewProc("RoundRect")
	pEllipse                    = gdi32.NewProc("Ellipse")
	pMoveToEx                   = gdi32.NewProc("MoveToEx")
	pLineTo                     = gdi32.NewProc("LineTo")
	pCreateCompatibleDC         = gdi32.NewProc("CreateCompatibleDC")
	pCreateCompatibleBitmap     = gdi32.NewProc("CreateCompatibleBitmap")
	pCreateRectRgn              = gdi32.NewProc("CreateRectRgn")
	pSelectClipRgn              = gdi32.NewProc("SelectClipRgn")
	pDeleteDC                   = gdi32.NewProc("DeleteDC")
	pBitBlt                     = gdi32.NewProc("BitBlt")
	pShellNotifyIcon            = shell32.NewProc("Shell_NotifyIconW")
	pShellExecute               = shell32.NewProc("ShellExecuteW")
	pDragAcceptFiles            = shell32.NewProc("DragAcceptFiles")
	pDragQueryFile              = shell32.NewProc("DragQueryFileW")
	pDragFinish                 = shell32.NewProc("DragFinish")
	pSetAppID                   = shell32.NewProc("SetCurrentProcessExplicitAppUserModelID")
	pGetModuleHandle            = kernel32.NewProc("GetModuleHandleW")
	pGlobalAlloc                = kernel32.NewProc("GlobalAlloc")
	pGlobalLock                 = kernel32.NewProc("GlobalLock")
	pGlobalUnlock               = kernel32.NewProc("GlobalUnlock")
	pGlobalFree                 = kernel32.NewProc("GlobalFree")
	pInitCommonControls         = comctl32.NewProc("InitCommonControls")
	pDwmSetWindowAttribute      = dwmapi.NewProc("DwmSetWindowAttribute")
)

var app *App
var uiSeq uint64
var uiJobs sync.Map

type App struct {
	hwnd, input, trayIcon, iconSmall, iconBig, inputBrush              uintptr
	inputOldProc                                                       uintptr
	font, fontSmall, fontTiny, fontBold, fontTitle, fontHero, fontMono uintptr
	name, id, recvDir, assetDir                                        string
	peers                                                              map[string]*peer
	mu                                                                 sync.Mutex
	scanMu                                                             sync.Mutex
	selectedPeerID                                                     string
	chats                                                              []ChatMessage
	logs                                                               []string
	progressLabel                                                      string
	progressPct                                                        int
	transferSpeed                                                      string
	transferETA                                                        string
	progressMu                                                         sync.Mutex
	progressPrevDone                                                   int64
	progressPrevAt                                                     time.Time
	progressSmooth                                                     float64
	scanning                                                           bool
	scanStarted                                                        time.Time
	hover                                                              string
	dark                                                               bool
	startup                                                            bool
	routerOpen                                                         bool
	routerLoading                                                      bool
	router                                                             RouterInfo
	hits                                                               []hitRect
	peerHits                                                           []hitRect
	chatScroll                                                         int
	chatScrollMax                                                      int
	chatScrollTrack, chatScrollThumb                                   RECT
	peerScroll                                                         int
	peerScrollMax                                                      int
	peerScrollTrack, peerScrollThumb                                   RECT
	mouseX, mouseY                                                     int
	unread                                                             map[string]int
	typingUntil                                                        map[string]time.Time
	lastTypingSent                                                     map[string]time.Time
	networkSignature                                                   string
	logScroll                                                          int
	width, height                                                      int
	aiMode                                                             bool
	aiBusy                                                             bool
	aiConfig                                                           AIConfig
	copyFeedbackID                                                     string
	copyFeedbackUntil                                                  time.Time
	p2pOpen                                                            bool
	p2pConfig                                                          P2PConfig
	p2p                                                                P2PState
	p2pMu                                                              sync.Mutex
	p2pProcess                                                         *exec.Cmd
	p2pPeerProcess                                                     *exec.Cmd
	p2pPeers                                                           []P2PPeer
	p2pScanning                                                        bool
	p2pRadarStarted                                                    time.Time
}

func wstr(s string) *uint16    { p, _ := syscall.UTF16PtrFromString(s); return p }
func rgb(r, g, b byte) uintptr { return uintptr(r) | uintptr(g)<<8 | uintptr(b)<<16 }
func postUI(fn func()) {
	if app == nil || app.hwnd == 0 {
		return
	}
	id := atomic.AddUint64(&uiSeq, 1)
	uiJobs.Store(uintptr(id), fn)
	pPostMessage.Call(app.hwnd, wmAppUI, uintptr(id), 0)
}
func getText(h uintptr) string {
	n, _, _ := pGetWindowTextLength.Call(h)
	b := make([]uint16, n+1)
	if n > 0 {
		pGetWindowText.Call(h, uintptr(unsafe.Pointer(&b[0])), n+1)
	}
	return syscall.UTF16ToString(b)
}
func setText(h uintptr, s string) { pSetWindowText.Call(h, uintptr(unsafe.Pointer(wstr(s)))) }
func invalidate() {
	if app != nil && app.hwnd != 0 {
		pInvalidateRect.Call(app.hwnd, 0, 0)
	}
}

func main() {
	runtime.LockOSThread()
	// Stable taskbar identity so Windows uses Farmitra Nearby runtime icon/grouping.
	pSetAppID.Call(uintptr(unsafe.Pointer(wstr("Farmitra.Nearby.Desktop"))))
	pInitCommonControls.Call()
	hInst, _, _ := pGetModuleHandle.Call(0)
	name, _ := os.Hostname()
	recv := filepath.Join(os.Getenv("USERPROFILE"), "Downloads", "Farmitra Nearby")
	_ = os.MkdirAll(recv, 0755)
	assetDir := filepath.Join(os.Getenv("APPDATA"), "FarmitraNearby", "assets")
	_ = os.MkdirAll(assetDir, 0755)
	writeEmbedded("farmitra.ico", filepath.Join(assetDir, "farmitra.ico"))
	app = &App{name: name, id: machineID(), recvDir: recv, assetDir: assetDir, peers: map[string]*peer{}, unread: map[string]int{}, typingUntil: map[string]time.Time{}, lastTypingSent: map[string]time.Time{}, progressLabel: "Ready • Select a nearby device", startup: startupEnabled()}
	app.aiConfig = loadAIConfig()
	app.p2pConfig = loadP2PConfig()
	iconPath := filepath.Join(assetDir, "farmitra.ico")
	iconBig, _, _ := pLoadImage.Call(0, uintptr(unsafe.Pointer(wstr(iconPath))), IMAGE_ICON, 32, 32, LR_LOADFROMFILE)
	iconSmall, _, _ := pLoadImage.Call(0, uintptr(unsafe.Pointer(wstr(iconPath))), IMAGE_ICON, 16, 16, LR_LOADFROMFILE)
	if iconBig == 0 {
		iconBig, _, _ = pLoadIcon.Call(0, IDI_APPLICATION)
	}
	if iconSmall == 0 {
		iconSmall = iconBig
	}
	app.iconBig, app.iconSmall, app.trayIcon = iconBig, iconSmall, iconSmall
	icon := iconBig
	cls := wstr("FarmitraNearbyV71SmoothRadar")
	cur, _, _ := pLoadCursor.Call(0, IDC_ARROW)
	wc := WNDCLASSEX{CbSize: uint32(unsafe.Sizeof(WNDCLASSEX{})), LpfnWndProc: syscall.NewCallback(wndProc), HInstance: hInst, HIcon: icon, HCursor: cur, HbrBackground: COLOR_WINDOW + 1, LpszClassName: cls, HIconSm: icon}
	pRegisterClassEx.Call(uintptr(unsafe.Pointer(&wc)))
	hwnd, _, _ := pCreateWindowEx.Call(0, uintptr(unsafe.Pointer(cls)), uintptr(unsafe.Pointer(wstr("Farmitra Nearby — Continuous P2P Radar, Chat & AI"))), WS_OVERLAPPEDWINDOW|WS_CLIPCHILDREN, 90, 60, 1280, 820, 0, 0, hInst, 0)
	if hwnd == 0 {
		return
	}
	app.hwnd = hwnd
	// Explicitly set both runtime taskbar/title icons. This avoids Windows falling
	// back to a generic application icon when the window is created from Go.
	pSendMessage.Call(hwnd, WM_SETICON, ICON_BIG, app.iconBig)
	pSendMessage.Call(hwnd, WM_SETICON, ICON_SMALL, app.iconSmall)
	app.createUI(hInst)
	app.addTray(icon)
	pDragAcceptFiles.Call(hwnd, 1)
	pSetTimer.Call(hwnd, 1, 16, 0)
	// Windows 11 rounded corners / dark title bar support where available.
	corner := uint32(2)
	pDwmSetWindowAttribute.Call(hwnd, 33, uintptr(unsafe.Pointer(&corner)), unsafe.Sizeof(corner))
	go app.discoveryLoop()
	go app.listenDiscovery()
	go app.listenTransfers()
	go app.maintainPeers()
	go app.networkRecoveryLoop()
	bg := false
	for _, s := range os.Args[1:] {
		if s == "--background" {
			bg = true
		}
	}
	if bg {
		pShowWindow.Call(hwnd, SW_HIDE)
	} else {
		pShowWindow.Call(hwnd, SW_SHOW)
		pUpdateWindow.Call(hwnd)
	}
	var m MSG
	for {
		r, _, _ := pGetMessage.Call(uintptr(unsafe.Pointer(&m)), 0, 0, 0)
		if int32(r) <= 0 {
			break
		}
		pTranslateMessage.Call(uintptr(unsafe.Pointer(&m)))
		pDispatchMessage.Call(uintptr(unsafe.Pointer(&m)))
	}
}

func writeEmbedded(name, dest string) {
	b, e := assets.ReadFile(name)
	if e == nil {
		_ = os.WriteFile(dest, b, 0644)
	}
}
func machineID() string {
	d := filepath.Join(os.Getenv("APPDATA"), "FarmitraNearby")
	_ = os.MkdirAll(d, 0755)
	f := filepath.Join(d, "device.id")
	if b, e := os.ReadFile(f); e == nil && strings.TrimSpace(string(b)) != "" {
		return strings.TrimSpace(string(b))
	}
	id := fmt.Sprintf("%d-%d", time.Now().UnixNano(), os.Getpid())
	_ = os.WriteFile(f, []byte(id), 0600)
	return id
}

func (a *App) createUI(hInst uintptr) {
	mkFont := func(px int, weight int, name string) uintptr {
		h, _, _ := pCreateFont.Call(uintptr(int32(-px)), 0, 0, 0, uintptr(weight), 0, 0, 0, 1, 0, 0, 5, 0, uintptr(unsafe.Pointer(wstr(name))))
		return h
	}
	a.font = mkFont(16, FW_NORMAL, "Segoe UI Variable Text")
	a.fontSmall = mkFont(14, FW_NORMAL, "Segoe UI Variable Text")
	a.fontTiny = mkFont(12, FW_NORMAL, "Segoe UI Variable Text")
	a.fontBold = mkFont(16, FW_SEMIBOLD, "Segoe UI Variable Text")
	// Bahnschrift gives the header/brand a cleaner modern Windows character while
	// keeping chat/body text on Segoe UI Variable for readability.
	a.fontTitle = mkFont(21, FW_SEMIBOLD, "Bahnschrift")
	a.fontHero = mkFont(29, FW_SEMIBOLD, "Bahnschrift")
	a.fontMono = mkFont(14, FW_NORMAL, "Cascadia Mono")
	h, _, _ := pCreateWindowEx.Call(0, uintptr(unsafe.Pointer(wstr("EDIT"))), uintptr(unsafe.Pointer(wstr(""))), WS_CHILD|WS_VISIBLE|ES_AUTOHSCROLL, 0, 0, 100, 38, a.hwnd, idInput, hInst, 0)
	a.input = h
	// Subclass the single-line editor so Enter reliably sends instead of producing
	// the default edit-control beep.
	cb := syscall.NewCallback(inputWndProc)
	a.inputOldProc, _, _ = pSetWindowLongPtr.Call(h, ^uintptr(3), cb)
	pSendMessage.Call(h, WM_SETFONT, a.font, 1)
	a.updateInputBrush()
}

func inputWndProc(hwnd uintptr, msg uint32, wParam, lParam uintptr) uintptr {
	if msg == WM_KEYDOWN && app != nil {
		// Ctrl+V keeps native EDIT behavior for normal text, but clipboard images,
		// screenshots and copied files are routed through the existing transfer
		// engine. This lets Win+Shift+S -> Ctrl+V work like a modern messenger.
		if wParam == VK_V && keyDown(VK_CONTROL) && clipboardHasAttachment() {
			app.pasteClipboardAttachmentAsync()
			return 0
		}
		if wParam == VK_RETURN {
			app.startChatFromUI()
			return 0
		}
		// Any real editing key refreshes the remote typing indicator. The sender is
		// throttled so normal typing does not create excessive LAN traffic.
		if wParam != 0x10 && wParam != 0x11 && wParam != 0x12 { // Shift/Ctrl/Alt
			app.noteTypingFromUI()
		}
	}
	if app != nil && app.inputOldProc != 0 {
		r, _, _ := pCallWindowProc.Call(app.inputOldProc, hwnd, uintptr(msg), wParam, lParam)
		return r
	}
	r, _, _ := pDefWindowProc.Call(hwnd, uintptr(msg), wParam, lParam)
	return r
}

func keyDown(vk uintptr) bool {
	r, _, _ := pGetKeyState.Call(vk)
	return uint16(r)&0x8000 != 0
}

func clipboardHasAttachment() bool {
	if r, _, _ := pIsClipboardFormatAvailable.Call(CF_HDROP); r != 0 {
		return true
	}
	if r, _, _ := pIsClipboardFormatAvailable.Call(CF_DIB); r != 0 {
		return true
	}
	return false
}

func (a *App) pasteClipboardAttachmentAsync() {
	if a.aiMode {
		messageBox(a.hwnd, "Clipboard attachment", "Switch to People mode to send clipboard images or files to a nearby device.", false)
		return
	}
	if a.selectedPeer() == nil {
		messageBox(a.hwnd, "Select a device", "Choose a nearby device before pasting an image or file.", false)
		return
	}
	a.appendLog("Reading attachment from clipboard…")
	go func() {
		dir := filepath.Join(os.TempDir(), "FarmitraNearby", "Clipboard")
		_ = os.MkdirAll(dir, 0755)
		// PowerShell runs in STA because System.Windows.Forms.Clipboard requires it.
		// File-drop clipboard content is preferred; screenshots/images are persisted
		// as PNG and then sent by the battle-tested normal file-transfer path.
		script := fmt.Sprintf(`[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; if([System.Windows.Forms.Clipboard]::ContainsFileDropList()){ $f=[System.Windows.Forms.Clipboard]::GetFileDropList(); [Console]::Write(($f -join [Environment]::NewLine)); exit }; if([System.Windows.Forms.Clipboard]::ContainsImage()){ $img=[System.Windows.Forms.Clipboard]::GetImage(); $p='%s'; $img.Save($p,[System.Drawing.Imaging.ImageFormat]::Png); $img.Dispose(); [Console]::Write($p) }`, strings.ReplaceAll(filepath.Join(dir, fmt.Sprintf("clipboard-%s.png", time.Now().Format("20060102-150405.000"))), "'", "''"))
		out, e := runPickerPowerShell(script)
		if e != nil {
			a.appendLog("Clipboard paste failed: " + e.Error())
			return
		}
		var paths []string
		for _, line := range strings.Split(strings.ReplaceAll(out, "\r", ""), "\n") {
			line = strings.TrimSpace(line)
			if line != "" {
				paths = append(paths, line)
			}
		}
		if len(paths) == 0 {
			a.appendLog("Clipboard does not contain an image or file attachment")
			return
		}
		postUI(func() {
			if len(paths) == 1 && strings.HasPrefix(strings.ToLower(filepath.Base(paths[0])), "clipboard-") {
				a.appendLogUI("Screenshot pasted • sending image…")
			} else {
				a.appendLogUI(fmt.Sprintf("Pasted %d clipboard attachment(s) • sending…", len(paths)))
			}
			a.startPathsFromUI(paths)
		})
	}()
}

func wndProc(hwnd uintptr, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case wmAppUI:
		if fn, ok := uiJobs.LoadAndDelete(wParam); ok {
			fn.(func())()
		}
		invalidate()
		return 0
	case WM_SIZE:
		if app != nil {
			app.width = int(uint16(lParam & 0xffff))
			app.height = int(uint16((lParam >> 16) & 0xffff))
			app.layoutInput()
		}
		invalidate()
		return 0
	case WM_PAINT:
		if app != nil {
			app.paint()
		}
		return 0
	case WM_TIMER:
		if app != nil {
			// Keep micro-animations fluid while scanning/transferring and briefly after a new message.
			animating := app.scanning || app.p2pScanning || app.p2p.Starting || (app.progressPct > 0 && app.progressPct < 100) || time.Since(app.scanStarted) < 350*time.Millisecond
			if len(app.chats) > 0 && time.Since(app.chats[len(app.chats)-1].At) < 320*time.Millisecond {
				animating = true
			}
			if app.selectedPeerTyping() {
				animating = true
			}
			if app.copyFeedbackID != "" && time.Now().Before(app.copyFeedbackUntil) {
				animating = true
			}
			if animating {
				invalidate()
			}
		}
		return 0
	case WM_MOUSEMOVE:
		if app != nil {
			x := int(int16(lParam & 0xffff))
			y := int(int16((lParam >> 16) & 0xffff))
			app.mouseX, app.mouseY = x, y
			h := app.hitAt(x, y)
			if h != app.hover {
				app.hover = h
				invalidate()
			}
		}
		return 0
	case WM_LBUTTONDOWN:
		if app != nil {
			x := int(int16(lParam & 0xffff))
			y := int(int16((lParam >> 16) & 0xffff))
			app.click(x, y)
		}
		return 0
	case WM_MOUSEWHEEL:
		if app != nil {
			delta := int16((wParam >> 16) & 0xffff)
			// When the pointer is over the nearby-device pane, scroll that list only.
			side := 300
			if app.width < 980 {
				side = 250
			}
			if app.mouseX < side && app.mouseY >= 250 && app.mouseY < app.height-205 && app.peerScrollMax > 0 {
				if delta > 0 {
					app.peerScroll -= 62
				} else {
					app.peerScroll += 62
				}
				if app.peerScroll < 0 {
					app.peerScroll = 0
				}
				if app.peerScroll > app.peerScrollMax {
					app.peerScroll = app.peerScrollMax
				}
			} else {
				// Wheel up moves toward older messages; wheel down returns to newest.
				if delta > 0 {
					app.chatScroll += 84
				} else {
					app.chatScroll -= 84
				}
				if app.chatScroll < 0 {
					app.chatScroll = 0
				}
				if app.chatScroll > app.chatScrollMax {
					app.chatScroll = app.chatScrollMax
				}
			}
			invalidate()
		}
		return 0
	case WM_KEYDOWN:
		if wParam == VK_RETURN && app != nil && pGetFocusCall() == app.input {
			app.startChatFromUI()
			return 0
		}
	case WM_DROPFILES:
		if app != nil {
			app.handleDrop(wParam)
		}
		return 0
	case WM_CTLCOLOREDIT:
		if app != nil && lParam == app.input {
			_, _, _, text, _, _, _, _, _ := app.palette()
			bg := rgb(255, 255, 255)
			if app.dark {
				bg = rgb(35, 42, 38)
			}
			pSetBkColor.Call(wParam, bg)
			pSetTextColor.Call(wParam, text)
			return app.inputBrush
		}
	case WM_COMMAND:
		return 0
	case WM_CLOSE:
		// Minimize silently to tray. Notifications are reserved for incoming chat/files only.
		pShowWindow.Call(hwnd, SW_HIDE)
		return 0
	case wmAppTray:
		if lParam == WM_LBUTTONDBLCLK {
			pShowWindow.Call(hwnd, SW_RESTORE)
			pSetForegroundWindow.Call(hwnd)
			return 0
		}
		if lParam == WM_RBUTTONUP || lParam == WM_CONTEXTMENU {
			showTrayMenu(hwnd)
			return 0
		}
	case WM_DESTROY:
		if app != nil {
			app.p2pMu.Lock()
			if app.p2pProcess != nil && app.p2pProcess.Process != nil {
				_ = app.p2pProcess.Process.Kill()
			}
			app.p2pProcess = nil
			app.p2pMu.Unlock()
			app.removeTray()
			pKillTimer.Call(hwnd, 1)
		}
		pPostQuitMessage.Call(0)
		return 0
	}
	r, _, _ := pDefWindowProc.Call(hwnd, uintptr(msg), wParam, lParam)
	return r
}
func pGetFocusCall() uintptr { r, _, _ := pGetFocus.Call(); return r }

func (a *App) updateInputBrush() {
	if a.inputBrush != 0 {
		pDeleteObject.Call(a.inputBrush)
	}
	c := rgb(255, 255, 255)
	if a.dark {
		c = rgb(35, 42, 38)
	}
	a.inputBrush, _, _ = pCreateSolidBrush.Call(c)
	if a.input != 0 {
		pInvalidateRect.Call(a.input, 0, 1)
	}
}
func contentYs(h int) (composerY, actionY, logY int) {
	// Reserve a real bottom activity panel instead of squeezing logs into a hidden strip.
	logH := 126
	if h < 650 {
		logH = 104
	}
	logY = h - logH - 24
	actionY = logY - 58
	composerY = actionY - 88
	return
}

func (a *App) layoutInput() {
	w, h := a.width, a.height
	if w < 760 {
		w = 760
	}
	if h < 560 {
		h = 560
	}
	side := 300
	if w < 980 {
		side = 250
	}
	mainX := side + 24
	composerY, _, _ := contentYs(h)
	// Leave room for an integrated attachment button and the Send button.
	inputX := mainX + 70
	inputW := w - inputX - 180 - 28
	if inputW < 150 {
		inputW = 150
	}
	pMoveWindow.Call(a.input, uintptr(inputX), uintptr(composerY+16), uintptr(inputW), 44, 1)
}

func (a *App) palette() (bg, surface, surface2, text, muted, green, greenSoft, border, logBg uintptr) {
	if a.dark {
		return rgb(14, 18, 16), rgb(23, 29, 26), rgb(31, 39, 35), rgb(244, 248, 245), rgb(148, 163, 154), rgb(48, 194, 93), rgb(28, 73, 44), rgb(53, 65, 58), rgb(18, 23, 20)
	}
	return rgb(244, 247, 245), rgb(255, 255, 255), rgb(248, 251, 249), rgb(25, 32, 28), rgb(98, 112, 104), rgb(42, 184, 82), rgb(226, 247, 233), rgb(218, 227, 221), rgb(238, 243, 240)
}

func (a *App) paint() {
	var ps PAINTSTRUCT
	hdc, _, _ := pBeginPaint.Call(a.hwnd, uintptr(unsafe.Pointer(&ps)))
	if hdc == 0 {
		return
	}
	defer pEndPaint.Call(a.hwnd, uintptr(unsafe.Pointer(&ps)))
	var rc RECT
	pGetClientRect.Call(a.hwnd, uintptr(unsafe.Pointer(&rc)))
	w := int(rc.Right)
	h := int(rc.Bottom)
	if w <= 0 || h <= 0 {
		return
	}
	a.width = w
	a.height = h
	mem, _, _ := pCreateCompatibleDC.Call(hdc)
	bmp, _, _ := pCreateCompatibleBitmap.Call(hdc, uintptr(w), uintptr(h))
	old, _, _ := pSelectObject.Call(mem, bmp)
	defer func() { pSelectObject.Call(mem, old); pDeleteObject.Call(bmp); pDeleteDC.Call(mem) }()
	bg, surface, surface2, text, muted, green, greenSoft, border, logBg := a.palette()
	fill(mem, RECT{0, 0, int32(w), int32(h)}, bg)
	a.hits = nil
	a.peerHits = nil
	side := 300
	if w < 980 {
		side = 250
	}
	// Sidebar surface
	fillRound(mem, RECT{12, 12, int32(side), int32(h - 12)}, 18, surface)
	// Compact text brand + vector leaf mark (no bitmap/logo image in the UI).
	a.drawLeafMark(mem, 28, 27, 28, green)
	drawText(mem, "Farmitra", RECT{64, 20, int32(side - 92), 52}, a.fontTitle, text, DT_LEFT|DT_VCENTER|DT_SINGLELINE)
	badge := RECT{int32(side - 92), 23, int32(side - 28), 49}
	fillRound(mem, badge, 13, greenSoft)
	drawText(mem, "NEARBY", badge, a.fontTiny, green, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	drawText(mem, "Fast. Private. On your local network.", RECT{28, 58, int32(side - 18), 82}, a.fontTiny, muted, DT_LEFT|DT_SINGLELINE)
	// Quick actions
	y := 92
	a.drawButton(mem, "scan", RECT{24, int32(y), int32(side - 24), int32(y + 42)}, "Scan nearby", false, green, surface2, text, border)
	y += 52
	p2pLabel := "Direct P2P"
	if a.p2p.Active {
		p2pLabel = "Direct P2P • Connected"
	}
	a.drawButton(mem, "p2p", RECT{24, int32(y), int32(side - 24), int32(y + 42)}, p2pLabel, a.p2p.Active, green, surface2, text, border)
	y += 52
	a.drawButton(mem, "router", RECT{24, int32(y), int32(side - 24), int32(y + 42)}, "Network & router", false, green, surface2, text, border)
	y += 62
	drawText(mem, "NEARBY DEVICES", RECT{28, int32(y), int32(side - 20), int32(y + 22)}, a.fontTiny, muted, DT_LEFT|DT_SINGLELINE)
	y += 30
	// Peer cards live inside an independently scrollable viewport so bottom controls remain fixed.
	peers := a.peerSnapshot()
	maxPeerY := h - 215
	listTop := y
	itemCount := len(peers)
	if a.aiMode {
		itemCount++
	}
	viewportH := max(0, maxPeerY-listTop)
	contentH := itemCount * 62
	a.peerScrollMax = max(0, contentH-viewportH)
	if a.peerScroll > a.peerScrollMax {
		a.peerScroll = a.peerScrollMax
	}
	if a.peerScroll < 0 {
		a.peerScroll = 0
	}
	y -= a.peerScroll
	shown := 0
	if a.aiMode && y+58 > listTop && y < maxPeerY {
		cfg := a.currentAIConfig()
		r := RECT{22, int32(y), int32(side - 22), int32(y + 54)}
		sel := a.selectedPeerID == "__local_ai__"
		col := surface2
		if sel {
			col = greenSoft
		}
		fillRound(mem, r, 12, col)
		if sel {
			fillRound(mem, RECT{22, int32(y + 7), 26, int32(y + 47)}, 2, green)
		}
		avatar := RECT{34, int32(y + 9), 70, int32(y + 45)}
		fillEllipse(mem, avatar, green)
		drawText(mem, "AI", avatar, a.fontTiny, rgb(255, 255, 255), DT_CENTER|DT_VCENTER|DT_SINGLELINE)
		drawText(mem, "This Device", RECT{82, int32(y + 9), int32(side - 36), int32(y + 30)}, a.fontBold, text, DT_LEFT|DT_SINGLELINE)
		localStatus := strings.Title(cfg.Provider) + "  •  " + effectiveAIModel(cfg) + "  •  Local"
		drawText(mem, localStatus, RECT{82, int32(y + 31), int32(side - 36), int32(y + 49)}, a.fontTiny, muted, DT_LEFT|DT_END_ELLIPSIS|DT_SINGLELINE)
		if y >= listTop && y+54 <= maxPeerY {
			a.peerHits = append(a.peerHits, hitRect{"selfAI", r})
		}
		y += 62
		shown++
	}
	for _, p := range peers {
		if y+58 <= listTop {
			y += 62
			continue
		}
		if y >= maxPeerY {
			break
		}
		if y < listTop || y+54 > maxPeerY {
			y += 62
			continue
		}
		r := RECT{22, int32(y), int32(side - 22), int32(y + 54)}
		sel := p.ID == a.selectedPeerID
		col := surface2
		if sel {
			col = greenSoft
		}
		fillRound(mem, r, 12, col)
		if sel {
			fillRound(mem, RECT{22, int32(y + 7), 26, int32(y + 47)}, 2, green)
		}
		avatar := RECT{34, int32(y + 9), 70, int32(y + 45)}
		fillEllipse(mem, avatar, green)
		initial := "?"
		if len([]rune(p.Name)) > 0 {
			initial = strings.ToUpper(string([]rune(p.Name)[0]))
		}
		drawText(mem, initial, avatar, a.fontBold, rgb(255, 255, 255), DT_CENTER|DT_VCENTER|DT_SINGLELINE)
		unread := a.unread[p.ID]
		nameRight := int32(side - 36)
		if unread > 0 {
			nameRight = int32(side - 70)
		}
		drawText(mem, p.Name, RECT{82, int32(y + 9), nameRight, int32(y + 30)}, a.fontBold, text, DT_LEFT|DT_END_ELLIPSIS|DT_SINGLELINE)
		// Keep the address muted but make the presence word clearly green.
		statusY := int32(y + 31)
		ipText := p.IP + "  •  "
		drawText(mem, ipText, RECT{82, statusY, nameRight, int32(y + 49)}, a.fontTiny, muted, DT_LEFT|DT_SINGLELINE)
		measure := RECT{0, 0, 400, 30}
		calcText(mem, ipText, &measure, a.fontTiny, DT_LEFT|DT_SINGLELINE)
		xOnline := int32(82) + (measure.Right - measure.Left)
		drawText(mem, "online", RECT{xOnline, statusY, nameRight, int32(y + 49)}, a.fontTiny, green, DT_LEFT|DT_SINGLELINE)
		if p.AIHost {
			measure2 := RECT{0, 0, 200, 30}
			calcText(mem, "online", &measure2, a.fontTiny, DT_LEFT|DT_SINGLELINE)
			xAI := xOnline + (measure2.Right - measure2.Left)
			drawText(mem, "  •  AI", RECT{xAI, statusY, nameRight, int32(y + 49)}, a.fontTiny, muted, DT_LEFT|DT_SINGLELINE)
		}
		if unread > 0 {
			label := strconv.Itoa(unread)
			if unread > 99 {
				label = "99+"
			}
			bw := int32(25)
			if unread > 9 {
				bw = 31
			}
			if unread > 99 {
				bw = 37
			}
			br := RECT{int32(side) - 30 - bw, int32(y + 14), int32(side) - 30, int32(y+14) + 25}
			fillRound(mem, br, 13, green)
			drawText(mem, label, br, a.fontTiny, rgb(255, 255, 255), DT_CENTER|DT_VCENTER|DT_SINGLELINE)
		}
		a.peerHits = append(a.peerHits, hitRect{"peer:" + p.ID, r})
		y += 62
		shown++
	}
	// Thin modern scrollbar for the nearby-device list.
	a.peerScrollTrack = RECT{int32(side - 15), int32(listTop), int32(side - 11), int32(maxPeerY)}
	if a.peerScrollMax > 0 && viewportH > 0 {
		trackH := viewportH
		thumbH := max(34, int(float64(trackH)*float64(viewportH)/float64(contentH)))
		travel := max(1, trackH-thumbH)
		thumbTop := listTop + int(float64(travel)*float64(a.peerScroll)/float64(a.peerScrollMax))
		a.peerScrollThumb = RECT{int32(side - 16), int32(thumbTop), int32(side - 10), int32(thumbTop + thumbH)}
		fillRound(mem, a.peerScrollTrack, 2, border)
		fillRound(mem, a.peerScrollThumb, 3, green)
	} else {
		a.peerScrollThumb = RECT{}
	}

	if shown == 0 && itemCount == 0 {
		drawText(mem, "No Farmitra Nearby devices yet.\nKeep this app open on another PC\non the same Wi‑Fi/LAN.", RECT{30, int32(y + 8), int32(side - 28), int32(y + 86)}, a.fontSmall, muted, DT_LEFT|DT_WORDBREAK)
	}
	// sidebar bottom
	bottomY := h - 236
	a.drawButton(mem, "received", RECT{24, int32(bottomY), int32(side - 24), int32(bottomY + 40)}, "Received files", false, green, surface2, text, border)
	bottomY += 50
	a.drawToggle(mem, "startup", RECT{24, int32(bottomY), int32(side - 24), int32(bottomY + 36)}, "Start with Windows", a.startup, text, muted, green, surface2)
	bottomY += 44
	a.drawButton(mem, "theme", RECT{24, int32(bottomY), int32(side - 24), int32(bottomY + 36)}, func() string {
		if a.dark {
			return "Light appearance"
		}
		return "Dark appearance"
	}(), false, green, surface2, text, border)
	bottomY += 44
	a.drawButton(mem, "about", RECT{24, int32(bottomY), int32(side - 24), int32(bottomY + 36)}, "About", false, green, surface2, text, border)

	mainX := side + 24
	mainR := RECT{int32(mainX), 12, int32(w - 12), int32(h - 12)}
	fillRound(mem, mainR, 18, surface)
	// Header
	title := "Chat & Transfers"
	sub := "Select a nearby device to start a private conversation"
	if a.aiMode && a.selectedPeerID == "__local_ai__" {
		cfg := a.currentAIConfig()
		title = "Nearby AI • This Device"
		sub = strings.Title(cfg.Provider) + "  •  " + effectiveAIModel(cfg) + "  •  runs locally on this PC"
	} else if p := a.selectedPeer(); p != nil {
		title = p.Name
		sub = p.IP + "  •  Direct LAN connection"
		if a.aiMode {
			title = "Nearby AI • " + p.Name
			if p.AIHost {
				sub = strings.TrimSpace(p.AIProvider + "  •  " + p.AIModel + "  •  runs on " + p.Name)
			} else {
				sub = "This device is not sharing Nearby AI"
			}
		}
	}
	drawText(mem, title, RECT{int32(mainX + 24), 24, int32(w - 220), 52}, a.fontTitle, text, DT_LEFT|DT_SINGLELINE)
	drawText(mem, sub, RECT{int32(mainX + 24), 54, int32(w - 220), 74}, a.fontSmall, muted, DT_LEFT|DT_SINGLELINE)
	// animated status pill
	statusR := RECT{int32(w - 190), 27, int32(w - 34), 59}
	statusCol := surface2
	fillRound(mem, statusR, 16, statusCol)
	if a.scanning {
		fillRound(mem, statusR, 16, greenSoft)
		a.drawSpinner(mem, int(statusR.Left)+19, int((statusR.Top+statusR.Bottom)/2), green, muted)
		drawText(mem, "Scanning…", RECT{statusR.Left + 34, statusR.Top, statusR.Right - 8, statusR.Bottom}, a.fontSmall, green, DT_LEFT|DT_VCENTER|DT_SINGLELINE)
	} else {
		fillEllipse(mem, RECT{statusR.Left + 13, statusR.Top + 12, statusR.Left + 21, statusR.Top + 20}, green)
		drawText(mem, "Ready", RECT{statusR.Left + 30, statusR.Top, statusR.Right - 8, statusR.Bottom}, a.fontSmall, muted, DT_LEFT|DT_VCENTER|DT_SINGLELINE)
	}
	// People / Nearby AI mode switch. AI settings always remain local to this PC.
	a.drawButton(mem, "peopleMode", RECT{int32(mainX + 20), 82, int32(mainX + 112), 116}, "People", !a.aiMode, green, surface2, text, border)
	a.drawButton(mem, "aiMode", RECT{int32(mainX + 120), 82, int32(mainX + 224), 116}, "Nearby AI", a.aiMode, green, surface2, text, border)
	a.drawButton(mem, "aiSettings", RECT{int32(mainX + 232), 82, int32(mainX + 346), 116}, "AI settings", false, green, surface2, text, border)
	// Chat canvas
	composerY, actionY, logY := contentYs(h)
	chatTop := 126
	chatBottom := composerY - 12
	chatR := RECT{int32(mainX + 16), int32(chatTop), int32(w - 28), int32(chatBottom)}
	fillRound(mem, chatR, 14, surface2)
	a.drawChat(mem, chatR, text, muted, green, greenSoft, surface, border)
	// Composer card and input area; native EDIT is placed on top.
	compR := RECT{int32(mainX + 16), int32(composerY), int32(w - 28), int32(composerY + 78)}
	fillRound(mem, compR, 14, surface2)
	// Composer: attachment action is integrated beside the message field.
	a.drawButton(mem, "attach", RECT{int32(mainX + 18), int32(composerY + 16), int32(mainX + 62), int32(composerY + 60)}, "", false, green, surface2, text, border)
	inputX := mainX + 70
	inputW := w - inputX - 180 - 28
	inputOutline := RECT{int32(inputX - 4), int32(composerY + 13), int32(inputX + inputW + 4), int32(composerY + 63)}
	strokeRound(mem, inputOutline, 13, border, 1)
	a.drawButton(mem, "send", RECT{int32(w - 172), int32(composerY + 16), int32(w - 44), int32(composerY + 60)}, "Send", true, green, surface2, text, border)
	// File/folder quick actions & transfer card.
	a.drawButton(mem, "file", RECT{int32(mainX + 18), int32(actionY), int32(mainX + 142), int32(actionY + 40)}, "File", false, green, surface2, text, border)
	a.drawButton(mem, "folder", RECT{int32(mainX + 154), int32(actionY), int32(mainX + 292), int32(actionY + 40)}, "Folder", false, green, surface2, text, border)
	progX := mainX + 310
	progR := RECT{int32(progX), int32(actionY), int32(w - 28), int32(actionY + 48)}
	fillRound(mem, progR, 12, surface2)
	strokeRound(mem, progR, 12, border, 1)
	labelRight := w - 92
	drawText(mem, a.progressLabel, RECT{int32(progX + 14), int32(actionY + 6), int32(labelRight), int32(actionY + 24)}, a.fontTiny, text, DT_LEFT|DT_END_ELLIPSIS|DT_SINGLELINE)
	meta := strings.TrimSpace(strings.Join(nonEmptyStrings(a.transferSpeed, a.transferETA), "  •  "))
	if meta == "" {
		meta = "Secure direct LAN transfer"
	}
	drawText(mem, meta, RECT{int32(progX + 14), int32(actionY + 25), int32(labelRight), int32(actionY + 41)}, a.fontTiny, muted, DT_LEFT|DT_END_ELLIPSIS|DT_SINGLELINE)
	pct := a.progressPct
	if pct < 0 {
		pct = 0
	}
	if pct > 100 {
		pct = 100
	}
	pill := RECT{int32(w - 82), int32(actionY + 8), int32(w - 40), int32(actionY + 32)}
	fillRound(mem, pill, 12, greenSoft)
	drawText(mem, fmt.Sprintf("%d%%", pct), pill, a.fontTiny, green, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	barY := actionY + 43
	fillRound(mem, RECT{int32(progX + 12), int32(barY), int32(w - 40), int32(barY + 4)}, 2, border)
	if pct > 0 {
		pw := float64(w-progX-52) * float64(pct) / 100
		endX := int32(float64(progX+12) + pw)
		fillRound(mem, RECT{int32(progX + 12), int32(barY), endX, int32(barY + 4)}, 2, green)
		// Tiny moving highlight gives active transfers a subtle, non-distracting motion cue.
		if pct < 100 && endX > int32(progX+24) {
			phase := int32((time.Now().UnixMilli() / 18) % int64(max(1, int(endX-int32(progX+14)))))
			sx := int32(progX+12) + phase
			fillRound(mem, RECT{sx, int32(barY), min32(sx+22, endX), int32(barY + 4)}, 2, func() uintptr {
				if a.dark {
					return rgb(105, 229, 139)
				}
				return rgb(104, 213, 134)
			}())
		}
	}
	// Real-time activity is now a dedicated visible bottom panel.
	logR := RECT{int32(mainX + 16), int32(logY), int32(w - 28), int32(h - 24)}
	fillRound(mem, logR, 12, logBg)
	fillEllipse(mem, RECT{int32(mainX + 30), int32(logY + 14), int32(mainX + 38), int32(logY + 22)}, green)
	drawText(mem, "ACTIVITY  •  REAL TIME", RECT{int32(mainX + 46), int32(logY + 10), int32(w - 44), int32(logY + 28)}, a.fontTiny, muted, DT_LEFT|DT_SINGLELINE)
	a.drawLogs(mem, RECT{int32(mainX + 30), int32(logY + 34), int32(w - 44), int32(h - 34)}, text, muted)
	if a.routerOpen {
		a.drawRouterModal(mem, w, h, surface, surface2, text, muted, green, greenSoft, border)
	}
	if a.p2pOpen {
		a.drawP2PModal(mem, w, h, surface, surface2, text, muted, green, greenSoft, border)
	}
	pBitBlt.Call(hdc, 0, 0, uintptr(w), uintptr(h), mem, 0, 0, SRCCOPY)
}

func nonEmptyStrings(vals ...string) []string {
	out := make([]string, 0, len(vals))
	for _, v := range vals {
		if strings.TrimSpace(v) != "" {
			out = append(out, strings.TrimSpace(v))
		}
	}
	return out
}

func (a *App) drawLeafMark(dc uintptr, x, y, size int, c uintptr) {
	// Simple two-leaf Farmitra mark drawn as vectors so it stays crisp at every DPI.
	fillEllipse(dc, RECT{int32(x), int32(y + 7), int32(x + size/2 + 5), int32(y + size)}, c)
	fillEllipse(dc, RECT{int32(x + size/2 - 2), int32(y), int32(x + size + 8), int32(y + size - 2)}, c)
	pen, _, _ := pCreatePen.Call(PS_SOLID, 2, c)
	old, _, _ := pSelectObject.Call(dc, pen)
	pMoveToEx.Call(dc, uintptr(x+size/2+2), uintptr(y+size), 0)
	pLineTo.Call(dc, uintptr(x+size/2), uintptr(y+size/2))
	pMoveToEx.Call(dc, uintptr(x+size/2+2), uintptr(y+size), 0)
	pLineTo.Call(dc, uintptr(x+size-1), uintptr(y+6))
	pSelectObject.Call(dc, old)
	pDeleteObject.Call(pen)
}

func (a *App) drawGlyph(dc uintptr, key string, r RECT, c uintptr) {
	cx, cy := int((r.Left+r.Right)/2), int((r.Top+r.Bottom)/2)
	pen, _, _ := pCreatePen.Call(PS_SOLID, 2, c)
	old, _, _ := pSelectObject.Call(dc, pen)
	defer func() { pSelectObject.Call(dc, old); pDeleteObject.Call(pen) }()
	if strings.HasPrefix(key, "p2pDevice:") {
		i, _ := strconv.Atoi(strings.TrimPrefix(key, "p2pDevice:"))
		go a.connectNativeWiFiDirectPeer(i)
		return
	}
	switch key {
	case "scan", "routerRefresh":
		// circular refresh arrow
		for i := 0; i < 18; i++ {
			a1 := float64(i) * math.Pi / 13
			a2 := float64(i+1) * math.Pi / 13
			x1 := cx + int(math.Cos(a1)*8)
			y1 := cy + int(math.Sin(a1)*8)
			x2 := cx + int(math.Cos(a2)*8)
			y2 := cy + int(math.Sin(a2)*8)
			pMoveToEx.Call(dc, uintptr(x1), uintptr(y1), 0)
			pLineTo.Call(dc, uintptr(x2), uintptr(y2))
		}
		pMoveToEx.Call(dc, uintptr(cx+8), uintptr(cy-5), 0)
		pLineTo.Call(dc, uintptr(cx+11), uintptr(cy-1))
		pLineTo.Call(dc, uintptr(cx+6), uintptr(cy))
	case "p2p":
		// Direct-link glyph: two peer nodes with a wireless bridge.
		fillEllipse(dc, RECT{int32(cx - 9), int32(cy - 3), int32(cx - 3), int32(cy + 3)}, c)
		fillEllipse(dc, RECT{int32(cx + 3), int32(cy - 3), int32(cx + 9), int32(cy + 3)}, c)
		pMoveToEx.Call(dc, uintptr(cx-2), uintptr(cy-5), 0)
		pLineTo.Call(dc, uintptr(cx+2), uintptr(cy-5))
		pMoveToEx.Call(dc, uintptr(cx-2), uintptr(cy+5), 0)
		pLineTo.Call(dc, uintptr(cx+2), uintptr(cy+5))
	case "router":
		pMoveToEx.Call(dc, uintptr(cx-9), uintptr(cy+5), 0)
		pLineTo.Call(dc, uintptr(cx+9), uintptr(cy+5))
		pMoveToEx.Call(dc, uintptr(cx-6), uintptr(cy+1), 0)
		pLineTo.Call(dc, uintptr(cx+6), uintptr(cy+1))
		pMoveToEx.Call(dc, uintptr(cx-3), uintptr(cy-3), 0)
		pLineTo.Call(dc, uintptr(cx+3), uintptr(cy-3))
	case "received":
		strokeRound(dc, RECT{int32(cx - 9), int32(cy - 8), int32(cx + 9), int32(cy + 8)}, 4, c, 1)
		pMoveToEx.Call(dc, uintptr(cx), uintptr(cy-5), 0)
		pLineTo.Call(dc, uintptr(cx), uintptr(cy+4))
		pMoveToEx.Call(dc, uintptr(cx-4), uintptr(cy), 0)
		pLineTo.Call(dc, uintptr(cx), uintptr(cy+4))
		pLineTo.Call(dc, uintptr(cx+4), uintptr(cy))
	case "theme":
		fillEllipse(dc, RECT{int32(cx - 7), int32(cy - 7), int32(cx + 7), int32(cy + 7)}, c)
	case "about":
		fillEllipse(dc, RECT{int32(cx - 8), int32(cy - 8), int32(cx + 8), int32(cy + 8)}, c)
		pMoveToEx.Call(dc, uintptr(cx), uintptr(cy-3), 0)
		pLineTo.Call(dc, uintptr(cx), uintptr(cy+6))
	case "file":
		strokeRound(dc, RECT{int32(cx - 7), int32(cy - 9), int32(cx + 7), int32(cy + 9)}, 3, c, 1)
		pMoveToEx.Call(dc, uintptr(cx+1), uintptr(cy-9), 0)
		pLineTo.Call(dc, uintptr(cx+7), uintptr(cy-3))
	case "folder":
		pMoveToEx.Call(dc, uintptr(cx-9), uintptr(cy-5), 0)
		pLineTo.Call(dc, uintptr(cx-2), uintptr(cy-5))
		pLineTo.Call(dc, uintptr(cx+1), uintptr(cy-2))
		pLineTo.Call(dc, uintptr(cx+9), uintptr(cy-2))
		pLineTo.Call(dc, uintptr(cx+8), uintptr(cy+7))
		pLineTo.Call(dc, uintptr(cx-9), uintptr(cy+7))
		pLineTo.Call(dc, uintptr(cx-9), uintptr(cy-5))
	case "attach":
		// paperclip-style attachment glyph
		pMoveToEx.Call(dc, uintptr(cx+5), uintptr(cy-7), 0)
		pLineTo.Call(dc, uintptr(cx-4), uintptr(cy+2))
		pLineTo.Call(dc, uintptr(cx-4), uintptr(cy+6))
		pLineTo.Call(dc, uintptr(cx), uintptr(cy+9))
		pLineTo.Call(dc, uintptr(cx+4), uintptr(cy+6))
		pLineTo.Call(dc, uintptr(cx+8), uintptr(cy+2))
	case "send":
		pMoveToEx.Call(dc, uintptr(cx-8), uintptr(cy-7), 0)
		pLineTo.Call(dc, uintptr(cx+9), uintptr(cy))
		pLineTo.Call(dc, uintptr(cx-8), uintptr(cy+7))
		pLineTo.Call(dc, uintptr(cx-4), uintptr(cy))
		pLineTo.Call(dc, uintptr(cx-8), uintptr(cy-7))
	case "copy":
		strokeRound(dc, RECT{int32(cx - 7), int32(cy - 7), int32(cx + 5), int32(cy + 5)}, 2, c, 1)
		strokeRound(dc, RECT{int32(cx - 3), int32(cy - 3), int32(cx + 9), int32(cy + 9)}, 2, c, 1)
	case "routerAdmin":
		pMoveToEx.Call(dc, uintptr(cx-8), uintptr(cy+6), 0)
		pLineTo.Call(dc, uintptr(cx+8), uintptr(cy-6))
		pMoveToEx.Call(dc, uintptr(cx+2), uintptr(cy-6), 0)
		pLineTo.Call(dc, uintptr(cx+8), uintptr(cy-6))
		pLineTo.Call(dc, uintptr(cx+8), uintptr(cy))
	}
}

func (a *App) drawSpinner(dc uintptr, cx, cy int, c, muted uintptr) {
	phase := int(time.Now().UnixMilli()/90) % 8
	for i := 0; i < 8; i++ {
		ang := float64(i) * math.Pi / 4
		x := cx + int(math.Cos(ang)*7)
		y := cy + int(math.Sin(ang)*7)
		col := muted
		if i == phase {
			col = c
		}
		fillEllipse(dc, RECT{int32(x - 2), int32(y - 2), int32(x + 2), int32(y + 2)}, col)
	}
}

func (a *App) drawButton(dc uintptr, key string, r RECT, label string, primary bool, green, surface2, text, border uintptr) {
	hovered := a.hover == key
	bg := surface2
	fg := text
	if primary {
		bg = green
		fg = rgb(255, 255, 255)
	} else if hovered {
		if a.dark {
			bg = rgb(43, 55, 48)
		} else {
			bg = rgb(236, 246, 240)
		}
	}
	fillRound(dc, r, 11, bg)
	if !primary {
		strokeRound(dc, r, 11, border, 1)
	}
	iconKeys := map[string]bool{"scan": true, "p2p": true, "router": true, "received": true, "theme": true, "file": true, "folder": true, "send": true, "attach": true, "routerRefresh": true, "routerAdmin": true}
	if iconKeys[key] {
		if label == "" {
			a.drawGlyph(dc, key, r, fg)
		} else {
			ir := RECT{r.Left + 10, r.Top + 8, r.Left + 34, r.Bottom - 8}
			a.drawGlyph(dc, key, ir, fg)
			drawText(dc, label, RECT{r.Left + 39, r.Top, r.Right - 12, r.Bottom}, a.fontBold, fg, DT_LEFT|DT_VCENTER|DT_SINGLELINE)
		}
	} else {
		drawText(dc, label, r, a.fontBold, fg, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	}
	a.hits = append(a.hits, hitRect{key, r})
}

func (a *App) drawToggle(dc uintptr, key string, r RECT, label string, on bool, text, muted, green, surface2 uintptr) {
	drawText(dc, label, RECT{r.Left, r.Top, r.Right - 54, r.Bottom}, a.fontSmall, text, DT_LEFT|DT_VCENTER|DT_SINGLELINE)
	tr := RECT{r.Right - 46, r.Top + 7, r.Right, r.Bottom - 7}
	c := rgb(190, 198, 193)
	if on {
		c = green
	}
	fillRound(dc, tr, 11, c)
	knobX := tr.Left + 3
	if on {
		knobX = tr.Right - 20
	}
	fillEllipse(dc, RECT{knobX, tr.Top + 3, knobX + 17, tr.Bottom - 3}, rgb(255, 255, 255))
	a.hits = append(a.hits, hitRect{key, r})
}

func cleanMarkdownInline(s string) string {
	// Friendly markdown links: [label](url) -> label (url). Inline emphasis markers
	// are intentionally kept here and consumed by parseInlineMarkdown below.
	for {
		lb := strings.Index(s, "[")
		if lb < 0 {
			break
		}
		mid := strings.Index(s[lb:], "](")
		if mid < 0 {
			break
		}
		mid += lb
		rp := strings.Index(s[mid+2:], ")")
		if rp < 0 {
			break
		}
		rp += mid + 2
		label := s[lb+1 : mid]
		url := s[mid+2 : rp]
		s = s[:lb] + label + " (" + url + ")" + s[rp+1:]
	}
	return s
}

type mdInlineRun struct {
	text  string
	font  uintptr
	color uintptr
}

func (a *App) parseInlineMarkdown(s string, baseFont uintptr, baseColor uintptr) []mdInlineRun {
	s = cleanMarkdownInline(s)
	runs := make([]mdInlineRun, 0, 6)
	var b strings.Builder
	bold, code, italic := false, false, false
	flush := func() {
		if b.Len() == 0 {
			return
		}
		font := baseFont
		if code {
			font = a.fontMono
		} else if bold {
			font = a.fontBold
		}
		// Italic markers are consumed even when the platform font fallback does not
		// expose a dedicated italic face; this still renders clean Markdown instead
		// of leaking * markers into the conversation.
		_ = italic
		runs = append(runs, mdInlineRun{text: b.String(), font: font, color: baseColor})
		b.Reset()
	}
	for i := 0; i < len(s); {
		if i+1 < len(s) && (s[i:i+2] == "**" || s[i:i+2] == "__") {
			flush()
			bold = !bold
			i += 2
			continue
		}
		if s[i] == '`' {
			flush()
			code = !code
			i++
			continue
		}
		if s[i] == '*' || s[i] == '_' {
			flush()
			italic = !italic
			i++
			continue
		}
		b.WriteByte(s[i])
		i++
	}
	flush()
	return runs
}

func gdiTextSize(dc uintptr, s string, font uintptr) (int, int) {
	if s == "" {
		return 0, 0
	}
	u := syscall.StringToUTF16(s)
	if len(u) <= 1 {
		return 0, 0
	}
	old, _, _ := pSelectObject.Call(dc, font)
	defer pSelectObject.Call(dc, old)
	var z SIZE
	pGetTextExtentPoint32.Call(dc, uintptr(unsafe.Pointer(&u[0])), uintptr(len(u)-1), uintptr(unsafe.Pointer(&z)))
	return int(z.CX), int(z.CY)
}

func gdiTextOut(dc uintptr, x, y int, s string, font, color uintptr) {
	if s == "" {
		return
	}
	u := syscall.StringToUTF16(s)
	if len(u) <= 1 {
		return
	}
	old, _, _ := pSelectObject.Call(dc, font)
	pSetBkMode.Call(dc, TRANSPARENT)
	pSetTextColor.Call(dc, color)
	pTextOut.Call(dc, uintptr(x), uintptr(y), uintptr(unsafe.Pointer(&u[0])), uintptr(len(u)-1))
	pSelectObject.Call(dc, old)
}

// layoutInlineRuns performs the same word wrapping for measuring and painting.
// That keeps bubble height stable and prevents Markdown from being measured with
// one layout and drawn with another.
func layoutInlineRuns(dc uintptr, runs []mdInlineRun, x, y, maxW, minLineH int, draw bool) int {
	if maxW < 40 {
		maxW = 40
	}
	cx, cy := 0, 0
	lineH := minLineH
	started := false
	for _, run := range runs {
		words := strings.Fields(run.text)
		for wi, word := range words {
			piece := word
			if started || wi > 0 {
				piece = " " + piece
			}
			pw, ph := gdiTextSize(dc, piece, run.font)
			if ph > lineH {
				lineH = ph + 3
			}
			if cx > 0 && cx+pw > maxW {
				cy += lineH
				cx = 0
				lineH = minLineH
				piece = word
				pw, ph = gdiTextSize(dc, piece, run.font)
				if ph > lineH {
					lineH = ph + 3
				}
			}
			if draw {
				gdiTextOut(dc, x+cx, y+cy, piece, run.font, run.color)
			}
			cx += pw
			started = true
		}
	}
	return cy + max(minLineH, lineH)
}

func (a *App) markdownHeight(dc uintptr, raw string, width int) int {
	if width < 100 {
		width = 100
	}
	lines := strings.Split(strings.ReplaceAll(raw, "\r\n", "\n"), "\n")
	h := 0
	inCode := false
	for _, ln := range lines {
		trim := strings.TrimSpace(ln)
		if strings.HasPrefix(trim, "```") {
			inCode = !inCode
			h += 6
			continue
		}
		if trim == "" {
			h += 10
			continue
		}
		if inCode {
			r := RECT{0, 0, int32(width), 4000}
			calcText(dc, ln, &r, a.fontMono, DT_WORDBREAK)
			h += max(20, int(r.Bottom-r.Top)) + 7
			continue
		}
		baseFont := a.font
		content := ln
		lineH := 22
		if strings.HasPrefix(trim, "# ") {
			baseFont = a.fontTitle
			content = strings.TrimSpace(trim[2:])
			lineH = 29
		} else if strings.HasPrefix(trim, "## ") {
			baseFont = a.fontBold
			content = strings.TrimSpace(trim[3:])
			lineH = 25
		} else if strings.HasPrefix(trim, "### ") {
			baseFont = a.fontBold
			content = strings.TrimSpace(trim[4:])
			lineH = 23
		} else if strings.HasPrefix(trim, "- ") || strings.HasPrefix(trim, "* ") {
			content = "• " + strings.TrimSpace(trim[2:])
		} else if strings.HasPrefix(trim, "> ") {
			content = "│ " + strings.TrimSpace(trim[2:])
		}
		runs := a.parseInlineMarkdown(content, baseFont, 0)
		h += layoutInlineRuns(dc, runs, 0, 0, width, lineH, false) + 5
	}
	return max(22, h)
}

func (a *App) drawMarkdown(dc uintptr, raw string, r RECT, text, muted, green, codeBg uintptr) {
	lines := strings.Split(strings.ReplaceAll(raw, "\r\n", "\n"), "\n")
	y := int(r.Top)
	inCode := false
	for _, ln := range lines {
		trim := strings.TrimSpace(ln)
		if strings.HasPrefix(trim, "```") {
			inCode = !inCode
			y += 6
			continue
		}
		if trim == "" {
			y += 10
			continue
		}
		if inCode {
			calc := RECT{0, 0, r.Right - r.Left, 4000}
			calcText(dc, ln, &calc, a.fontMono, DT_WORDBREAK)
			lh := max(20, int(calc.Bottom-calc.Top))
			bg := RECT{r.Left - 5, int32(y - 2), r.Right + 5, int32(y + lh + 4)}
			fillRound(dc, bg, 6, codeBg)
			drawText(dc, ln, RECT{r.Left, int32(y), r.Right, int32(y + lh + 2)}, a.fontMono, text, DT_LEFT|DT_WORDBREAK)
			y += lh + 7
			continue
		}
		baseFont, col := a.font, text
		content := ln
		lineH := 22
		if strings.HasPrefix(trim, "# ") {
			baseFont = a.fontTitle
			col = green
			content = strings.TrimSpace(trim[2:])
			lineH = 29
		} else if strings.HasPrefix(trim, "## ") {
			baseFont = a.fontBold
			col = green
			content = strings.TrimSpace(trim[3:])
			lineH = 25
		} else if strings.HasPrefix(trim, "### ") {
			baseFont = a.fontBold
			content = strings.TrimSpace(trim[4:])
			lineH = 23
		} else if strings.HasPrefix(trim, "- ") || strings.HasPrefix(trim, "* ") {
			content = "• " + strings.TrimSpace(trim[2:])
		} else if strings.HasPrefix(trim, "> ") {
			content = "│ " + strings.TrimSpace(trim[2:])
			col = muted
		}
		runs := a.parseInlineMarkdown(content, baseFont, col)
		lh := layoutInlineRuns(dc, runs, int(r.Left), y, int(r.Right-r.Left), lineH, true)
		y += lh + 5
		if y >= int(r.Bottom) {
			break
		}
	}
}

func (a *App) drawChat(dc uintptr, r RECT, text, muted, green, greenSoft, surface, border uintptr) {
	msgs := a.visibleChats()
	a.chatScrollTrack = RECT{r.Right - 20, r.Top + 8, r.Right - 1, r.Bottom - 8}
	if len(msgs) == 0 {
		a.chatScrollMax = 0
		a.chatScroll = 0
		track := RECT{r.Right - 10, r.Top + 12, r.Right - 5, r.Bottom - 12}
		fillRound(dc, track, 3, border)
		a.chatScrollThumb = track
		cx := (r.Left + r.Right) / 2
		cy := (r.Top + r.Bottom) / 2
		fillEllipse(dc, RECT{cx - 30, cy - 60, cx + 30, cy}, greenSoft)
		a.drawGlyph(dc, "attach", RECT{cx - 18, cy - 48, cx + 18, cy - 12}, green)
		drawText(dc, "Start a nearby conversation", RECT{r.Left + 40, cy + 12, r.Right - 40, cy + 40}, a.fontBold, text, DT_CENTER|DT_SINGLELINE)
		drawText(dc, "Messages and shared files stay on your local network.", RECT{r.Left + 40, cy + 40, r.Right - 40, cy + 64}, a.fontSmall, muted, DT_CENTER|DT_SINGLELINE)
		return
	}
	maxW := min(680, int(r.Right-r.Left)*70/100)
	if maxW < 260 {
		maxW = max(190, int(r.Right-r.Left)-58)
	}
	// Pre-measure every bubble so scrolling is pixel-based. This fixes long AI answers
	// and makes the scrollbar represent the actual rendered content, not message count.
	heights := make([]int, len(msgs))
	widths := make([]int, len(msgs))
	contentH := 24
	for i, m := range msgs {
		attach := m.Kind == "file" || m.Kind == "folder"
		bw := maxW
		bh := 62
		if attach {
			bh = 88
			bw = min(maxW, 430)
		} else {
			bodyW := maxW - 32
			bodyH := 0
			if m.Kind == "ai" {
				bodyH = a.markdownHeight(dc, m.Text, bodyW)
			} else {
				tmp := RECT{0, 0, int32(bodyW), 8000}
				calcText(dc, m.Text, &tmp, a.font, DT_WORDBREAK)
				bodyH = max(20, int(tmp.Bottom-tmp.Top))
			}
			bh = bodyH + 68
			if bh < 74 {
				bh = 74
			}
		}
		heights[i] = bh
		widths[i] = bw
		contentH += bh + 12
	}
	if a.selectedPeerTyping() {
		contentH += 32
	}
	viewportH := max(1, int(r.Bottom-r.Top)-24)
	a.chatScrollMax = max(0, contentH-viewportH)
	if a.chatScroll < 0 {
		a.chatScroll = 0
	}
	if a.chatScroll > a.chatScrollMax {
		a.chatScroll = a.chatScrollMax
	}
	// Clip all message drawing to the chat viewport so huge markdown responses never
	// paint over the header/composer while the user scrolls through them.
	clip, _, _ := pCreateRectRgn.Call(uintptr(r.Left+2), uintptr(r.Top+2), uintptr(r.Right-22), uintptr(r.Bottom-2))
	if clip != 0 {
		pSelectClipRgn.Call(dc, clip)
		defer func() { pSelectClipRgn.Call(dc, 0); pDeleteObject.Call(clip) }()
	}
	typing := a.selectedPeerTyping()
	y := int(r.Bottom) - 18 + a.chatScroll
	if typing {
		y -= 30
	}
	for i := len(msgs) - 1; i >= 0; i-- {
		m := msgs[i]
		bh := heights[i]
		bw := widths[i]
		x := int(r.Left) + 22
		if m.Mine {
			x = int(r.Right) - bw - 30
		}
		slide := 0
		if i == len(msgs)-1 && a.chatScroll == 0 && time.Since(m.At) < 360*time.Millisecond {
			age := time.Since(m.At)
			slide = int(float64(18) * (1 - float64(age)/float64(360*time.Millisecond)))
			if !m.Mine {
				slide = -slide
			}
		}
		br := RECT{int32(x + slide), int32(y - bh), int32(x + bw + slide), int32(y)}
		visible := br.Bottom > r.Top+4 && br.Top < r.Bottom-4
		if visible {
			bg := surface
			if m.Mine {
				bg = greenSoft
			}
			fillRound(dc, br, 16, bg)
			if !m.Mine {
				strokeRound(dc, br, 16, border, 1)
			}
			who := m.Sender
			if m.Mine {
				who = "You"
			}
			headCol := muted
			if m.Mine {
				headCol = green
			}
			drawText(dc, who+"  •  "+m.At.Format("15:04"), RECT{br.Left + 15, br.Top + 10, br.Right - 15, br.Top + 30}, a.fontTiny, headCol, DT_LEFT|DT_SINGLELINE)
			attach := m.Kind == "file" || m.Kind == "folder"
			if attach {
				iconR := RECT{br.Left + 15, br.Top + 35, br.Left + 57, br.Bottom - 11}
				fillRound(dc, iconR, 10, func() uintptr {
					if m.Mine {
						return green
					}
					if a.dark {
						return rgb(44, 57, 49)
					}
					return rgb(233, 240, 235)
				}())
				glyphCol := green
				if m.Mine {
					glyphCol = rgb(255, 255, 255)
				}
				a.drawGlyph(dc, m.Kind, iconR, glyphCol)
				drawText(dc, m.FileName, RECT{br.Left + 69, br.Top + 35, br.Right - 15, br.Top + 57}, a.fontBold, text, DT_LEFT|DT_END_ELLIPSIS|DT_SINGLELINE)
				meta := humanSize(m.FileSize) + "  •  " + m.Status
				if m.Kind == "folder" {
					meta = "Folder  •  " + meta
				}
				drawText(dc, meta, RECT{br.Left + 69, br.Top + 58, br.Right - 15, br.Bottom - 11}, a.fontTiny, muted, DT_LEFT|DT_END_ELLIPSIS|DT_SINGLELINE)
				// Attachment cards are clickable. Received items open the same Received Files
				// folder as the sidebar button; sent items prefer their original folder when
				// a valid local path is still available, otherwise they fall back there too.
				attachHit := RECT{br.Left + 8, br.Top + 29, br.Right - 8, br.Bottom - 5}
				if attachHit.Bottom > r.Top && attachHit.Top < r.Bottom {
					a.hits = append(a.hits, hitRect{"openAttach:" + m.ID, attachHit})
				}
			} else {
				bodyR := RECT{br.Left + 15, br.Top + 33, br.Right - 15, br.Bottom - 31}
				if m.Kind == "ai" {
					codeBg := rgb(239, 244, 241)
					if a.dark {
						codeBg = rgb(18, 24, 21)
					}
					a.drawMarkdown(dc, m.Text, bodyR, text, muted, green, codeBg)
				} else {
					drawText(dc, m.Text, bodyR, a.font, text, DT_LEFT|DT_WORDBREAK)
				}
				copyR := RECT{br.Left + 14, br.Bottom - 27, br.Left + 42, br.Bottom - 5}
				copyCol := muted
				if a.hover == "copyMsg:"+m.ID {
					copyCol = green
				}
				a.drawGlyph(dc, "copy", copyR, copyCol)
				// Use a generous 76x34 hit target while keeping the icon visually compact.
				hit := RECT{br.Left + 7, br.Bottom - 35, br.Left + 83, br.Bottom - 1}
				if hit.Bottom > r.Top && hit.Top < r.Bottom {
					a.hits = append(a.hits, hitRect{"copyMsg:" + m.ID, hit})
				}
				if a.copyFeedbackID == m.ID && time.Now().Before(a.copyFeedbackUntil) {
					drawText(dc, "Copied", RECT{br.Left + 45, br.Bottom - 27, br.Left + 100, br.Bottom - 5}, a.fontTiny, green, DT_LEFT|DT_VCENTER|DT_SINGLELINE)
				}
			}
		}
		y -= bh + 12
		if y < int(r.Top)-contentH {
			break
		}
	}
	if typing && a.chatScroll == 0 {
		phase := int(time.Now().UnixMilli()/320) % 3
		dots := "."
		if phase == 1 {
			dots = ".."
		} else if phase == 2 {
			dots = "..."
		}
		tr := RECT{r.Left + 22, r.Bottom - 34, r.Right - 36, r.Bottom - 8}
		fillRound(dc, RECT{tr.Left, tr.Top, tr.Left + 198, tr.Bottom}, 12, surface)
		drawText(dc, a.selectedPeerName()+" is typing "+dots, RECT{tr.Left + 10, tr.Top + 4, tr.Left + 190, tr.Bottom - 2}, a.fontSmall, green, DT_LEFT|DT_SINGLELINE)
	}
	// Always-visible right-side scrollbar with a larger hit target and green thumb.
	track := RECT{r.Right - 10, r.Top + 12, r.Right - 5, r.Bottom - 12}
	fillRound(dc, track, 3, border)
	trackH := max(1, int(track.Bottom-track.Top))
	thumbH := trackH
	if contentH > viewportH {
		thumbH = max(44, trackH*viewportH/contentH)
	}
	travel := max(1, trackH-thumbH)
	ratio := 0.0
	if a.chatScrollMax > 0 {
		ratio = float64(a.chatScroll) / float64(a.chatScrollMax)
	}
	thumbTop := int(track.Bottom) - thumbH - int(math.Round(ratio*float64(travel)))
	thumb := RECT{track.Left - 4, int32(thumbTop), track.Right + 4, int32(thumbTop + thumbH)}
	a.chatScrollThumb = thumb
	thumbCol := green
	if a.chatScrollMax == 0 {
		thumbCol = muted
	}
	fillRound(dc, thumb, 6, thumbCol)
}

func (a *App) drawLogs(dc uintptr, r RECT, text, muted uintptr) {
	lines := a.logs
	if len(lines) == 0 {
		drawText(dc, "Waiting for activity…", r, a.fontTiny, muted, DT_LEFT|DT_SINGLELINE)
		return
	}
	lineH := 17
	maxLines := int(r.Bottom-r.Top) / lineH
	start := len(lines) - maxLines - a.logScroll
	if start < 0 {
		start = 0
	}
	end := start + maxLines
	if end > len(lines) {
		end = len(lines)
	}
	y := int(r.Top)
	for i := start; i < end; i++ {
		c := muted
		if strings.Contains(strings.ToLower(lines[i]), "failed") || strings.Contains(strings.ToLower(lines[i]), "error") {
			c = rgb(220, 74, 74)
		}
		drawText(dc, lines[i], RECT{r.Left, int32(y), r.Right, int32(y + lineH)}, a.fontTiny, c, DT_LEFT|DT_END_ELLIPSIS|DT_SINGLELINE)
		y += lineH
	}
}

func loadP2PConfig() P2PConfig {
	dir := filepath.Join(os.Getenv("APPDATA"), "FarmitraNearby")
	_ = os.MkdirAll(dir, 0755)
	path := filepath.Join(dir, "p2p-settings.json")
	var cfg P2PConfig
	if b, err := os.ReadFile(path); err == nil {
		_ = json.Unmarshal(b, &cfg)
	}
	if strings.TrimSpace(cfg.SSID) == "" {
		suffix := strings.ToUpper(strings.ReplaceAll(machineID(), "-", ""))
		if len(suffix) > 6 {
			suffix = suffix[:6]
		}
		cfg.SSID = "FarmitraNearby-" + suffix
	}
	if len(cfg.Password) < 8 {
		cfg.Password = randomP2PPassword()
	}
	if b, err := json.MarshalIndent(cfg, "", "  "); err == nil {
		_ = os.WriteFile(path, b, 0600)
	}
	return cfg
}

func randomP2PPassword() string {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
	b := make([]byte, 12)
	r := make([]byte, 12)
	if _, err := rand.Read(r); err != nil {
		return fmt.Sprintf("Fmtr%08d", time.Now().UnixNano()%100000000)
	}
	for i := range b {
		b[i] = alphabet[int(r[i])%len(alphabet)]
	}
	return string(b)
}

func runNetsh(args ...string) (string, error) {
	cmd := exec.Command("netsh", args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
	out, err := cmd.CombinedOutput()
	return string(out), err
}

func (a *App) p2pPublisherRunning() bool {
	a.p2pMu.Lock()
	defer a.p2pMu.Unlock()
	return a.p2pProcess != nil && a.p2pProcess.Process != nil && a.p2pProcess.ProcessState == nil
}

func (a *App) refreshP2PStatus() {
	publisherActive := a.p2pPublisherRunning()
	out, err := runNetsh("wlan", "show", "hostednetwork")
	low := strings.ToLower(out)
	legacySupported := !strings.Contains(low, "not supported") && !strings.Contains(low, "isn't supported") && !strings.Contains(low, "not available")
	legacyActive := strings.Contains(low, "status") && strings.Contains(low, "started")
	active := publisherActive || legacyActive
	supported := publisherActive || legacySupported
	status := "Ready to create a private routerless link"
	if publisherActive {
		status = "Wi‑Fi Direct P2P link is active"
	} else if legacyActive {
		status = "Direct hosted P2P link is active"
	}
	if !supported && !active {
		status = "Direct P2P needs Wi‑Fi Direct / hotspot support on this driver"
	}
	lastErr := ""
	if err != nil && strings.TrimSpace(out) == "" && !publisherActive {
		lastErr = err.Error()
	}
	hostIP := directP2PHostIP()
	postUI(func() {
		a.p2p.Checked = true
		a.p2p.Supported = supported
		a.p2p.Active = active
		a.p2p.Starting = false
		a.p2p.Status = status
		a.p2p.HostIP = hostIP
		a.p2p.LastError = lastErr
		invalidate()
	})
}

func directP2PHostIP() string {
	var fallback string
	ifaces, _ := net.Interfaces()
	for _, in := range ifaces {
		if in.Flags&net.FlagUp == 0 || in.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := in.Addrs()
		for _, ad := range addrs {
			ip, _, e := net.ParseCIDR(ad.String())
			if e != nil {
				continue
			}
			v := ip.To4()
			if v == nil {
				continue
			}
			s := v.String()
			if strings.HasPrefix(s, "192.168.137.") {
				return s
			}
			if strings.HasPrefix(s, "192.168.49.") {
				return s
			}
			if strings.HasPrefix(s, "192.168.") || strings.HasPrefix(s, "10.") || strings.HasPrefix(s, "172.") {
				fallback = s
			}
		}
	}
	return fallback
}

func psEncoded(script string) string {
	// PowerShell -EncodedCommand expects UTF-16LE.
	r := []rune(script)
	b := make([]byte, 0, len(r)*2)
	for _, ch := range r {
		if ch <= 0xFFFF {
			b = append(b, byte(ch), byte(ch>>8))
		} else {
			v := uint32(ch) - 0x10000
			hi := uint16(0xD800 + (v >> 10))
			lo := uint16(0xDC00 + (v & 0x3FF))
			b = append(b, byte(hi), byte(hi>>8), byte(lo), byte(lo>>8))
		}
	}
	return base64.StdEncoding.EncodeToString(b)
}

func (a *App) startWiFiDirectPublisher() (bool, string) {
	cfg := a.p2pConfig
	// WiFiDirectAdvertisementPublisher LegacySettings exposes an autonomous Wi‑Fi Direct
	// group as a normal WPA2 network, so Android can join it directly or via the QR.
	script := fmt.Sprintf(`$ErrorActionPreference='Stop';
[void][Windows.Devices.WiFiDirect.WiFiDirectAdvertisementPublisher,Windows.Devices.WiFiDirect,ContentType=WindowsRuntime];
$p=[Windows.Devices.WiFiDirect.WiFiDirectAdvertisementPublisher]::new();
$p.Advertisement.IsAutonomousGroupOwnerEnabled=$true;
$p.Advertisement.ListenStateDiscoverability=1;
$p.Advertisement.LegacySettings.IsEnabled=$true;
$p.Advertisement.LegacySettings.Ssid='%s';
$p.Advertisement.LegacySettings.Passphrase.Password='%s';
$p.Start(); Start-Sleep -Milliseconds 900;
if ($p.Status -eq 3) { throw 'Wi-Fi Direct publisher failed to start' }
Write-Output ('READY '+$p.Status);
while($true){ Start-Sleep -Seconds 30 }`, cfg.SSID, cfg.Password)
	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", psEncoded(script))
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	if err := cmd.Start(); err != nil {
		return false, err.Error()
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err := <-done:
		msg := strings.TrimSpace(out.String())
		if msg == "" && err != nil {
			msg = err.Error()
		}
		if msg == "" {
			msg = "Wi-Fi Direct publisher stopped"
		}
		return false, msg
	case <-time.After(1600 * time.Millisecond):
		a.p2pMu.Lock()
		a.p2pProcess = cmd
		a.p2pMu.Unlock()
		return true, strings.TrimSpace(out.String())
	}
}

func (a *App) startDirectP2P() {
	postUI(func() {
		a.p2p.Starting = true
		a.p2p.Status = "Creating private Wi‑Fi Direct link…"
		a.p2p.LastError = ""
		invalidate()
	})
	if ok, msg := a.startWiFiDirectPublisher(); ok {
		time.Sleep(600 * time.Millisecond)
		a.discoveryBurst()
		postUI(func() {
			a.p2p.Starting = false
			a.p2p.Active = true
			a.p2p.Supported = true
			a.p2p.Status = "Wi‑Fi Direct active • Scan the QR on the second device"
			a.p2p.HostIP = directP2PHostIP()
			a.p2p.LastError = ""
			a.appendLogUI("Direct P2P Wi‑Fi link started")
			invalidate()
		})
		return
	} else if strings.TrimSpace(msg) != "" {
		a.appendLog("Wi‑Fi Direct publisher fallback: " + strings.ReplaceAll(msg, "\r\n", " "))
	}
	// Compatibility fallback for older adapters that still expose Hosted Network.
	cfg := a.p2pConfig
	out1, e1 := runNetsh("wlan", "set", "hostednetwork", "mode=allow", "ssid="+cfg.SSID, "key="+cfg.Password, "keyUsage=persistent")
	if e1 != nil {
		msg := strings.TrimSpace(out1)
		if msg == "" {
			msg = e1.Error()
		}
		postUI(func() {
			a.p2p.Starting = false
			a.p2p.LastError = msg
			a.p2p.Status = "Direct P2P is unavailable on this Wi‑Fi driver"
			invalidate()
		})
		return
	}
	out2, e2 := runNetsh("wlan", "start", "hostednetwork")
	if e2 != nil || strings.Contains(strings.ToLower(out2), "couldn't") || strings.Contains(strings.ToLower(out2), "not in the correct state") {
		msg := strings.TrimSpace(out2)
		if msg == "" && e2 != nil {
			msg = e2.Error()
		}
		postUI(func() {
			a.p2p.Starting = false
			a.p2p.Active = false
			a.p2p.LastError = msg
			a.p2p.Status = "Direct P2P could not start • use Windows Hotspot fallback"
			invalidate()
		})
		return
	}
	time.Sleep(700 * time.Millisecond)
	a.discoveryBurst()
	postUI(func() {
		a.p2p.Starting = false
		a.p2p.Active = true
		a.p2p.Supported = true
		a.p2p.Status = "Direct P2P active • Scan the QR on the second device"
		a.p2p.HostIP = directP2PHostIP()
		a.appendLogUI("Direct P2P hosted link started")
		invalidate()
	})
}

func (a *App) stopDirectP2P() {
	a.p2pMu.Lock()
	cmd := a.p2pProcess
	peerCmd := a.p2pPeerProcess
	a.p2pProcess = nil
	a.p2pPeerProcess = nil
	a.p2pMu.Unlock()
	if cmd != nil && cmd.Process != nil {
		_ = cmd.Process.Kill()
	}
	if peerCmd != nil && peerCmd.Process != nil {
		_ = peerCmd.Process.Kill()
	}
	_, _ = runNetsh("wlan", "stop", "hostednetwork")
	postUI(func() {
		a.p2p.Active = false
		a.p2p.Starting = false
		a.p2p.Status = "Direct P2P stopped"
		a.appendLogUI("Direct P2P link stopped")
		invalidate()
	})
}

func queryNativeWiFiDirectPeers() ([]P2PPeer, string, error) {
	script := `$ErrorActionPreference='Stop';
Add-Type -AssemblyName System.Runtime.WindowsRuntime;
[void][Windows.Devices.WiFiDirect.WiFiDirectDevice,Windows.Devices.WiFiDirect,ContentType=WindowsRuntime];
[void][Windows.Devices.Enumeration.DeviceInformation,Windows.Devices.Enumeration,ContentType=WindowsRuntime];
$sel=[Windows.Devices.WiFiDirect.WiFiDirectDevice]::GetDeviceSelector();
$op=[Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync($sel);
$t=[System.WindowsRuntimeSystemExtensions]::AsTask($op); $t.Wait();
@($t.Result | ForEach-Object { [pscustomobject]@{name=$_.Name; id=$_.Id} }) | ConvertTo-Json -Compress`
	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", psEncoded(script))
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
	out, err := cmd.CombinedOutput()
	peers := []P2PPeer{}
	if err != nil {
		return peers, strings.TrimSpace(string(out)), err
	}
	var many []struct {
		Name string `json:"name"`
		ID   string `json:"id"`
	}
	if json.Unmarshal(out, &many) != nil {
		var one struct {
			Name string `json:"name"`
			ID   string `json:"id"`
		}
		if json.Unmarshal(out, &one) == nil && one.ID != "" {
			many = []struct {
				Name string `json:"name"`
				ID   string `json:"id"`
			}{one}
		}
	}
	for _, d := range many {
		if strings.TrimSpace(d.ID) == "" {
			continue
		}
		n := strings.TrimSpace(d.Name)
		if n == "" {
			n = "Wi-Fi Direct device"
		}
		peers = append(peers, P2PPeer{Name: n, ID: d.ID, DiscoveredAt: time.Now()})
	}
	return peers, "", nil
}

func (a *App) scanNativeWiFiDirectPeers() {
	// Direct P2P discovery is intentionally a discovery window, not a one-shot lookup.
	// Phones/drivers often become discoverable a few seconds after their radar starts.
	if a.p2pScanning {
		return
	}
	postUI(func() {
		a.p2pScanning = true
		a.p2pRadarStarted = time.Now()
		a.p2pPeers = nil
		a.p2p.Status = "Radar scanning • keep the other device's P2P radar open"
		a.p2p.LastError = ""
		invalidate()
	})

	deadline := time.Now().Add(30 * time.Second)
	found := map[string]P2PPeer{}
	first := true
	for time.Now().Before(deadline) {
		if !first {
			time.Sleep(2500 * time.Millisecond)
		}
		first = false
		if !a.p2pScanning { // connection/close can stop the discovery window early
			return
		}

		peers, detail, err := queryNativeWiFiDirectPeers()
		if err != nil {
			postUI(func() {
				a.p2pScanning = false
				a.p2p.Status = "Direct P2P radar unavailable on this adapter"
				a.p2p.LastError = detail
				if a.p2p.LastError == "" {
					a.p2p.LastError = err.Error()
				}
				a.appendLogUI("Direct P2P radar could not start")
				invalidate()
			})
			return
		}

		for _, p := range peers {
			if old, ok := found[p.ID]; ok {
				p.DiscoveredAt = old.DiscoveredAt
				p.Connecting = old.Connecting
				p.Connected = old.Connected
			}
			found[p.ID] = p
		}

		snapshot := make([]P2PPeer, 0, len(found))
		for _, p := range found {
			snapshot = append(snapshot, p)
		}
		sort.Slice(snapshot, func(i, j int) bool {
			if snapshot[i].Name == snapshot[j].Name {
				return snapshot[i].ID < snapshot[j].ID
			}
			return snapshot[i].Name < snapshot[j].Name
		})
		remaining := int(time.Until(deadline).Seconds())
		if remaining < 0 {
			remaining = 0
		}
		postUI(func() {
			a.p2pPeers = snapshot
			if len(snapshot) == 0 {
				a.p2p.Status = fmt.Sprintf("Scanning nearby P2P devices… %ds", remaining)
			} else {
				a.p2p.Status = fmt.Sprintf("Scanning • %d device(s) found • tap a node to connect", len(snapshot))
			}
			invalidate()
		})
	}

	postUI(func() {
		a.p2pScanning = false
		if len(a.p2pPeers) == 0 {
			a.p2p.Status = "No Direct P2P devices found • use QR fallback if needed"
		} else {
			a.p2p.Status = fmt.Sprintf("Found %d Direct P2P device(s) • tap a node to connect", len(a.p2pPeers))
		}
		a.appendLogUI(fmt.Sprintf("Direct P2P continuous scan finished • %d device(s)", len(a.p2pPeers)))
		invalidate()
	})
}

func (a *App) connectNativeWiFiDirectPeer(idx int) {
	if idx < 0 || idx >= len(a.p2pPeers) {
		return
	}
	peer := a.p2pPeers[idx]
	a.p2pScanning = false // pause radar while establishing the selected direct link
	postUI(func() {
		if idx < len(a.p2pPeers) {
			a.p2pPeers[idx].Connecting = true
			a.p2pPeers[idx].Error = ""
		}
		a.p2p.Status = "Connecting to " + peer.Name + "…"
		invalidate()
	})
	// Keep the WinRT Wi-Fi Direct object alive in a hidden PowerShell process so the
	// point-to-point link is not torn down as soon as the connection call returns.
	script := fmt.Sprintf(`$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.Runtime.WindowsRuntime;
[void][Windows.Devices.WiFiDirect.WiFiDirectDevice,Windows.Devices.WiFiDirect,ContentType=WindowsRuntime];
$op=[Windows.Devices.WiFiDirect.WiFiDirectDevice]::FromIdAsync('%s');
$t=[System.WindowsRuntimeSystemExtensions]::AsTask($op); $t.Wait(); $d=$t.Result;
if($null -eq $d){ throw 'Direct P2P connection was not created' }; Write-Output 'CONNECTED'; while($true){Start-Sleep -Seconds 30}`, strings.ReplaceAll(peer.ID, "'", "''"))
	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", psEncoded(script))
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	if err := cmd.Start(); err != nil {
		postUI(func() {
			if idx < len(a.p2pPeers) {
				a.p2pPeers[idx].Connecting = false
				a.p2pPeers[idx].Error = err.Error()
			}
			a.p2p.Status = "Direct P2P connection failed"
			invalidate()
		})
		return
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err := <-done:
		msg := strings.TrimSpace(out.String())
		if msg == "" && err != nil {
			msg = err.Error()
		}
		postUI(func() {
			if idx < len(a.p2pPeers) {
				a.p2pPeers[idx].Connecting = false
				a.p2pPeers[idx].Error = msg
			}
			a.p2p.Status = "Direct P2P connection failed"
			invalidate()
		})
	case <-time.After(2200 * time.Millisecond):
		a.p2pMu.Lock()
		if a.p2pPeerProcess != nil && a.p2pPeerProcess.Process != nil {
			_ = a.p2pPeerProcess.Process.Kill()
		}
		a.p2pPeerProcess = cmd
		a.p2pMu.Unlock()
		postUI(func() {
			if idx < len(a.p2pPeers) {
				a.p2pPeers[idx].Connecting = false
				a.p2pPeers[idx].Connected = true
			}
			a.p2p.Active = true
			a.p2p.Status = "Connected to " + peer.Name + " • enabling chat & files"
			a.appendLogUI("Direct P2P connected to " + peer.Name)
			invalidate()
		})
		time.Sleep(900 * time.Millisecond)
		a.discoveryBurst()
		_ = a.scanLAN()
	}
}

func wifiQREscape(s string) string {
	r := strings.NewReplacer("\\", "\\\\", ";", "\\;", ",", "\\,", ":", "\\:", "\"", "\\\"")
	return r.Replace(s)
}
func (a *App) p2pWiFiPayload() string {
	return "WIFI:T:WPA;S:" + wifiQREscape(a.p2pConfig.SSID) + ";P:" + wifiQREscape(a.p2pConfig.Password) + ";;"
}
func (a *App) p2pPairingText() string {
	ip := a.p2p.HostIP
	if ip == "" {
		ip = directP2PHostIP()
	}
	return fmt.Sprintf("Farmitra Nearby Direct P2P\nSSID: %s\nPassword: %s\nHost: %s:%d\nDevice ID: %s", a.p2pConfig.SSID, a.p2pConfig.Password, ip, transferPort, a.id)
}

// makeQRv4L creates a fixed Version-4 / Error-Correction-L QR matrix in byte mode.
// That is enough for the compact standard WIFI: pairing payload used by Direct P2P.
func makeQRv4L(text string) [][]bool {
	const size = 33
	dataBytes := []byte(text)
	if len(dataBytes) > 78 {
		dataBytes = dataBytes[:78]
	}
	var bits []bool
	addBits := func(v int, n int) {
		for i := n - 1; i >= 0; i-- {
			bits = append(bits, ((v>>i)&1) != 0)
		}
	}
	addBits(4, 4)
	addBits(len(dataBytes), 8)
	for _, b := range dataBytes {
		addBits(int(b), 8)
	}
	capBits := 80 * 8
	for i := 0; i < 4 && len(bits) < capBits; i++ {
		bits = append(bits, false)
	}
	for len(bits)%8 != 0 {
		bits = append(bits, false)
	}
	cw := make([]byte, 0, 100)
	for i := 0; i < len(bits); i += 8 {
		var v byte
		for j := 0; j < 8; j++ {
			if bits[i+j] {
				v |= 1 << uint(7-j)
			}
		}
		cw = append(cw, v)
	}
	pads := []byte{0xEC, 0x11}
	pi := 0
	for len(cw) < 80 {
		cw = append(cw, pads[pi&1])
		pi++
	}
	ecc := rsRemainder(cw, 20)
	cw = append(cw, ecc...)
	m := make([][]bool, size)
	fn := make([][]bool, size)
	for y := 0; y < size; y++ {
		m[y] = make([]bool, size)
		fn[y] = make([]bool, size)
	}
	setFn := func(x, y int, dark bool) {
		if x >= 0 && x < size && y >= 0 && y < size {
			m[y][x] = dark
			fn[y][x] = true
		}
	}
	drawFinder := func(cx, cy int) {
		for dy := -4; dy <= 4; dy++ {
			for dx := -4; dx <= 4; dx++ {
				x, y := cx+dx, cy+dy
				if x < 0 || x >= size || y < 0 || y >= size {
					continue
				}
				dist := max(abs(dx), abs(dy))
				setFn(x, y, dist != 2 && dist != 4)
			}
		}
	}
	drawFinder(3, 3)
	drawFinder(size-4, 3)
	drawFinder(3, size-4)
	for i := 8; i < size-8; i++ {
		setFn(6, i, i%2 == 0)
		setFn(i, 6, i%2 == 0)
	}
	drawAlign := func(cx, cy int) {
		for dy := -2; dy <= 2; dy++ {
			for dx := -2; dx <= 2; dx++ {
				setFn(cx+dx, cy+dy, max(abs(dx), abs(dy)) != 1)
			}
		}
	}
	drawAlign(26, 26)
	// Reserve format-information modules and fixed dark module.
	for i := 0; i < 6; i++ {
		setFn(8, i, false)
	}
	setFn(8, 7, false)
	setFn(8, 8, false)
	setFn(7, 8, false)
	for i := 9; i < 15; i++ {
		setFn(14-i, 8, false)
	}
	for i := 0; i < 8; i++ {
		setFn(size-1-i, 8, false)
	}
	for i := 8; i < 15; i++ {
		setFn(8, size-15+i, false)
	}
	setFn(8, size-8, true)
	// Version information is not required below version 7.
	all := make([]bool, 0, len(cw)*8)
	for _, b := range cw {
		for i := 7; i >= 0; i-- {
			all = append(all, ((b>>uint(i))&1) != 0)
		}
	}
	bi := 0
	upward := true
	for right := size - 1; right >= 1; right -= 2 {
		if right == 6 {
			right--
		}
		for vert := 0; vert < size; vert++ {
			y := vert
			if upward {
				y = size - 1 - vert
			}
			for j := 0; j < 2; j++ {
				x := right - j
				if fn[y][x] {
					continue
				}
				bit := false
				if bi < len(all) {
					bit = all[bi]
					bi++
				} // mask 0
				if (x+y)%2 == 0 {
					bit = !bit
				}
				m[y][x] = bit
			}
		}
		upward = !upward
	}
	format := qrFormatBits(1, 0) // L=01, mask 0
	fb := func(i int) bool { return ((format >> uint(i)) & 1) != 0 }
	for i := 0; i < 6; i++ {
		setFn(8, i, fb(i))
	}
	setFn(8, 7, fb(6))
	setFn(8, 8, fb(7))
	setFn(7, 8, fb(8))
	for i := 9; i < 15; i++ {
		setFn(14-i, 8, fb(i))
	}
	for i := 0; i < 8; i++ {
		setFn(size-1-i, 8, fb(i))
	}
	for i := 8; i < 15; i++ {
		setFn(8, size-15+i, fb(i))
	}
	setFn(8, size-8, true)
	return m
}
func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}
func qrFormatBits(ecc, mask int) int {
	d := (ecc << 3) | mask
	rem := d << 10
	for i := 14; i >= 10; i-- {
		if ((rem >> uint(i)) & 1) != 0 {
			rem ^= 0x537 << (i - 10)
		}
	}
	return ((d << 10) | rem) ^ 0x5412
}
func gfMul(x, y byte) byte {
	z := 0
	a := int(x)
	b := int(y)
	for b > 0 {
		if b&1 != 0 {
			z ^= a
		}
		b >>= 1
		a <<= 1
		if a&0x100 != 0 {
			a ^= 0x11D
		}
	}
	return byte(z)
}
func rsRemainder(data []byte, degree int) []byte {
	gen := []byte{1}
	root := byte(1)
	for i := 0; i < degree; i++ {
		next := make([]byte, len(gen)+1)
		for j, c := range gen {
			next[j] ^= c
			next[j+1] ^= gfMul(c, root)
		}
		gen = next
		root = gfMul(root, 2)
	}
	rem := make([]byte, degree)
	for _, b := range data {
		f := b ^ rem[0]
		copy(rem, rem[1:])
		rem[degree-1] = 0
		for j := 0; j < degree; j++ {
			rem[j] ^= gfMul(gen[j+1], f)
		}
	}
	return rem
}

func drawQR(dc uintptr, r RECT, text string, dark, light uintptr) {
	m := makeQRv4L(text)
	n := len(m)
	quiet := 4
	w := int(r.Right - r.Left)
	h := int(r.Bottom - r.Top)
	cell := min(w, h) / (n + quiet*2)
	if cell < 2 {
		cell = 2
	}
	qrW := cell * (n + quiet*2)
	x0 := int(r.Left) + (w-qrW)/2
	y0 := int(r.Top) + (h-qrW)/2
	fill(dc, RECT{int32(x0), int32(y0), int32(x0 + qrW), int32(y0 + qrW)}, light)
	for y := 0; y < n; y++ {
		for x := 0; x < n; x++ {
			if m[y][x] {
				xx := x0 + (x+quiet)*cell
				yy := y0 + (y+quiet)*cell
				fill(dc, RECT{int32(xx), int32(yy), int32(xx + cell), int32(yy + cell)}, dark)
			}
		}
	}
}

func (a *App) drawP2PModal(dc uintptr, w, h int, surface, surface2, text, muted, green, greenSoft, border uintptr) {
	fill(dc, RECT{0, 0, int32(w), int32(h)}, func() uintptr {
		if a.dark {
			return rgb(12, 15, 13)
		}
		return rgb(232, 236, 233)
	}())
	mw := min(920, w-60)
	mh := min(680, h-50)
	x := (w - mw) / 2
	y := (h - mh) / 2
	r := RECT{int32(x), int32(y), int32(x + mw), int32(y + mh)}
	fillRound(dc, r, 22, surface)
	strokeRound(dc, r, 22, border, 1)
	drawText(dc, "Direct P2P Radar", RECT{int32(x + 28), int32(y + 20), int32(x + mw - 110), int32(y + 54)}, a.fontTitle, text, DT_LEFT|DT_SINGLELINE)
	drawText(dc, "Find Farmitra devices without a router • QR is only a fallback", RECT{int32(x + 28), int32(y + 54), int32(x + mw - 120), int32(y + 78)}, a.fontSmall, muted, DT_LEFT|DT_SINGLELINE)
	a.drawButton(dc, "p2pClose", RECT{int32(x + mw - 96), int32(y + 20), int32(x + mw - 28), int32(y + 56)}, "Close", false, green, surface2, text, border)
	left := RECT{int32(x + 28), int32(y + 96), int32(x + mw/2 - 8), int32(y + mh - 78)}
	fillRound(dc, left, 16, surface2)
	drawText(dc, "Connection", RECT{left.Left + 18, left.Top + 14, left.Right - 18, left.Top + 40}, a.fontBold, text, DT_LEFT|DT_SINGLELINE)
	status := a.p2p.Status
	if status == "" {
		status = "Ready for Direct P2P radar scan"
	}
	drawText(dc, status, RECT{left.Left + 18, left.Top + 44, left.Right - 18, left.Top + 82}, a.fontSmall, func() uintptr {
		if a.p2p.Active {
			return green
		}
		return muted
	}(), DT_LEFT|DT_WORDBREAK)
	if a.p2pScanning {
		chip := RECT{left.Right - 118, left.Top + 12, left.Right - 18, left.Top + 38}
		fillRound(dc, chip, 13, greenSoft)
		drawText(dc, "SCANNING", chip, a.fontTiny, green, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	}
	cy := left.Top + 184
	cx := (left.Left + left.Right) / 2
	maxR := int32(116)
	// Polished radar: stable 60fps repaint, soft breathing rings and a sweep trail.
	elapsed := time.Since(a.p2pRadarStarted)
	phase := float64(elapsed.Milliseconds()%2400) / 2400.0
	ringColors := []uintptr{border, func() uintptr {
		if a.dark {
			return rgb(35, 66, 48)
		}
		return rgb(202, 224, 211)
	}(), func() uintptr {
		if a.dark {
			return rgb(28, 78, 48)
		}
		return rgb(188, 222, 202)
	}()}
	for idx, rr := range []int32{40, 78, 116} {
		pen, _, _ := pCreatePen.Call(0, 1, ringColors[idx])
		oldPen, _, _ := pSelectObject.Call(dc, pen)
		pEllipse.Call(dc, uintptr(cx-rr), uintptr(cy-rr), uintptr(cx+rr), uintptr(cy+rr))
		pSelectObject.Call(dc, oldPen)
		pDeleteObject.Call(pen)
	}
	// One expanding pulse gives the scanner depth without flicker.
	if a.p2pScanning {
		pulseR := int32(28 + phase*88)
		pulseColor := func() uintptr {
			if phase < .5 {
				return rgb(122, 205, 155)
			}
			return rgb(90, 166, 119)
		}()
		pen, _, _ := pCreatePen.Call(0, 1, pulseColor)
		oldPen, _, _ := pSelectObject.Call(dc, pen)
		pEllipse.Call(dc, uintptr(cx-pulseR), uintptr(cy-pulseR), uintptr(cx+pulseR), uintptr(cy+pulseR))
		pSelectObject.Call(dc, oldPen)
		pDeleteObject.Call(pen)
	}
	// Center beacon.
	if a.p2pScanning {
		breath := int32(9 + 3*math.Sin(float64(elapsed.Milliseconds())/220.0))
		fillEllipse(dc, RECT{cx - breath, cy - breath, cx + breath, cy + breath}, greenSoft)
	}
	fillEllipse(dc, RECT{cx - 6, cy - 6, cx + 6, cy + 6}, green)
	if a.p2pScanning {
		// A 2.1s sweep with a four-segment fading trail feels much smoother than a single hard line.
		baseAng := float64(elapsed.Milliseconds()%2100) / 2100.0 * 2 * math.Pi
		trail := []struct {
			off   float64
			col   uintptr
			width int
		}{
			{0.00, green, 3},
			{-0.055, rgb(69, 176, 108), 2},
			{-0.105, rgb(61, 135, 91), 2},
			{-0.155, rgb(52, 104, 73), 1},
		}
		for _, seg := range trail {
			ang := baseAng + seg.off
			ex := cx + int32(math.Cos(ang)*float64(maxR))
			ey := cy + int32(math.Sin(ang)*float64(maxR))
			pen, _, _ := pCreatePen.Call(0, uintptr(seg.width), seg.col)
			oldPen, _, _ := pSelectObject.Call(dc, pen)
			pMoveToEx.Call(dc, uintptr(cx), uintptr(cy), 0)
			pLineTo.Call(dc, uintptr(ex), uintptr(ey))
			pSelectObject.Call(dc, oldPen)
			pDeleteObject.Call(pen)
		}
	}
	// Deterministic positions prevent discovered devices from jumping around between repaints.
	for i, p := range a.p2pPeers {
		ang := float64(i)*2.35 - 0.7
		rad := float64(55 + (i%2)*43)
		px := cx + int32(math.Cos(ang)*rad)
		py := cy + int32(math.Sin(ang)*rad)
		c := green
		if p.Connecting {
			c = rgb(230, 160, 40)
		}
		if p.Connected {
			c = rgb(36, 185, 94)
		}
		// Fade/scale a newly found node in once instead of popping it onto the radar.
		age := time.Since(p.DiscoveredAt)
		nodeR := int32(10)
		if !p.DiscoveredAt.IsZero() && age < 360*time.Millisecond {
			t := float64(age.Milliseconds()) / 360.0
			t = 1 - math.Pow(1-t, 3) // ease-out cubic
			nodeR = int32(4 + 6*t)
		}
		// Hover/connecting halo.
		hitID := fmt.Sprintf("p2pDevice:%d", i)
		if a.hover == hitID || p.Connecting {
			halo := nodeR + 7 + int32(2*math.Sin(float64(elapsed.Milliseconds())/180.0))
			fillEllipse(dc, RECT{px - halo, py - halo, px + halo, py + halo}, greenSoft)
		}
		fillEllipse(dc, RECT{px - nodeR, py - nodeR, px + nodeR, py + nodeR}, c)
		nr := RECT{px - 52, py + 14, px + 52, py + 38}
		drawText(dc, p.Name, nr, a.fontTiny, text, DT_CENTER|DT_END_ELLIPSIS|DT_SINGLELINE)
		a.hits = append(a.hits, hitRect{hitID, RECT{px - 30, py - 30, px + 30, py + 42}})
	}
	if len(a.p2pPeers) == 0 {
		msg := "Ready to scan"
		if a.p2pScanning {
			msg = "Scanning nearby P2P devices…"
		}
		drawText(dc, msg, RECT{left.Left + 45, cy + maxR + 18, left.Right - 45, cy + maxR + 44}, a.fontSmall, muted, DT_CENTER|DT_SINGLELINE)
	}
	btnY := int(left.Bottom) - 54
	a.drawButton(dc, "p2pScan", RECT{left.Left + 18, int32(btnY), left.Left + 168, int32(btnY + 40)}, func() string {
		if a.p2pScanning {
			return "Scanning…"
		}
		return "Radar scan"
	}(), true, green, surface, text, border)
	a.drawButton(dc, "p2pStop", RECT{left.Left + 180, int32(btnY), left.Left + 286, int32(btnY + 40)}, "Disconnect", false, green, surface, text, border)
	right := RECT{int32(x + mw/2 + 8), int32(y + 96), int32(x + mw - 28), int32(y + mh - 78)}
	fillRound(dc, right, 16, surface2)
	drawText(dc, "Pairing fallback", RECT{right.Left + 18, right.Top + 14, right.Right - 18, right.Top + 40}, a.fontBold, text, DT_LEFT|DT_SINGLELINE)
	drawText(dc, "Use only when native Direct P2P discovery is unavailable on the other device/driver.", RECT{right.Left + 18, right.Top + 42, right.Right - 18, right.Top + 78}, a.fontSmall, muted, DT_LEFT|DT_WORDBREAK)
	if !a.p2p.Active {
		a.drawButton(dc, "p2pStart", RECT{right.Left + 18, right.Top + 92, right.Left + 176, right.Top + 132}, func() string {
			if a.p2p.Starting {
				return "Creating…"
			}
			return "Create fallback link"
		}(), false, green, surface, text, border)
	}
	qrSide := min(230, int(right.Right-right.Left)-76)
	qrR := RECT{right.Left + 38, right.Top + 148, right.Left + 38 + int32(qrSide), right.Top + 148 + int32(qrSide)}
	if a.p2p.Active {
		drawQR(dc, qrR, a.p2pWiFiPayload(), rgb(12, 18, 14), rgb(255, 255, 255))
	} else {
		fillRound(dc, qrR, 12, surface)
		drawText(dc, "Fallback QR appears\nafter creating a private link", qrR, a.fontSmall, muted, DT_CENTER|DT_VCENTER|DT_WORDBREAK)
	}
	qy := int(right.Bottom) - 54
	a.drawButton(dc, "p2pCopy", RECT{right.Left + 18, int32(qy), right.Left + 150, int32(qy + 40)}, "Copy details", false, green, surface, text, border)
	a.drawButton(dc, "p2pHotspotSettings", RECT{right.Left + 162, int32(qy), right.Right - 18, int32(qy + 40)}, "Hotspot fallback", false, green, surface, text, border)
	drawText(dc, "Radar requires the other Farmitra app to advertise Wi‑Fi Direct. Once connected, existing People chat, files and Nearby AI are reused automatically.", RECT{int32(x + 28), int32(y + mh - 62), int32(x + mw - 28), int32(y + mh - 22)}, a.fontTiny, muted, DT_LEFT|DT_WORDBREAK)
}

func (a *App) drawRouterModal(dc uintptr, w, h int, surface, surface2, text, muted, green, greenSoft, border uintptr) {
	// dim overlay
	fill(dc, RECT{0, 0, int32(w), int32(h)}, func() uintptr {
		if a.dark {
			return rgb(12, 15, 13)
		}
		return rgb(232, 236, 233)
	}())
	mw := min(760, w-80)
	mh := min(620, h-70)
	x := (w - mw) / 2
	y := (h - mh) / 2
	r := RECT{int32(x), int32(y), int32(x + mw), int32(y + mh)}
	fillRound(dc, r, 20, surface)
	strokeRound(dc, r, 20, border, 1)
	drawText(dc, "Network & Router", RECT{int32(x + 28), int32(y + 24), int32(x + mw - 120), int32(y + 56)}, a.fontTitle, text, DT_LEFT|DT_SINGLELINE)
	drawText(dc, "Live details reported by Windows", RECT{int32(x + 28), int32(y + 56), int32(x + mw - 120), int32(y + 80)}, a.fontSmall, muted, DT_LEFT|DT_SINGLELINE)
	a.drawButton(dc, "routerClose", RECT{int32(x + mw - 94), int32(y + 24), int32(x + mw - 28), int32(y + 58)}, "Close", false, green, surface2, text, border)
	if a.routerLoading {
		drawText(dc, "◌  Reading adapter, Wi‑Fi and gateway information…", RECT{int32(x + 28), int32(y + 110), int32(x + mw - 28), int32(y + 150)}, a.font, text, DT_LEFT|DT_SINGLELINE)
		return
	}
	info := a.router
	fields := [][2]string{{"Connection", nv(info.Interface)}, {"Network", nv(info.SSID)}, {"Local IPv4", nv(info.IPv4)}, {"Router / Gateway", nv(info.Gateway)}, {"Link speed", nv(info.LinkSpeed)}, {"Wi‑Fi signal", nv(info.Signal)}, {"Wi‑Fi RX / TX", joinNonEmpty(info.RxRate, info.TxRate, " / ")}, {"DNS", nv(info.DNS)}, {"Adapter MAC", nv(info.MAC)}, {"LAN neighbors", strconv.Itoa(info.Neighbors) + " detected"}}
	cardX := x + 28
	cardY := y + 96
	cols := 2
	gap := 14
	cw := (mw - 56 - gap) / cols
	ch := 72
	for i, f := range fields {
		col := i % 2
		row := i / 2
		rr := RECT{int32(cardX + col*(cw+gap)), int32(cardY + row*(ch+10)), int32(cardX + col*(cw+gap) + cw), int32(cardY + row*(ch+10) + ch)}
		fillRound(dc, rr, 12, surface2)
		drawText(dc, f[0], RECT{rr.Left + 14, rr.Top + 10, rr.Right - 14, rr.Top + 29}, a.fontTiny, muted, DT_LEFT|DT_SINGLELINE)
		drawText(dc, f[1], RECT{rr.Left + 14, rr.Top + 31, rr.Right - 14, rr.Bottom - 8}, a.fontBold, text, DT_LEFT|DT_END_ELLIPSIS|DT_SINGLELINE)
	}
	btnY := y + mh - 74
	a.drawButton(dc, "routerRefresh", RECT{int32(x + 28), int32(btnY), int32(x + 176), int32(btnY + 42)}, "Refresh", false, green, surface2, text, border)
	a.drawButton(dc, "routerAdmin", RECT{int32(x + 188), int32(btnY), int32(x + 390), int32(btnY + 42)}, "Open Router Admin", true, green, surface2, text, border)
	a.drawButton(dc, "routerRestart", RECT{int32(x + 402), int32(btnY), int32(x + mw - 28), int32(btnY + 42)}, "Restart Router", false, green, surface2, text, border)
}
func nv(s string) string {
	if strings.TrimSpace(s) == "" {
		return "Not available"
	}
	return s
}
func joinNonEmpty(a, b, sep string) string {
	if a == "" && b == "" {
		return "Not available"
	}
	if a == "" {
		return b
	}
	if b == "" {
		return a
	}
	return a + sep + b
}

func (a *App) hitAt(x, y int) string {
	// Prefer the most recently painted hit target. Message actions are painted after
	// the surrounding cards, so this also prevents a broad parent hit area from
	// swallowing clicks on the copy icon.
	for i := len(a.hits) - 1; i >= 0; i-- {
		h := a.hits[i]
		if ptIn(h.r, x, y) {
			return h.key
		}
	}
	for i := len(a.peerHits) - 1; i >= 0; i-- {
		h := a.peerHits[i]
		if ptIn(h.r, x, y) {
			return h.key
		}
	}
	return ""
}
func ptIn(r RECT, x, y int) bool {
	return x >= int(r.Left) && x < int(r.Right) && y >= int(r.Top) && y < int(r.Bottom)
}
func (a *App) click(x, y int) {
	// Nearby-device scrollbar is independent of card hit-testing.
	if a.peerScrollMax > 0 && ptIn(a.peerScrollTrack, x, y) {
		trackH := int(a.peerScrollTrack.Bottom - a.peerScrollTrack.Top)
		thumbH := int(a.peerScrollThumb.Bottom - a.peerScrollThumb.Top)
		travel := trackH - thumbH
		if travel > 0 {
			pos := y - int(a.peerScrollTrack.Top) - thumbH/2
			if pos < 0 {
				pos = 0
			}
			if pos > travel {
				pos = travel
			}
			a.peerScroll = int(math.Round(float64(pos) / float64(travel) * float64(a.peerScrollMax)))
		}
		invalidate()
		return
	}
	// The slim chat scrollbar is intentionally independent of button hit-testing.
	if a.chatScrollMax > 0 && ptIn(a.chatScrollTrack, x, y) {
		trackH := int(a.chatScrollTrack.Bottom - a.chatScrollTrack.Top)
		thumbH := int(a.chatScrollThumb.Bottom - a.chatScrollThumb.Top)
		travel := trackH - thumbH
		if travel > 0 {
			pos := y - int(a.chatScrollTrack.Top) - thumbH/2
			if pos < 0 {
				pos = 0
			}
			if pos > travel {
				pos = travel
			}
			// Top means oldest (max scroll), bottom means newest (zero).
			ratio := float64(pos) / float64(travel)
			a.chatScroll = int(math.Round((1 - ratio) * float64(a.chatScrollMax)))
		}
		invalidate()
		return
	}
	key := a.hitAt(x, y)
	if strings.HasPrefix(key, "openAttach:") {
		id := strings.TrimPrefix(key, "openAttach:")
		for _, m := range a.chats {
			if m.ID != id {
				continue
			}
			if m.Mine && m.FilePath != "" {
				if info, err := os.Stat(m.FilePath); err == nil {
					if info.IsDir() {
						openPath(m.FilePath)
					} else {
						openPath(filepath.Dir(m.FilePath))
					}
					return
				}
			}
			openPath(a.recvDir)
			return
		}
	}
	if strings.HasPrefix(key, "copyMsg:") {
		id := strings.TrimPrefix(key, "copyMsg:")
		for _, m := range a.chats {
			if m.ID == id {
				if err := copyTextToClipboard(a.hwnd, m.Text); err != nil {
					messageBox(a.hwnd, "Copy message", err.Error(), true)
				} else {
					a.copyFeedbackID = id
					a.copyFeedbackUntil = time.Now().Add(1100 * time.Millisecond)
					invalidate()
				}
				return
			}
		}
	}
	if key == "selfAI" {
		a.selectedPeerID = "__local_ai__"
		a.chatScroll = 0
		invalidate()
		return
	}
	if strings.HasPrefix(key, "peer:") {
		a.selectedPeerID = strings.TrimPrefix(key, "peer:")
		a.unread[a.selectedPeerID] = 0
		a.chatScroll = 0
		invalidate()
		return
	}
	switch key {
	case "scan":
		if !a.scanning {
			a.scanning = true
			a.scanStarted = time.Now()
			a.appendLog("Refreshing nearby devices…")
			go func() {
				scanStarted := time.Now()
				a.discoveryBurst()
				if a.scanLAN() {
					// Manual Refresh is authoritative: devices that did not answer this
					// scan are removed immediately instead of waiting for the normal
					// 90-second stale-device window.
					a.prunePeersNotSeenSince(scanStarted)
				}
				postUI(func() { a.scanning = false; a.appendLogUI("Nearby devices refreshed") })
			}()
		}
	case "p2p":
		a.routerOpen = false
		a.p2pOpen = true
		go a.refreshP2PStatus()
		invalidate()
	case "p2pClose":
		a.p2pOpen = false
		invalidate()
	case "p2pStart":
		go a.startDirectP2P()
	case "p2pStop":
		go a.stopDirectP2P()
	case "p2pRefresh":
		go a.refreshP2PStatus()
	case "p2pScan":
		if !a.p2pScanning {
			go a.scanNativeWiFiDirectPeers()
		}
	case "p2pWifiSettings":
		openURL("ms-settings:network-wifi")
	case "p2pHotspotSettings":
		openURL("ms-settings:network-mobilehotspot")
	case "p2pCopy":
		payload := a.p2pPairingText()
		if err := copyTextToClipboard(a.hwnd, payload); err != nil {
			messageBox(a.hwnd, "Direct P2P", err.Error(), true)
		} else {
			a.appendLog("P2P pairing information copied")
		}
	case "router":
		a.p2pOpen = false
		a.routerOpen = true
		a.refreshRouter()
	case "routerClose":
		a.routerOpen = false
		invalidate()
	case "routerRefresh":
		a.refreshRouter()
	case "routerAdmin":
		if a.router.Gateway != "" {
			openURL("http://" + a.router.Gateway)
		} else {
			messageBox(a.hwnd, "Router admin", "Gateway address is not available.", false)
		}
	case "routerRestart":
		messageBox(a.hwnd, "Router restart", "A universal router restart command does not exist. Restart requires the router vendor's authenticated API or admin page. Use Open Router Admin for this router.", false)
	case "received":
		openPath(a.recvDir)
	case "startup":
		a.startup = !a.startup
		v := a.startup
		go func() {
			if e := setStartup(v); e != nil {
				postUI(func() { a.startup = !v; messageBox(a.hwnd, "Startup setting", e.Error(), true) })
			}
		}()
		invalidate()
	case "peopleMode":
		a.aiMode = false
		if a.selectedPeerID == "__local_ai__" {
			a.selectedPeerID = ""
		}
		invalidate()
	case "aiMode":
		a.aiMode = true
		if a.selectedPeerID == "" {
			a.selectedPeerID = "__local_ai__"
		}
		invalidate()
	case "aiSettings":
		go a.openAISettingsUI()
	case "about":
		go a.openAboutUI()
	case "theme":
		a.dark = !a.dark
		a.updateInputBrush()
		dark := int32(0)
		if a.dark {
			dark = 1
		}
		pDwmSetWindowAttribute.Call(a.hwnd, 20, uintptr(unsafe.Pointer(&dark)), unsafe.Sizeof(dark))
		invalidate()
	case "send":
		a.startChatFromUI()
	case "attach":
		a.openFilePickerAsync()
	case "file":
		a.openFilePickerAsync()
	case "folder":
		a.openFolderPickerAsync()
	}
}

func (a *App) peerSnapshot() []*peer {
	a.mu.Lock()
	defer a.mu.Unlock()
	out := make([]*peer, 0, len(a.peers))
	for _, p := range a.peers {
		cp := *p
		out = append(out, &cp)
	}
	sort.Slice(out, func(i, j int) bool { return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name) })
	return out
}
func (a *App) selectedPeer() *peer {
	a.mu.Lock()
	defer a.mu.Unlock()
	p := a.peers[a.selectedPeerID]
	if p == nil {
		return nil
	}
	cp := *p
	return &cp
}
func (a *App) startChatFromUI() {
	text := strings.TrimSpace(getText(a.input))
	if text == "" {
		return
	}
	if a.aiMode {
		setText(a.input, "")
		if a.selectedPeerID == "" || a.selectedPeerID == "__local_ai__" {
			a.selectedPeerID = "__local_ai__"
			go a.sendAILocal(text)
			return
		}
		p := a.selectedPeer()
		if p == nil {
			messageBox(a.hwnd, "Select an AI host", "Choose This Device or a nearby AI-enabled device.", false)
			return
		}
		if !p.AIHost {
			messageBox(a.hwnd, "Nearby AI", "This device is not sharing an AI provider. Enable Remote AI sharing on the host PC.", false)
			return
		}
		go a.sendAITo(p, text)
		return
	}
	p := a.selectedPeer()
	if p == nil {
		messageBox(a.hwnd, "Select a device", "Choose a nearby device first.", false)
		return
	}
	setText(a.input, "")
	go a.sendTypingTo(p, false)
	go a.sendChatTo(p, text)
}

func (a *App) sendAILocal(prompt string) {
	const peerID = "__local_ai__"
	cfg := a.currentAIConfig()
	postUI(func() { a.aiBusy = true })
	a.appendChat(peerID, "You", prompt, true)
	sender := strings.Title(cfg.Provider) + " • " + effectiveAIModel(cfg)
	streamID := a.startAIStream(peerID, sender)
	var full strings.Builder
	lastPaint := time.Now().Add(-time.Second)
	err := runAI(cfg, prompt, func(chunk string) error {
		full.WriteString(chunk)
		if time.Since(lastPaint) >= 80*time.Millisecond {
			a.updateAIStream(streamID, sender, full.String())
			lastPaint = time.Now()
		}
		return nil
	})
	text := strings.TrimSpace(full.String())
	if err != nil {
		text = "AI error: " + err.Error()
	}
	if text == "" {
		text = "No response returned by the local AI provider."
	}
	a.updateAIStream(streamID, sender, text)
	if err != nil {
		a.appendLog("Local AI error: " + err.Error())
	} else {
		a.appendLog("Local AI response • " + cfg.Provider + " • " + effectiveAIModel(cfg))
	}
	postUI(func() { a.aiBusy = false })
}

func (a *App) startPathsFromUI(paths []string) {
	p := a.selectedPeer()
	if p == nil {
		messageBox(a.hwnd, "Select a device", "Choose a nearby device first, then send files.", false)
		return
	}
	go func() {
		for _, path := range paths {
			st, e := os.Stat(path)
			if e != nil {
				a.appendLog("Skipped: " + e.Error())
				continue
			}
			a.sendPathTo(p, path, st.IsDir())
		}
	}()
}
func (a *App) handleDrop(hdrop uintptr) {
	count, _, _ := pDragQueryFile.Call(hdrop, 0xFFFFFFFF, 0, 0)
	paths := make([]string, 0, int(count))
	for i := uintptr(0); i < count; i++ {
		n, _, _ := pDragQueryFile.Call(hdrop, i, 0, 0)
		b := make([]uint16, n+1)
		pDragQueryFile.Call(hdrop, i, uintptr(unsafe.Pointer(&b[0])), n+1)
		paths = append(paths, syscall.UTF16ToString(b))
	}
	pDragFinish.Call(hdrop)
	if len(paths) > 0 {
		a.startPathsFromUI(paths)
	}
}

func (a *App) noteTypingFromUI() {
	p := a.selectedPeer()
	if p == nil {
		return
	}
	now := time.Now()
	if last := a.lastTypingSent[p.ID]; !last.IsZero() && now.Sub(last) < 700*time.Millisecond {
		return
	}
	a.lastTypingSent[p.ID] = now
	go a.sendTypingTo(p, true)
}

func (a *App) sendTypingTo(p *peer, active bool) {
	if p == nil {
		return
	}
	// Typing is ephemeral presence data. Keep the timeout short and never log or
	// notify on failure; Wi-Fi recovery will restore it on the next keystroke.
	c, e := a.dialPeerFast(p, 450*time.Millisecond)
	if e != nil {
		return
	}
	defer c.Close()
	state := "0"
	if active {
		state = "1"
	}
	b, _ := json.Marshal(wireHeader{Type: "typing", Sender: a.name, SenderID: a.id, Message: state})
	_, _ = fmt.Fprintf(c, "%s\n", b)
}

func (a *App) selectedPeerTyping() bool {
	if a.selectedPeerID == "" {
		return false
	}
	until, ok := a.typingUntil[a.selectedPeerID]
	return ok && time.Now().Before(until)
}

func (a *App) selectedPeerName() string {
	p := a.selectedPeer()
	if p == nil {
		return "Device"
	}
	return p.Name
}

func (a *App) sendChatTo(p *peer, text string) {
	// People messages should survive short Android/Wi-Fi listener stalls instead of
	// being dropped after one 1.5s connect attempt. dialPeer() also pins the dial
	// to a local adapter that actually owns the peer subnet when possible.
	var c net.Conn
	var e error
	for round := 0; round < 3; round++ {
		c, e = a.dialPeer(p, 3500*time.Millisecond)
		if e == nil {
			break
		}
		if round == 0 {
			a.appendLog("Message delivery delayed • recovering route to " + p.Name + "…")
			a.discoveryBurst()
			go a.scanLAN()
		}
		time.Sleep(time.Duration(700+round*650) * time.Millisecond)
	}
	if e != nil || c == nil {
		a.appendLog("Message failed: " + e.Error())
		return
	}
	defer c.Close()
	_ = c.SetWriteDeadline(time.Now().Add(5 * time.Second))
	b, _ := json.Marshal(wireHeader{Type: "chat", Sender: a.name, SenderID: a.id, Message: text})
	if _, e = fmt.Fprintf(c, "%s\n", b); e == nil {
		a.appendChat(p.ID, p.Name, text, true)
		a.appendLog("Message sent to " + p.Name)
	} else {
		a.appendLog("Message failed while sending: " + e.Error())
	}
}
func (a *App) sendPathTo(p *peer, path string, folder bool) {
	sendPath := path
	cleanup := func() {}
	display := filepath.Base(path)
	if folder {
		a.setProgress("Preparing folder: "+display, 0)
		tmp := filepath.Join(os.TempDir(), fmt.Sprintf("farmitra-nearby-%d.zip", time.Now().UnixNano()))
		if e := zipFolder(path, tmp); e != nil {
			a.appendLog("Folder preparation failed: " + e.Error())
			return
		}
		sendPath = tmp
		cleanup = func() { _ = os.Remove(tmp) }
	}
	defer cleanup()
	f, e := os.Open(sendPath)
	if e != nil {
		a.appendLog("Open failed: " + e.Error())
		return
	}
	defer f.Close()
	st, e := f.Stat()
	if e != nil {
		return
	}
	name := display
	if folder {
		name += ".zip"
	}
	c, e := a.dialPeer(p, 2*time.Second)
	if e != nil {
		a.appendLog("Could not reach " + p.Name + ": " + e.Error())
		return
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(2 * time.Hour))
	b, _ := json.Marshal(wireHeader{Type: "file", Sender: a.name, SenderID: a.id, Name: name, Size: st.Size(), Folder: folder})
	if _, e = fmt.Fprintf(c, "%s\n", b); e != nil {
		return
	}
	a.resetProgressStats()
	a.appendLog("Sending " + display + " to " + p.Name + "…")
	n, e := copyWithProgress(c, f, st.Size(), func(done, total int64) { a.setProgressThrottled("Sending "+display+" → "+p.Name, done, total) })
	if e != nil {
		a.appendLog("Transfer failed: " + e.Error())
		a.setProgress("Transfer failed", 0)
		return
	}
	a.setProgress("Sent "+display+" • "+humanSize(n), 100)
	a.appendAttachment(p.ID, p.Name, display, n, true, folder, "Sent", path)
	a.appendLog("Sent " + display + " (" + humanSize(n) + ") to " + p.Name)
}
func copyWithProgress(dst io.Writer, src io.Reader, total int64, cb func(int64, int64)) (int64, error) {
	buf := make([]byte, 256*1024)
	var done int64
	for {
		n, er := src.Read(buf)
		if n > 0 {
			wn, ew := dst.Write(buf[:n])
			done += int64(wn)
			cb(done, total)
			if ew != nil {
				return done, ew
			}
			if wn != n {
				return done, io.ErrShortWrite
			}
		}
		if er == io.EOF {
			return done, nil
		}
		if er != nil {
			return done, er
		}
	}
}
func (a *App) resetProgressStats() {
	a.progressMu.Lock()
	a.progressPrevDone = 0
	a.progressPrevAt = time.Now()
	a.progressSmooth = 0
	a.progressMu.Unlock()
}
func (a *App) setProgressThrottled(label string, done, total int64) {
	a.progressMu.Lock()
	now := time.Now()
	dt := now.Sub(a.progressPrevAt).Seconds()
	speed := a.progressSmooth
	if dt >= .08 {
		inst := float64(done-a.progressPrevDone) / dt
		if speed == 0 {
			speed = inst
		} else {
			speed = speed*.72 + inst*.28
		}
		a.progressSmooth = speed
		a.progressPrevDone = done
		a.progressPrevAt = now
	}
	a.progressMu.Unlock()
	pct := 0
	if total > 0 {
		pct = int(done * 100 / total)
	}
	sp := ""
	eta := ""
	if speed > 0 {
		sp = humanSize(int64(speed)) + "/s"
		remain := float64(total-done) / speed
		if remain >= 0 && remain < 86400 {
			eta = "ETA " + formatDuration(time.Duration(remain*float64(time.Second)))
		}
	}
	postUI(func() {
		a.progressLabel = fmt.Sprintf("%s • %d%% • %s / %s", label, pct, humanSize(done), humanSize(total))
		a.progressPct = pct
		a.transferSpeed = sp
		a.transferETA = eta
	})
}
func (a *App) setProgress(label string, pct int) {
	if pct < 0 {
		pct = 0
	}
	if pct > 100 {
		pct = 100
	}
	postUI(func() {
		a.progressLabel = label
		a.progressPct = pct
		if pct == 0 || pct == 100 {
			a.transferETA = ""
		}
	})
}
func formatDuration(d time.Duration) string {
	if d < time.Minute {
		return fmt.Sprintf("%ds", int(d.Seconds()))
	}
	return fmt.Sprintf("%dm %02ds", int(d.Minutes()), int(d.Seconds())%60)
}

func (a *App) listenTransfers() {
	// Keep the inbound TCP endpoint alive across Wi-Fi/P2P adapter changes. Earlier
	// builds could permanently lose Android -> Windows People chat if the listener
	// failed once during a network transition.
	for {
		ln, e := net.Listen("tcp4", fmt.Sprintf("0.0.0.0:%d", transferPort))
		if e != nil {
			a.appendLog("Incoming server unavailable • retrying: " + e.Error())
			time.Sleep(1200 * time.Millisecond)
			continue
		}
		a.appendLog("Incoming chat/file server ready on TCP 43889")
		for {
			c, ae := ln.Accept()
			if ae != nil {
				_ = ln.Close()
				a.appendLog("Incoming server restarting after network change")
				break
			}
			go a.handleConn(c)
		}
		time.Sleep(350 * time.Millisecond)
	}
}

// decodeWireHeader accepts the current snake_case protocol and a few legacy /
// Flutter-friendly aliases. This keeps Android -> Windows chat compatible even
// when the mobile client serializes senderId/deviceId instead of sender_id.
func decodeWireHeader(line []byte) (wireHeader, error) {
	var h wireHeader
	if err := json.Unmarshal(line, &h); err != nil {
		return h, err
	}
	var raw map[string]any
	if err := json.Unmarshal(line, &raw); err == nil {
		get := func(keys ...string) string {
			for _, k := range keys {
				if v, ok := raw[k]; ok {
					if str, ok := v.(string); ok && strings.TrimSpace(str) != "" {
						return strings.TrimSpace(str)
					}
				}
			}
			return ""
		}
		if h.SenderID == "" {
			h.SenderID = get("sender_id", "senderId", "device_id", "deviceId", "peer_id", "peerId")
		}
		if h.Sender == "" {
			h.Sender = get("sender", "sender_name", "senderName", "device_name", "deviceName", "name")
		}
		if h.Message == "" {
			h.Message = get("message", "text", "content")
		}
	}
	return h, nil
}

// canonicalIncomingPeer maps an inbound socket back to the peer identity already
// shown in the left sidebar. This is important after DHCP/P2P reconnects and for
// mobile clients that omit/rename sender_id; otherwise the message was appended
// under an empty/different PeerID and therefore existed but was invisible in the
// selected conversation.
func (a *App) canonicalIncomingPeer(senderID, senderName, remoteIP string) (string, string) {
	senderID = strings.TrimSpace(senderID)
	senderName = strings.TrimSpace(senderName)
	remoteIP = strings.TrimSpace(remoteIP)
	a.mu.Lock()
	defer a.mu.Unlock()
	if senderID != "" {
		if p := a.peers[senderID]; p != nil {
			if senderName == "" {
				senderName = p.Name
			}
			if remoteIP != "" {
				p.IP = remoteIP
			}
			p.LastSeen = time.Now()
			return p.ID, senderName
		}
	}
	// Prefer the currently selected peer when its known address matches the socket.
	if a.selectedPeerID != "" && a.selectedPeerID != "__local_ai__" {
		if p := a.peers[a.selectedPeerID]; p != nil && remoteIP != "" && p.IP == remoteIP {
			if senderName == "" {
				senderName = p.Name
			}
			p.LastSeen = time.Now()
			return p.ID, senderName
		}
	}
	for _, p := range a.peers {
		if remoteIP != "" && p.IP == remoteIP {
			if senderName == "" {
				senderName = p.Name
			}
			p.LastSeen = time.Now()
			return p.ID, senderName
		}
	}
	if senderID == "" {
		if remoteIP != "" {
			senderID = "ip:" + remoteIP
		} else {
			senderID = "unknown-peer"
		}
	}
	if senderName == "" {
		senderName = remoteIP
	}
	return senderID, senderName
}

func (a *App) handleConn(c net.Conn) {
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(2 * time.Hour))
	r := bufio.NewReaderSize(c, 256*1024)
	line, e := r.ReadBytes('\n')
	if e != nil {
		return
	}
	h, de := decodeWireHeader(line)
	if de != nil {
		a.appendLog("Incoming packet ignored • invalid JSON")
		return
	}
	switch h.Type {
	case "hello":
		cfg := a.currentAIConfig()
		b, _ := json.Marshal(wireHeader{Type: "hello", Sender: a.name, SenderID: a.id, AIHost: cfg.ShareAI && aiProviderAvailable(cfg), Provider: cfg.Provider, Model: effectiveAIModel(cfg)})
		_, _ = fmt.Fprintf(c, "%s\n", b)
		if ra, ok := c.RemoteAddr().(*net.TCPAddr); ok {
			a.upsertPeer(h.SenderID, h.Sender, ra.IP.String())
			a.updatePeerAI(h.SenderID, h.AIHost, h.Provider, h.Model)
		}
	case "typing":
		remoteIP := ""
		if ra, ok := c.RemoteAddr().(*net.TCPAddr); ok {
			remoteIP = ra.IP.String()
		}
		peerID, peerName := a.canonicalIncomingPeer(h.SenderID, h.Sender, remoteIP)
		a.upsertPeer(peerID, peerName, remoteIP)
		postUI(func() {
			if h.Message == "1" {
				a.typingUntil[peerID] = time.Now().Add(2400 * time.Millisecond)
			} else {
				delete(a.typingUntil, peerID)
			}
		})
	case "ai_prompt":
		if ra, ok := c.RemoteAddr().(*net.TCPAddr); ok {
			a.upsertPeer(h.SenderID, h.Sender, ra.IP.String())
		}
		cfg := a.currentAIConfig()
		if !cfg.ShareAI || !aiProviderAvailable(cfg) {
			b, _ := json.Marshal(wireHeader{Type: "ai_error", Sender: a.name, SenderID: a.id, Message: "Nearby AI is disabled or provider is unavailable", Done: true})
			_, _ = fmt.Fprintf(c, "%s\n", b)
			return
		}
		if !aiDeviceAllowed(cfg, h.SenderID) {
			b, _ := json.Marshal(wireHeader{Type: "ai_error", Sender: a.name, SenderID: a.id, Message: "Nearby AI access is not allowed for this device.", Done: true})
			_, _ = fmt.Fprintf(c, "%s\n", b)
			a.appendLog("Nearby AI blocked for " + h.Sender + " • device not allowed")
			return
		}
		a.appendLog("Nearby AI request from " + h.Sender + " • " + cfg.Provider)
		err := runAI(cfg, h.Message, func(chunk string) error {
			b, _ := json.Marshal(wireHeader{Type: "ai_chunk", Sender: a.name, SenderID: a.id, Message: chunk, Provider: cfg.Provider, Model: effectiveAIModel(cfg)})
			_, e := fmt.Fprintf(c, "%s\n", b)
			return e
		})
		if err != nil {
			b, _ := json.Marshal(wireHeader{Type: "ai_error", Sender: a.name, SenderID: a.id, Message: err.Error(), Done: true})
			_, _ = fmt.Fprintf(c, "%s\n", b)
		} else {
			b, _ := json.Marshal(wireHeader{Type: "ai_done", Sender: a.name, SenderID: a.id, Done: true, Provider: cfg.Provider, Model: effectiveAIModel(cfg)})
			_, _ = fmt.Fprintf(c, "%s\n", b)
		}
	case "chat":
		remoteIP := ""
		if ra, ok := c.RemoteAddr().(*net.TCPAddr); ok {
			remoteIP = ra.IP.String()
		}
		peerID, peerName := a.canonicalIncomingPeer(h.SenderID, h.Sender, remoteIP)
		// Ensure a newly seen mobile peer is still represented in discovery/sidebar.
		a.upsertPeer(peerID, peerName, remoteIP)
		postUI(func() { delete(a.typingUntil, peerID) })
		a.appendChat(peerID, peerName, h.Message, false)
		a.appendLog("Message received from " + peerName)
		a.notify("Message from "+peerName, h.Message)
	case "file":
		remoteIP := ""
		if ra, ok := c.RemoteAddr().(*net.TCPAddr); ok {
			remoteIP = ra.IP.String()
		}
		peerID, peerName := a.canonicalIncomingPeer(h.SenderID, h.Sender, remoteIP)
		a.upsertPeer(peerID, peerName, remoteIP)
		h.SenderID, h.Sender = peerID, peerName
		safe := filepath.Base(h.Name)
		if safe == "." || safe == "" || h.Size < 0 {
			return
		}
		dest := uniquePath(filepath.Join(a.recvDir, safe))
		f, e := os.Create(dest)
		if e != nil {
			return
		}
		a.resetProgressStats()
		a.setProgress("Receiving "+safe+" from "+h.Sender, 0)
		limited := io.LimitReader(r, h.Size)
		n, ce := copyWithProgress(f, limited, h.Size, func(done, total int64) { a.setProgressThrottled("Receiving "+safe+" ← "+h.Sender, done, total) })
		f.Close()
		if ce != nil || n != h.Size {
			_ = os.Remove(dest)
			a.appendLog("Receive failed")
			a.setProgress("Receive failed", 0)
			return
		}
		final := dest
		if h.Folder {
			folderName := strings.TrimSuffix(filepath.Base(h.Name), ".zip")
			out := uniqueDir(filepath.Join(a.recvDir, folderName))
			_ = os.MkdirAll(out, 0755)
			if e := unzipSafe(dest, out); e == nil {
				_ = os.Remove(dest)
				final = out
			} else {
				a.appendLog("Folder extract failed: " + e.Error())
			}
		}
		a.setProgress("Received "+filepath.Base(final)+" • "+humanSize(n), 100)
		a.appendAttachment(h.SenderID, h.Sender, filepath.Base(final), n, false, h.Folder, "Received", final)
		a.appendLog("Received " + filepath.Base(final) + " (" + humanSize(n) + ") from " + h.Sender)
		a.notify("File received from "+h.Sender, filepath.Base(final)+" saved")
	}
}

func (a *App) updatePeerAI(id string, enabled bool, provider, model string) {
	postUI(func() {
		a.mu.Lock()
		if p := a.peers[id]; p != nil {
			p.AIHost = enabled
			p.AIProvider = provider
			p.AIModel = model
		}
		a.mu.Unlock()
		invalidate()
	})
}

func (a *App) sendAITo(p *peer, prompt string) {
	if p == nil {
		return
	}
	postUI(func() { a.aiBusy = true })
	a.appendChat(p.ID, "You", prompt, true)
	c, e := a.dialPeer(p, 2*time.Second)
	if e != nil {
		a.appendChat(p.ID, "Nearby AI", "AI connection failed: "+e.Error(), false)
		postUI(func() { a.aiBusy = false })
		return
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(30 * time.Minute))
	b, _ := json.Marshal(wireHeader{Type: "ai_prompt", Sender: a.name, SenderID: a.id, Message: prompt})
	if _, e = fmt.Fprintf(c, "%s\n", b); e != nil {
		postUI(func() { a.aiBusy = false })
		return
	}
	r := bufio.NewReader(c)
	sender := "Nearby AI"
	streamID := a.startAIStream(p.ID, sender)
	var full strings.Builder
	lastPaint := time.Now().Add(-time.Second)
	for {
		line, e := r.ReadBytes('\n')
		if e != nil {
			if e != io.EOF {
				a.appendLog("Nearby AI stream ended: " + e.Error())
			}
			break
		}
		var h wireHeader
		if json.Unmarshal(line, &h) != nil {
			continue
		}
		if h.Provider != "" {
			sender = strings.Title(h.Provider) + " • " + h.Model
		}
		switch h.Type {
		case "ai_chunk":
			full.WriteString(h.Message)
			if time.Since(lastPaint) >= 80*time.Millisecond {
				a.updateAIStream(streamID, sender, full.String())
				lastPaint = time.Now()
			}
		case "ai_error":
			full.WriteString("\nAI error: " + h.Message)
			goto done
		case "ai_done":
			goto done
		}
	}
done:
	text := strings.TrimSpace(full.String())
	if text == "" {
		text = "No response returned by the AI host."
	}
	a.updateAIStream(streamID, sender, text)
	a.appendLog("Nearby AI response received from " + p.Name)
	postUI(func() { a.aiBusy = false })
}

func (a *App) discoveryLoop() {
	// Do one full discovery at startup, then rely primarily on lightweight
	// multicast + direct heartbeats. Re-scanning all 254 addresses every few
	// seconds caused needless socket churn and made peers appear unstable.
	a.discoveryBurst()
	a.scanLAN()
	burst := time.NewTicker(12 * time.Second)
	full := time.NewTicker(90 * time.Second)
	defer burst.Stop()
	defer full.Stop()
	for {
		select {
		case <-burst.C:
			a.discoveryBurst()
		case <-full.C:
			if a.scanLAN() {
				a.pruneStalePeers(90 * time.Second)
			}
		}
	}
}
func (a *App) discoveryBurst() {
	addr := &net.UDPAddr{IP: net.ParseIP(multicastIP), Port: discoverPort}
	c, e := net.DialUDP("udp4", nil, addr)
	if e != nil {
		return
	}
	defer c.Close()
	b, _ := json.Marshal(peer{ID: a.id, Name: a.name})
	_, _ = c.Write(b)
}
func (a *App) scanLAN() bool {
	// Avoid overlapping background/manual scans.
	if !a.scanMu.TryLock() {
		return false
	}
	defer a.scanMu.Unlock()
	prefixes := localIPv4Prefixes()
	sem := make(chan struct{}, 40)
	var wg sync.WaitGroup
	for _, prefix := range prefixes {
		for host := 1; host <= 254; host++ {
			ip := fmt.Sprintf("%s.%d", prefix, host)
			if isLocalIPv4(ip) {
				continue
			}
			wg.Add(1)
			sem <- struct{}{}
			go func(addr string) {
				defer wg.Done()
				defer func() { <-sem }()
				c, e := net.DialTimeout("tcp4", fmt.Sprintf("%s:%d", addr, transferPort), 160*time.Millisecond)
				if e != nil {
					return
				}
				defer c.Close()
				_ = c.SetDeadline(time.Now().Add(320 * time.Millisecond))
				b, _ := json.Marshal(wireHeader{Type: "hello", Sender: a.name, SenderID: a.id, AIHost: a.currentAIConfig().ShareAI && aiProviderAvailable(a.currentAIConfig()), Provider: a.currentAIConfig().Provider, Model: effectiveAIModel(a.currentAIConfig())})
				if _, e = fmt.Fprintf(c, "%s\n", b); e != nil {
					return
				}
				line, e := bufio.NewReader(c).ReadBytes('\n')
				if e != nil {
					return
				}
				var r wireHeader
				if json.Unmarshal(line, &r) != nil || r.Type != "hello" || r.SenderID == "" || r.SenderID == a.id {
					return
				}
				a.upsertPeer(r.SenderID, r.Sender, addr)
			}(ip)
		}
	}
	wg.Wait()
	return true
}

// prunePeersNotSeenSince is used by the explicit Refresh button. Unlike the
// normal background stale timer, manual refresh should immediately reflect
// devices that have actually left the LAN.
func (a *App) prunePeersNotSeenSince(cutoff time.Time) {
	type removedPeer struct{ ID, Name string }
	var removed []removedPeer
	a.mu.Lock()
	for id, p := range a.peers {
		if p.LastSeen.Before(cutoff) {
			removed = append(removed, removedPeer{ID: id, Name: p.Name})
			delete(a.peers, id)
		}
	}
	a.mu.Unlock()
	if len(removed) == 0 {
		return
	}
	for _, p := range removed {
		a.appendLog("Device left network: " + p.Name)
	}
	postUI(func() {
		for _, p := range removed {
			delete(a.unread, p.ID)
			delete(a.typingUntil, p.ID)
			if a.selectedPeerID == p.ID {
				a.selectedPeerID = ""
			}
		}
		invalidate()
	})
}

// Background cleanup stays intentionally conservative. A peer may miss
// multicast/heartbeat packets during Wi-Fi power saving, so only peers that
// have been silent for the configured stale window are removed.
func (a *App) pruneStalePeers(maxAge time.Duration) {
	a.prunePeersNotSeenSince(time.Now().Add(-maxAge))
}

func localIPv4Prefixes() []string {
	seen := map[string]bool{}
	var out []string
	ifaces, _ := net.Interfaces()
	for _, in := range ifaces {
		if in.Flags&net.FlagUp == 0 || in.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := in.Addrs()
		for _, ad := range addrs {
			ip, _, e := net.ParseCIDR(ad.String())
			if e != nil {
				continue
			}
			v := ip.To4()
			if v == nil {
				continue
			}
			if !(v[0] == 10 || (v[0] == 172 && v[1] >= 16 && v[1] <= 31) || (v[0] == 192 && v[1] == 168)) {
				continue
			}
			p := fmt.Sprintf("%d.%d.%d", v[0], v[1], v[2])
			if !seen[p] {
				seen[p] = true
				out = append(out, p)
			}
		}
	}
	return out
}
func isLocalIPv4(s string) bool {
	ifs, _ := net.Interfaces()
	for _, in := range ifs {
		addrs, _ := in.Addrs()
		for _, ad := range addrs {
			ip, _, e := net.ParseCIDR(ad.String())
			if e == nil && ip.To4() != nil && ip.String() == s {
				return true
			}
		}
	}
	return false
}
func (a *App) upsertPeer(id, name, ip string) {
	if id == "" || id == a.id || name == "" {
		return
	}
	now := time.Now()
	a.mu.Lock()
	p, exists := a.peers[id]
	if exists {
		p.Name = name
		if ip != "" {
			p.IP = ip
		}
		p.LastSeen = now
	} else {
		a.peers[id] = &peer{ID: id, Name: name, IP: ip, LastSeen: now}
	}
	a.mu.Unlock()
	if !exists {
		// Discovery is logged, but intentionally does NOT trigger a tray balloon.
		a.appendLog("Device discovered: " + name + " (" + ip + ")")
	}
	postUI(func() {})
}
func (a *App) listenDiscovery() {
	// Rejoin the multicast socket whenever Windows tears it down during a Wi-Fi
	// adapter disconnect/reconnect. A dead multicast socket must not end discovery.
	for {
		group := &net.UDPAddr{IP: net.ParseIP(multicastIP), Port: discoverPort}
		c, e := net.ListenMulticastUDP("udp4", nil, group)
		if e != nil {
			time.Sleep(1200 * time.Millisecond)
			continue
		}
		_ = c.SetReadBuffer(64 * 1024)
		buf := make([]byte, 2048)
		for {
			n, src, e := c.ReadFromUDP(buf)
			if e != nil {
				_ = c.Close()
				break
			}
			var p peer
			if json.Unmarshal(buf[:n], &p) != nil || p.ID == "" || p.ID == a.id {
				continue
			}
			a.upsertPeer(p.ID, p.Name, src.IP.String())
		}
		time.Sleep(700 * time.Millisecond)
	}
}

func networkSignature() string {
	var ips []string
	ifaces, _ := net.Interfaces()
	for _, in := range ifaces {
		if in.Flags&net.FlagUp == 0 || in.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := in.Addrs()
		for _, ad := range addrs {
			ip, _, e := net.ParseCIDR(ad.String())
			if e != nil || ip.To4() == nil {
				continue
			}
			v := ip.To4()
			if v[0] == 169 && v[1] == 254 { // APIPA while Wi-Fi is negotiating
				continue
			}
			ips = append(ips, ip.String())
		}
	}
	sort.Strings(ips)
	return strings.Join(ips, "|")
}

func (a *App) networkRecoveryLoop() {
	prev := networkSignature()
	a.networkSignature = prev
	wasOffline := prev == ""
	t := time.NewTicker(3 * time.Second)
	defer t.Stop()
	for range t.C {
		cur := networkSignature()
		if cur == prev {
			continue
		}
		prev = cur
		a.networkSignature = cur
		if cur == "" {
			if !wasOffline {
				wasOffline = true
				a.appendLog("Network disconnected • waiting for Wi-Fi/Ethernet…")
			}
			continue
		}
		if wasOffline {
			a.appendLog("Network restored • reconnecting nearby devices…")
		} else {
			a.appendLog("Network changed • refreshing nearby devices…")
		}
		wasOffline = false
		// Refresh multicast/ARP state immediately and rediscover DHCP-changed peer IPs.
		a.discoveryBurst()
		go a.scanLAN()
	}
}

func (a *App) maintainPeers() {
	// Peers are intentionally retained for the whole app session. Wi-Fi power
	// saving, multicast packet loss or a busy receiver must not make a device
	// disappear/reappear every few seconds. Known peers receive a tiny direct
	// hello periodically so LastSeen stays fresh whenever they are reachable.
	t := time.NewTicker(8 * time.Second)
	defer t.Stop()
	for range t.C {
		a.mu.Lock()
		peers := make([]peer, 0, len(a.peers))
		for _, p := range a.peers {
			peers = append(peers, *p)
		}
		a.mu.Unlock()
		for i := range peers {
			p := peers[i]
			go a.helloPeer(&p)
		}
	}
}

func (a *App) helloPeer(p *peer) bool {
	if p == nil || p.IP == "" {
		return false
	}
	c, e := net.DialTimeout("tcp4", fmt.Sprintf("%s:%d", p.IP, transferPort), 900*time.Millisecond)
	if e != nil {
		return false
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(1400 * time.Millisecond))
	b, _ := json.Marshal(wireHeader{Type: "hello", Sender: a.name, SenderID: a.id, AIHost: a.currentAIConfig().ShareAI && aiProviderAvailable(a.currentAIConfig()), Provider: a.currentAIConfig().Provider, Model: effectiveAIModel(a.currentAIConfig())})
	if _, e = fmt.Fprintf(c, "%s\n", b); e != nil {
		return false
	}
	line, e := bufio.NewReader(c).ReadBytes('\n')
	if e != nil {
		return false
	}
	var r wireHeader
	if json.Unmarshal(line, &r) != nil || r.Type != "hello" || r.SenderID == "" || r.SenderID == a.id {
		return false
	}
	a.upsertPeer(r.SenderID, r.Sender, p.IP)
	a.updatePeerAI(r.SenderID, r.AIHost, r.Provider, r.Model)
	return true
}

func localIPv4CandidatesForPeer(peerIP string) []net.IP {
	target := net.ParseIP(peerIP).To4()
	if target == nil {
		return nil
	}
	var exact []net.IP
	var other []net.IP
	ifs, _ := net.Interfaces()
	for _, in := range ifs {
		if in.Flags&net.FlagUp == 0 || in.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := in.Addrs()
		for _, ad := range addrs {
			ip, network, err := net.ParseCIDR(ad.String())
			if err != nil || ip.To4() == nil || network == nil {
				continue
			}
			v := ip.To4()
			if v[0] == 169 && v[1] == 254 {
				continue
			}
			cp := append(net.IP(nil), v...)
			if network.Contains(target) {
				exact = append(exact, cp)
			} else if v[0] == 10 || (v[0] == 172 && v[1] >= 16 && v[1] <= 31) || (v[0] == 192 && v[1] == 168) {
				other = append(other, cp)
			}
		}
	}
	return append(exact, other...)
}

func (a *App) dialPeerFast(p *peer, timeout time.Duration) (net.Conn, error) {
	if p == nil || p.IP == "" {
		return nil, fmt.Errorf("device address unavailable")
	}
	address := fmt.Sprintf("%s:%d", p.IP, transferPort)
	var last error
	// Prefer the adapter whose CIDR contains the target peer. This avoids a very
	// common Windows failure where VPN/Hyper-V/WSL/virtual adapters win route
	// selection even though discovery came from the physical Wi-Fi/LAN adapter.
	for _, localIP := range localIPv4CandidatesForPeer(p.IP) {
		d := net.Dialer{Timeout: timeout, KeepAlive: 20 * time.Second, LocalAddr: &net.TCPAddr{IP: localIP}}
		c, err := d.Dial("tcp4", address)
		if err == nil {
			return c, nil
		}
		last = err
	}
	// Always keep the normal Windows routing table as a final fallback.
	d := net.Dialer{Timeout: timeout, KeepAlive: 20 * time.Second}
	c, err := d.Dial("tcp4", address)
	if err == nil {
		return c, nil
	}
	if last != nil {
		return nil, fmt.Errorf("%v; fallback: %w", last, err)
	}
	return nil, err
}

func (a *App) currentPeer(id string) *peer {
	a.mu.Lock()
	defer a.mu.Unlock()
	p := a.peers[id]
	if p == nil {
		return nil
	}
	cp := *p
	return &cp
}

func (a *App) dialPeer(p *peer, timeout time.Duration) (net.Conn, error) {
	if p == nil || p.IP == "" {
		return nil, fmt.Errorf("device address unavailable")
	}
	var last error
	for attempt := 0; attempt < 3; attempt++ {
		candidate := p
		if fresh := a.currentPeer(p.ID); fresh != nil && fresh.IP != "" {
			candidate = fresh
		}
		c, e := a.dialPeerFast(candidate, timeout)
		if e == nil {
			return c, nil
		}
		last = e
		if attempt == 0 {
			a.discoveryBurst()
		}
		time.Sleep(time.Duration(220+attempt*240) * time.Millisecond)
	}

	// The peer may have received a new DHCP address after Wi-Fi reconnect. Do one
	// guarded LAN refresh, then retry using the newly learned address.
	a.scanLAN()
	if fresh := a.currentPeer(p.ID); fresh != nil && fresh.IP != "" {
		if c, e := a.dialPeerFast(fresh, timeout); e == nil {
			return c, nil
		} else {
			last = e
		}
	}
	return nil, last
}

func (a *App) appendLog(s string) { postUI(func() { a.appendLogUI(s) }) }
func (a *App) appendLogUI(s string) {
	a.logs = append(a.logs, time.Now().Format("15:04:05")+"   "+s)
	if len(a.logs) > 300 {
		a.logs = a.logs[len(a.logs)-300:]
	}
	a.logScroll = 0
}
func (a *App) appendChat(peerID, sender, text string, mine bool) {
	postUI(func() {
		a.chats = append(a.chats, ChatMessage{ID: fmt.Sprintf("m-%d", time.Now().UnixNano()), PeerID: peerID, Sender: sender, Text: text, Mine: mine, At: time.Now(), Kind: "text"})
		if len(a.chats) > 600 {
			a.chats = a.chats[len(a.chats)-600:]
		}
		a.chatScroll = 0
		if !mine && (a.selectedPeerID != peerID || a.aiMode) {
			a.unread[peerID]++
		}
	})
}
func (a *App) appendAttachment(peerID, sender, name string, size int64, mine, folder bool, status, path string) {
	kind := "file"
	if folder {
		kind = "folder"
	}
	postUI(func() {
		a.chats = append(a.chats, ChatMessage{ID: fmt.Sprintf("m-%d", time.Now().UnixNano()), PeerID: peerID, Sender: sender, Mine: mine, At: time.Now(), Kind: kind, FileName: name, FileSize: size, FilePath: path, Status: status})
		if len(a.chats) > 600 {
			a.chats = a.chats[len(a.chats)-600:]
		}
		a.chatScroll = 0
		if !mine && (a.selectedPeerID != peerID || a.aiMode) {
			a.unread[peerID]++
		}
	})
}
func (a *App) startAIStream(peerID, sender string) string {
	id := fmt.Sprintf("ai-%d", time.Now().UnixNano())
	postUI(func() {
		a.chats = append(a.chats, ChatMessage{ID: id, PeerID: peerID, Sender: sender, Text: "", Mine: false, At: time.Now(), Kind: "ai"})
		if len(a.chats) > 600 {
			a.chats = a.chats[len(a.chats)-600:]
		}
		a.chatScroll = 0
	})
	return id
}
func (a *App) updateAIStream(id, sender, text string) {
	postUI(func() {
		for i := range a.chats {
			if a.chats[i].ID == id {
				if sender != "" {
					a.chats[i].Sender = sender
				}
				a.chats[i].Text = text
				a.chats[i].Kind = "ai"
				// Keep the original timestamp stable. Updating At for every token used to
				// retrigger the slide-in animation and made the whole bubble visibly shake.
				break
			}
		}
		// Auto-follow only while the user is already at the newest message. If the
		// user scrolls up during generation, do not yank the viewport back down.
		if a.chatScroll <= 2 {
			a.chatScroll = 0
		}
	})
}

func (a *App) visibleChats() []ChatMessage {
	if a.selectedPeerID == "" {
		return nil
	}
	out := make([]ChatMessage, 0, len(a.chats))
	for _, m := range a.chats {
		if m.PeerID == a.selectedPeerID {
			out = append(out, m)
		}
	}
	return out
}

func (a *App) refreshRouter() {
	if a.routerLoading {
		return
	}
	a.routerLoading = true
	invalidate()
	go func() {
		info := collectRouterInfo()
		postUI(func() { a.router = info; a.routerLoading = false; a.appendLogUI("Network details refreshed") })
	}()
}
func collectRouterInfo() RouterInfo {
	ri := RouterInfo{Updated: time.Now()}
	script := `$ErrorActionPreference='SilentlyContinue'; $c=Get-NetIPConfiguration | Where-Object {$_.IPv4DefaultGateway -ne $null} | Select-Object -First 1; if($c){$a=Get-NetAdapter -InterfaceIndex $c.InterfaceIndex; $n=(Get-NetNeighbor -InterfaceIndex $c.InterfaceIndex -AddressFamily IPv4 | Where-Object {$_.State -notin @('Unreachable','Incomplete') -and $_.IPAddress -notlike '224.*' -and $_.IPAddress -notlike '255.*'} | Select-Object -ExpandProperty IPAddress -Unique).Count; [pscustomobject]@{Interface=$c.InterfaceAlias;Description=$a.InterfaceDescription;IPv4=($c.IPv4Address.IPAddress -join ', ');Gateway=$c.IPv4DefaultGateway.NextHop;DNS=($c.DNSServer.ServerAddresses -join ', ');MAC=$a.MacAddress;LinkSpeed=$a.LinkSpeed;Neighbors=$n} | ConvertTo-Json -Compress}`
	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	if out, e := cmd.Output(); e == nil {
		_ = json.Unmarshal([]byte(strings.TrimSpace(strings.TrimPrefix(string(out), "\ufeff"))), &ri)
	}
	cmd2 := exec.Command("netsh", "wlan", "show", "interfaces")
	cmd2.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	if out, e := cmd2.Output(); e == nil {
		parseWLAN(string(out), &ri)
	}
	if ri.Gateway != "" {
		c, e := net.DialTimeout("tcp", ri.Gateway+":80", 500*time.Millisecond)
		if e == nil {
			ri.RouterReachable = true
			c.Close()
		} else {
			u, e2 := net.DialTimeout("udp", ri.Gateway+":53", 300*time.Millisecond)
			if e2 == nil {
				ri.RouterReachable = true
				u.Close()
			}
		}
	}
	return ri
}
func parseWLAN(s string, ri *RouterInfo) {
	for _, line := range strings.Split(s, "\n") {
		p := strings.SplitN(line, ":", 2)
		if len(p) != 2 {
			continue
		}
		k := strings.TrimSpace(strings.ToLower(p[0]))
		v := strings.TrimSpace(p[1])
		switch k {
		case "ssid":
			if ri.SSID == "" {
				ri.SSID = v
			}
		case "bssid":
			ri.BSSID = v
		case "signal":
			ri.Signal = v
		case "receive rate (mbps)":
			ri.RxRate = v + " Mbps"
		case "transmit rate (mbps)":
			ri.TxRate = v + " Mbps"
		}
	}
}

func runPickerPowerShell(script string) (string, error) {
	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-STA", "-ExecutionPolicy", "Bypass", "-Command", script)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	out, e := cmd.Output()
	if e != nil {
		return "", e
	}
	return strings.TrimSpace(strings.TrimPrefix(string(out), "\ufeff")), nil
}
func (a *App) openFilePickerAsync() {
	if a.selectedPeer() == nil {
		messageBox(a.hwnd, "Select a device", "Choose a nearby device first.", false)
		return
	}
	go func() {
		script := `[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Add-Type -AssemblyName System.Windows.Forms; $d=New-Object System.Windows.Forms.OpenFileDialog; $d.Title='Choose a file to send'; $d.Filter='All files (*.*)|*.*'; if($d.ShowDialog() -eq 'OK'){[Console]::Write($d.FileName)}`
		path, e := runPickerPowerShell(script)
		if e != nil {
			a.appendLog("File picker error: " + e.Error())
			return
		}
		if path != "" {
			postUI(func() { a.startPathsFromUI([]string{path}) })
		}
	}()
}
func (a *App) openFolderPickerAsync() {
	if a.selectedPeer() == nil {
		messageBox(a.hwnd, "Select a device", "Choose a nearby device first.", false)
		return
	}
	go func() {
		script := `[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Add-Type -AssemblyName System.Windows.Forms; $d=New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description='Choose a folder to send'; if($d.ShowDialog() -eq 'OK'){[Console]::Write($d.SelectedPath)}`
		path, e := runPickerPowerShell(script)
		if e != nil {
			a.appendLog("Folder picker error: " + e.Error())
			return
		}
		if path != "" {
			postUI(func() { a.startPathsFromUI([]string{path}) })
		}
	}()
}

func (a *App) addTray(icon uintptr) {
	var n NOTIFYICONDATA
	n.CbSize = uint32(unsafe.Sizeof(n))
	n.HWnd = a.hwnd
	n.UID = trayID
	n.UFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP
	n.UCallbackMessage = wmAppTray
	n.HIcon = icon
	copy(n.SzTip[:], syscall.StringToUTF16(appName))
	pShellNotifyIcon.Call(NIM_ADD, uintptr(unsafe.Pointer(&n)))
}
func (a *App) removeTray() {
	var n NOTIFYICONDATA
	n.CbSize = uint32(unsafe.Sizeof(n))
	n.HWnd = a.hwnd
	n.UID = trayID
	pShellNotifyIcon.Call(NIM_DELETE, uintptr(unsafe.Pointer(&n)))
}
func (a *App) notify(title, text string) { postUI(func() { a.notifyUI(title, text) }) }
func (a *App) notifyUI(title, text string) {
	if len(text) > 230 {
		text = text[:230]
	}
	var n NOTIFYICONDATA
	n.CbSize = uint32(unsafe.Sizeof(n))
	n.HWnd = a.hwnd
	n.UID = trayID
	n.UFlags = NIF_INFO
	copy(n.SzInfoTitle[:], syscall.StringToUTF16(title))
	copy(n.SzInfo[:], syscall.StringToUTF16(text))
	n.DwInfoFlags = NIIF_INFO
	pShellNotifyIcon.Call(NIM_MODIFY, uintptr(unsafe.Pointer(&n)))
}
func showTrayMenu(hwnd uintptr) {
	m, _, _ := pCreatePopupMenu.Call()
	if m == 0 {
		return
	}
	defer pDestroyMenu.Call(m)
	pAppendMenu.Call(m, MF_STRING, idTrayShow, uintptr(unsafe.Pointer(wstr("Open Farmitra Nearby"))))
	pAppendMenu.Call(m, MF_SEPARATOR, 0, 0)
	pAppendMenu.Call(m, MF_STRING, idTrayExit, uintptr(unsafe.Pointer(wstr("Exit"))))
	var pt POINT
	pGetCursorPos.Call(uintptr(unsafe.Pointer(&pt)))
	pSetForegroundWindow.Call(hwnd)
	cmd, _, _ := pTrackPopupMenu.Call(m, TPM_RIGHTBUTTON|0x0100, uintptr(pt.X), uintptr(pt.Y), 0, hwnd, 0)
	if cmd == idTrayShow {
		pShowWindow.Call(hwnd, SW_RESTORE)
		pSetForegroundWindow.Call(hwnd)
	} else if cmd == idTrayExit {
		if app != nil {
			app.removeTray()
		}
		pDestroyWindow.Call(hwnd)
	}
}
func messageBox(hwnd uintptr, title, text string, isErr bool) {
	flags := uintptr(MB_OK | MB_ICONINFORMATION)
	if isErr {
		flags = MB_OK | MB_ICONERROR
	}
	pMessageBox.Call(hwnd, uintptr(unsafe.Pointer(wstr(text))), uintptr(unsafe.Pointer(wstr(title))), flags)
}
func openPath(path string) {
	pShellExecute.Call(0, uintptr(unsafe.Pointer(wstr("open"))), uintptr(unsafe.Pointer(wstr(path))), 0, 0, SW_SHOW)
}
func openURL(url string) {
	pShellExecute.Call(0, uintptr(unsafe.Pointer(wstr("open"))), uintptr(unsafe.Pointer(wstr(url))), 0, 0, SW_SHOW)
}
func defaultAIConfig() AIConfig {
	return AIConfig{ShareAI: true, Provider: "ollama", Model: "", OllamaURL: "http://127.0.0.1:11434", GroqModel: "llama-3.3-70b-versatile", OpenAIModel: "gpt-4.1-mini", GeminiModel: "gemini-2.5-flash"}
}
func aiConfigPath() string {
	d := filepath.Join(os.Getenv("APPDATA"), "FarmitraNearby")
	_ = os.MkdirAll(d, 0755)
	return filepath.Join(d, "ai-settings.json")
}
func loadAIConfig() AIConfig {
	cfg := defaultAIConfig()
	p := aiConfigPath()
	if b, e := os.ReadFile(p); e == nil {
		b = bytes.TrimPrefix(b, []byte{0xEF, 0xBB, 0xBF})
		_ = json.Unmarshal(b, &cfg)
	} else {
		if b, e := json.MarshalIndent(cfg, "", "  "); e == nil {
			_ = os.WriteFile(p, b, 0600)
		}
	}
	if cfg.OllamaURL == "" {
		cfg.OllamaURL = "http://127.0.0.1:11434"
	}
	if strings.ToLower(cfg.Provider) != "ollama" {
		cfg.APIKey = loadAISecret(strings.ToLower(cfg.Provider))
	}
	return cfg
}

func aiSecretPath(provider string) string {
	d := filepath.Join(os.Getenv("APPDATA"), "FarmitraNearby", "secrets")
	_ = os.MkdirAll(d, 0700)
	return filepath.Join(d, provider+".dpapi")
}

func loadAISecret(provider string) string {
	provider = strings.ToLower(strings.TrimSpace(provider))
	if provider == "" || provider == "ollama" {
		return ""
	}
	p := aiSecretPath(provider)
	if _, err := os.Stat(p); err != nil {
		return ""
	}
	ps := `$p='` + strings.ReplaceAll(p, "'", "''") + `'; try { Add-Type -AssemblyName System.Security; $b=[Convert]::FromBase64String((Get-Content -Raw -Path $p)); $d=[Security.Cryptography.ProtectedData]::Unprotect($b,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser); [Text.Encoding]::UTF8.GetString($d) } catch { '' }`
	out, err := exec.Command("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}
func (a *App) currentAIConfig() AIConfig { return a.aiConfig }
func (a *App) openAISettingsUI() {
	cfgPath := aiConfigPath()
	type aiPeerOption struct{ ID, Name, IP string }
	a.mu.Lock()
	peerOptions := make([]aiPeerOption, 0, len(a.peers))
	for _, p := range a.peers {
		peerOptions = append(peerOptions, aiPeerOption{ID: p.ID, Name: p.Name, IP: p.IP})
	}
	a.mu.Unlock()
	sort.Slice(peerOptions, func(i, j int) bool {
		return strings.ToLower(peerOptions[i].Name) < strings.ToLower(peerOptions[j].Name)
	})
	psEsc := func(v string) string { return strings.ReplaceAll(v, "'", "''") }
	peerRows := make([]string, 0, len(peerOptions))
	for _, p := range peerOptions {
		peerRows = append(peerRows, "[pscustomobject]@{ID='"+psEsc(p.ID)+"';Name='"+psEsc(p.Name)+"';IP='"+psEsc(p.IP)+"'}")
	}
	peerLiteral := "@(" + strings.Join(peerRows, ",") + ")"
	secretDir := filepath.Join(os.Getenv("APPDATA"), "FarmitraNearby", "secrets")
	_ = os.MkdirAll(secretDir, 0700)
	scriptPath := filepath.Join(filepath.Dir(cfgPath), "ai-settings-ui.ps1")
	ps := `$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security
$configPath='` + psEsc(cfgPath) + `'
$secretDir='` + psEsc(secretDir) + `'
$peers=` + peerLiteral + `
try{$cfg=Get-Content -Raw -Path $configPath|ConvertFrom-Json}catch{$cfg=[pscustomobject]@{share_ai=$true;allowed_ai_devices=@();provider='ollama';model='';ollama_url='http://127.0.0.1:11434';groq_model='llama-3.3-70b-versatile';openai_model='gpt-4.1-mini';gemini_model='gemini-2.5-flash'}}
function Read-Secret([string]$provider){
  $p=Join-Path $secretDir ($provider+'.dpapi'); if(-not(Test-Path $p)){return ''}
  try{$b=[Convert]::FromBase64String((Get-Content -Raw $p));$d=[Security.Cryptography.ProtectedData]::Unprotect($b,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser);return [Text.Encoding]::UTF8.GetString($d)}catch{return ''}
}
function Save-Secret([string]$provider,[string]$value){
  if($provider -eq 'ollama'){return}; $p=Join-Path $secretDir ($provider+'.dpapi')
  if([string]::IsNullOrWhiteSpace($value)){if(Test-Path $p){Remove-Item $p -Force};return}
  $b=[Text.Encoding]::UTF8.GetBytes($value);$d=[Security.Cryptography.ProtectedData]::Protect($b,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser);[Convert]::ToBase64String($d)|Set-Content -Encoding ASCII -Path $p
}
$keys=@{groq=(Read-Secret 'groq');openai=(Read-Secret 'openai');gemini=(Read-Secret 'gemini')}
$form=New-Object Windows.Forms.Form
$form.Text='Farmitra Nearby — AI Settings';$form.StartPosition='CenterScreen';$form.Size=New-Object Drawing.Size(660,760);$form.MinimumSize=$form.Size;$form.MaximumSize=$form.Size;$form.Font=New-Object Drawing.Font('Segoe UI Variable Text',10);$form.BackColor=[Drawing.Color]::FromArgb(247,250,248);$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false
$header=New-Object Windows.Forms.Label;$header.Text='AI Settings';$header.Font=New-Object Drawing.Font('Segoe UI Variable Display Semibold',20);$header.Location=New-Object Drawing.Point(30,22);$header.AutoSize=$true;$form.Controls.Add($header)
$sub=New-Object Windows.Forms.Label;$sub.Text='Use local Ollama or connect Groq, Gemini or OpenAI. API keys stay encrypted on this Windows account.';$sub.ForeColor=[Drawing.Color]::DimGray;$sub.Location=New-Object Drawing.Point(32,62);$sub.Size=New-Object Drawing.Size(570,42);$form.Controls.Add($sub)
$share=New-Object Windows.Forms.CheckBox;$share.Text='Enable Nearby AI for approved devices';$share.Location=New-Object Drawing.Point(32,108);$share.Size=New-Object Drawing.Size(500,28);$share.Checked=[bool]$cfg.share_ai;$form.Controls.Add($share)
$allowedTitle=New-Object Windows.Forms.Label;$allowedTitle.Text='Allowed nearby devices';$allowedTitle.Font=New-Object Drawing.Font('Segoe UI Variable Text Semibold',10);$allowedTitle.Location=New-Object Drawing.Point(32,146);$allowedTitle.Size=New-Object Drawing.Size(240,24);$form.Controls.Add($allowedTitle)
$hint=New-Object Windows.Forms.Label;$hint.Text='Each device has its own permission. Check multiple devices if needed.';$hint.ForeColor=[Drawing.Color]::DimGray;$hint.Location=New-Object Drawing.Point(32,170);$hint.Size=New-Object Drawing.Size(560,24);$form.Controls.Add($hint)
$devicePanel=New-Object Windows.Forms.Panel;$devicePanel.Location=New-Object Drawing.Point(32,198);$devicePanel.Size=New-Object Drawing.Size(580,128);$devicePanel.AutoScroll=$true;$devicePanel.BorderStyle='FixedSingle';$devicePanel.BackColor=[Drawing.Color]::White;$form.Controls.Add($devicePanel)
$deviceChecks=New-Object System.Collections.ArrayList;$allowedIds=@();if($null-ne$cfg.allowed_ai_devices){$allowedIds=@($cfg.allowed_ai_devices)};$y=6
foreach($p in $peers){$cb=New-Object Windows.Forms.CheckBox;$name=[string]$p.Name;if([string]::IsNullOrWhiteSpace($name)){$name='Unknown device'};$id=[string]$p.ID;$suffix=$id;if($suffix.Length-gt8){$suffix=$suffix.Substring($suffix.Length-8)};$cb.Text=($name+'   |   '+[string]$p.IP+'   |   ID '+$suffix);$cb.Tag=$id;$cb.Location=New-Object Drawing.Point(9,$y);$cb.Size=New-Object Drawing.Size(545,30);$cb.Checked=($allowedIds-contains$id);$devicePanel.Controls.Add($cb);[void]$deviceChecks.Add($cb);$y+=30}
if($deviceChecks.Count-eq0){$e=New-Object Windows.Forms.Label;$e.Text='No nearby devices discovered yet.';$e.ForeColor=[Drawing.Color]::DimGray;$e.Location=New-Object Drawing.Point(10,12);$e.Size=New-Object Drawing.Size(450,26);$devicePanel.Controls.Add($e)}
function L([string]$t,[int]$y){$l=New-Object Windows.Forms.Label;$l.Text=$t;$l.Location=New-Object Drawing.Point(32,$y);$l.Size=New-Object Drawing.Size(145,25);$form.Controls.Add($l)}
L 'Provider' 350
$provider=New-Object Windows.Forms.ComboBox;$provider.DropDownStyle='DropDownList';[void]$provider.Items.AddRange(@('ollama','groq','gemini','openai'));$provider.Location=New-Object Drawing.Point(180,346);$provider.Size=New-Object Drawing.Size(365,30);$provider.SelectedItem=[string]$cfg.provider;if($provider.SelectedIndex-lt0){$provider.SelectedIndex=0};$form.Controls.Add($provider)
L 'Model' 396
$model=New-Object Windows.Forms.ComboBox;$model.DropDownStyle='DropDown';$model.Location=New-Object Drawing.Point(180,392);$model.Size=New-Object Drawing.Size(365,30);$form.Controls.Add($model)
$valueLabel=New-Object Windows.Forms.Label;$valueLabel.Text='Ollama URL';$valueLabel.Location=New-Object Drawing.Point(32,442);$valueLabel.Size=New-Object Drawing.Size(145,25);$form.Controls.Add($valueLabel)
$url=New-Object Windows.Forms.TextBox;$url.Location=New-Object Drawing.Point(180,438);$url.Size=New-Object Drawing.Size(365,30);$url.Text=[string]$cfg.ollama_url;$form.Controls.Add($url)
$key=New-Object Windows.Forms.TextBox;$key.Location=New-Object Drawing.Point(180,438);$key.Size=New-Object Drawing.Size(280,30);$key.UseSystemPasswordChar=$true;$form.Controls.Add($key)
$eye=New-Object Windows.Forms.Button;$eye.Text='Show';$eye.Location=New-Object Drawing.Point(468,436);$eye.Size=New-Object Drawing.Size(66,32);$form.Controls.Add($eye)
$paste=New-Object Windows.Forms.Button;$paste.Text='Paste';$paste.Location=New-Object Drawing.Point(540,436);$paste.Size=New-Object Drawing.Size(72,32);$form.Controls.Add($paste)
$status=New-Object Windows.Forms.Label;$status.Location=New-Object Drawing.Point(32,486);$status.Size=New-Object Drawing.Size(580,54);$status.ForeColor=[Drawing.Color]::DimGray;$status.Text='Local AI works even when Nearby AI sharing is disabled.';$form.Controls.Add($status)
$detect=New-Object Windows.Forms.Button;$detect.Text='Detect models';$detect.Location=New-Object Drawing.Point(32,552);$detect.Size=New-Object Drawing.Size(150,40);$form.Controls.Add($detect)
$test=New-Object Windows.Forms.Button;$test.Text='Test connection';$test.Location=New-Object Drawing.Point(194,552);$test.Size=New-Object Drawing.Size(150,40);$form.Controls.Add($test)
$save=New-Object Windows.Forms.Button;$save.Text='Save';$save.Location=New-Object Drawing.Point(462,552);$save.Size=New-Object Drawing.Size(150,40);$save.BackColor=[Drawing.Color]::FromArgb(39,184,82);$save.ForeColor=[Drawing.Color]::White;$save.FlatStyle='Flat';$form.Controls.Add($save)
$privacy=New-Object Windows.Forms.Label;$privacy.Text='API keys are protected with Windows DPAPI (Current User) and are never shared with nearby devices.';$privacy.ForeColor=[Drawing.Color]::DimGray;$privacy.Location=New-Object Drawing.Point(32,610);$privacy.Size=New-Object Drawing.Size(580,45);$form.Controls.Add($privacy)
function Default-Model([string]$p){switch($p){'groq'{return [string]$cfg.groq_model};'openai'{return [string]$cfg.openai_model};'gemini'{return [string]$cfg.gemini_model};default{return [string]$cfg.model}}}
function Refresh-ProviderUI{
 $p=[string]$provider.SelectedItem;$cloud=($p-ne'ollama')
 if($cloud){
   $valueLabel.Text='API Key';$url.Visible=$false;$key.Visible=$true;$eye.Visible=$true;$paste.Visible=$true
   $key.Text=[string]$keys[$p];$key.UseSystemPasswordChar=$true;$eye.Text='Show'
   $status.Text=('Enter your '+$p+' API key. It will be encrypted with Windows DPAPI and kept only on this PC.')
 }else{
   $valueLabel.Text='Ollama URL';$url.Visible=$true;$key.Visible=$false;$eye.Visible=$false;$paste.Visible=$false;$key.Text=''
   $status.Text='Local AI works even when Nearby AI sharing is disabled.'
 }
 $model.Text=Default-Model $p
 $detect.Text=if($p-eq'ollama'){'Detect models'}else{'Use recommended model'}
}
$provider.Add_SelectedIndexChanged({Refresh-ProviderUI})
$eye.Add_Click({$key.UseSystemPasswordChar=-not$key.UseSystemPasswordChar;$eye.Text=if($key.UseSystemPasswordChar){'Show'}else{'Hide'}})
$paste.Add_Click({try{$v=[Windows.Forms.Clipboard]::GetText();if(-not[string]::IsNullOrWhiteSpace($v)){$key.Text=$v.Trim();$status.Text='API key pasted. Use Test connection before saving.'}}catch{$status.Text='Could not read clipboard.'}})
$detect.Add_Click({$p=[string]$provider.SelectedItem;if($p-eq'ollama'){try{$tags=Invoke-RestMethod -Uri (($url.Text.TrimEnd('/'))+'/api/tags') -TimeoutSec 4;$model.Items.Clear();foreach($m in $tags.models){[void]$model.Items.Add([string]$m.name)};if($model.Items.Count-gt0){$model.SelectedIndex=0};$status.Text=('Detected '+$model.Items.Count+' Ollama model(s).')}catch{$status.Text='Ollama detection failed: '+$_.Exception.Message}}else{$model.Text=Default-Model $p;$status.Text='Recommended model loaded. You can edit it manually.'}})
$test.Add_Click({
 $p=[string]$provider.SelectedItem;$status.Text='Testing '+$p+'…';$form.Refresh()
 try{
  if($p-eq'ollama'){$r=Invoke-RestMethod -Uri (($url.Text.TrimEnd('/'))+'/api/tags') -TimeoutSec 5;$status.Text=('Connected to Ollama • '+$r.models.Count+' model(s) available');return}
  if([string]::IsNullOrWhiteSpace($key.Text)){throw 'API key is required.'}
  $h=@{Authorization=('Bearer '+$key.Text)}
  if($p-eq'groq'){$null=Invoke-RestMethod -Uri 'https://api.groq.com/openai/v1/models' -Headers $h -TimeoutSec 8;$status.Text='Groq connected successfully.'}
  elseif($p-eq'openai'){$null=Invoke-RestMethod -Uri 'https://api.openai.com/v1/models' -Headers $h -TimeoutSec 8;$status.Text='OpenAI connected successfully.'}
  elseif($p-eq'gemini'){$null=Invoke-RestMethod -Uri ('https://generativelanguage.googleapis.com/v1beta/models?key='+[uri]::EscapeDataString($key.Text)) -TimeoutSec 8;$status.Text='Gemini connected successfully.'}
 }catch{$status.Text=('Connection failed: '+$_.Exception.Message)}
})
$save.Add_Click({
 $allowed=New-Object System.Collections.ArrayList;$current=@($peers|ForEach-Object{[string]$_.ID});foreach($old in $allowedIds){if($current-notcontains[string]$old){[void]$allowed.Add([string]$old)}};foreach($cb in $deviceChecks){if($cb.Checked){[void]$allowed.Add([string]$cb.Tag)}};$unique=@($allowed|Select-Object -Unique)
 $p=[string]$provider.SelectedItem;if($p-ne'ollama'){Save-Secret $p $key.Text;$keys[$p]=$key.Text}
 $gm=[string]$cfg.groq_model;$om=[string]$cfg.openai_model;$xm=[string]$cfg.gemini_model;if($p-eq'groq'){$gm=$model.Text.Trim()};if($p-eq'openai'){$om=$model.Text.Trim()};if($p-eq'gemini'){$xm=$model.Text.Trim()}
 $out=[ordered]@{share_ai=[bool]$share.Checked;allowed_ai_devices=@($unique);provider=$p;model=[string]$model.Text.Trim();ollama_url=[string]$url.Text.Trim();groq_model=$gm;openai_model=$om;gemini_model=$xm};$out|ConvertTo-Json -Depth 4|Set-Content -Encoding UTF8 -Path $configPath;$form.DialogResult=[Windows.Forms.DialogResult]::OK;$form.Close()
})
Refresh-ProviderUI
[void]$form.ShowDialog()
`
	if err := os.WriteFile(scriptPath, []byte(ps), 0600); err != nil {
		postUI(func() { messageBox(a.hwnd, "AI settings", err.Error(), true) })
		return
	}
	cmd := exec.Command("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-File", scriptPath)
	if err := cmd.Run(); err != nil {
		postUI(func() { messageBox(a.hwnd, "AI settings", "Could not open AI settings: "+err.Error(), true) })
		return
	}
	postUI(func() {
		a.aiConfig = loadAIConfig()
		a.appendLogUI("AI settings updated • " + a.aiConfig.Provider + " • " + effectiveAIModel(a.aiConfig))
		invalidate()
	})
}

func (a *App) openAboutUI() {
	ps := `$ErrorActionPreference='SilentlyContinue'; Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
$f=New-Object Windows.Forms.Form;$f.Text='About Farmitra Nearby';$f.StartPosition='CenterScreen';$f.Size=New-Object Drawing.Size(540,455);$f.MinimumSize=$f.Size;$f.MaximumSize=$f.Size;$f.FormBorderStyle='FixedDialog';$f.MaximizeBox=$false;$f.BackColor=[Drawing.Color]::FromArgb(247,250,248);$f.Font=New-Object Drawing.Font('Segoe UI Variable Text',10)
$t=New-Object Windows.Forms.Label;$t.Text='Farmitra Nearby';$t.Font=New-Object Drawing.Font('Segoe UI Variable Display Semibold',22);$t.ForeColor=[Drawing.Color]::FromArgb(31,166,76);$t.Location=New-Object Drawing.Point(28,23);$t.AutoSize=$true;$f.Controls.Add($t)
$tag=New-Object Windows.Forms.Label;$tag.Text='Fast • Private • Direct';$tag.Font=New-Object Drawing.Font('Segoe UI Variable Text Semibold',10);$tag.ForeColor=[Drawing.Color]::DimGray;$tag.Location=New-Object Drawing.Point(31,65);$tag.Size=New-Object Drawing.Size(450,24);$f.Controls.Add($tag)
$d=New-Object Windows.Forms.Label;$d.Text='Farmitra Nearby connects trusted Windows and Android devices for private local chat, file and folder sharing, clipboard transfer, Direct P2P and Nearby AI.';$d.Location=New-Object Drawing.Point(31,101);$d.Size=New-Object Drawing.Size(465,58);$f.Controls.Add($d)
$how=New-Object Windows.Forms.Label;$how.Text='How to use';$how.Font=New-Object Drawing.Font('Segoe UI Variable Text Semibold',11);$how.Location=New-Object Drawing.Point(31,171);$how.Size=New-Object Drawing.Size(180,24);$f.Controls.Add($how)
$steps=New-Object Windows.Forms.Label;$nl=[Environment]::NewLine;$steps.Text=('1. Open Farmitra Nearby on both devices and select a discovered device.'+$nl+'2. Use People mode for messages, files, folders or clipboard sharing.'+$nl+'3. Use Direct P2P when no router is available.'+$nl+'4. Use Nearby AI to access an approved host PC running Ollama, Groq, Gemini or OpenAI.');$steps.ForeColor=[Drawing.Color]::FromArgb(55,65,60);$steps.Location=New-Object Drawing.Point(31,199);$steps.Size=New-Object Drawing.Size(465,108);$f.Controls.Add($steps)
$who=New-Object Windows.Forms.Label;$who.Text='Who is it for?';$who.Font=New-Object Drawing.Font('Segoe UI Variable Text Semibold',11);$who.Location=New-Object Drawing.Point(31,316);$who.Size=New-Object Drawing.Size(180,24);$f.Controls.Add($who)
$whoText=New-Object Windows.Forms.Label;$whoText.Text='Useful for personal devices, developers, offices, students and small teams that need quick device-to-device sharing without relying on cloud storage.';$whoText.ForeColor=[Drawing.Color]::DimGray;$whoText.Location=New-Object Drawing.Point(31,343);$whoText.Size=New-Object Drawing.Size(465,48);$f.Controls.Add($whoText)
$brand=New-Object Windows.Forms.Label;$brand.Text='Farmitra Nearby  —  A Farmitra Product';$brand.Font=New-Object Drawing.Font('Segoe UI Variable Text Semibold',10);$brand.ForeColor=[Drawing.Color]::FromArgb(31,166,76);$brand.Location=New-Object Drawing.Point(31,400);$brand.Size=New-Object Drawing.Size(450,24);$f.Controls.Add($brand)
[void]$f.ShowDialog()`
	cmd := exec.Command("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-Command", ps)
	_ = cmd.Run()
}

func aiDeviceAllowed(c AIConfig, deviceID string) bool {
	if deviceID == "" {
		return false
	}
	for _, id := range c.AllowedAI {
		if strings.TrimSpace(id) == deviceID {
			return true
		}
	}
	return false
}

func effectiveAIModel(c AIConfig) string {
	if c.Model != "" {
		return c.Model
	}
	switch strings.ToLower(c.Provider) {
	case "groq":
		return c.GroqModel
	case "openai":
		return c.OpenAIModel
	case "gemini":
		return c.GeminiModel
	default:
		return "auto"
	}
}
func aiProviderAvailable(c AIConfig) bool {
	if !c.ShareAI {
		return false
	}
	switch strings.ToLower(c.Provider) {
	case "ollama":
		cl := http.Client{Timeout: 350 * time.Millisecond}
		r, e := cl.Get(strings.TrimRight(c.OllamaURL, "/") + "/api/tags")
		if e != nil {
			return false
		}
		r.Body.Close()
		return r.StatusCode >= 200 && r.StatusCode < 300
	case "groq", "openai", "gemini":
		return strings.TrimSpace(c.APIKey) != ""
	}
	return false
}
func runAI(c AIConfig, prompt string, emit func(string) error) error {
	switch strings.ToLower(c.Provider) {
	case "ollama":
		return runOllama(c, prompt, emit)
	case "groq":
		return runOpenAICompatible("https://api.groq.com/openai/v1/chat/completions", c.APIKey, effectiveAIModel(c), prompt, emit)
	case "openai":
		return runOpenAICompatible("https://api.openai.com/v1/chat/completions", c.APIKey, effectiveAIModel(c), prompt, emit)
	case "gemini":
		return runGemini(c, prompt, emit)
	}
	return fmt.Errorf("unsupported AI provider: %s", c.Provider)
}
func runOllama(c AIConfig, prompt string, emit func(string) error) error {
	model := c.Model
	if model == "" {
		model = firstOllamaModel(c.OllamaURL)
		if model == "" {
			return fmt.Errorf("Ollama is running but no model is installed")
		}
	}
	body, _ := json.Marshal(map[string]any{"model": model, "messages": []map[string]string{{"role": "user", "content": prompt}}, "stream": true})
	req, _ := http.NewRequest("POST", strings.TrimRight(c.OllamaURL, "/")+"/api/chat", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, e := (&http.Client{Timeout: 30 * time.Minute}).Do(req)
	if e != nil {
		return e
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return fmt.Errorf("Ollama HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(b)))
	}
	sc := bufio.NewScanner(resp.Body)
	buf := make([]byte, 0, 64*1024)
	sc.Buffer(buf, 1024*1024)
	for sc.Scan() {
		var x struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
			Done bool `json:"done"`
		}
		if json.Unmarshal(sc.Bytes(), &x) == nil && x.Message.Content != "" {
			if e := emit(x.Message.Content); e != nil {
				return e
			}
		}
	}
	return sc.Err()
}
func firstOllamaModel(url string) string {
	cl := http.Client{Timeout: 700 * time.Millisecond}
	r, e := cl.Get(strings.TrimRight(url, "/") + "/api/tags")
	if e != nil {
		return ""
	}
	defer r.Body.Close()
	var x struct {
		Models []struct {
			Name string `json:"name"`
		} `json:"models"`
	}
	if json.NewDecoder(r.Body).Decode(&x) == nil && len(x.Models) > 0 {
		return x.Models[0].Name
	}
	return ""
}
func runOpenAICompatible(url, key, model, prompt string, emit func(string) error) error {
	if key == "" {
		return fmt.Errorf("API key is not configured on the AI host")
	}
	body, _ := json.Marshal(map[string]any{"model": model, "messages": []map[string]string{{"role": "user", "content": prompt}}, "stream": false})
	req, _ := http.NewRequest("POST", url, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+key)
	resp, e := (&http.Client{Timeout: 5 * time.Minute}).Do(req)
	if e != nil {
		return e
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 16*1024*1024))
	if resp.StatusCode >= 300 {
		return fmt.Errorf("provider HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(b)))
	}
	var x struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if e := json.Unmarshal(b, &x); e != nil {
		return e
	}
	if len(x.Choices) == 0 {
		return fmt.Errorf("provider returned no response")
	}
	return emit(x.Choices[0].Message.Content)
}
func runGemini(c AIConfig, prompt string, emit func(string) error) error {
	key := strings.TrimSpace(c.APIKey)
	if key == "" {
		return fmt.Errorf("Gemini API key is not configured on the AI host")
	}
	model := effectiveAIModel(c)
	url := "https://generativelanguage.googleapis.com/v1beta/models/" + model + ":generateContent?key=" + key
	body, _ := json.Marshal(map[string]any{"contents": []map[string]any{{"parts": []map[string]string{{"text": prompt}}}}})
	req, _ := http.NewRequest("POST", url, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, e := (&http.Client{Timeout: 5 * time.Minute}).Do(req)
	if e != nil {
		return e
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 16*1024*1024))
	if resp.StatusCode >= 300 {
		return fmt.Errorf("Gemini HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(b)))
	}
	var x struct {
		Candidates []struct {
			Content struct {
				Parts []struct {
					Text string `json:"text"`
				} `json:"parts"`
			} `json:"content"`
		} `json:"candidates"`
	}
	if e := json.Unmarshal(b, &x); e != nil {
		return e
	}
	if len(x.Candidates) == 0 || len(x.Candidates[0].Content.Parts) == 0 {
		return fmt.Errorf("Gemini returned no response")
	}
	return emit(x.Candidates[0].Content.Parts[0].Text)
}

func exePath() string { e, _ := os.Executable(); e, _ = filepath.Abs(e); return e }
func startupEnabled() bool {
	out, e := exec.Command("reg", "query", `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, "/v", "FarmitraNearby").CombinedOutput()
	return e == nil && strings.Contains(strings.ToLower(string(out)), strings.ToLower(exePath()))
}
func setStartup(on bool) error {
	key := `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
	if on {
		return exec.Command("reg", "add", key, "/v", "FarmitraNearby", "/t", "REG_SZ", "/d", `"`+exePath()+`" --background`, "/f").Run()
	}
	return exec.Command("reg", "delete", key, "/v", "FarmitraNearby", "/f").Run()
}

func zipFolder(src, dest string) error {
	out, e := os.Create(dest)
	if e != nil {
		return e
	}
	zw := zip.NewWriter(out)
	e = filepath.Walk(src, func(path string, info os.FileInfo, e error) error {
		if e != nil {
			return e
		}
		rel, e := filepath.Rel(filepath.Dir(src), path)
		if e != nil {
			return e
		}
		rel = filepath.ToSlash(rel)
		if info.IsDir() {
			_, e = zw.Create(rel + "/")
			return e
		}
		h, e := zip.FileInfoHeader(info)
		if e != nil {
			return e
		}
		h.Name = rel
		h.Method = zip.Deflate
		w, e := zw.CreateHeader(h)
		if e != nil {
			return e
		}
		f, e := os.Open(path)
		if e != nil {
			return e
		}
		_, ce := io.Copy(w, f)
		f.Close()
		return ce
	})
	e2 := zw.Close()
	e3 := out.Close()
	if e != nil {
		return e
	}
	if e2 != nil {
		return e2
	}
	return e3
}
func unzipSafe(src, dest string) error {
	r, e := zip.OpenReader(src)
	if e != nil {
		return e
	}
	defer r.Close()
	cleanDest := filepath.Clean(dest) + string(os.PathSeparator)
	for _, f := range r.File {
		target := filepath.Join(dest, f.Name)
		clean := filepath.Clean(target)
		if clean != filepath.Clean(dest) && !strings.HasPrefix(clean+string(os.PathSeparator), cleanDest) {
			return fmt.Errorf("unsafe archive path")
		}
		if f.FileInfo().IsDir() {
			if e := os.MkdirAll(target, 0755); e != nil {
				return e
			}
			continue
		}
		if e := os.MkdirAll(filepath.Dir(target), 0755); e != nil {
			return e
		}
		rc, e := f.Open()
		if e != nil {
			return e
		}
		out, e := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, f.Mode())
		if e != nil {
			rc.Close()
			return e
		}
		_, ce := io.Copy(out, rc)
		out.Close()
		rc.Close()
		if ce != nil {
			return ce
		}
	}
	return nil
}
func uniquePath(p string) string {
	if _, e := os.Stat(p); os.IsNotExist(e) {
		return p
	}
	ext := filepath.Ext(p)
	base := strings.TrimSuffix(p, ext)
	for i := 2; ; i++ {
		c := fmt.Sprintf("%s (%d)%s", base, i, ext)
		if _, e := os.Stat(c); os.IsNotExist(e) {
			return c
		}
	}
}
func uniqueDir(p string) string {
	if _, e := os.Stat(p); os.IsNotExist(e) {
		return p
	}
	for i := 2; ; i++ {
		c := fmt.Sprintf("%s (%d)", p, i)
		if _, e := os.Stat(c); os.IsNotExist(e) {
			return c
		}
	}
}
func humanSize(n int64) string {
	const unit = 1024
	if n < unit {
		return fmt.Sprintf("%d B", n)
	}
	div, exp := int64(unit), 0
	for v := n / unit; v >= unit; v /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %ciB", float64(n)/float64(div), "KMGTPE"[exp])
}

// ---- GDI helpers ----
func fill(dc uintptr, r RECT, c uintptr) {
	b, _, _ := pCreateSolidBrush.Call(c)
	pFillRect.Call(dc, uintptr(unsafe.Pointer(&r)), b)
	pDeleteObject.Call(b)
}
func fillRound(dc uintptr, r RECT, rad int, c uintptr) {
	b, _, _ := pCreateSolidBrush.Call(c)
	pen, _, _ := pCreatePen.Call(PS_SOLID, 1, c)
	ob, _, _ := pSelectObject.Call(dc, b)
	op, _, _ := pSelectObject.Call(dc, pen)
	pRoundRect.Call(dc, uintptr(r.Left), uintptr(r.Top), uintptr(r.Right), uintptr(r.Bottom), uintptr(rad*2), uintptr(rad*2))
	pSelectObject.Call(dc, ob)
	pSelectObject.Call(dc, op)
	pDeleteObject.Call(b)
	pDeleteObject.Call(pen)
}
func fillEllipse(dc uintptr, r RECT, c uintptr) {
	b, _, _ := pCreateSolidBrush.Call(c)
	pen, _, _ := pCreatePen.Call(PS_SOLID, 1, c)
	ob, _, _ := pSelectObject.Call(dc, b)
	op, _, _ := pSelectObject.Call(dc, pen)
	pEllipse.Call(dc, uintptr(r.Left), uintptr(r.Top), uintptr(r.Right), uintptr(r.Bottom))
	pSelectObject.Call(dc, ob)
	pSelectObject.Call(dc, op)
	pDeleteObject.Call(b)
	pDeleteObject.Call(pen)
}
func strokeRound(dc uintptr, r RECT, rad int, c uintptr, width int) {
	pen, _, _ := pCreatePen.Call(PS_SOLID, uintptr(width), c)
	op, _, _ := pSelectObject.Call(dc, pen)
	stock, _, _ := pGetStockObject.Call(5)
	ob, _, _ := pSelectObject.Call(dc, stock)
	pRoundRect.Call(dc, uintptr(r.Left), uintptr(r.Top), uintptr(r.Right), uintptr(r.Bottom), uintptr(rad*2), uintptr(rad*2))
	pSelectObject.Call(dc, ob)
	pSelectObject.Call(dc, op)
	pDeleteObject.Call(pen)
}
func copyTextToClipboard(hwnd uintptr, text string) error {
	if text == "" {
		return nil
	}
	// Clipboard ownership can briefly be held by another Windows process. Retry a
	// few times and open without tying ownership to the custom-painted chat window.
	var opened bool
	for i := 0; i < 6; i++ {
		r, _, _ := pOpenClipboard.Call(0)
		if r != 0 {
			opened = true
			break
		}
		time.Sleep(18 * time.Millisecond)
	}
	if opened {
		func() {
			defer pCloseClipboard.Call()
			pEmptyClipboard.Call()
			u := syscall.StringToUTF16(text)
			size := uintptr(len(u) * 2)
			h, _, _ := pGlobalAlloc.Call(GMEM_MOVEABLE, size)
			if h == 0 {
				return
			}
			ptr, _, _ := pGlobalLock.Call(h)
			if ptr == 0 {
				pGlobalFree.Call(h)
				return
			}
			buf := unsafe.Slice((*uint16)(unsafe.Pointer(ptr)), len(u))
			copy(buf, u)
			pGlobalUnlock.Call(h)
			res, _, _ := pSetClipboardData.Call(CF_UNICODETEXT, h)
			if res == 0 {
				pGlobalFree.Call(h)
			}
		}()
		// Verify by trusting SetClipboardData path; Windows now owns the memory.
		return nil
	}
	// Last-resort Windows-native fallback. clip.exe is present on supported Windows
	// releases and avoids leaving the user with a dead copy affordance.
	cmd := exec.Command("cmd.exe", "/c", "clip")
	cmd.Stdin = strings.NewReader(text)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("could not copy to clipboard: %w", err)
	}
	_ = hwnd
	return nil
}

func drawText(dc uintptr, s string, r RECT, font, color uintptr, flags uint32) {
	old, _, _ := pSelectObject.Call(dc, font)
	pSetBkMode.Call(dc, TRANSPARENT)
	pSetTextColor.Call(dc, color)
	pDrawText.Call(dc, uintptr(unsafe.Pointer(wstr(s))), ^uintptr(0), uintptr(unsafe.Pointer(&r)), uintptr(flags))
	pSelectObject.Call(dc, old)
}
func calcText(dc uintptr, s string, r *RECT, font uintptr, flags uint32) {
	old, _, _ := pSelectObject.Call(dc, font)
	pDrawText.Call(dc, uintptr(unsafe.Pointer(wstr(s))), ^uintptr(0), uintptr(unsafe.Pointer(r)), uintptr(flags|DT_CALCRECT))
	pSelectObject.Call(dc, old)
}
func min32(a, b int32) int32 {
	if a < b {
		return a
	}
	return b
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
