package network

import (
	"encoding/json"
	"errors"
	"net"
	"testing"
	"time"

	"nearmitra-windows-app/internal/models"
)

func presenceDiscovery(t *testing.T, age time.Duration) *DiscoveryService {
	t.Helper()
	t.Setenv("APPDATA", t.TempDir())
	t.Setenv("USERPROFILE", t.TempDir())
	return &DiscoveryService{peers: map[string]*models.Peer{"pc": {
		ID: "pc", Name: "Office", IP: "203.0.113.7", Port: models.TransferPort,
		IsOnline: true, LastSeen: time.Now().Add(-age), AvatarEmoji: "🖥️",
		InternetDeviceID: "pc-cloud", SupportsDeliveryAck: true,
	}}, lanDevices: make(map[string]*models.LANDevice)}
}

func TestQuietTrayPeerStaysOnlineWhenAppHelloResponds(t *testing.T) {
	ds := presenceDiscovery(t, time.Minute)
	ds.refreshPeerPresence(time.Now(), func(p models.Peer) (models.WireHeader, error) {
		return models.WireHeader{Type: "hello", SenderID: p.ID, Sender: p.Name, SupportsDeliveryAck: true}, nil
	})
	p := ds.GetPeers()[0]
	if !p.IsOnline || time.Since(p.LastSeen) > time.Second || p.AvatarEmoji != "🖥️" || p.InternetDeviceID != "pc-cloud" || !p.SupportsDeliveryAck {
		t.Fatalf("quiet desktop lost presence or identity: %+v", p)
	}
}

func TestFailedProbeExpiresPeerAndLaterHelloRecoversIt(t *testing.T) {
	ds := presenceDiscovery(t, time.Minute)
	ds.refreshPeerPresence(time.Now(), func(models.Peer) (models.WireHeader, error) { return models.WireHeader{}, errors.New("app closed") })
	if ds.GetPeers()[0].IsOnline {
		t.Fatal("closed app still online")
	}
	ds.refreshPeerPresence(time.Now(), func(p models.Peer) (models.WireHeader, error) {
		return models.WireHeader{Type: "hello", SenderID: p.ID, Sender: p.Name}, nil
	})
	if !ds.GetPeers()[0].IsOnline {
		t.Fatal("tray app did not recover")
	}
}

func TestBriefBeaconGapDoesNotImmediatelyGoOffline(t *testing.T) {
	ds := presenceDiscovery(t, 12*time.Second)
	ds.refreshPeerPresence(time.Now(), func(models.Peer) (models.WireHeader, error) {
		return models.WireHeader{}, errors.New("temporary failure")
	})
	if !ds.GetPeers()[0].IsOnline {
		t.Fatal("short beacon gap caused offline flicker")
	}
}

func TestBeaconDuringFailedProbeWinsOverOldSnapshot(t *testing.T) {
	ds := presenceDiscovery(t, time.Minute)
	ds.refreshPeerPresence(time.Now(), func(p models.Peer) (models.WireHeader, error) {
		ds.RegisterPeer(p.ID, p.Name, p.IP, p.Port, false)
		return models.WireHeader{}, errors.New("probe failed")
	})
	if !ds.GetPeers()[0].IsOnline {
		t.Fatal("fresh beacon overwritten by stale probe")
	}
}

func TestRecentBeaconNeedsNoTCPProbe(t *testing.T) {
	ds := presenceDiscovery(t, time.Second)
	ds.refreshPeerPresence(time.Now(), func(models.Peer) (models.WireHeader, error) {
		t.Error("recent beacon was probed")
		return models.WireHeader{}, nil
	})
}

func TestLegacyBeaconKeepsCloudIdentityLearnedFromHello(t *testing.T) {
	ds := presenceDiscovery(t, time.Second)
	packet, err := json.Marshal(models.WireHeader{Type: "discover", SenderID: "pc", Sender: "Office"})
	if err != nil {
		t.Fatal(err)
	}
	ds.handleBeacon(packet, "203.0.113.7")
	if ds.GetPeers()[0].InternetDeviceID != "pc-cloud" {
		t.Fatal("UDP beacon erased the known LAN/WAN identity link")
	}
}

func TestHelloReadsFragmentedResponseAndRejectsUnrelatedService(t *testing.T) {
	for _, valid := range []bool{true, false} {
		client, server := net.Pipe()
		done := make(chan struct{})
		go func() {
			defer close(done)
			defer server.Close()
			var request models.WireHeader
			if err := json.NewDecoder(server).Decode(&request); err != nil {
				return
			}
			if valid {
				_, _ = server.Write([]byte(`{"type":"hello","sender_`))
				_, _ = server.Write([]byte("id\":\"pc\",\"avatar_emoji\":\"🖥️\"}\n"))
			} else {
				_, _ = server.Write([]byte("{\"type\":\"other\",\"id\":\"pc\"}\n"))
			}
		}()
		h, err := exchangePeerHello(client)
		client.Close()
		<-done
		if valid && (err != nil || helloID(h) != "pc" || helloAvatar(h) != "🖥️") {
			t.Fatalf("fragmented hello: %+v %v", h, err)
		}
		if !valid && err == nil {
			t.Fatal("unrelated service accepted as running app")
		}
	}
}
