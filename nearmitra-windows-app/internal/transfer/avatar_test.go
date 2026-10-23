package transfer

import (
	"encoding/json"
	"net"
	"testing"
	"time"

	"nearmitra-windows-app/internal/config"
	"nearmitra-windows-app/internal/models"
)

func TestDesktopHelloIncludesConfiguredAvatar(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	t.Setenv("USERPROFILE", t.TempDir())
	cfg := config.Get().GetConfig()
	defer config.Get().SetDeviceIdentity(cfg.DeviceName, cfg.AvatarEmoji)
	config.Get().SetDeviceIdentity("Office PC", "🖥️")

	client, server := net.Pipe()
	defer client.Close()
	client.SetDeadline(time.Now().Add(3 * time.Second))
	ts := &TransferServer{}
	go ts.handleConnection(server)
	if err := json.NewEncoder(client).Encode(models.WireHeader{Type: "hello", SenderID: "other-desktop", Sender: "Other PC"}); err != nil {
		t.Fatal(err)
	}
	var reply models.WireHeader
	if err := json.NewDecoder(client).Decode(&reply); err != nil {
		t.Fatal(err)
	}
	if reply.Name != "Office PC" || reply.AvatarEmoji != "🖥️" || reply.Emoji != "🖥️" || reply.Avatar != "🖥️" {
		t.Fatalf("desktop hello lost configured identity: %+v", reply)
	}
}
