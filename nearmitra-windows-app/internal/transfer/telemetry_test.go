package transfer

import (
	"encoding/json"
	"net"
	"testing"
	"time"
)

func TestPhoneTelemetryRoundTripAndDenial(t *testing.T) {
	for _, denied := range []bool{false, true} {
		client, phone := net.Pipe()
		_ = client.SetDeadline(time.Now().Add(time.Second))
		go func() {
			defer phone.Close()
			var request map[string]interface{}
			_ = json.NewDecoder(phone).Decode(&request)
			if request["type"] != "sensor_request" {
				t.Error("wrong request type")
			}
			response := map[string]interface{}{"type": "sensor_response", "sensors": map[string]interface{}{"device_ip": "spoofed", "battery": map[string]interface{}{"level": 0}}}
			if denied {
				response["error"] = "Phone owner declined sensor sharing"
			}
			_ = json.NewEncoder(phone).Encode(response)
		}()
		data, err := exchangeTelemetry(client, "192.168.1.4", map[string]interface{}{"type": "sensor_request"})
		client.Close()
		if denied {
			if err == nil {
				t.Fatal("declined sharing accepted")
			}
		} else if err != nil || data["device_ip"] != "192.168.1.4" {
			t.Fatalf("incorrect phone snapshot: %+v %v", data, err)
		}
	}
}
