package transfer

import (
	"archive/zip"
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"io"
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

func TestReceiveProgressStartsBeforePayloadAndPreservesIdentityThroughStorage(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	t.Setenv("USERPROFILE", t.TempDir())
	config.Get().SetSaveDirectory(t.TempDir())
	var events []models.TransferProgress
	var saved models.ChatMessage
	cb := TransferCallbacks{OnTransferProgress: func(p models.TransferProgress) { events = append(events, p) }, OnIncomingMessage: func(m models.ChatMessage) error { saved = m; return nil }}
	r, w := io.Pipe()
	done := make(chan error, 1)
	started := make(chan models.TransferProgress, 1)
	cb.OnTransferProgress = func(p models.TransferProgress) {
		events = append(events, p)
		if len(events) == 1 {
			started <- p
		}
	}
	go func() {
		done <- (&TransferServer{}).receiveFileStream(bufio.NewReader(r), models.WireHeader{Name: "same.txt", Size: 5}, cb, "phone", "Phone", "192.168.1.6")
	}()
	initial := <-started
	if !initial.Active || initial.BytesSent != 0 || initial.ID == "" || initial.PeerID != "phone" || initial.PeerIP != "192.168.1.6" || initial.ETASeconds != -1 {
		t.Fatalf("invalid initial progress: %+v", initial)
	}
	if _, err := w.Write([]byte("hello")); err != nil {
		t.Fatal(err)
	}
	w.Close()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	r.Close()
	last := events[len(events)-1]
	if last.Active || !last.Complete || last.ID != initial.ID || saved.ID != initial.ID || last.BytesSent != 5 || last.PeerIP != initial.PeerIP {
		t.Fatalf("progress/history identity changed: %+v %+v", last, saved)
	}
}
func TestFailedReceiveKeepsPeerAndTransferID(t *testing.T) {
	config.Get().SetSaveDirectory(t.TempDir())
	var events []models.TransferProgress
	err := (&TransferServer{}).receiveFileStream(bufio.NewReader(strings.NewReader("short")), models.WireHeader{MsgID: "failed", Name: "same.txt", Size: 100}, TransferCallbacks{OnTransferProgress: func(p models.TransferProgress) { events = append(events, p) }}, "phone2", "Phone 2", "192.168.1.7")
	if err == nil {
		t.Fatal("truncated receive succeeded")
	}
	last := events[len(events)-1]
	if last.Active || last.Complete || last.Error == "" || last.ID != "failed" || last.PeerID != "phone2" || last.PeerIP != "192.168.1.7" {
		t.Fatalf("failure lost sender: %+v", last)
	}
}
