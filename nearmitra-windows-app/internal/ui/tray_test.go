package ui

import (
	"fmt"
	"os"
	"runtime"
	"strings"
	"syscall"
	"testing"
	"unsafe"
)

func TestTrayTextIsTerminatedWithoutReadingPastInput(t *testing.T) {
	var value [8]uint16
	copyTrayText(value[:], "NearMitra is running")
	if value[len(value)-1] != 0 || syscall.UTF16ToString(value[:]) != "NearMit" {
		t.Fatalf("invalid truncated tooltip: %v", value)
	}
	copyTrayText(value[:], "Hi")
	if syscall.UTF16ToString(value[:]) != "Hi" || value[3] != 0 {
		t.Fatal("old tooltip contents retained")
	}
}
func TestNotificationDataMatchesWindowsLayout(t *testing.T) {
	if unsafe.Sizeof(uintptr(0)) != 8 {
		t.Skip("amd64 package")
	}
	var value NOTIFYICONDATA
	if unsafe.Sizeof(value) != 976 || unsafe.Offsetof(value.HIcon) != 32 || unsafe.Offsetof(value.HBalloonIcon) != 968 {
		t.Fatalf("invalid notification structure size %d", unsafe.Sizeof(value))
	}
}
func TestEmbeddedTrayIconRegistersInWindowsShell(t *testing.T) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	shell, _, _ := user32.NewProc("GetShellWindow").Call()
	if shell == 0 {
		t.Skip("no interactive Windows Shell")
	}
	icon := loadEmbeddedTrayIcon()
	if icon == 0 {
		t.Fatal("embedded tray icon could not be loaded")
	}
	defer user32.NewProc("DestroyIcon").Call(icon)
	instance, _, _ := kernel32.NewProc("GetModuleHandleW").Call(0)
	name := UTF16Ptr(fmt.Sprintf("NearMitraTrayTest%d", os.Getpid()))
	wc := WNDCLASSEX{CbSize: uint32(unsafe.Sizeof(WNDCLASSEX{})), LpfnWndProc: pDefWindowProc.Addr(), HInstance: instance, LpszClassName: name}
	atom, _, err := pRegisterClassEx.Call(uintptr(unsafe.Pointer(&wc)))
	if atom == 0 {
		t.Fatal(err)
	}
	defer user32.NewProc("UnregisterClassW").Call(uintptr(unsafe.Pointer(name)), instance)
	hwnd, _, err := pCreateWindowEx.Call(0, uintptr(unsafe.Pointer(name)), uintptr(unsafe.Pointer(name)), 0, 0, 0, 0, 0, 0, 0, instance, 0)
	if hwnd == 0 {
		t.Fatal(err)
	}
	defer user32.NewProc("DestroyWindow").Call(hwnd)
	tray := NewTrayManager(hwnd, icon)
	defer tray.Remove()
	if !tray.active {
		t.Fatal("Windows Shell rejected tray icon")
	}
	if !strings.HasPrefix(syscall.UTF16ToString(tray.nid.SzTip[:]), "NearMitra") {
		t.Fatal("tooltip was not registered")
	}
}
