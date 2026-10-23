// Package iot manages multi-protocol peripherals, connection state, and hardware actions.
package iot

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

type Manager struct {
	mu          sync.RWMutex
	support     HardwareSupportMatrix
	devices     map[string]*IoTDevice
	subscribers []func(event string, dev *IoTDevice)
	autoRefresh bool
	stopChan    chan struct{}
}

// NewManager initializes hardware diagnostics without registering demo devices.
func NewManager() *Manager {
	mgr := &Manager{
		devices:     make(map[string]*IoTDevice),
		subscribers: make([]func(string, *IoTDevice), 0),
		stopChan:    make(chan struct{}),
	}

	// 1. Initial Diagnostic Probe
	mgr.support = ProbeHardwareCapabilities()
	if dir, err := os.UserConfigDir(); err == nil {
		_ = LoadGatewayConfig(filepath.Join(dir, "NearMitra", "hardware.json"))
		_ = LoadRelaySchedules(filepath.Join(dir, "NearMitra", "relay-schedules.json"))
	}
	go func() {
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		for {
			select {
			case now := <-ticker.C:
				RunRelaySchedules(now)
			case <-mgr.stopChan:
				return
			}
		}
	}()

	// Device records and telemetry must come from configured hardware.

	return mgr
}

// GetSupportMatrix returns live hardware diagnostics.
func (m *Manager) GetSupportMatrix() HardwareSupportMatrix {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.support
}

// RefreshDiagnostics re-probes host PC hardware.
func (m *Manager) RefreshDiagnostics() HardwareSupportMatrix {
	mat := ProbeHardwareCapabilities()
	m.mu.Lock()
	m.support = mat
	m.mu.Unlock()
	return mat
}

// GetDevices returns all registered and discovered IoT devices.
func (m *Manager) GetDevices() []IoTDevice {
	m.mu.RLock()
	defer m.mu.RUnlock()
	list := make([]IoTDevice, 0, len(m.devices))
	for _, d := range m.devices {
		list = append(list, *d)
	}
	return list
}

// ToggleRelay switches power state of a relay/pump.
func (m *Manager) ToggleRelay(deviceID string) (bool, error) {
	return false, fmt.Errorf("no hardware relay transport configured for %s", deviceID)
}

// TriggerTestPrint executes a sample print job for receipt/dispatch printers.
func (m *Manager) TriggerTestPrint(printerID string) error {
	return fmt.Errorf("use a configured LAN printer for %s", printerID)
}

// TriggerScan starts document scanning.
func (m *Manager) TriggerScan(scannerID string) error {
	return fmt.Errorf("use Windows scanner for %s", scannerID)
}

// SetInternetMode toggles WAN connectivity.
func (m *Manager) SetInternetMode(enabled bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.support.InternetModeEnabled = enabled
}

// Close stops background routines.
func (m *Manager) Close() {
	close(m.stopChan)
}
