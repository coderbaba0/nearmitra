// Package iot provides real Windows-level hardware scanning for USB, Audio, Camera, NFC, and Serial ports.
package iot

import (
	"bytes"
	"context"
	"encoding/json"
	"net"
	"os/exec"
	"strings"
	"sync"
	"syscall"
	"time"
)

// WindowsPnPItem represents an item returned by Windows Get-PnpDevice.
type WindowsPnPItem struct {
	FriendlyName string `json:"FriendlyName"`
	Class        string `json:"Class"`
	Status       string `json:"Status"`
	InstanceId   string `json:"InstanceId"`
}

// SystemHardwareSummary represents the real live state of host PC hardware.
type SystemHardwareSummary struct {
	LastScanned       time.Time        `json:"last_scanned"`
	ScanError         string           `json:"scan_error,omitempty"`
	WiFiOnline        bool             `json:"wifi_online"`
	WiFiAdapter       string           `json:"wifi_adapter"`
	IsScanning        bool             `json:"is_scanning"`
	WiFiDirect        bool             `json:"wifi_direct"`
	BluetoothBLE      bool             `json:"bluetooth_ble"`
	BluetoothRadio    string           `json:"bluetooth_radio"`
	LANOnline         bool             `json:"lan_online"`
	LANAdapter        string           `json:"lan_adapter"`
	NFCSupported      bool             `json:"nfc_supported"`
	NFCActive         bool             `json:"nfc_active"`
	NFCReaderName     string           `json:"nfc_reader_name"`
	HasBuiltinSpeaker bool             `json:"has_builtin_speaker"`
	HasBuiltinMic     bool             `json:"has_builtin_mic"`
	HasBuiltinCam     bool             `json:"has_builtin_cam"`
	USBDevices        []DiscoveredItem `json:"usb_devices"`
	AudioDevices      []DiscoveredItem `json:"audio_devices"`
	CameraDevices     []DiscoveredItem `json:"camera_devices"`
	ScannerDevices    []DiscoveredItem `json:"scanner_devices"`
	NFCDevices        []DiscoveredItem `json:"nfc_devices"`
	SerialCOMPorts    []DiscoveredItem `json:"serial_com_ports"`
}

// DiscoveredItem represents a single detected physical or virtual hardware device.
type DiscoveredItem struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Category    string `json:"category"` // "usb", "audio_out", "audio_in", "camera", "scanner", "nfc", "serial"
	PortOrBus   string `json:"port_or_bus"`
	Status      string `json:"status"` // "OK", "Ready", "Offline", "Error"
	IsVirtual   bool   `json:"is_virtual"`
	Description string `json:"description"`
}

var (
	hwSummaryCache SystemHardwareSummary
	hwSummaryMu    sync.RWMutex
	hwScanMu       sync.Mutex
)

// GetSystemHardwareSummary returns the cached hardware diagnostic summary.
func GetSystemHardwareSummary() SystemHardwareSummary {
	hwSummaryMu.RLock()
	defer hwSummaryMu.RUnlock()
	if hwSummaryCache.LastScanned.IsZero() {
		hwSummaryMu.RUnlock()
		summary := ScanRealWindowsHardware()
		hwSummaryMu.RLock()
		return summary
	}
	return hwSummaryCache
}

// ScanRealWindowsHardware performs real Windows PnP and interface discovery.
func ScanRealWindowsHardware() SystemHardwareSummary {
	if !hwScanMu.TryLock() {
		hwSummaryMu.RLock()
		cached := hwSummaryCache
		hwSummaryMu.RUnlock()
		cached.IsScanning = true
		return cached
	}
	defer hwScanMu.Unlock()

	summary := SystemHardwareSummary{
		LastScanned:    time.Now(),
		USBDevices:     make([]DiscoveredItem, 0),
		AudioDevices:   make([]DiscoveredItem, 0),
		CameraDevices:  make([]DiscoveredItem, 0),
		ScannerDevices: make([]DiscoveredItem, 0),
		NFCDevices:     make([]DiscoveredItem, 0),
		SerialCOMPorts: make([]DiscoveredItem, 0),
	}

	// 1. Native Network Interface Scan (Wi-Fi, LAN, Virtual Adapters)
	ifaces, err := net.Interfaces()
	if err == nil {
		for _, iface := range ifaces {
			nameLower := strings.ToLower(iface.Name)
			isUp := (iface.Flags & net.FlagUp) != 0
			isLoopback := (iface.Flags & net.FlagLoopback) != 0

			if isLoopback {
				continue
			}

			if strings.Contains(nameLower, "wi-fi") || strings.Contains(nameLower, "wireless") || strings.Contains(nameLower, "wlan") {
				summary.WiFiOnline = summary.WiFiOnline || isUp
				summary.WiFiAdapter = iface.Name
			} else if strings.Contains(nameLower, "ethernet") || strings.Contains(nameLower, "lan") {
				if isUp {
					summary.LANOnline = true
					summary.LANAdapter = iface.Name
				}
			}
		}
	}

	// 2. Real Windows PnP Hardware Query via PowerShell
	psScript := `$ErrorActionPreference = 'Stop'; [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(); Get-PnpDevice -PresentOnly | Where-Object { 'USB','AudioEndpoint','Camera','Image','SmartCardReader','Bluetooth','Ports','Media' -contains $_.Class } | Select-Object FriendlyName, Class, Status, InstanceId | ConvertTo-Json`

	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
	defer cancel()
	output, err := executeHardwareQuery(ctx, psScript)
	if err != nil {
		summary.ScanError = "Windows hardware query failed: " + err.Error()
		if ctx.Err() != nil {
			summary.ScanError = "Windows hardware query timed out. Try scanning again."
		}
	} else if len(output) > 0 {
		var pnpItems []WindowsPnPItem
		trimOut := strings.TrimSpace(string(output))
		if strings.HasPrefix(trimOut, "[") {
			if err := json.Unmarshal([]byte(trimOut), &pnpItems); err != nil {
				summary.ScanError = "Windows hardware query returned invalid data"
			}
		} else if strings.HasPrefix(trimOut, "{") {
			var single WindowsPnPItem
			if err := json.Unmarshal([]byte(trimOut), &single); err == nil {
				pnpItems = append(pnpItems, single)
			} else {
				summary.ScanError = "Windows hardware query returned invalid data"
			}
		} else if trimOut != "null" {
			summary.ScanError = "Windows hardware query returned invalid data"
		}

		for _, item := range pnpItems {
			name := strings.TrimSpace(item.FriendlyName)
			if name == "" {
				continue
			}

			cls := strings.ToUpper(item.Class)
			stat := item.Status
			if stat == "" {
				stat = "Unknown"
			}

			disc := DiscoveredItem{
				ID:        item.InstanceId,
				Name:      name,
				PortOrBus: cls,
				Status:    stat,
			}

			switch cls {
			case "USB":
				disc.Category = "usb"
				disc.Description = "Physical USB Controller / Peripheral Bus"
				summary.USBDevices = append(summary.USBDevices, disc)

			case "AUDIOENDPOINT", "MEDIA":
				disc.Category = "audio"
				nameLow := strings.ToLower(name)
				if strings.Contains(nameLow, "mic") || strings.Contains(nameLow, "input") || strings.Contains(nameLow, "capture") {
					disc.Category = "audio_in"
					disc.Description = "Microphone / Audio Capture Input"
					summary.HasBuiltinMic = summary.HasBuiltinMic || stat == "OK"
				} else {
					disc.Category = "audio_out"
					disc.Description = "Audio Speaker / Headphone Output"
					summary.HasBuiltinSpeaker = summary.HasBuiltinSpeaker || stat == "OK"
				}
				if strings.Contains(nameLow, "virtual") {
					disc.IsVirtual = true
				}
				summary.AudioDevices = append(summary.AudioDevices, disc)

			case "CAMERA":
				disc.Category = "camera"
				disc.Description = "Video Camera / DirectShow Imaging Lens"
				summary.HasBuiltinCam = summary.HasBuiltinCam || stat == "OK"
				summary.CameraDevices = append(summary.CameraDevices, disc)

			case "IMAGE":
				disc.Category = "scanner"
				disc.Description = "WIA / TWAIN Document Scanner"
				summary.ScannerDevices = append(summary.ScannerDevices, disc)

			case "SMARTCARDREADER":
				disc.Category = "nfc"
				disc.Description = "NFC Proximity / SmartCard Reader Interface"
				summary.NFCSupported = true
				summary.NFCActive = summary.NFCActive || stat == "OK"
				summary.NFCReaderName = name
				summary.NFCDevices = append(summary.NFCDevices, disc)

			case "BLUETOOTH":
				summary.BluetoothBLE = summary.BluetoothBLE || stat == "OK"
				summary.BluetoothRadio = name

			case "PORTS":
				disc.Category = "serial"
				disc.Description = "Serial COM Port (ESP32 / Arduino / USB Relay)"
				summary.SerialCOMPorts = append(summary.SerialCOMPorts, disc)
			}
		}
	}

	hwSummaryMu.Lock()
	hwSummaryCache = summary
	hwSummaryMu.Unlock()

	return summary
}

var executeHardwareQuery = func(ctx context.Context, script string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, "powershell", "-NoProfile", "-NonInteractive", "-Command", script)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	var output bytes.Buffer
	cmd.Stdout = &output
	err := cmd.Run()
	return output.Bytes(), err
}
