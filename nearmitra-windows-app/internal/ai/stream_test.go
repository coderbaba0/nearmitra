package ai

import (
	"context"
	"encoding/json"
	"fmt"
	"nearmitra-windows-app/internal/config"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestOllamaStreamsActualChunksWithoutChangingMyAI(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	t.Setenv("USERPROFILE", t.TempDir())
	var stream bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/generate" {
			t.Error("incorrect Ollama endpoint")
		}
		var body map[string]interface{}
		json.NewDecoder(r.Body).Decode(&body)
		stream = body["stream"] == true
		fmt.Fprintln(w, `{"response":"Hello ","done":false}`)
		w.(http.Flusher).Flush()
		fmt.Fprintln(w, `{"response":"phone","done":false}`)
		w.(http.Flusher).Flush()
		fmt.Fprintln(w, `{"done":true}`)
	}))
	defer server.Close()
	cfg := config.Get().GetConfig().AIConfig
	old := cfg
	defer config.Get().SetAIConfig(old)
	cfg.Enabled = true
	cfg.Provider = "ollama"
	cfg.OllamaURL = server.URL
	cfg.OllamaModel = "test-model"
	config.Get().SetAIConfig(cfg)
	service := &AIService{lastQuery: "private", lastResponse: "private answer"}
	var chunks []string
	if err := service.StreamSharedResponse(context.Background(), "hello", func(chunk string) error { chunks = append(chunks, chunk); return nil }); err != nil {
		t.Fatal(err)
	}
	if !stream || len(chunks) != 2 || chunks[0] != "Hello " || chunks[1] != "phone" {
		t.Fatalf("not streaming actual chunks: %v", chunks)
	}
	q, r, busy := service.GetLastState()
	if q != "private" || r != "private answer" || busy {
		t.Fatal("owner state changed")
	}
}
func TestSharedStreamReportsProviderErrors(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	t.Setenv("USERPROFILE", t.TempDir())
	cfg := config.Get().GetConfig().AIConfig
	old := cfg
	defer config.Get().SetAIConfig(old)
	cfg.Enabled = true
	cfg.Provider = "gemini"
	cfg.GeminiAPIKey = ""
	config.Get().SetAIConfig(cfg)
	called := false
	if err := Get().StreamSharedResponse(context.Background(), "hello", func(string) error { called = true; return nil }); err == nil || called {
		t.Fatal("missing key produced simulated output")
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fmt.Fprintln(w, `{"response":"partial","done":false}`) }))
	defer server.Close()
	cfg.Provider = "ollama"
	cfg.OllamaURL = server.URL
	cfg.OllamaModel = "test"
	config.Get().SetAIConfig(cfg)
	if err := Get().StreamSharedResponse(context.Background(), "hello", func(string) error { return nil }); err == nil {
		t.Fatal("truncated stream marked completed")
	}
}
