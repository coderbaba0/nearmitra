package chat

import (
	"nearmitra-windows-app/internal/models"
	"path/filepath"
	"testing"
)

func TestReactionsRemainPeerScopedAndSurviveReload(t *testing.T) {
	h := &HistoryManager{path: filepath.Join(t.TempDir(), "history.json")}
	m := models.ChatMessage{ID: "original", PeerID: "phone-wan", PeerIP: "192.168.1.6", Text: "Hello", ReplyToID: "older", ReplyToText: "Quote", ReplyToSender: "Phone", IsForwarded: true}
	if err := h.AddMessage(m); err != nil {
		t.Fatal(err)
	}
	if h.SetPeerReaction(m.ID, "❤️", "other-phone") {
		t.Fatal("unrelated peer changed the message")
	}
	if !h.SetPeerReaction(m.ID, "❤️", "phone-lan", "phone-wan") || !h.SetLocalReaction(m.ID, "👍") {
		t.Fatal("reaction not saved")
	}
	if err := h.AddMessage(m); err != nil {
		t.Fatal(err)
	}
	restored := &HistoryManager{path: h.path}
	restored.load()
	got := restored.GetMessages()[0]
	if got.Reaction != "❤️" || got.LocalReaction != "👍" || got.ReplyToID != "older" || !got.IsForwarded {
		t.Fatalf("lost state: %+v", got)
	}
	h.SetPeerReaction(m.ID, "", "192.168.1.6")
	h.SetLocalReaction(m.ID, "")
	restored.load()
	got = restored.GetMessages()[0]
	if got.Reaction != "" || got.LocalReaction != "" {
		t.Fatalf("reaction removal not saved: %+v", got)
	}
}
