// Package ui provides embedded HTTP/REST server and native Windows 11 launcher.
package ui

import (
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"log"
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
	"nearmitra-windows-app/internal/wan"
)

//go:embed web/*
var webFS embed.FS

// HTTPServer manages local embedded web GUI server.
type HTTPServer struct {
	mu            sync.RWMutex
	port          int
	cfgMgr        *config.ConfigManager
	discovery     *network.DiscoveryService
	server        *transfer.TransferServer
	chatMgr       *chat.HistoryManager
	aiService     *ai.AIService
	cctv          *streaming.StreamState
	signaling     *calling.CallState
	iotMgr        *iot.Manager
	iotAuto       *iot.AutomationEngine
	logs          []string
	transfers     []models.TransferProgress
	streamSignals []StreamSignalEvent
	signalMu      sync.Mutex
	typingPeers   map[string]time.Time
	typingMu      sync.RWMutex
}

// StreamSignalEvent represents incoming WebRTC stream signals from network peers.
type StreamSignalEvent struct {
	PeerIP   string            `json:"peer_ip"`
	Header   models.WireHeader `json:"header"`
	Received time.Time         `json:"received"`
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
	if strings.HasPrefix(header.Type, "wireless_audio_") && header.Reason != "" {
		hs.AddLog(fmt.Sprintf("[AUDIO] %s from %s: %s", header.Type, peerIP, header.Reason))
		log.Printf("[AUDIO] %s from %s: %s", header.Type, peerIP, header.Reason)
	}
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

// serveEmbeddedUI serves the same embedded assets used by the installed app.
func serveEmbeddedUI(w http.ResponseWriter, r *http.Request) {
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
	} else if path == "app.js" || path == "chat-routing.js" || path == "nearby-call.js" || path == "audio-capture.js" || path == "wireless-audio.js" || path == "chat-transfers.js" || path == "native-audio.js" || path == "native-audio-worklet.js" || path == "native-pcm-buffer.js" {
		data, err := fs.ReadFile(webFS, "web/"+path)
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
}

// routes defines the embedded UI and API handlers.
func (hs *HTTPServer) routes() *http.ServeMux {
	mux := http.NewServeMux()

	mux.HandleFunc("/", serveEmbeddedUI)

	// API Endpoints
	mux.HandleFunc("/api/audio/devices", hs.handleAudioDevices)
	mux.HandleFunc("/api/audio/loopback", hs.handleAudioLoopback)
	mux.HandleFunc("/api/state", hs.handleState)
	mux.HandleFunc("/api/discovery/rescan", hs.handleDiscoveryRescan)
	mux.HandleFunc("/api/lan/scan", hs.handleLANScan)
	mux.HandleFunc("/api/manual-pair", hs.handleManualPair)
	mux.HandleFunc("/api/profile/update", hs.handleProfileUpdate)
	mux.HandleFunc("/api/profile/reset", hs.handleProfileReset)
	mux.HandleFunc("/api/send-file", hs.handleSendFile)
	mux.HandleFunc("/api/send-file-upload", hs.handleSendFileUpload)
	mux.HandleFunc("/api/send-folder", hs.handleSendFolder)
	mux.HandleFunc("/api/chat/send", hs.handleChatSend)
	mux.HandleFunc("/api/chat/receive-file", hs.handleChatReceiveFile)
	mux.HandleFunc("/api/chat/cache-attachment", hs.handleChatCacheAttachment)
	mux.HandleFunc("/api/chat/folder-archive", hs.handleChatFolderArchive)
	mux.HandleFunc("/api/chat/react", hs.handleChatReact)
	mux.HandleFunc("/api/chat/forward", hs.handleChatForward)
	mux.HandleFunc("/api/chat/forward-file", hs.handleChatForwardFile)
	mux.HandleFunc("/api/chat/typing", hs.handleChatTyping)
	mux.HandleFunc("/api/chat/clear", hs.handleChatClear)
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
	mux.HandleFunc("/api/ai/nearby-query", hs.handleNearbyAIQuery)
	mux.HandleFunc("/api/ai/selected-sharing", hs.handleSelectedAISharing)
	mux.HandleFunc("/api/ai/share-toggle", hs.handleAIShareToggle)
	mux.HandleFunc("/api/ai/peer-permission", hs.handleAIPeerPermission)
	mux.HandleFunc("/api/ai/analytics", hs.handleAIAnalytics)
	mux.HandleFunc("/api/iot/config", hs.handleIOTConfig)
	mux.HandleFunc("/api/iot/scale", hs.handleIOTScale)
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

	// WAN / Internet Mesh Endpoints
	mux.HandleFunc("/api/wan/state", hs.handleWanState)
	mux.HandleFunc("/api/wan/toggle", hs.handleWanToggle)
	mux.HandleFunc("/api/wan/mode", hs.handleWanMode)
	mux.HandleFunc("/api/wan/pair-code/generate", hs.handleWanPairCodeGenerate)
	mux.HandleFunc("/api/wan/pair-code/cancel", hs.handleWanPairCodeCancel)
	mux.HandleFunc("/api/wan/pair-code/claim", hs.handleWanPairCodeClaim)
	mux.HandleFunc("/api/wan/request/send", hs.handleWanRequestSend)
	mux.HandleFunc("/api/wan/request/respond", hs.handleWanRequestRespond)
	mux.HandleFunc("/api/wan/trusted/remove", hs.handleWanTrustedRemove)
	mux.HandleFunc("/api/wan/session/create", hs.handleWanSessionCreate)
	mux.HandleFunc("/api/wan/session/accept", hs.handleWanSessionAccept)
	mux.HandleFunc("/api/wan/session/candidate", hs.handleWanSessionCandidate)
	mux.HandleFunc("/api/wan/session/get", hs.handleWanSessionGet)
	mux.HandleFunc("/api/wan/session/incoming", hs.handleWanSessionIncoming)
	mux.HandleFunc("/api/wan/session/delete", hs.handleWanSessionDelete)

	return mux
}

// Start launches embedded web server.
func (hs *HTTPServer) Start() error {
	mux := hs.routes()
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
	pendingCall := hs.signaling.Snapshot()

	resp := map[string]interface{}{
		"local_device": map[string]interface{}{
			"id":           hs.cfgMgr.GetConfig().DeviceID,
			"name":         hs.cfgMgr.GetConfig().DeviceName,
			"avatar_emoji": hs.cfgMgr.GetConfig().AvatarEmoji,
			"ip":           router.IPv4,
		},
		"peers":         peers,
		"lan_devices":   lanDevs,
		"typing_peers":  hs.GetTypingPeers(),
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
		"voice": pendingCall,
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
		http.Error(w, "Select an available Nearby device", 400)
		return
	}
	sent, err := hs.sendChatAttachment(targetIP, filePath, false)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(502)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"file": filepath.Base(filePath), "message": sent})
}

// handleSendFileUpload receives drag-dropped file bytes from the browser,
// saves them to a temp file, and sends to the target peer.
func (hs *HTTPServer) handleSendFileUpload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	targetIP := r.URL.Query().Get("ip")
	if targetIP == "" {
		http.Error(w, "Selected device is offline or unavailable. Reconnect before sending files.", http.StatusBadRequest)
		return
	}

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
	defer r.MultipartForm.RemoveAll()

	path, err := transfer.StoreReceivedFile(hs.chatMgr.AttachmentDirectory(), header.Filename, false, file, header.Size)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	sent, err := hs.sendChatAttachment(targetIP, path, false)
	if err != nil {
		http.Error(w, err.Error(), 502)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"file": header.Filename, "size": header.Size, "message": sent})
}

func (hs *HTTPServer) handleSendFolder(w http.ResponseWriter, r *http.Request) {
	targetIP := r.URL.Query().Get("ip")
	folder, err := SelectFolderDialog(hs.cfgMgr.GetConfig().SaveDirectory)
	if err == nil && folder != "" {
		if targetIP == "" {
			http.Error(w, "Select an available Nearby device", 400)
			return
		}
		sent, err := hs.sendChatAttachment(targetIP, folder, true)
		if err != nil {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(502)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]interface{}{"folder": filepath.Base(folder), "message": sent})
		return
	}
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleChatSend(w http.ResponseWriter, r *http.Request) {
	var msg models.ChatMessage
	if err := json.NewDecoder(r.Body).Decode(&msg); err != nil {
		http.Error(w, "invalid message", 400)
		return
	}
	if msg.ID == "" {
		msg.ID = fmt.Sprintf("msg_%d", time.Now().UnixNano())
	}
	if msg.At.IsZero() {
		msg.At = time.Now()
	}
	if msg.Mine && !msg.IsWan && msg.Kind != "file" && msg.Kind != "folder" {
		ip := msg.PeerIP
		for _, peer := range hs.discovery.GetPeers() {
			if peer.ID == msg.PeerID || peer.InternetDeviceID == msg.PeerID {
				if peer.IsOnline {
					ip = peer.IP
				}
				break
			}
		}
		if ip == "" || strings.HasPrefix(ip, "wan") {
			http.Error(w, "Nearby device unavailable", 503)
			return
		}
		if err := transfer.SendTextMessage(ip, msg.ID, msg.Text, msg); err != nil {
			msg.Status = "Queued"
			_ = hs.chatMgr.AddMessage(msg)
			http.Error(w, err.Error(), 502)
			return
		}
		msg.Status = "Sent"
	}
	if err := hs.chatMgr.AddMessage(msg); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(msg)
}

func (hs *HTTPServer) handleChatReceiveFile(w http.ResponseWriter, r *http.Request) {
	hs.handleChatFileStorage(w, r, false)
}
func (hs *HTTPServer) handleChatCacheAttachment(w http.ResponseWriter, r *http.Request) {
	hs.handleChatFileStorage(w, r, true)
}
func (hs *HTTPServer) handleChatFileStorage(w http.ResponseWriter, r *http.Request, outgoing bool) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", 405)
		return
	}
	if err := r.ParseMultipartForm(16 << 20); err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	defer r.MultipartForm.RemoveAll()
	var msg models.ChatMessage
	if err := json.Unmarshal([]byte(r.FormValue("message")), &msg); err != nil {
		http.Error(w, "invalid metadata", 400)
		return
	}
	input, header, err := r.FormFile("file")
	if err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	defer input.Close()
	if msg.FileSize != header.Size {
		http.Error(w, "incomplete transfer", 400)
		return
	}
	directory := hs.chatMgr.AttachmentDirectory()
	if !outgoing {
		directory = hs.cfgMgr.GetConfig().SaveDirectory
	}
	msg.FilePath, err = transfer.StoreReceivedFile(directory, msg.FileName, msg.Kind == "folder", input, header.Size)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	msg.Mine = outgoing
	msg.IsWan = true
	msg.Status = "Delivered"
	if outgoing {
		msg.Status = "Sent"
	}
	if msg.Kind == "" {
		msg.Kind = "file"
	}
	if err := hs.chatMgr.AddMessage(msg); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(msg)
}

func (hs *HTTPServer) handleChatReact(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", 405)
		return
	}
	var body struct {
		TargetIP string `json:"target_ip"`
		MsgID    string `json:"msg_id"`
		Emoji    string `json:"emoji"`
		PeerID   string `json:"peer_id"`
		Incoming bool   `json:"incoming"`
	}
	if json.NewDecoder(r.Body).Decode(&body) != nil || body.MsgID == "" {
		http.Error(w, "Invalid reaction", 400)
		return
	}
	if body.Incoming {
		if !hs.chatMgr.SetPeerReaction(body.MsgID, body.Emoji, hs.reactionPeerAliases(body.PeerID)...) {
			http.Error(w, "Message not found for peer", 404)
			return
		}
	} else {
		if body.TargetIP != "" {
			if err := transfer.SendReaction(body.TargetIP, body.MsgID, body.Emoji); err != nil {
				http.Error(w, err.Error(), 502)
				return
			}
		}
		if !hs.chatMgr.SetLocalReaction(body.MsgID, body.Emoji) {
			http.Error(w, "Message not found", 404)
			return
		}
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

func (hs *HTTPServer) handleChatClear(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var body struct {
		PeerID   string `json:"peer_id"`
		PeerIP   string `json:"peer_ip"`
		Sender   string `json:"sender"`
		ClearAll bool   `json:"clear_all"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)

	if body.ClearAll {
		hs.chatMgr.ClearAllChat()
		hs.AddLog("[CHAT] All conversation history deleted permanently.")
	} else {
		hs.chatMgr.ClearChat(body.PeerID, body.PeerIP, body.Sender)
		hs.AddLog(fmt.Sprintf("[CHAT] Cleared chat history for peer [%s / %s / %s]", body.PeerID, body.PeerIP, body.Sender))
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true})
}

func (hs *HTTPServer) handleProfileUpdate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var body struct {
		Name  string `json:"name"`
		Emoji string `json:"emoji"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	if body.Name != "" || body.Emoji != "" {
		hs.cfgMgr.SetDeviceIdentity(body.Name, body.Emoji)
		hs.AddLog(fmt.Sprintf("[PROFILE] Updated device identity: name='%s', emoji='%s'", body.Name, body.Emoji))
		go hs.discovery.ScanLANNow()
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"success":      true,
		"device_name":  hs.cfgMgr.GetConfig().DeviceName,
		"avatar_emoji": hs.cfgMgr.GetConfig().AvatarEmoji,
	})
}

func (hs *HTTPServer) handleProfileReset(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	name, emoji := hs.cfgMgr.ResetDeviceIdentity()
	hs.AddLog(fmt.Sprintf("[PROFILE] Reset device identity to hardware defaults: '%s' (%s)", name, emoji))
	go hs.discovery.ScanLANNow()
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"success":      true,
		"device_name":  name,
		"avatar_emoji": emoji,
	})
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

	if net.ParseIP(targetIP) == nil {
		http.Error(w, "Select a Nearby device", 400)
		return
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
	if strings.HasPrefix(sigType, "wireless_audio_") {
		if reason, ok := signalPayload["reason"].(string); ok && reason != "" {
			hs.AddLog(fmt.Sprintf("[AUDIO] %s to %s: %s", sigType, targetIP, reason))
			log.Printf("[AUDIO] %s to %s: %s", sigType, targetIP, reason)
		}
	}
	if sigType == "" {
		sigType, _ = rawMap["type"].(string)
		signalPayload["type"] = sigType
	}

	if targetIP != "" {
		err := transfer.SendWebRTCSignal(targetIP, signalPayload)
		if err != nil {
			hs.AddLog(fmt.Sprintf("[WARN] Failed to send [%s] stream signal to %s: %v", sigType, targetIP, err))
			http.Error(w, err.Error(), 502)
			return
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
	if err := OpenFolderInExplorer(recDir); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
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
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"muted": muted})
}

func (hs *HTTPServer) handleVoiceEnd(w http.ResponseWriter, r *http.Request) {
	hs.signaling.EndCall()
	hs.AddLog("Voice call session ended.")
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true})
}

func (hs *HTTPServer) handleCallInvite(w http.ResponseWriter, r *http.Request) {
	var body struct {
		TargetIP string `json:"target_ip"`
		PeerID   string `json:"peer_id"`
		PeerName string `json:"peer_name"`
		IsVideo  bool   `json:"is_video"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	if err := hs.signaling.InviteCall(body.TargetIP, body.PeerID, body.PeerName, body.IsVideo); err != nil {
		http.Error(w, err.Error(), 502)
		return
	}
	callType := "HD Audio"
	if body.IsVideo {
		callType = "HD Video"
	}
	hs.AddLog(fmt.Sprintf("[CALL] WebRTC %s Call initiated with %s (%s)", callType, body.PeerName, body.TargetIP))
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true, "is_video": body.IsVideo})
}

func (hs *HTTPServer) handleCallAnswer(w http.ResponseWriter, r *http.Request) {
	if err := hs.signaling.AnswerCall(); err != nil {
		http.Error(w, err.Error(), 502)
		return
	}
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
	if strings.TrimSpace(body.PeerID) == "" || body.PeerID == "unknown_device_id" {
		http.Error(w, "Select a device", 400)
		return
	}
	ids := map[string]bool{body.PeerID: true}
	for _, peer := range hs.discovery.GetPeers() {
		if peer.ID == body.PeerID || peer.InternetDeviceID == body.PeerID || peer.IP == body.PeerID {
			ids[peer.ID] = true
			if peer.InternetDeviceID != "" && peer.InternetDeviceID != "unknown_device_id" {
				ids[peer.InternetDeviceID] = true
			}
			// Remove legacy IP grants when changing this device's permission.
			ids[peer.IP] = true
		}
	}
	// Remove from both lists first
	var newAllowed, newRevoked []string
	for _, id := range cfg.AllowedPeers {
		if !ids[id] {
			newAllowed = append(newAllowed, id)
		}
	}
	for _, id := range cfg.RevokedPeers {
		if !ids[id] {
			newRevoked = append(newRevoked, id)
		}
	}

	if body.Allow {
		for id := range ids {
			if net.ParseIP(id) == nil {
				newAllowed = append(newAllowed, id)
			}
		}
		hs.AddLog(fmt.Sprintf("AI Access GRANTED for Peer [%s]", body.PeerID))
	} else {
		for id := range ids {
			if net.ParseIP(id) == nil {
				newRevoked = append(newRevoked, id)
			}
		}
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
		isAllowed := ai.PeerAllowed(cfg, p.ID, p.InternetDeviceID, p.IP)
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
		"share_enabled":    cfg.ShareAI,
		"provider":         cfg.Provider,
		"model":            cfg.GeminiModel,
		"gpu":              gpuLabel,
		"cpu":              cpuName,
		"ram":              ramLabel,
		"ram_used_pct":     usedPct,
		"ram_total_gb":     totalRAM,
		"speed":            speedLabel,
		"ollama_installed": ollamaInstalled,
		"ollama_models":    ollamaModels,
		"prompts_served":   hs.aiService.GetPromptsServed(),
		"peers":            peerPerms,
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
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"hardware": hw,
		"devices":  hs.iotMgr.GetDevices(),
	})
}

func (hs *HTTPServer) handleIOTAudioCast(w http.ResponseWriter, r *http.Request) {
	http.Error(w, "Use the audio sharing controls to establish a Nearby WebRTC connection.", http.StatusNotImplemented)
}

func (hs *HTTPServer) handleIOTLiveAudioStream(w http.ResponseWriter, r *http.Request) {
	http.Error(w, "Audio streaming requires a connected WebRTC session in the desktop app.", http.StatusNotImplemented)
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
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", 405)
		return
	}
	var body struct {
		TargetIP string `json:"target_ip"`
	}
	if json.NewDecoder(r.Body).Decode(&body) != nil {
		http.Error(w, "Invalid request", 400)
		return
	}
	found := false
	if hs.discovery != nil {
		for _, peer := range hs.discovery.GetPeers() {
			if peer.IP == body.TargetIP && peer.IsOnline {
				found = true
				break
			}
		}
	}
	if !found {
		http.Error(w, "Select an online Nearby phone", 400)
		return
	}
	sensors, err := transfer.RequestPhoneTelemetry(body.TargetIP)
	if err != nil {
		http.Error(w, err.Error(), 502)
		return
	}
	iot.ReplaceRemoteSnapshot(sensors)
	writeIOTJSON(w, map[string]interface{}{"success": true, "sensors": iot.GetRemotePhoneSensors()})
}

func (hs *HTTPServer) handleIOTRemoteMic(w http.ResponseWriter, r *http.Request) {
	http.Error(w, "Use Listen to Phone Microphone and accept the call on the phone.", http.StatusNotImplemented)
}

func (hs *HTTPServer) handleIOTRemoteCam(w http.ResponseWriter, r *http.Request) {
	http.Error(w, "Use the Nearby CCTV viewer. No Windows virtual camera driver is installed by NearMitra.", http.StatusNotImplemented)
}

func (hs *HTTPServer) handleIOTNFCRead(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", 405)
		return
	}
	var data map[string]interface{}
	var err error
	if iot.GetGatewayConfig().NFCURL != "" {
		data, err = iot.ReadGateway(r.Context(), "nfc")
	} else {
		type nfcResult struct {
			data map[string]interface{}
			err  error
		}
		completed := make(chan nfcResult, 1)
		go func() { d, e := iot.ReadLocalNFCTag(); completed <- nfcResult{d, e} }()
		select {
		case result := <-completed:
			data, err = result.data, result.err
		case <-time.After(8 * time.Second):
			err = fmt.Errorf("NFC reader timed out; reconnect the reader and try again")
		case <-r.Context().Done():
			return
		}
	}
	if err != nil {
		http.Error(w, err.Error(), 503)
		return
	}
	writeIOTJSON(w, data)
}

func (hs *HTTPServer) handleIOTPrintGatepass(w http.ResponseWriter, r *http.Request) {
	var body struct {
		FarmerName string  `json:"farmer_name"`
		CropType   string  `json:"crop_type"`
		WeightKg   float64 `json:"weight_kg"`
		MandiRate  float64 `json:"mandi_rate"`
		PrinterIP  string  `json:"printer_ip"`
	}
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, "Invalid print request", http.StatusBadRequest)
		return
	}
	if net.ParseIP(body.PrinterIP) == nil {
		http.Error(w, "Enter the LAN printer IP address", http.StatusBadRequest)
		return
	}
	if strings.TrimSpace(body.FarmerName) == "" || strings.TrimSpace(body.CropType) == "" || body.WeightKg <= 0 || body.MandiRate < 0 || math.IsNaN(body.WeightKg) || math.IsInf(body.WeightKg, 0) {
		http.Error(w, "Enter a farmer name, crop, positive weight and non-negative rate", http.StatusBadRequest)
		return
	}
	receiptBytes := iot.GenerateSampleGatePassReceipt(body.FarmerName, body.CropType, body.WeightKg, body.MandiRate)
	if err := iot.SendRawToLANPrinter(body.PrinterIP, 9100, receiptBytes); err != nil {
		http.Error(w, "Printer connection failed: "+err.Error(), http.StatusBadGateway)
		return
	}
	hs.AddLog(fmt.Sprintf("[PRINT] Mandi Gate Pass printed for farmer [%s] (Produce: %s, %.2f Qtl)", body.FarmerName, body.CropType, body.WeightKg/100))

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"success":  true,
		"bytes":    len(receiptBytes),
		"gatepass": fmt.Sprintf("GP-%d", time.Now().Unix()%100000),
	})
}

func (hs *HTTPServer) handleIOTToggle(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", 405)
		return
	}
	var body struct {
		Channel int   `json:"channel"`
		State   *bool `json:"state"`
	}
	if json.NewDecoder(r.Body).Decode(&body) != nil || body.State == nil {
		http.Error(w, "channel and explicit state required", 400)
		return
	}
	state, err := iot.SetRelay(r.Context(), body.Channel, *body.State)
	if err != nil {
		http.Error(w, err.Error(), 502)
		return
	}
	writeIOTJSON(w, state)
}

func (hs *HTTPServer) handleIOTPoll(w http.ResponseWriter, r *http.Request) {
	state, err := iot.ReadGateway(r.Context(), "sensor")
	if err != nil {
		http.Error(w, err.Error(), 502)
		return
	}
	writeIOTJSON(w, state)
}

func (hs *HTTPServer) handleIOTPrint(w http.ResponseWriter, r *http.Request) {
	http.Error(w, "Configure a LAN printer in the gate pass form first.", http.StatusNotImplemented)
}

func (hs *HTTPServer) handleIOTScan(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	// Windows owns scan settings, device selection and the save dialog.
	cmd := exec.Command("wiaacmgr.exe")
	if err := cmd.Start(); err != nil {
		http.Error(w, "Windows scanner could not be opened: "+err.Error(), http.StatusServiceUnavailable)
		return
	}
	go func() { _ = cmd.Wait() }()
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"opened": true})
}

func (hs *HTTPServer) handleIOTSchedule(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodDelete {
		if err := iot.CancelRelaySchedule(r.URL.Query().Get("id")); err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		writeIOTJSON(w, iot.GetRelaySchedules())
		return
	}
	if r.Method == http.MethodGet {
		writeIOTJSON(w, iot.GetRelaySchedules())
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "GET or POST required", 405)
		return
	}
	var schedule iot.RelaySchedule
	if json.NewDecoder(r.Body).Decode(&schedule) != nil {
		http.Error(w, "Invalid schedule", 400)
		return
	}
	if err := iot.AddRelaySchedule(schedule); err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	writeIOTJSON(w, iot.GetRelaySchedules())
}

func (hs *HTTPServer) handleLogsClear(w http.ResponseWriter, r *http.Request) {
	hs.mu.Lock()
	hs.logs = hs.logs[:0]
	hs.transfers = hs.transfers[:0]
	hs.mu.Unlock()
	w.WriteHeader(http.StatusOK)
}

func (hs *HTTPServer) handleOpenSaveDir(w http.ResponseWriter, r *http.Request) {
	if err := OpenFolderInExplorer(hs.cfgMgr.GetConfig().SaveDirectory); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
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
	target := r.URL.Query().Get("path")
	var err error
	if target != "" {
		err = OpenFileInExplorer(target)
	} else {
		err = OpenFolderInExplorer(hs.cfgMgr.GetConfig().SaveDirectory)
	}
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	w.WriteHeader(http.StatusOK)
}

// -----------------------------------------------------------------------------
// WAN / INTERNET MESH HANDLERS
// -----------------------------------------------------------------------------
func (hs *HTTPServer) handleWanState(w http.ResponseWriter, r *http.Request) {
	ws := wan.GetWanService()
	state := ws.GetState()
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(state)
}

func (hs *HTTPServer) handleWanToggle(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Enable bool `json:"enable"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	ws := wan.GetWanService()
	ws.SetInternetMode(req.Enable)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(ws.GetState())
}

func (hs *HTTPServer) handleWanMode(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Mode string `json:"mode"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	ws := wan.GetWanService()
	ws.SetDiscoveryMode(wan.WanDiscoveryMode(req.Mode))
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(ws.GetState())
}

func (hs *HTTPServer) handleWanPairCodeGenerate(w http.ResponseWriter, r *http.Request) {
	ws := wan.GetWanService()
	code, err := ws.GeneratePairCode()
	w.Header().Set("Content-Type", "application/json")
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	_ = json.NewEncoder(w).Encode(code)
}

func (hs *HTTPServer) handleWanPairCodeCancel(w http.ResponseWriter, r *http.Request) {
	ws := wan.GetWanService()
	ws.CancelPairCode()
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "cancelled"})
}

func (hs *HTTPServer) handleWanPairCodeClaim(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Code string `json:"code"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	ws := wan.GetWanService()
	dev, err := ws.ClaimPairCode(req.Code)
	w.Header().Set("Content-Type", "application/json")
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	_ = json.NewEncoder(w).Encode(dev)
}

func (hs *HTTPServer) handleWanRequestSend(w http.ResponseWriter, r *http.Request) {
	var req struct {
		TargetDeviceID string `json:"target_device_id"`
		TargetName     string `json:"target_name"`
		TargetPlatform string `json:"target_platform"`
		TargetAvatar   string `json:"target_avatar"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	ws := wan.GetWanService()
	dev, err := ws.SendDirectPairRequest(req.TargetDeviceID, req.TargetName, req.TargetPlatform, req.TargetAvatar)
	w.Header().Set("Content-Type", "application/json")
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	_ = json.NewEncoder(w).Encode(dev)
}

func (hs *HTTPServer) handleWanRequestRespond(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RequestID      string `json:"request_id"`
		FromDeviceID   string `json:"from_device_id"`
		FromDeviceName string `json:"from_device_name"`
		FromPlatform   string `json:"from_platform"`
		FromAvatar     string `json:"from_avatar"`
		Accept         bool   `json:"accept"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	ws := wan.GetWanService()
	err := ws.RespondPairRequest(req.RequestID, req.FromDeviceID, req.FromDeviceName, req.FromPlatform, req.FromAvatar, req.Accept)
	w.Header().Set("Content-Type", "application/json")
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "success"})
}

func (hs *HTTPServer) handleWanTrustedRemove(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DeviceID string `json:"device_id"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	ws := wan.GetWanService()
	ws.RemoveTrustedDevice(req.DeviceID)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "removed"})
}

func (hs *HTTPServer) handleWanSessionCreate(w http.ResponseWriter, r *http.Request) {
	var req struct {
		SessionID  string                 `json:"session_id"`
		ReceiverID string                 `json:"receiver_id"`
		Offer      map[string]interface{} `json:"offer"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	ws := wan.GetWanService()
	sID, err := ws.CreateSignalingSession(req.SessionID, req.ReceiverID, req.Offer)
	w.Header().Set("Content-Type", "application/json")
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	_ = json.NewEncoder(w).Encode(map[string]string{"session_id": sID})
}

func (hs *HTTPServer) handleWanSessionAccept(w http.ResponseWriter, r *http.Request) {
	var req struct {
		SessionID string                 `json:"session_id"`
		Answer    map[string]interface{} `json:"answer"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	ws := wan.GetWanService()
	err := ws.AcceptSignalingSession(req.SessionID, req.Answer)
	w.Header().Set("Content-Type", "application/json")
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "accepted"})
}

func (hs *HTTPServer) handleWanSessionCandidate(w http.ResponseWriter, r *http.Request) {
	var req struct {
		SessionID string                 `json:"session_id"`
		Role      string                 `json:"role"`
		Candidate map[string]interface{} `json:"candidate"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	ws := wan.GetWanService()
	err := ws.AddIceCandidate(req.SessionID, req.Role, req.Candidate)
	w.Header().Set("Content-Type", "application/json")
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "candidate_added"})
}

func (hs *HTTPServer) handleWanSessionGet(w http.ResponseWriter, r *http.Request) {
	sessionID := r.URL.Query().Get("id")
	ws := wan.GetWanService()
	data, err := ws.GetSession(sessionID)
	w.Header().Set("Content-Type", "application/json")
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	_ = json.NewEncoder(w).Encode(data)
}

func (hs *HTTPServer) handleWanSessionIncoming(w http.ResponseWriter, r *http.Request) {
	ws := wan.GetWanService()
	sessions, err := ws.GetIncomingSessions()
	w.Header().Set("Content-Type", "application/json")
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	_ = json.NewEncoder(w).Encode(sessions)
}

func (hs *HTTPServer) handleWanSessionDelete(w http.ResponseWriter, r *http.Request) {
	var req struct {
		SessionID string `json:"session_id"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	ws := wan.GetWanService()
	_ = ws.DeleteSession(req.SessionID)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "deleted"})
}

func (hs *HTTPServer) handleChatFolderArchive(w http.ResponseWriter, r *http.Request) {
	folder, err := SelectFolderDialog(hs.cfgMgr.GetConfig().SaveDirectory)
	if err != nil || folder == "" {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	dir, err := os.MkdirTemp("", "nearmitra-folder-*")
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer os.RemoveAll(dir)
	name := filepath.Base(folder) + ".zip"
	path := filepath.Join(dir, name)
	if err := transfer.ArchiveFolder(folder, path); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	w.Header().Set("Content-Type", "application/zip")
	w.Header().Set("X-Folder-Name", name)
	http.ServeFile(w, r, path)
}

func writeIOTJSON(w http.ResponseWriter, value interface{}) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(value)
}
func (hs *HTTPServer) handleIOTConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		writeIOTJSON(w, iot.GetGatewayConfig())
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "GET or POST required", 405)
		return
	}
	var cfg iot.GatewayConfig
	if json.NewDecoder(r.Body).Decode(&cfg) != nil {
		http.Error(w, "Invalid device configuration", 400)
		return
	}
	if err := iot.SaveGatewayConfig(cfg); err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	writeIOTJSON(w, cfg)
}
func (hs *HTTPServer) handleIOTScale(w http.ResponseWriter, r *http.Request) {
	var state map[string]interface{}
	var err error
	if r.Method == http.MethodPost {
		var body struct {
			Action string `json:"action"`
		}
		if json.NewDecoder(r.Body).Decode(&body) != nil || body.Action != "tare" {
			http.Error(w, "tare action required", 400)
			return
		}
		state, err = iot.TareScale(r.Context())
	} else if r.Method == http.MethodGet {
		state, err = iot.ReadGateway(r.Context(), "scale")
	} else {
		http.Error(w, "GET or POST required", 405)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), 502)
		return
	}
	writeIOTJSON(w, state)
}

func (hs *HTTPServer) reactionPeerAliases(id string) []string {
	aliases := []string{id, "wan://" + id}
	if hs.discovery != nil {
		for _, p := range hs.discovery.GetPeers() {
			if p.ID == id || p.InternetDeviceID == id {
				aliases = append(aliases, p.ID, p.InternetDeviceID, p.IP)
			}
		}
	}
	return aliases
}
