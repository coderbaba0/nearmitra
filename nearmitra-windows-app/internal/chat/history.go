// Package chat manages chat message history persistence, reactions, and conversational querying.
package chat

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"time"

	"nearmitra-windows-app/internal/models"
)

// HistoryManager provides thread-safe chat storage and search.
type HistoryManager struct {
	mu       sync.RWMutex
	messages []models.ChatMessage
	path     string
}

var (
	historyInstance *HistoryManager
	historyOnce     sync.Once
)

// GetHistory returns singleton HistoryManager.
func GetHistory() *HistoryManager {
	historyOnce.Do(func() {
		appData := os.Getenv("APPDATA")
		if appData == "" {
			appData = "."
		}
		dir := filepath.Join(appData, "NearMitra")
		_ = os.MkdirAll(dir, 0755)

		hm := &HistoryManager{
			path:     filepath.Join(dir, "chat_history.json"),
			messages: make([]models.ChatMessage, 0),
		}
		hm.load()
		historyInstance = hm
	})
	return historyInstance
}

func (hm *HistoryManager) load() {
	hm.mu.Lock()
	defer hm.mu.Unlock()

	data, err := os.ReadFile(hm.path)
	if err == nil {
		_ = json.Unmarshal(data, &hm.messages)
	}
}

func (hm *HistoryManager) saveUnsafe() error {
	data, err := json.MarshalIndent(hm.messages, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(hm.path, data, 0644)
}

// AddMessage appends a new message to history.
func (hm *HistoryManager) AddMessage(msg models.ChatMessage) {
	hm.mu.Lock()
	if msg.At.IsZero() {
		msg.At = time.Now()
	}
	hm.messages = append(hm.messages, msg)
	_ = hm.saveUnsafe()
	hm.mu.Unlock()
}

// AddReaction updates or sets reaction on a targeted message.
func (hm *HistoryManager) AddReaction(msgID string, emoji string) bool {
	return hm.SetReaction(msgID, emoji)
}

// GetMessages returns all chat messages.
func (hm *HistoryManager) GetMessages() []models.ChatMessage {
	hm.mu.RLock()
	defer hm.mu.RUnlock()
	res := make([]models.ChatMessage, len(hm.messages))
	copy(res, hm.messages)
	return res
}

// SetReaction updates reaction on a targeted message.
func (hm *HistoryManager) SetReaction(msgID string, emoji string) bool {
	hm.mu.Lock()
	defer hm.mu.Unlock()

	for i := range hm.messages {
		if hm.messages[i].ID == msgID {
			hm.messages[i].Reaction = emoji
			_ = hm.saveUnsafe()
			return true
		}
	}
	return false
}

// GetMessagesForPeer retrieves conversation messages for a specific peer ID or IP.
func (hm *HistoryManager) GetMessagesForPeer(peerID string, peerIP string, isAI bool) []models.ChatMessage {
	hm.mu.RLock()
	defer hm.mu.RUnlock()

	var result []models.ChatMessage
	for _, m := range hm.messages {
		if (m.PeerID == peerID || (peerIP != "" && m.PeerID == peerIP)) && m.IsAi == isAI {
			result = append(result, m)
		}
	}
	return result
}

// ClearChat removes conversation messages with a peer.
func (hm *HistoryManager) ClearChat(peerID string, peerIP string) {
	hm.mu.Lock()
	defer hm.mu.Unlock()

	filtered := make([]models.ChatMessage, 0, len(hm.messages))
	for _, m := range hm.messages {
		if m.PeerID != peerID && (peerIP == "" || m.PeerID != peerIP) {
			filtered = append(filtered, m)
		}
	}
	hm.messages = filtered
	_ = hm.saveUnsafe()
}
