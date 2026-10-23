package transfer

import (
	"encoding/json"
	"nearmitra-windows-app/internal/models"
	"net"
	"testing"
	"time"
)

func TestMobileQuotedReplySurvivesReceiveAndAck(t *testing.T) {
	stored := make(chan models.ChatMessage, 1)
	ts := &TransferServer{callbacks: TransferCallbacks{OnIncomingMessage: func(m models.ChatMessage) error { stored <- m; return nil }}}
	client, server := net.Pipe()
	defer client.Close()
	client.SetDeadline(time.Now().Add(3 * time.Second))
	go ts.handleConnection(server)
	// Actual Flutter snake_case wire keys, not Go field names.
	packet := `{"type":"chat","sender_id":"phone","sender":"Phone","msg_id":"reply","text":"Yes","reply_to_id":"original","reply_to_sender":"PC","reply_to_text":"Send the file?","is_forwarded":true,"require_ack":true}`
	if _, err := client.Write([]byte(packet + "\n")); err != nil {
		t.Fatal(err)
	}
	var ack models.WireHeader
	if err := json.NewDecoder(client).Decode(&ack); err != nil {
		t.Fatal(err)
	}
	got := <-stored
	if got.ReplyToID != "original" || got.ReplyToSender != "PC" || got.ReplyToText != "Send the file?" || !got.IsForwarded || ack.Status != "delivered" {
		t.Fatalf("metadata lost: %+v ack %+v", got, ack)
	}
}
func TestMessageMetadataUsesSameIdentityOnWire(t *testing.T) {
	h := models.WireHeader{Type: "file"}
	m := models.ChatMessage{ID: "forward-1", Kind: "folder", IsForwarded: true, ReplyToID: "original", ReplyToText: "Quote"}
	applyMessageMetadata(&h, []models.ChatMessage{m})
	if h.MsgID != m.ID || !h.IsForwarded || !h.Folder || h.ReplyToID != "original" {
		t.Fatalf("wire metadata missing: %+v", h)
	}
}
func TestMobileReactionSetAndRemoveUseOriginalMessageID(t *testing.T) {
	for _, emoji := range []string{"❤️", ""} {
		result := make(chan []string, 1)
		ts := &TransferServer{callbacks: TransferCallbacks{OnIncomingReaction: func(id, reaction, peer string) { result <- []string{id, reaction, peer} }}}
		client, server := net.Pipe()
		go ts.handleConnection(server)
		client.SetDeadline(time.Now().Add(3 * time.Second))
		json.NewEncoder(client).Encode(map[string]string{"type": "reaction", "sender_id": "phone", "msg_id": "original", "reaction": emoji})
		select {
		case got := <-result:
			if got[0] != "original" || got[1] != emoji || got[2] != "phone" {
				t.Fatal(got)
			}
		case <-time.After(3 * time.Second):
			t.Fatal("reaction not delivered")
		}
		client.Close()
	}
}
