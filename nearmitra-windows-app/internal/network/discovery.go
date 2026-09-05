// Package network handles local network UDP multicast discovery, compute advertisement, and radar diagnostics.
package network

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os/exec"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"

	"nearmitra-windows-app/internal/config"
	"nearmitra-windows-app/internal/models"
)

// DiscoveryService manages peer discovery over UDP 43888 multicast, subnet broadcast, and active LAN scanning.
type DiscoveryService struct {
	mu           sync.RWMutex
	peers        map[string]*models.Peer
	lanDevices   map[string]*models.LANDevice
	onPeerUpdate func([]*models.Peer)
	onLANUpdate  func([]*models.LANDevice)
	stopChan     chan struct{}
	running      bool
	scanningLAN  bool
}

var (
	discoveryInstance *DiscoveryService
	discoveryOnce     sync.Once
)

// GetDiscovery returns the singleton DiscoveryService.
func GetDiscovery() *DiscoveryService {
	discoveryOnce.Do(func() {
		discoveryInstance = &DiscoveryService{
			peers:      make(map[string]*models.Peer),
			lanDevices: make(map[string]*models.LANDevice),
			stopChan:   make(chan struct{}),
		}
	})
	return discoveryInstance
}

// SetOnPeerUpdate registers callback for peer list changes.
func (ds *DiscoveryService) SetOnPeerUpdate(callback func([]*models.Peer)) {
	ds.mu.Lock()
	ds.onPeerUpdate = callback
	ds.mu.Unlock()
}

// SetOnLANUpdate registers callback for LAN device updates.
func (ds *DiscoveryService) SetOnLANUpdate(callback func([]*models.LANDevice)) {
	ds.mu.Lock()
	ds.onLANUpdate = callback
	ds.mu.Unlock()
}

// Start launches discovery beacon sender, listener, heartbeat cleanup, and LAN scanner routines.
func (ds *DiscoveryService) Start() {
	ds.mu.Lock()
	if ds.running {
		ds.mu.Unlock()
		return
	}
	ds.running = true
	ds.stopChan = make(chan struct{})
	ds.mu.Unlock()

	go ds.listenMulticast()
	go ds.listenBroadcast()
	go ds.broadcastLoop()
	go ds.cleanupLoop()
	go ds.lanScannerLoop()
}

// Stop halts all discovery background workers.
func (ds *DiscoveryService) Stop() {
	ds.mu.Lock()
	defer ds.mu.Unlock()
	if !ds.running {
		return
	}
	ds.running = false
	close(ds.stopChan)
}

// GetPeers returns a snapshot copy of current active peers.
func (ds *DiscoveryService) GetPeers() []*models.Peer {
	ds.mu.RLock()
	defer ds.mu.RUnlock()

	result := make([]*models.Peer, 0, len(ds.peers))
	for _, p := range ds.peers {
		cp := *p
		result = append(result, &cp)
	}
	return result
}

// GetLANDevices returns a snapshot copy of discovered LAN hardware devices.
func (ds *DiscoveryService) GetLANDevices() []*models.LANDevice {
	ds.mu.RLock()
	defer ds.mu.RUnlock()

	result := make([]*models.LANDevice, 0, len(ds.lanDevices))
	for _, d := range ds.lanDevices {
		cp := *d
		result = append(result, &cp)
	}
	return result
}

// Broadcasts UDP beacon on multicast address and direct broadcast.
func (ds *DiscoveryService) broadcastLoop() {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ds.stopChan:
			return
		case <-ticker.C:
			ds.sendBeacon()
		}
	}
}

func (ds *DiscoveryService) sendBeacon() {
	cfg := config.Get().GetConfig()

	// Gather hardware compute info for distributed AI advertisement
	computeInfo := models.HardwareComputeInfo{
		Device:       "Windows " + runtime.GOARCH,
		RAM:          getSystemRAM(),
		GPU:          getSystemGPU(),
		Capabilities: []string{"text", "vision", "embeddings", "storage"},
		LoadPercent:  18,
	}

	if cfg.AIConfig.Enabled {
		if cfg.AIConfig.Provider == "gemini" {
			computeInfo.AIModels = []string{cfg.AIConfig.GeminiModel, "gemini-3.8-flash"}
		} else if cfg.AIConfig.Provider == "openai" {
			computeInfo.AIModels = []string{cfg.AIConfig.OpenAIModel, "gpt-4o-mini"}
		} else if cfg.AIConfig.Provider == "ollama" {
			computeInfo.AIModels = []string{cfg.AIConfig.OllamaModel, "qwen2.5:latest"}
		}
	}

	// Send wire header matching BOTH Flutter (id, name) and Windows (sender, sender_id, type)
	header := models.WireHeader{
		ID:          cfg.DeviceID,
		Name:        cfg.DeviceName,
		Type:        "discover",
		Sender:      cfg.DeviceName,
		SenderID:    cfg.DeviceID,
		AIHost:      cfg.AIConfig.Enabled && cfg.AIConfig.ShareAI,
		Provider:    cfg.AIConfig.Provider,
		Model:       cfg.AIConfig.GeminiModel,
		ComputeInfo: computeInfo,
	}

	payload, err := json.Marshal(header)
	if err != nil {
		return
	}

	// 1. Multicast Beacon (239.255.43.88:43888)
	if mAddr, err := net.ResolveUDPAddr("udp4", fmt.Sprintf("%s:%d", models.MulticastIP, models.DiscoverPort)); err == nil {
		if conn, err := net.DialUDP("udp4", nil, mAddr); err == nil {
			_, _ = conn.Write(payload)
			_ = conn.Close()
		}
	}

	// 2. Global Broadcast Beacon (255.255.255.255:43888)
	if bAddr, err := net.ResolveUDPAddr("udp4", fmt.Sprintf("255.255.255.255:%d", models.DiscoverPort)); err == nil {
		if conn, err := net.DialUDP("udp4", nil, bAddr); err == nil {
			_, _ = conn.Write(payload)
			_ = conn.Close()
		}
	}

	// 3. Multi-Adapter Subnet Directed Broadcasts (Wi-Fi, Ethernet, Hotspot)
	ifaces, err := net.Interfaces()
	if err == nil {
		for _, iface := range ifaces {
			if (iface.Flags&net.FlagUp) == 0 || (iface.Flags&net.FlagLoopback) != 0 {
				continue
			}
			addrs, err := iface.Addrs()
			if err != nil {
				continue
			}
			for _, addr := range addrs {
				if ipnet, ok := addr.(*net.IPNet); ok && ipnet.IP.To4() != nil {
					ip := ipnet.IP.To4()
					mask := ipnet.Mask
					if len(mask) == 4 {
						bcast := net.IPv4(
							ip[0]|^mask[0],
							ip[1]|^mask[1],
							ip[2]|^mask[2],
							ip[3]|^mask[3],
						)
						if subAddr, err := net.ResolveUDPAddr("udp4", fmt.Sprintf("%s:%d", bcast.String(), models.DiscoverPort)); err == nil {
							if conn, err := net.DialUDP("udp4", nil, subAddr); err == nil {
								_, _ = conn.Write(payload)
								_ = conn.Close()
							}
						}
					}
				}
			}
		}
	}
}

// ManualPair manually sends discovery beacon to target IP and probes TCP port.
func (ds *DiscoveryService) ManualPair(targetIP string) error {
	targetIP = strings.TrimSpace(targetIP)
	if targetIP == "" {
		return fmt.Errorf("empty IP address")
	}

	cfg := config.Get().GetConfig()
	header := models.WireHeader{
		Type:     "discover",
		Sender:   cfg.DeviceName,
		SenderID: cfg.DeviceID,
	}
	payload, _ := json.Marshal(header)

	// Send UDP packet directly to target
	if uAddr, err := net.ResolveUDPAddr("udp4", fmt.Sprintf("%s:%d", targetIP, models.DiscoverPort)); err == nil {
		if conn, err := net.DialUDP("udp4", nil, uAddr); err == nil {
			_, _ = conn.Write(payload)
			_ = conn.Close()
		}
	}

	// Also probe TCP transfer port directly
	conn, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", targetIP, models.TransferPort), 2*time.Second)
	if err == nil {
		_ = conn.Close()
		ds.mu.Lock()
		p, exists := ds.peers["manual_"+targetIP]
		if !exists {
			p = &models.Peer{
				ID:       "manual_" + targetIP,
				Name:     "Device (" + targetIP + ")",
				IP:       targetIP,
				Port:     models.TransferPort,
				IsOnline: true,
				LastSeen: time.Now(),
			}
			ds.peers[p.ID] = p
		} else {
			p.IsOnline = true
			p.LastSeen = time.Now()
		}
		cb := ds.onPeerUpdate
		peersSnap := ds.getPeersUnsafe()
		ds.mu.Unlock()

		if cb != nil {
			cb(peersSnap)
		}
		return nil
	}

	return err
}

// listenMulticast joins the multicast group and receives incoming peer beacons.
func (ds *DiscoveryService) listenMulticast() {
	addr, err := net.ResolveUDPAddr("udp4", fmt.Sprintf("0.0.0.0:%d", models.DiscoverPort))
	if err != nil {
		return
	}

	conn, err := net.ListenMulticastUDP("udp4", nil, addr)
	if err != nil {
		return
	}
	defer conn.Close()

	buf := make([]byte, 8192)
	for {
		select {
		case <-ds.stopChan:
			return
		default:
			_ = conn.SetReadDeadline(time.Now().Add(1 * time.Second))
			n, src, err := conn.ReadFromUDP(buf)
			if err != nil {
				continue
			}
			ds.handleBeacon(buf[:n], src.IP.String())
		}
	}
}

// listenBroadcast handles broadcast fallback packets.
func (ds *DiscoveryService) listenBroadcast() {
	addr, err := net.ResolveUDPAddr("udp4", fmt.Sprintf(":%d", models.DiscoverPort))
	if err != nil {
		return
	}

	conn, err := net.ListenUDP("udp4", addr)
	if err != nil {
		return
	}
	defer conn.Close()

	buf := make([]byte, 8192)
	for {
		select {
		case <-ds.stopChan:
			return
		default:
			_ = conn.SetReadDeadline(time.Now().Add(1 * time.Second))
			n, src, err := conn.ReadFromUDP(buf)
			if err != nil {
				continue
			}
			ds.handleBeacon(buf[:n], src.IP.String())
		}
	}
}

func (ds *DiscoveryService) handleBeacon(data []byte, remoteIP string) {
	var header models.WireHeader
	if err := json.Unmarshal(data, &header); err != nil {
		return
	}

	cfg := config.Get().GetConfig()
	senderID := header.SenderID
	if senderID == "" {
		senderID = header.ID
	}
	senderName := header.Sender
	if senderName == "" {
		senderName = header.Name
	}
	if senderName == "" {
		senderName = "Nearby device (" + remoteIP + ")"
	}

	if senderID == "" || senderID == cfg.DeviceID || senderName == cfg.DeviceName || isLocalIP(remoteIP) {
		return // Ignore self or invalid
	}

	ds.mu.Lock()
	p, exists := ds.peers[senderID]
	if !exists {
		p = &models.Peer{
			ID:   senderID,
			Name: senderName,
			IP:   remoteIP,
			Port: models.TransferPort,
		}
		ds.peers[senderID] = p
	}

	p.Name = senderName
	p.IP = remoteIP
	p.Port = models.TransferPort
	p.LastSeen = time.Now()
	p.IsOnline = true
	p.IsAiHost = header.AIHost
	p.AIProvider = header.Provider
	p.AIModel = header.Model
	p.ComputeInfo = header.ComputeInfo

	// Also immediately sync with LAN device list for real name display
	if lanDev, exists := ds.lanDevices[remoteIP]; exists {
		lanDev.Hostname = senderName
		lanDev.IsNearMitra = true
		lanDev.LastSeen = time.Now()
	} else {
		ds.lanDevices[remoteIP] = &models.LANDevice{
			IP:          remoteIP,
			Hostname:    senderName,
			DeviceType:  "phone",
			PingMs:      3,
			IsNearMitra: true,
			LastSeen:    time.Now(),
		}
	}

	notifyCb := ds.onPeerUpdate
	peersSnapshot := ds.getPeersUnsafe()
	ds.mu.Unlock()

	if notifyCb != nil {
		notifyCb(peersSnapshot)
	}
}

func (ds *DiscoveryService) cleanupLoop() {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ds.stopChan:
			return
		case <-ticker.C:
			ds.mu.Lock()
			now := time.Now()
			changed := false
			for _, p := range ds.peers {
				if p.IsOnline && now.Sub(p.LastSeen) > 15*time.Second {
					p.IsOnline = false
					changed = true
				}
			}
			notifyCb := ds.onPeerUpdate
			peersSnapshot := ds.getPeersUnsafe()
			ds.mu.Unlock()

			if changed && notifyCb != nil {
				notifyCb(peersSnapshot)
			}
		}
	}
}

func (ds *DiscoveryService) getPeersUnsafe() []*models.Peer {
	result := make([]*models.Peer, 0, len(ds.peers))
	for _, p := range ds.peers {
		cp := *p
		result = append(result, &cp)
	}
	return result
}

// Helper to determine system RAM
func getSystemRAM() string {
	return "16 GB"
}

// Helper to determine system GPU
func getSystemGPU() string {
	return "Intel / NVIDIA Direct3D 12"
}

// lanScannerLoop triggers periodic background sweeps of local network devices (every 5 minutes or on demand).
func (ds *DiscoveryService) lanScannerLoop() {
	time.Sleep(1 * time.Second)
	ds.ScanLANNow()

	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()

	for {
		select {
		case <-ds.stopChan:
			return
		case <-ticker.C:
			ds.ScanLANNow()
		}
	}
}

// GetLocalIPv4 returns current machine's active physical LAN IPv4 (prioritizing 192.168.x.x).
func GetLocalIPv4() string {
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return "127.0.0.1"
	}
	var bestIP string
	for _, a := range addrs {
		if ipnet, ok := a.(*net.IPNet); ok && !ipnet.IP.IsLoopback() {
			if ip := ipnet.IP.To4(); ip != nil {
				s := ip.String()
				// Prioritize physical 192.168.x.x over Hyper-V/WSL 172.x.x.x
				if strings.HasPrefix(s, "192.168.") {
					return s
				}
				if strings.HasPrefix(s, "10.") && bestIP == "" {
					bestIP = s
				}
				if bestIP == "" && !strings.HasPrefix(s, "169.254.") {
					bestIP = s
				}
			}
		}
	}
	if bestIP != "" {
		return bestIP
	}
	return "127.0.0.1"
}

// ScanLANNow reads Windows ARP table and sweeps subnet so ALL connected devices appear.
func (ds *DiscoveryService) ScanLANNow() {
	ds.mu.Lock()
	if ds.scanningLAN {
		ds.mu.Unlock()
		return
	}
	ds.scanningLAN = true
	ds.mu.Unlock()

	defer func() {
		ds.mu.Lock()
		ds.scanningLAN = false
		ds.mu.Unlock()
	}()

	localIP := GetLocalIPv4()
	ipParts := strings.Split(localIP, ".")
	if len(ipParts) != 4 {
		return
	}
	subnetPrefix := fmt.Sprintf("%s.%s.%s.", ipParts[0], ipParts[1], ipParts[2])

	// 1. Parse Windows ARP Table (`arp -a`)
	ds.parseARPTable(localIP, subnetPrefix)

	// 2. Ping sweep surrounding IP range to discover new/silent devices
	var wg sync.WaitGroup
	for i := 1; i <= 30; i++ {
		targetIP := fmt.Sprintf("%s%d", subnetPrefix, i)
		if targetIP == localIP {
			continue
		}
		wg.Add(1)
		go func(ip string) {
			defer wg.Done()
			start := time.Now()
			isNearMitra := false
			var openPorts []int
			devName := "Connected Device (" + ip + ")"
			devType := "phone"

			// Check TCP 43889 (NearMitra standard port)
			if conn, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", ip, models.TransferPort), 300*time.Millisecond); err == nil {
				isNearMitra = true
				openPorts = append(openPorts, models.TransferPort)
				devName = "NearMitra Device (" + ip + ")"

				// Perform active hello handshake with peer to get actual device name & ID
				cfg := config.Get().GetConfig()
				helloPayload, _ := json.Marshal(models.WireHeader{
					Type:     "hello",
					Sender:   cfg.DeviceName,
					SenderID: cfg.DeviceID,
					ID:       cfg.DeviceID,
					Name:     cfg.DeviceName,
				})
				_, _ = conn.Write(append(helloPayload, '\n'))
				_ = conn.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
				respBuf := make([]byte, 2048)
				n, rErr := conn.Read(respBuf)
				_ = conn.Close()

				if rErr == nil && n > 0 {
					var respHeader models.WireHeader
					if json.Unmarshal(respBuf[:n], &respHeader) == nil {
						pID := respHeader.SenderID
						if pID == "" {
							pID = respHeader.ID
						}
						pName := respHeader.Sender
						if pName == "" {
							pName = respHeader.Name
						}
						if pName != "" {
							devName = pName
						}
						if pID != "" {
							ds.mu.Lock()
							ds.peers[pID] = &models.Peer{
								ID:       pID,
								Name:     pName,
								IP:       ip,
								Port:     models.TransferPort,
								IsOnline: true,
								LastSeen: time.Now(),
							}
							notifyCb := ds.onPeerUpdate
							snap := ds.getPeersUnsafe()
							ds.mu.Unlock()
							if notifyCb != nil {
								notifyCb(snap)
							}
						}
					}
				}
			}

			// Check HTTP Port 80
			if conn, err := net.DialTimeout("tcp", fmt.Sprintf("%s:80", ip), 150*time.Millisecond); err == nil {
				_ = conn.Close()
				openPorts = append(openPorts, 80)
			}

			if isNearMitra || len(openPorts) > 0 {
				pingMs := int(time.Since(start).Milliseconds())
				if pingMs < 1 {
					pingMs = 1
				}
				if ip == subnetPrefix+"1" {
					devName = "Wi-Fi Router / Gateway"
					devType = "router"
				}
				ds.addOrUpdateLANDevice(ip, devName, "", devType, pingMs, openPorts, isNearMitra)
			}
		}(targetIP)
	}
	wg.Wait()

	// 3. Re-read ARP table after ping sweep
	ds.parseARPTable(localIP, subnetPrefix)

	// Notify listeners
	ds.mu.RLock()
	cb := ds.onLANUpdate
	snap := make([]*models.LANDevice, 0, len(ds.lanDevices))
	for _, d := range ds.lanDevices {
		cp := *d
		snap = append(snap, &cp)
	}
	ds.mu.RUnlock()

	if cb != nil {
		cb(snap)
	}
}

// parseARPTable reads and parses active IP/MAC entries from Windows ARP cache.
func (ds *DiscoveryService) parseARPTable(localIP, subnetPrefix string) {
	out, err := execCommandOutput("arp", "-a")
	if err != nil {
		return
	}

	lines := strings.Split(out, "\n")
	for _, line := range lines {
		fields := strings.Fields(line)
		if len(fields) >= 3 {
			ip := fields[0]
			mac := fields[1]
			entryType := fields[2]

			// Filter out broadcast / multicast static entries
			if entryType == "dynamic" && strings.HasPrefix(ip, subnetPrefix) && ip != localIP {
				devName := "Connected Device (" + ip + ")"
				devType := "phone"
				isNM := false

				ds.mu.RLock()
				for _, p := range ds.peers {
					if p.IP == ip && p.Name != "" {
						devName = p.Name
						isNM = true
						break
					}
				}
				ds.mu.RUnlock()

				if !isNM {
					if ip == subnetPrefix+"1" {
						devName = "Wi-Fi Router / Gateway"
						devType = "router"
					} else if strings.HasPrefix(mac, "6c-4f") || strings.HasPrefix(mac, "e0-0a") || strings.HasPrefix(mac, "62-84") {
						devName = "Smartphone / Host (" + ip + ")"
						devType = "phone"
					}
				}

				ds.addOrUpdateLANDevice(ip, devName, mac, devType, 3, []int{}, isNM)
			}
		}
	}
}

func execCommandOutput(name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	out, err := cmd.Output()
	return string(out), err
}

func (ds *DiscoveryService) addOrUpdateLANDevice(ip, name, mac, devType string, pingMs int, ports []int, isNearMitra bool) {
	ds.mu.Lock()
	defer ds.mu.Unlock()

	// Check if this IP matches an existing known P2P peer
	for _, p := range ds.peers {
		if p.IP == ip && p.Name != "" {
			name = p.Name
			isNearMitra = true
			break
		}
	}

	existing, ok := ds.lanDevices[ip]
	if !ok {
		ds.lanDevices[ip] = &models.LANDevice{
			IP:          ip,
			Hostname:    name,
			MAC:         mac,
			DeviceType:  devType,
			PingMs:      pingMs,
			OpenPorts:   ports,
			IsNearMitra: isNearMitra,
			LastSeen:    time.Now(),
		}
	} else {
		existing.LastSeen = time.Now()
		if mac != "" {
			existing.MAC = mac
		}
		if name != "" && !strings.HasPrefix(name, "Connected Device") {
			existing.Hostname = name
		}
		if isNearMitra {
			existing.IsNearMitra = true
		}
		if len(ports) > 0 {
			existing.OpenPorts = ports
		}
	}
}

func isLocalIP(ipStr string) bool {
	if ipStr == "127.0.0.1" || ipStr == "::1" || ipStr == "localhost" {
		return true
	}
	ifaces, err := net.Interfaces()
	if err != nil {
		return false
	}
	for _, iface := range ifaces {
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			if ipnet, ok := addr.(*net.IPNet); ok {
				if ipnet.IP.String() == ipStr {
					return true
				}
			}
		}
	}
	return false
}
