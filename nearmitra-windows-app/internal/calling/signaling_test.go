package calling

import (
	"encoding/json"
	"nearmitra-windows-app/internal/models"
	"net"
	"testing"
	"time"
)

func TestRemoteEndResetsOnlyTheActivePeer(t *testing.T) {
	cs := &CallState{}
	if !cs.SetIncoming("192.0.2.1", "Phone", true) {
		t.Fatal("incoming failed")
	}
	if cs.SetIncoming("192.0.2.2", "Other", false) {
		t.Fatal("busy call replaced")
	}
	if cs.ApplyRemote("call_ended", "192.0.2.2") {
		t.Fatal("other peer ended call")
	}
	if !cs.ApplyRemote("call_accepted", "192.0.2.1") || cs.Snapshot()["active"] != true {
		t.Fatal("accept not recorded")
	}
	if !cs.ApplyRemote("call_ended", "192.0.2.1") || cs.Snapshot()["active"] != false || cs.Snapshot()["ringing"] != false {
		t.Fatal("remote end not reset")
	}
}

func TestAbandonedOutgoingInviteExpiresWithoutEndingAcceptedOrNewerCall(t *testing.T) {
	started := time.Now()
	cs := &CallState{PeerIP: "192.0.2.1", StartTime: started}
	if cs.expireOutgoing("192.0.2.1", started.Add(-time.Second)) {
		t.Fatal("old timer ended new invitation")
	}
	cs.Active = true
	if cs.expireOutgoing("192.0.2.1", started) {
		t.Fatal("active call expired")
	}
	cs.Active = false
	if !cs.expireOutgoing("192.0.2.1", started) || cs.PeerIP != "" {
		t.Fatal("abandoned invitation did not release busy state")
	}
}

func TestMobileAcknowledgesDisplayedIncomingCallAndBusy(t *testing.T) {
	for _, status := range []string{"ringing", "busy"} {
		desktop, phone := net.Pipe()
		desktop.SetDeadline(time.Now().Add(time.Second))
		go func() {
			defer phone.Close()
			var request models.WireHeader
			_ = json.NewDecoder(phone).Decode(&request)
			if request.Type != "call_invite" || !request.RequireAck {
				t.Error("invalid Windows call packet")
			}
			_ = json.NewEncoder(phone).Encode(map[string]string{"type": "call_ringing", "status": status})
		}()
		err := writeCallPacket(desktop, "phone", models.WireHeader{Type: "call_invite", RequireAck: true})
		desktop.Close()
		if (status == "busy") != (err != nil) {
			t.Fatalf("status %s: %v", status, err)
		}
	}
}
