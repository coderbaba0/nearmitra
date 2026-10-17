// Package models defines all core domain structs and wire protocol payloads for NearMitra Windows.
package models

import (
	"time"
)

// App Constants
const (
	AppName      = "NearMitra"
	DiscoverPort = 43888
	TransferPort = 43889
	MulticastIP  = "239.255.43.88"
)

// HardwareComputeInfo represents distributed edge AI capabilities advertised over local network.
type HardwareComputeInfo struct {
	Device       string   `json:"device,omitempty"`
	RAM          string   `json:"ram,omitempty"`
	GPU          string   `json:"gpu,omitempty"`
	AIModels     []string `json:"ai_models,omitempty"`
	Capabilities []string `json:"capabilities,omitempty"`
	LoadPercent  int      `json:"load,omitempty"`
}

// LANDevice represents any physical hardware node discovered on the local LAN subnet.
type LANDevice struct {
	IP          string    `json:"ip"`
	Hostname    string    `json:"hostname"`
	MAC         string    `json:"mac"`
	Vendor      string    `json:"vendor"`
	DeviceType  string    `json:"device_type"` // phone, computer, router, printer, iot, camera, generic
	PingMs      int       `json:"ping_ms"`
	OpenPorts   []int     `json:"open_ports"`
	IsNearMitra bool      `json:"is_nearmitra"`
	AvatarEmoji string    `json:"avatar_emoji,omitempty"`
	LastSeen    time.Time `json:"last_seen"`
}

// Peer represents a discovered nearby network node.
type Peer struct {
	InternetDeviceID    string              `json:"internet_device_id,omitempty"`
	SupportsDeliveryAck bool                `json:"delivery_ack,omitempty"`
	ID                  string              `json:"id"`
	Name                string              `json:"name"`
	IP                  string              `json:"ip,omitempty"`
	Port                int                 `json:"port,omitempty"`
	LastSeen            time.Time           `json:"-"`
	IsOnline            bool                `json:"is_online"`
	AvatarEmoji         string              `json:"avatar_emoji,omitempty"`
	IsAiHost            bool                `json:"ai_host,omitempty"`
	AIProvider          string              `json:"ai_provider,omitempty"`
	AIModel             string              `json:"ai_model,omitempty"`
	ComputeInfo         HardwareComputeInfo `json:"compute_info,omitempty"`
	IsTyping            bool                `json:"-"`
	UnreadCount         int                 `json:"-"`
	IsAiAllowed         bool                `json:"-"`
}

// WireHeader represents standard protocol packet header for TCP & UDP exchanges.
type WireHeader struct {
	InternetDeviceID    string              `json:"internet_device_id,omitempty"`
	SupportsDeliveryAck bool                `json:"delivery_ack,omitempty"`
	RequireAck          bool                `json:"require_ack,omitempty"`
	Error               string              `json:"error,omitempty"`
	Type                string              `json:"type,omitempty"` // discover, hello, chat, text, typing, reaction, file, folder, ai_request, ai_response, call_invite, call_accepted, call_declined, call_ended, webrtc_offer, webrtc_answer, webrtc_ice, cctv_ctrl
	ID                  string              `json:"id,omitempty"`   // mobile UDP discovery identifier
	Name                string              `json:"name,omitempty"` // mobile UDP discovery name or file name
	AvatarEmoji         string              `json:"avatar_emoji,omitempty"`
	Emoji               string              `json:"emoji,omitempty"`
	Avatar              string              `json:"avatar,omitempty"`
	Sender              string              `json:"sender,omitempty"`
	SenderID            string              `json:"sender_id,omitempty"`
	Message             string              `json:"message,omitempty"`
	Text                string              `json:"text,omitempty"`
	Prompt              string              `json:"prompt,omitempty"`
	Reply               string              `json:"reply,omitempty"`
	Status              string              `json:"status,omitempty"`
	Size                int64               `json:"size,omitempty"`
	Folder              bool                `json:"folder,omitempty"`
	Checksum            string              `json:"checksum,omitempty"`
	Reaction            string              `json:"reaction,omitempty"`
	MsgID               string              `json:"msg_id,omitempty"`
	TargetMsgID         string              `json:"target_msg_id,omitempty"`
	IsTyping            bool                `json:"is_typing,omitempty"`
	IsVideo             bool                `json:"is_video,omitempty"`
	AIHost              bool                `json:"ai_host,omitempty"`
	Provider            string              `json:"provider,omitempty"`
	Model               string              `json:"model,omitempty"`
	ComputeInfo         HardwareComputeInfo `json:"compute_info,omitempty"`
	Done                bool                `json:"done,omitempty"`
	CallType            string              `json:"call_type,omitempty"`   // audio, video
	CallAction          string              `json:"call_action,omitempty"` // invite, accept, decline, end
	CctvAction          string              `json:"cctv_action,omitempty"` // torch_on, torch_off, flip_camera, mute_mic, reset
	// WebRTC Stream & Call Signaling Fields (matching Flutter Mobile App)
	SDP         string      `json:"sdp,omitempty"`
	SDPType     string      `json:"sdp_type,omitempty"`    // offer, answer
	StreamType  string      `json:"stream_type,omitempty"` // camera, audio
	AudioMode   string      `json:"audio_mode,omitempty"`  // mic, listen
	Action      string      `json:"action,omitempty"`      // toggle_torch, switch_camera, toggle_mic, torch_status
	Value       interface{} `json:"value,omitempty"`       // boolean or string value
	Candidate   string      `json:"candidate,omitempty"`
	SDPMid      string      `json:"sdp_mid,omitempty"`
	SDPMLineIdx int         `json:"sdp_mline_index,omitempty"`
	Reason      string      `json:"reason,omitempty"`
}

// ChatMessage represents a persistent or in-memory chat message.
type ChatMessage struct {
	ID         string      `json:"id"`
	PeerID     string      `json:"peer_id"`
	PeerIP     string      `json:"peer_ip,omitempty"`
	Sender     string      `json:"sender"`
	Text       string      `json:"text"`
	Mine       bool        `json:"mine"`
	At         time.Time   `json:"at"`
	Kind       string      `json:"kind"` // text, file, folder, ai
	FileName   string      `json:"file_name,omitempty"`
	FileSize   int64       `json:"file_size,omitempty"`
	FilePath   string      `json:"file_path,omitempty"`
	Status     string      `json:"status,omitempty"` // Sending, Sent, Delivered, Failed
	Reaction   string      `json:"reaction,omitempty"`
	IsAi       bool        `json:"is_ai,omitempty"`
	IsWan      bool        `json:"is_wan,omitempty"`
	Attachment interface{} `json:"attachment,omitempty"`
}

// TransferProgress represents active socket file transfer stats.
type TransferProgress struct {
	Active     bool
	Direction  string // "upload" or "download"
	PeerName   string
	FileName   string
	BytesTotal int64
	BytesSent  int64
	SpeedMBps  float64
	StartTime  time.Time
	Complete   bool
	Error      string
}

// AIConfig stores AI preferences and local host parameters.
type AIConfig struct {
	Enabled      bool     `json:"enabled"`
	ShareAI      bool     `json:"share_ai"`
	AllowedPeers []string `json:"allowed_peers"`
	RevokedPeers []string `json:"revoked_peers"`
	Provider     string   `json:"provider"` // gemini, openai, groq, ollama
	GeminiModel  string   `json:"gemini_model"`
	GeminiAPIKey string   `json:"gemini_api_key"`
	OpenAIModel  string   `json:"openai_model"`
	OpenAIAPIKey string   `json:"openai_api_key"`
	GroqModel    string   `json:"groq_model"`
	GroqAPIKey   string   `json:"groq_api_key"`
	OllamaURL    string   `json:"ollama_url"`
	OllamaModel  string   `json:"ollama_model"`
	Temperature  float64  `json:"temperature"`
	SystemPrompt string   `json:"system_prompt"`
}

// StreamingSecurityConfig manages local P2P stream permissions and always-trusted peers.
type StreamingSecurityConfig struct {
	AllowCamera    bool     `json:"allow_camera"`
	AllowAudio     bool     `json:"allow_audio"`
	AllowScreen    bool     `json:"allow_screen"`
	AlwaysTrust    bool     `json:"always_trust"`
	TrustedDevices []string `json:"trusted_devices"`
}

// RouterInfo holds local Wi-Fi interface and radar telemetry.
type RouterInfo struct {
	Interface       string
	Description     string
	IPv4            string
	Gateway         string
	DNS             string
	MAC             string
	LinkSpeed       string
	SSID            string
	BSSID           string
	SignalPercent   string
	RxRate          string
	TxRate          string
	Neighbors       int
	RouterReachable bool
	Updated         time.Time
}

// ActivityLogEntry records audit logs for files, calls, streams, and AI queries.
type ActivityLogEntry struct {
	ID        string    `json:"id"`
	Type      string    `json:"type"` // "file", "call", "stream", "ai", "system"
	Title     string    `json:"title"`
	Detail    string    `json:"detail"`
	PeerName  string    `json:"peer_name"`
	Timestamp time.Time `json:"timestamp"`
	Success   bool      `json:"success"`
}
