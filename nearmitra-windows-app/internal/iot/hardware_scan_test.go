package iot

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestHardwareScanFailureDoesNotInventDevices(t *testing.T) {
	original := executeHardwareQuery
	originalSummary := hwSummaryCache
	defer func() { executeHardwareQuery = original; hwSummaryCache = originalSummary }()
	executeHardwareQuery = func(ctx context.Context, _ string) ([]byte, error) {
		deadline, ok := ctx.Deadline()
		if !ok || time.Until(deadline) > 13*time.Second {
			t.Error("hardware query must have bounded deadline")
		}
		return nil, errors.New("PowerShell unavailable")
	}
	got := ScanRealWindowsHardware()
	if got.ScanError == "" || len(got.AudioDevices) != 0 || len(got.USBDevices) != 0 || got.BluetoothBLE || got.HasBuiltinSpeaker {
		t.Fatalf("failure fabricated hardware: %+v", got)
	}
}
func TestPnPUnknownStatusAndRealDevices(t *testing.T) {
	original := executeHardwareQuery
	originalSummary := hwSummaryCache
	defer func() { executeHardwareQuery = original; hwSummaryCache = originalSummary }()
	executeHardwareQuery = func(context.Context, string) ([]byte, error) {
		return []byte(`[{"FriendlyName":"USB controller","Class":"USB","Status":"OK"},{"FriendlyName":"Microphone","Class":"AudioEndpoint","Status":"Error"},{"FriendlyName":"Camera","Class":"Camera","Status":"OK"}]`), nil
	}
	got := ScanRealWindowsHardware()
	if len(got.USBDevices) != 1 || len(got.AudioDevices) != 1 || got.HasBuiltinMic || !got.HasBuiltinCam || got.BluetoothBLE {
		t.Fatalf("incorrect device readiness: %+v", got)
	}
}
func TestConcurrentScanReturnsBusyImmediately(t *testing.T) {
	hwScanMu.Lock()
	defer hwScanMu.Unlock()
	started := time.Now()
	got := ScanRealWindowsHardware()
	if !got.IsScanning || time.Since(started) > time.Second {
		t.Fatal("concurrent scan must not block behind query")
	}
}
