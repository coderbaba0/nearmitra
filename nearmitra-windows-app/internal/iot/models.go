// Package iot provides models, multi-protocol device management, hardware diagnostics, and AI scheduling.
package iot

import (
	"time"
)

// DeviceType classifies peripheral hardware.
type DeviceType string

const (
	TypeRelay     DeviceType = "relay"      // Smart Switches, Water Pumps, Solenoid Valves
	TypeSensor    DeviceType = "sensor"     // Soil Moisture, Temperature, Humidity, NPK
	TypePrinter   DeviceType = "printer"    // Network, Thermal, POS, Windows Spooler
	TypeScanner   DeviceType = "scanner"    // WIA, TWAIN, Document & Barcode Scanners
	TypeAudio     DeviceType = "audio"      // Bluetooth Earphones, Headsets, Speakers
	TypeBLEBeacon DeviceType = "ble_beacon" // Proximity Beacons & Asset Trackers
	TypeNFCReader DeviceType = "nfc_reader" // Proximity Tags & Smart Cards
	TypeSmartNode DeviceType = "smart_node" // ESP32 / Arduino / Raspberry Pi Bridge
)

// Protocol specifies the physical/link communication layer.
type Protocol string

const (
	ProtocolWiFi       Protocol = "Wi-Fi"
	ProtocolLAN        Protocol = "LAN / Ethernet"
	ProtocolBluetooth  Protocol = "Bluetooth / BLE"
	ProtocolWiFiDirect Protocol = "Wi-Fi Direct"
	ProtocolNFC        Protocol = "NFC"
	ProtocolUSB        Protocol = "USB Direct"
	ProtocolInternet   Protocol = "Internet (WAN)"
)

// HardwareSupportMatrix holds the host PC's detected hardware capabilities.
type HardwareSupportMatrix struct {
	WiFiSupported   bool   `json:"wifi_supported"`
	WiFiActive      bool   `json:"wifi_active"`
	WiFiAdapterName string `json:"wifi_adapter_name"`

	BluetoothSupported bool   `json:"bluetooth_supported"`
	BluetoothActive    bool   `json:"bluetooth_active"`
	BluetoothRadioName string `json:"bluetooth_radio_name"`

	LANSupported   bool   `json:"lan_supported"`
	LANActive      bool   `json:"lan_active"`
	LANAdapterName string `json:"lan_adapter_name"`

	NFCSupported    bool   `json:"nfc_supported"`
	NFCActive       bool   `json:"nfc_active"`
	NFCStatusReason string `json:"nfc_status_reason"`

	WiFiDirectSupported bool `json:"wifi_direct_supported"`
	WiFiDirectActive    bool `json:"wifi_direct_active"`

	PrintersCount int `json:"printers_count"`
	ScannersCount int `json:"scanners_count"`

	InternetModeEnabled bool      `json:"internet_mode_enabled"` // Strictly false by default for local-first security
	LastDiagnostic      time.Time `json:"last_diagnostic"`
}

// IoTDevice represents a connected or discovered hardware peripheral.
type IoTDevice struct {
	ID           string                 `json:"id"`
	Name         string                 `json:"name"`
	Type         DeviceType             `json:"type"`
	Protocol     Protocol               `json:"protocol"`
	Address      string                 `json:"address"` // IP, MAC, COM Port, or System GUID
	IsOnline     bool                   `json:"is_online"`
	State        map[string]interface{} `json:"state"` // e.g. {"power": true, "moisture": 42.5, "battery": 90}
	Capabilities []string               `json:"capabilities"`
	LastSeen     time.Time              `json:"last_seen"`
}

// AITaskSchedule defines automated or scheduled device operations.
type AITaskSchedule struct {
	ID              string    `json:"id"`
	DeviceID        string    `json:"device_id"`
	DeviceName      string    `json:"device_name"`
	Action          string    `json:"action"` // e.g. "turn_on", "turn_off", "test_print", "read_sensor"
	DurationMinutes int       `json:"duration_minutes"`
	ScheduledAt     time.Time `json:"scheduled_at"`
	CronExpr        string    `json:"cron_expr,omitempty"`
	AIPromptTrigger string    `json:"ai_prompt_trigger,omitempty"` // Natural language condition
	IsActive        bool      `json:"is_active"`
}
