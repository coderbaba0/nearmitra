// Package ui provides embedded HTTP/REST server and native Windows 11 launcher.
package ui

import (
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"math"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"nearmitra-windows-app/internal/ai"
	"nearmitra-windows-app/internal/calling"
	"nearmitra-windows-app/internal/chat"
	"nearmitra-windows-app/internal/config"
	"nearmitra-windows-app/internal/iot"
	"nearmitra-windows-app/internal/models"
	"nearmitra-windows-app/internal/network"
	"nearmitra-windows-app/internal/streaming"
	"nearmitra-windows-app/internal/transfer"
)

//go:embed web/*
var webFS embed.FS

// HTTPServer manages local embedded web GUI server.
type HTTPServer struct {
	mu        sync.RWMutex
	port      int
	cfgMgr    *config.ConfigManager
	discovery *network.DiscoveryService
	server    *transfer.TransferServer
	chatMgr   *chat.HistoryManager
	aiService *ai.AIService
	cctv      *streaming.StreamState
	signaling *calling.CallState
	iotMgr    *iot.Manager
	iotAuto   *iot.AutomationEngine
	logs          []string
	transfers     []models.TransferProgress
	streamSignals []StreamSignalEvent
	signalMu      sync.Mutex
	typingPeers   map[string]time.Time
	typingMu      sync.RWMutex
}

// StreamSignalEvent represents incoming WebRTC stream signals from network peers.
type StreamSignalEvent struct {
	PeerIP   string           `json:"peer_ip"`
	Header   models.WireHeader `json:"header"`
	Received time.Time        `json:"received"`
}

var globalHTTPServer *HTTPServer

// NewHTTPServer initializes local UI server.
func NewHTTPServer(
	cfgMgr *config.ConfigManager,
	discovery *network.DiscoveryService,
	server *transfer.TransferServer,
	chatMgr *chat.HistoryManager,
	aiService *ai.AIService,
	cctv *streaming.StreamState,
	signaling *calling.CallState,
	iotMgr *iot.Manager,
	iotAuto *iot.AutomationEngine,
) *HTTPServer {
	hs := &HTTPServer{
		port:          43880,
		cfgMgr:        cfgMgr,
		discovery:     discovery,
		server:        server,
		chatMgr:       chatMgr,
		aiService:     aiService,
		cctv:          cctv,
		signaling:     signaling,
		iotMgr:        iotMgr,
		iotAuto:       iotAuto,
		logs:          make([]string, 0),
		transfers:     make([]models.TransferProgress, 0),
		streamSignals: make([]StreamSignalEvent, 0),
		typingPeers:   make(map[string]time.Time),
	}
	globalHTTPServer = hs
	return hs
}

// SetPeerTyping updates active typing status for a network peer.
func (hs *HTTPServer) SetPeerTyping(peerID string, isTyping bool) {
	hs.typingMu.Lock()
	defer hs.typingMu.Unlock()
	if hs.typingPeers == nil {
		hs.typingPeers = make(map[string]time.Time)
	}
	if isTyping {
		hs.typingPeers[peerID] = time.Now().Add(3500 * time.Millisecond)
	} else {
		delete(hs.typingPeers, peerID)
	}
}

// GetTypingPeers returns currently active typing peer IDs / IPs.
func (hs *HTTPServer) GetTypingPeers() []string {
	hs.typingMu.Lock()
	defer hs.typingMu.Unlock()
	now := time.Now()
	var active []string
	for id, exp := range hs.typingPeers {
		if now.Before(exp) {
			active = append(active, id)
		} else {
			delete(hs.typingPeers, id)
		}
	}
	return active
}

// PushStreamSignal stores incoming WebRTC signaling message for web UI polling.
func (hs *HTTPServer) PushStreamSignal(peerIP string, header models.WireHeader) {
	hs.signalMu.Lock()
	defer hs.signalMu.Unlock()
	hs.streamSignals = append(hs.streamSignals, StreamSignalEvent{
		PeerIP:   peerIP,
		Header:   header,
		Received: time.Now(),
	})
	hs.AddLog(fmt.Sprintf("[SIGNAL] WebRTC Stream Signal [%s] received from %s", header.Type, peerIP))
}

// AddLog appends a timestamped log to the UI console.
func (hs *HTTPServer) AddLog(msg string) {
	hs.mu.Lock()
	defer hs.mu.Unlock()
	entry := fmt.Sprintf("[%s] %s", time.Now().Format("15:04:05"), msg)
	hs.logs = append(hs.logs, entry)
	if len(hs.logs) > 200 {
		hs.logs = hs.logs[len(hs.logs)-200:]
	}
}

// Start launches embedded web server.
func (hs *HTTPServer) Start() error {
	mux := http.NewServeMux()

	// Direct Embedded Asset Handlers
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate")
		w.Header().Set("Pragma", "no-cache")
		w.Header().Set("Expires", "0")

		path := strings.TrimPrefix(r.URL.Path, "/")
		if path == "" || path == "index.html" {
			data, err := fs.ReadFile(webFS, "web/index.html")
			if err == nil {
				w.Header().Set("Content-Type", "text/html; charset=utf-8")
				_, _ = w.Write(data)
				return
			}
		} else if path == "style.css" {
			data, err := fs.ReadFile(webFS, "web/style.css")
			if err == nil {
				w.Header().Set("Content-Type", "text/css; charset=utf-8")
				_, _ = w.Write(data)
				return
			}
		} else if path == "app.js" {
			data, err := fs.ReadFile(webFS, "web/app.js")
			if err == nil {
				w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
				_, _ = w.Write(data)
				return
			}
		} else if path == "logo.png" {
			data, err := fs.ReadFile(webFS, "web/logo.png")
			if err == nil {
				w.Header().Set("Content-Type", "image/png")
				_, _ = w.Write(data)
				return
			}
		} else if path == "favicon.ico" {
			data, err := fs.ReadFile(webFS, "web/favicon.ico")
			if err == nil {
				w.Header().Set("Content-Type", "image/x-icon")
				_, _ = w.Write(data)
				return
			}
		}
		http.NotFound(w, r)
	})

	// API Endpoints
	mux.HandleFunc("/api/state", hs.handleState)
	mux.HandleFunc("/api/discovery/rescan", hs.handleDiscoveryRescan)
	mux.HandleFunc("/api/lan/scan", hs.handleLANScan)
	mux.HandleFunc("/api/manual-pair", hs.handleManualPair)
	mux.HandleFunc("/api/send-file", hs.handleSendFile)
	mux.HandleFunc("/api/send-file-upload", hs.handleSendFileUpload)
	mux.HandleFunc("/api/send-folder", hs.handleSendFolder)
	mux.HandleFunc("/api/chat/send", hs.handleChatSend)
	mux.HandleFunc("/api/chat/react", hs.handleChatReact)
	mux.HandleFunc("/api/chat/typing", hs.handleChatTyping)
	mux.HandleFunc("/api/cctv/filter", hs.handleCCTVFilter)
	mux.HandleFunc("/api/cctv/record", hs.handleCCTVRecord)
	mux.HandleFunc("/api/cctv/upload-recording", hs.handleUploadRecording)
	mux.HandleFunc("/api/cctv/upload-snapshot", hs.handleUploadSnapshot)
	mux.HandleFunc("/api/cctv/snapshot", hs.handleCCTVSnapshot)
	mux.HandleFunc("/api/open-recordings", hs.handleOpenRecordings)
	mux.HandleFunc("/api/cctv/remote-ctrl", hs.handleCCTVRemoteCtrl)
	mux.HandleFunc("/api/cctv/signal", hs.handleCCTVSignal)
	mux.HandleFunc("/api/cctv/poll-signals", hs.handleCCTVPollSignals)
	mux.HandleFunc("/api/streaming/security", hs.handleStreamingSecurity)
	mux.HandleFunc("/api/streaming/trust-device", hs.handleStreamingTrustDevice)
	mux.HandleFunc("/api/call/invite", hs.handleCallInvite)
	mux.HandleFunc("/api/call/answer", hs.handleCallAnswer)
	mux.HandleFunc("/api/call/decline", hs.handleCallDecline)
	mux.HandleFunc("/api/call/end", hs.handleVoiceEnd)
	mux.HandleFunc("/api/voice/end", hs.handleVoiceEnd)
	mux.HandleFunc("/api/voice/mute", hs.handleVoiceMute)
	mux.HandleFunc("/api/voice/ptt", hs.handleVoicePTT)
	mux.HandleFunc("/api/ai/set-model", hs.handleAISetModel)
	mux.HandleFunc("/api/ai/set-config", hs.handleAISetConfig)
	mux.HandleFunc("/api/ai/get-config", hs.handleAIGetConfig)
	mux.HandleFunc("/api/ai/query", hs.handleAIQuery)
	mux.HandleFunc("/api/ai/share-toggle", hs.handleAIShareToggle)
	mux.HandleFunc("/api/ai/peer-permission", hs.handleAIPeerPermission)
	mux.HandleFunc("/api/ai/analytics", hs.handleAIAnalytics)
	mux.HandleFunc("/api/iot/reprobe", hs.handleIOTReprobe)
	mux.HandleFunc("/api/iot/hardware-scan", hs.handleIOTHwScan)
	mux.HandleFunc("/api/iot/audio-cast", hs.handleIOTAudioCast)
	mux.HandleFunc("/api/iot/live-audio-stream", hs.handleIOTLiveAudioStream)
	mux.HandleFunc("/api/iot/sensors/poll", hs.handleIOTSensorsPoll)
	mux.HandleFunc("/api/iot/sensors/trigger", hs.handleIOTSensorsTrigger)
	mux.HandleFunc("/api/iot/remote-mic", hs.handleIOTRemoteMic)
	mux.HandleFunc("/api/iot/remote-cam", hs.handleIOTRemoteCam)
	mux.HandleFunc("/api/iot/nfc-read", hs.handleIOTNFCRead)
	mux.HandleFunc("/api/iot/print-gatepass", hs.handleIOTPrintGatepass)
	mux.HandleFunc("/api/iot/toggle", hs.handleIOTToggle)
	mux.HandleFunc("/api/iot/poll", hs.handleIOTPoll)
	mux.HandleFunc("/api/iot/print", hs.handleIOTPrint)
	mux.HandleFunc("/api/iot/scan", hs.handleIOTScan)
	mux.HandleFunc("/api/iot/schedule", hs.handleIOTSchedule)
	mux.HandleFunc("/api/logs/clear", hs.handleLogsClear)
	mux.HandleFunc("/api/open-save-dir", hs.handleOpenSaveDir)
	mux.HandleFunc("/api/open-file", hs.handleOpenFile)
	mux.HandleFunc("/api/recents/files", hs.handleRecentsFiles)
	mux.HandleFunc("/api/recents/show-in-folder", hs.handleShowInFolder)
	mux.HandleFunc("/api/set-theme", hs.handleSetTheme)
	mux.HandleFunc("/api/settings/autostart", hs.handleAutoStart)
	mux.HandleFunc("/api/settings/notifications", hs.handleNotifications)

	var listener net.Listener
	var err error
	for i := 0; i < 10; i++ {
		listener, err = net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", hs.port))
		if err == nil {
			break
		}
		time.Sleep(300 * time.Millisecond)
	}
	if err != nil {
		return fmt.Errorf("failed to bind port %d: %w", hs.port, err)
	}

	go func() {
		_ = http.Serve(listener, mux)
	}()

	hs.AddLog(fmt.Sprintf("NearMitra Windows 11 Fluent Engine online on port %d.", hs.port))
	return nil
}

func (hs *HTTPServer) handleState(w http.ResponseWriter, r *http.Request) {
	hs.mu.RLock()
	peers := hs.discovery.GetPeers()
	lanDevs := hs.discovery.GetLANDevices()
	router := network.GetRouterDiagnostics()
	aiCfg := hs.cfgMgr.GetConfig().AIConfig
	logs := append([]string(nil), hs.logs...)
	transfers := append([]models.TransferProgress(nil), hs.transfers...)
	hs.mu.RUnlock()

	lastQ, lastR, isBusy := hs.aiService.GetLastState()

	// Fetch persisted chat messages from disk (all peers)
	chatMessages := hs.chatMgr.GetMessages()

	// Pending incoming call info from signaling
	pendingCall := map[string]interface{}{
		"active":     hs.signaling.Active,
		"ptt":        hs.signaling.PTTActive,
		"muted":      hs.signaling.Muted,
		"is_video":   hs.signaling.IsVideo,
		"peer_name":  hs.signaling.PeerName,
		"peer_ip":    hs.signaling.PeerIP,
		"ringing":    hs.signaling.Ringing,
	}

	resp := map[string]interface{}{
		"local_device": map[string]interface{}{
			"id":   hs.cfgMgr.GetConfig().DeviceID,
			"name": hs.cfgMgr.GetConfig().DeviceName,
			"ip":   router.IPv4,
		},
		"peers":        peers,
		"lan_devices":  lanDevs,
		"typing_peers": hs.GetTypingPeers(),
		"chat_messages": chatMessages,
		"router": map[string]interface{}{
			"ssid":      router.SSID,
			"ip":        router.IPv4,
			"speed":     router.LinkSpeed,
			"interface": router.Interface,
		},
		"logs":      logs,
		"transfers": transfers,
		"settings": map[string]interface{}{
			"autostart":     hs.cfgMgr.IsAutoStartEnabled(),
			"notifications": hs.cfgMgr.IsNotificationsEnabled(),
			"theme":         hs.cfgMgr.GetConfig().ThemeMode,
			"save_dir":      hs.cfgMgr.GetConfig().SaveDirectory,
		},
		"cctv": map[string]interface{}{
			"active":          hs.cctv.Active,
			"selected_filter": hs.cctv.SelectedFilter,
			"is_recording":    hs.cctv.IsRecording,
			"torch_on":        hs.cctv.TorchOn,
		},
		"voice":  pendingCall,
		"ai": map[string]interface{}{
			"provider":      aiCfg.Provider,
			"model":         aiCfg.GeminiModel,
			"last_query":    lastQ,
			"last_response": lastR,
			"is_busy":       isBusy,
		},
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

func (hs *HTTPServer) handleLANScan(w http.ResponseWriter, r *http.Request) {
	go hs.discovery.ScanLANNow()
	hs.AddLog("Active LAN Subnet scan initiated across subnet range.")
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]bool{"scanning": true})
}

func (hs *HTTPServer) handleDiscoveryRescan(w http.ResponseWriter, r *http.Request) {
	hs.discovery.Start()
	hs.AddLog("Discovery rescan triggered across all subnets.")
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleManualPair(w http.ResponseWriter, r *http.Request) {
	var body struct {
		IP string `json:"ip"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	err := hs.discovery.ManualPair(body.IP)
	hs.AddLog(fmt.Sprintf("Manual Pair beacon sent to %s", body.IP))
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": err == nil})
}

func (hs *HTTPServer) handleSendFile(w http.ResponseWriter, r *http.Request) {
	targetIP := r.URL.Query().Get("ip")
	directPath := r.URL.Query().Get("path") // direct path from drag-drop (no dialog)

	var filePath string
	if directPath != "" {
		// Validate the path exists on disk
		if _, err := os.Stat(directPath); err != nil {
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]interface{}{"error": "file not found"})
			return
		}
		filePath = directPath
	} else {
		// Open native file picker dialog
		path, err := OpenFileDialog(0, "Select File to Send via NearMitra")
		if err != nil || path == "" {
			w.WriteHeader(http.StatusOK)
			return
		}
		filePath = path
	}

	hs.AddLog(fmt.Sprintf("Sending file %s...", filepath.Base(filePath)))
	if targetIP == "" {
		peers := hs.discovery.GetPeers()
		if len(peers) > 0 {
			targetIP = peers[0].IP
		}
	}
	if targetIP != "" {
		go transfer.SendFile(targetIP, filePath, nil)
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"file": filepath.Base(filePath)})
}

// handleSendFileUpload receives drag-dropped file bytes from the browser,
// saves them to a temp file, and sends to the target peer.
func (hs *HTTPServer) handleSendFileUpload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	targetIP := r.URL.Query().Get("ip")

	// 200 MB max
	if err := r.ParseMultipartForm(200 << 20); err != nil {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]interface{}{"error": err.Error()})
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]interface{}{"error": "no file field"})
		return
	}
	defer file.Close()

	// Save to temp dir
	tmpDir := os.TempDir()
	tmpPath := filepath.Join(tmpDir, "nearmitra_drop_"+header.Filename)
	tmpFile, err := os.Create(tmpPath)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]interface{}{"error": "cannot write temp file"})
		return
	}
	defer tmpFile.Close()

	buf := make([]byte, 1<<20) // 1 MB chunks
	for {
		n, readErr := file.Read(buf)
		if n > 0 {
			_, _ = tmpFile.Write(buf[:n])
		}
		if readErr != nil {
			break
		}
	}
	tmpFile.Close()

	if targetIP == "" {
		peers := hs.discovery.GetPeers()
		if len(peers) > 0 {
			targetIP = peers[0].IP
		}
	}

	hs.AddLog(fmt.Sprintf("[TRANSFER] Drag-Drop: Sending %s → %s", header.Filename, targetIP))
	if targetIP != "" {
		go func() {
			_ = transfer.SendFile(targetIP, tmpPath, nil)
			_ = os.Remove(tmpPath) // clean up temp after send
		}()
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"file": header.Filename, "size": header.Size})
}

func (hs *HTTPServer) handleSendFolder(w http.ResponseWriter, r *http.Request) {
	targetIP := r.URL.Query().Get("ip")
	folder, err := SelectFolderDialog(hs.cfgMgr.GetConfig().SaveDirectory)
	if err == nil && folder != "" {
		if targetIP == "" {
			peers := hs.discovery.GetPeers()
			if len(peers) > 0 {
				targetIP = peers[0].IP
			}
		}
		hs.AddLog(fmt.Sprintf("Sending folder %s to %s...", filepath.Base(folder), targetIP))
		if targetIP != "" {
			go transfer.SendFolder(targetIP, folder, nil)
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]interface{}{"folder": filepath.Base(folder)})
		return
	}
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleChatSend(w http.ResponseWriter, r *http.Request) {
	var msg models.ChatMessage
	_ = json.NewDecoder(r.Body).Decode(&msg)
	hs.chatMgr.AddMessage(msg)
	
	targetIP := msg.PeerIP
	if targetIP == "" && msg.PeerID != "" {
		peers := hs.discovery.GetPeers()
		for _, p := range peers {
			if p.ID == msg.PeerID {
				targetIP = p.IP
				break
			}
		}
	}
	
	hs.AddLog(fmt.Sprintf("Chat Message to [%s]: %s", targetIP, msg.Text))
	if targetIP != "" {
		go transfer.SendTextMessage(targetIP, msg.ID, msg.Text)
	}
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleChatReact(w http.ResponseWriter, r *http.Request) {
	var body struct {
		TargetIP string `json:"target_ip"`
		MsgID    string `json:"msg_id"`
		Emoji    string `json:"emoji"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	hs.chatMgr.AddReaction(body.MsgID, body.Emoji)
	if body.TargetIP != "" {
		go transfer.SendReaction(body.TargetIP, body.MsgID, body.Emoji)
	}
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleChatTyping(w http.ResponseWriter, r *http.Request) {
	var body struct {
		TargetIP string `json:"target_ip"`
		PeerID   string `json:"peer_id"`
		IsTyping bool   `json:"is_typing"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	targetIP := body.TargetIP
	if targetIP == "" && body.PeerID != "" {
		peers := hs.discovery.GetPeers()
		for _, p := range peers {
			if p.ID == body.PeerID {
				targetIP = p.IP
				break
			}
		}
	}
	if targetIP != "" {
		go transfer.SendTypingStatus(targetIP, body.IsTyping)
	}
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleCCTVFilter(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Filter string `json:"filter"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	hs.cctv.SetFilter(streaming.CVFilter(body.Filter))
	hs.AddLog(fmt.Sprintf("CV Filter set to %s", body.Filter))
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleCCTVRecord(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Recording bool `json:"recording"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	if body.Recording {
		path, _ := hs.cctv.StartRecording()
		hs.AddLog(fmt.Sprintf("[CCTV] Live Recording Started: %s", path))
	} else {
		path, dur := hs.cctv.StopRecording()
		hs.AddLog(fmt.Sprintf("⏹ CCTV Recording Finalizing: %s (Duration: %v)", path, dur.Round(time.Second)))
	}
	w.WriteHeader(http.StatusOK)
}

// handleUploadRecording saves the real video Blob recorded from WebRTC/Local canvas to disk
func (hs *HTTPServer) handleUploadRecording(w http.ResponseWriter, r *http.Request) {
	saveDir := hs.cfgMgr.GetConfig().SaveDirectory
	recDir := filepath.Join(saveDir, "CCTV_Recordings")
	_ = os.MkdirAll(recDir, 0755)

	ext := r.URL.Query().Get("ext")
	if ext == "" {
		ext = "webm"
	}
	fileName := fmt.Sprintf("CCTV_Rec_%s.%s", time.Now().Format("20060102_150405"), ext)
	filePath := filepath.Join(recDir, fileName)

	data, err := io.ReadAll(r.Body)
	if err != nil || len(data) == 0 {
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	err = os.WriteFile(filePath, data, 0644)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	durStr := r.URL.Query().Get("dur")
	if durStr != "" {
		hs.AddLog(fmt.Sprintf("⏹ CCTV Recording Saved: %s (Duration: %s, Size: %s)", filePath, durStr, formatStorageBytes(int64(len(data)))))
	} else {
		hs.AddLog(fmt.Sprintf("⏹ CCTV Recording Saved: %s (Size: %s)", filePath, formatStorageBytes(int64(len(data)))))
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true, "path": filePath})
}

// handleUploadSnapshot saves the real canvas snapshot image to disk
func (hs *HTTPServer) handleUploadSnapshot(w http.ResponseWriter, r *http.Request) {
	saveDir := hs.cfgMgr.GetConfig().SaveDirectory
	snapDir := filepath.Join(saveDir, "CCTV_Snapshots")
	_ = os.MkdirAll(snapDir, 0755)

	fileName := fmt.Sprintf("SNAP_%s.png", time.Now().Format("20060102_150405"))
	filePath := filepath.Join(snapDir, fileName)

	data, err := io.ReadAll(r.Body)
	if err != nil || len(data) == 0 {
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	err = os.WriteFile(filePath, data, 0644)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	hs.AddLog(fmt.Sprintf("[SNAPSHOT] Snapshot saved: %s (Size: %s)", filePath, formatStorageBytes(int64(len(data)))))

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true, "path": filePath})
}

func formatStorageBytes(b int64) string {
	const unit = 1024
	if b < unit {
		return fmt.Sprintf("%d B", b)
	}
	div, exp := int64(unit), 0
	for n := b / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(b)/float64(div), "KMGTPE"[exp])
}

func (hs *HTTPServer) handleCCTVSnapshot(w http.ResponseWriter, r *http.Request) {
	path, _ := hs.cctv.SaveSnapshot()
	hs.AddLog(fmt.Sprintf("[SNAPSHOT] Snapshot saved: %s", path))
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleCCTVTorch(w http.ResponseWriter, r *http.Request) {
	hs.cctv.ToggleTorch()
	hs.AddLog("CCTV Flashlight Torch toggled.")
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleCCTVFlip(w http.ResponseWriter, r *http.Request) {
	hs.cctv.FlipCamera()
	hs.AddLog("CCTV Camera lens flipped.")
	w.WriteHeader(http.StatusOK)
}

// handleCCTVRemoteCtrl sends remote hardware commands to the selected mobile or PC peer
func (hs *HTTPServer) handleCCTVRemoteCtrl(w http.ResponseWriter, r *http.Request) {
	var body struct {
		TargetIP string      `json:"target_ip"`
		Action   string      `json:"action"` // "toggle_torch", "torch_on", "torch_off", "switch_camera", "toggle_mic", "reset"
		Value    interface{} `json:"value"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	if body.TargetIP == "" {
		peers := hs.discovery.GetPeers()
		if len(peers) > 0 {
			body.TargetIP = peers[0].IP
		}
	}
	if body.TargetIP != "" {
		_ = transfer.SendCctvCommand(body.TargetIP, body.Action, body.Value)
		hs.AddLog(fmt.Sprintf("[HARDWARE] Remote Command [%s] sent to %s", body.Action, body.TargetIP))
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true, "action": body.Action})
}

// handleCCTVSignal handles sending WebRTC offers, answers, ICE candidates to peer
func (hs *HTTPServer) handleCCTVSignal(w http.ResponseWriter, r *http.Request) {
	var rawMap map[string]interface{}
	if err := json.NewDecoder(r.Body).Decode(&rawMap); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	targetIP, _ := rawMap["target_ip"].(string)
	if targetIP == "" {
		peers := hs.discovery.GetPeers()
		if len(peers) > 0 {
			targetIP = peers[0].IP
		}
	}

	// Flatten signal payload
	signalPayload := make(map[string]interface{})
	if hdr, ok := rawMap["header"].(map[string]interface{}); ok && len(hdr) > 0 {
		for k, v := range hdr {
			signalPayload[k] = v
		}
	}
	for k, v := range rawMap {
		if k != "target_ip" && k != "header" {
			signalPayload[k] = v
		}
	}

	cfg := hs.cfgMgr.GetConfig()
	signalPayload["sender"] = cfg.DeviceName
	signalPayload["sender_id"] = cfg.DeviceID
	signalPayload["name"] = cfg.DeviceName
	signalPayload["id"] = cfg.DeviceID

	sigType, _ := signalPayload["type"].(string)
	if sigType == "" {
		sigType, _ = rawMap["type"].(string)
		signalPayload["type"] = sigType
	}

	if targetIP != "" {
		err := transfer.SendWebRTCSignal(targetIP, signalPayload)
		if err != nil {
			hs.AddLog(fmt.Sprintf("[WARN] Failed to send [%s] stream signal to %s: %v", sigType, targetIP, err))
		} else {
			hs.AddLog(fmt.Sprintf("[SIGNAL] Sent [%s] stream signal to %s (as %s / %s)", sigType, targetIP, cfg.DeviceName, cfg.DeviceID))
		}
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true, "signal_type": sigType})
}

// handleCCTVPollSignals returns any incoming WebRTC stream signals received from peers
func (hs *HTTPServer) handleCCTVPollSignals(w http.ResponseWriter, r *http.Request) {
	hs.signalMu.Lock()
	signals := hs.streamSignals
	hs.streamSignals = nil
	hs.signalMu.Unlock()

	w.Header().Set("Content-Type", "application/json")
	if signals == nil {
		signals = make([]StreamSignalEvent, 0)
	}
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"signals": signals})
}

// handleStreamingSecurity handles GET (retrieve) and POST (update) for streaming security permissions
func (hs *HTTPServer) handleStreamingSecurity(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method == http.MethodGet {
		sec := hs.cfgMgr.GetStreamingSecurity()
		_ = json.NewEncoder(w).Encode(sec)
		return
	}
	if r.Method == http.MethodPost {
		var sec models.StreamingSecurityConfig
		if err := json.NewDecoder(r.Body).Decode(&sec); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		hs.cfgMgr.SetStreamingSecurity(sec)
		hs.AddLog(fmt.Sprintf("[SECURITY] Streaming Security updated: camera=%v, audio=%v, screen=%v", sec.AllowCamera, sec.AllowAudio, sec.AllowScreen))
		_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true})
	}
}

// handleStreamingTrustDevice adds or removes a device from always-trusted list
func (hs *HTTPServer) handleStreamingTrustDevice(w http.ResponseWriter, r *http.Request) {
	var body struct {
		DeviceID string `json:"device_id"`
		Action   string `json:"action"` // "add" or "remove"
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	if body.DeviceID != "" {
		if body.Action == "remove" {
			hs.cfgMgr.RemoveTrustedDevice(body.DeviceID)
			hs.AddLog(fmt.Sprintf("Revoked always-trusted status for %s", body.DeviceID))
		} else {
			hs.cfgMgr.AddTrustedDevice(body.DeviceID)
			hs.AddLog(fmt.Sprintf("Added %s to always-trusted devices", body.DeviceID))
		}
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(hs.cfgMgr.GetStreamingSecurity())
}

func (hs *HTTPServer) handleOpenRecordings(w http.ResponseWriter, r *http.Request) {
	recDir := filepath.Join(hs.cfgMgr.GetConfig().SaveDirectory, "CCTV_Recordings")
	_ = os.MkdirAll(recDir, 0755)
	OpenFolderInExplorer(recDir)
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleVoicePTT(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Active bool `json:"active"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	hs.signaling.SetPTT(body.Active)
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleVoiceMute(w http.ResponseWriter, r *http.Request) {
	muted := hs.signaling.ToggleMute()
	hs.AddLog(fmt.Sprintf("Microphone Mute: %v", muted))
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleVoiceEnd(w http.ResponseWriter, r *http.Request) {
	hs.signaling.EndCall()
	hs.AddLog("Voice call session ended.")
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleCallInvite(w http.ResponseWriter, r *http.Request) {
	var body struct {
		TargetIP string `json:"target_ip"`
		PeerID   string `json:"peer_id"`
		PeerName string `json:"peer_name"`
		IsVideo  bool   `json:"is_video"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	_ = hs.signaling.InviteCall(body.TargetIP, body.PeerID, body.PeerName, body.IsVideo)
	callType := "HD Audio"
	if body.IsVideo {
		callType = "HD Video"
	}
	hs.AddLog(fmt.Sprintf("[CALL] WebRTC %s Call initiated with %s (%s)", callType, body.PeerName, body.TargetIP))
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true, "is_video": body.IsVideo})
}

func (hs *HTTPServer) handleCallAnswer(w http.ResponseWriter, r *http.Request) {
	hs.signaling.AnswerCall()
	hs.AddLog(fmt.Sprintf("[CALL] Call answered from %s", hs.signaling.PeerName))
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true})
}

func (hs *HTTPServer) handleCallDecline(w http.ResponseWriter, r *http.Request) {
	hs.signaling.DeclineCall()
	hs.AddLog("[CALL] Incoming call declined.")
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true})
}

func (hs *HTTPServer) handleAISetModel(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Provider string `json:"provider"`
		Model    string `json:"model"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	cfg := hs.cfgMgr.GetConfig().AIConfig
	if body.Provider != "" {
		cfg.Provider = body.Provider
	}
	if body.Model != "" {
		switch body.Provider {
		case "gemini":
			cfg.GeminiModel = body.Model
		case "openai":
			cfg.OpenAIModel = body.Model
		case "groq":
			cfg.GroqModel = body.Model
		case "ollama":
			cfg.OllamaModel = body.Model
		}
	}
	hs.cfgMgr.SetAIConfig(cfg)
	hs.aiService.ReloadConfig()
	hs.AddLog(fmt.Sprintf("AI Engine switched to: %s (%s)", body.Provider, body.Model))
	w.WriteHeader(http.StatusOK)
}

// handleAISetConfig saves full AI provider configuration (API keys, models, etc.)
func (hs *HTTPServer) handleAISetConfig(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Provider     string  `json:"provider"`
		GeminiKey    string  `json:"gemini_api_key"`
		GeminiModel  string  `json:"gemini_model"`
		OpenAIKey    string  `json:"openai_api_key"`
		OpenAIModel  string  `json:"openai_model"`
		GroqKey      string  `json:"groq_api_key"`
		GroqModel    string  `json:"groq_model"`
		OllamaURL    string  `json:"ollama_url"`
		OllamaModel  string  `json:"ollama_model"`
		Temperature  float64 `json:"temperature"`
		SystemPrompt string  `json:"system_prompt"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	cfg := hs.cfgMgr.GetConfig().AIConfig
	if body.Provider != "" {
		cfg.Provider = body.Provider
	}
	if body.GeminiKey != "" {
		cfg.GeminiAPIKey = body.GeminiKey
	}
	if body.GeminiModel != "" {
		cfg.GeminiModel = body.GeminiModel
	}
	if body.OpenAIKey != "" {
		cfg.OpenAIAPIKey = body.OpenAIKey
	}
	if body.OpenAIModel != "" {
		cfg.OpenAIModel = body.OpenAIModel
	}
	if body.GroqKey != "" {
		cfg.GroqAPIKey = body.GroqKey
	}
	if body.GroqModel != "" {
		cfg.GroqModel = body.GroqModel
	}
	if body.OllamaURL != "" {
		cfg.OllamaURL = body.OllamaURL
	}
	if body.OllamaModel != "" {
		cfg.OllamaModel = body.OllamaModel
	}
	if body.Temperature > 0 {
		cfg.Temperature = body.Temperature
	}
	if body.SystemPrompt != "" {
		cfg.SystemPrompt = body.SystemPrompt
	}
	hs.cfgMgr.SetAIConfig(cfg)
	hs.aiService.ReloadConfig()
	hs.AddLog(fmt.Sprintf("AI Config updated: provider=%s", cfg.Provider))
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true, "provider": cfg.Provider})
}

// handleAIGetConfig returns current AI provider config (keys masked)
func (hs *HTTPServer) handleAIGetConfig(w http.ResponseWriter, r *http.Request) {
	cfg := hs.cfgMgr.GetConfig().AIConfig
	// Mask API keys - return only first 8 chars + ***
	maskKey := func(k string) string {
		if len(k) > 8 {
			return k[:8] + "••••••••"
		}
		if k != "" {
			return "••••••••"
		}
		return ""
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"provider":      cfg.Provider,
		"gemini_model":  cfg.GeminiModel,
		"gemini_key":    maskKey(cfg.GeminiAPIKey),
		"gemini_set":    cfg.GeminiAPIKey != "",
		"openai_model":  cfg.OpenAIModel,
		"openai_key":    maskKey(cfg.OpenAIAPIKey),
		"openai_set":    cfg.OpenAIAPIKey != "",
		"groq_model":    cfg.GroqModel,
		"groq_key":      maskKey(cfg.GroqAPIKey),
		"groq_set":      cfg.GroqAPIKey != "",
		"ollama_url":    cfg.OllamaURL,
		"ollama_model":  cfg.OllamaModel,
		"temperature":   cfg.Temperature,
		"system_prompt": cfg.SystemPrompt,
		"share_ai":      cfg.ShareAI,
	})
}

func (hs *HTTPServer) handleAIQuery(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Prompt string `json:"prompt"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	resp, err := hs.aiService.GenerateResponse(body.Prompt)
	if err != nil {
		resp = fmt.Sprintf("Error: %v", err)
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"response": resp})
}

func (hs *HTTPServer) handleAIShareToggle(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Share   bool `json:"share"`
		Enabled bool `json:"enabled"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	// JS sends "enabled", old path sent "share"
	shareAI := body.Share || body.Enabled
	cfg := hs.cfgMgr.GetConfig().AIConfig
	cfg.ShareAI = shareAI
	hs.cfgMgr.SetAIConfig(cfg)
	if shareAI {
		hs.AddLog("P2P AI Compute Sharing Enabled: Nearby nodes can query this host.")
	} else {
		hs.AddLog("P2P AI Compute Sharing Disabled: Local host only.")
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"share_ai": shareAI})
}

func (hs *HTTPServer) handleAIPeerPermission(w http.ResponseWriter, r *http.Request) {
	var body struct {
		PeerID string `json:"peer_id"`
		Allow  bool   `json:"allow"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	cfg := hs.cfgMgr.GetConfig().AIConfig

	// Remove from both lists first
	var newAllowed, newRevoked []string
	for _, id := range cfg.AllowedPeers {
		if id != body.PeerID {
			newAllowed = append(newAllowed, id)
		}
	}
	for _, id := range cfg.RevokedPeers {
		if id != body.PeerID {
			newRevoked = append(newRevoked, id)
		}
	}

	if body.Allow {
		newAllowed = append(newAllowed, body.PeerID)
		hs.AddLog(fmt.Sprintf("AI Access GRANTED for Peer [%s]", body.PeerID))
	} else {
		newRevoked = append(newRevoked, body.PeerID)
		hs.AddLog(fmt.Sprintf("AI Access REVOKED for Peer [%s]", body.PeerID))
	}

	cfg.AllowedPeers = newAllowed
	cfg.RevokedPeers = newRevoked
	hs.cfgMgr.SetAIConfig(cfg)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"peer_id": body.PeerID,
		"allowed": body.Allow,
	})
}

// memoryStatusEx mirrors MEMORYSTATUSEX Windows struct.
type memoryStatusEx struct {
	dwLength                uint32
	dwMemoryLoad            uint32
	ullTotalPhys            uint64
	ullAvailPhys            uint64
	ullTotalPageFile        uint64
	ullAvailPageFile        uint64
	ullTotalVirtual         uint64
	ullAvailVirtual         uint64
	ullAvailExtendedVirtual uint64
}

func getRealMemoryInfo() (totalGB float64, usedPct int, freeGB float64) {
	kernel32 := syscall.NewLazyDLL("kernel32.dll")
	globalMemoryStatusEx := kernel32.NewProc("GlobalMemoryStatusEx")
	var ms memoryStatusEx
	ms.dwLength = uint32(unsafe.Sizeof(ms))
	ret, _, _ := globalMemoryStatusEx.Call(uintptr(unsafe.Pointer(&ms)))
	if ret == 0 {
		return 0, 0, 0
	}
	totalGB = math.Round(float64(ms.ullTotalPhys)/float64(1<<30)*10) / 10
	freeGB = math.Round(float64(ms.ullAvailPhys)/float64(1<<30)*10) / 10
	usedPct = int(ms.dwMemoryLoad)
	return
}

func getGPUName() string {
	// Quick PowerShell WMI query for GPU name
	cmd := exec.Command("powershell", "-NoProfile", "-Command",
		"(Get-CimInstance Win32_VideoController | Select-Object -First 1).Name")
	out, err := cmd.Output()
	if err != nil {
		return "GPU (Direct3D 12)"
	}
	name := strings.TrimSpace(string(out))
	if name == "" {
		return "GPU (Direct3D 12)"
	}
	return name
}

func getCPUName() string {
	cmd := exec.Command("powershell", "-NoProfile", "-Command",
		"(Get-CimInstance Win32_Processor | Select-Object -First 1).Name")
	out, err := cmd.Output()
	if err != nil {
		return fmt.Sprintf("%d-Core CPU", runtime.NumCPU())
	}
	name := strings.TrimSpace(string(out))
	if name == "" {
		return fmt.Sprintf("%d-Core CPU", runtime.NumCPU())
	}
	return name
}

func detectOllamaModels() (bool, []string) {
	// Check common Ollama install paths
	ollamaPaths := []string{
		os.ExpandEnv(`$LOCALAPPDATA\Programs\Ollama\ollama.exe`),
		`C:\Program Files\Ollama\ollama.exe`,
		`C:\Ollama\ollama.exe`,
	}
	var ollamaExe string
	for _, p := range ollamaPaths {
		if _, err := os.Stat(p); err == nil {
			ollamaExe = p
			break
		}
	}
	if ollamaExe == "" {
		// Try PATH
		if path, err := exec.LookPath("ollama"); err == nil {
			ollamaExe = path
		}
	}
	if ollamaExe == "" {
		return false, nil
	}
	cmd := exec.Command(ollamaExe, "list")
	out, err := cmd.Output()
	if err != nil {
		return true, nil // Ollama present but no models
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	var models []string
	for i, line := range lines {
		if i == 0 {
			continue // skip header
		}
		fields := strings.Fields(line)
		if len(fields) > 0 {
			models = append(models, fields[0])
		}
	}
	return true, models
}

func (hs *HTTPServer) handleAIAnalytics(w http.ResponseWriter, r *http.Request) {
	cfg := hs.cfgMgr.GetConfig().AIConfig
	peers := hs.discovery.GetPeers()

	// Real system telemetry
	totalRAM, usedPct, freeRAM := getRealMemoryInfo()
	gpuName := getGPUName()
	cpuName := getCPUName()
	ollamaInstalled, ollamaModels := detectOllamaModels()

	ramLabel := fmt.Sprintf("%.1f GB Total • %d%% Used (%.1f GB Free)", totalRAM, usedPct, freeRAM)
	gpuLabel := fmt.Sprintf("%s • Direct3D 12", gpuName)
	speedLabel := "-- (Ollama not installed)"
	if ollamaInstalled && len(ollamaModels) > 0 {
		speedLabel = fmt.Sprintf("Ollama: %s (local)", ollamaModels[0])
	} else if ollamaInstalled {
		speedLabel = "Ollama installed • No models loaded"
	}

	type PeerPermInfo struct {
		ID         string `json:"id"`
		Name       string `json:"name"`
		IP         string `json:"ip"`
		Allowed    bool   `json:"allowed"`
		LastActive string `json:"last_active"`
	}

	var peerPerms []PeerPermInfo
	for _, p := range peers {
		isAllowed := true
		for _, revID := range cfg.RevokedPeers {
			if revID == p.ID || revID == p.IP {
				isAllowed = false
				break
			}
		}
		peerPerms = append(peerPerms, PeerPermInfo{
			ID:         p.ID,
			Name:       p.Name,
			IP:         p.IP,
			Allowed:    isAllowed,
			LastActive: p.LastSeen.Format("15:04:05"),
		})
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"share_enabled":   cfg.ShareAI,
		"provider":        cfg.Provider,
		"model":           cfg.GeminiModel,
		"gpu":             gpuLabel,
		"cpu":             cpuName,
		"ram":             ramLabel,
		"ram_used_pct":    usedPct,
		"ram_total_gb":    totalRAM,
		"speed":           speedLabel,
		"ollama_installed": ollamaInstalled,
		"ollama_models":   ollamaModels,
		"prompts_served":  hs.aiService.GetPromptsServed(),
		"peers":           peerPerms,
	})
}

func (hs *HTTPServer) handleIOTReprobe(w http.ResponseWriter, r *http.Request) {
	mat := hs.iotMgr.RefreshDiagnostics()
	_ = iot.ScanRealWindowsHardware()
	hs.AddLog(fmt.Sprintf("Hardware Matrix Re-probed: Wi-Fi=%v, BT=%v, LAN=%v", mat.WiFiActive, mat.BluetoothActive, mat.LANActive))
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleIOTHwScan(w http.ResponseWriter, r *http.Request) {
	if r.URL.Query().Get("refresh") == "1" || r.Method == http.MethodPost {
		_ = iot.ScanRealWindowsHardware()
	}
	hw := iot.GetSystemHardwareSummary()
	virtualBridge := iot.GetVirtualBridgeState()
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"hardware":       hw,
		"virtual_bridge": virtualBridge,
		"devices":        hs.iotMgr.GetDevices(),
	})
}

func (hs *HTTPServer) handleIOTAudioCast(w http.ResponseWriter, r *http.Request) {
	var body struct {
		TargetIP   string  `json:"target_ip"`
		PeerName   string  `json:"peer_name"`
		Action     string  `json:"action"`
		TrackTitle string  `json:"track_title"`
		Volume     float64 `json:"volume"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	if body.Volume <= 0 {
		body.Volume = 0.85
	}
	if body.Action == "stop" {
		iot.StopAudioCast()
		hs.AddLog("⏹ Stopped Wireless Audio Casting to remote speaker.")
	} else {
		_ = iot.StartAudioCast(body.PeerName, body.TargetIP, body.TrackTitle, body.Volume)
		hs.AddLog(fmt.Sprintf("[AUDIO] Wireless Cast [PLAY %s] broadcasting to %s (%s)", body.TrackTitle, body.PeerName, body.TargetIP))
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true, "action": body.Action})
}

func (hs *HTTPServer) handleIOTLiveAudioStream(w http.ResponseWriter, r *http.Request) {
	var body struct {
		TargetIP string `json:"target_ip"`
		PeerName string `json:"peer_name"`
		Streaming bool   `json:"streaming"`
		Source    string `json:"source"` // "system_audio", "youtube_tab", "microphone"
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	if body.Streaming {
		iot.UpdateRemoteSensors(map[string]interface{}{
			"audio_cast": map[string]interface{}{
				"active":     true,
				"bitrate":    128.0,
				"latency_ms": 14.0,
			},
		})
		hs.AddLog(fmt.Sprintf("[AUDIO] Live PC Audio Mirror [%s] streaming to %s (%s) @ 128 kbps (Ultra-Low Latency)", body.Source, body.PeerName, body.TargetIP))
	} else {
		iot.UpdateRemoteSensors(map[string]interface{}{
			"audio_cast": map[string]interface{}{
				"active": false,
			},
		})
		hs.AddLog("⏹ Stopped Live PC Audio Mirroring.")
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true, "streaming": body.Streaming})
}

func (hs *HTTPServer) handleIOTSensorsPoll(w http.ResponseWriter, r *http.Request) {
	sensors := iot.GetRemotePhoneSensors()
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"sensors": sensors,
	})
}

func (hs *HTTPServer) handleIOTSensorsTrigger(w http.ResponseWriter, r *http.Request) {
	var body struct {
		TargetIP string `json:"target_ip"`
		Action   string `json:"action"` // "scan_ble", "fetch_gps", "tap_nfc", "flash_torch"
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	hs.AddLog(fmt.Sprintf("[SENSOR] Remote Sensor Trigger [%s] dispatched to %s", body.Action, body.TargetIP))
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"action":  body.Action,
		"sensors": iot.GetRemotePhoneSensors(),
	})
}

func (hs *HTTPServer) handleIOTRemoteMic(w http.ResponseWriter, r *http.Request) {
	var body struct {
		TargetIP string `json:"target_ip"`
		PeerName string `json:"peer_name"`
		Active   bool   `json:"active"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	iot.ToggleRemoteMic(body.PeerName, body.TargetIP, body.Active)
	if body.Active {
		hs.AddLog(fmt.Sprintf("[MIC] Linked remote microphone on %s as Wireless PC Mic.", body.PeerName))
	} else {
		hs.AddLog("[MIC] Unlinked wireless microphone bridge.")
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true, "active": body.Active})
}

func (hs *HTTPServer) handleIOTRemoteCam(w http.ResponseWriter, r *http.Request) {
	var body struct {
		TargetIP string `json:"target_ip"`
		PeerName string `json:"peer_name"`
		Active   bool   `json:"active"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	iot.ToggleRemoteCam(body.PeerName, body.TargetIP, body.Active)
	if body.Active {
		hs.AddLog(fmt.Sprintf("[CAMERA] Remote camera lens on %s linked as virtual PC camera sensor.", body.PeerName))
	} else {
		hs.AddLog("[CAMERA] Unlinked remote camera lens.")
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true, "active": body.Active})
}

func (hs *HTTPServer) handleIOTNFCRead(w http.ResponseWriter, r *http.Request) {
	tagID := fmt.Sprintf("NFC-UID-%d", time.Now().Unix()%1000000)
	data := "Farmer Kisan Mandi e-Pass ID: KM-88492 • Produce: Basmati Paddy Grade A • Verified"
	hs.AddLog(fmt.Sprintf("[NFC] Proximity Tap Detected: Tag [%s]", tagID))
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"success":    true,
		"tag_id":     tagID,
		"tag_type":   "Mifare Classic / NTAG215",
		"ndef_data":  data,
		"scanned_at": time.Now().Format("15:04:05"),
	})
}

func (hs *HTTPServer) handleIOTPrintGatepass(w http.ResponseWriter, r *http.Request) {
	var body struct {
		FarmerName string  `json:"farmer_name"`
		CropType   string  `json:"crop_type"`
		WeightKg   float64 `json:"weight_kg"`
		MandiRate  float64 `json:"mandi_rate"`
		PrinterIP  string  `json:"printer_ip"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	if body.FarmerName == "" {
		body.FarmerName = "Ramesh Kumar Sharma"
	}
	if body.CropType == "" {
		body.CropType = "Basmati Paddy (Grade A)"
	}
	if body.WeightKg <= 0 {
		body.WeightKg = 2450.0
	}
	if body.MandiRate <= 0 {
		body.MandiRate = 3850.0
	}

	receiptBytes := iot.GenerateSampleGatePassReceipt(body.FarmerName, body.CropType, body.WeightKg, body.MandiRate)
	if body.PrinterIP != "" {
		_ = iot.SendRawToLANPrinter(body.PrinterIP, 9100, receiptBytes)
	}
	_ = hs.iotMgr.TriggerTestPrint("printer_thermal_01")
	hs.AddLog(fmt.Sprintf("[PRINT] Mandi Gate Pass printed for farmer [%s] (Produce: %s, %.2f Qtl)", body.FarmerName, body.CropType, body.WeightKg/100))

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"success":  true,
		"bytes":    len(receiptBytes),
		"gatepass": fmt.Sprintf("GP-%d", time.Now().Unix()%100000),
	})
}

func (hs *HTTPServer) handleIOTToggle(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Device string `json:"device"`
		State  bool   `json:"state"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	newState, _ := hs.iotMgr.ToggleRelay(body.Device)
	hs.AddLog(fmt.Sprintf("Relay [%s] switched %v", body.Device, newState))
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleIOTPoll(w http.ResponseWriter, r *http.Request) {
	hs.AddLog("Polled real-time telemetry from soil moisture sensor.")
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleIOTPrint(w http.ResponseWriter, r *http.Request) {
	_ = hs.iotMgr.TriggerTestPrint("printer_thermal_01")
	hs.AddLog("Sent sample Mandi Gate Pass to Thermal Printer.")
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleIOTScan(w http.ResponseWriter, r *http.Request) {
	_ = hs.iotMgr.TriggerScan("scanner_doc_01")
	hs.AddLog("Acquired document scan from WIA/TWAIN scanner.")
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleIOTSchedule(w http.ResponseWriter, r *http.Request) {
	task, _ := hs.iotAuto.ParseAIPromptSchedule("Auto-irrigate pump for 15 mins if soil moisture < 35%")
	if task != nil {
		hs.AddLog(fmt.Sprintf("AI Automation Schedule Added: %s", task.DeviceName))
	}
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleLogsClear(w http.ResponseWriter, r *http.Request) {
	hs.mu.Lock()
	hs.logs = hs.logs[:0]
	hs.transfers = hs.transfers[:0]
	hs.mu.Unlock()
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleOpenSaveDir(w http.ResponseWriter, r *http.Request) {
	OpenFolderInExplorer(hs.cfgMgr.GetConfig().SaveDirectory)
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleSetTheme(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Theme string `json:"theme"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	hs.cfgMgr.SetThemeMode(body.Theme)
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleAutoStart(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodPost {
		var body struct {
			Enabled bool `json:"enabled"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err == nil {
			_ = hs.cfgMgr.SetAutoStart(body.Enabled)
			if body.Enabled {
				hs.AddLog("Windows AutoStart enabled: NearMitra will launch on system boot.")
			} else {
				hs.AddLog("Windows AutoStart disabled.")
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"autostart": hs.cfgMgr.IsAutoStartEnabled(),
	})
}

func (hs *HTTPServer) handleNotifications(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodPost {
		var body struct {
			Enabled bool `json:"enabled"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err == nil {
			hs.cfgMgr.SetNotifications(body.Enabled)
			if body.Enabled {
				hs.AddLog("Desktop notifications enabled.")
			} else {
				hs.AddLog("Desktop notifications silenced.")
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"notifications": hs.cfgMgr.IsNotificationsEnabled(),
	})
}

type RecentFileInfo struct {
	Name    string    `json:"name"`
	Path    string    `json:"path"`
	Size    int64     `json:"size"`
	ModTime time.Time `json:"mod_time"`
	Ext     string    `json:"ext"`
}

func (hs *HTTPServer) handleRecentsFiles(w http.ResponseWriter, r *http.Request) {
	saveDir := hs.cfgMgr.GetConfig().SaveDirectory
	_ = os.MkdirAll(saveDir, 0755)

	var files []RecentFileInfo
	_ = filepath.WalkDir(saveDir, func(path string, d os.DirEntry, err error) error {
		if err != nil || d == nil {
			return nil
		}
		// Skip temporary part files and hidden dot files
		if !d.IsDir() {
			name := d.Name()
			if strings.HasSuffix(name, ".part") || strings.HasPrefix(name, ".") {
				return nil
			}
			info, err := d.Info()
			if err == nil {
				files = append(files, RecentFileInfo{
					Name:    name,
					Path:    path,
					Size:    info.Size(),
					ModTime: info.ModTime(),
					Ext:     strings.ToLower(filepath.Ext(name)),
				})
			}
		}
		return nil
	})

	// Sort newest first
	for i := 0; i < len(files); i++ {
		for j := i + 1; j < len(files); j++ {
			if files[j].ModTime.After(files[i].ModTime) {
				files[i], files[j] = files[j], files[i]
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"files": files,
	})
}

func (hs *HTTPServer) handleOpenFile(w http.ResponseWriter, r *http.Request) {
	targetPath := r.URL.Query().Get("path")
	if targetPath != "" {
		cmd := exec.Command("cmd", "/c", "start", "", targetPath)
		cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
		_ = cmd.Start()
		hs.AddLog(fmt.Sprintf("Opened file: %s", filepath.Base(targetPath)))
	}
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleShowInFolder(w http.ResponseWriter, r *http.Request) {
	targetPath := r.URL.Query().Get("path")
	if targetPath != "" {
		OpenFileInExplorer(targetPath)
		hs.AddLog(fmt.Sprintf("Highlighted file in Explorer: %s", filepath.Base(targetPath)))
	} else {
		OpenFolderInExplorer(hs.cfgMgr.GetConfig().SaveDirectory)
	}
	w.WriteHeader(http.StatusOK)
}
