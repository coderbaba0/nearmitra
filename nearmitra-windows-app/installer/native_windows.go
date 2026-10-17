package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

func hiddenCommand(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s: %s (%w)", name, strings.TrimSpace(string(output)), err)
	}
	return nil
}
func knownFolder(id uintptr) (string, error) {
	var path [260]uint16
	hr, _, _ := shell32.NewProc("SHGetFolderPathW").Call(0, id, 0, 0, uintptr(unsafe.Pointer(&path[0])))
	if int32(uint32(hr)) < 0 {
		return "", fmt.Errorf("Windows user folder unavailable (0x%x)", hr)
	}
	return syscall.UTF16ToString(path[:]), nil
}

type setupGUID struct {
	A    uint32
	B, C uint16
	D    [8]byte
}
type setupCOM struct{ table *[24]uintptr }

func (o *setupCOM) call(index int, args ...uintptr) uintptr {
	r, _, _ := syscall.SyscallN(o.table[index], append([]uintptr{uintptr(unsafe.Pointer(o))}, args...)...)
	return r
}
func checkSetupCOM(hr uintptr) error {
	if int32(uint32(hr)) < 0 {
		return fmt.Errorf("Windows shell operation failed (0x%08x)", uint32(hr))
	}
	return nil
}
func createShortcut(path, exe, dir, icon string) error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	ole := syscall.NewLazyDLL("ole32.dll")
	hr, _, _ := ole.NewProc("CoInitializeEx").Call(0, 2)
	if err := checkSetupCOM(hr); err != nil {
		return err
	}
	defer ole.NewProc("CoUninitialize").Call()
	cls := setupGUID{0x00021401, 0, 0, [8]byte{0xc0, 0, 0, 0, 0, 0, 0, 0x46}}
	iid := setupGUID{0x000214f9, 0, 0, [8]byte{0xc0, 0, 0, 0, 0, 0, 0, 0x46}}
	persistIID := setupGUID{0x0000010b, 0, 0, [8]byte{0xc0, 0, 0, 0, 0, 0, 0, 0x46}}
	var link *setupCOM
	hr, _, _ = ole.NewProc("CoCreateInstance").Call(uintptr(unsafe.Pointer(&cls)), 0, 1, uintptr(unsafe.Pointer(&iid)), uintptr(unsafe.Pointer(&link)))
	if err := checkSetupCOM(hr); err != nil {
		return err
	}
	defer link.call(2)
	for _, item := range []struct {
		method int
		value  string
	}{{20, exe}, {9, dir}, {7, "NearMitra - Nearby chat, calls and sharing"}} {
		if err := checkSetupCOM(link.call(item.method, uintptr(unsafe.Pointer(UTF16Ptr(item.value))))); err != nil {
			return err
		}
	}
	if err := checkSetupCOM(link.call(17, uintptr(unsafe.Pointer(UTF16Ptr(icon))), 0)); err != nil {
		return err
	}
	var persist *setupCOM
	if err := checkSetupCOM(link.call(0, uintptr(unsafe.Pointer(&persistIID)), uintptr(unsafe.Pointer(&persist)))); err != nil {
		return err
	}
	defer persist.call(2)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	return checkSetupCOM(persist.call(6, uintptr(unsafe.Pointer(UTF16Ptr(path))), 1))
}
func startupValue(exe string) string { return `"` + exe + `" --minimized` }
func registerInstallation(dir string, options InstallOptions) error {
	exe := filepath.Join(dir, "NearMitra.exe")
	icon := filepath.Join(dir, "nearmitra.ico")
	for _, item := range []struct {
		id      uintptr
		enabled bool
	}{{0x10, options.DesktopShortcut}, {0x2, options.StartMenu}} {
		folder, err := knownFolder(item.id)
		if err != nil {
			return err
		}
		path := filepath.Join(folder, "NearMitra.lnk")
		if item.enabled {
			if err = createShortcut(path, exe, dir, icon); err != nil {
				return err
			}
		} else {
			_ = os.Remove(path)
		}
	}
	key := `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\NearMitra`
	props := map[string]string{"DisplayName": AppName, "DisplayVersion": AppVersion, "Publisher": Publisher, "DisplayIcon": icon, "InstallLocation": dir, "UninstallString": `"` + filepath.Join(dir, "Uninstall.exe") + `" --uninstall`}
	for name, value := range props {
		if err := hiddenCommand("reg.exe", "add", key, "/v", name, "/t", "REG_SZ", "/d", value, "/f"); err != nil {
			return err
		}
	}
	installedBytes := int64(len(appBinary) + len(appIcon))
	if info, err := os.Stat(filepath.Join(dir, "Uninstall.exe")); err == nil {
		installedBytes += info.Size()
	}
	for name, value := range map[string]string{"NoModify": "1", "NoRepair": "1", "EstimatedSize": fmt.Sprint(installedBytes / 1024)} {
		if err := hiddenCommand("reg.exe", "add", key, "/v", name, "/t", "REG_DWORD", "/d", value, "/f"); err != nil {
			return err
		}
	}
	run := `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
	if options.Autostart {
		return hiddenCommand("reg.exe", "add", run, "/v", "NearMitra", "/t", "REG_SZ", "/d", startupValue(exe), "/f")
	}
	// Deleting an absent startup value is harmless, but do not hide other failures.
	query := exec.Command("reg.exe", "query", run, "/v", "NearMitra")
	query.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	if query.Run() == nil {
		return hiddenCommand("reg.exe", "delete", run, "/v", "NearMitra", "/f")
	}
	return nil
}

type setupProcessEntry struct {
	Size, Usage, PID             uint32
	Heap                         uintptr
	ModuleID, Threads, ParentPID uint32
	Priority                     int32
	Flags                        uint32
	Exe                          [260]uint16
}

func stopInstalledApps() error {
	snap, _, err := kernel32.NewProc("CreateToolhelp32Snapshot").Call(2, 0)
	if snap == ^uintptr(0) {
		return err
	}
	defer kernel32.NewProc("CloseHandle").Call(snap)
	var entry setupProcessEntry
	entry.Size = uint32(unsafe.Sizeof(entry))
	more, _, _ := kernel32.NewProc("Process32FirstW").Call(snap, uintptr(unsafe.Pointer(&entry)))
	for more != 0 {
		name := strings.ToLower(syscall.UTF16ToString(entry.Exe[:]))
		if name == "nearmitra.exe" || name == "nearmitra-windows-app.exe" {
			process, _, _ := kernel32.NewProc("OpenProcess").Call(0x100001, 0, uintptr(entry.PID))
			if process != 0 {
				stopped, _, stopErr := kernel32.NewProc("TerminateProcess").Call(process, 0)
				if stopped == 0 {
					kernel32.NewProc("CloseHandle").Call(process)
					return fmt.Errorf("Close the running NearMitra app and retry: %w", stopErr)
				}
				kernel32.NewProc("WaitForSingleObject").Call(process, 5000)
				kernel32.NewProc("CloseHandle").Call(process)
			}
		}
		more, _, _ = kernel32.NewProc("Process32NextW").Call(snap, uintptr(unsafe.Pointer(&entry)))
	}
	return nil
}

type setupShellExecuteInfo struct {
	Size                              uint32
	Mask                              uint32
	Window                            uintptr
	Verb, File, Parameters, Directory *uint16
	Show                              int32
	Instance                          uintptr
	IDList                            uintptr
	Class                             *uint16
	ClassKey                          uintptr
	HotKey                            uint32
	Icon                              uintptr
	Process                           uintptr
}

func configurePrivateNetwork(dir string) error {
	self, err := os.Executable()
	if err != nil {
		return err
	}
	args := syscall.EscapeArg("--configure-network") + " " + syscall.EscapeArg(filepath.Join(dir, "NearMitra.exe"))
	info := setupShellExecuteInfo{Mask: 0x40 | 0x100, Verb: UTF16Ptr("runas"), File: UTF16Ptr(self), Parameters: UTF16Ptr(args), Show: 0}
	info.Size = uint32(unsafe.Sizeof(info))
	ok, _, callErr := shell32.NewProc("ShellExecuteExW").Call(uintptr(unsafe.Pointer(&info)))
	if ok == 0 {
		if callErr == syscall.Errno(1223) {
			return fmt.Errorf("Windows administrator approval was cancelled")
		}
		return callErr
	}
	defer kernel32.NewProc("CloseHandle").Call(info.Process)
	wait, _, _ := kernel32.NewProc("WaitForSingleObject").Call(info.Process, 120000)
	if wait != 0 {
		return fmt.Errorf("Network setup is still pending; allow NearMitra in Windows Firewall later")
	}
	var code uint32
	kernel32.NewProc("GetExitCodeProcess").Call(info.Process, uintptr(unsafe.Pointer(&code)))
	if code != 0 {
		return fmt.Errorf("Windows firewall setup returned %d", code)
	}
	return nil
}
func firewallRuleArguments(exe, protocol string) []string {
	return []string{"advfirewall", "firewall", "add", "rule", "name=NearMitra.Private." + protocol, "dir=in", "action=allow", "program=" + exe, "protocol=" + protocol, "profile=private", "remoteip=localsubnet", "enable=yes"}
}
func setupPrivateFirewall(exe string) error {
	if !filepath.IsAbs(exe) || !strings.EqualFold(filepath.Base(exe), "NearMitra.exe") {
		return fmt.Errorf("Invalid NearMitra executable path")
	}
	if _, err := os.Stat(exe); err != nil {
		return err
	}
	for _, protocol := range []string{"TCP", "UDP"} {
		// Native Windows utility; confined to this executable, private profile and LAN.
		_ = hiddenCommand("netsh.exe", "advfirewall", "firewall", "delete", "rule", "name=NearMitra.Private."+protocol, "program="+exe)
		if err := hiddenCommand("netsh.exe", firewallRuleArguments(exe, protocol)...); err != nil {
			return err
		}
	}
	return nil
}
func messageBox(text, title string, flags uintptr) uintptr {
	r, _, _ := user32.NewProc("MessageBoxW").Call(0, uintptr(unsafe.Pointer(UTF16Ptr(text))), uintptr(unsafe.Pointer(UTF16Ptr(title))), flags)
	return r
}
func handleMaintenanceCommand() bool {
	if len(os.Args) < 2 {
		return false
	}
	switch os.Args[1] {
	case "--configure-network":
		if len(os.Args) != 3 {
			os.Exit(2)
		}
		if err := setupPrivateFirewall(os.Args[2]); err != nil {
			messageBox(err.Error(), "NearMitra network setup", 0x10)
			os.Exit(1)
		}
		return true
	case "--uninstall":
		if messageBox("Uninstall NearMitra Desktop? Your saved chats and received files will be kept.", "NearMitra", 0x24) != 6 {
			return true
		}
		self, err := os.Executable()
		if err != nil {
			return true
		}
		dir := filepath.Dir(self)
		temp, err := os.MkdirTemp("", "NearMitra-Uninstall-")
		if err != nil {
			return true
		}
		data, err := os.ReadFile(self)
		if err != nil {
			return true
		}
		worker := filepath.Join(temp, "Uninstall.exe")
		if os.WriteFile(worker, data, 0600) != nil {
			return true
		}
		cmd := exec.Command(worker, "--uninstall-worker", dir)
		cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
		if err = cmd.Start(); err != nil {
			messageBox(err.Error(), "NearMitra uninstall", 0x10)
		}
		return true
	case "--uninstall-worker":
		if len(os.Args) != 3 {
			return true
		}
		dir := filepath.Clean(os.Args[2])
		if !filepath.IsAbs(dir) || !strings.EqualFold(filepath.Base(dir), "NearMitra") {
			return true
		}
		_ = stopInstalledApps()
		time.Sleep(800 * time.Millisecond)
		for _, id := range []uintptr{0x10, 0x2} {
			if folder, err := knownFolder(id); err == nil {
				_ = os.Remove(filepath.Join(folder, "NearMitra.lnk"))
			}
		}
		_ = hiddenCommand("reg.exe", "delete", `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, "/v", "NearMitra", "/f")
		_ = hiddenCommand("reg.exe", "delete", `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\NearMitra`, "/f")
		if err := os.RemoveAll(dir); err != nil {
			messageBox("Some application files could not be removed. Close NearMitra and remove the installation folder.", "NearMitra uninstall", 0x30)
		} else {
			messageBox("NearMitra was uninstalled. Your chats and received files were kept.", "NearMitra", 0x40)
		}
		return true
	}
	return false
}
