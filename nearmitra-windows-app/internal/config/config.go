// Package config manages application settings and persistence under %AppData%\NearMitra\config.json
package config

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"syscall"

	"nearmitra-windows-app/internal/models"
)

// AppConfig represents full persistent user preferences.
type AppConfig struct {
	DeviceID             string                         `json:"device_id"`
	DeviceName           string                         `json:"device_name"`
	AvatarEmoji          string                         `json:"avatar_emoji"`
	ThemeMode            string                         `json:"theme_mode"` // "dark", "light", "system"
	SaveDirectory        string                         `json:"save_directory"`
	AutoStart            bool                           `json:"auto_start"`
	MinimizeTray         bool                           `json:"minimize_tray"`
	NotificationsEnabled bool                           `json:"notifications_enabled"`
	AIConfig             models.AIConfig                `json:"ai_config"`
	StreamingSecurity    models.StreamingSecurityConfig `json:"streaming_security"`
}

// ConfigManager handles thread-safe loading and saving of preferences.
type ConfigManager struct {
	mu     sync.RWMutex
	config AppConfig
	path   string
}

var (
	instance *ConfigManager
	once     sync.Once
)

// Get returns the singleton ConfigManager instance.
func Get() *ConfigManager {
	once.Do(func() {
		appData := os.Getenv("APPDATA")
		if appData == "" {
			appData = "."
		}
		dir := filepath.Join(appData, "NearMitra")
		_ = os.MkdirAll(dir, 0755)

		downloadsDir := filepath.Join(os.Getenv("USERPROFILE"), "Downloads", "NearMitra")
		_ = os.MkdirAll(downloadsDir, 0755)

		cm := &ConfigManager{
			path: filepath.Join(dir, "config.json"),
			config: AppConfig{
				AvatarEmoji:          "💻",
				ThemeMode:            "dark",
				SaveDirectory:        downloadsDir,
				AutoStart:            false,
				MinimizeTray:         true,
				NotificationsEnabled: true,
				AIConfig: models.AIConfig{
					Enabled:      true,
					ShareAI:      false,
					Provider:     "gemini",
					GeminiModel:  "gemini-2.0-flash",
					OpenAIModel:  "gpt-4o-mini",
					OllamaURL:    "http://127.0.0.1:11434",
					OllamaModel:  "qwen2.5:latest",
					Temperature:  0.7,
					SystemPrompt: "You are NearMitra AI on Windows, a helpful and fast local assistant.",
				},
				StreamingSecurity: models.StreamingSecurityConfig{
					AllowCamera:    true,
					AllowAudio:     true,
					AllowScreen:    true,
					AlwaysTrust:    true,
					TrustedDevices: []string{},
				},
			},
		}

		cm.load()
		instance = cm
	})
	return instance
}

// load reads config from disk or initializes defaults.
func (cm *ConfigManager) load() {
	cm.mu.Lock()
	defer cm.mu.Unlock()

	data, err := os.ReadFile(cm.path)
	if err == nil {
		_ = json.Unmarshal(data, &cm.config)
	}

	if cm.config.DeviceID == "" {
		cm.config.DeviceID = generateRandomID()
	}
	if cm.config.AvatarEmoji == "" {
		cm.config.AvatarEmoji = "💻"
	}
	if cm.config.DeviceName == "" {
		hostname, err := os.Hostname()
		if err == nil && hostname != "" {
			cm.config.DeviceName = hostname
		} else {
			cm.config.DeviceName = "Windows-PC"
		}
	}
	if cm.config.SaveDirectory == "" {
		cm.config.SaveDirectory = filepath.Join(os.Getenv("USERPROFILE"), "Downloads", "NearMitra")
		_ = os.MkdirAll(cm.config.SaveDirectory, 0755)
	}

	cm.saveUnsafe()
}

// Save commits changes to disk safely.
func (cm *ConfigManager) Save() error {
	cm.mu.Lock()
	defer cm.mu.Unlock()
	return cm.saveUnsafe()
}

func (cm *ConfigManager) saveUnsafe() error {
	data, err := json.MarshalIndent(cm.config, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(cm.path, data, 0644)
}

// GetConfig returns a copy of current config.
func (cm *ConfigManager) GetConfig() AppConfig {
	cm.mu.RLock()
	defer cm.mu.RUnlock()
	return cm.config
}

// SetThemeMode updates the theme preference.
func (cm *ConfigManager) SetThemeMode(mode string) {
	cm.mu.Lock()
	cm.config.ThemeMode = mode
	cm.saveUnsafe()
	cm.mu.Unlock()
}

// SetSaveDirectory updates default received files storage folder.
func (cm *ConfigManager) SetSaveDirectory(dir string) {
	cm.mu.Lock()
	cm.config.SaveDirectory = dir
	cm.saveUnsafe()
	cm.mu.Unlock()
}

// SetDeviceName updates local broadcast node name.
func (cm *ConfigManager) SetDeviceName(name string) {
	cm.mu.Lock()
	cm.config.DeviceName = name
	cm.saveUnsafe()
	cm.mu.Unlock()
}

// SetDeviceIdentity updates local device name and avatar emoji.
func (cm *ConfigManager) SetDeviceIdentity(name, emoji string) {
	cm.mu.Lock()
	if name != "" {
		cm.config.DeviceName = name
	}
	if emoji != "" {
		cm.config.AvatarEmoji = emoji
	}
	cm.saveUnsafe()
	cm.mu.Unlock()
}

// ResetDeviceIdentity resets name and emoji to hardware defaults.
func (cm *ConfigManager) ResetDeviceIdentity() (string, string) {
	cm.mu.Lock()
	hostname, err := os.Hostname()
	if err == nil && hostname != "" {
		cm.config.DeviceName = hostname
	} else {
		cm.config.DeviceName = "Windows-PC"
	}
	cm.config.AvatarEmoji = "💻"
	cm.saveUnsafe()
	name := cm.config.DeviceName
	emoji := cm.config.AvatarEmoji
	cm.mu.Unlock()
	return name, emoji
}

// SetAIConfig updates AI provider parameters.
func (cm *ConfigManager) SetAIConfig(ai models.AIConfig) {
	cm.mu.Lock()
	cm.config.AIConfig = ai
	cm.saveUnsafe()
	cm.mu.Unlock()
}

// GetStreamingSecurity returns current media stream permissions and trusted devices.
func (cm *ConfigManager) GetStreamingSecurity() models.StreamingSecurityConfig {
	cm.mu.RLock()
	defer cm.mu.RUnlock()
	return cm.config.StreamingSecurity
}

// SetStreamingSecurity updates media stream permissions.
func (cm *ConfigManager) SetStreamingSecurity(sec models.StreamingSecurityConfig) {
	cm.mu.Lock()
	cm.config.StreamingSecurity = sec
	cm.saveUnsafe()
	cm.mu.Unlock()
}

// AddTrustedDevice adds a peer ID to always-trusted stream list.
func (cm *ConfigManager) AddTrustedDevice(peerID string) {
	cm.mu.Lock()
	defer cm.mu.Unlock()
	for _, id := range cm.config.StreamingSecurity.TrustedDevices {
		if id == peerID {
			return
		}
	}
	cm.config.StreamingSecurity.TrustedDevices = append(cm.config.StreamingSecurity.TrustedDevices, peerID)
	cm.saveUnsafe()
}

// RemoveTrustedDevice removes a peer ID from always-trusted list.
func (cm *ConfigManager) RemoveTrustedDevice(peerID string) {
	cm.mu.Lock()
	defer cm.mu.Unlock()
	filtered := make([]string, 0)
	for _, id := range cm.config.StreamingSecurity.TrustedDevices {
		if id != peerID {
			filtered = append(filtered, id)
		}
	}
	cm.config.StreamingSecurity.TrustedDevices = filtered
	cm.saveUnsafe()
}

// SetNotifications updates the user desktop notifications preference.
func (cm *ConfigManager) SetNotifications(enabled bool) {
	cm.mu.Lock()
	cm.config.NotificationsEnabled = enabled
	_ = cm.saveUnsafe()
	cm.mu.Unlock()
}

// IsNotificationsEnabled returns true if desktop notifications are active.
func (cm *ConfigManager) IsNotificationsEnabled() bool {
	cm.mu.RLock()
	defer cm.mu.RUnlock()
	return cm.config.NotificationsEnabled
}

// SetAutoStart configures Windows Registry Run key for auto-starting NearMitra.
func (cm *ConfigManager) SetAutoStart(enabled bool) error {
	cm.mu.Lock()
	cm.config.AutoStart = enabled
	_ = cm.saveUnsafe()
	cm.mu.Unlock()

	return SetWindowsAutoStart(enabled)
}

// IsAutoStartEnabled returns whether NearMitra is configured to run at startup.
func (cm *ConfigManager) IsAutoStartEnabled() bool {
	cm.mu.RLock()
	defer cm.mu.RUnlock()
	return cm.config.AutoStart || CheckWindowsAutoStart()
}

// SetWindowsAutoStart writes or removes the registry entry in HKCU\Software\Microsoft\Windows\CurrentVersion\Run.
func SetWindowsAutoStart(enabled bool) error {
	if enabled {
		exePath, err := os.Executable()
		if err != nil {
			exePath = filepath.Join(os.Getenv("LOCALAPPDATA"), "Programs", "NearMitra", "NearMitra.exe")
		}
		// Set registry key: "NearMitra" = "<exePath>" --minimized
		val := fmt.Sprintf("\"%s\" --minimized", exePath)
		cmd := exec.Command("reg", "add", "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run", "/v", "NearMitra", "/t", "REG_SZ", "/d", val, "/f")
		cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
		return cmd.Run()
	} else {
		cmd := exec.Command("reg", "delete", "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run", "/v", "NearMitra", "/f")
		cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
		return cmd.Run()
	}
}

// CheckWindowsAutoStart queries HKCU\Software\Microsoft\Windows\CurrentVersion\Run.
func CheckWindowsAutoStart() bool {
	cmd := exec.Command("reg", "query", "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run", "/v", "NearMitra")
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	err := cmd.Run()
	return err == nil
}

// Helper to generate unique 8-byte hex node ID
func generateRandomID() string {
	b := make([]byte, 4)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
