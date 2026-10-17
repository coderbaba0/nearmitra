// Package ui provides system tray integration and notifications for NearMitra.
package ui

import (
	_ "embed"
	"encoding/binary"
	"log"
	"syscall"
	"unsafe"
)

//go:embed web/favicon.ico
var embeddedTrayIcon []byte

const (
	TrayUID     = 1001
	WM_TRAYICON = 0x8000 + 7
)

type TrayManager struct {
	hwnd   uintptr
	hIcon  uintptr
	nid    NOTIFYICONDATA
	active bool
}

// NewTrayManager creates a system tray manager bound to the main window.
func NewTrayManager(hwnd uintptr, hIcon uintptr) *TrayManager {
	tm := &TrayManager{
		hwnd:  hwnd,
		hIcon: hIcon,
	}

	tm.nid.CbSize = uint32(unsafe.Sizeof(tm.nid))
	tm.nid.HWnd = hwnd
	tm.nid.UID = TrayUID
	tm.nid.UFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP
	tm.nid.UCallbackMessage = WM_TRAYICON
	tm.nid.HIcon = hIcon

	copyTrayText(tm.nid.SzTip[:], "NearMitra - Local AI & P2P Transfer")
	tm.Add()
	return tm
}

// ShowNotification displays a Windows balloon notification from the tray icon.
func (tm *TrayManager) ShowNotification(title, message string) {
	if !tm.active {
		return
	}
	tm.nid.UFlags = NIF_INFO
	copyTrayText(tm.nid.SzInfoTitle[:], title)
	copyTrayText(tm.nid.SzInfo[:], message)
	tm.nid.DwInfoFlags = NIIF_INFO

	pShellNotifyIcon.Call(NIM_MODIFY, uintptr(unsafe.Pointer(&tm.nid)))
}

// Remove removes the icon from the system tray.
func (tm *TrayManager) Remove() {
	if tm.active {
		pShellNotifyIcon.Call(NIM_DELETE, uintptr(unsafe.Pointer(&tm.nid)))
		tm.active = false
	}
}

// ShowContextMenu renders the right-click tray context menu.
func (tm *TrayManager) ShowContextMenu(onOpen, onSaveFolder, onToggleTheme, onExit func()) {
	hMenu, _, _ := pCreatePopupMenu.Call()
	if hMenu == 0 {
		return
	}
	defer pDestroyMenu.Call(hMenu)

	pAppendMenu.Call(hMenu, MF_STRING, 1, uintptr(unsafe.Pointer(UTF16Ptr("Open NearMitra"))))
	pAppendMenu.Call(hMenu, MF_STRING, 2, uintptr(unsafe.Pointer(UTF16Ptr("Open Downloads Folder"))))
	pAppendMenu.Call(hMenu, MF_STRING, 3, uintptr(unsafe.Pointer(UTF16Ptr("Toggle Dark / Light Theme"))))
	pAppendMenu.Call(hMenu, MF_SEPARATOR, 0, 0)
	pAppendMenu.Call(hMenu, MF_STRING, 4, uintptr(unsafe.Pointer(UTF16Ptr("Exit NearMitra"))))

	var pt POINT
	pGetCursorPos.Call(uintptr(unsafe.Pointer(&pt)))
	pSetForegroundWindow.Call(tm.hwnd)

	ret, _, _ := pTrackPopupMenu.Call(hMenu, TPM_RIGHTBUTTON|0x0100, uintptr(pt.X), uintptr(pt.Y), 0, tm.hwnd, 0) // TPM_RETURNCMD = 0x0100
	switch ret {
	case 1:
		if onOpen != nil {
			onOpen()
		}
	case 2:
		if onSaveFolder != nil {
			onSaveFolder()
		}
	case 3:
		if onToggleTheme != nil {
			onToggleTheme()
		}
	case 4:
		if onExit != nil {
			onExit()
		}
	}
}

func copyTrayText(destination []uint16, text string) {
	clear(destination)
	value := syscall.StringToUTF16(text)
	if len(value) > len(destination) {
		value = value[:len(destination)-1]
	}
	copy(destination, value)
}

// Add is called at creation, on Explorer restart, and while registration retries.
func (tm *TrayManager) Add() bool {
	tm.nid.UFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP
	result, _, err := pShellNotifyIcon.Call(NIM_ADD, uintptr(unsafe.Pointer(&tm.nid)))
	tm.active = result != 0
	if !tm.active {
		log.Printf("[Tray] Shell_NotifyIcon registration failed: %v (window=%x icon=%x)", err, tm.hwnd, tm.hIcon)
	} else {
		log.Printf("[Tray] Notification icon registered")
	}
	return tm.active
}
func loadEmbeddedTrayIcon() uintptr {
	data := embeddedTrayIcon
	if len(data) < 22 || binary.LittleEndian.Uint16(data[2:4]) != 1 {
		return 0
	}
	count := int(binary.LittleEndian.Uint16(data[4:6]))
	best := -1
	for i := 0; i < count; i++ {
		offset := 6 + 16*i
		if offset+16 > len(data) {
			break
		}
		if best < 0 || data[offset] == 32 {
			best = offset
			if data[offset] == 32 {
				break
			}
		}
	}
	if best < 0 {
		return 0
	}
	size := int(binary.LittleEndian.Uint32(data[best+8 : best+12]))
	offset := int(binary.LittleEndian.Uint32(data[best+12 : best+16]))
	if size <= 0 || offset < 0 || offset > len(data)-size {
		return 0
	}
	icon, _, _ := user32.NewProc("CreateIconFromResourceEx").Call(uintptr(unsafe.Pointer(&data[offset])), uintptr(size), 1, 0x00030000, 32, 32, 0)
	return icon
}
