package transfer

import (
	"encoding/json"
	"fmt"
	"nearmitra-windows-app/internal/config"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestNearbyAIRequiresAllowAndStreamsBeforeGenerationCompletes(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	t.Setenv("USERPROFILE", t.TempDir())
	release := make(chan struct{})
	defer close(release)
	invoked := make(chan struct{}, 1)
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		invoked <- struct{}{}
		fmt.Fprintln(w, `{"response":"First ","done":false}`)
		w.(http.Flusher).Flush()
		select {
		case <-release:
		case <-r.Context().Done():
			return
		}
		fmt.Fprintln(w, `{"response":"second","done":true}`)
	}))
	defer host.Close()
	cfg := config.Get().GetConfig().AIConfig
	old := cfg
	defer config.Get().SetAIConfig(old)
	cfg.Enabled = true
	cfg.ShareAI = true
	cfg.Provider = "ollama"
	cfg.OllamaURL = host.URL
	cfg.OllamaModel = "test"
	cfg.AllowedPeers = nil
	cfg.RevokedPeers = nil
	config.Get().SetAIConfig(cfg)
	request := func() net.Conn {
		client, server := net.Pipe()
		client.SetDeadline(time.Now().Add(5 * time.Second))
		go (&TransferServer{}).handleConnection(server)
		json.NewEncoder(client).Encode(map[string]string{"type": "ai_request", "sender_id": "phone-lan", "internet_device_id": "phone-wan", "prompt": "Hello"})
		return client
	}
	denied := request()
	var packet map[string]interface{}
	json.NewDecoder(denied).Decode(&packet)
	denied.Close()
	if packet["status"] != "disabled" {
		t.Fatal("ungranted phone not rejected", packet)
	}
	select {
	case <-invoked:
		t.Fatal("ungranted request invoked Ollama")
	default:
	}
	cfg.AllowedPeers = []string{"phone-wan"}
	config.Get().SetAIConfig(cfg)
	client := request()
	defer client.Close()
	decoder := json.NewDecoder(client)
	if err := decoder.Decode(&packet); err != nil {
		t.Fatal(err)
	}
	if packet["reply"] != "First " || packet["done"] != false || packet["status"] != "streaming" {
		t.Fatal("first chunk was not streamed", packet)
	}
	// Revoke while Ollama is still generating: no second token is sent.
	cfg.RevokedPeers = []string{"phone-lan"}
	config.Get().SetAIConfig(cfg)
	release <- struct{}{}
	packet = nil
	if err := decoder.Decode(&packet); err != nil {
		t.Fatal(err)
	}
	if packet["status"] != "error" || packet["done"] != true {
		t.Fatal("revocation not enforced", packet)
	}
}

func TestNearbyAIStopCancelsOllamaGeneration(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	t.Setenv("USERPROFILE", t.TempDir())
	cancelled := make(chan struct{})
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, `{"response":"First","done":false}`)
		w.(http.Flusher).Flush()
		select {
		case <-r.Context().Done():
			close(cancelled)
		case <-time.After(5 * time.Second):
		}
	}))
	defer host.Close()
	cfg := config.Get().GetConfig().AIConfig
	old := cfg
	defer config.Get().SetAIConfig(old)
	cfg.Enabled = true
	cfg.ShareAI = true
	cfg.Provider = "ollama"
	cfg.OllamaURL = host.URL
	cfg.OllamaModel = "test"
	cfg.AllowedPeers = []string{"cancel-phone"}
	cfg.RevokedPeers = nil
	config.Get().SetAIConfig(cfg)
	client, server := net.Pipe()
	client.SetDeadline(time.Now().Add(3 * time.Second))
	go (&TransferServer{}).handleConnection(server)
	json.NewEncoder(client).Encode(map[string]string{"type": "ai_request", "sender_id": "cancel-phone", "prompt": "hello"})
	var packet map[string]interface{}
	if err := json.NewDecoder(client).Decode(&packet); err != nil {
		client.Close()
		t.Fatal(err)
	}
	client.Close()
	select {
	case <-cancelled:
	case <-time.After(3 * time.Second):
		t.Fatal("Stop did not cancel Ollama request")
	}
}
