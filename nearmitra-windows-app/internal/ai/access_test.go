package ai

import (
	"encoding/json"
	"nearmitra-windows-app/internal/config"
	"nearmitra-windows-app/internal/models"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestSharedPermissionPolicy(t *testing.T) {
	cfg := models.AIConfig{Enabled: true, ShareAI: true}
	if ok, _ := SharedAccess(cfg, "phone"); ok {
		t.Fatal("ungranted device allowed")
	}
	cfg.AllowedPeers = []string{"wan-phone"}
	if ok, _ := SharedAccess(cfg, "lan-phone", "wan-phone", "192.0.2.3"); !ok {
		t.Fatal("stable alias grant ignored")
	}
	cfg.RevokedPeers = []string{"lan-phone"}
	if ok, _ := SharedAccess(cfg, "lan-phone", "wan-phone"); ok {
		t.Fatal("revoke ignored")
	}
	cfg.RevokedPeers = nil
	cfg.ShareAI = false
	if ok, _ := SharedAccess(cfg, "wan-phone"); ok {
		t.Fatal("sharing disabled but remote allowed")
	}
	cfg.ShareAI = true
	cfg.Enabled = false
	if ok, _ := SharedAccess(cfg, "wan-phone"); ok {
		t.Fatal("disabled engine allowed")
	}
}
func TestRemotePromptDoesNotReplaceMyAIState(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	t.Setenv("USERPROFILE", t.TempDir())
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var b map[string]interface{}
		json.NewDecoder(r.Body).Decode(&b)
		json.NewEncoder(w).Encode(map[string]interface{}{"response": b["prompt"]})
	}))
	defer server.Close()
	cfg := config.Get().GetConfig().AIConfig
	cfg.Enabled = true
	cfg.ShareAI = false
	cfg.Provider = "ollama"
	cfg.OllamaURL = server.URL
	cfg.SystemPrompt = ""
	config.Get().SetAIConfig(cfg)
	s := &AIService{client: server.Client()}
	if _, err := s.GenerateResponse("private question"); err != nil {
		t.Fatal(err)
	}
	if _, err := s.GenerateSharedResponse("remote question"); err != nil {
		t.Fatal(err)
	}
	query, response, busy := s.GetLastState()
	if query != "private question" || response != "private question" || busy {
		t.Fatalf("My AI state overwritten: %s %s %v", query, response, busy)
	}
}
