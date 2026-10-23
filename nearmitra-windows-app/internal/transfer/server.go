// Package transfer implements the TCP port 43889 socket server and client for files, chat, and streaming.
package transfer

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"strings"
	"sync"
	"time"

	"nearmitra-windows-app/internal/ai"
	"nearmitra-windows-app/internal/calling"
	"nearmitra-windows-app/internal/config"
	"nearmitra-windows-app/internal/models"
	"nearmitra-windows-app/internal/network"
)

// TransferCallbacks defines event hooks for incoming TCP events.
type TransferCallbacks struct {
	OnIncomingMessage  func(msg models.ChatMessage) error
	OnIncomingReaction func(targetMsgID string, reaction string, peerID string)
	OnTypingStatus     func(peerID string, isTyping bool)
	OnTransferProgress func(progress models.TransferProgress)
	OnAIRequest        func(prompt string, senderID string, senderName string, conn net.Conn)
	OnCallInvite       func(senderID string, senderName string, isVideo bool)
	OnCctvControl      func(action string, senderID string)
	OnStreamSignal     func(peerIP string, header models.WireHeader)
}

// TransferServer runs the inbound TCP server on port 43889.
type TransferServer struct {
	listener  net.Listener
	callbacks TransferCallbacks
	stopChan  chan struct{}
	mu        sync.RWMutex
	running   bool
}

var (
	serverInstance *TransferServer
	serverOnce     sync.Once
)

// GetServer returns the singleton TransferServer.
func GetServer() *TransferServer {
	serverOnce.Do(func() {
		serverInstance = &TransferServer{
			stopChan: make(chan struct{}),
		}
	})
	return serverInstance
}

// SetCallbacks configures event listeners for the transfer server.
func (ts *TransferServer) SetCallbacks(cb TransferCallbacks) {
	ts.mu.Lock()
	ts.callbacks = cb
	ts.mu.Unlock()
}

// Start launches the TCP transfer socket listener.
func (ts *TransferServer) Start() error {
	ts.mu.Lock()
	if ts.running {
		ts.mu.Unlock()
		return nil
	}

	listener, err := net.Listen("tcp", fmt.Sprintf("0.0.0.0:%d", models.TransferPort))
	if err != nil {
		ts.mu.Unlock()
		return err
	}

	ts.listener = listener
	ts.running = true
	ts.stopChan = make(chan struct{})
	ts.mu.Unlock()

	go ts.acceptLoop()
	return nil
}

// Stop closes the server socket and terminates connections.
func (ts *TransferServer) Stop() {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	if !ts.running {
		return
	}
	ts.running = false
	close(ts.stopChan)
	if ts.listener != nil {
		_ = ts.listener.Close()
	}
}

func (ts *TransferServer) acceptLoop() {
	for {
		conn, err := ts.listener.Accept()
		if err != nil {
			select {
			case <-ts.stopChan:
				return
			default:
				time.Sleep(100 * time.Millisecond)
				continue
			}
		}
		go ts.handleConnection(conn)
	}
}

func (ts *TransferServer) handleConnection(conn net.Conn) {
	defer conn.Close()
	reader := bufio.NewReader(conn)

	// Read line containing JSON header
	line, err := reader.ReadBytes('\n')
	if err != nil && len(line) == 0 {
		return
	}
	line = bytes.TrimSpace(line)
	if len(line) == 0 {
		data, readErr := io.ReadAll(reader)
		if readErr == nil && len(data) > 0 {
			line = bytes.TrimSpace(data)
		} else {
			return
		}
	}

	var header models.WireHeader
	if err := json.Unmarshal(line, &header); err != nil {
		log.Printf("[TransferServer] JSON Unmarshal error from %s: %v | Raw: %s", conn.RemoteAddr(), err, string(line))
		return
	}

	log.Printf("[TransferServer] Incoming TCP packet from %s: type=%s, sender=%s", conn.RemoteAddr(), header.Type, header.Sender)

	ts.mu.RLock()
	cb := ts.callbacks
	ts.mu.RUnlock()

	senderID := header.SenderID
	if senderID == "" {
		senderID = header.ID
	}
	senderName := header.Sender
	if senderName == "" {
		senderName = header.Name
	}

	peerIP, _, err := net.SplitHostPort(conn.RemoteAddr().String())
	if err != nil {
		peerIP = conn.RemoteAddr().String()
	}
	if senderID == "" {
		senderID = peerIP
	}

	// Always ensure peer is registered in discovery upon direct TCP connection
	if peerIP != "" && senderID != "" {
		avatarEmoji := header.AvatarEmoji
		if avatarEmoji == "" {
			avatarEmoji = header.Emoji
		}
		if avatarEmoji == "" {
			avatarEmoji = header.Avatar
		}
		network.GetDiscovery().RegisterPeer(senderID, senderName, peerIP, models.TransferPort, header.AIHost, avatarEmoji)
		network.GetDiscovery().SetPeerIdentity(senderID, header.InternetDeviceID, header.SupportsDeliveryAck)
	}

	switch header.Type {
	case "hello":
		// Respond with hello handshake to confirm presence & device identity
		cfg := config.Get().GetConfig()
		resp := models.WireHeader{
			Type:                "hello",
			SupportsDeliveryAck: true,
			InternetDeviceID:    cfg.DeviceID,
			Sender:              cfg.DeviceName,
			SenderID:            cfg.DeviceID,
			ID:                  cfg.DeviceID,
			Name:                cfg.DeviceName,
			AvatarEmoji:         cfg.AvatarEmoji,
			Emoji:               cfg.AvatarEmoji,
			Avatar:              cfg.AvatarEmoji,
		}
		respData, _ := json.Marshal(resp)
		_, _ = conn.Write(append(respData, '\n'))

	case "chat", "text":
		text := header.Message
		if text == "" {
			text = header.Text
		}
		msgID := header.MsgID
		if msgID == "" {
			msgID = header.TargetMsgID
		}
		if msgID == "" {
			msgID = fmt.Sprintf("msg_%d", time.Now().UnixNano())
		}
		if text != "" && cb.OnIncomingMessage != nil {
			storeErr := cb.OnIncomingMessage(models.ChatMessage{
				ID:     msgID,
				PeerID: senderID,
				PeerIP: peerIP,
				Sender: senderName,
				Text:   text,
				Mine:   false,
				At:     time.Now(),
				Kind:   "text",
				IsAi:   header.AIHost,
				Status: "Delivered", ReplyToID: header.ReplyToID, ReplyToSender: header.ReplyToSender, ReplyToText: header.ReplyToText, IsForwarded: header.IsForwarded,
			})
			ts.writeDeliveryAck(conn, header, storeErr)
		}

	case "reaction":
		targetID := header.TargetMsgID
		if targetID == "" {
			targetID = header.MsgID
		}
		if cb.OnIncomingReaction != nil {
			cb.OnIncomingReaction(targetID, header.Reaction, senderID)
		}

	case "typing":
		isTyping := header.IsTyping || header.Message == "true"
		if cb.OnTypingStatus != nil {
			cb.OnTypingStatus(senderID, isTyping)
			if peerIP != "" && peerIP != senderID {
				cb.OnTypingStatus(peerIP, isTyping)
			}
		}

	case "file", "folder":
		ts.writeDeliveryAck(conn, header, ts.receiveFileStream(reader, header, cb, senderID, senderName, peerIP))

	case "ai_request", "ai_prompt", "ai_req", "ai_chat":
		cfg := config.Get().GetConfig()
		allowed, reason := ai.SharedAccess(cfg.AIConfig, senderID, header.InternetDeviceID, peerIP)
		reply := map[string]interface{}{"type": "ai_response", "sender": cfg.DeviceName + " AI", "sender_id": cfg.DeviceID, "done": true}
		if !allowed {
			reply["status"] = "disabled"
			reply["error_code"] = "ai_disabled"
			reply["reply"] = reason
			reply["message"] = reason
			_ = json.NewEncoder(conn).Encode(reply)
			return
		}
		prompt := header.Prompt
		if prompt == "" {
			prompt = header.Message
		}
		if prompt == "" {
			prompt = header.Text
		}
		if strings.TrimSpace(prompt) == "" {
			reply["status"] = "error"
			reply["error"] = "Prompt is empty"
			_ = json.NewEncoder(conn).Encode(reply)
			return
		}
		if cb.OnAIRequest != nil {
			cb.OnAIRequest(prompt, senderID, senderName, conn)
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		defer cancel()
		encoder := json.NewEncoder(conn)
		var outputMu sync.Mutex
		send := func(packet map[string]interface{}) error {
			outputMu.Lock()
			defer outputMu.Unlock()
			_ = conn.SetWriteDeadline(time.Now().Add(15 * time.Second))
			return encoder.Encode(packet)
		}
		// Phone's line reader remains responsive while a local model is loading.
		go func() {
			ticker := time.NewTicker(10 * time.Second)
			defer ticker.Stop()
			for {
				select {
				case <-ctx.Done():
					return
				case <-ticker.C:
					if err := send(map[string]interface{}{"type": "ai_stream", "status": "loading", "done": false}); err != nil {
						cancel()
						return
					}
				}
			}
		}()
		// A stopped remote request cancels model generation without waiting for its next token.
		go func() { var one [1]byte; _, _ = conn.Read(one[:]); cancel() }()

		err := ai.Get().StreamSharedResponse(ctx, prompt, func(delta string) error {
			// Re-check revocations during a long answer, before sending another token.
			current := config.Get().GetConfig().AIConfig
			if ok, why := ai.SharedAccess(current, senderID, header.InternetDeviceID, peerIP); !ok {
				return fmt.Errorf("%s", why)
			}
			return send(map[string]interface{}{"type": "ai_stream", "sender": cfg.DeviceName + " AI", "sender_id": cfg.DeviceID, "reply": delta, "done": false, "status": "streaming", "provider": cfg.AIConfig.Provider})
		})
		reply["reply"] = ""
		if err != nil {
			reply["status"] = "error"
			reply["error"] = err.Error()
		} else {
			reply["status"] = "done"
		}
		_ = send(reply)

	case "call_invite", "call_accepted", "call_declined", "call_ended", "call_video_toggle":
		kind := header.Type
		if kind == "call_invite" {
			switch header.CallAction {
			case "end":
				kind = "call_ended"
			case "decline":
				kind = "call_declined"
			case "accept", "answer":
				kind = "call_accepted"
			}
		}
		if kind == "call_invite" {
			video := header.IsVideo || header.CallType == "video"
			if !calling.GetCall().SetIncoming(peerIP, senderName, video) {
				_ = calling.SendControl(peerIP, "call_declined")
				return
			}
			if cb.OnCallInvite != nil {
				cb.OnCallInvite(senderID, senderName, video)
			}
		} else if kind != "call_video_toggle" {
			if !calling.GetCall().ApplyRemote(kind, peerIP) {
				return
			}
		}
		header.Type = kind
		if cb.OnStreamSignal != nil {
			cb.OnStreamSignal(peerIP, header)
		}

	case "cctv_ctrl":
		if cb.OnCctvControl != nil {
			cb.OnCctvControl(header.CctvAction, senderID)
		}
		if cb.OnStreamSignal != nil {
			cb.OnStreamSignal(peerIP, header)
		}

	case "wireless_audio_pending", "wireless_audio_request", "wireless_audio_offer", "wireless_audio_answer", "wireless_audio_ice", "wireless_audio_stop", "wireless_audio_reject":
		if cb.OnStreamSignal != nil {
			cb.OnStreamSignal(peerIP, header)
		}

	case "stream_offer", "stream_answer", "stream_ice", "stream_control", "stream_rejected", "stream_stopped", "webrtc_offer", "webrtc_answer", "webrtc_ice":
		if cb.OnStreamSignal != nil {
			cb.OnStreamSignal(peerIP, header)
		}
	}
}

func (ts *TransferServer) writeDeliveryAck(conn net.Conn, header models.WireHeader, err error) {
	if !header.RequireAck {
		return
	}
	reply := models.WireHeader{Type: "delivery_ack", MsgID: header.MsgID, Status: "delivered"}
	if err != nil {
		reply.Status = "failed"
		reply.Error = err.Error()
	}
	_ = json.NewEncoder(conn).Encode(reply)
}

func (ts *TransferServer) receiveFileStream(reader *bufio.Reader, header models.WireHeader, cb TransferCallbacks, senderID, senderName, peerIP string) error {
	started := time.Now()
	id := header.MsgID
	if id == "" {
		id = fmt.Sprintf("msg_file_%d", time.Now().UnixNano())
	}
	kind := "file"
	if header.Folder || header.Type == "folder" {
		kind = "folder"
	}
	progress := models.TransferProgress{ID: id, PeerID: senderID, PeerIP: peerIP, Kind: kind, Active: true, Direction: "download", PeerName: senderName, FileName: header.Name, BytesTotal: header.Size, StartTime: started, ETASeconds: -1}
	report := func() {
		if cb.OnTransferProgress != nil {
			cb.OnTransferProgress(progress)
		}
	}
	report()
	lastReport := started
	tracked := &progressReader{Reader: reader, OnRead: func(received int64) {
		progress.BytesSent = received
		seconds := time.Since(started).Seconds()
		if seconds > 0 {
			progress.SpeedMBps = float64(received) / (1024 * 1024) / seconds
		}
		if progress.SpeedMBps > 0 {
			progress.ETASeconds = float64(header.Size-received) / (progress.SpeedMBps * 1024 * 1024)
		}
		if time.Since(lastReport) >= 100*time.Millisecond || received == header.Size {
			report()
			lastReport = time.Now()
		}
	}}
	path, err := StoreReceivedFile(config.Get().GetConfig().SaveDirectory, header.Name, header.Folder || header.Type == "folder", tracked, header.Size)
	if err != nil {
		log.Printf("[TransferServer] Receive failed for %s: %v", header.Name, err)
		if cb.OnTransferProgress != nil {
			progress.Active = false
			progress.Error = err.Error()
			report()
		}
		return err
	}
	if cb.OnIncomingMessage == nil {
		progress.Active = false
		progress.Error = "message storage is unavailable"
		report()
		return fmt.Errorf("message storage is unavailable")
	}
	err = cb.OnIncomingMessage(models.ChatMessage{ID: id, PeerID: senderID, PeerIP: peerIP, Sender: senderName,
		Mine: false, At: time.Now(), Kind: kind, FileName: header.Name, FileSize: header.Size, FilePath: path, Status: "Delivered", ReplyToID: header.ReplyToID, ReplyToSender: header.ReplyToSender, ReplyToText: header.ReplyToText, IsForwarded: header.IsForwarded})
	progress.Active = false
	if err == nil {
		progress.Complete = true
		progress.BytesSent = header.Size
		progress.ETASeconds = 0
	} else {
		progress.Error = err.Error()
	}
	report()
	return err
}

type progressReader struct {
	io.Reader
	received int64
	OnRead   func(int64)
}

func (r *progressReader) Read(buffer []byte) (int, error) {
	n, err := r.Reader.Read(buffer)
	r.received += int64(n)
	if n > 0 && r.OnRead != nil {
		r.OnRead(r.received)
	}
	return n, err
}
