package wan

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"
)

func testPresenceService(t *testing.T, handler http.HandlerFunc) *WanService {
	t.Helper()
	dir := t.TempDir()
	for _, key := range []string{"LOCALAPPDATA", "APPDATA", "USERPROFILE"} {
		t.Setenv(key, dir)
	}
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	return &WanService{client: NewFirebaseClient(server.URL), config: WanConfig{InternetModeEnabled: true, DiscoveryMode: ModePublicRadar}, running: true, stopChan: make(chan struct{}), trustedDevices: make(map[string]*WanDevice), publicDevices: make(map[string]*WanDevice), pendingRequests: make(map[string]*WanPairRequest)}
}

func TestWindowsPresenceExpiresButSDKMobilePresenceKeepsOnDisconnectSemantics(t *testing.T) {
	now := time.Now()
	cases := []struct {
		name, platform string
		online         bool
		seen           time.Time
		lease          int64
		want           bool
	}{
		{"fresh Windows", "windows", true, now.Add(-20 * time.Second), 0, true},
		{"powered-off legacy Windows", "windows", true, now.Add(-10 * time.Minute), 0, false},
		{"missing heartbeat", "windows", true, time.Time{}, 0, false},
		{"explicit offline wins", "windows", false, now, 75000, false},
		{"SDK mobile does not require heartbeat", "android", true, now.Add(-24 * time.Hour), 0, true},
		{"SDK mobile disconnect", "android", false, now, 0, false},
		{"future timestamp cannot live forever", "windows", true, now.Add(time.Hour), 0, false},
		{"declared REST lease on other platform", "linux", true, now.Add(-2 * time.Minute), 75000, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := presenceAlive(c.online, c.platform, c.seen, c.lease, now); got != c.want {
				t.Fatalf("got online=%v want %v", got, c.want)
			}
		})
	}
}

func TestHeartbeatPublishesServerTimestampAndStopWritesOfflineAfterOnline(t *testing.T) {
	var mu sync.Mutex
	var writes []string
	var payloads []map[string]interface{}
	ws := testPresenceService(t, func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		writes = append(writes, r.Method+" "+r.URL.Path)
		if r.Method == "PUT" || r.Method == "PATCH" {
			var p map[string]interface{}
			if err := json.NewDecoder(r.Body).Decode(&p); err != nil {
				t.Error(err)
			}
			payloads = append(payloads, p)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`null`))
	})
	ws.syncPresenceImmediate()
	if !ws.isPresenceOnline {
		t.Fatal("successful heartbeat did not mark presence online")
	}
	ws.Stop()
	ws.syncPresenceImmediate()
	mu.Lock()
	defer mu.Unlock()
	if len(writes) != 4 {
		t.Fatalf("expected online/private, online/public, offline/private, delete/public; got %v", writes)
	}
	if payloads[0]["online"] != true || payloads[0]["presenceLeaseMs"] != float64(desktopPresenceLease.Milliseconds()) {
		t.Fatalf("missing bounded heartbeat lease: %v", payloads[0])
	}
	for _, p := range payloads {
		timestamp, ok := p["lastSeen"].(map[string]interface{})
		if !ok || timestamp[".sv"] != "timestamp" {
			t.Fatal("presence must use Firebase server time")
		}
	}
	if payloads[2]["online"] != false || ws.isPresenceOnline {
		t.Fatal("stop did not leave presence offline")
	}
}

func TestStopCancelsInflightHeartbeatAndCannotBeResurrected(t *testing.T) {
	started := make(chan struct{})
	var mu sync.Mutex
	var writes []string
	ws := testPresenceService(t, func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		writes = append(writes, r.Method)
		mu.Unlock()
		if r.Method == http.MethodPut {
			close(started)
			select {
			case <-r.Context().Done():
			case <-time.After(5 * time.Second):
			}
			return
		}
		_, _ = w.Write([]byte(`null`))
	})
	done := make(chan struct{})
	go func() { ws.syncPresenceImmediate(); close(done) }()
	select {
	case <-started:
	case <-time.After(3 * time.Second):
		t.Fatal("heartbeat did not start")
	}
	stopped := make(chan struct{})
	go func() { ws.Stop(); close(stopped) }()
	select {
	case <-stopped:
	case <-time.After(3 * time.Second):
		t.Fatal("stop failed to cancel inflight presence")
	}
	<-done
	mu.Lock()
	defer mu.Unlock()
	if len(writes) != 3 || writes[1] != "PATCH" || writes[2] != "DELETE" {
		t.Fatalf("late heartbeat or missing cleanup: %v", writes)
	}
	if ws.isPresenceOnline {
		t.Fatal("late heartbeat resurrected stopped WAN presence")
	}
}

func TestPublicSweepDropsStaleAndDeletedDesktopEntries(t *testing.T) {
	var payload interface{} = map[string]interface{}{
		"active": map[string]interface{}{"platform": "windows", "online": true, "lastSeen": time.Now().UnixMilli()},
		"stale":  map[string]interface{}{"platform": "windows", "online": true, "lastSeen": time.Now().Add(-time.Hour).UnixMilli()},
	}
	ws := testPresenceService(t, func(w http.ResponseWriter, r *http.Request) { _ = json.NewEncoder(w).Encode(payload) })
	ws.sweepPublicPresence()
	if len(ws.publicDevices) != 1 || ws.publicDevices["active"] == nil {
		t.Fatalf("stale public devices remain: %v", ws.publicDevices)
	}
	payload = nil
	ws.sweepPublicPresence()
	if len(ws.publicDevices) != 0 {
		t.Fatal("deleted Firebase public records left cached devices online")
	}
}

func TestCachedPresenceExpiresEvenWithoutAnotherFirebaseResponse(t *testing.T) {
	ws := testPresenceService(t, func(w http.ResponseWriter, r *http.Request) { _, _ = w.Write([]byte(`null`)) })
	ws.trustedDevices["pc"] = &WanDevice{ID: "pc", Platform: "windows", IsOnline: true, LastSeen: time.Now().Add(-time.Hour), IsTrusted: true}
	state := ws.GetState()
	if len(state.TrustedDevices) != 1 || state.TrustedDevices[0].IsOnline {
		t.Fatal("stale trusted desktop still shown online")
	}
}
