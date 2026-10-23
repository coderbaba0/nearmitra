package iot

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"
)

func withGateway(t *testing.T, handler http.HandlerFunc) *httptest.Server {
	t.Helper()
	old := GetGatewayConfig()
	oldPath := gatewayState.Path
	t.Cleanup(func() {
		gatewayState.Lock()
		gatewayState.Config = old
		gatewayState.Path = oldPath
		gatewayState.Unlock()
	})
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	if err := LoadGatewayConfig(filepath.Join(t.TempDir(), "hardware.json")); err != nil {
		t.Fatal(err)
	}
	if err := SaveGatewayConfig(GatewayConfig{Relays: [4]string{server.URL}, SensorURL: server.URL, NFCURL: server.URL, ScaleURL: server.URL}); err != nil {
		t.Fatal(err)
	}
	return server
}
func TestRelayRequiresExplicitAcknowledgement(t *testing.T) {
	confirm := true
	withGateway(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Error("must POST")
		}
		var body map[string]bool
		_ = json.NewDecoder(r.Body).Decode(&body)
		_ = json.NewEncoder(w).Encode(map[string]bool{"power": body["power"] && confirm})
	})
	if _, err := SetRelay(context.Background(), 1, true); err != nil {
		t.Fatal(err)
	}
	confirm = false
	if _, err := SetRelay(context.Background(), 1, true); err == nil {
		t.Fatal("unacknowledged power must fail")
	}
	if _, err := SetRelay(context.Background(), 5, true); err == nil {
		t.Fatal("invalid channel")
	}
}
func TestGatewayRejectsBadResponseAndCancelledRequest(t *testing.T) {
	server := withGateway(t, func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"moisture_pct":150,"weight_kg":-2}`))
	})
	for _, kind := range []string{"sensor", "scale", "nfc"} {
		if _, err := ReadGateway(context.Background(), kind); err == nil {
			t.Fatal("invalid reading accepted: " + kind)
		}
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := gatewayRequest(ctx, server.URL, nil); err == nil {
		t.Fatal("cancellation ignored")
	}
}
func TestGatewayPersistenceAndTare(t *testing.T) {
	withGateway(t, func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]float64{"weight_kg": 0})
	})
	cfg := GetGatewayConfig()
	if err := LoadGatewayConfig(gatewayState.Path); err != nil {
		t.Fatal(err)
	}
	if GetGatewayConfig() != cfg {
		t.Fatal("configuration did not persist")
	}
	if _, err := TareScale(context.Background()); err != nil {
		t.Fatal(err)
	}
}
func TestScheduledRelayPersistsOffAndRecoversAfterRestart(t *testing.T) {
	var powers []bool
	server := withGateway(t, func(w http.ResponseWriter, r *http.Request) {
		var body map[string]bool
		_ = json.NewDecoder(r.Body).Decode(&body)
		powers = append(powers, body["power"])
		_ = json.NewEncoder(w).Encode(body)
	})
	old := GetRelaySchedules()
	oldPath := scheduleState.Path
	t.Cleanup(func() {
		scheduleState.Lock()
		scheduleState.Items = old
		scheduleState.Path = oldPath
		scheduleState.Unlock()
	})
	path := filepath.Join(t.TempDir(), "timers.json")
	if err := LoadRelaySchedules(path); err != nil {
		t.Fatal(err)
	}
	scheduleState.Items = nil
	start := time.Now().Add(time.Minute)
	if err := AddRelaySchedule(RelaySchedule{Channel: 1, At: start, DurationSeconds: 60}); err != nil {
		t.Fatal(err)
	}
	if len(GetRelaySchedules()) != 2 {
		t.Fatal("ON and OFF must persist together")
	}
	// Editing current connections must never redirect a previously scheduled OFF.
	if err := SaveGatewayConfig(GatewayConfig{}); err != nil {
		t.Fatal(err)
	}
	RunRelaySchedules(start.Add(time.Second))
	if len(powers) != 1 || !powers[0] {
		t.Fatal("ON not sent")
	}
	if err := LoadRelaySchedules(path); err != nil {
		t.Fatal(err)
	}
	RunRelaySchedules(start.Add(2 * time.Minute))
	if len(powers) != 2 || powers[1] {
		t.Fatal("persisted OFF not recovered")
	}
	if GetRelaySchedules()[1].Endpoint != server.URL {
		t.Fatal("schedule target changed")
	}
}
func TestCancellingRunningRelayConfirmsOffAndRetainsRecoveryOnFailure(t *testing.T) {
	failOff := false
	var powers []bool
	withGateway(t, func(w http.ResponseWriter, r *http.Request) {
		var body map[string]bool
		_ = json.NewDecoder(r.Body).Decode(&body)
		powers = append(powers, body["power"])
		if !body["power"] && failOff {
			http.Error(w, "offline", 503)
			return
		}
		_ = json.NewEncoder(w).Encode(body)
	})
	old := GetRelaySchedules()
	oldPath := scheduleState.Path
	t.Cleanup(func() {
		scheduleState.Lock()
		scheduleState.Items = old
		scheduleState.Path = oldPath
		scheduleState.Unlock()
	})
	_ = LoadRelaySchedules(filepath.Join(t.TempDir(), "timers.json"))
	scheduleState.Items = nil
	start := time.Now().Add(time.Minute)
	if err := AddRelaySchedule(RelaySchedule{Channel: 1, At: start, DurationSeconds: 120}); err != nil {
		t.Fatal(err)
	}
	RunRelaySchedules(start)
	id := GetRelaySchedules()[0].ID
	failOff = true
	if err := CancelRelaySchedule(id); err == nil {
		t.Fatal("cancel must not discard OFF recovery after failure")
	}
	if GetRelaySchedules()[1].Status != "pending" {
		t.Fatal("OFF recovery lost")
	}
	failOff = false
	if err := CancelRelaySchedule(id); err != nil {
		t.Fatal(err)
	}
	if GetRelaySchedules()[1].Status != "cancelled" || powers[len(powers)-1] {
		t.Fatal("cancel did not confirm OFF")
	}
}
