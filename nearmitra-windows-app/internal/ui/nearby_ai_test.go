package ui

import (
	"encoding/json"
	"fmt"
	"nearmitra-windows-app/internal/config"
	"nearmitra-windows-app/internal/models"
	"nearmitra-windows-app/internal/network"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestNearbyAIProxyUsesSelectedDeviceAndFlushesEachChunk(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	t.Setenv("USERPROFILE", t.TempDir())
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	done := make(chan struct{})
	defer close(done)
	requestBody := make(chan map[string]interface{}, 1)
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		var request map[string]interface{}
		json.NewDecoder(conn).Decode(&request)
		requestBody <- request
		fmt.Fprintln(conn, `{"type":"ai_stream","reply":"From phone","done":false}`)
		<-done
		fmt.Fprintln(conn, `{"type":"ai_response","done":true,"status":"done"}`)
	}()
	hs := &HTTPServer{cfgMgr: config.Get()}
	local := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hs.proxyNearbyAI(w, r, models.Peer{ID: "phone", IP: "127.0.0.1", Port: listener.Addr().(*net.TCPAddr).Port}, "remote question")
	}))
	defer local.Close()
	client := &http.Client{Timeout: 5 * time.Second}
	response, err := client.Post(local.URL, "application/json", strings.NewReader(`{"peer_id":"phone","prompt":"remote question"}`))
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	var packet map[string]interface{}
	if err = json.NewDecoder(response.Body).Decode(&packet); err != nil {
		t.Fatal(err)
	}
	if packet["reply"] != "From phone" {
		t.Fatal("selected device answer not forwarded", packet)
	}
	request := <-requestBody
	if request["type"] != "ai_request" || request["prompt"] != "remote question" {
		t.Fatal("wrong request", request)
	}
	// First chunk arrived before the host has been permitted to finish.
	done <- struct{}{}
}
func TestNearbyAIRejectsOfflineInsteadOfRunningMyAI(t *testing.T) {
	hs := &HTTPServer{discovery: network.GetDiscovery()}
	w := httptest.NewRecorder()
	hs.handleNearbyAIQuery(w, httptest.NewRequest(http.MethodPost, "/api/ai/nearby-query", strings.NewReader(`{"peer_id":"missing-device-ai","prompt":"hello"}`)))
	if w.Code != 503 || !strings.Contains(w.Body.String(), "Nearby / P2P") {
		t.Fatal(w.Code, w.Body.String())
	}
}

func TestNearbyAIRequiresAnExplicitDevice(t *testing.T) {
	hs := &HTTPServer{discovery: network.GetDiscovery()}
	if _, err := hs.resolveNearbyAI(""); err == nil {
		t.Fatal("empty selection chose another device")
	}
	if _, err := hs.resolveNearbyAI("unknown_device_id"); err == nil {
		t.Fatal("placeholder selected a device")
	}
}
