package network

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"sync"
	"time"

	"nearmitra-windows-app/internal/config"
	"nearmitra-windows-app/internal/models"
)

const peerProbeAfter = 8 * time.Second
const peerOfflineAfter = 25 * time.Second

func helloID(h models.WireHeader) string {
	if h.SenderID != "" {
		return h.SenderID
	}
	return h.ID
}
func helloName(h models.WireHeader) string {
	if h.Sender != "" {
		return h.Sender
	}
	return h.Name
}
func helloAvatar(h models.WireHeader) string {
	if h.AvatarEmoji != "" {
		return h.AvatarEmoji
	}
	if h.Emoji != "" {
		return h.Emoji
	}
	return h.Avatar
}

// A listening port alone is not proof that the NearMitra app is alive.
func exchangePeerHello(conn net.Conn) (models.WireHeader, error) {
	_ = conn.SetDeadline(time.Now().Add(1500 * time.Millisecond))
	cfg := config.Get().GetConfig()
	request := models.WireHeader{Type: "hello", ID: cfg.DeviceID, SenderID: cfg.DeviceID,
		Name: cfg.DeviceName, Sender: cfg.DeviceName, InternetDeviceID: cfg.DeviceID,
		AvatarEmoji: cfg.AvatarEmoji, Avatar: cfg.AvatarEmoji, Emoji: cfg.AvatarEmoji, SupportsDeliveryAck: true}
	var response models.WireHeader
	if err := json.NewEncoder(conn).Encode(request); err != nil {
		return response, err
	}
	if err := json.NewDecoder(io.LimitReader(conn, 8192)).Decode(&response); err != nil {
		return response, err
	}
	if response.Type != "hello" || helloID(response) == "" {
		return response, fmt.Errorf("invalid NearMitra hello")
	}
	return response, nil
}

func probeNearbyPeer(peer models.Peer) (models.WireHeader, error) {
	port := peer.Port
	if port <= 0 {
		port = models.TransferPort
	}
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(peer.IP, fmt.Sprint(port)), 800*time.Millisecond)
	if err != nil {
		return models.WireHeader{}, err
	}
	defer conn.Close()
	h, err := exchangePeerHello(conn)
	if err == nil && helloID(h) != peer.ID && peer.ID != "manual_"+peer.IP && peer.ID != peer.IP {
		err = fmt.Errorf("different device at previous peer address")
	}
	return h, err
}

func (ds *DiscoveryService) registerPeerHello(h models.WireHeader, ip string) {
	id := helloID(h)
	ds.RegisterPeer(id, helloName(h), ip, models.TransferPort, h.AIHost, helloAvatar(h))
	ds.SetPeerIdentity(id, h.InternetDeviceID, h.SupportsDeliveryAck)
}

// Go workers keep running when the browser is closed or minimized to the tray.
// Confirm quiet peers through their app protocol before expiring local presence.
func (ds *DiscoveryService) refreshPeerPresence(now time.Time, probe func(models.Peer) (models.WireHeader, error)) {
	jobs := make(chan *models.Peer)
	var workers sync.WaitGroup
	for i := 0; i < 8; i++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for peer := range jobs {
				if h, err := probe(*peer); err == nil {
					ds.registerPeerHello(h, peer.IP)
				}
			}
		}()
	}
	for _, peer := range ds.GetPeers() {
		if now.Sub(peer.LastSeen) >= peerProbeAfter {
			jobs <- peer
		}
	}
	close(jobs)
	workers.Wait()
	ds.mu.Lock()
	changed := false
	for _, peer := range ds.peers {
		// Recheck current LastSeen: a beacon may arrive while a TCP probe fails.
		if peer.IsOnline && now.Sub(peer.LastSeen) >= peerOfflineAfter {
			peer.IsOnline = false
			changed = true
		}
	}
	cb, snapshot := ds.onPeerUpdate, ds.getPeersUnsafe()
	ds.mu.Unlock()
	if changed && cb != nil {
		cb(snapshot)
	}
}
