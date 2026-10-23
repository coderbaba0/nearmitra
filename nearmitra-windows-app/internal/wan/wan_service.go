package wan

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"nearmitra-windows-app/internal/config"
)

// WanService manages Internet / WAN remote discovery, privacy modes, pair codes, and trusted peer relationships.
type WanService struct {
	mu                  sync.RWMutex
	presenceMu          sync.Mutex
	presenceCancel      context.CancelFunc
	lastPresenceAt      time.Time
	client              *FirebaseClient
	config              WanConfig
	trustedDevices      map[string]*WanDevice
	publicDevices       map[string]*WanDevice
	pendingRequests     map[string]*WanPairRequest
	activePairCode      *WanPairCode
	isFirebaseConnected bool
	isPresenceOnline    bool
	stopChan            chan struct{}
	running             bool
	onStateChange       func(*WanState)
}

var (
	wanInstance *WanService
	wanOnce     sync.Once
)

// GetWanService returns the singleton WanService instance.
func GetWanService() *WanService {
	wanOnce.Do(func() {
		wanInstance = &WanService{
			client:          NewFirebaseClient(DefaultFirebaseRTDBUrl),
			trustedDevices:  make(map[string]*WanDevice),
			publicDevices:   make(map[string]*WanDevice),
			pendingRequests: make(map[string]*WanPairRequest),
			config: WanConfig{
				InternetModeEnabled: DefaultFirebaseRTDBUrl != "",
				DiscoveryMode:       ModePublicRadar,
				FirebaseRTDBUrl:     DefaultFirebaseRTDBUrl,
			},
			stopChan: make(chan struct{}),
		}
	})
	return wanInstance
}

// Init loads persisted WAN configuration and trusted devices from disk.
func (ws *WanService) Init() {
	ws.loadConfig()
	ws.loadTrustedDevices()

	// An owner-supplied URL is required; local operation does not need Firebase.
	if endpoint := strings.TrimSpace(os.Getenv("NEARMITRA_FIREBASE_RTDB_URL")); endpoint != "" {
		ws.config.FirebaseRTDBUrl = endpoint
	}
	ws.client = NewFirebaseClient(ws.config.FirebaseRTDBUrl)
	if ws.client.baseURL != "" {
		ws.Start()
	}
}

func (ws *WanService) getAppDataDir() string {
	dir := filepath.Join(os.Getenv("LOCALAPPDATA"), "NearMitra")
	_ = os.MkdirAll(dir, 0755)
	return dir
}

func (ws *WanService) loadConfig() {
	ws.mu.Lock()
	defer ws.mu.Unlock()

	configFile := filepath.Join(ws.getAppDataDir(), "wan_config.json")
	data, err := os.ReadFile(configFile)
	if err == nil {
		var cfg WanConfig
		if json.Unmarshal(data, &cfg) == nil {
			if cfg.DiscoveryMode == "" {
				cfg.DiscoveryMode = ModePublicRadar
			}
			if cfg.FirebaseRTDBUrl == "" {
				cfg.FirebaseRTDBUrl = DefaultFirebaseRTDBUrl
			}
			ws.config = cfg
			ws.client = NewFirebaseClient(cfg.FirebaseRTDBUrl)
		}
	}
}

func (ws *WanService) saveConfigLocked() {
	configFile := filepath.Join(ws.getAppDataDir(), "wan_config.json")
	data, err := json.MarshalIndent(ws.config, "", "  ")
	if err == nil {
		_ = os.WriteFile(configFile, data, 0644)
	}
}

func (ws *WanService) loadTrustedDevices() {
	ws.mu.Lock()
	defer ws.mu.Unlock()

	trustedFile := filepath.Join(ws.getAppDataDir(), "wan_trusted.json")
	data, err := os.ReadFile(trustedFile)
	if err == nil {
		var list []*WanDevice
		if json.Unmarshal(data, &list) == nil {
			for _, d := range list {
				d.IsTrusted = true
				d.IsOnline = false
				ws.trustedDevices[d.ID] = d
			}
		}
	}
}

func (ws *WanService) saveTrustedDevicesLocked() {
	trustedFile := filepath.Join(ws.getAppDataDir(), "wan_trusted.json")
	list := make([]*WanDevice, 0, len(ws.trustedDevices))
	for _, d := range ws.trustedDevices {
		list = append(list, d)
	}
	data, err := json.MarshalIndent(list, "", "  ")
	if err == nil {
		_ = os.WriteFile(trustedFile, data, 0644)
	}
}

// Start initiates background WAN workers (presence heartbeat, pair request polling, public discovery sweep).
func (ws *WanService) Start() {
	ws.mu.Lock()
	if ws.running {
		ws.mu.Unlock()
		return
	}
	endpoint, err := url.Parse(ws.client.baseURL)
	if err != nil || endpoint.Host == "" || (endpoint.Scheme != "https" &&
		!(endpoint.Scheme == "http" && (endpoint.Hostname() == "localhost" || endpoint.Hostname() == "127.0.0.1"))) {
		ws.config.InternetModeEnabled = false
		ws.mu.Unlock()
		log.Println("[WanService] WAN disabled: configure your own Firebase RTDB URL (see docs/FIREBASE_SETUP.md)")
		return
	}
	ws.running = true
	ws.stopChan = make(chan struct{})
	ws.config.InternetModeEnabled = true
	ws.saveConfigLocked()
	stop := ws.stopChan
	ws.mu.Unlock()

	log.Println("[WanService] Starting Internet / WAN Mesh & Firebase Presence...")
	go ws.presenceLoop(stop)
	go ws.incomingRequestsLoop(stop)
	go ws.publicDiscoveryLoop(stop)
	go ws.syncTrustedDevicesLoop(stop)
}

// Stop halts all WAN background workers and cleans up presence.
func (ws *WanService) Stop() {
	ws.mu.Lock()
	if !ws.running {
		ws.mu.Unlock()
		return
	}
	ws.running = false
	ws.config.InternetModeEnabled = false
	ws.saveConfigLocked()
	close(ws.stopChan)
	if ws.presenceCancel != nil {
		ws.presenceCancel()
	}
	ws.isFirebaseConnected = false
	ws.isPresenceOnline = false
	ws.mu.Unlock()

	log.Println("[WanService] Stopping WAN Mesh and cleaning up Firebase presence...")
	ws.cleanupPresence()
}

// SetInternetMode toggles the master WAN internet mesh.
func (ws *WanService) SetInternetMode(enable bool) {
	if enable {
		ws.Start()
	} else {
		ws.Stop()
	}
}

// SetDiscoveryMode updates the privacy & visibility mode (publicRadar, privateGhost, pinOnly).
func (ws *WanService) SetDiscoveryMode(mode WanDiscoveryMode) {
	ws.mu.Lock()
	ws.config.DiscoveryMode = mode
	ws.saveConfigLocked()
	running := ws.running
	ws.mu.Unlock()

	if running {
		go ws.syncPresenceImmediate()
	}
}

// SetOnStateChange registers a callback for WAN state notifications.
func (ws *WanService) SetOnStateChange(cb func(*WanState)) {
	ws.mu.Lock()
	ws.onStateChange = cb
	ws.mu.Unlock()
}

// GetState returns the current complete runtime snapshot.
func (ws *WanService) GetState() *WanState {
	ws.mu.RLock()
	defer ws.mu.RUnlock()

	cfg := config.Get().GetConfig()

	publicList := make([]*WanDevice, 0, len(ws.publicDevices))
	for _, d := range ws.publicDevices {
		if d.ID == cfg.DeviceID || ws.trustedDevices[d.ID] != nil {
			continue
		}
		cp := *d
		cp.IsOnline = presenceAlive(cp.IsOnline, cp.Platform, cp.LastSeen, cp.PresenceLeaseMs, time.Now())
		if !cp.IsOnline {
			continue
		}
		publicList = append(publicList, &cp)
	}

	trustedList := make([]*WanDevice, 0, len(ws.trustedDevices))
	for _, d := range ws.trustedDevices {
		cp := *d
		cp.IsOnline = presenceAlive(cp.IsOnline, cp.Platform, cp.LastSeen, cp.PresenceLeaseMs, time.Now())
		trustedList = append(trustedList, &cp)
	}

	reqList := make([]*WanPairRequest, 0, len(ws.pendingRequests))
	for _, r := range ws.pendingRequests {
		cp := *r
		reqList = append(reqList, &cp)
	}

	var activeCode *WanPairCode
	if ws.activePairCode != nil {
		if time.Now().UnixMilli() < ws.activePairCode.ExpiresAt && !ws.activePairCode.Used {
			cp := *ws.activePairCode
			activeCode = &cp
		}
	}

	return &WanState{
		InternetModeEnabled: ws.config.InternetModeEnabled,
		DiscoveryMode:       ws.config.DiscoveryMode,
		IsFirebaseConnected: ws.isFirebaseConnected && time.Since(ws.lastPresenceAt) < desktopPresenceLease,
		IsPresenceOnline:    ws.isPresenceOnline && time.Since(ws.lastPresenceAt) < desktopPresenceLease,
		MyDeviceID:          cfg.DeviceID,
		MyDeviceName:        cfg.DeviceName,
		MyAvatarEmoji:       cfg.AvatarEmoji,
		PublicDevices:       publicList,
		TrustedDevices:      trustedList,
		ActivePairCode:      activeCode,
		PendingRequests:     reqList,
	}
}

// GeneratePairCode generates a random 6-digit PIN pairing code with 5-minute validity.
func (ws *WanService) GeneratePairCode() (*WanPairCode, error) {
	ws.mu.Lock()
	if !ws.running {
		ws.mu.Unlock()
		ws.Start()
		ws.mu.Lock()
	}

	cfg := config.Get().GetConfig()
	nBig, err := rand.Int(rand.Reader, big.NewInt(900000))
	if err != nil {
		ws.mu.Unlock()
		return nil, err
	}
	code := fmt.Sprintf("%06d", nBig.Int64()+100000)
	now := time.Now()
	expiresAt := now.Add(5 * time.Minute).UnixMilli()

	pairCode := &WanPairCode{
		Code:          code,
		OwnerDeviceID: cfg.DeviceID,
		OwnerName:     cfg.DeviceName,
		Platform:      "windows",
		CreatedAt:     now.UnixMilli(),
		ExpiresAt:     expiresAt,
		Used:          false,
	}
	ws.activePairCode = pairCode
	ws.mu.Unlock()

	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()

	payload := map[string]interface{}{
		"code":            code,
		"ownerDeviceId":   cfg.DeviceID,
		"ownerDeviceName": cfg.DeviceName,
		"platform":        "windows",
		"createdAt":       now.UnixMilli(),
		"expiresAt":       expiresAt,
		"used":            false,
	}

	if err := ws.client.Put(ctx, "pairCodes/"+code, payload); err != nil {
		log.Printf("[WanService] Error saving pairCode to Firebase: %v", err)
		return nil, err
	}

	log.Printf("[WanService] Generated 6-digit pair code: %s (expires in 5m)", code)
	return pairCode, nil
}

// CancelPairCode cancels and removes the active PIN pairing code.
func (ws *WanService) CancelPairCode() {
	ws.mu.Lock()
	code := ""
	if ws.activePairCode != nil {
		code = ws.activePairCode.Code
		ws.activePairCode = nil
	}
	ws.mu.Unlock()

	if code != "" {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = ws.client.Delete(ctx, "pairCodes/"+code)
	}
}

// ClaimPairCode enters a 6-digit PIN code to validate, send a pair request, and await peer acceptance.
func (ws *WanService) ClaimPairCode(code string) (*WanDevice, error) {
	code = filepath.Clean(code)
	if len(code) != 6 {
		return nil, fmt.Errorf("please enter a valid 6-digit pairing code")
	}

	ws.mu.Lock()
	if !ws.running {
		ws.mu.Unlock()
		ws.Start()
		ws.mu.Lock()
	}
	ws.mu.Unlock()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	var record map[string]interface{}
	if err := ws.client.Get(ctx, "pairCodes/"+code, &record); err != nil || record == nil {
		return nil, fmt.Errorf("invalid or expired 6-digit pairing code")
	}

	used, _ := record["used"].(bool)
	if used {
		return nil, fmt.Errorf("this pairing code has already been used")
	}

	expiresAtNum, _ := record["expiresAt"].(float64)
	if time.Now().UnixMilli() > int64(expiresAtNum) {
		return nil, fmt.Errorf("pairing code has expired. Please ask peer to generate a new code")
	}

	targetDeviceID, _ := record["ownerDeviceId"].(string)
	targetName, _ := record["ownerDeviceName"].(string)
	targetPlatform, _ := record["platform"].(string)

	cfg := config.Get().GetConfig()
	if targetDeviceID == cfg.DeviceID {
		return nil, fmt.Errorf("cannot pair the same device with itself")
	}

	// Generate pairing request: pairRequests/{targetDeviceID}/{requestID}
	requestID := fmt.Sprintf("req_%d", time.Now().UnixNano())
	reqPayload := map[string]interface{}{
		"requestId":       requestID,
		"fromDeviceId":    cfg.DeviceID,
		"fromDeviceName":  cfg.DeviceName,
		"fromPlatform":    "windows",
		"fromAvatarEmoji": cfg.AvatarEmoji,
		"toDeviceId":      targetDeviceID,
		"code":            code,
		"createdAt":       time.Now().UnixMilli(),
		"status":          "pending",
	}

	if err := ws.client.Put(ctx, fmt.Sprintf("pairRequests/%s/%s", targetDeviceID, requestID), reqPayload); err != nil {
		return nil, fmt.Errorf("failed to send pairing request: %v", err)
	}

	log.Printf("[WanService] Sent pairing request to %s (%s). Awaiting response...", targetName, targetDeviceID)

	// Poll request status for acceptance (timeout 45s)
	startTime := time.Now()
	for time.Since(startTime) < 45*time.Second {
		time.Sleep(1500 * time.Millisecond)

		var statusCheck map[string]interface{}
		pollCtx, pCancel := context.WithTimeout(context.Background(), 5*time.Second)
		_ = ws.client.Get(pollCtx, fmt.Sprintf("pairRequests/%s/%s", targetDeviceID, requestID), &statusCheck)
		pCancel()

		if statusCheck != nil {
			st, _ := statusCheck["status"].(string)
			if st == "accepted" {
				// 1. Create mutual trusted records in Firebase RTDB
				tCtx, tCancel := context.WithTimeout(context.Background(), 6*time.Second)
				_ = ws.client.Put(tCtx, fmt.Sprintf("trustedDevices/%s/%s", cfg.DeviceID, targetDeviceID), map[string]interface{}{
					"deviceId":   targetDeviceID,
					"deviceName": targetName,
					"platform":   targetPlatform,
					"pairedAt":   time.Now().UnixMilli(),
				})
				_ = ws.client.Put(tCtx, fmt.Sprintf("trustedDevices/%s/%s", targetDeviceID, cfg.DeviceID), map[string]interface{}{
					"deviceId":    cfg.DeviceID,
					"deviceName":  cfg.DeviceName,
					"platform":    "windows",
					"avatarEmoji": cfg.AvatarEmoji,
					"pairedAt":    time.Now().UnixMilli(),
				})
				tCancel()

				// 2. Mark code used and cleanup request
				cleanCtx, cCancel := context.WithTimeout(context.Background(), 5*time.Second)
				_ = ws.client.Delete(cleanCtx, fmt.Sprintf("pairRequests/%s/%s", targetDeviceID, requestID))
				_ = ws.client.Delete(cleanCtx, "pairCodes/"+code)
				cCancel()

				device := &WanDevice{
					ID:        targetDeviceID,
					Name:      targetName,
					Platform:  targetPlatform,
					IsOnline:  true,
					IsTrusted: true,
					LastSeen:  time.Now(),
				}

				ws.AddTrustedDevice(device)
				return device, nil
			} else if st == "rejected" {
				cleanCtx, cCancel := context.WithTimeout(context.Background(), 5*time.Second)
				_ = ws.client.Delete(cleanCtx, fmt.Sprintf("pairRequests/%s/%s", targetDeviceID, requestID))
				cCancel()
				return nil, fmt.Errorf("pairing request was declined by remote device")
			}
		}
	}

	return nil, fmt.Errorf("pairing request timed out. Please try again")
}

// SendDirectPairRequest sends a 1-tap connection request to a discovered peer on WAN Radar and awaits acceptance.
func (ws *WanService) SendDirectPairRequest(targetDeviceID, targetName, targetPlatform, targetAvatar string) (*WanDevice, error) {
	cfg := config.Get().GetConfig()
	if targetDeviceID == cfg.DeviceID {
		return nil, fmt.Errorf("cannot connect to your own device")
	}

	ws.mu.Lock()
	if !ws.running {
		ws.mu.Unlock()
		ws.Start()
		ws.mu.Lock()
	}
	ws.mu.Unlock()

	requestID := fmt.Sprintf("direct_%d", time.Now().UnixNano())
	reqPayload := map[string]interface{}{
		"requestId":       requestID,
		"fromDeviceId":    cfg.DeviceID,
		"fromDeviceName":  cfg.DeviceName,
		"fromPlatform":    "windows",
		"fromAvatarEmoji": cfg.AvatarEmoji,
		"toDeviceId":      targetDeviceID,
		"code":            "",
		"isDirectRadar":   true,
		"createdAt":       time.Now().UnixMilli(),
		"status":          "pending",
	}

	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	if err := ws.client.Put(ctx, fmt.Sprintf("pairRequests/%s/%s", targetDeviceID, requestID), reqPayload); err != nil {
		cancel()
		return nil, fmt.Errorf("failed to send pairing request: %v", err)
	}
	cancel()

	log.Printf("[WanService] Sent direct 1-tap pair request to %s (%s). Awaiting acceptance...", targetName, targetDeviceID)

	// Poll request status for acceptance (timeout 45s)
	startTime := time.Now()
	for time.Since(startTime) < 45*time.Second {
		time.Sleep(1200 * time.Millisecond)

		// 1. Check pairRequests/{targetDeviceID}/{requestID} status
		var statusCheck map[string]interface{}
		pollCtx, pCancel := context.WithTimeout(context.Background(), 5*time.Second)
		_ = ws.client.Get(pollCtx, fmt.Sprintf("pairRequests/%s/%s", targetDeviceID, requestID), &statusCheck)
		pCancel()

		var isAccepted bool
		var isRejected bool

		if statusCheck != nil {
			st, _ := statusCheck["status"].(string)
			if st == "accepted" {
				isAccepted = true
			} else if st == "rejected" {
				isRejected = true
			}
		}

		// 2. Also check if trustedDevices/{myId}/{targetId} was created by peer
		if !isAccepted && !isRejected {
			var trustedCheck map[string]interface{}
			tCheckCtx, tcCancel := context.WithTimeout(context.Background(), 4*time.Second)
			_ = ws.client.Get(tCheckCtx, fmt.Sprintf("trustedDevices/%s/%s", cfg.DeviceID, targetDeviceID), &trustedCheck)
			tcCancel()
			if trustedCheck != nil && len(trustedCheck) > 0 {
				isAccepted = true
			}
		}

		if isAccepted {
			// Write mutual trusted records in Firebase
			tCtx, tCancel := context.WithTimeout(context.Background(), 6*time.Second)
			_ = ws.client.Put(tCtx, fmt.Sprintf("trustedDevices/%s/%s", cfg.DeviceID, targetDeviceID), map[string]interface{}{
				"deviceId":    targetDeviceID,
				"deviceName":  targetName,
				"platform":    targetPlatform,
				"avatarEmoji": targetAvatar,
				"pairedAt":    time.Now().UnixMilli(),
			})
			_ = ws.client.Put(tCtx, fmt.Sprintf("trustedDevices/%s/%s", targetDeviceID, cfg.DeviceID), map[string]interface{}{
				"deviceId":    cfg.DeviceID,
				"deviceName":  cfg.DeviceName,
				"platform":    "windows",
				"avatarEmoji": cfg.AvatarEmoji,
				"pairedAt":    time.Now().UnixMilli(),
			})
			tCancel()

			// Cleanup request
			cleanCtx, cCancel := context.WithTimeout(context.Background(), 5*time.Second)
			_ = ws.client.Delete(cleanCtx, fmt.Sprintf("pairRequests/%s/%s", targetDeviceID, requestID))
			cCancel()

			device := &WanDevice{
				ID:          targetDeviceID,
				Name:        targetName,
				Platform:    targetPlatform,
				AvatarEmoji: targetAvatar,
				IsOnline:    true,
				IsTrusted:   true,
				LastSeen:    time.Now(),
			}

			ws.AddTrustedDevice(device)
			log.Printf("[WanService] Direct pairing successful with %s! Peer added to trusted peers.", targetName)
			return device, nil
		}

		if isRejected {
			cleanCtx, cCancel := context.WithTimeout(context.Background(), 5*time.Second)
			_ = ws.client.Delete(cleanCtx, fmt.Sprintf("pairRequests/%s/%s", targetDeviceID, requestID))
			cCancel()
			return nil, fmt.Errorf("connection request was declined by %s", targetName)
		}
	}

	// Timeout cleanup
	cleanCtx, cCancel := context.WithTimeout(context.Background(), 5*time.Second)
	_ = ws.client.Delete(cleanCtx, fmt.Sprintf("pairRequests/%s/%s", targetDeviceID, requestID))
	cCancel()

	return nil, fmt.Errorf("connection request timed out. Please try again")
}

// RespondPairRequest accepts or declines an incoming connection request.
func (ws *WanService) RespondPairRequest(requestID, fromDeviceID, fromDeviceName, fromPlatform, fromAvatar string, accept bool) error {
	cfg := config.Get().GetConfig()
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()

	status := "rejected"
	if accept {
		status = "accepted"
	}

	// 1. Update status on request node so sender is notified
	_ = ws.client.Patch(ctx, fmt.Sprintf("pairRequests/%s/%s", cfg.DeviceID, requestID), map[string]interface{}{
		"status": status,
	})

	ws.mu.Lock()
	delete(ws.pendingRequests, requestID)
	ws.mu.Unlock()

	if accept {
		// 2. Create mutual trusted records in Firebase RTDB
		tCtx, tCancel := context.WithTimeout(context.Background(), 6*time.Second)
		_ = ws.client.Put(tCtx, fmt.Sprintf("trustedDevices/%s/%s", cfg.DeviceID, fromDeviceID), map[string]interface{}{
			"deviceId":    fromDeviceID,
			"deviceName":  fromDeviceName,
			"platform":    fromPlatform,
			"avatarEmoji": fromAvatar,
			"pairedAt":    time.Now().UnixMilli(),
		})
		_ = ws.client.Put(tCtx, fmt.Sprintf("trustedDevices/%s/%s", fromDeviceID, cfg.DeviceID), map[string]interface{}{
			"deviceId":    cfg.DeviceID,
			"deviceName":  cfg.DeviceName,
			"platform":    "windows",
			"avatarEmoji": cfg.AvatarEmoji,
			"pairedAt":    time.Now().UnixMilli(),
		})
		tCancel()

		// 3. Add to local trusted devices
		device := &WanDevice{
			ID:          fromDeviceID,
			Name:        fromDeviceName,
			Platform:    fromPlatform,
			AvatarEmoji: fromAvatar,
			IsOnline:    true,
			IsTrusted:   true,
			LastSeen:    time.Now(),
		}
		ws.AddTrustedDevice(device)
	}

	return nil
}

// AddTrustedDevice adds a device to the trusted devices map and saves to disk.
func (ws *WanService) AddTrustedDevice(d *WanDevice) {
	ws.mu.Lock()
	defer ws.mu.Unlock()

	d.IsTrusted = true
	ws.trustedDevices[d.ID] = d
	delete(ws.publicDevices, d.ID)
	ws.saveTrustedDevicesLocked()
}

// RemoveTrustedDevice removes a device from the trusted list and cleans up Firebase mutual trust.
func (ws *WanService) RemoveTrustedDevice(id string) {
	ws.mu.Lock()
	delete(ws.trustedDevices, id)
	ws.saveTrustedDevicesLocked()
	ws.mu.Unlock()

	cfg := config.Get().GetConfig()
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Second)
	defer cancel()

	_ = ws.client.Delete(ctx, fmt.Sprintf("trustedDevices/%s/%s", cfg.DeviceID, id))
	_ = ws.client.Delete(ctx, fmt.Sprintf("trustedDevices/%s/%s", id, cfg.DeviceID))
}

// presenceLoop periodically refreshes device heartbeat in presence/{deviceId} and public_presence/{deviceId}.
func (ws *WanService) presenceLoop(stop <-chan struct{}) {
	ws.syncPresenceImmediate()

	ticker := time.NewTicker(presenceHeartbeatInterval)
	defer ticker.Stop()

	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			ws.syncPresenceImmediate()
		}
	}
}

func (ws *WanService) syncPresenceImmediate() {
	// Serialize writes with offline cleanup, so a late heartbeat cannot
	// resurrect the app after WAN is disabled or the process exits.
	ws.presenceMu.Lock()
	defer ws.presenceMu.Unlock()
	ws.mu.Lock()
	if !ws.running || !ws.config.InternetModeEnabled {
		ws.mu.Unlock()
		return
	}
	mode, client := ws.config.DiscoveryMode, ws.client
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Second)
	ws.presenceCancel = cancel
	ws.mu.Unlock()
	defer func() {
		cancel()
		ws.mu.Lock()
		ws.presenceCancel = nil
		ws.mu.Unlock()
	}()

	cfg := config.Get().GetConfig()
	payload := map[string]interface{}{
		"deviceId": cfg.DeviceID, "deviceName": cfg.DeviceName,
		"avatarEmoji": cfg.AvatarEmoji, "platform": "windows", "online": true,
		"lastSeen":        map[string]string{".sv": "timestamp"},
		"presenceLeaseMs": desktopPresenceLease.Milliseconds(),
	}
	err := client.Put(ctx, "presence/"+cfg.DeviceID, payload)
	ws.mu.Lock()
	active := ws.running && ws.config.InternetModeEnabled
	ws.isFirebaseConnected = active && err == nil
	ws.isPresenceOnline = active && err == nil
	if active && err == nil {
		ws.lastPresenceAt = time.Now()
	}
	ws.mu.Unlock()
	if !active {
		return
	}
	if mode == ModePublicRadar && err == nil {
		if err := client.Put(ctx, "public_presence/"+cfg.DeviceID, payload); err != nil {
			log.Printf("[WanService] Public presence refresh failed: %v", err)
		}
	} else {
		_ = client.Delete(ctx, "public_presence/"+cfg.DeviceID)
	}
}

func (ws *WanService) cleanupPresence() {
	ws.presenceMu.Lock()
	defer ws.presenceMu.Unlock()
	ws.mu.RLock()
	running, client := ws.running, ws.client
	ws.mu.RUnlock()
	if running {
		return
	} // A new WAN session already owns presence.
	cfg := config.Get().GetConfig()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = client.Patch(ctx, "presence/"+cfg.DeviceID, map[string]interface{}{
		"online": false, "lastSeen": map[string]string{".sv": "timestamp"},
	})
	_ = client.Delete(ctx, "public_presence/"+cfg.DeviceID)
}

// incomingRequestsLoop polls for incoming pairing requests at pairRequests/{myDeviceID}.
func (ws *WanService) incomingRequestsLoop(stop <-chan struct{}) {
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			ws.pollIncomingRequests()
		}
	}
}

func (ws *WanService) pollIncomingRequests() {
	cfg := config.Get().GetConfig()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	var reqs map[string]map[string]interface{}
	if err := ws.client.Get(ctx, "pairRequests/"+cfg.DeviceID, &reqs); err != nil || reqs == nil {
		return
	}

	ws.mu.Lock()
	defer ws.mu.Unlock()

	for reqID, data := range reqs {
		st, _ := data["status"].(string)
		if st == "pending" {
			fromID, _ := data["fromDeviceId"].(string)
			fromName, _ := data["fromDeviceName"].(string)
			fromPlatform, _ := data["fromPlatform"].(string)
			fromAvatar, _ := data["fromAvatarEmoji"].(string)
			code, _ := data["code"].(string)
			isDirect, _ := data["isDirectRadar"].(bool)

			ws.pendingRequests[reqID] = &WanPairRequest{
				RequestID:       reqID,
				FromDeviceID:    fromID,
				FromDeviceName:  fromName,
				FromPlatform:    fromPlatform,
				FromAvatarEmoji: fromAvatar,
				ToDeviceID:      cfg.DeviceID,
				Code:            code,
				Status:          "pending",
				IsDirectRadar:   isDirect,
				CreatedAt:       time.Now(),
			}
		}
	}
}

// publicDiscoveryLoop sweeps public_presence/ to discover other online peers on WAN Radar.
func (ws *WanService) publicDiscoveryLoop(stop <-chan struct{}) {
	ticker := time.NewTicker(6 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			ws.sweepPublicPresence()
		}
	}
}

func (ws *WanService) sweepPublicPresence() {
	ws.mu.RLock()
	mode := ws.config.DiscoveryMode
	ws.mu.RUnlock()

	if mode != ModePublicRadar {
		return
	}

	cfg := config.Get().GetConfig()
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Second)
	defer cancel()

	var presenceMap map[string]map[string]interface{}
	if err := ws.client.Get(ctx, "public_presence", &presenceMap); err != nil {
		return
	}

	now := time.Now()
	ws.mu.Lock()
	defer ws.mu.Unlock()

	ws.publicDevices = make(map[string]*WanDevice)
	for devID, data := range presenceMap {
		if devID == cfg.DeviceID {
			continue
		}
		name, _ := data["deviceName"].(string)
		if name == "" {
			name = "Remote Peer (" + devID + ")"
		}
		platform, _ := data["platform"].(string)
		avatar, _ := data["avatarEmoji"].(string)
		online, _ := data["online"].(bool)
		lastSeenNum := presenceNumber(data["lastSeen"])
		var lastSeen time.Time
		if lastSeenNum > 0 {
			lastSeen = time.UnixMilli(lastSeenNum)
		}
		lease := presenceNumber(data["presenceLeaseMs"])
		online = presenceAlive(online, platform, lastSeen, lease, now)
		if !online {
			continue
		}

		ws.publicDevices[devID] = &WanDevice{
			ID:              devID,
			Name:            name,
			Platform:        platform,
			AvatarEmoji:     avatar,
			IsOnline:        online,
			LastSeen:        lastSeen,
			PresenceLeaseMs: lease,
			IsTrusted:       ws.trustedDevices[devID] != nil,
		}
	}
}

// syncTrustedDevicesLoop continuously synchronizes paired trusted peers with Firebase RTDB.
func (ws *WanService) syncTrustedDevicesLoop(stop <-chan struct{}) {
	ws.syncTrustedDevices()

	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			ws.syncTrustedDevices()
		}
	}
}

func (ws *WanService) syncTrustedDevices() {
	cfg := config.Get().GetConfig()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	var trustedMap map[string]map[string]interface{}
	_ = ws.client.Get(ctx, "trustedDevices/"+cfg.DeviceID, &trustedMap)

	// Fetch presence map to query online/offline status in realtime
	var presenceMap map[string]map[string]interface{}
	_ = ws.client.Get(ctx, "presence", &presenceMap)

	// Also fetch public_presence map as supplementary
	var publicPresenceMap map[string]map[string]interface{}
	_ = ws.client.Get(ctx, "public_presence", &publicPresenceMap)

	now := time.Now()

	ws.mu.Lock()
	changed := false

	// Combine peers from Firebase and local trusted storage
	allPeers := make(map[string]map[string]interface{})
	if trustedMap != nil {
		for k, v := range trustedMap {
			allPeers[k] = v
		}
	}
	for id, dev := range ws.trustedDevices {
		if _, ok := allPeers[id]; !ok {
			allPeers[id] = map[string]interface{}{
				"deviceName":  dev.Name,
				"platform":    dev.Platform,
				"avatarEmoji": dev.AvatarEmoji,
			}
		}
	}

	for peerID, data := range allPeers {
		if peerID == cfg.DeviceID {
			continue
		}
		name, _ := data["deviceName"].(string)
		if name == "" {
			name, _ = data["name"].(string)
		}
		if name == "" {
			name = "Trusted Peer (" + peerID + ")"
		}
		platform, _ := data["platform"].(string)
		avatar, _ := data["avatarEmoji"].(string)

		isOnline := false
		var lastSeen time.Time
		var lease int64

		// Try presence node first, then fallback to public_presence node
		var pData map[string]interface{}
		if presenceMap != nil {
			pData = presenceMap[peerID]
		}
		if pData == nil && publicPresenceMap != nil {
			pData = publicPresenceMap[peerID]
		}
		if pData == nil {
			var singleP map[string]interface{}
			if err := ws.client.Get(ctx, "presence/"+peerID, &singleP); err == nil && singleP != nil {
				pData = singleP
			}
		}

		if pData != nil {
			onlineVal, _ := pData["online"].(bool)
			lastSeenNum, _ := pData["lastSeen"].(float64)
			if lastSeenNum > 0 {
				lastSeen = time.UnixMilli(int64(lastSeenNum))
			}
			lease = presenceNumber(pData["presenceLeaseMs"])
			isOnline = onlineVal
			if pName, _ := pData["deviceName"].(string); pName != "" {
				name = pName
			}
			if pPlatform, _ := pData["platform"].(string); pPlatform != "" {
				platform = pPlatform
			}
			if pAvatar, _ := pData["avatarEmoji"].(string); pAvatar != "" {
				avatar = pAvatar
			}
		}
		isOnline = presenceAlive(isOnline, platform, lastSeen, lease, now)

		existing, exists := ws.trustedDevices[peerID]
		if !exists {
			ws.trustedDevices[peerID] = &WanDevice{
				ID:              peerID,
				Name:            name,
				Platform:        platform,
				AvatarEmoji:     avatar,
				IsOnline:        isOnline,
				IsTrusted:       true,
				LastSeen:        lastSeen,
				PresenceLeaseMs: lease,
			}
			changed = true
		} else {
			if existing.IsOnline != isOnline {
				existing.IsOnline = isOnline
				changed = true
			}
			if avatar != "" && existing.AvatarEmoji != avatar {
				existing.AvatarEmoji = avatar
				changed = true
			}
			if name != "" && existing.Name != name {
				existing.Name = name
				changed = true
			}
			if platform != "" && existing.Platform != platform {
				existing.Platform = platform
				changed = true
			}
			existing.LastSeen = lastSeen
			existing.PresenceLeaseMs = lease
		}
		// Ensure peer is excluded from public radar list
		delete(ws.publicDevices, peerID)
	}

	if changed {
		ws.saveTrustedDevicesLocked()
	}
	ws.mu.Unlock()
}

// CreateSignalingSession creates an offer session node in Firebase RTDB: sessions/{sessionId}
func (ws *WanService) CreateSignalingSession(sessionID, receiverID string, offer map[string]interface{}) (string, error) {
	if sessionID == "" {
		sessionID = fmt.Sprintf("session_%d", time.Now().UnixNano())
	}
	cfg := config.Get().GetConfig()
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()

	payload := map[string]interface{}{
		"sessionId":      sessionID,
		"callerId":       cfg.DeviceID,
		"callerName":     cfg.DeviceName,
		"callerPlatform": "windows",
		"receiverId":     receiverID,
		"status":         "calling",
		"offer":          offer,
		"createdAt":      time.Now().UnixMilli(),
	}

	err := ws.client.Put(ctx, "sessions/"+sessionID, payload)
	if err != nil {
		return "", err
	}
	return sessionID, nil
}

// AcceptSignalingSession writes the answer SDP to Firebase RTDB: sessions/{sessionId}
func (ws *WanService) AcceptSignalingSession(sessionID string, answer map[string]interface{}) error {
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()

	return ws.client.Patch(ctx, "sessions/"+sessionID, map[string]interface{}{
		"status": "accepted",
		"answer": answer,
	})
}

// AddIceCandidate adds an ICE candidate under sessions/{sessionId}/candidates/{role}
func (ws *WanService) AddIceCandidate(sessionID string, role string, candidate map[string]interface{}) error {
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Second)
	defer cancel()

	candID := fmt.Sprintf("c_%d", time.Now().UnixNano())
	return ws.client.Put(ctx, fmt.Sprintf("sessions/%s/candidates/%s/%s", sessionID, role, candID), candidate)
}

// GetSession reads the signaling session node from Firebase RTDB
func (ws *WanService) GetSession(sessionID string) (map[string]interface{}, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Second)
	defer cancel()

	var sessionData map[string]interface{}
	err := ws.client.Get(ctx, "sessions/"+sessionID, &sessionData)
	return sessionData, err
}

// GetIncomingSessions finds active incoming sessions where receiverId == myDeviceID
func (ws *WanService) GetIncomingSessions() ([]map[string]interface{}, error) {
	cfg := config.Get().GetConfig()
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Second)
	defer cancel()

	var sessionsMap map[string]map[string]interface{}
	err := ws.client.Get(ctx, "sessions", &sessionsMap)
	if err != nil || sessionsMap == nil {
		return []map[string]interface{}{}, nil
	}

	now := time.Now().UnixMilli()
	var incoming []map[string]interface{}
	for sID, data := range sessionsMap {
		recID, _ := data["receiverId"].(string)
		status, _ := data["status"].(string)
		createdAt, _ := data["createdAt"].(float64)

		// Must be addressed to us, status calling, and created within last 90 seconds
		if recID == cfg.DeviceID && status == "calling" && (now-int64(createdAt)) < 90000 {
			data["sessionId"] = sID
			incoming = append(incoming, data)
		}
	}
	return incoming, nil
}

// DeleteSession cleans up the signaling session node
func (ws *WanService) DeleteSession(sessionID string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Second)
	defer cancel()

	return ws.client.Delete(ctx, "sessions/"+sessionID)
}
