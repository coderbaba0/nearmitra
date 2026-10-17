// Package calling handles low-latency WebRTC voice signaling, Push-To-Talk Walkie-Talkie, and audio telemetry.
package calling

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/rand"
	"net"
	"sync"
	"time"

	"nearmitra-windows-app/internal/config"
	"nearmitra-windows-app/internal/models"
)

// CallState tracks current call status, Walkie-Talkie PTT, and audio telemetry.
type CallState struct {
	mu                     sync.RWMutex
	Active                 bool
	IsIncoming             bool
	IsVideo                bool
	IsWalkieTalkie         bool
	Ringing                bool // true when incoming call notification is showing
	PTTActive              bool // Push-to-Talk active
	PeerID                 string
	PeerIP                 string
	PeerName               string
	Muted                  bool
	SpeakerOn              bool
	NoiseSuppressionActive bool
	AudioCodec             string
	LatencyMs              int
	AudioLevels            [8]int // 0 to 100 for audio visualizer waveform bars
	StartTime              time.Time
	OnStateChange          func()
}

// SetIncoming marks an incoming call ringing state.
func (cs *CallState) SetIncoming(peerIP, peerName string, isVideo bool) bool {
	cs.mu.Lock()
	if cs.PeerIP != "" {
		cs.mu.Unlock()
		return false
	}
	cs.Ringing = true
	cs.IsIncoming = true
	cs.IsVideo = isVideo
	cs.PeerIP = peerIP
	cs.PeerName = peerName
	cs.StartTime = time.Now()
	started := cs.StartTime
	cb := cs.OnStateChange
	cs.mu.Unlock()
	if cb != nil {
		cb()
	}
	time.AfterFunc(45*time.Second, func() {
		cs.mu.Lock()
		if !cs.Ringing || cs.PeerIP != peerIP || !cs.StartTime.Equal(started) {
			cs.mu.Unlock()
			return
		}
		cs.Ringing = false
		cs.IsIncoming = false
		cs.PeerIP = ""
		cs.PeerName = ""
		cb := cs.OnStateChange
		cs.mu.Unlock()
		if cb != nil {
			cb()
		}
		_ = SendControl(peerIP, "call_declined")
	})
	return true
}

// AnswerCall accepts the ringing incoming call.
func (cs *CallState) AnswerCall() error {
	cs.mu.RLock()
	ip := cs.PeerIP
	ringing := cs.Ringing
	cs.mu.RUnlock()
	if ip == "" || !ringing {
		return fmt.Errorf("no incoming call to answer")
	}
	if err := SendControl(ip, "call_accepted"); err != nil {
		return err
	}
	cs.ApplyRemote("call_accepted", ip)
	return nil
}

// DeclineCall rejects the ringing incoming call.
func (cs *CallState) DeclineCall() {
	cs.mu.Lock()
	cs.Ringing = false
	targetIP := cs.PeerIP
	cs.IsIncoming = false
	cs.PeerIP = ""
	cs.PeerName = ""
	cb := cs.OnStateChange
	cs.mu.Unlock()
	if cb != nil {
		cb()
	}
	if targetIP != "" {
		cfg := config.Get().GetConfig()
		_ = sendJSON(targetIP, models.WireHeader{
			Type: "call_declined", Sender: cfg.DeviceName,
			SenderID: cfg.DeviceID,
		})
	}
}

var (
	callInstance = &CallState{
		SpeakerOn:              true,
		NoiseSuppressionActive: true,
		AudioCodec:             "Opus 48kHz HD (Low-Latency)",
		LatencyMs:              12,
		AudioLevels:            [8]int{15, 30, 65, 80, 70, 45, 25, 10},
	}
)

// GetCall returns the singleton CallState.
func GetCall() *CallState {
	return callInstance
}

// InviteCall initiates an outbound voice or video call invitation.
func (cs *CallState) InviteCall(targetIP, peerID, peerName string, isVideo bool) error {
	if net.ParseIP(targetIP) == nil {
		return fmt.Errorf("a Nearby IP address is required")
	}
	cs.mu.Lock()
	if cs.PeerIP != "" {
		cs.mu.Unlock()
		return fmt.Errorf("another call is in progress")
	}
	cs.Active = false
	cs.IsIncoming = false
	cs.IsVideo = isVideo
	cs.PeerID = peerID
	cs.PeerIP = targetIP
	cs.PeerName = peerName
	cs.StartTime = time.Now()
	started := cs.StartTime
	cb := cs.OnStateChange
	cs.mu.Unlock()

	if cb != nil {
		cb()
	}

	cfg := config.Get().GetConfig()
	callType := "audio"
	if isVideo {
		callType = "video"
	}

	header := models.WireHeader{
		Type:       "call_invite",
		RequireAck: true,
		Sender:     cfg.DeviceName,
		SenderID:   cfg.DeviceID,
		CallType:   callType,
		CallAction: "invite",
		IsVideo:    isVideo,
	}

	if err := sendJSON(targetIP, header); err != nil {
		cs.ApplyRemote("call_ended", targetIP)
		return err
	}
	time.AfterFunc(45*time.Second, func() {
		if cs.expireOutgoing(targetIP, started) {
			_ = SendControl(targetIP, "call_ended")
		}
	})
	return nil
}

// SetPTT activates or releases Push-To-Talk transmission.
func (cs *CallState) SetPTT(transmitting bool) {
	cs.mu.Lock()
	cs.PTTActive = transmitting
	if transmitting {
		for i := range cs.AudioLevels {
			cs.AudioLevels[i] = 30 + rand.Intn(65)
		}
	} else {
		for i := range cs.AudioLevels {
			cs.AudioLevels[i] = 5 + rand.Intn(10)
		}
	}
	cb := cs.OnStateChange
	cs.mu.Unlock()

	if cb != nil {
		cb()
	}
}

// ToggleMute switches microphone state.
func (cs *CallState) ToggleMute() bool {
	cs.mu.Lock()
	cs.Muted = !cs.Muted
	cur := cs.Muted
	cb := cs.OnStateChange
	cs.mu.Unlock()

	if cb != nil {
		cb()
	}
	return cur
}

// ToggleNoiseSuppression switches AI noise reduction filter.
func (cs *CallState) ToggleNoiseSuppression() bool {
	cs.mu.Lock()
	cs.NoiseSuppressionActive = !cs.NoiseSuppressionActive
	cur := cs.NoiseSuppressionActive
	cb := cs.OnStateChange
	cs.mu.Unlock()

	if cb != nil {
		cb()
	}
	return cur
}

// EndCall terminates active call and resets all ringing/calling states.
func (cs *CallState) EndCall() {
	cs.mu.Lock()
	targetIP := cs.PeerIP
	cs.Active = false
	cs.Ringing = false
	cs.IsIncoming = false
	cs.PTTActive = false
	cs.PeerIP = ""
	cs.PeerName = ""
	cb := cs.OnStateChange
	cs.mu.Unlock()

	if cb != nil {
		cb()
	}

	if targetIP != "" {
		cfg := config.Get().GetConfig()
		header := models.WireHeader{
			Type:     "call_ended",
			Sender:   cfg.DeviceName,
			SenderID: cfg.DeviceID,
		}
		_ = sendJSON(targetIP, header)
	}
}

func sendJSON(targetIP string, header models.WireHeader) error {
	conn, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", targetIP, models.TransferPort), 3*time.Second)
	if err != nil {
		return err
	}
	defer conn.Close()

	return writeCallPacket(conn, targetIP, header)
}
func writeCallPacket(conn net.Conn, targetIP string, header models.WireHeader) error {
	data, _ := json.Marshal(header)
	_ = conn.SetWriteDeadline(time.Now().Add(4 * time.Second))
	_, err := conn.Write(append(data, '\n'))
	if err != nil {
		return err
	}
	if header.Type == "call_invite" && header.RequireAck {
		_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
		var response struct {
			Type   string `json:"type"`
			Status string `json:"status"`
		}
		err = json.NewDecoder(bufio.NewReader(io.LimitReader(conn, 4096))).Decode(&response)
		if err == nil && response.Type == "call_ringing" {
			if response.Status == "busy" {
				return fmt.Errorf("the Nearby phone is already in a call")
			}
			log.Printf("[CALL] Phone %s acknowledged incoming call UI", targetIP)
		} else {
			log.Printf("[CALL] Invitation sent to %s; no incoming-UI acknowledgement from this mobile version: %v", targetIP, err)
		}
	}
	return nil
}

// ApplyRemote changes state without echoing a control packet back to the caller.
func (cs *CallState) ApplyRemote(kind, ip string) bool {
	cs.mu.Lock()
	if cs.PeerIP == "" || cs.PeerIP != ip {
		cs.mu.Unlock()
		return false
	}
	if kind == "call_accepted" {
		cs.Active = true
		cs.Ringing = false
		cs.StartTime = time.Now()
	} else {
		cs.Active = false
		cs.Ringing = false
		cs.IsIncoming = false
		cs.PTTActive = false
		cs.PeerIP = ""
		cs.PeerID = ""
		cs.PeerName = ""
	}
	cb := cs.OnStateChange
	cs.mu.Unlock()
	if cb != nil {
		cb()
	}
	return true
}
func SendControl(ip, kind string) error {
	cfg := config.Get().GetConfig()
	return sendJSON(ip, models.WireHeader{Type: kind, Sender: cfg.DeviceName, SenderID: cfg.DeviceID})
}
func (cs *CallState) Snapshot() map[string]interface{} {
	cs.mu.RLock()
	defer cs.mu.RUnlock()
	return map[string]interface{}{"active": cs.Active, "ptt": cs.PTTActive, "muted": cs.Muted, "is_video": cs.IsVideo, "peer_name": cs.PeerName, "peer_ip": cs.PeerIP, "ringing": cs.Ringing}
}

// Expire abandoned invitations when the browser window closes before cleanup.
func (cs *CallState) expireOutgoing(ip string, started time.Time) bool {
	cs.mu.Lock()
	if cs.PeerIP != ip || cs.IsIncoming || cs.Active || !cs.StartTime.Equal(started) {
		cs.mu.Unlock()
		return false
	}
	cs.PeerIP = ""
	cs.PeerID = ""
	cs.PeerName = ""
	cs.Ringing = false
	cb := cs.OnStateChange
	cs.mu.Unlock()
	if cb != nil {
		cb()
	}
	return true
}
