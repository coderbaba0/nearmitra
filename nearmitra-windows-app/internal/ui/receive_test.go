package ui

import (
	"bytes"
	"encoding/json"
	"mime/multipart"
	"nearmitra-windows-app/internal/chat"
	"nearmitra-windows-app/internal/config"
	"nearmitra-windows-app/internal/models"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestWanFileIsSavedBeforeDeliveredResponse(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	t.Setenv("USERPROFILE", t.TempDir())
	cfg := config.Get()
	cfg.SetSaveDirectory(t.TempDir())
	hs := &HTTPServer{cfgMgr: cfg, chatMgr: chat.NewHistory(filepath.Join(t.TempDir(), "history.json"))}
	for _, badSize := range []bool{false, true} {
		t.Run(map[bool]string{false: "complete", true: "truncated"}[badSize], func(t *testing.T) {
			var body bytes.Buffer
			form := multipart.NewWriter(&body)
			size := int64(5)
			if badSize {
				size = 100
			}
			m := models.ChatMessage{ID: "wan-file", PeerID: "mobile-wan", FileName: "mobile.txt", FileSize: size, Kind: "file"}
			meta, _ := json.Marshal(m)
			form.WriteField("message", string(meta))
			part, _ := form.CreateFormFile("file", "mobile.txt")
			part.Write([]byte("hello"))
			form.Close()
			r := httptest.NewRequest(http.MethodPost, "/api/chat/receive-file", &body)
			r.Header.Set("Content-Type", form.FormDataContentType())
			w := httptest.NewRecorder()
			hs.handleChatReceiveFile(w, r)
			if badSize {
				if w.Code != 400 {
					t.Fatalf("incomplete accepted: %d", w.Code)
				}
				return
			}
			if w.Code != 200 {
				t.Fatal(w.Body.String())
			}
			var saved models.ChatMessage
			if e := json.Unmarshal(w.Body.Bytes(), &saved); e != nil {
				t.Fatal(e)
			}
			content, e := os.ReadFile(saved.FilePath)
			if e != nil || string(content) != "hello" || saved.Status != "Delivered" {
				t.Fatalf("not persisted: %+v %s %v", saved, content, e)
			}
			if len(hs.chatMgr.GetMessages()) != 1 {
				t.Fatal("missing chat history")
			}
		})
	}
}
