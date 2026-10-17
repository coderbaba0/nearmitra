package transfer

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"errors"
	"nearmitra-windows-app/internal/config"
	"nearmitra-windows-app/internal/models"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func archive(t *testing.T, name, content string) []byte {
	t.Helper()
	var b bytes.Buffer
	z := zip.NewWriter(&b)
	w, e := z.Create(name)
	if e != nil {
		t.Fatal(e)
	}
	w.Write([]byte(content))
	if e = z.Close(); e != nil {
		t.Fatal(e)
	}
	return b.Bytes()
}
func TestMobileFolderWithoutZipSuffix(t *testing.T) {
	data := archive(t, "notes/readme.txt", "mobile folder")
	p, e := StoreReceivedFile(t.TempDir(), "Documents", true, bytes.NewReader(data), int64(len(data)))
	if e != nil {
		t.Fatal(e)
	}
	b, e := os.ReadFile(filepath.Join(p, "notes", "readme.txt"))
	if e != nil || string(b) != "mobile folder" {
		t.Fatalf("not extracted: %s %v", b, e)
	}
}
func TestDuplicateNamesAndIncompleteFile(t *testing.T) {
	d := t.TempDir()
	a, e := StoreReceivedFile(d, "photo.txt", false, strings.NewReader("first"), 5)
	if e != nil {
		t.Fatal(e)
	}
	b, e := StoreReceivedFile(d, "photo.txt", false, strings.NewReader("next"), 4)
	if e != nil {
		t.Fatal(e)
	}
	if a == b {
		t.Fatal("overwritten")
	}
	if _, e = StoreReceivedFile(d, "broken.txt", false, strings.NewReader("part"), 100); e == nil {
		t.Fatal("truncated file accepted")
	}
	files, _ := os.ReadDir(d)
	if len(files) != 2 {
		t.Fatalf("partial file left: %v", files)
	}
}
func TestArchiveEscape(t *testing.T) {
	b := archive(t, "../outside.txt", "bad")
	if _, e := StoreReceivedFile(t.TempDir(), "folder", true, bytes.NewReader(b), int64(len(b))); e == nil {
		t.Fatal("escape accepted")
	}
}
func TestMobilePacketsStoredBeforeAck(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	t.Setenv("USERPROFILE", t.TempDir())
	config.Get().SetSaveDirectory(t.TempDir())
	for _, kind := range []string{"chat", "file", "folder"} {
		t.Run(kind, func(t *testing.T) {
			var stored models.ChatMessage
			ts := &TransferServer{callbacks: TransferCallbacks{OnIncomingMessage: func(m models.ChatMessage) error { stored = m; return nil }}}
			r, s := net.Pipe()
			defer s.Close()
			s.SetDeadline(time.Now().Add(3 * time.Second))
			go ts.handleConnection(r)
			b := []byte("from mobile")
			name := "hello.txt"
			if kind == "folder" {
				b = archive(t, "inside.txt", "nested")
				name = "PhoneFolder"
			}
			h := models.WireHeader{Type: kind, SenderID: "mobile-lan", InternetDeviceID: "mobile-wan", Sender: "Phone", MsgID: "mobile-" + kind, RequireAck: true, Name: name, Message: "hello", Size: int64(len(b)), Folder: kind == "folder"}
			if e := json.NewEncoder(s).Encode(h); e != nil {
				t.Fatal(e)
			}
			if kind != "chat" {
				if _, e := s.Write(b); e != nil {
					t.Fatal(e)
				}
			}
			var ack models.WireHeader
			if e := json.NewDecoder(s).Decode(&ack); e != nil {
				t.Fatal(e)
			}
			if ack.Status != "delivered" || ack.MsgID != h.MsgID || stored.ID != h.MsgID {
				t.Fatalf("unconfirmed: %+v %+v", ack, stored)
			}
			if kind != "chat" {
				if _, e := os.Stat(stored.FilePath); e != nil {
					t.Fatal(e)
				}
			}
		})
	}
}
func TestFailedStorageAck(t *testing.T) {
	ts := &TransferServer{callbacks: TransferCallbacks{OnIncomingMessage: func(models.ChatMessage) error { return errors.New("disk unavailable") }}}
	r, s := net.Pipe()
	defer s.Close()
	s.SetDeadline(time.Now().Add(3 * time.Second))
	go ts.handleConnection(r)
	json.NewEncoder(s).Encode(models.WireHeader{Type: "chat", SenderID: "phone", Message: "text", RequireAck: true, MsgID: "failure"})
	var ack models.WireHeader
	if e := json.NewDecoder(s).Decode(&ack); e != nil {
		t.Fatal(e)
	}
	if ack.Status != "failed" {
		t.Fatalf("false success: %+v", ack)
	}
}

func TestWindowsArchiveUsesPortablePaths(t *testing.T) {
	dir := t.TempDir()
	os.MkdirAll(filepath.Join(dir, "nested"), 0755)
	os.WriteFile(filepath.Join(dir, "nested", "hello.txt"), []byte("hello"), 0644)
	archivePath := filepath.Join(t.TempDir(), "folder.zip")
	if err := zipFolder(dir, archivePath); err != nil {
		t.Fatal(err)
	}
	z, err := zip.OpenReader(archivePath)
	if err != nil {
		t.Fatal(err)
	}
	defer z.Close()
	found := false
	for _, entry := range z.File {
		if strings.Contains(entry.Name, "\\") {
			t.Fatalf("Windows separator in archive: %s", entry.Name)
		}
		if entry.Name == "nested/hello.txt" {
			found = true
		}
	}
	if !found {
		t.Fatal("portable nested file missing")
	}
}
