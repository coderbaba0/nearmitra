package transfer

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"time"

	"nearmitra-windows-app/internal/config"
	"nearmitra-windows-app/internal/models"
)

// RequestPhoneTelemetry uses the existing Nearby TCP connection. The phone must
// explicitly approve sharing in its foreground app; older apps return an error.
func RequestPhoneTelemetry(ip string) (map[string]interface{}, error) {
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(ip, fmt.Sprint(models.TransferPort)), 4*time.Second)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(45 * time.Second))
	cfg := config.Get().GetConfig()
	return exchangeTelemetry(conn, ip, map[string]interface{}{"type": "sensor_request", "sender": cfg.DeviceName, "sender_id": cfg.DeviceID})
}
func exchangeTelemetry(conn io.ReadWriter, ip string, request map[string]interface{}) (map[string]interface{}, error) {
	if err := json.NewEncoder(conn).Encode(request); err != nil {
		return nil, err
	}
	var response struct {
		Type    string                 `json:"type"`
		Error   string                 `json:"error"`
		Sensors map[string]interface{} `json:"sensors"`
	}
	if err := json.NewDecoder(bufio.NewReader(io.LimitReader(conn, 64*1024))).Decode(&response); err != nil {
		return nil, fmt.Errorf("phone telemetry unavailable; update/open the mobile app and approve the request: %w", err)
	}
	if response.Error != "" {
		return nil, fmt.Errorf("%s", response.Error)
	}
	if response.Type != "sensor_response" || response.Sensors == nil {
		return nil, fmt.Errorf("phone does not support sensor telemetry")
	}
	response.Sensors["device_ip"] = ip
	return response.Sensors, nil
}
