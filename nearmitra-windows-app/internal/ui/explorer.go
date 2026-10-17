package ui

import (
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

var explorerMu sync.Mutex
var explorerOLE = syscall.NewLazyDLL("ole32.dll")
var explorerAutomation = syscall.NewLazyDLL("oleaut32.dll")

type explorerGUID struct {
	A    uint32
	B, C uint16
	D    [8]byte
}
type explorerDispatch struct{ table *[7]uintptr }
type explorerVariant struct {
	Kind     uint16
	Reserved [3]uint16
	Value    uintptr
	Extra    uintptr
}
type explorerParams struct {
	Args              *explorerVariant
	Named             *int32
	Count, NamedCount uint32
}

func (o *explorerDispatch) call(index int, args ...uintptr) uintptr {
	r, _, _ := syscall.SyscallN(o.table[index], append([]uintptr{uintptr(unsafe.Pointer(o))}, args...)...)
	return r
}
func explorerHRESULT(hr uintptr) error {
	if int32(uint32(hr)) < 0 {
		return fmt.Errorf("Windows Explorer operation failed (0x%08x)", uint32(hr))
	}
	return nil
}
func (v *explorerVariant) clear() {
	explorerAutomation.NewProc("VariantClear").Call(uintptr(unsafe.Pointer(v)))
}
func (o *explorerDispatch) property(name string, args ...explorerVariant) (explorerVariant, error) {
	var empty explorerGUID
	var id int32
	ptr := UTF16Ptr(name)
	if err := explorerHRESULT(o.call(5, uintptr(unsafe.Pointer(&empty)), uintptr(unsafe.Pointer(&ptr)), 1, 0, uintptr(unsafe.Pointer(&id)))); err != nil {
		return explorerVariant{}, err
	}
	params := explorerParams{Count: uint32(len(args))}
	if len(args) > 0 {
		params.Args = &args[0]
	}
	var value explorerVariant
	hr := o.call(6, uintptr(id), uintptr(unsafe.Pointer(&empty)), 0, 3, uintptr(unsafe.Pointer(&params)), uintptr(unsafe.Pointer(&value)), 0, 0)
	if err := explorerHRESULT(hr); err != nil {
		value.clear()
		return explorerVariant{}, err
	}
	return value, nil
}
func (v explorerVariant) text() string {
	if v.Kind != 8 || v.Value == 0 {
		return ""
	}
	size, _, _ := explorerAutomation.NewProc("SysStringLen").Call(v.Value)
	if size == 0 || size > 32768 {
		return ""
	}
	return syscall.UTF16ToString(unsafe.Slice((*uint16)(unsafe.Pointer(v.Value)), size))
}
func explorerFolderFromURL(location string) (string, error) {
	parsed, err := url.Parse(location)
	if err != nil {
		return "", err
	}
	if !strings.EqualFold(parsed.Scheme, "file") {
		return "", fmt.Errorf("Not a file system folder")
	}
	path := parsed.Path
	if parsed.Host != "" && !strings.EqualFold(parsed.Host, "localhost") {
		path = "//" + parsed.Host + path
	} else if len(path) > 2 && path[0] == '/' && path[2] == ':' {
		path = path[1:]
	}
	return filepath.Clean(filepath.FromSlash(path)), nil
}
func explorerMatchingWindows(windows *explorerDispatch, folder string) []uintptr {
	count, err := windows.property("Count")
	if err != nil {
		return nil
	}
	n := int(uint32(count.Value))
	count.clear()
	if n > 256 {
		n = 256
	}
	var matches []uintptr
	for i := 0; i < n; i++ {
		item, err := windows.property("Item", explorerVariant{Kind: 3, Value: uintptr(i)})
		if err != nil {
			continue
		}
		if item.Kind == 9 && item.Value != 0 {
			window := (*explorerDispatch)(unsafe.Pointer(item.Value))
			location, e := window.property("LocationURL")
			if e == nil {
				path, e := explorerFolderFromURL(location.text())
				location.clear()
				if e == nil && strings.EqualFold(filepath.Clean(folder), path) {
					hwnd, e := window.property("HWND")
					if e == nil {
						if hwnd.Kind == 3 {
							matches = append(matches, uintptr(uint32(hwnd.Value)))
						} else if hwnd.Kind == 20 {
							matches = append(matches, hwnd.Value)
						}
						hwnd.clear()
					}
				}
			}
		}
		item.clear()
	}
	return matches
}
func explorerWindows() (*explorerDispatch, error) {
	cls := explorerGUID{0x9ba05972, 0xf6a8, 0x11cf, [8]byte{0xa4, 0x42, 0, 0xa0, 0xc9, 0x0a, 0x8f, 0x39}}
	iid := explorerGUID{0x00020400, 0, 0, [8]byte{0xc0, 0, 0, 0, 0, 0, 0, 0x46}}
	var windows *explorerDispatch
	hr, _, _ := explorerOLE.NewProc("CoCreateInstance").Call(uintptr(unsafe.Pointer(&cls)), 0, 0x17, uintptr(unsafe.Pointer(&iid)), uintptr(unsafe.Pointer(&windows)))
	return windows, explorerHRESULT(hr)
}
func explorerNativeOpen(folder, target string) error {
	var folderID uintptr
	hr, _, _ := shell32.NewProc("SHParseDisplayName").Call(uintptr(unsafe.Pointer(UTF16Ptr(folder))), 0, uintptr(unsafe.Pointer(&folderID)), 0, 0)
	if err := explorerHRESULT(hr); err != nil {
		return err
	}
	defer explorerOLE.NewProc("CoTaskMemFree").Call(folderID)
	var count uintptr
	var child uintptr
	var targetID uintptr
	if target != "" {
		hr, _, _ = shell32.NewProc("SHParseDisplayName").Call(uintptr(unsafe.Pointer(UTF16Ptr(target))), 0, uintptr(unsafe.Pointer(&targetID)), 0, 0)
		if err := explorerHRESULT(hr); err != nil {
			return err
		}
		defer explorerOLE.NewProc("CoTaskMemFree").Call(targetID)
		child, _, _ = shell32.NewProc("ILFindLastID").Call(targetID)
		count = 1
	}
	var children uintptr
	if count > 0 {
		children = uintptr(unsafe.Pointer(&child))
	}
	hr, _, _ = shell32.NewProc("SHOpenFolderAndSelectItems").Call(folderID, count, children, 0)
	return explorerHRESULT(hr)
}
func foregroundExplorer(hwnd uintptr) {
	if hwnd == 0 {
		return
	}
	var pid uint32
	user32.NewProc("GetWindowThreadProcessId").Call(hwnd, uintptr(unsafe.Pointer(&pid)))
	if pid != 0 {
		user32.NewProc("AllowSetForegroundWindow").Call(uintptr(pid))
	}
	iconic, _, _ := user32.NewProc("IsIconic").Call(hwnd)
	if iconic != 0 {
		user32.NewProc("ShowWindowAsync").Call(hwnd, 9)
	}
	// Normal z-order only; Explorer is never made permanently topmost.
	user32.NewProc("SetWindowPos").Call(hwnd, 0, 0, 0, 0, 0, 0x4053)
	user32.NewProc("SetForegroundWindow").Call(hwnd)
}
func openExplorerPath(path string, selectItem bool) error {
	if strings.TrimSpace(path) == "" {
		return fmt.Errorf("Folder path is empty")
	}
	absolute, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	folder := absolute
	target := ""
	if selectItem {
		if _, err = os.Stat(absolute); err != nil {
			return fmt.Errorf("Item is no longer available: %w", err)
		}
		folder = filepath.Dir(absolute)
		target = absolute
	} else {
		if err = os.MkdirAll(folder, 0755); err != nil {
			return err
		}
	}
	explorerMu.Lock()
	defer explorerMu.Unlock()
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	hr, _, _ := explorerOLE.NewProc("CoInitializeEx").Call(0, 2)
	if err = explorerHRESULT(hr); err != nil {
		return err
	}
	defer explorerOLE.NewProc("CoUninitialize").Call()
	original, _, _ := user32.NewProc("GetForegroundWindow").Call()
	windows, automationErr := explorerWindows()
	if automationErr == nil {
		defer windows.call(2)
	}
	if err = explorerNativeOpen(folder, target); err != nil {
		return err
	}
	if automationErr != nil {
		return nil
	} // Shell still opened the requested folder.
	deadline := time.Now().Add(2500 * time.Millisecond)
	for {
		matches := explorerMatchingWindows(windows, folder)
		foreground, _, _ := user32.NewProc("GetForegroundWindow").Call()
		for _, hwnd := range matches {
			if foreground == hwnd {
				return nil
			}
		}
		if len(matches) > 0 {
			// Do not steal focus if the user switched to an unrelated application while opening.
			if foreground != 0 && foreground != original {
				return nil
			}
			foregroundExplorer(matches[len(matches)-1])
			return nil
		}
		if time.Now().After(deadline) {
			return nil
		}
		time.Sleep(75 * time.Millisecond)
	}
}
