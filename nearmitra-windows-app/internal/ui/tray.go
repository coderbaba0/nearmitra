// Package ui provides system tray integration and notifications for NearMitra.
package ui

import (
	"unsafe"
)

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

	copyTip := UTF16Ptr("NearMitra - Local AI & P2P Transfer")
	copy(tm.nid.SzTip[:], (*[128]uint16)(unsafe.Pointer(copyTip))[:])

	pShellNotifyIcon.Call(NIM_ADD, uintptr(unsafe.Pointer(&tm.nid)))
	tm.active = true
	return tm
}

// ShowNotification displays a Windows balloon notification from the tray icon.
func (tm *TrayManager) ShowNotification(title, message string) {
	if !tm.active {
		return
	}
	tm.nid.UFlags = NIF_INFO
	copyTitle := UTF16Ptr(title)
	copyMsg := UTF16Ptr(message)
	copy(tm.nid.SzInfoTitle[:], (*[64]uint16)(unsafe.Pointer(copyTitle))[:])
	copy(tm.nid.SzInfo[:], (*[256]uint16)(unsafe.Pointer(copyMsg))[:])
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
