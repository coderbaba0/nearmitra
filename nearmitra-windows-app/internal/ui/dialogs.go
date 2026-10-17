// Package ui provides modern native Win32 controls, dialogs, and graphics rendering for NearMitra.
package ui

import (
	"fmt"
	"os/exec"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"unicode/utf16"
	"unsafe"
)

var pickerMu sync.Mutex

var (
	comdlg32         = syscall.NewLazyDLL("comdlg32.dll")
	pGetOpenFileName = comdlg32.NewProc("GetOpenFileNameW")
	pGetSaveFileName = comdlg32.NewProc("GetSaveFileNameW")
	pShellExecute    = shell32.NewProc("ShellExecuteW")

	pGlobalAlloc  = kernel32.NewProc("GlobalAlloc")
	pGlobalLock   = kernel32.NewProc("GlobalLock")
	pGlobalUnlock = kernel32.NewProc("GlobalUnlock")
)

type OPENFILENAME struct {
	StructSize    uint32
	HwndOwner     uintptr
	HInstance     uintptr
	Filter        *uint16
	CustomFilter  *uint16
	MaxCustFilter uint32
	FilterIndex   uint32
	File          *uint16
	MaxFile       uint32
	FileTitle     *uint16
	MaxFileTitle  uint32
	InitialDir    *uint16
	Title         *uint16
	Flags         uint32
	FileOffset    uint16
	FileExtension uint16
	DefExt        *uint16
	CustData      uintptr
	FnHook        uintptr
	TemplateName  *uint16
	PvReserved    unsafe.Pointer
	DwReserved    uint32
	FlagsEx       uint32
}

const (
	OFN_FILEMUSTEXIST    = 0x00001000
	OFN_PATHMUSTEXIST    = 0x00000800
	OFN_EXPLORER         = 0x00080000
	OFN_NOCHANGEDIR      = 0x00000008
	OFN_ALLOWMULTISELECT = 0x00000200
)

// OpenFileDialog prompts user to choose a file and returns its absolute path.
func OpenFileDialog(hwnd uintptr, title string) (string, error) {
	pickerMu.Lock()
	defer pickerMu.Unlock()
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	if hwnd == 0 {
		hwnd, _, _ = user32.NewProc("GetForegroundWindow").Call()
	}
	var ofn OPENFILENAME
	var buf [32768]uint16
	filter := utf16.Encode([]rune("All Files (*.*)\x00*.*\x00Documents & Media\x00*.png;*.jpg;*.jpeg;*.mp4;*.zip;*.pdf;*.apk;*.exe;*.docx;*.txt\x00\x00"))

	ofn.StructSize = uint32(unsafe.Sizeof(ofn))
	ofn.HwndOwner = hwnd
	ofn.Filter = &filter[0]
	ofn.File = &buf[0]
	ofn.MaxFile = uint32(len(buf))
	ofn.Title = UTF16Ptr(title)
	ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_EXPLORER | OFN_NOCHANGEDIR

	r, _, _ := pGetOpenFileName.Call(uintptr(unsafe.Pointer(&ofn)))
	if r == 0 {
		code, _, _ := comdlg32.NewProc("CommDlgExtendedError").Call()
		if code != 0 {
			return "", fmt.Errorf("file picker failed (0x%x)", code)
		}
		return "", nil
	}
	return syscall.UTF16ToString(buf[:]), nil
}

// OpenFolderInExplorer opens the target folder and activates its matching Explorer window.
func OpenFolderInExplorer(folderPath string) error { return openExplorerPath(folderPath, false) }

// OpenFileInExplorer selects the target item in its parent Explorer folder.
func OpenFileInExplorer(filePath string) error { return openExplorerPath(filePath, true) }

// CopyToClipboard copies a UTF-8 string into Windows Clipboard.
func CopyToClipboard(hwnd uintptr, text string) bool {
	if text == "" {
		return false
	}
	u16, err := syscall.UTF16FromString(text)
	if err != nil {
		return false
	}

	pOpenClipboard.Call(hwnd)
	defer pCloseClipboard.Call()
	pEmptyClipboard.Call()

	bytesLen := uintptr(len(u16) * 2)
	hMem, _, _ := pGlobalAlloc.Call(GMEM_MOVEABLE, bytesLen)
	if hMem == 0 {
		return false
	}

	ptr, _, _ := pGlobalLock.Call(hMem)
	if ptr != 0 {
		pRtlMoveMemory := kernel32.NewProc("RtlMoveMemory")
		pRtlMoveMemory.Call(ptr, uintptr(unsafe.Pointer(&u16[0])), bytesLen)
		pGlobalUnlock.Call(hMem)
		pSetClipboardData.Call(CF_UNICODETEXT, hMem)
		return true
	}
	return false
}

// folderPickerScript attaches the folder browser to the initiating app window.
// An explicit owner keeps the picker above Edge/Chrome's standalone window.
func folderPickerScript(owner uintptr, currentPath string) string {
	pathLiteral := "'" + strings.ReplaceAll(currentPath, "'", "''") + "'"
	return fmt.Sprintf(`$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$owner = New-Object System.Windows.Forms.NativeWindow
$owner.AssignHandle([IntPtr]%d)
$f = New-Object System.Windows.Forms.FolderBrowserDialog
$f.Description = 'Select a folder - NearMitra'
$f.SelectedPath = %s
$f.ShowNewFolderButton = $true
try {
 if ($f.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {
  [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
  [Console]::Write($f.SelectedPath)
 }
} finally { $f.Dispose(); $owner.ReleaseHandle() }`, owner, pathLiteral)
}

// SelectFolderDialog preserves the starting directory and owns its modal picker.
func SelectFolderDialog(currentPath string) (string, error) {
	pickerMu.Lock()
	defer pickerMu.Unlock()
	owner, _, _ := user32.NewProc("GetForegroundWindow").Call()
	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-STA", "-WindowStyle", "Hidden", "-Command", folderPickerScript(owner, currentPath))
	cmd.SysProcAttr = &syscall.SysProcAttr{
		HideWindow:    true,
		CreationFlags: 0x08000000,
	}
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}
