package transfer

import (
	"encoding/json"
	"nearmitra-windows-app/internal/calling"
	"nearmitra-windows-app/internal/config"
	"nearmitra-windows-app/internal/models"
	"net"
	"testing"
	"time"
)

func TestMobileAIProtocolsRespectGrantAndRevoke(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	t.Setenv("USERPROFILE", t.TempDir())
	cfg := config.Get().GetConfig().AIConfig
	previous := cfg
	defer config.Get().SetAIConfig(previous)
	cfg.Enabled = true
	cfg.ShareAI = true
	cfg.AllowedPeers = []string{"phone-wan"}
	for _, kind := range []string{"ai_chat", "ai_prompt", "ai_request"} {
		for _, revoke := range []bool{false, true} {
			t.Run(kind+map[bool]string{false: "-allowed", true: "-revoked"}[revoke], func(t *testing.T) {
				cfg.RevokedPeers = nil
				if revoke {
					cfg.RevokedPeers = []string{"phone-lan"}
				}
				config.Get().SetAIConfig(cfg)
				called := false
				ts := &TransferServer{callbacks: TransferCallbacks{OnAIRequest: func(prompt, id, name string, c net.Conn) {
					called = true
					json.NewEncoder(c).Encode(map[string]interface{}{"type": "ai_response", "status": "success", "reply": "Desktop AI answer", "done": true})
				}}}
				r, s := net.Pipe()
				defer s.Close()
				s.SetDeadline(time.Now().Add(3 * time.Second))
				go ts.handleConnection(r)
				json.NewEncoder(s).Encode(models.WireHeader{Type: kind, SenderID: "phone-lan", InternetDeviceID: "phone-wan", Prompt: "Question"})
				var reply map[string]interface{}
				if err := json.NewDecoder(s).Decode(&reply); err != nil {
					t.Fatal(err)
				}
				if revoke {
					if called || reply["status"] != "disabled" || reply["error_code"] != "ai_disabled" {
						t.Fatalf("revoked access: %+v", reply)
					}
				} else if !called || reply["reply"] != "Desktop AI answer" {
					t.Fatalf("allowed request failed: %+v", reply)
				}
			})
		}
	}
}
func TestMobileCallControlReachesBrowserWithoutEcho(t *testing.T) {
	cs := calling.GetCall()
	cs.ApplyRemote("call_ended", "pipe")
	if !cs.SetIncoming("pipe", "Phone", true) {
		t.Fatal("busy before test")
	}
	defer cs.ApplyRemote("call_ended", "pipe")
	for _, kind := range []string{"call_accepted", "webrtc_offer", "webrtc_ice", "call_ended"} {
		t.Run(kind, func(t *testing.T) {
			events := make(chan models.WireHeader, 1)
			ts := &TransferServer{callbacks: TransferCallbacks{OnStreamSignal: func(ip string, h models.WireHeader) {
				if ip != "pipe" {
					t.Errorf("wrong remote: %s", ip)
				}
				events <- h
			}}}
			r, s := net.Pipe()
			go ts.handleConnection(r)
			s.SetDeadline(time.Now().Add(time.Second))
			json.NewEncoder(s).Encode(models.WireHeader{Type: kind, SenderID: "phone", SDP: "offer", Candidate: "candidate"})
			s.Close()
			select {
			case event := <-events:
				if event.Type != kind {
					t.Fatalf("wrong event: %+v", event)
				}
			case <-time.After(time.Second):
				t.Fatal("call event lost")
			}
		})
	}
}
