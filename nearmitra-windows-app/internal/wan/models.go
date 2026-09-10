// Package wan implements Internet / WAN Remote Discovery, Privacy Modes (Public Radar, Ghost, PIN Only), and Firebase Realtime Database mesh.
package wan

import "time"

// WanDiscoveryMode defines the visibility policy on the Internet WAN mesh.
type WanDiscoveryMode string

const (
	ModePublicRadar  WanDiscoveryMode = "publicRadar"  // Visible to all worldwide peers on WAN Radar
	ModePrivateGhost WanDiscoveryMode = "privateGhost" // Hidden from public discovery, visible only to trusted paired devices
	ModePinOnly      WanDiscoveryMode = "pinOnly"      // Hidden from public discovery, connects only with 6-digit PIN code
)

// WanDevice represents a discovered or trusted remote device over the Internet.
type WanDevice struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Platform    string    `json:"platform"`
	AvatarEmoji string    `json:"avatar_emoji"`
	IsOnline    bool      `json:"is_online"`
	LastSeen    time.Time `json:"last_seen"`
	IsTrusted   bool      `json:"is_trusted"`
	UnreadCount int       `json:"unread_count"`
}

// WanPairCode represents a temporary 6-digit PIN pairing code.
type WanPairCode struct {
	Code          string `json:"code"`
	OwnerDeviceID string `json:"owner_device_id"`
	OwnerName     string `json:"owner_name"`
	Platform      string `json:"platform"`
	CreatedAt     int64  `json:"created_at"`
	ExpiresAt     int64  `json:"expires_at"`
	Used          bool   `json:"used"`
}

// WanPairRequest represents a pairing invitation sent over Firebase RTDB.
type WanPairRequest struct {
	RequestID       string    `json:"request_id"`
	FromDeviceID    string    `json:"from_device_id"`
	FromDeviceName  string    `json:"from_device_name"`
	FromPlatform    string    `json:"from_platform"`
	FromAvatarEmoji string    `json:"from_avatar_emoji"`
	ToDeviceID      string    `json:"to_device_id"`
	Code            string    `json:"code"`
	Status          string    `json:"status"` // "pending", "accepted", "rejected"
	IsDirectRadar   bool      `json:"is_direct_radar"`
	CreatedAt       time.Time `json:"created_at"`
}

// WanConfig represents local persistent configuration for WAN settings.
type WanConfig struct {
	InternetModeEnabled bool             `json:"internet_mode_enabled"`
	DiscoveryMode       WanDiscoveryMode `json:"discovery_mode"`
	FirebaseRTDBUrl     string           `json:"firebase_rtdb_url"`
}

// WanState represents the complete runtime snapshot returned to the frontend.
type WanState struct {
	InternetModeEnabled bool              `json:"internet_mode_enabled"`
	DiscoveryMode       WanDiscoveryMode  `json:"discovery_mode"`
	IsFirebaseConnected bool              `json:"is_firebase_connected"`
	IsPresenceOnline    bool              `json:"is_presence_online"`
	MyDeviceID          string            `json:"my_device_id"`
	MyDeviceName        string            `json:"my_device_name"`
	MyAvatarEmoji       string            `json:"my_avatar_emoji"`
	PublicDevices       []*WanDevice      `json:"public_devices"`
	TrustedDevices      []*WanDevice      `json:"trusted_devices"`
	ActivePairCode      *WanPairCode      `json:"active_pair_code,omitempty"`
	PendingRequests     []*WanPairRequest `json:"pending_requests"`
}
