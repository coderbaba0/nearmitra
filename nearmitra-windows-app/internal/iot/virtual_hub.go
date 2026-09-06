// Package iot provides virtual hardware bridging (Audio Cast, Remote Mic, Virtual Cam, ESC/POS printing, and NFC).
package iot

import (
	"fmt"
	"net"
	"sync"
	"time"
)

// VirtualBridgeState tracks active hardware links with network peers.
type VirtualBridgeState struct {
	mu sync.RWMutex

	// Audio Cast to Remote Speaker
	AudioCastActive    bool    `json:"audio_cast_active"`
	AudioCastPeer      string  `json:"audio_cast_peer"`
	AudioCastPeerIP    string  `json:"audio_cast_peer_ip"`
	AudioCastTrack     string  `json:"audio_cast_track"`
	AudioCastVolume    float64 `json:"audio_cast_volume"`
	AudioCastPlaying   bool    `json:"audio_cast_playing"`

	// Remote Phone Microphone Bridge
	RemoteMicActive    bool    `json:"remote_mic_active"`
	RemoteMicPeer      string  `json:"remote_mic_peer"`
	RemoteMicPeerIP    string  `json:"remote_mic_peer_ip"`
	RemoteMicLevel     int     `json:"remote_mic_level"` // 0 - 100

	// Remote Phone Camera Bridge
	RemoteCamActive    bool    `json:"remote_cam_active"`
	RemoteCamPeer      string  `json:"remote_cam_peer"`
	RemoteCamPeerIP    string  `json:"remote_cam_peer_ip"`

	// NFC Reader / Emulation
	LastNFCTagID       string  `json:"last_nfc_tag_id"`
	LastNFCData        string  `json:"last_nfc_data"`
	NFCReadTimestamp   time.Time `json:"nfc_read_timestamp"`
}

var globalVirtualBridge = &VirtualBridgeState{
	AudioCastVolume: 0.85,
}

// GetVirtualBridgeState returns current hardware bridge statuses.
func GetVirtualBridgeState() VirtualBridgeState {
	globalVirtualBridge.mu.RLock()
	defer globalVirtualBridge.mu.RUnlock()
	return *globalVirtualBridge
}

// StartAudioCast begins casting music/sound to remote peer speaker.
func StartAudioCast(peerName string, peerIP string, trackTitle string, volume float64) error {
	globalVirtualBridge.mu.Lock()
	globalVirtualBridge.AudioCastActive = true
	globalVirtualBridge.AudioCastPeer = peerName
	globalVirtualBridge.AudioCastPeerIP = peerIP
	globalVirtualBridge.AudioCastTrack = trackTitle
	globalVirtualBridge.AudioCastVolume = volume
	globalVirtualBridge.AudioCastPlaying = true
	globalVirtualBridge.mu.Unlock()

	if peerIP != "" {
		_ = CastAudioToPeer(peerIP, "play", trackTitle, volume)
	}
	return nil
}

// StopAudioCast stops casting audio to remote peer.
func StopAudioCast() {
	globalVirtualBridge.mu.Lock()
	peerIP := globalVirtualBridge.AudioCastPeerIP
	globalVirtualBridge.AudioCastActive = false
	globalVirtualBridge.AudioCastPlaying = false
	globalVirtualBridge.mu.Unlock()

	if peerIP != "" {
		_ = CastAudioToPeer(peerIP, "stop", "", 0)
	}
}

// ToggleRemoteMic links or unlinks remote phone's microphone to host PC.
func ToggleRemoteMic(peerName string, peerIP string, active bool) {
	globalVirtualBridge.mu.Lock()
	defer globalVirtualBridge.mu.Unlock()
	globalVirtualBridge.RemoteMicActive = active
	globalVirtualBridge.RemoteMicPeer = peerName
	globalVirtualBridge.RemoteMicPeerIP = peerIP
	if active {
		globalVirtualBridge.RemoteMicLevel = 65
	} else {
		globalVirtualBridge.RemoteMicLevel = 0
	}
}

// ToggleRemoteCam links or unlinks remote phone's camera lens to host PC.
func ToggleRemoteCam(peerName string, peerIP string, active bool) {
	globalVirtualBridge.mu.Lock()
	defer globalVirtualBridge.mu.Unlock()
	globalVirtualBridge.RemoteCamActive = active
	globalVirtualBridge.RemoteCamPeer = peerName
	globalVirtualBridge.RemoteCamPeerIP = peerIP
}

// GenerateSampleGatePassReceipt creates a standardized ESC/POS receipt for thermal printers.
func GenerateSampleGatePassReceipt(farmerName string, cropType string, weightKg float64, mandiRate float64) []byte {
	var buf []byte
	// ESC @ (Initialize Printer)
	buf = append(buf, 0x1B, 0x40)
	// ESC a 1 (Center Align)
	buf = append(buf, 0x1B, 0x61, 0x01)
	// Bold ON
	buf = append(buf, 0x1B, 0x45, 0x01)
	buf = append(buf, []byte("================================\n")...)
	buf = append(buf, []byte("      NEARMITRA KRISHI MANDI    \n")...)
	buf = append(buf, []byte("     GATE PASS & DISPATCH SLIP  \n")...)
	buf = append(buf, []byte("================================\n")...)
	// Bold OFF
	buf = append(buf, 0x1B, 0x45, 0x00)
	// Left Align
	buf = append(buf, 0x1B, 0x61, 0x00)
	buf = append(buf, []byte(fmt.Sprintf("Date:      %s\n", time.Now().Format("02-01-2006 15:04")))...)
	buf = append(buf, []byte(fmt.Sprintf("Pass ID:   GP-%d\n", time.Now().Unix()%100000))...)
	buf = append(buf, []byte(fmt.Sprintf("Farmer:    %s\n", farmerName))...)
	buf = append(buf, []byte(fmt.Sprintf("Produce:   %s\n", cropType))...)
	buf = append(buf, []byte(fmt.Sprintf("Quantity:  %.2f Quintals\n", weightKg/100))...)
	buf = append(buf, []byte(fmt.Sprintf("MSP Rate:  Rs. %.2f / Qtl\n", mandiRate))...)
	buf = append(buf, []byte("--------------------------------\n")...)
	total := (weightKg / 100) * mandiRate
	buf = append(buf, []byte(fmt.Sprintf("TOTAL VAL: Rs. %.2f\n", total))...)
	buf = append(buf, []byte("--------------------------------\n")...)
	// Center Align & Barcode/QR
	buf = append(buf, 0x1B, 0x61, 0x01)
	buf = append(buf, []byte("Scan QR on Mobile for e-Payment\n\n")...)
	buf = append(buf, []byte("  [ QR: NEARMITRA-PAY-DIRECT ]  \n\n\n")...)
	// Paper Cut (GS V 66 0)
	buf = append(buf, 0x1D, 0x56, 0x42, 0x00)
	return buf
}

// SendRawToLANPrinter sends ESC/POS byte stream to a network thermal printer.
func SendRawToLANPrinter(printerIP string, port int, data []byte) error {
	if port <= 0 {
		port = 9100
	}
	conn, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", printerIP, port), 4*time.Second)
	if err != nil {
		return err
	}
	defer conn.Close()
	_, err = conn.Write(data)
	return err
}
