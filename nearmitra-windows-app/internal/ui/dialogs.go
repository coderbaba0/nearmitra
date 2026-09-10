// Package ui provides modern native Win32 controls, dialogs, and graphics rendering for NearMitra.
package ui

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

var (
	comdlg32         = syscall.NewLazyDLL("comdlg32.dll")
	pGetOpenFileName = comdlg32.NewProc("GetOpenFileNameW")
	pGetSaveFileName = comdlg32.NewProc("GetSaveFileNameW")
	pShellExecute    = shell32.NewProc("ShellExecuteW")

	pGlobalAlloc = kernel32.NewProc("GlobalAlloc")
	pGlobalLock  = kernel32.NewProc("GlobalLock")
	pGlobalUnlock = kernel32.NewProc("GlobalUnlock")
)

type OPENFILENAME struct {
	StructSize      uint32
	HwndOwner       uintptr
	HInstance       uintptr
	Filter          *uint16
	CustomFilter    *uint16
	MaxCustFilter   uint32
	FilterIndex     uint32
	File            *uint16
	MaxFile         uint32
	FileTitle       *uint16
	MaxFileTitle    uint32
	InitialDir      *uint16
	Title           *uint16
	Flags           uint32
	FileOffset      uint16
	FileExtension   uint16
	DefExt          *uint16
	CustData        uintptr
	FnHook          uintptr
	TemplateName    *uint16
	PvReserved      unsafe.Pointer
	DwReserved      uint32
	FlagsEx         uint32
}

const (
	OFN_FILEMUSTEXIST = 0x00001000
	OFN_PATHMUSTEXIST = 0x00000800
	OFN_EXPLORER      = 0x00080000
	OFN_NOCHANGEDIR   = 0x00000008
	OFN_ALLOWMULTISELECT = 0x00000200
)

// OpenFileDialog prompts user to choose a file and returns its absolute path.
func OpenFileDialog(hwnd uintptr, title string) (string, error) {
	var ofn OPENFILENAME
	var buf [1024]uint16
	filter := UTF16Ptr("All Files (*.*)\x00*.*\x00Documents & Media\x00*.png;*.jpg;*.jpeg;*.mp4;*.zip;*.pdf;*.apk;*.exe;*.docx;*.txt\x00\x00")

	ofn.StructSize = uint32(unsafe.Sizeof(ofn))
	ofn.HwndOwner = hwnd
	ofn.Filter = filter
	ofn.File = &buf[0]
	ofn.MaxFile = uint32(len(buf))
	ofn.Title = UTF16Ptr(title)
	ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_EXPLORER | OFN_NOCHANGEDIR

	r, _, _ := pGetOpenFileName.Call(uintptr(unsafe.Pointer(&ofn)))
	if r == 0 {
		return "", nil
	}
	return syscall.UTF16ToString(buf[:]), nil
}

// OpenFolderInExplorer opens Windows Explorer displaying target folder in the foreground.
func OpenFolderInExplorer(folderPath string) {
	if folderPath == "" {
		return
	}
	_ = os.MkdirAll(folderPath, 0755)
	absPath, err := filepath.Abs(folderPath)
	if err == nil {
		folderPath = absPath
	}
	// Using explorer.exe directly makes Windows Explorer open as an active foreground window
	cmd := exec.Command("explorer.exe", folderPath)
	_ = cmd.Start()
}

// OpenFileInExplorer highlights a specific file in Windows Explorer in the foreground.
func OpenFileInExplorer(filePath string) {
	if filePath == "" {
		return
	}
	absPath, err := filepath.Abs(filePath)
	if err == nil {
		filePath = absPath
	}
	cmd := exec.Command("explorer.exe", "/select,"+filePath)
	_ = cmd.Start()
}

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

// SelectFolderDialog prompts folder selection via PowerShell folder browser if needed.
func SelectFolderDialog(currentPath string) (string, error) {
	psScript := `Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.FolderBrowserDialog; if ($f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $f.SelectedPath }`
	cmd := exec.Command("powershell", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", psScript)
	cmd.SysProcAttr = &syscall.SysProcAttr{
		HideWindow:    true,
		CreationFlags: 0x08000000, // CREATE_NO_WINDOW
	}
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}
