package ui

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"unsafe"
)

func TestExplorerLocationMatchesDecodedFullPath(t *testing.T) {
	for _, test := range []struct{ location, path string }{
		{"file:///C:/Users/O%27Brien/Report%20Files", `C:\Users\O'Brien\Report Files`},
		{"file://server/share/Reports%20New", `\\server\share\Reports New`},
		{"file:///H:/Docs/%E0%A4%A8%E0%A4%AF%E0%A4%BE", `H:\Docs\नया`},
	} {
		got, err := explorerFolderFromURL(test.location)
		if err != nil || !strings.EqualFold(got, test.path) {
			t.Fatalf("%s: %q %v", test.location, got, err)
		}
	}
	if _, err := explorerFolderFromURL("https://example.com/Reports"); err == nil {
		t.Fatal("non-filesystem window accepted")
	}
}
func TestExplorerRejectsMissingItemBeforeOpening(t *testing.T) {
	if err := OpenFileInExplorer(filepath.Join(t.TempDir(), "missing.pdf")); err == nil {
		t.Fatal("missing item accepted")
	}
	if err := OpenFolderInExplorer(""); err == nil {
		t.Fatal("empty folder accepted")
	}
}
func TestExplorerAutomationABI(t *testing.T) {
	if unsafe.Sizeof(explorerVariant{}) != 24 || unsafe.Sizeof(explorerParams{}) != 24 {
		t.Fatal("incorrect x64 Automation layout")
	}
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	hr, _, _ := explorerOLE.NewProc("CoInitializeEx").Call(0, 2)
	if err := explorerHRESULT(hr); err != nil {
		t.Fatal(err)
	}
	defer explorerOLE.NewProc("CoUninitialize").Call()
	windows, err := explorerWindows()
	if err != nil {
		t.Fatal(err)
	}
	defer windows.call(2)
	count, err := windows.property("Count")
	if err != nil {
		t.Fatal(err)
	}
	defer count.clear()
	if count.Kind != 3 {
		t.Fatalf("unexpected Count variant: %d", count.Kind)
	}
}

// Opt-in interactive test opens only a new temporary folder and closes its own window.
func TestExplorerForegroundInteractive(t *testing.T) {
	if os.Getenv("NEARMITRA_EXPLORER_TEST") != "1" {
		t.Skip("interactive desktop test")
	}
	folder := filepath.Join(t.TempDir(), "O'Brien नया Reports")
	if err := os.MkdirAll(folder, 0755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(folder, "report file.txt")
	os.WriteFile(path, []byte("Explorer integration test"), 0600)
	if err := OpenFolderInExplorer(folder); err != nil {
		t.Fatal(err)
	}
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	// Put a different app-style window in front of the already-open Explorer.
	cover, _, createErr := user32.NewProc("CreateWindowExW").Call(0, uintptr(unsafe.Pointer(UTF16Ptr("STATIC"))), uintptr(unsafe.Pointer(UTF16Ptr("NearMitra Explorer focus test"))), 0x00cf0000, 80, 80, 400, 240, 0, 0, 0, 0)
	if cover == 0 {
		t.Fatal(createErr)
	}
	defer user32.NewProc("DestroyWindow").Call(cover)
	user32.NewProc("ShowWindow").Call(cover, 5)
	user32.NewProc("SetForegroundWindow").Call(cover)
	active, _, _ := user32.NewProc("GetForegroundWindow").Call()
	if active != cover {
		t.Fatal("Could not arrange the existing-window-behind-app test")
	}
	if err := OpenFileInExplorer(path); err != nil {
		t.Fatal(err)
	}
	hr, _, _ := explorerOLE.NewProc("CoInitializeEx").Call(0, 2)
	if err := explorerHRESULT(hr); err != nil {
		t.Fatal(err)
	}
	defer explorerOLE.NewProc("CoUninitialize").Call()
	windows, err := explorerWindows()
	if err != nil {
		t.Fatal(err)
	}
	defer windows.call(2)
	matches := explorerMatchingWindows(windows, folder)
	if len(matches) == 0 {
		t.Fatal("target Explorer folder could not be located")
	}
	defer func() {
		for _, hwnd := range matches {
			user32.NewProc("PostMessageW").Call(hwnd, 0x10, 0, 0)
		}
	}()
	foreground, _, _ := user32.NewProc("GetForegroundWindow").Call()
	for _, hwnd := range matches {
		if hwnd == foreground {
			t.Log("Exact target Explorer window is foreground")
			return
		}
	}
	t.Fatalf("Explorer opened, but Windows did not grant foreground activation; foreground=%x matched=%v", foreground, matches)
}
