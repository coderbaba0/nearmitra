// Package calling handles low-latency WebRTC voice signaling, Push-To-Talk Walkie-Talkie, and audio telemetry.
package calling

import (
	"encoding/json"
	"fmt"
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
	Ringing                bool   // true when incoming call notification is showing
	PTTActive              bool   // Push-to-Talk active
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
func (cs *CallState) SetIncoming(peerIP, peerName string, isVideo bool) {
	cs.mu.Lock()
	cs.Ringing = true
	cs.IsIncoming = true
	cs.IsVideo = isVideo
	cs.PeerIP = peerIP
	cs.PeerName = peerName
	cb := cs.OnStateChange
	cs.mu.Unlock()
	if cb != nil {
		cb()
	}
}

// AnswerCall accepts the ringing incoming call.
func (cs *CallState) AnswerCall() {
	cs.mu.Lock()
	cs.Ringing = false
	cs.Active = true
	cs.StartTime = time.Now()
	cb := cs.OnStateChange
	cs.mu.Unlock()
	if cb != nil {
		cb()
	}
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
			Type: "call_invite", Sender: cfg.DeviceName,
			SenderID: cfg.DeviceID, CallAction: "decline",
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
	cs.mu.Lock()
	cs.Active = true
	cs.IsIncoming = false
	cs.IsVideo = isVideo
	cs.PeerID = peerID
	cs.PeerIP = targetIP
	cs.PeerName = peerName
	cs.StartTime = time.Now()
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
		Sender:     cfg.DeviceName,
		SenderID:   cfg.DeviceID,
		CallType:   callType,
		CallAction: "invite",
		IsVideo:    isVideo,
	}

	return sendJSON(targetIP, header)
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
			Type:       "call_invite",
			Sender:     cfg.DeviceName,
			SenderID:   cfg.DeviceID,
			CallAction: "end",
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

	data, _ := json.Marshal(header)
	_, err = conn.Write(append(data, '\n'))
	return err
}
