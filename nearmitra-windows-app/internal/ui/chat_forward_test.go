package ui

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"nearmitra-windows-app/internal/chat"
	"nearmitra-windows-app/internal/models"
	"nearmitra-windows-app/internal/network"
)

func isolatedChatServer(t *testing.T) *HTTPServer {
	return &HTTPServer{chatMgr: chat.NewHistory(filepath.Join(t.TempDir(), "history.json")), discovery: network.GetDiscovery()}
}
func TestForwardFileServesStoredBytesAndArchivesFolder(t *testing.T) {
	hs := isolatedChatServer(t)
	for _, folder := range []bool{false, true} {
		dir := t.TempDir()
		path := filepath.Join(dir, "note.txt")
		if err := os.WriteFile(path, []byte("saved file"), 0600); err != nil {
			t.Fatal(err)
		}
		kind := "file"
		id := "file"
		if folder {
			path = dir
			kind = "folder"
			id = "folder"
		}
		hs.chatMgr.AddMessage(models.ChatMessage{ID: id, FileName: "note.txt", FilePath: path, Kind: kind})
		w := httptest.NewRecorder()
		hs.handleChatForwardFile(w, httptest.NewRequest(http.MethodGet, "/api/chat/forward-file?id="+id, nil))
		if w.Code != 200 {
			t.Fatal(w.Code, w.Body.String())
		}
		data := w.Body.Bytes()
		if folder {
			z, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
			if err != nil {
				t.Fatal(err)
			}
			if len(z.File) != 1 || z.File[0].Name != "note.txt" {
				t.Fatal("incorrect archive", z.File)
			}
			f, _ := z.File[0].Open()
			data, _ = io.ReadAll(f)
			f.Close()
		}
		if string(data) != "saved file" {
			t.Fatal("wrong attachment bytes")
		}
	}
}
func TestForwardRejectsMissingAndOfflineInsteadOfSuccess(t *testing.T) {
	hs := isolatedChatServer(t)
	hs.chatMgr.AddMessage(models.ChatMessage{ID: "original", Text: "hello"})
	for _, test := range []struct {
		body string
		code int
	}{{`{"id":"unknown","peer_id":"unknown"}`, 404}, {`{"id":"original","peer_id":"unknown"}`, 503}} {
		w := httptest.NewRecorder()
		hs.handleChatForward(w, httptest.NewRequest(http.MethodPost, "/api/chat/forward", strings.NewReader(test.body)))
		if w.Code != test.code {
			t.Fatal(w.Code, w.Body.String())
		}
	}
	if len(hs.chatMgr.GetMessages()) != 1 {
		t.Fatal("failed forwarding created a sent message")
	}
}
func TestIncomingWANReactionChecksPeerAndPersistsClear(t *testing.T) {
	hs := isolatedChatServer(t)
	hs.chatMgr.AddMessage(models.ChatMessage{ID: "m", PeerID: "phone"})
	for _, test := range []struct {
		peer, emoji string
		code        int
	}{{"unrelated", "❤️", 404}, {"phone", "❤️", 200}, {"phone", "", 200}} {
		b, _ := json.Marshal(map[string]interface{}{"incoming": true, "peer_id": test.peer, "msg_id": "m", "emoji": test.emoji})
		w := httptest.NewRecorder()
		hs.handleChatReact(w, httptest.NewRequest(http.MethodPost, "/api/chat/react", bytes.NewReader(b)))
		if w.Code != test.code {
			t.Fatal(w.Code, w.Body.String())
		}
	}
	if hs.chatMgr.GetMessages()[0].Reaction != "" {
		t.Fatal("reaction did not clear")
	}
}

func TestSentBrowserFileIsStoredWithSameIDForForwarding(t *testing.T) {
	hs := isolatedChatServer(t)
	var body bytes.Buffer
	form := multipart.NewWriter(&body)
	meta := models.ChatMessage{ID: "sent-file", PeerID: "phone", FileName: "report.txt", FileSize: 5, Kind: "file", IsForwarded: true}
	encoded, _ := json.Marshal(meta)
	form.WriteField("message", string(encoded))
	part, _ := form.CreateFormFile("file", "report.txt")
	part.Write([]byte("hello"))
	form.Close()
	request := httptest.NewRequest(http.MethodPost, "/api/chat/cache-attachment", &body)
	request.Header.Set("Content-Type", form.FormDataContentType())
	w := httptest.NewRecorder()
	hs.handleChatCacheAttachment(w, request)
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	var stored models.ChatMessage
	json.Unmarshal(w.Body.Bytes(), &stored)
	if stored.ID != meta.ID || !stored.Mine || !stored.IsForwarded || stored.Status != "Sent" || !strings.HasPrefix(stored.FilePath, hs.chatMgr.AttachmentDirectory()) {
		t.Fatalf("sent attachment not retained: %+v", stored)
	}
	out := httptest.NewRecorder()
	hs.handleChatForwardFile(out, httptest.NewRequest(http.MethodGet, "/api/chat/forward-file?id=sent-file", nil))
	if out.Code != 200 || out.Body.String() != "hello" {
		t.Fatal("sent attachment cannot be forwarded", out.Code, out.Body.String())
	}
}
