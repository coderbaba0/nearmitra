// Package transfer implements the TCP port 43889 socket server and client for files, chat, and streaming.
package transfer

import (
	"archive/zip"
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"nearmitra-windows-app/internal/config"
	"nearmitra-windows-app/internal/models"
)

// TransferCallbacks defines event hooks for incoming TCP events.
type TransferCallbacks struct {
	OnIncomingMessage  func(msg models.ChatMessage)
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

	switch header.Type {
	case "hello":
		// Respond with hello handshake to confirm presence & device identity
		cfg := config.Get().GetConfig()
		resp := models.WireHeader{
			Type:     "hello",
			Sender:   cfg.DeviceName,
			SenderID: cfg.DeviceID,
			ID:       cfg.DeviceID,
			Name:     cfg.DeviceName,
		}
		respData, _ := json.Marshal(resp)
		_, _ = conn.Write(append(respData, '\n'))

	case "chat", "text":
		text := header.Message
		if text == "" {
			text = header.Text
		}
		if text != "" && cb.OnIncomingMessage != nil {
			cb.OnIncomingMessage(models.ChatMessage{
				ID:       header.TargetMsgID,
				PeerID:   senderID,
				Sender:   senderName,
				Text:     text,
				Mine:     false,
				At:       time.Now(),
				Kind:     "text",
				IsAi:     header.AIHost,
			})
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
		}

	case "file", "folder":
		ts.receiveFileStream(reader, header, cb)

	case "ai_request", "ai_prompt", "ai_req":
		prompt := header.Prompt
		if prompt == "" {
			prompt = header.Message
		}
		if cb.OnAIRequest != nil {
			cb.OnAIRequest(prompt, senderID, senderName, conn)
		}

	case "call_invite":
		isVideo := header.IsVideo || header.CallType == "video"
		if cb.OnCallInvite != nil {
			cb.OnCallInvite(senderID, senderName, isVideo)
		}

	case "cctv_ctrl":
		if cb.OnCctvControl != nil {
			cb.OnCctvControl(header.CctvAction, senderID)
		}
		if cb.OnStreamSignal != nil {
			cb.OnStreamSignal(peerIP, header)
		}

	case "stream_offer", "stream_answer", "stream_ice", "stream_control", "stream_rejected", "stream_stopped", "webrtc_offer", "webrtc_answer", "webrtc_ice":
		if cb.OnStreamSignal != nil {
			cb.OnStreamSignal(peerIP, header)
		}
	}
}

func (ts *TransferServer) receiveFileStream(reader *bufio.Reader, header models.WireHeader, cb TransferCallbacks) {
	cfg := config.Get().GetConfig()
	saveDir := cfg.SaveDirectory
	_ = os.MkdirAll(saveDir, 0755)

	targetPath := filepath.Join(saveDir, header.Name)
	tempPath := targetPath + ".part"

	outFile, err := os.Create(tempPath)
	if err != nil {
		return
	}

	hasher := sha256.New()
	multiWriter := io.MultiWriter(outFile, hasher)

	var received int64
	startTime := time.Now()
	buf := make([]byte, 64*1024)

	for received < header.Size {
		toRead := int64(len(buf))
		if (header.Size - received) < toRead {
			toRead = header.Size - received
		}

		n, err := reader.Read(buf[:toRead])
		if n > 0 {
			_, _ = multiWriter.Write(buf[:n])
			received += int64(n)

			if cb.OnTransferProgress != nil {
				elapsed := time.Since(startTime).Seconds()
				var speed float64
				if elapsed > 0.1 {
					speed = (float64(received) / (1024 * 1024)) / elapsed
				}
				cb.OnTransferProgress(models.TransferProgress{
					Active:     true,
					Direction:  "download",
					PeerName:   header.Sender,
					FileName:   header.Name,
					BytesTotal: header.Size,
					BytesSent:  received,
					SpeedMBps:  speed,
					StartTime:  startTime,
				})
			}
		}
		if err != nil {
			break
		}
	}

	_ = outFile.Close()

	if received == header.Size {
		_ = os.Rename(tempPath, targetPath)

		// Handle folder auto-extraction if transfer was an archived folder
		if header.Folder {
			destFolder := filepath.Join(saveDir, strings.TrimSuffix(header.Name, ".zip"))
			_ = extractZip(targetPath, destFolder)
			targetPath = destFolder
		}

		if cb.OnTransferProgress != nil {
			cb.OnTransferProgress(models.TransferProgress{
				Active:     false,
				Direction:  "download",
				PeerName:   header.Sender,
				FileName:   header.Name,
				BytesTotal: header.Size,
				BytesSent:  received,
				Complete:   true,
			})
		}

		if cb.OnIncomingMessage != nil {
			kind := "file"
			if header.Folder {
				kind = "folder"
			}
			cb.OnIncomingMessage(models.ChatMessage{
				PeerID:   header.SenderID,
				Sender:   header.Sender,
				Mine:     false,
				At:       time.Now(),
				Kind:     kind,
				FileName: header.Name,
				FileSize: header.Size,
				FilePath: targetPath,
				Status:   "Delivered",
			})
		}
	} else {
		_ = os.Remove(tempPath)
	}
}

// Helper to extract ZIP folder transfers
func extractZip(srcZip, destDir string) error {
	r, err := zip.OpenReader(srcZip)
	if err != nil {
		return err
	}
	defer r.Close()

	_ = os.MkdirAll(destDir, 0755)
	for _, f := range r.File {
		fpath := filepath.Join(destDir, f.Name)
		if f.FileInfo().IsDir() {
			_ = os.MkdirAll(fpath, os.ModePerm)
			continue
		}
		if err := os.MkdirAll(filepath.Dir(fpath), os.ModePerm); err != nil {
			continue
		}
		outFile, err := os.OpenFile(fpath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
		if err != nil {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			_ = outFile.Close()
			continue
		}
		_, _ = io.Copy(outFile, rc)
		_ = outFile.Close()
		_ = rc.Close()
	}
	return nil
}
