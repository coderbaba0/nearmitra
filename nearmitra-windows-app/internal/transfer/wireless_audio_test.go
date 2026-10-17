package transfer

import (
	"encoding/json"
	"nearmitra-windows-app/internal/models"
	"net"
	"testing"
	"time"
)

func TestWirelessAudioProtocolPreservesSessionAndBypassesCallAndCameraFlows(t *testing.T) {
	for _, kind := range []string{"pending", "request", "offer", "answer", "ice", "stop", "reject"} {
		t.Run(kind, func(t *testing.T) {
			received := make(chan models.WireHeader, 1)
			ts := &TransferServer{callbacks: TransferCallbacks{OnStreamSignal: func(ip string, h models.WireHeader) { received <- h }, OnCallInvite: func(string, string, bool) { t.Error("wireless audio incorrectly triggered incoming call") }}}
			server, client := net.Pipe()
			defer client.Close()
			client.SetDeadline(time.Now().Add(3 * time.Second))
			go ts.handleConnection(server)
			packet := models.WireHeader{Type: "wireless_audio_" + kind, SessionID: "wa-12345678-abcd", StreamType: "wireless_audio", AudioMode: "system", SDP: "audio-only", Candidate: "host candidate", SenderID: "phone"}
			if err := json.NewEncoder(client).Encode(packet); err != nil {
				t.Fatal(err)
			}
			select {
			case got := <-received:
				if got.SessionID != packet.SessionID || got.AudioMode != packet.AudioMode || got.Type != packet.Type || got.SDP != packet.SDP || got.Candidate != packet.Candidate {
					t.Fatalf("wireless signal metadata lost: %+v", got)
				}
			case <-time.After(3 * time.Second):
				t.Fatal("wireless audio packet not forwarded")
			}
		})
	}
}
