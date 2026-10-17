package iot

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// GatewayConfig describes an explicitly configured JSON HTTP hardware adapter.
// Relays acknowledge POST {"power":bool}; telemetry is returned by GET.
type GatewayConfig struct {
	Relays    [4]string `json:"relays"`
	SensorURL string    `json:"sensor_url"`
	NFCURL    string    `json:"nfc_url"`
	ScaleURL  string    `json:"scale_url"`
}

var gatewayState = struct {
	sync.RWMutex
	Config GatewayConfig
	Path   string
}{}
var hardwareHTTP = &http.Client{Timeout: 5 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
var relayOperations sync.Mutex

func LoadGatewayConfig(path string) error {
	gatewayState.Lock()
	defer gatewayState.Unlock()
	gatewayState.Path = path
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	var cfg GatewayConfig
	if err = json.Unmarshal(data, &cfg); err != nil {
		return err
	}
	if err = validateGateway(cfg); err != nil {
		return err
	}
	gatewayState.Config = cfg
	return nil
}
func GetGatewayConfig() GatewayConfig {
	gatewayState.RLock()
	defer gatewayState.RUnlock()
	return gatewayState.Config
}
func validateGateway(cfg GatewayConfig) error {
	endpoints := append(cfg.Relays[:], cfg.SensorURL, cfg.NFCURL, cfg.ScaleURL)
	for _, endpoint := range endpoints {
		if endpoint == "" {
			continue
		}
		u, err := url.Parse(endpoint)
		if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Hostname() == "" || u.User != nil || u.Fragment != "" {
			return fmt.Errorf("use a valid http(s) device URL without embedded credentials")
		}
	}
	return nil
}
func SaveGatewayConfig(cfg GatewayConfig) error {
	if err := validateGateway(cfg); err != nil {
		return err
	}
	gatewayState.Lock()
	defer gatewayState.Unlock()
	if gatewayState.Path == "" {
		return fmt.Errorf("hardware configuration storage is unavailable")
	}
	if err := os.MkdirAll(filepath.Dir(gatewayState.Path), 0700); err != nil {
		return err
	}
	data, _ := json.MarshalIndent(cfg, "", "  ")
	tmp := gatewayState.Path + ".tmp"
	if err := os.WriteFile(tmp, data, 0600); err != nil {
		return err
	}
	if err := os.Rename(tmp, gatewayState.Path); err != nil {
		return err
	}
	gatewayState.Config = cfg
	return nil
}
func gatewayRequest(ctx context.Context, endpoint string, body interface{}) (map[string]interface{}, error) {
	if endpoint == "" {
		return nil, fmt.Errorf("configure this device URL first")
	}
	method := http.MethodGet
	var input io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return nil, err
		}
		input = bytes.NewReader(data)
		method = http.MethodPost
	}
	req, err := http.NewRequestWithContext(ctx, method, endpoint, input)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	response, err := hardwareHTTP.Do(req)
	if err != nil {
		return nil, fmt.Errorf("device connection failed: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return nil, fmt.Errorf("device returned HTTP %d", response.StatusCode)
	}
	var state map[string]interface{}
	if err = json.NewDecoder(io.LimitReader(response.Body, 64*1024)).Decode(&state); err != nil {
		return nil, fmt.Errorf("device did not return a JSON acknowledgement: %w", err)
	}
	if state == nil {
		return nil, fmt.Errorf("device returned an empty acknowledgement")
	}
	return state, nil
}
func SetRelay(ctx context.Context, ch int, power bool) (map[string]interface{}, error) {
	if ch < 1 || ch > 4 {
		return nil, fmt.Errorf("relay channel must be 1–4")
	}
	relayOperations.Lock()
	defer relayOperations.Unlock()
	return setRelayEndpoint(ctx, GetGatewayConfig().Relays[ch-1], power)
}
func setRelayEndpoint(ctx context.Context, endpoint string, power bool) (map[string]interface{}, error) {
	state, err := gatewayRequest(ctx, endpoint, map[string]interface{}{"power": power})
	if err != nil {
		return nil, err
	}
	actual, ok := state["power"].(bool)
	if !ok || actual != power {
		return nil, fmt.Errorf("relay did not confirm requested power state")
	}
	return state, nil
}
func ReadGateway(ctx context.Context, kind string) (map[string]interface{}, error) {
	cfg := GetGatewayConfig()
	endpoint := ""
	switch kind {
	case "sensor":
		endpoint = cfg.SensorURL
	case "nfc":
		endpoint = cfg.NFCURL
	case "scale":
		endpoint = cfg.ScaleURL
	default:
		return nil, fmt.Errorf("unknown hardware kind")
	}
	state, err := gatewayRequest(ctx, endpoint, nil)
	if err != nil {
		return nil, err
	}
	switch kind {
	case "sensor":
		v, ok := state["moisture_pct"].(float64)
		if !ok || v < 0 || v > 100 {
			return nil, fmt.Errorf("sensor response requires moisture_pct from 0 to 100")
		}
	case "nfc":
		uid, ok := state["tag_id"].(string)
		if !ok || strings.TrimSpace(uid) == "" {
			return nil, fmt.Errorf("no NFC tag is present")
		}
	case "scale":
		v, ok := state["weight_kg"].(float64)
		if !ok || v < 0 {
			return nil, fmt.Errorf("scale response requires a non-negative weight_kg")
		}
	}
	return state, nil
}

func TareScale(ctx context.Context) (map[string]interface{}, error) {
	state, err := gatewayRequest(ctx, GetGatewayConfig().ScaleURL, map[string]interface{}{"action": "tare"})
	if err != nil {
		return nil, err
	}
	weight, ok := state["weight_kg"].(float64)
	if !ok || weight != 0 {
		return nil, fmt.Errorf("scale did not confirm a zero reading")
	}
	return state, nil
}
