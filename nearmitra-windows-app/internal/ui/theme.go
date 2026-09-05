// Package ui implements the native Windows 11 Fluent UI graphics engine, controls, and event loop.
package ui

import (
	"syscall"
	"unsafe"
)

// Win32 GDI & System Constants
const (
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
	WM_LBUTTONUP        = 0x0202
	WM_LBUTTONDBLCLK    = 0x0203
	WM_MOUSEWHEEL       = 0x020A
	WM_RBUTTONUP        = 0x0205
	WM_DROPFILES        = 0x0233
	WM_SETFONT          = 0x0030
	WM_SETICON          = 0x0080
	ICON_SMALL          = 0
	ICON_BIG            = 1
	WM_KEYDOWN          = 0x0100
	VK_RETURN           = 0x0D

	SW_HIDE            = 0
	SW_SHOW            = 5
	SW_RESTORE         = 9
	DT_LEFT            = 0x00
	DT_CENTER          = 0x01
	DT_RIGHT           = 0x02
	DT_VCENTER         = 0x04
	DT_WORDBREAK       = 0x10
	DT_SINGLELINE      = 0x20
	DT_END_ELLIPSIS    = 0x8000
	DT_NOPREFIX        = 0x0800
	TRANSPARENT        = 1
	SRCCOPY            = 0x00CC0020
	FW_NORMAL          = 400
	FW_MEDIUM          = 500
	FW_SEMIBOLD        = 600
	FW_BOLD            = 700

	CLEARTYPE_QUALITY  = 5
	DEFAULT_CHARSET    = 1

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
	CF_UNICODETEXT     = 13
	GMEM_MOVEABLE      = 0x0002
	PS_SOLID           = 0
	MB_OK              = 0x00000000
	MB_ICONINFORMATION = 0x00000040
	MB_ICONERROR       = 0x00000010
	DWMWA_USE_IMMERSIVE_DARK_MODE = 20
)

// Windows 11 Fluent Theme Color Palette
type FluentPalette struct {
	PrimaryGreen   uint32
	PrimaryHover   uint32
	BgMain         uint32
	BgSidebar      uint32
	BgCard         uint32
	BgCardHover    uint32
	BorderColor    uint32
	BorderLight    uint32
	TextTitle      uint32
	TextBody       uint32
	TextMuted      uint32
	BubbleMine     uint32
	BubblePeer     uint32
	BadgeOnline    uint32
	BadgeOffline   uint32
	AccentCCTV     uint32
	AccentAI       uint32
}

var (
	DarkTheme = FluentPalette{
		PrimaryGreen: RGB(16, 185, 129),  // #10B981 (Vibrant Emerald)
		PrimaryHover: RGB(5, 150, 105),   // #059669
		BgMain:       RGB(11, 15, 25),    // #0B0F19 (Deep Fluent Dark)
		BgSidebar:    RGB(17, 24, 39),    // #111827 (Sidebar Slate)
		BgCard:       RGB(22, 31, 48),    // #161F30 (Mica Card)
		BgCardHover:  RGB(35, 47, 69),    // #232F45 (Card Hover)
		BorderColor:  RGB(40, 53, 77),    // #28354D (Subtle Border)
		BorderLight:  RGB(51, 65, 85),    // #334155
		TextTitle:    RGB(255, 255, 255), // #FFFFFF (Crisp White)
		TextBody:     RGB(226, 232, 240), // #E2E8F0 (Clean Slate Text)
		TextMuted:    RGB(148, 163, 184), // #94A3B8 (Muted Gray)
		BubbleMine:   RGB(6, 95, 70),     // Dark Emerald
		BubblePeer:   RGB(30, 41, 59),    // Slate Card
		BadgeOnline:  RGB(34, 197, 94),   // #22C55E
		BadgeOffline: RGB(100, 116, 139), // #64748B
		AccentCCTV:   RGB(59, 130, 246),  // #3B82F6 (Blue)
		AccentAI:     RGB(139, 92, 246),  // #8B5CF6 (Purple)
	}

	LightTheme = FluentPalette{
		PrimaryGreen: RGB(16, 185, 129),  // #10B981
		PrimaryHover: RGB(5, 150, 105),   // #059669
		BgMain:       RGB(248, 250, 252), // #F8FAFC
		BgSidebar:    RGB(255, 255, 255), // #FFFFFF
		BgCard:       RGB(255, 255, 255), // #FFFFFF
		BgCardHover:  RGB(241, 245, 249), // #F1F5F9
		BorderColor:  RGB(226, 232, 240), // #E2E8F0
		BorderLight:  RGB(203, 213, 225), // #CBD5E1
		TextTitle:    RGB(15, 23, 42),    // #0F172A
		TextBody:     RGB(51, 65, 85),    // #334155
		TextMuted:    RGB(100, 116, 139), // #64748B
		BubbleMine:   RGB(209, 250, 229), // Light Emerald
		BubblePeer:   RGB(255, 255, 255), // White
		BadgeOnline:  RGB(34, 197, 94),   // #22C55E
		BadgeOffline: RGB(148, 163, 184), // #94A3B8
		AccentCCTV:   RGB(59, 130, 246),  // #3B82F6
		AccentAI:     RGB(139, 92, 246),  // #8B5CF6
	}
)

// RGB packs r, g, b components into COLORREF format (0x00BBGGRR).
func RGB(r, g, b byte) uint32 {
	return uint32(r) | (uint32(g) << 8) | (uint32(b) << 16)
}

// DPI scale helper (baseline 96 DPI = 1.0)
var currentDPI = 96

func Scale(px int) int32 {
	if currentDPI <= 0 {
		return int32(px)
	}
	return int32((px * currentDPI) / 96)
}

func SetDPI(dpi int) {
	if dpi > 0 {
		currentDPI = dpi
	}
}

// Win32 API DLL Bindings
var (
	user32   = syscall.NewLazyDLL("user32.dll")
	gdi32    = syscall.NewLazyDLL("gdi32.dll")
	shell32  = syscall.NewLazyDLL("shell32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	dwmapi   = syscall.NewLazyDLL("dwmapi.dll")

	pRegisterClassEx         = user32.NewProc("RegisterClassExW")
	pCreateWindowEx          = user32.NewProc("CreateWindowExW")
	pDefWindowProc           = user32.NewProc("DefWindowProcW")
	pDestroyWindow           = user32.NewProc("DestroyWindow")
	pPostQuitMessage         = user32.NewProc("PostQuitMessage")
	pPostMessage             = user32.NewProc("PostMessageW")
	pGetMessage              = user32.NewProc("GetMessageW")
	pTranslateMessage        = user32.NewProc("TranslateMessage")
	pDispatchMessage         = user32.NewProc("DispatchMessageW")
	pBeginPaint              = user32.NewProc("BeginPaint")
	pEndPaint                = user32.NewProc("EndPaint")
	pInvalidateRect          = user32.NewProc("InvalidateRect")
	pGetClientRect           = user32.NewProc("GetClientRect")
	pSetWindowText           = user32.NewProc("SetWindowTextW")
	pGetWindowText           = user32.NewProc("GetWindowTextW")
	pShowWindow              = user32.NewProc("ShowWindow")
	pUpdateWindow            = user32.NewProc("UpdateWindow")
	pSendMessage             = user32.NewProc("SendMessageW")
	pSetFocus                = user32.NewProc("SetFocus")
	pFillRect                = user32.NewProc("FillRect")
	pDrawText                = user32.NewProc("DrawTextW")
	pSetTimer                = user32.NewProc("SetTimer")
	pKillTimer               = user32.NewProc("KillTimer")
	pShellNotifyIcon         = shell32.NewProc("Shell_NotifyIconW")
	pTrackPopupMenu          = user32.NewProc("TrackPopupMenu")
	pCreatePopupMenu         = user32.NewProc("CreatePopupMenu")
	pAppendMenu              = user32.NewProc("AppendMenuW")
	pDestroyMenu             = user32.NewProc("DestroyMenu")
	pGetCursorPos            = user32.NewProc("GetCursorPos")
	pSetForegroundWindow     = user32.NewProc("SetForegroundWindow")
	pMoveWindow              = user32.NewProc("MoveWindow")
	pMessageBox              = user32.NewProc("MessageBoxW")
	pOpenClipboard           = user32.NewProc("OpenClipboard")
	pCloseClipboard          = user32.NewProc("CloseClipboard")
	pEmptyClipboard          = user32.NewProc("EmptyClipboard")
	pSetClipboardData        = user32.NewProc("SetClipboardData")

	pCreateCompatibleDC      = gdi32.NewProc("CreateCompatibleDC")
	pCreateCompatibleBitmap  = gdi32.NewProc("CreateCompatibleBitmap")
	pSelectObject            = gdi32.NewProc("SelectObject")
	pDeleteObject            = gdi32.NewProc("DeleteObject")
	pDeleteDC                = gdi32.NewProc("DeleteDC")
	pBitBlt                  = gdi32.NewProc("BitBlt")
	pSetBkMode               = gdi32.NewProc("SetBkMode")
	pSetTextColor            = gdi32.NewProc("SetTextColor")
	pCreateSolidBrush        = gdi32.NewProc("CreateSolidBrush")
	pCreateFont              = gdi32.NewProc("CreateFontW")
	pRoundRect               = gdi32.NewProc("RoundRect")
	pCreatePen               = gdi32.NewProc("CreatePen")
	pEllipse                 = gdi32.NewProc("Ellipse")
	pDwmSetWindowAttribute   = dwmapi.NewProc("DwmSetWindowAttribute")
)

// Helper structures
type POINT struct{ X, Y int32 }
type RECT struct{ Left, Top, Right, Bottom int32 }
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

func UTF16Ptr(s string) *uint16 {
	res, _ := syscall.UTF16PtrFromString(s)
	return res
}

func UTF16ToString(ptr *uint16) string {
	if ptr == nil {
		return ""
	}
	return syscall.UTF16ToString((*[1 << 20]uint16)(unsafe.Pointer(ptr))[:])
}
