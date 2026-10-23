// Package iot provides diagnostic functions to probe local Windows hardware capabilities without spawning console subprocesses.
package iot

import (
	"net"
	"strings"
	"sync"
	"time"
)

var (
	diagCache HardwareSupportMatrix
	diagMu    sync.RWMutex
	diagOnce  sync.Once
)

// ProbeHardwareCapabilities returns fast cached hardware capabilities instantly without lag.
func ProbeHardwareCapabilities() HardwareSupportMatrix {
	diagOnce.Do(func() {
		refreshHardwareDiagnostics()
		go startHardwareDiagWorker()
	})

	diagMu.RLock()
	defer diagMu.RUnlock()
	return diagCache
}

func startHardwareDiagWorker() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		refreshHardwareDiagnostics()
	}
}

func refreshHardwareDiagnostics() {
	matrix := HardwareSupportMatrix{
		InternetModeEnabled: false, // Strictly OFF by default as requested
		LastDiagnostic:      time.Now(),
		NFCStatusReason:     "No NFC reader detected on this PC",
	}

	// 1. Probe Network Interfaces (Wi-Fi & LAN) via native net.Interfaces()
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
				matrix.WiFiSupported = true
				if isUp {
					matrix.WiFiActive = true
					matrix.WiFiAdapterName = iface.Name
				}
			} else if strings.Contains(nameLower, "ethernet") || strings.Contains(nameLower, "lan") || strings.Contains(nameLower, "local") {
				matrix.LANSupported = true
				if isUp {
					matrix.LANActive = true
					matrix.LANAdapterName = iface.Name
				}
			}
		}
	}

	// 2. Bluetooth & NFC Native Flags
	hwSummaryMu.RLock()
	hw := hwSummaryCache
	hwSummaryMu.RUnlock()
	matrix.BluetoothSupported = hw.BluetoothRadio != ""
	matrix.BluetoothActive = hw.BluetoothBLE
	matrix.BluetoothRadioName = hw.BluetoothRadio
	matrix.NFCSupported = hw.NFCSupported
	matrix.NFCActive = hw.NFCActive
	matrix.ScannersCount = len(hw.ScannerDevices)

	if matrix.NFCSupported {
		matrix.NFCStatusReason = hw.NFCReaderName
	}

	diagMu.Lock()
	diagCache = matrix
	diagMu.Unlock()
}
