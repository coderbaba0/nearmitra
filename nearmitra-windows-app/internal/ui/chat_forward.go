package ui

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"nearmitra-windows-app/internal/models"
	"nearmitra-windows-app/internal/transfer"
)

func (hs *HTTPServer) storedChatMessage(id string) (models.ChatMessage, bool) {
	for _, m := range hs.chatMgr.GetMessages() {
		if m.ID == id {
			return m, true
		}
	}
	return models.ChatMessage{}, false
}

// Forward uses a stored message, never a browser-supplied arbitrary file path.
func (hs *HTTPServer) handleChatForward(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", 405)
		return
	}
	var body struct {
		ID     string `json:"id"`
		PeerID string `json:"peer_id"`
	}
	if json.NewDecoder(r.Body).Decode(&body) != nil {
		http.Error(w, "Invalid forward request", 400)
		return
	}
	original, ok := hs.storedChatMessage(body.ID)
	if !ok {
		http.Error(w, "Original message is not saved yet", 404)
		return
	}
	var ip string
	for _, p := range hs.discovery.GetPeers() {
		if p.IsOnline && (p.ID == body.PeerID || p.InternetDeviceID == body.PeerID) {
			ip = p.IP
			break
		}
	}
	if ip == "" {
		http.Error(w, "Nearby recipient is unavailable", 503)
		return
	}
	forwarded := models.ChatMessage{ID: fmt.Sprintf("fwd_%d", time.Now().UnixNano()), PeerID: body.PeerID, PeerIP: ip, Sender: hs.cfgMgr.GetConfig().DeviceName, Mine: true, At: time.Now(), Text: original.Text, Kind: original.Kind, IsForwarded: true, FileName: original.FileName, FilePath: original.FilePath, FileSize: original.FileSize, Status: "Sending"}
	isFile := original.Kind == "file" || original.Kind == "folder" || original.FileName != "" || original.Attachment != nil
	if isFile {
		if original.FilePath == "" {
			http.Error(w, "File is not saved on this PC", 404)
			return
		}
		if _, err := os.Stat(original.FilePath); err != nil {
			http.Error(w, "Original file is no longer available on this PC", 404)
			return
		}
	}
	if err := hs.chatMgr.AddMessage(forwarded); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	var err error
	if isFile {
		info, statErr := os.Stat(original.FilePath)
		if statErr != nil {
			err = statErr
		} else if info.IsDir() {
			err = transfer.SendFolder(ip, original.FilePath, nil, forwarded)
		} else {
			err = transfer.SendFile(ip, original.FilePath, nil, forwarded)
		}
	} else {
		err = transfer.SendTextMessage(ip, forwarded.ID, original.Text, forwarded)
	}
	forwarded.Status = "Sent"
	if err != nil {
		forwarded.Status = "Failed"
	}
	if saveErr := hs.chatMgr.AddMessage(forwarded); saveErr != nil {
		http.Error(w, saveErr.Error(), 500)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), 502)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(forwarded)
}

// Supplies a stored attachment to the existing WAN file sender, including folders.
func (hs *HTTPServer) handleChatForwardFile(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", 405)
		return
	}
	m, ok := hs.storedChatMessage(r.URL.Query().Get("id"))
	if !ok || m.FilePath == "" {
		http.Error(w, "File is not saved on this PC", 404)
		return
	}
	info, err := os.Stat(m.FilePath)
	if err != nil {
		http.Error(w, "Original file is no longer available on this PC", 404)
		return
	}
	path := m.FilePath
	if info.IsDir() {
		dir, err := os.MkdirTemp("", "nearmitra-forward-*")
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer os.RemoveAll(dir)
		path = filepath.Join(dir, filepath.Base(m.FilePath)+".zip")
		if err = transfer.ArchiveFolder(m.FilePath, path); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
	}
	http.ServeFile(w, r, path)
}

// A common identity on disk, in chat and on the wire also makes file reactions work.
func (hs *HTTPServer) sendChatAttachment(ip, path string, folder bool) (models.ChatMessage, error) {
	info, err := os.Stat(path)
	if err != nil {
		return models.ChatMessage{}, err
	}
	id := fmt.Sprintf("attachment_%d", time.Now().UnixNano())
	peerID := ip
	for _, p := range hs.discovery.GetPeers() {
		if p.IP == ip {
			peerID = p.InternetDeviceID
			if peerID == "" || peerID == "unknown_device_id" {
				peerID = p.ID
			}
			break
		}
	}
	kind := "file"
	if folder {
		kind = "folder"
	}
	msg := models.ChatMessage{ID: id, PeerID: peerID, PeerIP: ip, Sender: hs.cfgMgr.GetConfig().DeviceName, Mine: true, At: time.Now(), Kind: kind, FileName: filepath.Base(path), FilePath: path, FileSize: info.Size(), Status: "Sending"}
	if folder {
		msg.FileSize = 0
	}
	if err = hs.chatMgr.AddMessage(msg); err != nil {
		return msg, err
	}
	if folder {
		err = transfer.SendFolder(ip, path, nil, msg)
	} else {
		err = transfer.SendFile(ip, path, nil, msg)
	}
	msg.Status = "Sent"
	if err != nil {
		msg.Status = "Failed"
	}
	if saveErr := hs.chatMgr.AddMessage(msg); saveErr != nil {
		return msg, saveErr
	}
	return msg, err
}
