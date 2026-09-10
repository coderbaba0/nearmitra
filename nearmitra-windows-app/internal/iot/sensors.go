// Package iot provides remote mobile sensor telemetry models and virtual hardware state.
package iot

import (
	"sync"
	"time"
)

// RemotePhoneSensors represents live sensor telemetry received from a remote Android phone or node.
type RemotePhoneSensors struct {
	DeviceName       string             `json:"device_name"`
	DeviceIP         string             `json:"device_ip"`
	LastSeen         time.Time          `json:"last_seen"`

	// GPS & Location Telemetry
	GPSLatitude      float64            `json:"gps_latitude"`
	GPSLongitude     float64            `json:"gps_longitude"`
	GPSAltitude      float64            `json:"gps_altitude"`
	GPSAccuracy      float64            `json:"gps_accuracy"`
	GPSSpeedKmh      float64            `json:"gps_speed_kmh"`
	GPSLocationName  string             `json:"gps_location_name"`
	GPSLocked        bool               `json:"gps_locked"`

	// Battery & Power Telemetry
	BatteryLevel     int                `json:"battery_level"`     // 0 - 100%
	IsCharging       bool               `json:"is_charging"`
	BatteryHealth    string             `json:"battery_health"`    // "Good", "Overheat", "Cold"
	BatteryTempC     float64            `json:"battery_temp_c"`

	// 3D Motion & Gyroscope Telemetry
	OrientationPitch float64            `json:"orientation_pitch"` // Degrees -90 to +90
	OrientationRoll  float64            `json:"orientation_roll"`  // Degrees -180 to +180
	OrientationAzimuth float64          `json:"orientation_azimuth"` // 0 to 360 compass
	StepCount        int                `json:"step_count"`

	// Remote Bluetooth BLE Scanner results (Discovered by Phone)
	RemoteBLEDevices []RemoteBLEDevice  `json:"remote_ble_devices"`

	// Remote NFC Card Reader
	LastNFCTagUID    string             `json:"last_nfc_tag_uid"`
	LastNFCTech      string             `json:"last_nfc_tech"`
	LastNFCData      string             `json:"last_nfc_data"`
	NFCTapTimestamp  time.Time          `json:"nfc_tap_timestamp"`

	// Live System Audio Cast Sink Status
	LiveAudioStreaming bool             `json:"live_audio_streaming"`
	AudioBitrateKbps   int              `json:"audio_bitrate_kbps"`
	AudioLatencyMs     int              `json:"audio_latency_ms"`
}

// RemoteBLEDevice represents a Bluetooth device scanned by the remote phone.
type RemoteBLEDevice struct {
	Name     string `json:"name"`
	MAC      string `json:"mac"`
	RSSI     int    `json:"rssi"`
	Type     string `json:"type"` // "Beacon", "Smart Band", "Heart Rate", "Sensor Tag"
	Distance string `json:"distance"`
}

var (
	sensorsMu     sync.RWMutex
	globalSensors = &RemotePhoneSensors{
		DeviceName:       "Subham007 (Remote Phone)",
		DeviceIP:         "192.168.1.5",
		LastSeen:         time.Now(),
		GPSLatitude:      28.6139,
		GPSLongitude:     77.2090,
		GPSAltitude:      216.5,
		GPSAccuracy:      4.2,
		GPSSpeedKmh:      0.0,
		GPSLocationName:  "New Delhi, India (Mandi Sector-4)",
		GPSLocked:        true,
		BatteryLevel:     86,
		IsCharging:       false,
		BatteryHealth:    "Good (Optimal)",
		BatteryTempC:     31.4,
		OrientationPitch: 12.5,
		OrientationRoll:  -4.8,
		OrientationAzimuth: 142.0,
		StepCount:        4820,
		RemoteBLEDevices: []RemoteBLEDevice{
			{Name: "Kisan Soil Probe #1", MAC: "C4:4F:33:1A:89:BC", RSSI: -54, Type: "Soil NPK Sensor", Distance: "~1.2m"},
			{Name: "ESP32 Mandi Gateway", MAC: "24:6F:28:B2:A1:04", RSSI: -68, Type: "Smart Relay Bridge", Distance: "~3.8m"},
			{Name: "Bluetooth Thermal POS", MAC: "66:32:1B:00:29:EE", RSSI: -61, Type: "ESC/POS Printer", Distance: "~2.4m"},
			{Name: "FitBand HR Tracker", MAC: "E2:15:6C:99:41:2B", RSSI: -74, Type: "BLE Wearable", Distance: "~5.1m"},
		},
		LastNFCTagUID:   "04:A2:88:5A:19:6C:80",
		LastNFCTech:     "ISO 14443-4 / NXP MIFARE Classic 1K",
		LastNFCData:     "Farmer e-Mandi Pass: KM-88492 • Crop: Basmati Grade A • Trader: Verified",
		NFCTapTimestamp: time.Now().Add(-15 * time.Minute),
		LiveAudioStreaming: false,
		AudioBitrateKbps: 128,
		AudioLatencyMs: 16,
	}
)

// GetRemotePhoneSensors returns live sensor data from the connected remote phone.
func GetRemotePhoneSensors() RemotePhoneSensors {
	sensorsMu.RLock()
	defer sensorsMu.RUnlock()
	return *globalSensors
}

// UpdateRemoteSensors updates sensor values when telemetry packets arrive.
func UpdateRemoteSensors(data map[string]interface{}) {
	sensorsMu.Lock()
	defer sensorsMu.Unlock()

	globalSensors.LastSeen = time.Now()
	if dev, ok := data["device_name"].(string); ok && dev != "" {
		globalSensors.DeviceName = dev
	}
	if ip, ok := data["device_ip"].(string); ok && ip != "" {
		globalSensors.DeviceIP = ip
	}

	if gps, ok := data["gps"].(map[string]interface{}); ok {
		if lat, ok := gps["lat"].(float64); ok { globalSensors.GPSLatitude = lat }
		if lng, ok := gps["lng"].(float64); ok { globalSensors.GPSLongitude = lng }
		if alt, ok := gps["alt"].(float64); ok { globalSensors.GPSAltitude = alt }
		if acc, ok := gps["accuracy"].(float64); ok { globalSensors.GPSAccuracy = acc }
		if loc, ok := gps["location_name"].(string); ok { globalSensors.GPSLocationName = loc }
		globalSensors.GPSLocked = true
	}

	if bat, ok := data["battery"].(map[string]interface{}); ok {
		if lvl, ok := bat["level"].(float64); ok { globalSensors.BatteryLevel = int(lvl) }
		if chg, ok := bat["charging"].(bool); ok { globalSensors.IsCharging = chg }
		if temp, ok := bat["temp"].(float64); ok { globalSensors.BatteryTempC = temp }
	}

	if nfc, ok := data["nfc"].(map[string]interface{}); ok {
		if uid, ok := nfc["uid"].(string); ok { globalSensors.LastNFCTagUID = uid }
		if tech, ok := nfc["tech"].(string); ok { globalSensors.LastNFCTech = tech }
		if ndef, ok := nfc["ndef"].(string); ok { globalSensors.LastNFCData = ndef }
		globalSensors.NFCTapTimestamp = time.Now()
	}

	if audio, ok := data["audio_cast"].(map[string]interface{}); ok {
		if active, ok := audio["active"].(bool); ok { globalSensors.LiveAudioStreaming = active }
		if kbps, ok := audio["bitrate"].(float64); ok { globalSensors.AudioBitrateKbps = int(kbps) }
		if lat, ok := audio["latency_ms"].(float64); ok { globalSensors.AudioLatencyMs = int(lat) }
	}
}
