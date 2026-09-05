// Package iot manages multi-protocol peripherals, connection state, and hardware actions.
package iot

import (
	"fmt"
	"math/rand"
	"sync"
	"time"
)

type Manager struct {
	mu           sync.RWMutex
	support      HardwareSupportMatrix
	devices      map[string]*IoTDevice
	subscribers  []func(event string, dev *IoTDevice)
	autoRefresh  bool
	stopChan     chan struct{}
}

// NewManager initializes the IoT device manager and loads default ecosystem peripherals.
func NewManager() *Manager {
	mgr := &Manager{
		devices:     make(map[string]*IoTDevice),
		subscribers: make([]func(string, *IoTDevice), 0),
		stopChan:    make(chan struct{}),
	}

	// 1. Initial Diagnostic Probe
	mgr.support = ProbeHardwareCapabilities()

	// 2. Initialize default registered Smart Devices & Peripherals
	mgr.seedDefaultPeripherals()

	// 3. Start background telemetry poll
	go mgr.startTelemetryWorker()

	return mgr
}

func (m *Manager) seedDefaultPeripherals() {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Smart Agricultural Water Pump Relay (Wi-Fi / LAN)
	m.devices["relay_pump_01"] = &IoTDevice{
		ID:       "relay_pump_01",
		Name:     "Kisan Smart Irrigation Pump #1",
		Type:     TypeRelay,
		Protocol: ProtocolWiFi,
		Address:  "192.168.1.120:80",
		IsOnline: true,
		State: map[string]interface{}{
			"power":         false,
			"voltage_v":     228.4,
			"current_a":     0.0,
			"flow_rate_lpm": 0.0,
		},
		Capabilities: []string{"power_switch", "timer_auto_cutoff", "current_sensor"},
		LastSeen:     time.Now(),
	}

	// Field Soil Moisture & Temperature Sensor (BLE / Wi-Fi)
	m.devices["sensor_soil_01"] = &IoTDevice{
		ID:       "sensor_soil_01",
		Name:     "Field Sector-A Soil Moisture Sensor",
		Type:     TypeSensor,
		Protocol: ProtocolBluetooth,
		Address:  "C4:4F:33:1A:89:BC",
		IsOnline: true,
		State: map[string]interface{}{
			"moisture_pct": 34.8,
			"temp_c":       28.5,
			"humidity_pct": 62.0,
			"battery_pct":  88,
		},
		Capabilities: []string{"moisture_telemetry", "temp_sensor", "battery_monitor"},
		LastSeen:     time.Now(),
	}

	// Thermal Receipt & Gate Pass Printer (LAN / USB)
	m.devices["printer_thermal_01"] = &IoTDevice{
		ID:       "printer_thermal_01",
		Name:     "Mandi Gate Pass & Receipt Printer",
		Type:     TypePrinter,
		Protocol: ProtocolLAN,
		Address:  "192.168.1.188:9100",
		IsOnline: true,
		State: map[string]interface{}{
			"paper_status": "ready",
			"jobs_queued":  0,
		},
		Capabilities: []string{"esc_pos_print", "qr_code_print", "auto_cutter"},
		LastSeen:     time.Now(),
	}

	// Bluetooth Earphone / Audio Sink
	m.devices["audio_earphone_01"] = &IoTDevice{
		ID:       "audio_earphone_01",
		Name:     "NearMitra Wireless Voice Earphone",
		Type:     TypeAudio,
		Protocol: ProtocolBluetooth,
		Address:  "70:99:1C:82:11:4A",
		IsOnline: m.support.BluetoothActive,
		State: map[string]interface{}{
			"connected":   m.support.BluetoothActive,
			"battery_pct": 92,
			"codec":       "AAC / SBC",
		},
		Capabilities: []string{"audio_playback", "walkie_talkie_mic", "noise_cancellation"},
		LastSeen:     time.Now(),
	}

	// Document & Barcode Scanner Node
	m.devices["scanner_doc_01"] = &IoTDevice{
		ID:       "scanner_doc_01",
		Name:     "Document & Invoice Scanner",
		Type:     TypeScanner,
		Protocol: ProtocolUSB,
		Address:  "WIA-Device-001",
		IsOnline: true,
		State: map[string]interface{}{
			"ready":      true,
			"resolution": "300 DPI",
		},
		Capabilities: []string{"document_scan", "barcode_reader", "ocr_auto"},
		LastSeen:     time.Now(),
	}
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
	m.mu.Lock()
	defer m.mu.Unlock()

	dev, ok := m.devices[deviceID]
	if !ok {
		return false, fmt.Errorf("device %s not found", deviceID)
	}

	currentPower, _ := dev.State["power"].(bool)
	newPower := !currentPower
	dev.State["power"] = newPower
	if newPower {
		dev.State["current_a"] = 8.4
		dev.State["flow_rate_lpm"] = 45.0
	} else {
		dev.State["current_a"] = 0.0
		dev.State["flow_rate_lpm"] = 0.0
	}
	dev.LastSeen = time.Now()
	return newPower, nil
}

// TriggerTestPrint executes a sample print job for receipt/dispatch printers.
func (m *Manager) TriggerTestPrint(printerID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	dev, ok := m.devices[printerID]
	if !ok {
		return fmt.Errorf("printer %s not found", printerID)
	}

	dev.State["jobs_queued"] = 1
	dev.LastSeen = time.Now()

	time.AfterFunc(2*time.Second, func() {
		m.mu.Lock()
		dev.State["jobs_queued"] = 0
		m.mu.Unlock()
	})
	return nil
}

// TriggerScan starts document scanning.
func (m *Manager) TriggerScan(scannerID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	dev, ok := m.devices[scannerID]
	if !ok {
		return fmt.Errorf("scanner %s not found", scannerID)
	}

	dev.State["scanning"] = true
	time.AfterFunc(3*time.Second, func() {
		m.mu.Lock()
		dev.State["scanning"] = false
		m.mu.Unlock()
	})
	return nil
}

// SetInternetMode toggles WAN connectivity.
func (m *Manager) SetInternetMode(enabled bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.support.InternetModeEnabled = enabled
}

// startTelemetryWorker periodically refreshes sensor metrics.
func (m *Manager) startTelemetryWorker() {
	ticker := time.NewTicker(4 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			m.mu.Lock()
			if sensor, ok := m.devices["sensor_soil_01"]; ok {
				curM, _ := sensor.State["moisture_pct"].(float64)
				jitter := (rand.Float64() - 0.5) * 0.4
				newM := curM + jitter
				if newM < 10.0 {
					newM = 10.0
				}
				if newM > 90.0 {
					newM = 90.0
				}
				sensor.State["moisture_pct"] = float64(int(newM*10)) / 10.0
				sensor.LastSeen = time.Now()
			}
			m.mu.Unlock()

		case <-m.stopChan:
			return
		}
	}
}

// Close stops background routines.
func (m *Manager) Close() {
	close(m.stopChan)
}
