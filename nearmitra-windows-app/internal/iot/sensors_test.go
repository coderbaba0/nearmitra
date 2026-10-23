package iot

import "testing"

func TestRemoteTelemetryUsesRealDataAndSeparatesDevices(t *testing.T) {
	old := globalSensors
	globalSensors = &RemotePhoneSensors{}
	defer func() { globalSensors = old }()
	if !GetRemotePhoneSensors().LastSeen.IsZero() {
		t.Fatal("empty state must not claim live telemetry")
	}
	UpdateRemoteSensors(map[string]interface{}{"device_ip": "192.168.1.4", "gps": map[string]interface{}{"lat": 0.0, "lng": 0.0}, "battery": map[string]interface{}{"level": 0.0}})
	got := GetRemotePhoneSensors()
	if !got.GPSLocked || !got.BatteryAvailable || got.BatteryLevel != 0 {
		t.Fatalf("zero values are valid: %+v", got)
	}
	UpdateRemoteSensors(map[string]interface{}{"device_ip": "192.168.1.8"})
	got = GetRemotePhoneSensors()
	if got.GPSLocked || got.BatteryAvailable {
		t.Fatal("new phone must not inherit another phone's readings")
	}
	UpdateRemoteSensors(map[string]interface{}{"gps": map[string]interface{}{"lat": 91.0, "lng": 0.0}, "battery": map[string]interface{}{"level": 150.0}})
	got = GetRemotePhoneSensors()
	if got.GPSLocked || got.BatteryAvailable {
		t.Fatal("invalid telemetry was accepted")
	}
}

func TestBatteryOnlySnapshotClearsPreviouslySharedLocation(t *testing.T) {
	old := globalSensors
	defer func() { globalSensors = old }()
	ReplaceRemoteSnapshot(map[string]interface{}{"device_ip": "1.2.3.4", "gps": map[string]interface{}{"lat": 1.0, "lng": 2.0}})
	ReplaceRemoteSnapshot(map[string]interface{}{"device_ip": "1.2.3.4", "battery": map[string]interface{}{"level": 50.0}})
	if GetRemotePhoneSensors().GPSLocked {
		t.Fatal("battery consent must not refresh previous GPS")
	}
}
