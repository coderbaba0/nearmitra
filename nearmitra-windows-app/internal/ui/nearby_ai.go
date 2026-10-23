package ui

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"strings"
	"time"

	"nearmitra-windows-app/internal/ai"
	"nearmitra-windows-app/internal/models"
)

// resolveNearbyAI never falls back to this desktop's own engine or an arbitrary IP.
func (hs *HTTPServer) resolveNearbyAI(id string) (models.Peer, error) {
	if strings.TrimSpace(id) == "" || id == "unknown_device_id" {
		return models.Peer{}, fmt.Errorf("Select a Nearby / P2P device")
	}
	for _, p := range hs.discovery.GetPeers() {
		if p.IsOnline && (p.ID == id || p.InternetDeviceID == id) {
			return *p, nil
		}
	}
	return models.Peer{}, fmt.Errorf("Selected device is not connected through Nearby / P2P")
}

func (hs *HTTPServer) handleNearbyAIQuery(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", 405)
		return
	}
	var body struct {
		PeerID string `json:"peer_id"`
		Prompt string `json:"prompt"`
	}
	if json.NewDecoder(r.Body).Decode(&body) != nil || strings.TrimSpace(body.Prompt) == "" {
		http.Error(w, "Select a device and enter a prompt", 400)
		return
	}
	peer, err := hs.resolveNearbyAI(body.PeerID)
	if err != nil {
		http.Error(w, err.Error(), 503)
		return
	}
	hs.proxyNearbyAI(w, r, peer, body.Prompt)
}

// proxyNearbyAI relays a resolved device stream and propagates browser cancellation.
func (hs *HTTPServer) proxyNearbyAI(w http.ResponseWriter, r *http.Request, peer models.Peer, prompt string) {
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Minute)
	defer cancel()
	port := peer.Port
	if port <= 0 {
		port = models.TransferPort
	}
	conn, err := (&net.Dialer{Timeout: 8 * time.Second}).DialContext(ctx, "tcp", net.JoinHostPort(peer.IP, fmt.Sprint(port)))
	if err != nil {
		http.Error(w, "Could not reach selected device: "+err.Error(), 502)
		return
	}
	defer conn.Close()
	stop := context.AfterFunc(ctx, func() { conn.Close() })
	defer stop()
	_ = conn.SetDeadline(time.Now().Add(5 * time.Minute))
	cfg := hs.cfgMgr.GetConfig()
	err = json.NewEncoder(conn).Encode(map[string]interface{}{"type": "ai_request", "sender": cfg.DeviceName, "sender_id": cfg.DeviceID, "internet_device_id": cfg.DeviceID, "prompt": prompt, "stream": true})
	if err != nil {
		http.Error(w, err.Error(), 502)
		return
	}
	w.Header().Set("Content-Type", "application/x-ndjson; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	encoder := json.NewEncoder(w)
	emit := func(packet map[string]interface{}) error {
		if err := encoder.Encode(packet); err != nil {
			return err
		}
		if f, ok := w.(http.Flusher); ok {
			f.Flush()
		}
		return nil
	}
	decoder := json.NewDecoder(conn)
	received := false
	for {
		var packet map[string]interface{}
		if err = decoder.Decode(&packet); err != nil {
			if !received {
				emit(map[string]interface{}{"status": "error", "error": "Selected device did not return an AI response. Check its AI sharing permission.", "done": true})
			} else {
				emit(map[string]interface{}{"status": "error", "error": "Nearby AI response ended before completion", "done": true})
			}
			return
		}
		received = true
		if err = emit(packet); err != nil {
			return
		}
		status, _ := packet["status"].(string)
		if packet["done"] == true || status == "disabled" || status == "error" || status == "done" || status == "success" || status == "ok" {
			return
		}
	}
}

func (hs *HTTPServer) handleSelectedAISharing(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", 405)
		return
	}
	peer, err := hs.resolveNearbyAI(r.URL.Query().Get("peer_id"))
	if err != nil {
		http.Error(w, err.Error(), 503)
		return
	}
	cfg := hs.cfgMgr.GetConfig().AIConfig
	allowed := ai.PeerAllowed(cfg, peer.ID, peer.InternetDeviceID, peer.IP)
	writeIOTJSON(w, map[string]interface{}{"peer_id": peer.ID, "allowed": allowed, "sharing_enabled": cfg.ShareAI, "ai_enabled": cfg.Enabled, "provider": cfg.Provider})
}
