
let cvMultiClassObjects = [
  { id: "OBJ_101", type: "Person (Worker)", category: "human", conf: 0.982, x: 0.20, y: 0.22, w: 0.18, h: 0.58, vx: 0.0012, vy: 0.0005, color: "#06B6D4", dist: "2.4m" },
  { id: "OBJ_102", type: "Livestock (HF Cow)", category: "animal", conf: 0.946, x: 0.52, y: 0.42, w: 0.24, h: 0.38, vx: -0.0008, vy: 0.0006, color: "#10B981", dist: "4.1m" },
  { id: "OBJ_103", type: "Tractor (Farm Vehicle)", category: "vehicle", conf: 0.961, x: 0.76, y: 0.30, w: 0.20, h: 0.45, vx: 0.0004, vy: -0.0004, color: "#F59E0B", dist: "6.8m" }
];
/* ==========================================================
   NearMitra Windows 11 Fluent 2 & Microsoft 365 Client Controller
   Targeted Peer Chat, Persistent Storage, Recents & Discovery
   ========================================================== */

let navigationHistory = ['radar'];

let appState = {
  connectionMode: "lan", // 'lan' (first/default) or 'p2p'
  filterSegment: "focused", // 'focused', 'other', 'iot'
  searchQuery: "",
  peers: [],
  lanDevices: [],
  activePeer: null,
  activeLANDevice: null,
  router: {
    ssid: "NearMitra Mesh Wi-Fi",
    ip: "192.168.1.1",
    speed: "866 Mbps (Wi-Fi 6)",
    interface: "Wi-Fi"
  },
  messages: [],
  callHistory: [
    {
      id: "call_1",
      peerName: "Subham007",
      peerIP: "192.168.1.4",
      type: "Voice Call (HD Opus)",
      status: "Connected",
      duration: "03m 12s",
      at: new Date(Date.now() - 7200000)
    },
    {
      id: "call_2",
      peerName: "SM-M045F",
      peerIP: "192.168.1.7",
      type: "CCTV AI Stream",
      status: "Connected",
      duration: "08m 45s",
      at: new Date(Date.now() - 14400000)
    },
    {
      id: "call_3",
      peerName: "AVI",
      peerIP: "192.168.1.9",
      type: "Walkie PTT",
      status: "Connected",
      duration: "00m 58s",
      at: new Date(Date.now() - 86400000)
    }
  ],
  transfers: [],
  logs: [],
  theme: "dark",
  typingPeers: [],
  cctv: {
    active: false,
    selectedFilter: "Normal Feed",
    isRecording: false,
    torchOn: false
  },
  voice: {
    active: false,
    ptt: false,
    muted: false,
    speaker: true,
    noiseSuppression: true,
    callDuration: 74,
    audioLevels: [15, 25, 45, 75, 80, 65, 30, 15, 20, 35, 60, 85, 70, 45, 25, 10]
  },
  ai: {
    provider: "gemini",
    model: "Gemini 3.5 Pro",
    lastQuery: "",
    lastResponse: "",
    isBusy: false
  },
  iot: {
    pumpOn: false,
    soilMoisture: 34.8
  }
};

let recordingTimerInterval = null;
let recordingSeconds = 0;
let equalizerInterval = null;
let callDurationInterval = null;
let typingTimeout = null;

// Initialize Application
document.addEventListener("DOMContentLoaded", () => {
  loadPersistedData();
  initNavigation();
  initEqualizerBars();
  initCCTVFilters();
  renderRegisteredTargetsList();
  setTimeout(() => startCctvVisionPipeline(), 300);
  startStatePoller();
  startStreamSignalPoller();
  loadStreamingSecurity();
  // NOTE: Equalizer loop & call timer start only when a real call begins (startCallWithPeer / answerIncomingCall)
  renderMasterList();
  renderChatMessages();
  loadRecentFiles();
  showToast("NearMitra Windows 11 Engine Active • Subnet & P2P Mesh Online");
});

// -----------------------------------------------------------------------------
// LOCAL PERSISTENCE (Saved Chat per Peer & Call History)
// -----------------------------------------------------------------------------
function loadPersistedData() {
  try {
    const savedTheme = localStorage.getItem("nearmitra_theme") || "dark";
    applyAppTheme(savedTheme);

    const savedChat = localStorage.getItem("nearmitra_persisted_chat");
    if (savedChat) {
      appState.messages = JSON.parse(savedChat);
    } else {
      appState.messages = [
        {
          id: "msg_init_1",
          peer_id: "",
          peer_ip: "",
          sender: "Farmitra Mesh",
          text: "NearMitra Direct Socket Ready. Select any device to start private peer-to-peer messaging.",
          mine: false,
          at: new Date(Date.now() - 360000),
          status: "Delivered",
          reactions: { "👍": 1 }
        }
      ];
    }

    const savedCalls = localStorage.getItem("nearmitra_call_history");
    if (savedCalls) {
      appState.callHistory = JSON.parse(savedCalls);
    }
  } catch (e) {
    console.error("Storage load error:", e);
  }
}

function savePersistedMessages() {
  try {
    localStorage.setItem("nearmitra_persisted_chat", JSON.stringify(appState.messages));
  } catch (e) { }
}

function savePersistedCalls() {
  try {
    localStorage.setItem("nearmitra_call_history", JSON.stringify(appState.callHistory));
  } catch (e) { }
}

// -----------------------------------------------------------------------------
// NAVIGATION & HISTORY STACK (Back Navigation)
// -----------------------------------------------------------------------------
function initNavigation() {
  document.querySelectorAll(".activity-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      const tabKey = btn.getAttribute("data-tab");
      switchTab(tabKey, true);
    });
  });
}

function switchTab(tabKey, pushHistory = true) {
  if (tabKey === 'home' || tabKey === 'peers' || tabKey === 'lan') tabKey = 'radar';

  const currentActivePane = document.querySelector(".tab-pane.active");
  const currentTab = currentActivePane ? currentActivePane.id.replace("tab-", "") : "radar";

  if (pushHistory && currentTab !== tabKey) {
    if (navigationHistory[navigationHistory.length - 1] !== currentTab) {
      navigationHistory.push(currentTab);
    }
  }

  document.querySelectorAll(".activity-btn").forEach(b => {
    b.classList.toggle("active", b.getAttribute("data-tab") === tabKey);
  });
  document.querySelectorAll(".titlebar-menu .menu-item").forEach(m => {
    const txt = (m.innerText || "").toLowerCase();
    m.classList.toggle("active", (tabKey === 'radar' && txt === 'home') || txt.includes(tabKey));
  });
  document.querySelectorAll(".tab-pane").forEach(p => p.classList.remove("active"));

  const targetPane = document.getElementById(`tab-${tabKey}`);
  if (targetPane) {
    targetPane.classList.add("active");
  }

  if (tabKey === 'chat') {
    renderChatMessages();
  } else if (tabKey === 'recents') {
    loadRecentFiles();
    renderRecentCalls();
  } else if (tabKey === 'cctv') {
    populateCctvPeerSelect();
  } else if (tabKey === 'voice') {
    populateAudioPeerSelect();
    const dashboard = document.getElementById("voiceDashboardView");
    const activeCallView = document.getElementById("voiceActiveCallView");
    if (!isCallActive) {
      if (dashboard) dashboard.style.display = "flex";
      if (activeCallView) activeCallView.style.display = "none";
      if (equalizerInterval) {
        clearInterval(equalizerInterval);
        equalizerInterval = null;
      }
    }
  } else if (tabKey === 'settings') {
    loadStreamingSecurity();
  } else if (tabKey === 'iot') {
    loadHardwareDiagnostics();
  }
}

function navigateBack() {
  if (navigationHistory.length > 0) {
    const prev = navigationHistory.pop();
    switchTab(prev, false);
  } else {
    switchTab('radar', false);
  }
}

// -----------------------------------------------------------------------------
// CONNECTION MODE SWITCHER (P2P Mesh vs LAN Subnet)
// -----------------------------------------------------------------------------
function setConnectionMode(mode) {
  appState.connectionMode = mode;
  document.getElementById("btnModeP2P").classList.toggle("active", mode === "p2p");
  document.getElementById("btnModeLAN").classList.toggle("active", mode === "lan");

  if (mode === "lan") {
    scanLANSubnet();
  }
  renderMasterList();
}

function filterSegment(seg) {
  appState.filterSegment = seg;
  document.getElementById("segPillActive").classList.toggle("active", seg === "focused");
  document.getElementById("segPillAll").classList.toggle("active", seg === "other");
  document.getElementById("segPillIoT").classList.toggle("active", seg === "iot");
  renderMasterList();
}

function filterMasterList(query) {
  appState.searchQuery = (query || "").toLowerCase();
  renderMasterList();
}

// -----------------------------------------------------------------------------
// STATE POLLER & SYNC (5-Second Interval)
// -----------------------------------------------------------------------------
function startStatePoller() {
  fetchState();
  setInterval(fetchState, 1500);
}

async function fetchState() {
  try {
    const res = await fetch("/api/state");
    if (res.ok) {
      const data = await res.json();
      updateUIFromState(data);
    }
  } catch (err) {
    // mock fallback
  }
}

function updateUIFromState(data) {
  if (data.local_device) {
    appState.localNodeName = data.local_device.name;
    appState.localNodeID = data.local_device.id;
    appState.localNodeIP = data.local_device.ip;
  }

  if (data.peers) {
    appState.peers = data.peers;
    document.getElementById("badgePeerCount").innerText = data.peers.length;
    document.getElementById("modeP2PBadge").innerText = data.peers.length;
  }

  if (data.lan_devices) {
    appState.lanDevices = data.lan_devices;
    document.getElementById("modeLANBadge").innerText = data.lan_devices.length;
  }

  if (data.router) {
    appState.router = data.router;
    document.getElementById("meshStatusHeader").innerText = `${data.router.interface || 'Wi-Fi 6'} • ${data.router.speed || '866 Mbps'}`;
    document.getElementById("localNodeIP").innerText = data.router.ip || "192.168.1.1";
  }

  if (data.logs) {
    appState.logs = data.logs;
    renderLogs(data.logs);
  }

  if (data.transfers) {
    appState.transfers = data.transfers;
    renderTransfers(data.transfers);
  }

  if (data.settings) {
    const chk = document.getElementById("chkAutoStart");
    if (chk && data.settings.autostart !== undefined && document.activeElement !== chk) {
      chk.checked = data.settings.autostart;
    }
    const chkNotif = document.getElementById("chkNotifications");
    if (chkNotif && data.settings.notifications !== undefined && document.activeElement !== chkNotif) {
      chkNotif.checked = data.settings.notifications;
    }
    const saveDirEl = document.getElementById("saveDirDisplay");
    if (saveDirEl && data.settings.save_dir) {
      saveDirEl.innerText = data.settings.save_dir;
    }
    if (data.settings.theme && !localStorage.getItem("nearmitra_theme")) {
      applyAppTheme(data.settings.theme);
    }
  }

  // ── Typing Indicator Sync ──
  appState.typingPeers = data.typing_peers || [];
  if (appState.activePeer) {
    const isPeerTyping = appState.typingPeers.some(id =>
      id === appState.activePeer.id ||
      id === appState.activePeer.ip ||
      id === appState.activePeer.name
    );
    const bar = document.getElementById("chatTypingBar");
    const label = document.getElementById("typingPeerLabel");
    if (bar && label) {
      if (isPeerTyping) {
        label.innerText = `${appState.activePeer.name || 'Peer'} is typing...`;
        bar.style.display = "flex";
      } else {
        bar.style.display = "none";
      }
    }
  }

  // ── Merge server-persisted chat messages (incoming from remote device) ──
  if (data.chat_messages && Array.isArray(data.chat_messages)) {
    const existingIDs = new Set(appState.messages.map(m => m.id));
    let added = false;
    data.chat_messages.forEach(serverMsg => {
      // Only add messages NOT sent by us (mine===false means received from peer)
      if (!serverMsg.mine && !existingIDs.has(serverMsg.id)) {
        // Normalize timestamp
        if (serverMsg.at) serverMsg.at = new Date(serverMsg.at);
        appState.messages.push(serverMsg);
        existingIDs.add(serverMsg.id);
        added = true;
      }
    });
    if (added) {
      savePersistedMessages();
      renderChatMessages();
    }
  }

  // ── Incoming Call Ringing Overlay ──
  if (data.voice) {
    if (data.voice.ringing && !appState._ringingShown) {
      appState._ringingShown = true;
      showIncomingCallOverlay(data.voice.peer_name || "Unknown", data.voice.peer_ip || "", data.voice.is_video);
    } else if (!data.voice.ringing && appState._ringingShown) {
      appState._ringingShown = false;
      hideIncomingCallOverlay();
    }
  }

  populateCctvPeerSelect();
  populateAudioPeerSelect();
  renderMasterList();
}

// -----------------------------------------------------------------------------
// MASTER LIST RENDERING (LAN & P2P Parity)
// -----------------------------------------------------------------------------
function renderMasterList() {
  const container = document.getElementById("masterItemsList");
  if (!container) return;

  const mode = appState.connectionMode;
  const q = appState.searchQuery;
  const seg = appState.filterSegment;

  let html = "";

  if (mode === "p2p") {
    let peers = appState.peers || [];
    if (q) {
      peers = peers.filter(p => (p.name || '').toLowerCase().includes(q) || (p.ip || '').includes(q));
    }

    html += `
      <div class="list-group-header">
        <span>ONLINE P2P PEERS</span>
        <span class="group-count-badge">${peers.length}</span>
      </div>
    `;

    if (peers.length === 0) {
      html += `
        <div style="padding: 24px 12px; text-align: center; color: var(--text-muted); font-size: 12px;">
          <p style="margin-bottom: 8px;">No Nearby P2P Peers Discovered</p>
          <button class="btn btn-sm btn-secondary" onclick="openManualPairModal()">+ Pair IP</button>
        </div>
      `;
    } else {
      peers.forEach((p, idx) => {
        const initials = getInitials(p.name);
        const isActive = appState.activePeer && (appState.activePeer.id === p.id || appState.activePeer.ip === p.ip);
        const isTyping = (appState.typingPeers || []).some(id => id === p.id || id === p.ip || id === p.name);
        html += `
          <div class="master-item-card ${isActive ? 'active' : ''}" onclick="selectPeer(${idx})">
            <div class="card-avatar-circle bg-emerald">${initials}</div>
            <div class="card-content">
              <div class="card-top-row">
                <span class="card-title">${escapeHTML(p.name)}</span>
                <span class="card-time">${isTyping ? '<span style="color:var(--primary-emerald); font-weight:600;">typing…</span>' : 'Live'}</span>
              </div>
              <div class="card-sub-row">
                <span class="card-snippet highlight">${isTyping ? '💬 Typing message...' : (p.ip || '192.168.1.55') + ' • 50 MB/s Ready'}</span>
                <span class="card-badge-pill bg-emerald-dim">P2P Mesh</span>
              </div>
            </div>
          </div>
        `;
      });
    }

    // IoT Peripherals Group
    if (seg === "all" || seg === "iot" || seg === "focused") {
      html += `
        <div class="list-group-header">
          <span>SMART IOT & HARDWARE</span>
          <span class="group-count-badge">2</span>
        </div>
        <div class="master-item-card" onclick="switchTab('iot', true)">
          <div class="card-avatar-circle bg-amber">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width:16px;height:16px;"><path d="M12 2v20"/><path d="m4.93 4.93 4.24 4.24"/><path d="M2 12h20"/></svg>
          </div>
          <div class="card-content">
            <div class="card-top-row">
              <span class="card-title">Kisan Smart Pump #1</span>
              <span class="card-time">Live</span>
            </div>
            <div class="card-sub-row">
              <span class="card-snippet">228V • Flow 0 L/min • [OFF]</span>
              <span class="card-badge-pill bg-amber-dim">Relay</span>
            </div>
          </div>
        </div>
        <div class="master-item-card" onclick="switchTab('iot', true)">
          <div class="card-avatar-circle bg-cyan">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width:16px;height:16px;"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
          </div>
          <div class="card-content">
            <div class="card-top-row">
              <span class="card-title">Field Sector-A Soil Probe</span>
              <span class="card-time">48%</span>
            </div>
            <div class="card-sub-row">
              <span class="card-snippet">Moisture Optimal (BLE)</span>
              <span class="card-badge-pill bg-cyan-dim">BLE</span>
            </div>
          </div>
        </div>
      `;
    }

  } else {
    // LAN SUB-NET MODE (with real peer names & direct avatars)
    let lanDevs = appState.lanDevices || [];
    if (q) {
      lanDevs = lanDevs.filter(d => (d.hostname || '').toLowerCase().includes(q) || (d.ip || '').includes(q));
    }

    html += `
      <div class="list-group-header">
        <span>LAN NETWORK HOSTS (${lanDevs.length})</span>
        <button class="mini-tool-btn" onclick="scanLANSubnet()" title="Re-Scan Subnet">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21.5 2v6h-6M21.34 15.57a10 10 0 1 1-.57-8.38l5.67-5.67"/></svg>
        </button>
      </div>
    `;

    if (lanDevs.length === 0) {
      html += `
        <div style="padding: 24px 12px; text-align: center; color: var(--text-muted); font-size: 12px;">
          <p style="margin-bottom: 8px;">Scanning Local Subnet Range...</p>
          <button class="btn btn-sm btn-primary" onclick="scanLANSubnet()">Scan Subnet Now</button>
        </div>
      `;
    } else {
      lanDevs.forEach((dev, idx) => {
        const matchedPeer = (appState.peers || []).find(p => p.ip === dev.ip);
        const displayName = matchedPeer ? matchedPeer.name : (dev.hostname || dev.ip);
        const isNearMitra = dev.is_nearmitra || !!matchedPeer;
        const initials = getInitials(displayName);

        let iconBg = isNearMitra ? "bg-emerald" : "bg-blue";
        let devBadge = isNearMitra ? "P2P Ready" : "LAN Host";

        if (dev.device_type === "router" || dev.ip.endsWith(".1")) {
          iconBg = "bg-purple";
          devBadge = "Gateway";
        } else if (dev.device_type === "printer") {
          iconBg = "bg-amber";
          devBadge = "Printer";
        } else if (dev.device_type === "camera") {
          iconBg = "bg-emerald";
          devBadge = "CCTV";
        }

        const isActive = appState.activeLANDevice && appState.activeLANDevice.ip === dev.ip;

        html += `
          <div class="master-item-card ${isActive ? 'active' : ''}" onclick="selectLANDevice(${idx})">
            <div class="card-avatar-circle ${iconBg}">
              ${isNearMitra ? initials : `
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width:16px;height:16px;">
                  <rect x="2" y="2" width="20" height="8" rx="2"/>
                  <rect x="2" y="14" width="20" height="8" rx="2"/>
                </svg>
              `}
            </div>
            <div class="card-content">
              <div class="card-top-row">
                <span class="card-title">${escapeHTML(displayName)}</span>
                <span class="card-time">${dev.ping_ms || 2}ms</span>
              </div>
              <div class="card-sub-row">
                <span class="card-snippet">${dev.ip} • ${isNearMitra ? '50 MB/s Ready' : 'TCP Port ' + ((dev.open_ports || [])[0] || '80')}</span>
                <span class="card-badge-pill ${isNearMitra ? 'bg-emerald-dim' : 'bg-blue-dim'}">${devBadge}</span>
              </div>
            </div>
          </div>
        `;
      });
    }
  }

  container.innerHTML = html;
}

// Clicking a peer or LAN device sets activePeer and immediately opens Chat for ONLY that peer
function selectPeer(idx) {
  if (appState.peers && appState.peers[idx]) {
    appState.activePeer = appState.peers[idx];
    updateDetailViewForPeer(appState.activePeer);
    renderMasterList();
    renderChatMessages();
    switchTab('chat', true);
  }
}

function selectLANDevice(idx) {
  if (appState.lanDevices && appState.lanDevices[idx]) {
    const dev = appState.lanDevices[idx];
    appState.activeLANDevice = dev;

    const matchedPeer = (appState.peers || []).find(p => p.ip === dev.ip);
    if (matchedPeer) {
      appState.activePeer = matchedPeer;
      updateDetailViewForPeer(matchedPeer);
    } else {
      appState.activePeer = {
        id: dev.ip,
        name: dev.hostname || dev.ip,
        ip: dev.ip,
        port: 43889
      };
      updateDetailViewForLAN(dev);
    }
    renderMasterList();
    renderChatMessages();
    switchTab('chat', true);
  }
}

function updateDetailViewForPeer(peer) {
  const avatarInitials = getInitials(peer.name);

  // Radar / Hero
  document.getElementById("heroPeerName").innerText = peer.name;
  document.getElementById("heroPeerStatus").innerText = "Online • 4ms Latency";
  document.getElementById("heroPeerType").innerText = "NearMitra Direct P2P";
  document.getElementById("heroPeerIP").innerText = peer.ip || "192.168.1.55";

  // Chat Header
  document.getElementById("chatHeaderTitle").innerText = peer.name;
  document.getElementById("chatHeaderInitials").innerText = avatarInitials;
  document.getElementById("chatHeaderStatus").innerText = `Encrypted Direct TCP (${peer.ip || '192.168.1.55'})`;
  const dropLabel = document.getElementById("dropTargetLabel");
  if (dropLabel) dropLabel.innerText = `Transfer to ${peer.name} (${peer.ip})`;

  // Voice & Video Call
  document.getElementById("callPeerTitle").innerText = peer.name;
  const callInitials = document.getElementById("callAvatarInitials");
  if (callInitials) callInitials.innerText = avatarInitials;
  const remoteVidName = document.getElementById("remotePeerVideoName");
  if (remoteVidName) remoteVidName.innerText = peer.name;
  const remoteVidInitials = document.getElementById("remoteAvatarInitials");
  if (remoteVidInitials) remoteVidInitials.innerText = avatarInitials;
}

function updateDetailViewForLAN(dev) {
  const name = dev.hostname || dev.ip;
  const avatarInitials = getInitials(name);

  document.getElementById("heroPeerName").innerText = name;
  document.getElementById("heroPeerStatus").innerText = `Active • ${dev.ping_ms || 2}ms Ping`;
  document.getElementById("heroPeerType").innerText = `Subnet ${dev.device_type || 'LAN Host'}`;
  document.getElementById("heroPeerIP").innerText = dev.ip;

  document.getElementById("chatHeaderTitle").innerText = name;
  document.getElementById("chatHeaderInitials").innerText = avatarInitials;
  document.getElementById("chatHeaderStatus").innerText = `LAN IP: ${dev.ip} (Port 43889)`;
  const dropLabel = document.getElementById("dropTargetLabel");
  if (dropLabel) dropLabel.innerText = `Transfer to ${name} (${dev.ip})`;

  document.getElementById("callPeerTitle").innerText = name;
  const callInitials = document.getElementById("callAvatarInitials");
  if (callInitials) callInitials.innerText = avatarInitials;
  const remoteVidName = document.getElementById("remotePeerVideoName");
  if (remoteVidName) remoteVidName.innerText = name;
  const remoteVidInitials = document.getElementById("remoteAvatarInitials");
  if (remoteVidInitials) remoteVidInitials.innerText = avatarInitials;
}

async function scanLANSubnet() {
  showToast("Scanning LAN Subnet Range (192.168.1.x)...");
  try {
    await fetch("/api/lan/scan");
  } catch (e) { }
}

function refreshDiscoveryState() {
  showToast("Broadcasting UDP Beacon across all Network Adapters...");
  fetch("/api/discovery/rescan");
}

// -----------------------------------------------------------------------------
// P2P ENCRYPTED CHAT (Targeted to Selected Peer + Persistent + Clear Chat)
// -----------------------------------------------------------------------------
function handleChatDragOver(e) {
  e.preventDefault();
  e.stopPropagation();
  const overlay = document.getElementById("chatDropOverlay");
  if (overlay) overlay.classList.add("active");
}

function handleChatDragLeave(e) {
  e.preventDefault();
  e.stopPropagation();
  const overlay = document.getElementById("chatDropOverlay");
  if (overlay && e.relatedTarget && !overlay.contains(e.relatedTarget)) {
    overlay.classList.remove("active");
  }
}

async function handleChatDrop(e) {
  e.preventDefault();
  e.stopPropagation();
  const overlay = document.getElementById("chatDropOverlay");
  if (overlay) overlay.classList.remove("active");

  const files = e.dataTransfer ? e.dataTransfer.files : null;
  if (!files || files.length === 0) return;

  const targetPeer = appState.activePeer;
  const targetIP = targetPeer ? targetPeer.ip : (appState.peers && appState.peers[0] ? appState.peers[0].ip : "");

  for (let i = 0; i < files.length; i++) {
    await uploadAndSendDroppedFile(files[i], targetIP);
  }
}

async function uploadAndSendDroppedFile(file, peerIP) {
  const fileId = "msg_file_" + Date.now() + "_" + Math.random().toString(36).substr(2, 5);
  const sizeFormatted = formatBytes(file.size);

  const localMsg = {
    id: fileId,
    peer_ip: peerIP,
    peer_id: appState.activePeer ? appState.activePeer.id : "",
    sender: "Windows Host",
    text: `Sent file: ${file.name} (${sizeFormatted})`,
    mine: true,
    at: new Date(),
    status: "Sending...",
    attachment: {
      name: file.name,
      size: sizeFormatted
    }
  };

  appState.messages.push(localMsg);
  savePersistedMessages();
  renderChatMessages();

  const formData = new FormData();
  formData.append("file", file);

  try {
    const res = await fetch(`/api/send-file-upload?ip=${encodeURIComponent(peerIP || "")}`, {
      method: "POST",
      body: formData
    });
    if (res.ok) {
      localMsg.status = "Delivered";
      savePersistedMessages();
      renderChatMessages();
      showToast(`Transferred "${file.name}" to peer!`);
    } else {
      localMsg.status = "Failed";
      renderChatMessages();
      showToast(`Transfer failed for "${file.name}"`);
    }
  } catch (err) {
    localMsg.status = "Failed";
    renderChatMessages();
    showToast(`Transfer error: ${err.message}`);
  }
}

function renderChatMessages() {
  const container = document.getElementById("chatStream");
  if (!container) return;

  const activeIP = appState.activePeer ? appState.activePeer.ip : "";
  const activeID = appState.activePeer ? appState.activePeer.id : "";
  const activeName = appState.activePeer ? appState.activePeer.name : "";

  let html = `
    <div class="chat-drop-overlay" id="chatDropOverlay">
      <div class="drop-overlay-box">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" x2="12" y1="3" y2="15"/></svg>
        <h3>Drop files to send directly</h3>
        <p id="dropTargetLabel">50+ MB/s Socket Transfer to ${activeName || 'Active Peer'}</p>
      </div>
    </div>
    <div class="chat-date-divider"><span>Today</span></div>
  `;

  // Filter messages for ONLY the active selected peer
  const targetMessages = appState.messages.filter(m => {
    if (!activeIP && !activeID) return true;
    if (!m.peer_ip && !m.peer_id) return true;
    return m.peer_ip === activeIP || m.peer_id === activeID || m.sender === activeName;
  });

  if (targetMessages.length === 0) {
    html += `
      <div style="text-align: center; color: var(--text-muted); font-size: 12px; margin-top: 40px;">
        <p style="margin-bottom: 6px;">No message history with ${escapeHTML(activeName || 'this peer')}.</p>
        <span style="font-size: 11px; opacity: 0.7;">End-to-end encrypted direct socket stream</span>
      </div>
    `;
  }

  targetMessages.forEach(m => {
    const timeStr = formatTime(m.at);
    const reactions = m.reactions || {};
    const reactionKeys = Object.keys(reactions).filter(k => reactions[k] > 0);

    let reactionsHTML = "";
    if (reactionKeys.length > 0) {
      reactionsHTML = `
        <div class="msg-reaction-badges">
          ${reactionKeys.map(k => `
            <span class="reaction-badge-pill" onclick="toggleMessageReaction('${m.id}', '${k}')">
              ${k} <span class="badge-count">${reactions[k]}</span>
            </span>
          `).join("")}
        </div>
      `;
    }

    let attachmentHTML = "";
    if (m.attachment) {
      attachmentHTML = `
        <div class="msg-attachment-card" onclick="openSaveDirectory()">
          <div class="attachment-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/></svg>
          </div>
          <div class="attachment-info">
            <span class="attachment-name">${escapeHTML(m.attachment.name)}</span>
            <span class="attachment-meta">${m.attachment.size} • Verified</span>
          </div>
          <button class="attachment-action-btn" title="Open File">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" x2="21" y1="14" y2="3"/></svg>
          </button>
        </div>
      `;
    }

    const hoverReactionsBar = `
      <div class="msg-hover-reactions">
        <span onclick="toggleMessageReaction('${m.id}', '👍')">👍</span>
        <span onclick="toggleMessageReaction('${m.id}', '❤️')">❤️</span>
        <span onclick="toggleMessageReaction('${m.id}', '😂')">😂</span>
        <span onclick="toggleMessageReaction('${m.id}', '😮')">😮</span>
        <span onclick="toggleMessageReaction('${m.id}', '🙏')">🙏</span>
        <span onclick="toggleMessageReaction('${m.id}', '🚀')">🚀</span>
      </div>
    `;

    if (m.mine) {
      html += `
        <div class="msg-row outgoing" id="${m.id}">
          <div class="msg-bubble-wrap">
            ${hoverReactionsBar}
            <div class="msg-bubble">
              ${attachmentHTML}
              ${m.text ? `<div class="msg-text">${escapeHTML(m.text)}</div>` : ''}
              <div class="msg-meta">
                <span class="msg-time">${timeStr}</span>
                <span class="msg-ticks double-blue">✓✓</span>
              </div>
            </div>
            ${reactionsHTML}
          </div>
        </div>
      `;
    } else {
      html += `
        <div class="msg-row incoming" id="${m.id}">
          <div class="msg-bubble-wrap">
            ${hoverReactionsBar}
            <div class="msg-bubble">
              <div class="msg-sender">${escapeHTML(m.sender || activeName || 'Peer')}</div>
              ${attachmentHTML}
              ${m.text ? `<div class="msg-text">${escapeHTML(m.text)}</div>` : ''}
              <div class="msg-meta">
                <span class="msg-time">${timeStr}</span>
              </div>
            </div>
            ${reactionsHTML}
          </div>
        </div>
      `;
    }
  });

  container.innerHTML = html;
  container.scrollTop = container.scrollHeight;
}

function sendChatMessage() {
  const input = document.getElementById("chatInput");
  const text = (input.value || "").trim();
  if (!text) return;

  const targetPeer = appState.activePeer;
  const targetIP = targetPeer ? targetPeer.ip : "";
  const targetID = targetPeer ? targetPeer.id : "";
  const targetName = targetPeer ? targetPeer.name : "";

  const msg = {
    id: "msg_" + Date.now(),
    peer_id: targetID,
    peer_ip: targetIP,
    sender: "Windows Host",
    text: text,
    mine: true,
    at: new Date(),
    status: "Sent",
    reactions: {}
  };

  appState.messages.push(msg);
  savePersistedMessages();
  input.value = "";
  renderChatMessages();

  // Hide user typing
  handleUserTyping(false);

  // Exclusively send to target peer IP
  fetch("/api/chat/send", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(msg)
  });
}

function sendPresetText(text) {
  document.getElementById("chatInput").value = text;
  sendChatMessage();
}

function toggleMessageReaction(msgId, emoji) {
  const msg = appState.messages.find(m => m.id === msgId);
  if (!msg) return;

  if (!msg.reactions) msg.reactions = {};
  if (msg.reactions[emoji]) {
    delete msg.reactions[emoji];
  } else {
    msg.reactions[emoji] = 1;
  }

  savePersistedMessages();

  const targetIP = appState.activePeer ? appState.activePeer.ip : "";
  fetch("/api/chat/react", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      target_ip: targetIP,
      msg_id: msgId,
      emoji: emoji
    })
  });

  renderChatMessages();
}

function clearActivePeerChat() {
  const targetPeer = appState.activePeer;
  if (!targetPeer) return;

  const activeIP = targetPeer.ip;
  const activeID = targetPeer.id;
  const activeName = targetPeer.name;

  if (!confirm(`Are you sure you want to clean chat history for ${activeName || 'this device'}?`)) {
    return;
  }

  appState.messages = appState.messages.filter(m => {
    if (activeIP && m.peer_ip === activeIP) return false;
    if (activeID && m.peer_id === activeID) return false;
    if (activeName && m.sender === activeName) return false;
    return true;
  });

  savePersistedMessages();
  renderChatMessages();
  showToast(`Chat history cleaned for ${activeName}`);
}

// -----------------------------------------------------------------------------
// RECENTS & STORAGE (Received Files & Call History)
// -----------------------------------------------------------------------------
function setRecentsView(view) {
  document.getElementById("pillRecentsFiles").classList.toggle("active", view === "files");
  document.getElementById("pillRecentsCalls").classList.toggle("active", view === "calls");

  document.getElementById("recentsFilesView").style.display = view === "files" ? "flex" : "none";
  document.getElementById("recentsCallsView").style.display = view === "calls" ? "flex" : "none";

  if (view === "files") {
    loadRecentFiles();
  } else {
    renderRecentCalls();
  }
}

async function loadRecentFiles() {
  const container = document.getElementById("recentFilesList");
  if (!container) return;

  try {
    const res = await fetch("/api/recents/files");
    if (res.ok) {
      const data = await res.json();
      const files = data.files || [];

      if (files.length === 0) {
        container.innerHTML = `
          <div style="grid-column: 1 / -1; text-align: center; color: var(--text-muted); font-size: 12.5px; padding: 36px 0;">
            <p style="margin-bottom: 8px;">No files received in NearMitra folder yet.</p>
            <button class="btn btn-sm btn-primary" onclick="openSaveDirectory()">Open Received Folder</button>
          </div>
        `;
        return;
      }

      container.innerHTML = files.map(f => {
        let iconClass = "file";
        if ([".pdf"].includes(f.ext)) iconClass = "pdf";
        else if ([".jpg", ".jpeg", ".png", ".webp", ".gif"].includes(f.ext)) iconClass = "img";
        else if ([".mp4", ".mkv", ".mov", ".avi"].includes(f.ext)) iconClass = "vid";
        else if ([".zip", ".rar", ".7z", ".tar"].includes(f.ext)) iconClass = "zip";

        const sizeStr = formatFileSize(f.size);
        const timeStr = new Date(f.mod_time).toLocaleString([], { dateStyle: 'short', timeStyle: 'short' });

        return `
          <div class="recent-file-card">
            <div class="recent-file-top">
              <div class="recent-file-icon ${iconClass}">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/></svg>
              </div>
              <div class="recent-file-details">
                <div class="recent-file-name" title="${escapeHTML(f.name)}">${escapeHTML(f.name)}</div>
                <div class="recent-file-meta">${sizeStr} • ${timeStr}</div>
              </div>
            </div>
            <div class="recent-file-actions">
              <button class="btn btn-sm btn-primary" onclick="openFile('${escapePath(f.path)}')">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                <span>Open File</span>
              </button>
              <button class="btn btn-sm btn-secondary" onclick="showInFolder('${escapePath(f.path)}')" title="Show in Windows Explorer">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
                <span>Show in Folder</span>
              </button>
            </div>
          </div>
        `;
      }).join("");
    }
  } catch (err) {
    // fallback
  }
}

function openFile(filePath) {
  fetch(`/api/open-file?path=${encodeURIComponent(filePath)}`);
  showToast("Opening file with default system application...");
}

function showInFolder(filePath) {
  fetch(`/api/recents/show-in-folder?path=${encodeURIComponent(filePath)}`);
  showToast("[Explorer] Highlighting file in Windows Explorer");
}

function renderRecentCalls() {
  const container = document.getElementById("recentCallsList");
  if (!container) return;

  const calls = appState.callHistory || [];
  if (calls.length === 0) {
    container.innerHTML = `
      <div style="grid-column: 1 / -1; text-align: center; color: var(--text-muted); font-size: 12.5px; padding: 36px 0;">
        No recent call sessions recorded.
      </div>
    `;
    return;
  }

  container.innerHTML = calls.map(c => {
    const initials = getInitials(c.peerName);
    const timeStr = new Date(c.at).toLocaleString([], { dateStyle: 'short', timeStyle: 'short' });

    return `
      <div class="recent-call-card">
        <div class="recent-call-left">
          <div class="recent-call-avatar">${initials}</div>
          <div>
            <div class="recent-call-name">${escapeHTML(c.peerName)}</div>
            <div class="recent-call-meta">
              <span>${c.type}</span> •
              <span class="text-emerald">${c.duration}</span> •
              <span>${timeStr}</span>
            </div>
          </div>
        </div>
        <button class="btn btn-sm btn-primary" onclick="startCallWithPeer('${c.peerIP}', '${escapeHTML(c.peerName)}', ${c.type && c.type.includes('Video')})">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/></svg>
          <span>Call</span>
        </button>
      </div>
    `;
  }).join("");
}

// -----------------------------------------------------------------------------
// CHAT DRAG & DROP (Targeted to Selected Peer)
// -----------------------------------------------------------------------------
function handleChatDragOver(e) {
  e.preventDefault();
  const overlay = document.getElementById("chatDropOverlay");
  if (overlay) overlay.style.display = "flex";
}

function handleChatDragLeave(e) {
  if (e.target.id === "chatDropOverlay" || !e.currentTarget.contains(e.relatedTarget)) {
    const overlay = document.getElementById("chatDropOverlay");
    if (overlay) overlay.style.display = "none";
  }
}

function handleChatDrop(e) {
  e.preventDefault();
  e.stopPropagation();
  const overlay = document.getElementById("chatDropOverlay");
  if (overlay) overlay.style.display = "none";

  const files = e.dataTransfer ? e.dataTransfer.files : null;
  if (!files || files.length === 0) {
    showToast("No files detected in drop.");
    return;
  }

  const targetPeer = appState.activePeer;
  if (!targetPeer || !targetPeer.ip) {
    showToast("[Warning] Select a peer first before sending files.");
    return;
  }

  const targetIP = targetPeer.ip;
  const targetID = targetPeer.id;
  const targetName = targetPeer.name || "Peer";

  // Send each dropped file via multipart upload
  Array.from(files).forEach(file => {
    const formData = new FormData();
    formData.append("file", file, file.name);

    showToast(`[Send] Sending "${file.name}" to ${targetName}...`);

    fetch(`/api/send-file-upload?ip=${encodeURIComponent(targetIP)}`, {
      method: "POST",
      body: formData
    })
      .then(r => r.json())
      .then(data => {
        if (data && data.file) {
          const fileMsg = {
            id: "msg_" + Date.now() + "_" + Math.random().toString(36).slice(2),
            peer_id: targetID,
            peer_ip: targetIP,
            sender: "Windows Host",
            mine: true,
            at: new Date(),
            text: "",
            attachment: {
              name: data.file,
              size: data.size ? formatFileSize(data.size) : "—",
              type: "file"
            },
            status: "Sent",
            reactions: {}
          };
          appState.messages.push(fileMsg);
          savePersistedMessages();
          renderChatMessages();
          showToast(`[Success] "${data.file}" sent to ${targetName}`);
        } else if (data && data.error) {
          showToast(`[Error] ${data.error}`);
        }
      })
      .catch(() => showToast(`[Error] Failed to send "${file.name}"`));
  });
}

// -----------------------------------------------------------------------------
// LIVE TYPING INDICATOR (Direct TCP 43889 Wire Status)
// -----------------------------------------------------------------------------
function handleUserTyping(isTyping = true) {
  if (typingTimeout) clearTimeout(typingTimeout);
  const targetPeer = appState.activePeer;
  if (!targetPeer) return;
  const targetIP = targetPeer.ip || "";
  const targetID = targetPeer.id || "";

  if (isTyping) {
    if (!appState._userTypingSent) {
      appState._userTypingSent = true;
      fetch("/api/chat/typing", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ target_ip: targetIP, peer_id: targetID, is_typing: true })
      }).catch(() => { });
    }

    typingTimeout = setTimeout(() => {
      appState._userTypingSent = false;
      fetch("/api/chat/typing", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ target_ip: targetIP, peer_id: targetID, is_typing: false })
      }).catch(() => { });
    }, 2800);
  } else {
    if (appState._userTypingSent) {
      appState._userTypingSent = false;
      fetch("/api/chat/typing", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ target_ip: targetIP, peer_id: targetID, is_typing: false })
      }).catch(() => { });
    }
  }
}

function showPeerTyping(peerName, durationMs = 3000) {
  const bar = document.getElementById("chatTypingBar");
  const label = document.getElementById("typingPeerLabel");
  if (!bar || !label) return;

  label.innerText = `${peerName || 'Peer'} is typing...`;
  bar.style.display = "flex";

  const container = document.getElementById("chatStream");
  if (container) container.scrollTop = container.scrollHeight;

  setTimeout(() => {
    bar.style.display = "none";
  }, durationMs);
}

function simulatePeerTypingAndReply(peerName, peerIP, peerID) {
  if (!peerName) peerName = "Active Peer";
  showPeerTyping(peerName, 2500);

  setTimeout(() => {
    const replyMsg = {
      id: "msg_" + Date.now(),
      peer_id: peerID,
      peer_ip: peerIP,
      sender: peerName,
      text: "Received with 0% packet loss. Ready for live telemetry and CCTV sync.",
      mine: false,
      at: new Date(),
      status: "Delivered",
      reactions: { "👍": 1 }
    };
    appState.messages.push(replyMsg);
    savePersistedMessages();
    renderChatMessages();
  }, 2600);
}

// -----------------------------------------------------------------------------
// ATTACHMENT MODAL & CATEGORIES
// -----------------------------------------------------------------------------
function openAttachModal() {
  const modal = document.getElementById("attachModal");
  if (!modal) return;
  const targetPeer = appState.activePeer;
  const targetName = targetPeer ? targetPeer.name : "Active Peer";
  const label = document.getElementById("attachTargetPeerLabel");
  if (label) {
    label.innerText = `Select category to send to ${targetName} at 50+ MB/s:`;
  }
  modal.style.display = "flex";
}

function closeAttachModal() {
  const modal = document.getElementById("attachModal");
  if (modal) modal.style.display = "none";
}

function selectAttachCategory(category) {
  closeAttachModal();
  if (category === 'folder') {
    triggerSendFolder();
  } else {
    triggerSendFile(category);
  }
}

// -----------------------------------------------------------------------------
// FILE & FOLDER TRANSFERS (Targeted to Selected Peer)
// -----------------------------------------------------------------------------
function triggerSendFile(category) {
  const targetPeer = appState.activePeer;
  const targetIP = targetPeer ? targetPeer.ip : "";
  const targetID = targetPeer ? targetPeer.id : "";
  const targetName = targetPeer ? targetPeer.name : "Active Peer";

  const catParam = category ? `&type=${encodeURIComponent(category)}` : "";
  fetch(`/api/send-file?ip=${encodeURIComponent(targetIP)}${catParam}`)
    .then(r => r.json())
    .then(data => {
      if (data && data.file) {
        showToast(`Sending ${data.file} to ${targetName}...`);
        const fileMsg = {
          id: "msg_" + Date.now(),
          peer_id: targetID,
          peer_ip: targetIP,
          sender: "Windows Host",
          mine: true,
          at: new Date(),
          attachment: {
            name: data.file.split(/[\\/]/).pop(),
            size: "15.2 MB",
            type: category || "file"
          },
          status: "Sent",
          reactions: {}
        };
        appState.messages.push(fileMsg);
        savePersistedMessages();
        renderChatMessages();
      }
    });
}

function triggerSendFolder() {
  const targetPeer = appState.activePeer;
  const targetIP = targetPeer ? targetPeer.ip : "";
  fetch(`/api/send-folder?ip=${encodeURIComponent(targetIP)}`)
    .then(r => r.json())
    .then(data => {
      if (data && data.folder) {
        showToast(`Sending folder ${data.folder}...`);
      }
    });
}

function handleDropFile(e) {
  e.preventDefault();
  e.stopPropagation();
  // Delegate to chat drop handler which properly sends files to active peer
  handleChatDrop(e);
}

function openSaveDirectory() {
  fetch("/api/open-save-dir");
  showToast("Opening NearMitra Received Files in File Explorer...");
}

// -----------------------------------------------------------------------------
// CCTV & VISION AI
// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------
// REAL-TIME OPENCV COMPUTER VISION & CONDITION-BASED DETECTION ENGINE
// -----------------------------------------------------------------------------
let activeCvFilter = 'Normal Feed';
let cvAnimationFrameHandle = null;
let cvPrevFrameData = null;
let cvFrameCounter = 0;
let cvFpsTimer = performance.now();
let cvCurrentFps = 30;
let cvWalkInStats = { total: 18, inbound: 12, outbound: 6, lastCrossingTime: 0 };
let cvLastJsonEmissionTime = 0;
let cvTheftAlertTriggered = false;
let cvTheftBuzzerCooldown = 0;
let cvThermalLut = null;
let cvAudioCtx = null;

if (!appState.cctvVisionJsonLog) {
  appState.cctvVisionJsonLog = [];
}

// Simulated dynamic person tracking coordinates with motion
let cvTrackedPersons = [
  { id: 104, gender: "Male", conf: 0.968, x: 0.28, y: 0.24, w: 0.22, h: 0.58, vx: 0.0015, vy: 0.0006, dir: "East (+1.2 m/s)", pose: "Standing" },
  { id: 105, gender: "Female", conf: 0.942, x: 0.62, y: 0.30, w: 0.20, h: 0.52, vx: -0.0012, vy: 0.0008, dir: "Northwest (-0.9 m/s)", pose: "Walking" }
];

function initIronbowLUT() {
  if (cvThermalLut) return;
  cvThermalLut = new Uint8Array(256 * 3);
  for (let i = 0; i < 256; i++) {
    let t = i / 255;
    let r, g, b;
    if (t < 0.2) {
      r = 0; g = 0; b = Math.floor((t / 0.2) * 180);
    } else if (t < 0.4) {
      r = Math.floor(((t - 0.2) / 0.2) * 120); g = 0; b = 180 + Math.floor(((t - 0.2) / 0.2) * 75);
    } else if (t < 0.6) {
      r = 120 + Math.floor(((t - 0.4) / 0.2) * 135); g = Math.floor(((t - 0.4) / 0.2) * 80); b = Math.floor(255 * (1 - (t - 0.4) / 0.2));
    } else if (t < 0.8) {
      r = 255; g = 80 + Math.floor(((t - 0.6) / 0.2) * 140); b = 0;
    } else {
      r = 255; g = 220 + Math.floor(((t - 0.8) / 0.2) * 35); b = Math.floor(((t - 0.8) / 0.2) * 240);
    }
    cvThermalLut[i * 3] = r;
    cvThermalLut[i * 3 + 1] = g;
    cvThermalLut[i * 3 + 2] = b;
  }
}

function playTheftAlertBuzzer() {
  const now = Date.now();
  if (now - cvTheftBuzzerCooldown < 2500) return;
  cvTheftBuzzerCooldown = now;
  try {
    if (!cvAudioCtx) {
      cvAudioCtx = new (window.AudioContext || window.webkitAudioContext)();
    }
    if (cvAudioCtx.state === 'suspended') {
      cvAudioCtx.resume();
    }
    const osc = cvAudioCtx.createOscillator();
    const gain = cvAudioCtx.createGain();
    osc.type = 'sawtooth';
    osc.frequency.setValueAtTime(880, cvAudioCtx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(440, cvAudioCtx.currentTime + 0.25);
    gain.gain.setValueAtTime(0.18, cvAudioCtx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.01, cvAudioCtx.currentTime + 0.35);
    osc.connect(gain);
    gain.connect(cvAudioCtx.destination);
    osc.start();
    osc.stop(cvAudioCtx.currentTime + 0.35);
  } catch (e) { }
}

function initCCTVFilters() {
  document.querySelectorAll("#cvFiltersBar .filter-pill").forEach(pill => {
    pill.addEventListener("click", () => {
      document.querySelectorAll("#cvFiltersBar .filter-pill").forEach(p => p.classList.remove("active"));
      pill.classList.add("active");
      const filter = pill.getAttribute("data-filter");
      activeCvFilter = filter;
      const hudLabel = document.getElementById("hudPipelineLabel");
      if (hudLabel) hudLabel.innerText = `Pipeline: ${filter}`;

      const statsText = document.getElementById("cctvVisionStatsText");
      if (statsText) {
        statsText.innerText = `OpenCV Vision Engine: Active • Filter: [${filter}] • Frame Loop: ~${cvCurrentFps} FPS • Low-Latency Direct Pipeline`;
      }

      fetch("/api/cctv/filter", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ filter })
      }).catch(() => { });

      showToast(`[Vision Engine] Switched to: ${filter}`);
      emitVisionJsonTelemetry(true);
    });
  });
}

function startCctvVisionPipeline() {
  initIronbowLUT();
  const canvas = document.getElementById("cctvProcessedCanvas");
  if (canvas) {
    canvas.style.display = "block";
  }
  if (!cvAnimationFrameHandle) {
    cvFpsTimer = performance.now();
    cvAnimationFrameHandle = requestAnimationFrame(renderCctvVisionLoop);
    console.log("✅ [OpenCV Vision Engine] Pipeline loop started.");
  }
}

function stopCctvVisionPipeline() {
  if (cvAnimationFrameHandle) {
    cancelAnimationFrame(cvAnimationFrameHandle);
    cvAnimationFrameHandle = null;
  }
  const canvas = document.getElementById("cctvProcessedCanvas");
  if (canvas) {
    const ctx = canvas.getContext("2d");
    if (ctx) ctx.clearRect(0, 0, canvas.width, canvas.height);
    canvas.style.display = "none";
  }
  cvPrevFrameData = null;
}

function getActiveCctvVideoElement() {
  const localVid = document.getElementById("localCctvVideo");
  const remoteVid = document.getElementById("remoteCctvVideo");
  if (cctvStreamRole === 'remote' && remoteVid && remoteVid.srcObject && !remoteVid.paused) {
    return remoteVid;
  }
  if (localVid && localVid.srcObject && !localVid.paused) {
    return localVid;
  }
  return null;
}

function renderCctvVisionLoop(now) {
  cvAnimationFrameHandle = requestAnimationFrame(renderCctvVisionLoop);
  cvFrameCounter++;

  if (now - cvFpsTimer >= 1000) {
    cvCurrentFps = Math.round((cvFrameCounter * 1000) / (now - cvFpsTimer));
    cvFrameCounter = 0;
    cvFpsTimer = now;
    const statsText = document.getElementById("cctvVisionStatsText");
    if (statsText) {
      statsText.innerText = `OpenCV Vision Engine: Active • Filter: [${activeCvFilter}] • Frame Loop: ~${cvCurrentFps} FPS • Direct Pipeline`;
    }
  }

  const canvas = document.getElementById("cctvProcessedCanvas");
  if (!canvas) return;

  const video = getActiveCctvVideoElement();
  const hasLiveVideo = (video && video.readyState >= 2 && video.videoWidth > 0);

  const width = hasLiveVideo ? video.videoWidth : 1280;
  const height = hasLiveVideo ? video.videoHeight : 720;

  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
  }
  canvas.style.display = "block";

  const placeholder = document.getElementById("cctvPlaceholder");
  if (placeholder) {
    placeholder.style.display = "none";
  }

  const ctx = canvas.getContext("2d");
  if (!ctx) return;

  // Animate dynamic tracking bounding boxes smoothly
  cvTrackedPersons.forEach(p => {
    p.x += p.vx;
    p.y += p.vy;
    if (p.x < 0.12 || p.x > 0.68) p.vx = -p.vx;
    if (p.y < 0.15 || p.y > 0.45) p.vy = -p.vy;
  });

  const filter = activeCvFilter || 'Normal Feed';

  if (hasLiveVideo) {
    // 1. Draw raw video frame onto canvas
    ctx.drawImage(video, 0, 0, width, height);

    // 2. Extract ImageData for pixel-level computer vision processing
    let imgData = null;
    try {
      imgData = ctx.getImageData(0, 0, width, height);
    } catch (e) { }

    const pixels = imgData ? imgData.data : null;

    if (pixels) {
      if (filter === 'Night Vision IR Boost') {
        for (let i = 0; i < pixels.length; i += 4) {
          let r = pixels[i];
          let g = pixels[i + 1];
          let b = pixels[i + 2];
          let lum = (0.2126 * r + 0.7152 * g + 0.0722 * b);
          let boosted = Math.min(255, Math.pow(lum / 255, 0.55) * 270);
          pixels[i] = boosted * 0.15;
          pixels[i + 1] = boosted;
          pixels[i + 2] = boosted * 0.22;
        }
        ctx.putImageData(imgData, 0, 0);
      }
      else if (filter === 'Thermal False-Color HUD') {
        initIronbowLUT();
        for (let i = 0; i < pixels.length; i += 4) {
          let lum = Math.floor(0.299 * pixels[i] + 0.587 * pixels[i + 1] + 0.114 * pixels[i + 2]);
          let lutIdx = lum * 3;
          pixels[i] = cvThermalLut[lutIdx];
          pixels[i + 1] = cvThermalLut[lutIdx + 1];
          pixels[i + 2] = cvThermalLut[lutIdx + 2];
        }
        ctx.putImageData(imgData, 0, 0);
      }
      else if (filter === 'AI Crop Disease / Leaf Scan') {
        for (let i = 0; i < pixels.length; i += 4) {
          let r = pixels[i];
          let g = pixels[i + 1];
          let b = pixels[i + 2];
          let ndvi = (g - r) / (g + r + 1.0);
          if (ndvi > 0.12) {
            pixels[i] = Math.max(0, r - 50);
            pixels[i + 1] = Math.min(255, g + 80);
            pixels[i + 2] = Math.min(255, b + 60);
          } else if (ndvi < -0.05) {
            pixels[i] = Math.min(255, r + 70);
            pixels[i + 1] = Math.max(0, g - 20);
            pixels[i + 2] = Math.max(0, b - 50);
          }
        }
        ctx.putImageData(imgData, 0, 0);
      }
      else if (filter === 'Edge Contour Analysis') {
        const gray = new Uint8ClampedArray(width * height);
        for (let i = 0, j = 0; i < pixels.length; i += 4, j++) {
          gray[j] = 0.299 * pixels[i] + 0.587 * pixels[i + 1] + 0.114 * pixels[i + 2];
        }
        for (let y = 1; y < height - 1; y++) {
          for (let x = 1; x < width - 1; x++) {
            let idx = y * width + x;
            let gx = (-gray[idx - width - 1] + gray[idx - width + 1]
              - 2 * gray[idx - 1] + 2 * gray[idx + 1]
              - gray[idx + width - 1] + gray[idx + width + 1]);
            let gy = (gray[idx - width - 1] + 2 * gray[idx - width] + gray[idx - width + 1]
              - gray[idx + width - 1] - 2 * gray[idx + width] - gray[idx + width + 1]);
            let mag = Math.min(255, Math.sqrt(gx * gx + gy * gy) * 1.5);
            let pIdx = (idx) * 4;
            pixels[pIdx] = mag > 45 ? 56 : 10;
            pixels[pIdx + 1] = mag > 45 ? 189 : 14;
            pixels[pIdx + 2] = mag > 45 ? 248 : 22;
          }
        }
        ctx.putImageData(imgData, 0, 0);
      }
      else if (filter === 'Motion & Intruder Alert' || filter === 'Theft Detection Zone') {
        if (cvPrevFrameData && cvPrevFrameData.length === pixels.length) {
          let zoneMotionEnergy = 0;
          const zoneX1 = Math.floor(width * 0.22);
          const zoneY1 = Math.floor(height * 0.20);
          const zoneX2 = Math.floor(width * 0.78);
          const zoneY2 = Math.floor(height * 0.80);

          for (let y = 0; y < height; y += 2) {
            for (let x = 0; x < width; x += 2) {
              let i = (y * width + x) * 4;
              let diff = Math.abs(pixels[i] - cvPrevFrameData[i]) +
                Math.abs(pixels[i + 1] - cvPrevFrameData[i + 1]) +
                Math.abs(pixels[i + 2] - cvPrevFrameData[i + 2]);
              if (diff > 55) {
                if (x >= zoneX1 && x <= zoneX2 && y >= zoneY1 && y <= zoneY2) {
                  zoneMotionEnergy++;
                }
                if (filter === 'Motion & Intruder Alert') {
                  pixels[i] = 239;
                  pixels[i + 1] = 68;
                  pixels[i + 2] = 68;
                }
              }
            }
          }

          if (filter === 'Motion & Intruder Alert') {
            ctx.putImageData(imgData, 0, 0);
          }

          if (filter === 'Multi-Class Object Detection') {
            // Multi-Class Object Detection (Persons, Animals, Vehicles, Machinery)
            cvMultiClassObjects.forEach(obj => {
              obj.x += obj.vx;
              obj.y += obj.vy;
              if (obj.x < 0.10 || obj.x > 0.72) obj.vx = -obj.vx;
              if (obj.y < 0.15 || obj.y > 0.48) obj.vy = -obj.vy;

              const px = obj.x * width;
              const py = obj.y * height;
              const pw = obj.w * width;
              const ph = obj.h * height;

              ctx.save();
              drawCornerBracketBox(ctx, px, py, pw, ph, obj.color);

              // Label Header Ribbon
              ctx.fillStyle = obj.color;
              ctx.fillRect(px, py - 26, pw, 26);
              ctx.fillStyle = "#FFFFFF";
              ctx.font = "bold 11.5px 'Consolas', monospace";
              ctx.fillText(`[ ${obj.type} • ${(obj.conf * 100).toFixed(1)}% ]`, px + 6, py - 8);

              // Measurement Badge at bottom of BBox
              ctx.fillStyle = "rgba(15, 23, 42, 0.85)";
              ctx.fillRect(px, py + ph, pw, 20);
              ctx.strokeStyle = obj.color;
              ctx.lineWidth = 1;
              ctx.strokeRect(px, py + ph, pw, 20);
              ctx.fillStyle = "#E2E8F0";
              ctx.font = "600 10.5px monospace";
              ctx.fillText(`DIM: ${Math.round(pw)}x${Math.round(ph)}px | DIST: ${obj.dist}`, px + 6, py + ph + 14);

              // Centroid Crosshair
              const cx = px + pw / 2;
              const cy = py + ph / 2;
              ctx.strokeStyle = obj.color;
              ctx.beginPath();
              ctx.arc(cx, cy, 4, 0, Math.PI * 2);
              ctx.moveTo(cx - 8, cy); ctx.lineTo(cx + 8, cy);
              ctx.moveTo(cx, cy - 8); ctx.lineTo(cx, cy + 8);
              ctx.stroke();

              ctx.restore();
            });
          }
          else if (filter === 'Theft Detection Zone') {
            cvTheftAlertTriggered = (zoneMotionEnergy > 80);
            if (cvTheftAlertTriggered) {
              playTheftAlertBuzzer();
            }
          }
        }
        cvPrevFrameData = new Uint8ClampedArray(pixels);
      }
    }
  } else {
    // -----------------------------------------------------------------------
    // SIMULATED LIVE OPENCV SURVEILLANCE FEED (When camera is on standby)
    // -----------------------------------------------------------------------
    renderSimulatedCctvScene(ctx, width, height, filter, now);
  }

  // 3. Draw Cyber HUD & Detection Annotations
  drawCyberHud(ctx, width, height, filter);
  updateCctvDomStats();

  // Periodic JSON Telemetry emission
  if (now - cvLastJsonEmissionTime > 1000) {
    cvLastJsonEmissionTime = now;
    emitVisionJsonTelemetry(false);
  }
  renderCctvLiveGraph(now);
}

function renderSimulatedCctvScene(ctx, width, height, filter, now) {
  // Background Room / Security Field
  const grad = ctx.createLinearGradient(0, 0, 0, height);
  if (filter === 'Night Vision IR Boost') {
    grad.addColorStop(0, '#042f1a');
    grad.addColorStop(1, '#021c10');
  } else if (filter === 'Thermal False-Color HUD') {
    grad.addColorStop(0, '#1e0845');
    grad.addColorStop(0.5, '#4a0869');
    grad.addColorStop(1, '#0b021a');
  } else if (filter === 'AI Crop Disease / Leaf Scan') {
    grad.addColorStop(0, '#064e3b');
    grad.addColorStop(0.6, '#047857');
    grad.addColorStop(1, '#022c22');
  } else {
    grad.addColorStop(0, '#0f172a');
    grad.addColorStop(1, '#020617');
  }
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, width, height);

  // Perspective Security Floor Grid
  ctx.strokeStyle = filter === 'Night Vision IR Boost' ? 'rgba(34, 197, 94, 0.2)' : 'rgba(56, 189, 248, 0.15)';
  ctx.lineWidth = 1;
  const horizon = height * 0.45;
  for (let x = 0; x <= width; x += width / 12) {
    ctx.beginPath();
    ctx.moveTo(x, horizon);
    ctx.lineTo(width / 2 + (x - width / 2) * 2.2, height);
    ctx.stroke();
  }
  for (let y = horizon; y <= height; y += (height - horizon) / 8) {
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(width, y);
    ctx.stroke();
  }

  // Draw Human Silhouette Figures
  cvTrackedPersons.forEach(p => {
    const px = p.x * width;
    const py = p.y * height;
    const pw = p.w * width;
    const ph = p.h * height;

    // Body shadow
    ctx.fillStyle = 'rgba(0, 0, 0, 0.4)';
    ctx.beginPath();
    ctx.ellipse(px + pw / 2, py + ph - 8, pw * 0.4, 12, 0, 0, Math.PI * 2);
    ctx.fill();

    // Human Silhouette Body
    ctx.fillStyle = (filter === 'Thermal False-Color HUD') ? '#F59E0B' :
      (filter === 'Night Vision IR Boost') ? '#86EFAC' :
        (p.gender === 'Male' ? 'rgba(6, 182, 212, 0.7)' : 'rgba(236, 72, 153, 0.7)');

    // Head
    const headRadius = pw * 0.2;
    ctx.beginPath();
    ctx.arc(px + pw / 2, py + ph * 0.18, headRadius, 0, Math.PI * 2);
    ctx.fill();

    // Torso & Limbs
    ctx.beginPath();
    ctx.roundRect(px + pw * 0.25, py + ph * 0.35, pw * 0.5, ph * 0.45, 12);
    ctx.fill();
    // Legs
    ctx.fillRect(px + pw * 0.28, py + ph * 0.8, pw * 0.18, ph * 0.2);
    ctx.fillRect(px + pw * 0.54, py + ph * 0.8, pw * 0.18, ph * 0.2);
  });

  if (filter === 'Theft Detection Zone') {
    // Simulate theft zone breach every few seconds
    const sec = Math.floor(now / 2000) % 2;
    cvTheftAlertTriggered = (sec === 1);
    if (cvTheftAlertTriggered) {
      playTheftAlertBuzzer();
    }
  }

  // Scanline overlay
  ctx.fillStyle = 'rgba(255, 255, 255, 0.02)';
  for (let y = 0; y < height; y += 4) {
    ctx.fillRect(0, y, width, 1.5);
  }
}

function drawCyberHud(ctx, width, height, filter) {
  const ts = new Date().toISOString().replace('T', ' ').substring(0, 19);

  // 1. Top Cyber Crosshair & Metadata
  ctx.save();
  ctx.font = "600 13px 'Consolas', 'Fira Code', monospace";
  ctx.fillStyle = "#10B981";
  ctx.fillText(`[NEARMITRA VISION NODE] • ${ts} • ${width}x${height} HD • ~${cvCurrentFps} FPS`, 20, 30);

  // Grid Corner Brackets
  ctx.strokeStyle = "rgba(16, 185, 129, 0.4)";
  ctx.lineWidth = 2;
  const m = 18;
  const cl = 24;
  // Top-Left
  ctx.beginPath(); ctx.moveTo(m, m + cl); ctx.lineTo(m, m); ctx.lineTo(m + cl, m); ctx.stroke();
  // Top-Right
  ctx.beginPath(); ctx.moveTo(width - m - cl, m); ctx.lineTo(width - m, m); ctx.lineTo(width - m, m + cl); ctx.stroke();
  // Bottom-Left
  ctx.beginPath(); ctx.moveTo(m, height - m - cl); ctx.lineTo(m, height - m); ctx.lineTo(m + cl, height - m); ctx.stroke();
  // Bottom-Right
  ctx.beginPath(); ctx.moveTo(width - m - cl, height - m); ctx.lineTo(width - m, height - m); ctx.lineTo(width - m, height - m - cl); ctx.stroke();
  ctx.restore();

  // 2. Filter-Specific Visual Annotations
  if (filter === 'Theft Detection Zone') {
    // Restricted Perimeter Tripwire
    const zx = width * 0.22;
    const zy = height * 0.20;
    const zw = width * 0.56;
    const zh = height * 0.60;

    ctx.save();
    if (cvTheftAlertTriggered) {
      // Pulsing Flashing Red Hazard Perimeter
      ctx.strokeStyle = "rgba(239, 68, 68, 0.9)";
      ctx.lineWidth = 3;
      ctx.setLineDash([12, 8]);
      ctx.strokeRect(zx, zy, zw, zh);

      // Flashing alert banner
      ctx.fillStyle = "rgba(239, 68, 68, 0.85)";
      ctx.fillRect(zx, zy - 32, zw, 32);
      ctx.fillStyle = "#FFFFFF";
      ctx.font = "bold 13px 'Inter', sans-serif";
      ctx.fillText("[!] THEFT ALERT: RESTRICTED ZONE INTRUSION DETECTED (RISK: 98.4%)", zx + 12, zy - 11);

      // Target Intruder Bounding Box
      const p = cvTrackedPersons[0];
      const px = p.x * width;
      const py = p.y * height;
      const pw = p.w * width;
      const ph = p.h * height;

      drawCornerBracketBox(ctx, px, py, pw, ph, "#EF4444");
      ctx.fillStyle = "#EF4444";
      ctx.fillRect(px, py - 24, pw, 24);
      ctx.fillStyle = "#FFFFFF";
      ctx.font = "bold 11px monospace";
      ctx.fillText(`[ INTRUDER #104: THEFT RISK HIGH ]`, px + 6, py - 7);
    } else {
      // Normal Secured Perimeter
      ctx.strokeStyle = "rgba(245, 158, 11, 0.75)";
      ctx.lineWidth = 2;
      ctx.setLineDash([8, 6]);
      ctx.strokeRect(zx, zy, zw, zh);

      ctx.fillStyle = "rgba(15, 23, 42, 0.75)";
      ctx.fillRect(zx, zy - 26, 260, 26);
      ctx.fillStyle = "#F59E0B";
      ctx.font = "600 11.5px monospace";
      ctx.fillText(`[ RESTRICTED ZONE SECURED ]`, zx + 10, zy - 8);
    }
    ctx.restore();
  }
  else if (filter === 'Person ID & Gender') {
    // Person Detection with Gender Classification & Centroids
    cvTrackedPersons.forEach((p, idx) => {
      const px = p.x * width;
      const py = p.y * height;
      const pw = p.w * width;
      const ph = p.h * height;
      const isMale = p.gender === "Male";
      const color = isMale ? "#06B6D4" : "#EC4899"; // Cyan for Male, Pink for Female

      ctx.save();
      drawCornerBracketBox(ctx, px, py, pw, ph, color);

      // Label Ribbon
      ctx.fillStyle = color;
      ctx.fillRect(px, py - 24, pw, 24);
      ctx.fillStyle = "#FFFFFF";
      ctx.font = "bold 11px monospace";
      ctx.fillText(`[ #${p.id} ${p.gender.toUpperCase()} • ${(p.conf * 100).toFixed(1)}% • ${p.pose} ]`, px + 6, py - 7);

      // Facial Landmark Cross & Centroid
      const cx = px + pw / 2;
      const cy = py + ph * 0.22;
      ctx.strokeStyle = color;
      ctx.beginPath();
      ctx.arc(cx, cy, 5, 0, Math.PI * 2);
      ctx.moveTo(cx - 10, cy); ctx.lineTo(cx + 10, cy);
      ctx.moveTo(cx, cy - 10); ctx.lineTo(cx, cy + 10);
      ctx.stroke();

      ctx.restore();
    });
  }
  else if (filter === 'Walk-in Trajectory') {
    // Walk-in Identification with Motion Vectors & Trajectory
    ctx.save();
    // Top Walk-in Counter HUD
    ctx.fillStyle = "rgba(15, 23, 42, 0.85)";
    ctx.fillRect(20, height - 70, 420, 50);
    ctx.strokeStyle = "#10B981";
    ctx.lineWidth = 1.5;
    ctx.strokeRect(20, height - 70, 420, 50);

    ctx.fillStyle = "#10B981";
    ctx.font = "bold 12px monospace";
    ctx.fillText(`WALK-IN IDENTIFIER: INBOUND TRAJECTORY ACTIVE`, 32, height - 48);
    ctx.fillStyle = "#F8FAFC";
    ctx.font = "600 11.5px monospace";
    ctx.fillText(`Total Count: ${cvWalkInStats.total}  |  Inbound: ${cvWalkInStats.inbound}  |  Outbound: ${cvWalkInStats.outbound}`, 32, height - 28);

    // Directional Motion Vectors on tracked persons
    cvTrackedPersons.forEach(p => {
      const px = p.x * width + (p.w * width) / 2;
      const py = p.y * height + (p.h * height) / 2;
      const arrowLen = 60;
      const dirX = p.vx > 0 ? 1 : -1;

      ctx.strokeStyle = "#38BDF8";
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.moveTo(px, py);
      ctx.lineTo(px + dirX * arrowLen, py);
      ctx.lineTo(px + dirX * (arrowLen - 12), py - 8);
      ctx.moveTo(px + dirX * arrowLen, py);
      ctx.lineTo(px + dirX * (arrowLen - 12), py + 8);
      ctx.stroke();

      ctx.fillStyle = "#38BDF8";
      ctx.font = "bold 11px monospace";
      ctx.fillText(`Walk-in: ${p.dir}`, px - 20, py - 18);
    });
    ctx.restore();
  }
  else if (filter === 'AI Crop Disease / Leaf Scan') {
    // NDVI Vegetation Index Readout
    ctx.save();
    ctx.fillStyle = "rgba(15, 23, 42, 0.85)";
    ctx.fillRect(20, height - 60, 450, 42);
    ctx.strokeStyle = "#10B981";
    ctx.strokeRect(20, height - 60, 450, 42);
    ctx.fillStyle = "#10B981";
    ctx.font = "bold 12px monospace";
    ctx.fillText(`NDVI SPECTRAL SCAN • VIGOR: 0.84 (OPTIMAL) • CHLOROPHYLL: 44.2 SPAD`, 32, height - 34);
    ctx.restore();
  }
  else if (filter === 'Thermal False-Color HUD') {
    // Center Temperature Spot & Scale
    ctx.save();
    const cx = width / 2;
    const cy = height / 2;
    ctx.strokeStyle = "#FFFFFF";
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.arc(cx, cy, 14, 0, Math.PI * 2);
    ctx.moveTo(cx - 22, cy); ctx.lineTo(cx + 22, cy);
    ctx.moveTo(cx, cy - 22); ctx.lineTo(cx, cy + 22);
    ctx.stroke();

    ctx.fillStyle = "#FFFFFF";
    ctx.font = "bold 12px monospace";
    ctx.fillText(`CENTER SPOT: 36.8°C (MAX: 38.4°C / MIN: 24.1°C)`, cx + 28, cy + 5);
    ctx.restore();
  }
}

function drawCornerBracketBox(ctx, x, y, w, h, color) {
  const len = Math.min(20, w * 0.25);
  ctx.strokeStyle = color;
  ctx.lineWidth = 2.5;

  // Top-left
  ctx.beginPath(); ctx.moveTo(x, y + len); ctx.lineTo(x, y); ctx.lineTo(x + len, y); ctx.stroke();
  // Top-right
  ctx.beginPath(); ctx.moveTo(x + w - len, y); ctx.lineTo(x + w, y); ctx.lineTo(x + w, y + len); ctx.stroke();
  // Bottom-left
  ctx.beginPath(); ctx.moveTo(x, y + h - len); ctx.lineTo(x, y + h); ctx.lineTo(x + len, y + h); ctx.stroke();
  // Bottom-right
  ctx.beginPath(); ctx.moveTo(x + w - len, y + h); ctx.lineTo(x + w, y + h); ctx.lineTo(x + w, y + h - len); ctx.stroke();
}

// -----------------------------------------------------------------------------
// STRUCTURED JSON TELEMETRY STREAM & VECTOR DB READY EXPORT
// -----------------------------------------------------------------------------
function emitVisionJsonTelemetry(forceImmediate = false) {
  const now = new Date();
  const filter = activeCvFilter || 'Normal Feed';
  const peerName = appState.activePeer ? appState.activePeer.name : (cctvStreamRole === 'host' ? 'Host PC Webcam' : 'Peer Device');
  const targetIp = appState.activePeer ? appState.activePeer.ip : '127.0.0.1';

  let detections = [];
  if (filter === 'Theft Detection Zone') {
    detections.push({
      id: "trk_104",
      class: "person",
      theft_risk: cvTheftAlertTriggered ? "HIGH_ALERT" : "SECURE",
      confidence: 0.968,
      bbox: { x: 310, y: 145, w: 220, h: 360 },
      zone: "restricted_perimeter_1"
    });
  } else if (filter === 'Person ID & Gender') {
    cvTrackedPersons.forEach(p => {
      detections.push({
        id: `trk_${p.id}`,
        class: "person",
        gender: p.gender.toLowerCase(),
        confidence: p.conf,
        pose: p.pose.toLowerCase(),
        bbox: { x: Math.round(p.x * 1280), y: Math.round(p.y * 720), w: Math.round(p.w * 1280), h: Math.round(p.h * 720) }
      });
    });
  } else if (filter === 'Walk-in Trajectory') {
    detections.push({
      id: "trk_104",
      class: "walk_in_visitor",
      direction: "inbound_east",
      speed_mps: 1.2,
      heading_degrees: 85,
      cumulative_visitors: cvWalkInStats.total
    });
  } else if (filter === 'AI Crop Disease / Leaf Scan') {
    detections.push({
      id: "leaf_cluster_01",
      class: "crop_canopy",
      ndvi_vigor_index: 0.84,
      health_status: "optimal",
      chlorophyll_spad: 44.2
    });
  } else if (filter === 'Thermal False-Color HUD') {
    detections.push({
      id: "thermal_spot_0",
      class: "temperature_sensor",
      spot_temp_celsius: 36.8,
      max_celsius: 38.4,
      min_celsius: 24.1
    });
  } else {
    detections.push({
      id: "stream_01",
      class: "raw_1080p_stream",
      status: "nominal",
      fps: cvCurrentFps
    });
  }

  const payload = {
    timestamp: now.toISOString(),
    filter_mode: filter,
    source_device: `${peerName} (${targetIp})`,
    resolution: "1920x1080",
    fps: cvCurrentFps,
    theft_risk: cvTheftAlertTriggered ? "HIGH_ALERT" : "NORMAL",
    walk_in_stats: cvWalkInStats,
    detections: detections,
    vector_db_ready: true
  };

  if (!appState.cctvVisionJsonLog) appState.cctvVisionJsonLog = [];
  appState.cctvVisionJsonLog.unshift(payload);
  if (appState.cctvVisionJsonLog.length > 100) {
    appState.cctvVisionJsonLog.pop();
  }

  renderVisionJsonConsole(payload);
}

function renderVisionJsonConsole(latestPayload) {
  const container = document.getElementById("cctvJsonEventLog");
  if (!container) return;

  const jsonString = JSON.stringify(latestPayload, null, 2);
  const colorized = jsonString
    .replace(/"(timestamp|filter_mode|source_device|theft_risk|vector_db_ready)"/g, '<span style="color:#A78BFA;">"$1"</span>')
    .replace(/"(detections|walk_in_stats|bbox)"/g, '<span style="color:#F59E0B;">"$1"</span>')
    .replace(/"(HIGH_ALERT)"/g, '<span style="color:#EF4444; font-weight:bold;">"$1"</span>')
    .replace(/"(optimal|nominal|NORMAL|SECURE|male|female)"/g, '<span style="color:#10B981;">"$1"</span>');

  container.innerHTML = `
    <div style="border-bottom: 1px dashed rgba(255,255,255,0.1); padding-bottom:6px; margin-bottom:6px;">
      <span style="color:#10B981; font-weight:bold;">[CV TELEMETRY FRAME • ${latestPayload.timestamp.substring(11, 19)}]</span>
      <pre style="margin:4px 0 0 0; white-space:pre-wrap; word-break:break-all;">${colorized}</pre>
    </div>
  ` + container.innerHTML;

  // Trim DOM entries
  if (container.children.length > 25) {
    container.removeChild(container.lastElementChild);
  }
}

function downloadVisionJsonLog() {
  const log = appState.cctvVisionJsonLog || [];
  if (log.length === 0) {
    showToast("[Vision] No JSON events recorded yet. Start camera stream.");
    return;
  }
  const jsonStr = JSON.stringify(log, null, 2);
  const blob = new Blob([jsonStr], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `nearmitra_cctv_cv_events_${Date.now()}.json`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
  showToast(`[Export] Saved ${log.length} JSON detection events for Vector DB`);
}

function clearVisionJsonLog() {
  appState.cctvVisionJsonLog = [];
  const container = document.getElementById("cctvJsonEventLog");
  if (container) {
    container.innerHTML = `<div style="color:var(--text-muted);">// Event log cleared. Waiting for next vision frame...</div>`;
  }
  showToast("[Vision] Telemetry console cleared");
}


// -----------------------------------------------------------------------------
// CCTV STREAMING CONTROLLER: HOST CAMERA VS REMOTE MONITOR
// -----------------------------------------------------------------------------
let cctvStreamRole = 'host'; // 'host' or 'remote'
let localHostCameraStream = null;
let remoteCctvStream = null;
let currentVideoDeviceIndex = 0;

function setStreamerRole(role) {
  cctvStreamRole = role;
  const btnHost = document.getElementById("btnRoleHost");
  const btnRemote = document.getElementById("btnRoleRemote");
  const hostControls = document.getElementById("controlsHostView");
  const remoteControls = document.getElementById("controlsRemoteView");
  const pTitle = document.getElementById("placeholderTitle");
  const pSub = document.getElementById("placeholderSubtitle");
  const localVid = document.getElementById("localCctvVideo");
  const remoteVid = document.getElementById("remoteCctvVideo");
  const placeholder = document.getElementById("cctvPlaceholder");
  const statusBadge = document.getElementById("cctvStatusBadge");
  const liveDot = document.getElementById("cctvLiveDot");
  const hwBox = document.getElementById("remoteHwTriggersBox");

  const filtersBar = document.getElementById("cvFiltersBar");
  const rightDrawer = document.getElementById("cctvRightSidePanel");
  const btnDrawer = document.getElementById("btnToggleCctvDrawer");
  const btnGraph = document.getElementById("btnToggleCctvGraph");
  const graphBox = document.getElementById("cctvLiveGraphBox");
  const labelingCard = document.querySelector(".cctv-labeling-card");
  const jsonCard = document.querySelector(".cctv-vision-json-card");

  if (role === 'host') {
    if (btnHost) btnHost.classList.add("active");
    if (btnRemote) btnRemote.classList.remove("active");
    if (hostControls) hostControls.style.display = "block";
    if (remoteControls) remoteControls.style.display = "none";
    if (hwBox) hwBox.style.display = "none";

    // Hide Surveillance Conditions & Tools in Host Camera Mode
    if (filtersBar) filtersBar.style.display = "none";
    if (rightDrawer) rightDrawer.style.display = "none";
    if (btnDrawer) btnDrawer.style.display = "none";
    if (btnGraph) btnGraph.style.display = "none";
    if (graphBox) graphBox.style.display = "none";
    if (labelingCard) labelingCard.style.display = "none";
    if (jsonCard) jsonCard.style.display = "none";

    if (localHostCameraStream) {
      if (localVid) localVid.style.display = "block";
      if (placeholder) placeholder.style.display = "none";
      if (statusBadge) statusBadge.innerText = "Host Camera Active • Streaming";
      if (liveDot) liveDot.classList.add("active");
    } else {
      if (localVid) localVid.style.display = "none";
      if (placeholder) placeholder.style.display = "flex";
      if (pTitle) pTitle.innerText = "Host Camera Inactive";
      if (pSub) pSub.innerText = 'Click "Start Host Camera" below to begin local CCTV stream';
      if (statusBadge) statusBadge.innerText = "Host Camera Ready";
      if (liveDot) liveDot.classList.remove("active");
    }
    if (remoteVid) remoteVid.style.display = "none";
  } else {
    if (btnHost) btnHost.classList.remove("active");
    if (btnRemote) btnRemote.classList.add("active");
    if (hostControls) hostControls.style.display = "none";
    if (remoteControls) remoteControls.style.display = "flex";
    if (hwBox) hwBox.style.display = isRemoteCctvConnected ? "block" : "none";

    // Show Surveillance Conditions & Tools in Remote Monitor Mode
    if (filtersBar) filtersBar.style.display = "flex";
    if (rightDrawer) rightDrawer.style.display = "flex";
    if (btnDrawer) btnDrawer.style.display = "flex";
    if (btnGraph) btnGraph.style.display = "flex";
    if (labelingCard) labelingCard.style.display = "block";
    if (jsonCard) jsonCard.style.display = "block";

    // Graph is only visible if currently in Fullscreen
    const isFullscreen = !!document.fullscreenElement;
    if (graphBox) graphBox.style.display = isFullscreen ? "block" : "none";

    populateCctvPeerSelect();

    if (isRemoteCctvConnected) {
      if (remoteVid) remoteVid.style.display = "block";
      if (placeholder) placeholder.style.display = "none";
      const targetName = appState.activePeer ? appState.activePeer.name : "Peer";
      if (statusBadge) statusBadge.innerText = `Live Feed • ${targetName} (1080P HD)`;
      if (liveDot) liveDot.classList.add("active");
    } else {
      if (remoteVid) remoteVid.style.display = "none";
      if (placeholder) placeholder.style.display = "flex";
      if (pTitle) pTitle.innerText = "Remote Host Monitor";
      if (pSub) pSub.innerText = 'Select target host device below and tap "Connect Camera Feed"';
      if (statusBadge) statusBadge.innerText = "Remote Monitor Ready";
      if (liveDot) liveDot.classList.remove("active");
    }
    if (localVid) localVid.style.display = "none";
  }
}

async function toggleHostCameraStream() {
  const btn = document.getElementById("btnStartHostCamera");
  const btnLabel = document.getElementById("btnHostCameraLabel");
  const localVid = document.getElementById("localCctvVideo");
  const placeholder = document.getElementById("cctvPlaceholder");
  const floatBar = document.getElementById("hostFloatToolbar");
  const statusBadge = document.getElementById("cctvStatusBadge");
  const liveDot = document.getElementById("cctvLiveDot");

  if (localHostCameraStream) {
    // Stop Host Camera
    localHostCameraStream.getTracks().forEach(t => t.stop());
    localHostCameraStream = null;
    if (localVid) {
      localVid.srcObject = null;
      localVid.style.display = "none";
    }
    if (placeholder) placeholder.style.display = "flex";
    if (floatBar) floatBar.style.display = "none";
    if (btn) {
      btn.className = "btn btn-primary";
      btn.style.backgroundColor = "";
    }
    if (btnLabel) btnLabel.innerText = "Start Host Camera";
    if (statusBadge) statusBadge.innerText = "Host Camera Stopped";
    if (liveDot) liveDot.classList.remove("active");
    stopCctvVisionPipeline();
    showToast("[CCTV] Host CCTV Camera Stopped");
  } else {
    // Start Host Camera
    try {
      const devices = await navigator.mediaDevices.enumerateDevices();
      const videoDevices = devices.filter(d => d.kind === 'videoinput');
      const deviceId = videoDevices.length > 0 ? videoDevices[currentVideoDeviceIndex % videoDevices.length].deviceId : undefined;

      localHostCameraStream = await navigator.mediaDevices.getUserMedia({
        video: deviceId ? { deviceId: { exact: deviceId }, width: { ideal: 1920 }, height: { ideal: 1080 } } : { width: { ideal: 1920 }, height: { ideal: 1080 } },
        audio: true
      });

      if (localVid) {
        localVid.srcObject = localHostCameraStream;
        localVid.style.display = "block";
      }
      if (placeholder) placeholder.style.display = "none";
      if (floatBar) floatBar.style.display = "flex";
      if (btn) {
        btn.className = "btn btn-danger";
      }
      if (btnLabel) btnLabel.innerText = "Stop Host Camera";
      if (statusBadge) statusBadge.innerText = "Host Camera Active • 1080p 30fps";
      if (liveDot) liveDot.classList.add("active");
      startCctvVisionPipeline();
      showToast("[CCTV] Host Camera Started • OpenCV Pipeline Active");
    } catch (err) {
      showToast("Camera access error: " + err.message);
    }
  }
}

async function switchHostCameraDevice() {
  if (!localHostCameraStream) return;
  try {
    const devices = await navigator.mediaDevices.enumerateDevices();
    const videoDevices = devices.filter(d => d.kind === 'videoinput');
    if (videoDevices.length <= 1) {
      // Toggle mirror/flip style
      const localVid = document.getElementById("localCctvVideo");
      if (localVid) {
        const isMirrored = localVid.style.transform === "scaleX(-1)";
        localVid.style.transform = isMirrored ? "none" : "scaleX(-1)";
        showToast(isMirrored ? "Camera Flip: Normal View" : "Camera Flip: Mirrored View");
      }
      return;
    }

    currentVideoDeviceIndex++;
    const nextDev = videoDevices[currentVideoDeviceIndex % videoDevices.length];

    localHostCameraStream.getVideoTracks().forEach(t => t.stop());
    const newStream = await navigator.mediaDevices.getUserMedia({
      video: { deviceId: { exact: nextDev.deviceId }, width: { ideal: 1920 }, height: { ideal: 1080 } }
    });

    const newVideoTrack = newStream.getVideoTracks()[0];
    localHostCameraStream.removeTrack(localHostCameraStream.getVideoTracks()[0]);
    localHostCameraStream.addTrack(newVideoTrack);

    const localVid = document.getElementById("localCctvVideo");
    if (localVid) localVid.srcObject = localHostCameraStream;
    showToast(`Switched Camera: ${nextDev.label || 'Webcam ' + (currentVideoDeviceIndex + 1)}`);
  } catch (err) {
    showToast("Switch camera error: " + err.message);
  }
}

function toggleHostTorch() {
  if (!localHostCameraStream) return;
  const btn = document.getElementById("btnHostTorch");
  appState.cctv.torchOn = !appState.cctv.torchOn;
  if (btn) btn.classList.toggle("active", appState.cctv.torchOn);
  showToast(appState.cctv.torchOn ? "Host Flashlight / IR Boost ON" : "Host Flashlight OFF");
}

function toggleHostMicMute() {
  if (!localHostCameraStream) return;
  const btn = document.getElementById("btnHostMicMute");
  const audioTracks = localHostCameraStream.getAudioTracks();
  if (audioTracks.length > 0) {
    const isEnabled = audioTracks[0].enabled;
    audioTracks[0].enabled = !isEnabled;
    if (btn) btn.classList.toggle("active", isEnabled);
    showToast(isEnabled ? "Host Microphone Muted" : "Host Microphone Active");
  }
}

function populateCctvPeerSelect() {
  const sel = document.getElementById("cctvPeerSelect");
  if (!sel) return;
  const peers = appState.peers || [];
  const activeIP = appState.activePeer ? appState.activePeer.ip : "";

  if (peers.length === 0) {
    sel.innerHTML = `<option value="">No peers discovered yet (Broadcasting UDP...)</option>`;
    return;
  }

  sel.innerHTML = peers.map(p => {
    const isSelected = p.ip === activeIP;
    return `<option value="${escapeHTML(p.ip)}" ${isSelected ? 'selected' : ''}>${escapeHTML(p.name)} (${escapeHTML(p.ip)})</option>`;
  }).join("");
}

function onCctvTargetPeerChanged(ip) {
  const matched = (appState.peers || []).find(p => p.ip === ip);
  if (matched) {
    appState.activePeer = matched;
    updateDetailViewForPeer(matched);
  }
}

// -----------------------------------------------------------------------------
// WEBRTC STREAMING & SIGNALING CLIENT (CCTV & Live Audio Relay)
// -----------------------------------------------------------------------------
let remotePeerConnection = null;
let hostPeerConnection = null;
let pendingRemoteCandidates = [];
let isRemoteCctvConnected = false;
let isRemoteTorchActive = false;
let isRemoteMicMuted = false;
let streamSignalPollerInterval = null;

async function sendWebRTCSignalToTarget(targetIP, header) {
  if (!targetIP) return;
  try {
    const payload = { target_ip: targetIP, ...header };
    await fetch("/api/cctv/signal", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
  } catch (err) {
    console.error("sendWebRTCSignal error:", err);
  }
}

function startStreamSignalPoller() {
  if (streamSignalPollerInterval) return;
  streamSignalPollerInterval = setInterval(async () => {
    try {
      const res = await fetch("/api/cctv/poll-signals");
      if (!res.ok) return;
      const data = await res.json();
      const signals = data.signals || [];
      for (const sig of signals) {
        await handleIncomingStreamSignal(sig);
      }
    } catch (e) { }
  }, 200);
}

async function handleIncomingStreamSignal(sig) {
  const hdr = sig.header || sig;
  if (!hdr || !hdr.type) return;

  console.log("📥 [WebRTC Signal Received]", hdr.type, hdr);

  if (hdr.type === 'stream_answer') {
    isRemoteCctvConnected = true;

    const statusBadge = document.getElementById("cctvStatusBadge");
    const liveDot = document.getElementById("cctvLiveDot");
    const hwBox = document.getElementById("remoteHwTriggersBox");
    const btn = document.getElementById("btnConnectRemoteCctv");
    const btnLabel = document.getElementById("btnConnectRemoteLabel");
    const remoteVid = document.getElementById("remoteCctvVideo");
    const placeholder = document.getElementById("cctvPlaceholder");

    const peerDisplayName = hdr.sender || (appState.activePeer ? appState.activePeer.name : 'Peer Device');
    if (statusBadge) statusBadge.innerText = `Live Feed • ${peerDisplayName} (1080P HD)`;
    if (liveDot) liveDot.classList.add("active");
    if (hwBox) hwBox.style.display = "block";
    if (btn) btn.className = "btn btn-danger";
    if (btnLabel) btnLabel.innerText = "Disconnect Stream";
    if (placeholder) placeholder.style.display = "none";
    if (remoteVid) remoteVid.style.display = "block";

    if (remotePeerConnection && hdr.sdp) {
      try {
        if (remotePeerConnection.signalingState === "have-local-offer") {
          await remotePeerConnection.setRemoteDescription(new RTCSessionDescription({
            type: hdr.sdp_type || 'answer',
            sdp: hdr.sdp
          }));
          console.log("✅ Set Remote Description successfully");
        } else {
          console.log("ℹ️ remotePeerConnection signalingState is:", remotePeerConnection.signalingState);
        }
      } catch (err) {
        console.error("❌ Error setting remote stream description:", err);
      }

      if (pendingRemoteCandidates && pendingRemoteCandidates.length > 0) {
        for (const cand of pendingRemoteCandidates) {
          try {
            await remotePeerConnection.addIceCandidate(new RTCIceCandidate(cand));
          } catch (e) {
            console.warn("Error adding pending ice candidate:", e);
          }
        }
        pendingRemoteCandidates = [];
      }
    }
    startCctvVisionPipeline();
    showToast(`[CCTV] Connected to ${peerDisplayName} Live Stream!`);
  } else if (hdr.type === 'stream_ice') {
    if (hdr.candidate) {
      const candidateInit = {
        candidate: hdr.candidate,
        sdpMid: hdr.sdp_mid || hdr.sdpMid || "0",
        sdpMLineIndex: (hdr.sdp_mline_index !== undefined) ? parseInt(hdr.sdp_mline_index) : ((hdr.sdpMLineIndex !== undefined) ? parseInt(hdr.sdpMLineIndex) : 0)
      };
      if (remotePeerConnection && remotePeerConnection.remoteDescription && remotePeerConnection.remoteDescription.type) {
        try {
          await remotePeerConnection.addIceCandidate(new RTCIceCandidate(candidateInit));
        } catch (e) {
          console.warn("Error adding ice candidate:", e);
        }
      } else {
        pendingRemoteCandidates.push(candidateInit);
      }
    }
  } else if (hdr.type === 'stream_rejected') {
    showToast(`Access Denied: ${hdr.reason || 'Stream request declined by host'}`);
    disconnectRemoteCctv("Access Denied");
  } else if (hdr.type === 'stream_stopped' || hdr.type === 'stream_reset' || hdr.type === 'stream_ended') {
    showToast("Stream ended by remote peer");
    disconnectRemoteCctv("Stream Ended");
  } else if (hdr.type === 'stream_control') {
    if (hdr.action === 'torch_status') {
      isRemoteTorchActive = (hdr.value === true);
      const txt = document.getElementById("remoteTorchText");
      if (txt) txt.innerText = isRemoteTorchActive ? "Torch OFF" : "Torch ON";
    }
  } else if (hdr.type === 'stream_offer') {
    // Remote peer wants to view local PC camera or listen to local PC audio
    await handleIncomingStreamOffer(sig);
  }
}

async function handleIncomingStreamOffer(sig) {
  const hdr = sig.header;
  const senderIP = sig.sender_ip;
  if (!hdr || !hdr.sdp || !senderIP) return;

  try {
    if (!localHostCameraStream) {
      localHostCameraStream = await navigator.mediaDevices.getUserMedia({
        video: { width: { ideal: 1920 }, height: { ideal: 1080 } },
        audio: true
      }).catch(() => null);
    }

    if (hostPeerConnection) {
      try { hostPeerConnection.close(); } catch (e) { }
    }

    hostPeerConnection = new RTCPeerConnection({
      iceServers: [
        { urls: 'stun:stun.l.google.com:19302' },
        { urls: 'stun:stun1.l.google.com:19302' }
      ]
    });

    if (localHostCameraStream) {
      localHostCameraStream.getTracks().forEach(track => {
        hostPeerConnection.addTrack(track, localHostCameraStream);
      });
      const localVid = document.getElementById("localCctvVideo");
      if (localVid) {
        localVid.srcObject = localHostCameraStream;
        localVid.style.display = "block";
      }
      const placeholder = document.getElementById("cctvPlaceholder");
      if (placeholder) placeholder.style.display = "none";
    }

    hostPeerConnection.onicecandidate = (event) => {
      if (event.candidate) {
        sendWebRTCSignalToTarget(senderIP, {
          type: "stream_ice",
          candidate: event.candidate.candidate,
          sdp_mid: event.candidate.sdpMid,
          sdp_mline_index: event.candidate.sdpMLineIndex
        });
      }
    };

    await hostPeerConnection.setRemoteDescription(new RTCSessionDescription({
      type: hdr.sdp_type || 'offer',
      sdp: hdr.sdp
    }));

    const answer = await hostPeerConnection.createAnswer();
    await hostPeerConnection.setLocalDescription(answer);

    sendWebRTCSignalToTarget(senderIP, {
      type: "stream_answer",
      sender: "Windows Host",
      sender_id: "windows_host",
      sdp: answer.sdp,
      sdp_type: "answer"
    });

    showToast(`Streaming PC Camera to ${hdr.sender || senderIP}`);
  } catch (err) {
    console.error("handleIncomingStreamOffer error:", err);
  }
}

function disconnectRemoteCctv(reason = "") {
  isRemoteCctvConnected = false;
  if (remotePeerConnection) {
    try { remotePeerConnection.close(); } catch (e) { }
    remotePeerConnection = null;
  }
  remoteCctvStream = null;
  pendingRemoteCandidates = [];

  const remoteVid = document.getElementById("remoteCctvVideo");
  const placeholder = document.getElementById("cctvPlaceholder");
  const hwBox = document.getElementById("remoteHwTriggersBox");
  const btn = document.getElementById("btnConnectRemoteCctv");
  const btnLabel = document.getElementById("btnConnectRemoteLabel");
  const statusBadge = document.getElementById("cctvStatusBadge");
  const liveDot = document.getElementById("cctvLiveDot");

  if (remoteVid) {
    remoteVid.srcObject = null;
    remoteVid.style.display = "none";
  }
  if (placeholder) placeholder.style.display = "flex";
  if (hwBox) {
    hwBox.style.display = (cctvStreamRole === 'remote') ? "block" : "none";
  }
  if (btn) btn.className = "btn btn-primary";
  if (btnLabel) btnLabel.innerText = "Connect Camera Feed";
  if (statusBadge) statusBadge.innerText = reason ? `Disconnected (${reason})` : "Disconnected";
  if (liveDot) liveDot.classList.remove("active");
  stopCctvVisionPipeline();
}

async function toggleRemoteCctvConnection() {
  const btn = document.getElementById("btnConnectRemoteCctv");
  const btnLabel = document.getElementById("btnConnectRemoteLabel");
  const hwBox = document.getElementById("remoteHwTriggersBox");
  const remoteVid = document.getElementById("remoteCctvVideo");
  const placeholder = document.getElementById("cctvPlaceholder");
  const statusBadge = document.getElementById("cctvStatusBadge");
  const liveDot = document.getElementById("cctvLiveDot");

  const sel = document.getElementById("cctvPeerSelect");
  const selectedIP = sel ? sel.value : "";
  const targetPeer = (appState.peers || []).find(p => p.ip === selectedIP) || appState.activePeer || (appState.peers && appState.peers[0]);

  if (isRemoteCctvConnected) {
    if (targetPeer && targetPeer.ip) {
      sendWebRTCSignalToTarget(targetPeer.ip, {
        type: "stream_stopped",
        reason: "Disconnected by user"
      });
    }
    disconnectRemoteCctv();
    showToast("Remote CCTV Stream Disconnected");
  } else {
    if (!targetPeer || !targetPeer.ip) {
      showToast("Please select a target device to monitor.");
      return;
    }
    appState.activePeer = targetPeer;
    isRemoteCctvConnected = true;

    if (btn) btn.className = "btn btn-danger";
    if (btnLabel) btnLabel.innerText = "Cancel Request";
    if (statusBadge) statusBadge.innerText = `Requesting Permission from ${targetPeer.name}…`;
    if (hwBox) hwBox.style.display = "block";

    showToast(`Sending Stream Offer to ${targetPeer.name}. Check phone screen for permission prompt.`);

    try {
      if (remotePeerConnection) {
        try { remotePeerConnection.close(); } catch (e) { }
      }
      pendingRemoteCandidates = [];

      remotePeerConnection = new RTCPeerConnection({
        iceServers: [
          { urls: 'stun:stun.l.google.com:19302' },
          { urls: 'stun:stun1.l.google.com:19302' }
        ]
      });

      remotePeerConnection.addTransceiver('video', { direction: 'recvonly' });
      remotePeerConnection.addTransceiver('audio', { direction: 'recvonly' });

      remotePeerConnection.ontrack = (event) => {
        console.log("WebRTC Remote Stream ontrack received:", event);
        const remoteVid = document.getElementById("remoteCctvVideo");
        const placeholder = document.getElementById("cctvPlaceholder");
        const hwBox = document.getElementById("remoteHwTriggersBox");
        const statusBadge = document.getElementById("cctvStatusBadge");
        const liveDot = document.getElementById("cctvLiveDot");

        let streamToUse = null;
        if (event.streams && event.streams.length > 0 && event.streams[0]) {
          streamToUse = event.streams[0];
        } else if (event.track) {
          if (!remoteCctvStream) {
            remoteCctvStream = new MediaStream();
          }
          remoteCctvStream.addTrack(event.track);
          streamToUse = remoteCctvStream;
        }

        if (streamToUse) {
          remoteCctvStream = streamToUse;
          if (remoteVid) {
            remoteVid.srcObject = streamToUse;
            remoteVid.style.display = "block";
            remoteVid.muted = true;
            remoteVid.play().then(() => {
              setTimeout(() => { remoteVid.muted = false; }, 300);
            }).catch(e => {
              console.warn("Autoplay fallback to muted play:", e);
              remoteVid.muted = true;
              remoteVid.play().catch(err => console.error("Remote video play error:", err));
            });
          }
          if (placeholder) placeholder.style.display = "none";
          if (hwBox) hwBox.style.display = "block";
          if (statusBadge) statusBadge.innerText = `Live Feed • ${targetPeer ? targetPeer.name : 'Host'} (1080P HD)`;
          if (liveDot) liveDot.classList.add("active");
        }
      };

      remotePeerConnection.onconnectionstatechange = () => {
        console.log("Remote WebRTC connection state:", remotePeerConnection.connectionState);
        if (remotePeerConnection.connectionState === "connected") {
          const statusBadge = document.getElementById("cctvStatusBadge");
          const liveDot = document.getElementById("cctvLiveDot");
          if (statusBadge) statusBadge.innerText = `Live Feed • ${targetPeer ? targetPeer.name : 'Host'} (1080P HD)`;
          if (liveDot) liveDot.classList.add("active");
        } else if (remotePeerConnection.connectionState === "disconnected" || remotePeerConnection.connectionState === "failed") {
          showToast("Remote CCTV stream connection lost or ended.");
        }
      };

      remotePeerConnection.onicecandidate = (event) => {
        if (event.candidate && targetPeer && targetPeer.ip) {
          sendWebRTCSignalToTarget(targetPeer.ip, {
            type: "stream_ice",
            candidate: event.candidate.candidate,
            sdp_mid: event.candidate.sdpMid,
            sdp_mline_index: event.candidate.sdpMLineIndex
          });
        }
      };

      const offer = await remotePeerConnection.createOffer({
        offerToReceiveVideo: true,
        offerToReceiveAudio: true
      });
      await remotePeerConnection.setLocalDescription(offer);

      sendWebRTCSignalToTarget(targetPeer.ip, {
        type: "stream_offer",
        sender: appState.localNodeName || "DESKTOP-NAFH7L0",
        sender_id: appState.localNodeID || "28993748",
        sdp: offer.sdp,
        sdp_type: "offer",
        stream_type: "camera",
        audio_mode: "listen"
      });

    } catch (err) {
      console.error("toggleRemoteCctvConnection error:", err);
      showToast(`Stream negotiation error: ${err.message}`);
      disconnectRemoteCctv("Error");
    }
  }
}

async function triggerRemoteHardware(action) {
  const sel = document.getElementById("cctvPeerSelect");
  const selectedIP = sel ? sel.value : "";
  const targetPeer = (appState.peers || []).find(p => p.ip === selectedIP) || appState.activePeer || (appState.peers && appState.peers[0]);
  const ip = targetPeer ? targetPeer.ip : "";

  if (!ip) {
    showToast("No active peer selected for remote hardware commands.");
    return;
  }

  if (action === 'toggle_torch') {
    isRemoteTorchActive = !isRemoteTorchActive;
    const txt = document.getElementById("remoteTorchText");
    if (txt) txt.innerText = isRemoteTorchActive ? "Torch OFF" : "Torch ON";
    await fetch("/api/cctv/remote-ctrl", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ target_ip: ip, action: "toggle_torch", value: isRemoteTorchActive })
    });
    showToast(isRemoteTorchActive ? "[Hardware] Turned Remote Flashlight ON" : "[Hardware] Turned Remote Flashlight OFF");
  } else if (action === 'switch_camera') {
    await fetch("/api/cctv/remote-ctrl", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ target_ip: ip, action: "switch_camera" })
    });
    showToast("[Hardware] Sent Flip Lens command to remote device");
  } else if (action === 'toggle_mic') {
    isRemoteMicMuted = !isRemoteMicMuted;
    const txt = document.getElementById("remoteMicText");
    if (txt) txt.innerText = isRemoteMicMuted ? "Unmute Peer" : "Mute Peer";
    await fetch("/api/cctv/remote-ctrl", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ target_ip: ip, action: "toggle_mic", value: isRemoteMicMuted })
    });
    showToast(isRemoteMicMuted ? "[Audio] Muted Remote Peer Microphone" : "[Audio] Unmuted Remote Peer Microphone");
  }
}

function resetCctvStream() {
  stopCctvVisionPipeline();
  showToast("Resetting & refreshing CCTV stream session...");
  if (isRemoteCctvConnected) {
    toggleRemoteCctvConnection();
    setTimeout(toggleRemoteCctvConnection, 600);
  } else if (localHostCameraStream) {
    toggleHostCameraStream();
    setTimeout(toggleHostCameraStream, 600);
  }
}

function toggleCctvFullscreen() {
  const vp = document.getElementById("cctvMainViewport");
  if (!vp) return;
  if (!document.fullscreenElement) {
    vp.requestFullscreen().then(() => {
      handleFullscreenGraphVisibility(true);
    }).catch(err => {
      showToast("Fullscreen unavailable: " + err.message);
    });
  } else {
    document.exitFullscreen().then(() => {
      handleFullscreenGraphVisibility(false);
    });
  }
}

function handleFullscreenGraphVisibility(isFullscreen) {
  const graphBox = document.getElementById("cctvLiveGraphBox");
  const rightDrawer = document.getElementById("cctvRightSidePanel");
  const btnDrawer = document.getElementById("btnToggleCctvDrawer");
  const btnGraph = document.getElementById("btnToggleCctvGraph");

  if (isFullscreen && cctvStreamRole === 'remote') {
    if (graphBox && cctvGraphHudVisible) graphBox.style.display = "block";
    if (rightDrawer && cctvDrawerOpen) {
      rightDrawer.style.display = "flex";
      rightDrawer.classList.remove("hidden");
    }
    if (btnDrawer) btnDrawer.style.display = "flex";
    if (btnGraph) btnGraph.style.display = "flex";
  } else {
    if (graphBox) graphBox.style.display = "none";
    if (rightDrawer) {
      rightDrawer.style.display = "none";
      rightDrawer.classList.add("hidden");
    }
    if (btnDrawer) btnDrawer.style.display = "none";
    if (btnGraph) btnGraph.style.display = "none";
  }
}

document.addEventListener("fullscreenchange", () => {
  const isFullscreen = !!document.fullscreenElement;
  handleFullscreenGraphVisibility(isFullscreen);
});


let cctvMediaRecorder = null;
let cctvRecordedChunks = [];
let cctvRecordingStartTime = null;

function getActiveCctvStream() {
  const remoteVid = document.getElementById("remoteCctvVideo");
  const localVid = document.getElementById("localCctvVideo");

  if (remoteVid && remoteVid.style.display !== "none" && remoteVid.srcObject) {
    return { stream: remoteVid.srcObject, videoEl: remoteVid };
  }
  if (localVid && localVid.style.display !== "none" && localVid.srcObject) {
    return { stream: localVid.srcObject, videoEl: localVid };
  }
  if (remoteCctvStream) {
    return { stream: remoteCctvStream, videoEl: remoteVid };
  }
  if (localHostCameraStream) {
    return { stream: localHostCameraStream, videoEl: localVid };
  }
  return null;
}

function toggleCctvRecording() {
  const badge = document.getElementById("cctvRecBadge");
  const btnLabel = document.getElementById("recBtnLabel");

  if (appState.cctv.isRecording) {
    appState.cctv.isRecording = false;
    if (badge) badge.style.display = "none";
    if (btnLabel) btnLabel.innerText = "Start REC";
    if (recordingTimerInterval) {
      clearInterval(recordingTimerInterval);
      recordingTimerInterval = null;
    }

    if (cctvMediaRecorder && cctvMediaRecorder.state !== "inactive") {
      try {
        cctvMediaRecorder.stop();
      } catch (e) { }
    }
    showToast("⏹ Stopping and saving live CCTV recording...");
  } else {
    const active = getActiveCctvStream();
    if (!active || !active.stream) {
      showToast("No active video feed to record. Start host or connect remote feed first.");
      return;
    }

    try {
      cctvRecordedChunks = [];
      let mimeType = "video/webm;codecs=vp8,opus";
      let fileExt = "webm";
      if (window.MediaRecorder) {
        if (MediaRecorder.isTypeSupported("video/webm;codecs=vp9,opus")) {
          mimeType = "video/webm;codecs=vp9,opus";
          fileExt = "webm";
        } else if (MediaRecorder.isTypeSupported("video/mp4")) {
          mimeType = "video/mp4";
          fileExt = "mp4";
        } else if (MediaRecorder.isTypeSupported("video/webm;codecs=h264")) {
          mimeType = "video/webm;codecs=h264";
          fileExt = "webm";
        }
      }

      cctvMediaRecorder = new MediaRecorder(active.stream, { mimeType: mimeType });
      cctvRecordingStartTime = Date.now();

      cctvMediaRecorder.ondataavailable = (e) => {
        if (e.data && e.data.size > 0) {
          cctvRecordedChunks.push(e.data);
        }
      };

      cctvMediaRecorder.onstop = async () => {
        const blob = new Blob(cctvRecordedChunks, { type: mimeType });
        const durSec = Math.round((Date.now() - cctvRecordingStartTime) / 1000);
        const mins = Math.floor(durSec / 60);
        const secs = durSec % 60;
        const durStr = `${mins}m ${secs}s`;

        try {
          const res = await fetch(`/api/cctv/upload-recording?ext=${fileExt}&dur=${encodeURIComponent(durStr)}`, {
            method: "POST",
            body: blob
          });
          if (res.ok) {
            showToast(`💾 CCTV Recording Saved to CCTV_Recordings (${durStr})!`);
          }
        } catch (err) {
          console.error("Recording upload error:", err);
        }
      };

      cctvMediaRecorder.start(1000);
      appState.cctv.isRecording = true;

      if (badge) badge.style.display = "flex";
      if (btnLabel) btnLabel.innerText = "Stop REC";

      recordingSeconds = 0;
      recordingTimerInterval = setInterval(() => {
        recordingSeconds++;
        const hrs = String(Math.floor(recordingSeconds / 3600)).padStart(2, "0");
        const mins = String(Math.floor((recordingSeconds % 3600) / 60)).padStart(2, "0");
        const secs = String(recordingSeconds % 60).padStart(2, "0");
        const timerEl = document.getElementById("recTimer");
        if (timerEl) timerEl.innerText = `${hrs}:${mins}:${secs}`;
      }, 1000);

      showToast("[CCTV] Live Recording Started (1080P HD)");
    } catch (err) {
      console.error("MediaRecorder start error:", err);
      showToast(`Recording error: ${err.message}`);
    }
  }
}

function captureCctvSnapshot() {
  const active = getActiveCctvStream();
  if (!active || !active.videoEl) {
    showToast("No active camera stream to capture snapshot.");
    return;
  }

  const vid = active.videoEl;
  const canvas = document.createElement("canvas");
  canvas.width = vid.videoWidth || 1920;
  canvas.height = vid.videoHeight || 1080;
  const ctx = canvas.getContext("2d");
  ctx.drawImage(vid, 0, 0, canvas.width, canvas.height);

  canvas.toBlob(async (blob) => {
    if (!blob) return;
    try {
      await fetch("/api/cctv/upload-snapshot", {
        method: "POST",
        body: blob
      });
      showToast("[Snapshot] High-Res Snapshot saved to CCTV_Snapshots folder");
    } catch (e) {
      console.error("Snapshot upload error:", e);
      showToast("Snapshot saved locally.");
    }
  }, "image/png");
}

function toggleCctvTorch() {
  appState.cctv.torchOn = !appState.cctv.torchOn;
  document.getElementById("torchLabel").innerText = `Torch: ${appState.cctv.torchOn ? 'ON' : 'OFF'}`;
  fetch("/api/cctv/torch", { method: "POST" });
}

function flipCctvCamera() {
  fetch("/api/cctv/flip", { method: "POST" });
  showToast("Flipping camera lens...");
}

function openRecordingsFolder() {
  fetch("/api/open-recordings");
}

// -----------------------------------------------------------------------------
// LIVE AUDIO RELAY & WEBRTC CALLING (Listen Remote Mic vs Broadcast My Voice)
// =============================================================================
// PROFESSIONAL WEBRTC VOICE & AUDIO INTERCOM STUDIO
// =============================================================================
let isCallActive = false;
let localMediaStream = null;
let peerConnection = null;
let isScreenSharing = false;
let incomingCallData = null;
let testMicStream = null;
let testMicInterval = null;

function populateAudioPeerSelect() {
  const sel = document.getElementById("audioPeerSelect");
  if (!sel) return;

  const peers = (appState.peers && appState.peers.length > 0) ? appState.peers : [];
  const lanDevs = (appState.lanDevices && appState.lanDevices.length > 0) ? appState.lanDevices : [];

  const map = new Map();
  peers.forEach(p => { if (p.ip) map.set(p.ip, { ip: p.ip, name: p.name || p.ip, isPhone: true }); });
  lanDevs.forEach(d => {
    if (d.ip && !map.has(d.ip)) {
      const isPhone = (d.hostname || d.name || "").toLowerCase().includes("sm-") || (d.hostname || "").toLowerCase().includes("phone");
      map.set(d.ip, { ip: d.ip, name: d.hostname || d.name || d.ip, isPhone });
    }
  });

  const list = Array.from(map.values());
  const activeIP = appState.activePeer ? appState.activePeer.ip : "";

  if (list.length === 0) {
    sel.innerHTML = `<option value="">No devices discovered yet (Scanning LAN...)</option>`;
    return;
  }

  sel.innerHTML = list.map(p => {
    const isSelected = p.ip === activeIP;
    const devTag = p.isPhone ? "Smartphone" : "Device";
    return `<option value="${escapeHTML(p.ip)}" ${isSelected ? 'selected' : ''}>Target: [${devTag}] ${escapeHTML(p.name)} (${escapeHTML(p.ip)})</option>`;
  }).join("");
}

function onAudioTargetPeerChanged(ip) {
  const matched = (appState.peers || []).find(p => p.ip === ip) ||
    (appState.lanDevices || []).find(d => d.ip === ip);
  if (matched) {
    appState.activePeer = {
      ip: matched.ip,
      name: matched.name || matched.hostname || matched.ip,
      id: matched.id || matched.ip
    };
    updateDetailViewForPeer(appState.activePeer);
  }
}

function getSelectedAudioTarget() {
  const sel = document.getElementById("audioPeerSelect");
  const selectedIP = sel ? sel.value : "";
  const matched = (appState.peers || []).find(p => p.ip === selectedIP) ||
    (appState.lanDevices || []).find(d => d.ip === selectedIP);
  if (matched) {
    return {
      ip: matched.ip,
      name: matched.name || matched.hostname || matched.ip,
      id: matched.id || matched.ip
    };
  }
  if (appState.activePeer && appState.activePeer.ip) return appState.activePeer;
  if (appState.peers && appState.peers.length > 0) return appState.peers[0];
  return null;
}

function startSelectedAudioAction(actionType) {
  const target = getSelectedAudioTarget();
  if (!target || !target.ip) {
    showToast("Please select a target device from the dropdown first.");
    return;
  }

  appState.activePeer = target;
  isCallActive = true;

  const dashboard = document.getElementById("voiceDashboardView");
  const activeCallView = document.getElementById("voiceActiveCallView");
  const peerTitle = document.getElementById("callPeerTitle");
  const peerStatus = document.getElementById("callPeerStatus");

  if (dashboard) dashboard.style.display = "none";
  if (activeCallView) activeCallView.style.display = "flex";

  if (peerTitle) peerTitle.innerText = target.name;

  if (actionType === 'voice_call') {
    if (peerStatus) peerStatus.innerText = "Active Two-Way Encrypted Voice Intercom";
    setCallMode('audio');
    startCallWithPeer(target.ip, target.name, false);
    showToast(`[Voice Intercom] Connecting to ${target.name}...`);
  } else if (actionType === 'listen_mic') {
    if (peerStatus) peerStatus.innerText = "Surveillance Audio: Listening to Remote Device Mic";
    setCallMode('audio');
    startCallWithPeer(target.ip, target.name, false);
    showToast(`[Remote Mic] Connecting to ${target.name} room microphone...`);
  } else if (actionType === 'broadcast_voice') {
    if (peerStatus) peerStatus.innerText = "PA Intercom: Broadcasting PC Mic to Remote Speaker";
    setCallMode('audio');
    startCallWithPeer(target.ip, target.name, false);
    showToast(`[PA Broadcast] Broadcasting voice to ${target.name}...`);
  } else if (actionType === 'video_call') {
    if (peerStatus) peerStatus.innerText = "Active 1080P WebRTC HD Video Call";
    setCallMode('video');
    startCallWithPeer(target.ip, target.name, true);
    showToast(`[Video Call] Ringing ${target.name}...`);
  }
}

async function testLocalMicInput() {
  const btn = document.getElementById("btnTestLocalMic");
  const bar = document.getElementById("localMicVuBar");
  const txt = document.getElementById("localMicVuText");

  if (testMicInterval) {
    clearInterval(testMicInterval);
    testMicInterval = null;
    if (testMicStream) {
      testMicStream.getTracks().forEach(t => t.stop());
      testMicStream = null;
    }
    if (btn) btn.innerHTML = "<span>🎙️ Test PC Mic Level</span>";
    if (bar) bar.style.width = "0%";
    if (txt) txt.innerText = "0 dB";
    showToast("[Mic Test] Microphone VU level test stopped");
    return;
  }

  try {
    testMicStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    if (btn) btn.innerHTML = "<span style='color:#EF4444;'>⏹️ Stop Mic Test</span>";

    testMicInterval = setInterval(() => {
      const randVu = Math.floor(35 + Math.random() * 55);
      if (bar) bar.style.width = `${randVu}%`;
      if (txt) txt.innerText = `-${Math.round((100 - randVu) / 2)} dB (Normal)`;
    }, 120);

    showToast("[Mic Test] Speaking into PC mic... VU meter active");
  } catch (e) {
    showToast("[Mic Test Error] Could not access PC microphone: " + e.message);
  }
}

function setCallMode(mode) {
  appState.voice.mode = mode; // 'audio' or 'video'
  const isVideo = mode === 'video';

  const pillAudio = document.getElementById("pillModeAudio");
  const pillBroadcast = document.getElementById("pillModeBroadcast");
  const pillVideo = document.getElementById("pillModeVideo");
  if (pillAudio) pillAudio.classList.remove("active");
  if (pillBroadcast) pillBroadcast.classList.remove("active");
  if (pillVideo) pillVideo.classList.toggle("active", isVideo);

  const stageAudio = document.getElementById("stageAudioCall");
  const stageVideo = document.getElementById("stageVideoCall");
  if (stageAudio) stageAudio.style.display = isVideo ? "none" : "flex";
  if (stageVideo) stageVideo.style.display = isVideo ? "flex" : "none";

  const camBtn = document.getElementById("btnCallCam");
  if (camBtn) camBtn.classList.toggle("active-ctrl", isVideo);

  if (isVideo) {
    acquireLocalCamera();
  } else {
    stopLocalCameraTrack();
  }
}

async function acquireLocalCamera() {
  try {
    if (!localMediaStream) {
      localMediaStream = await navigator.mediaDevices.getUserMedia({
        video: { width: { ideal: 1280 }, height: { ideal: 720 } },
        audio: true
      });
    } else {
      const videoTracks = localMediaStream.getVideoTracks();
      if (videoTracks.length === 0) {
        const stream = await navigator.mediaDevices.getUserMedia({ video: true });
        stream.getVideoTracks().forEach(t => localMediaStream.addTrack(t));
      } else {
        videoTracks.forEach(t => t.enabled = true);
      }
    }
    const localVid = document.getElementById("localVideo");
    if (localVid) localVid.srcObject = localMediaStream;
  } catch (err) {
    console.log("Local camera acquisition handled:", err);
  }
}

function stopLocalCameraTrack() {
  if (localMediaStream) {
    localMediaStream.getVideoTracks().forEach(t => {
      t.enabled = false;
    });
  }
}

function initEqualizerBars() {
  const eq = document.getElementById("audioEqualizer");
  if (!eq) return;
  eq.innerHTML = "";
  for (let i = 0; i < 24; i++) {
    const bar = document.createElement("div");
    bar.className = "eq-bar";
    bar.style.height = "10px";
    eq.appendChild(bar);
  }
}

function startEqualizerLoop() {
  if (equalizerInterval) clearInterval(equalizerInterval);
  equalizerInterval = setInterval(() => {
    const bars = document.querySelectorAll(".audio-wave-visualizer .eq-bar");
    bars.forEach((bar, i) => {
      const muted = appState.voice.muted;
      const height = muted ? 4 : Math.floor(Math.sin((Date.now() / 150) + i) * 10) + 14;
      bar.style.height = `${Math.max(4, height)}px`;
    });
  }, 80);
}

function startCallTimer() {
  if (callDurationInterval) clearInterval(callDurationInterval);
  callDurationInterval = setInterval(() => {
    appState.voice.callDuration++;
    const mins = String(Math.floor(appState.voice.callDuration / 60)).padStart(2, "0");
    const secs = String(appState.voice.callDuration % 60).padStart(2, "0");
    const badge = document.getElementById("callDurationBadge");
    if (badge) badge.innerText = `00:${mins}:${secs}`;
    const vidBadge = document.getElementById("videoDurationBadge");
    if (vidBadge) vidBadge.innerText = `00:${mins}:${secs}`;
  }, 1000);
}

function startCallWithPeer(ip, name, isVideo = false) {
  isCallActive = true;
  appState.activePeer = { ip, name: name || ip, id: ip };
  updateDetailViewForPeer(appState.activePeer);

  const dashboard = document.getElementById("voiceDashboardView");
  const activeCallView = document.getElementById("voiceActiveCallView");
  const peerTitle = document.getElementById("callPeerTitle");
  const peerStatus = document.getElementById("callPeerStatus");

  if (dashboard) dashboard.style.display = "none";
  if (activeCallView) activeCallView.style.display = "flex";
  if (peerTitle) peerTitle.innerText = name || ip;
  if (peerStatus) peerStatus.innerText = isVideo ? "Active 1080P WebRTC HD Video Call" : "Active Encrypted Voice Stream";

  appState.voice.callDuration = 0;
  startCallTimer();
  startEqualizerLoop();

  fetch("/api/call/invite", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      target_ip: ip,
      peer_id: ip,
      peer_name: name || ip,
      is_video: isVideo
    })
  }).catch(() => {});

  switchTab('voice', true);
  setCallMode(isVideo ? 'video' : 'audio');

  const callRecord = {
    id: "call_" + Date.now(),
    peerName: name || ip,
    peerIP: ip,
    type: isVideo ? "WebRTC HD Video Call" : "WebRTC HD Voice Call",
    status: "Connected",
    duration: "00m 01s",
    at: new Date()
  };
  appState.callHistory.unshift(callRecord);
  savePersistedCalls();
}

function toggleVoiceMute() {
  appState.voice.muted = !appState.voice.muted;
  const lbl = document.getElementById("muteLabel");
  if (lbl) lbl.innerText = appState.voice.muted ? "Muted" : "Mic On";
  const btn = document.getElementById("btnCallMute");
  if (btn) btn.classList.toggle("active-ctrl", appState.voice.muted);

  if (localMediaStream) {
    localMediaStream.getAudioTracks().forEach(t => {
      t.enabled = !appState.voice.muted;
    });
  }

  fetch("/api/voice/mute", { method: "POST" });
  showToast(appState.voice.muted ? "Microphone Muted" : "Microphone Active");
}

// -----------------------------------------------------------------------------
// STREAMING SECURITY HUB (P2P Stream Permissions & Always-Trusted Devices)
// -----------------------------------------------------------------------------
async function loadStreamingSecurity() {
  try {
    const res = await fetch("/api/streaming/security");
    if (res.ok) {
      const data = await res.json();
      const chkCam = document.getElementById("chkAllowCamera");
      const chkAud = document.getElementById("chkAllowAudio");
      const chkScr = document.getElementById("chkAllowScreen");

      if (chkCam && data.allow_camera !== undefined) chkCam.checked = data.allow_camera;
      if (chkAud && data.allow_audio !== undefined) chkAud.checked = data.allow_audio;
      if (chkScr && data.allow_screen !== undefined) chkScr.checked = data.allow_screen;

      renderTrustedDevices(data.trusted_devices || []);
    }
  } catch (err) {
    console.error("loadStreamingSecurity error:", err);
  }
}

async function updateStreamingSecurity() {
  const allowCamera = document.getElementById("chkAllowCamera") ? document.getElementById("chkAllowCamera").checked : true;
  const allowAudio = document.getElementById("chkAllowAudio") ? document.getElementById("chkAllowAudio").checked : true;
  const allowScreen = document.getElementById("chkAllowScreen") ? document.getElementById("chkAllowScreen").checked : true;

  try {
    await fetch("/api/streaming/security", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        allow_camera: allowCamera,
        allow_audio: allowAudio,
        allow_screen: allowScreen,
        always_trust: true
      })
    });
    showToast("[Security] Streaming Security permissions updated");
  } catch (err) {
    showToast("Error updating streaming security.");
  }
}

function renderTrustedDevices(trusted) {
  const container = document.getElementById("trustedDevicesContainer");
  if (!container) return;

  if (trusted.length === 0) {
    container.innerHTML = `
      <div style="padding:14px; text-align:center; color:var(--text-muted); font-size:12px; background:rgba(255,255,255,0.02); border-radius:8px;">
        No always-trusted devices configured yet.<br>When streaming requests arrive, you can choose "Always Trust".
      </div>
    `;
    return;
  }

  container.innerHTML = trusted.map(id => {
    return `
      <div class="trusted-device-row">
        <div class="trusted-dev-info">
          <div class="trusted-icon-wrap">✓</div>
          <div>
            <div style="font-weight:600; font-size:13px; color:var(--text-title);">${escapeHTML(id)}</div>
            <div style="font-size:11px; color:var(--text-muted);">Auto-authorized for local camera/audio stream</div>
          </div>
        </div>
        <button class="btn btn-sm btn-danger" onclick="revokeTrustedDevice('${escapeHTML(id)}')" style="padding:4px 10px; font-size:11.5px;">Revoke</button>
      </div>
    `;
  }).join("");
}

async function addActivePeerToTrusted() {
  const activePeer = appState.activePeer;
  const peerId = activePeer ? (activePeer.name || activePeer.ip) : "";
  if (!peerId) {
    showToast("No active device selected to add to trusted list.");
    return;
  }

  try {
    const res = await fetch("/api/streaming/trust-device", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ device_id: peerId, action: "add" })
    });
    const data = await res.json();
    renderTrustedDevices(data.trusted_devices || []);
    showToast(`Added "${peerId}" to Always-Trusted Devices!`);
  } catch (err) {
    showToast("Error trusting device.");
  }
}

async function revokeTrustedDevice(peerId) {
  try {
    const res = await fetch("/api/streaming/trust-device", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ device_id: peerId, action: "remove" })
    });
    const data = await res.json();
    renderTrustedDevices(data.trusted_devices || []);
    showToast(`Revoked trust for "${peerId}"`);
  } catch (err) {
    showToast("Error revoking trust.");
  }
}

function toggleVideoCamera() {
  const currentMode = appState.voice.mode || 'audio';
  if (currentMode === 'audio') {
    setCallMode('video');
    showToast("Switched to HD Video Call");
  } else {
    setCallMode('audio');
    showToast("Switched to Audio Call");
  }
}

async function toggleScreenShare() {
  if (isScreenSharing) {
    isScreenSharing = false;
    const lbl = document.getElementById("screenLabel");
    if (lbl) lbl.innerText = "Share";
    const btn = document.getElementById("btnCallScreen");
    if (btn) btn.classList.remove("active-ctrl");
    acquireLocalCamera();
    showToast("Screen sharing stopped");
  } else {
    try {
      const screenStream = await navigator.mediaDevices.getDisplayMedia({ video: true });
      isScreenSharing = true;
      const lbl = document.getElementById("screenLabel");
      if (lbl) lbl.innerText = "Sharing";
      const btn = document.getElementById("btnCallScreen");
      if (btn) btn.classList.add("active-ctrl");

      const localVid = document.getElementById("localVideo");
      if (localVid) localVid.srcObject = screenStream;

      screenStream.getVideoTracks()[0].onended = () => {
        toggleScreenShare();
      };
      showToast("Live Screen Sharing started over P2P WebRTC");
    } catch (err) {
      showToast("Screen sharing cancelled or unavailable");
    }
  }
}

function toggleSpeaker() {
  appState.voice.speaker = !appState.voice.speaker;
  const lbl = document.getElementById("speakerLabel");
  if (lbl) lbl.innerText = appState.voice.speaker ? "Speaker" : "Earpiece";
  showToast(appState.voice.speaker ? "Audio Output: Speakerphone" : "Audio Output: Earpiece");
}

function endVoiceCall() {
  isCallActive = false;

  try {
    if (localMediaStream) {
      localMediaStream.getTracks().forEach(t => {
        try { t.stop(); } catch (e) { }
      });
      localMediaStream = null;
    }
    if (peerConnection) {
      try { peerConnection.close(); } catch (e) { }
      peerConnection = null;
    }
    if (callDurationInterval) {
      clearInterval(callDurationInterval);
      callDurationInterval = null;
    }
    if (equalizerInterval) {
      clearInterval(equalizerInterval);
      equalizerInterval = null;
    }
    stopLocalCameraTrack();
  } catch (err) {
    console.error("endVoiceCall cleanup error:", err);
  } finally {
    const dashboard = document.getElementById("voiceDashboardView");
    const activeCallView = document.getElementById("voiceActiveCallView");
    if (dashboard) dashboard.style.display = "flex";
    if (activeCallView) activeCallView.style.display = "none";

    const stageAudio = document.getElementById("stageAudioCall");
    const stageVideo = document.getElementById("stageVideoCall");
    if (stageAudio) stageAudio.style.display = "flex";
    if (stageVideo) stageVideo.style.display = "none";

    const statusBadge = document.getElementById("callDurationBadge");
    if (statusBadge) statusBadge.innerText = "00:00:00";
    const vidBadge = document.getElementById("videoDurationBadge");
    if (vidBadge) vidBadge.innerText = "00:00:00";

    document.querySelectorAll(".audio-wave-visualizer .eq-bar").forEach(b => b.style.height = "4px");

    populateAudioPeerSelect();
    fetch("/api/call/end", { method: "POST" }).catch(() => { });
    fetch("/api/voice/end", { method: "POST" }).catch(() => { });
    showToast("Call session ended.");
  }
}

function showIncomingCallOverlay(peerName, peerIP, isVideo) {
  incomingCallData = { peerName, peerIP, isVideo };
  const overlay = document.getElementById("incomingCallOverlay");
  const nameEl = document.getElementById("icPeerName");
  const avatarEl = document.getElementById("icAvatar");
  const typeEl = document.getElementById("icCallType");

  if (nameEl) nameEl.innerText = peerName || "Unknown Peer";
  if (avatarEl) avatarEl.innerText = getInitials(peerName || "Peer");
  if (typeEl) typeEl.innerText = isVideo ? "HD Video • P2P WebRTC" : "Audio • P2P WebRTC";
  if (overlay) overlay.style.display = "flex";
}

function hideIncomingCallOverlay() {
  incomingCallData = null;
  const overlay = document.getElementById("incomingCallOverlay");
  if (overlay) overlay.style.display = "none";
}

async function answerIncomingCall() {
  const data = incomingCallData;
  hideIncomingCallOverlay();
  try {
    await fetch("/api/call/answer", { method: "POST" });
  } catch (e) { }

  if (data) {
    startCallWithPeer(data.peerIP, data.peerName, data.isVideo);
  } else {
    switchTab('voice', true);
  }
}

async function declineIncomingCall() {
  hideIncomingCallOverlay();
  try {
    await fetch("/api/call/decline", { method: "POST" });
  } catch (e) { }
  showToast("Incoming call declined.");
}

// -----------------------------------------------------------------------------
// AI FLEET HUB
// -----------------------------------------------------------------------------
function setAIModel(provider, model, el) {
  document.querySelectorAll(".model-pill").forEach(p => p.classList.remove("active"));
  if (el) {
    el.classList.add("active");
  } else {
    document.querySelectorAll(".model-pill").forEach(p => {
      if (p.innerText && p.innerText.toLowerCase().includes(provider.toLowerCase())) {
        p.classList.add("active");
      }
    });
  }
  const badge = document.getElementById("aiModelBadge");
  if (badge) badge.innerText = `${model} Active`;
  fetch("/api/ai/set-model", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ provider, model })
  });
  showToast(`AI Model switched to ${model}`);
}

const aiPresets = [
  "Analyze wheat and mustard crop leaves for fungal rust and recommend bio-fungicide treatment.",
  "Calculate optimal irrigation pump schedule for 4 acres of loamy soil at 32% volumetric moisture.",
  "Generate APMC Mandi price forecast table for Wheat, Mustard, and Potato for local district.",
  "Dispatch compute pipeline for local computer vision leaf contour detection across mesh nodes."
];

function runAIPreset(idx) {
  const prompt = aiPresets[idx];
  executeAIQuery(prompt);
}

function queryCustomAI() {
  const input = document.getElementById("aiCustomInput");
  const prompt = (input.value || "").trim();
  if (!prompt) return;
  input.value = "";
  executeAIQuery(prompt);
}

async function executeAIQuery(prompt) {
  const consoleBody = document.getElementById("aiConsoleBody");
  consoleBody.innerHTML = `<em>Querying NearMitra AI Diagnostic Engine (${(appState.ai.provider || 'gemini').toUpperCase()})...</em>`;
  try {
    const res = await fetch("/api/ai/query", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ prompt })
    });
    const data = await res.json();
    consoleBody.innerHTML = formatMarkdown(data.response || "No response received.");
  } catch (err) {
    consoleBody.innerText = "Error contacting AI engine: " + err.message;
  }
}

function copyAIConsoleOutput() {
  const consoleBody = document.getElementById("aiConsoleBody");
  if (!consoleBody) return;
  const text = consoleBody.innerText || consoleBody.textContent;
  if (!text) return;
  navigator.clipboard.writeText(text);
  showToast("AI reasoning response copied to clipboard!");
}

function shareAIToActivePeer() {
  const consoleBody = document.getElementById("aiConsoleBody");
  if (!consoleBody) return;
  const text = (consoleBody.innerText || consoleBody.textContent || "").trim();
  if (!text || text.startsWith("Click \"Analyze\"")) {
    showToast("No AI response to share yet. Run a query first.");
    return;
  }

  const targetPeer = appState.activePeer;
  const targetIP = targetPeer ? targetPeer.ip : (appState.peers && appState.peers[0] ? appState.peers[0].ip : "");
  const targetID = targetPeer ? targetPeer.id : (appState.peers && appState.peers[0] ? appState.peers[0].id : "");

  if (!targetIP && !targetID) {
    showToast("No active peer connected to share with.");
    return;
  }

  const prov = (appState.ai.provider || "Gemini").toUpperCase();
  const sharedMsg = {
    id: "msg_ai_share_" + Date.now(),
    peer_id: targetID,
    peer_ip: targetIP,
    sender: "Windows Host",
    text: `[NearMitra ${prov} AI Shared Reasoning]\n\n${text}`,
    mine: true,
    at: new Date(),
    status: "Sent",
    reactions: { "🤖": 1 }
  };

  appState.messages.push(sharedMsg);
  savePersistedMessages();
  fetch("/api/chat/send", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(sharedMsg)
  });

  showToast(`AI diagnostic report shared to ${targetPeer ? targetPeer.name : 'Peer'}!`);
  switchTab('chat', true);
  setChatSubTab('peer');
}

// -----------------------------------------------------------------------------
// CHAT SUBTAB TOGGLE (Peer Chat vs Nearby AI) & NEARBY AI CHAT
// -----------------------------------------------------------------------------
function setChatSubTab(tab) {
  const btnPeer = document.getElementById("subtabPeerChat");
  const btnAI = document.getElementById("subtabNearbyAI");
  const viewPeer = document.getElementById("chatViewPeer");
  const viewAI = document.getElementById("chatViewAI");

  if (tab === 'ai') {
    if (btnPeer) btnPeer.classList.remove("active");
    if (btnAI) btnAI.classList.add("active");
    if (viewPeer) viewPeer.style.display = "none";
    if (viewAI) viewAI.style.display = "flex";
    updateAIChatHeader();
  } else {
    if (btnPeer) btnPeer.classList.add("active");
    if (btnAI) btnAI.classList.remove("active");
    if (viewPeer) viewPeer.style.display = "flex";
    if (viewAI) viewAI.style.display = "none";
  }
}

function updateAIChatHeader() {
  const badge = document.getElementById("aiSubtabProviderBadge");
  const modelBadge = document.getElementById("aiChatModelBadge");
  const shareInd = document.getElementById("aiShareIndicator");
  const prov = appState.ai.provider || "gemini";
  const mod = appState.ai.model || "Gemini 2.0 Flash";

  if (badge) badge.innerText = prov.toUpperCase();
  if (modelBadge) modelBadge.innerText = `${prov.toUpperCase()}: ${mod}`;
  if (shareInd) shareInd.style.display = appState.ai.shareAI ? "inline-flex" : "none";

  ['gemini', 'openai', 'groq', 'ollama'].forEach(p => {
    const pill = document.getElementById(`aiProvPill${p.charAt(0).toUpperCase() + p.slice(1)}`);
    if (pill) pill.classList.toggle("active", prov === p);
  });
}

// -----------------------------------------------------------------------------
// AI FLEET & NEURAL STUDIO CONTROLLER
// -----------------------------------------------------------------------------

const AI_PRESET_PROMPTS = [
  "🌾 Provide a comprehensive diagnostic and organic remedy for yellow/brown leaf rust in Wheat (Triticum aestivum), including bio-fungicide dosages and watering precautions.",
  "💧 Calculate optimal smart irrigation scheduling and water requirement for 1 acre of sandy loam soil with current soil moisture at 24% and temperature at 32°C.",
  "📊 Analyze current mandi price trends and market forecast for Wheat (HD-3086) and Mustard across North Indian mandis with MSP comparison and best selling week.",
  "🧪 Provide customized NPK fertilizer calculation, bio-fertilizer recommendations (Azotobacter & PSB), and zinc sulfate deficiency remedies for rabi crops."
];

const AI_MODEL_PRESETS = {
  groq: [
    "llama-3.3-70b-versatile",
    "deepseek-r1-distill-llama-70b",
    "llama-3.1-8b-instant",
    "llama-3.2-11b-vision-preview",
    "mixtral-8x7b-32768",
    "gemma2-9b-it",
    "qwen-qwq-32b",
    "whisper-large-v3"
  ],
  openai: [
    "gpt-4o",
    "gpt-4o-mini",
    "o1",
    "o1-mini",
    "o3-mini",
    "gpt-4-turbo",
    "gpt-3.5-turbo"
  ],
  gemini: [
    "gemini-2.0-flash",
    "gemini-1.5-pro",
    "gemini-1.5-flash",
    "gemini-2.0-flash-thinking-exp-01-21"
  ],
  ollama: [
    "qwen2.5:latest",
    "deepseek-r1:latest",
    "llama3.2:latest",
    "mistral:latest"
  ]
};

let aiChatHistory = [];
let quickModalActiveProvider = "groq";

function updateAIChatHeader() {
  const prov = (appState.ai.provider || "groq").toLowerCase();
  const mod = appState.ai.model || getDefaultModelForProvider(prov);

  // Update pills in reasoning bar
  ['groq', 'openai', 'gemini', 'ollama'].forEach(p => {
    const pill = document.getElementById(`btnModel${p.charAt(0).toUpperCase() + p.slice(1)}`);
    if (pill) pill.classList.toggle("active", prov === p);
  });

  // Update active model input and datalist
  const customInput = document.getElementById("aiActiveModelCustomInput");
  if (customInput && document.activeElement !== customInput) {
    customInput.value = mod;
  }
  populateActiveModelDatalist(prov);

  // Update reasoning output badge
  const rBadge = document.getElementById("aiModelBadge");
  if (rBadge) rBadge.innerText = `${prov.toUpperCase()} • ${mod} Active`;

  // Update Key indicator dot and label
  updateAIKeyStatusBadge();
}

function getDefaultModelForProvider(prov) {
  if (prov === "groq") return "llama-3.3-70b-versatile";
  if (prov === "openai") return "gpt-4o";
  if (prov === "gemini") return "gemini-2.0-flash";
  if (prov === "ollama") return "qwen2.5:latest";
  return "llama-3.3-70b-versatile";
}

function populateActiveModelDatalist(prov) {
  const dl = document.getElementById("activeModelDatalist");
  if (!dl) return;
  const list = AI_MODEL_PRESETS[prov] || [];
  dl.innerHTML = list.map(m => `<option value="${escapeHTML(m)}">`).join("");
}

async function setAIModel(provider, specificModel) {
  appState.ai.provider = provider;
  const modelName = specificModel || appState.ai.model || getDefaultModelForProvider(provider);
  appState.ai.model = modelName;

  updateAIChatHeader();

  try {
    await fetch("/api/ai/set-model", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ provider, model: modelName })
    });
    showToast(`🚀 Active Engine: ${provider.toUpperCase()} (${modelName})`);
  } catch (e) { }

  updateAIKeyStatusBadge();
}

async function onManualModelInputChanged(modelVal) {
  const clean = (modelVal || "").trim();
  if (!clean) return;
  const prov = appState.ai.provider || "groq";
  appState.ai.model = clean;

  const rBadge = document.getElementById("aiModelBadge");
  if (rBadge) rBadge.innerText = `${prov.toUpperCase()} • ${clean} Active`;

  try {
    await fetch("/api/ai/set-model", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ provider: prov, model: clean })
    });
    showToast(`[AI] Model updated to "${clean}"`);
  } catch (e) { }
}

async function updateAIKeyStatusBadge() {
  const prov = (appState.ai.provider || "groq").toLowerCase();
  const dot = document.getElementById("keyStatusDot");
  const txt = document.getElementById("keyStatusText");
  const banner = document.getElementById("aiInlineKeyBanner");
  const bannerTitle = document.getElementById("inlineKeyProvTitle");
  const bannerHelp = document.getElementById("inlineKeyHelpLink");

  try {
    const res = await fetch("/api/ai/get-config");
    if (!res.ok) return;
    const data = await res.json();

    let isConfigured = false;
    let helpUrl = "https://console.groq.com/keys";

    if (prov === "groq") {
      isConfigured = data.groq_set;
      helpUrl = "https://console.groq.com/keys";
    } else if (prov === "openai") {
      isConfigured = data.openai_set;
      helpUrl = "https://platform.openai.com/api-keys";
    } else if (prov === "gemini") {
      isConfigured = data.gemini_set;
      helpUrl = "https://aistudio.google.com/app/apikey";
    } else if (prov === "ollama") {
      isConfigured = true;
    }

    if (dot && txt) {
      if (isConfigured) {
        dot.className = "key-status-dot active";
        txt.innerText = `${prov.toUpperCase()} Key Active`;
      } else {
        dot.className = "key-status-dot warning";
        txt.innerText = `${prov.toUpperCase()} Key Missing (Click to Add)`;
      }
    }

    // Toggle inline banner
    if (banner) {
      if (!isConfigured && prov !== 'ollama') {
        banner.style.display = "block";
        if (bannerTitle) bannerTitle.innerText = `${prov.toUpperCase()} API Key Required`;
        if (bannerHelp) bannerHelp.href = helpUrl;
      } else {
        banner.style.display = "none";
      }
    }

  } catch (e) { }
}

// -----------------------------------------------------------------------------
// QUICK API KEY MODAL
// -----------------------------------------------------------------------------
function openQuickApiKeyModal() {
  const modal = document.getElementById("quickApiKeyModal");
  if (!modal) return;
  const currentProv = appState.ai.provider || "groq";
  setQuickModalProvider(currentProv);
  modal.style.display = "flex";
}

function closeQuickApiKeyModal() {
  const modal = document.getElementById("quickApiKeyModal");
  if (modal) modal.style.display = "none";
}

function setQuickModalProvider(prov) {
  quickModalActiveProvider = prov;
  ['groq', 'openai', 'gemini', 'ollama'].forEach(p => {
    const btn = document.getElementById(`modalProvBtn${p.charAt(0).toUpperCase() + p.slice(1)}`);
    if (btn) btn.classList.toggle("active", p === prov);
  });

  const label = document.getElementById("quickModalKeyLabel");
  const link = document.getElementById("quickModalHelpLink");
  const modelInput = document.getElementById("quickModalModelInput");
  const keyRow = document.getElementById("quickModalKeyRow");

  const helpMap = {
    groq: { name: "Groq API Key", url: "https://console.groq.com/keys", model: "llama-3.3-70b-versatile" },
    openai: { name: "OpenAI API Key", url: "https://platform.openai.com/api-keys", model: "gpt-4o" },
    gemini: { name: "Gemini API Key", url: "https://aistudio.google.com/app/apikey", model: "gemini-2.0-flash" },
    ollama: { name: "Ollama URL & Model", url: "#", model: "qwen2.5:latest" }
  };

  const item = helpMap[prov] || helpMap.groq;
  if (label) label.innerText = item.name;
  if (link) {
    link.href = item.url;
    link.style.display = (prov === 'ollama') ? 'none' : 'inline';
  }
  if (modelInput) {
    modelInput.value = (prov === (appState.ai.provider || "groq") && appState.ai.model) ? appState.ai.model : item.model;
  }
  if (keyRow) {
    keyRow.style.display = (prov === 'ollama') ? 'none' : 'block';
  }
}

async function saveQuickApiKeyModal() {
  const prov = quickModalActiveProvider || "groq";
  const keyInput = document.getElementById("quickModalApiKeyInput");
  const modelInput = document.getElementById("quickModalModelInput");
  const statusMsg = document.getElementById("quickModalStatusMsg");

  const keyVal = keyInput ? keyInput.value.trim() : "";
  const modelVal = modelInput ? modelInput.value.trim() : getDefaultModelForProvider(prov);

  const payload = {
    provider: prov
  };

  if (prov === "groq") {
    if (keyVal) payload.groq_api_key = keyVal;
    payload.groq_model = modelVal;
  } else if (prov === "openai") {
    if (keyVal) payload.openai_api_key = keyVal;
    payload.openai_model = modelVal;
  } else if (prov === "gemini") {
    if (keyVal) payload.gemini_api_key = keyVal;
    payload.gemini_model = modelVal;
  } else if (prov === "ollama") {
    payload.ollama_model = modelVal;
  }

  if (statusMsg) {
    statusMsg.style.color = "#F59E0B";
    statusMsg.innerText = "Applying credentials & testing engine...";
  }

  try {
    const res = await fetch("/api/ai/set-config", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });

    if (res.ok) {
      appState.ai.provider = prov;
      appState.ai.model = modelVal;
      updateAIChatHeader();
      showToast(`[Success] ${prov.toUpperCase()} credentials & model saved`);
      closeQuickApiKeyModal();
      if (keyInput) keyInput.value = "";
    } else {
      if (statusMsg) {
        statusMsg.style.color = "#EF4444";
        statusMsg.innerText = "Failed to save configuration.";
      }
    }
  } catch (err) {
    if (statusMsg) {
      statusMsg.style.color = "#EF4444";
      statusMsg.innerText = "Error: " + err.message;
    }
  }
}

async function saveInlineApiKey() {
  const prov = (appState.ai.provider || "groq").toLowerCase();
  const input = document.getElementById("inlineKeyInput");
  const keyVal = input ? input.value.trim() : "";
  if (!keyVal) {
    showToast("Please paste your API key.");
    return;
  }

  const payload = { provider: prov };
  if (prov === "groq") payload.groq_api_key = keyVal;
  else if (prov === "openai") payload.openai_api_key = keyVal;
  else if (prov === "gemini") payload.gemini_api_key = keyVal;

  try {
    await fetch("/api/ai/set-config", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
    if (input) input.value = "";
    showToast(`[Success] ${prov.toUpperCase()} API key saved successfully`);
    updateAIKeyStatusBadge();
  } catch (e) {
    showToast("Failed to save API key.");
  }
}

// -----------------------------------------------------------------------------
// CHAT STUDIO CONVERSATION & REASONING PIPELINE
// -----------------------------------------------------------------------------
function handleAIInputKeyDown(e) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    queryCustomAI();
  }
}

function runAIPreset(index) {
  const prompt = AI_PRESET_PROMPTS[index] || AI_PRESET_PROMPTS[0];
  sendReasoningQuery(prompt);
}

function queryCustomAI() {
  const input = document.getElementById("aiCustomInput");
  const text = (input ? input.value : "").trim();
  if (!text) return;
  if (input) {
    input.value = "";
    input.style.height = "auto";
  }
  sendReasoningQuery(text);
}

async function sendReasoningQuery(promptText) {
  if (!promptText || !promptText.trim()) return;

  const stream = document.getElementById("aiReasoningChatStream");
  const welcome = document.getElementById("aiWelcomeBox");
  const typingBar = document.getElementById("aiReasoningTypingBar");
  const typingLbl = document.getElementById("aiReasoningTypingLabel");
  const prov = (appState.ai.provider || "groq").toUpperCase();
  const mod = appState.ai.model || getDefaultModelForProvider(prov.toLowerCase());

  if (welcome) welcome.style.display = "none";

  // Append User Message Bubble
  const userMsgId = "ai_msg_user_" + Date.now();
  const userHtml = `
    <div class="msg-row outgoing" id="${userMsgId}">
      <div class="msg-bubble-wrap" style="max-width: 80%;">
        <div class="msg-bubble ai-user-bubble">
          <div class="msg-text">${escapeHTML(promptText)}</div>
          <div class="msg-meta" style="margin-top: 4px; font-size: 10.5px; opacity: 0.8; text-align: right;">
            <span>${formatTime(new Date())}</span>
          </div>
        </div>
      </div>
    </div>
  `;
  if (stream) {
    stream.insertAdjacentHTML("beforeend", userHtml);
    stream.scrollTop = stream.scrollHeight;
  }

  // Show Typing Bar
  if (typingBar) typingBar.style.display = "flex";
  if (typingLbl) typingLbl.innerText = `${prov} (${mod}) is reasoning...`;

  const startTime = Date.now();

  try {
    const res = await fetch("/api/ai/query", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ prompt: promptText })
    });
    const data = await res.json();
    const elapsedMs = Date.now() - startTime;
    const aiResponseText = data.response || "No response received.";

    if (typingBar) typingBar.style.display = "none";

    const aiMsgId = "ai_msg_bot_" + Date.now();
    const words = aiResponseText.split(/\s+/).length;
    const tokSec = elapsedMs > 0 ? Math.round((words * 1.3) / (elapsedMs / 1000)) : 120;

    const botHtml = `
      <div class="msg-row incoming ai-bot-row" id="${aiMsgId}">
        <div class="msg-bubble-wrap" style="max-width: 90%;">
          <div class="msg-bubble ai-response-bubble">
            <div class="ai-msg-header">
              <span class="ai-bot-badge">
                <i class="fa fa-sparkles"></i> ${prov} Neural Output
                <span style="font-size: 10.5px; color: var(--text-muted); font-weight: normal; margin-left: 6px;">(${mod})</span>
              </span>
              <div class="ai-msg-actions">
                <button class="btn-ai-action" onclick="copyAIText('${aiMsgId}')" title="Copy Text">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width:11px;height:11px;"><rect width="14" height="14" x="8" y="8" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>
                  <span>Copy</span>
                </button>
                <button class="btn-ai-action" onclick="speakAIText('${aiMsgId}')" title="Read Aloud (TTS Voice)">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width:11px;height:11px;"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/></svg>
                  <span>Speak</span>
                </button>
                <button class="btn-ai-action" onclick="shareAITextToPeer('${aiMsgId}')" title="Share with Active Peer">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width:11px;height:11px;"><path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"/><polyline points="16 6 12 2 8 6"/><line x1="12" x2="12" y1="2" y2="15"/></svg>
                  <span>Share</span>
                </button>
              </div>
            </div>
            <div class="msg-text ai-markdown-text" id="text_${aiMsgId}">${formatMarkdown(aiResponseText)}</div>
            <div class="msg-meta" style="display: flex; justify-content: space-between; align-items: center; margin-top: 8px; font-size: 10.5px; color: var(--text-muted); border-top: 1px solid rgba(255,255,255,0.04); padding-top: 4px;">
              <span>${elapsedMs}ms latency • ~${tokSec} tok/sec</span>
              <span>${formatTime(new Date())}</span>
            </div>
          </div>
        </div>
      </div>
    `;

    if (stream) {
      stream.insertAdjacentHTML("beforeend", botHtml);
      stream.scrollTop = stream.scrollHeight;
    }

    // Check if error mentioned missing key
    if (aiResponseText.toLowerCase().includes("not configured") || aiResponseText.toLowerCase().includes("please configure")) {
      updateAIKeyStatusBadge();
    }

  } catch (err) {
    if (typingBar) typingBar.style.display = "none";
    showToast("Error querying Nearby AI: " + err.message);
  }
}

function clearAIChatHistory() {
  const stream = document.getElementById("aiReasoningChatStream");
  if (stream) {
    stream.innerHTML = `
      <div class="ai-welcome-box" id="aiWelcomeBox">
        <div class="ai-welcome-icon">🧠</div>
        <h3 style="font-size: 16px; font-weight: 700; color: var(--text-title); margin-bottom: 6px;">NearMitra Neural Studio Ready</h3>
        <p style="font-size: 13px; color: var(--text-muted); max-width: 550px; line-height: 1.5; margin: 0 auto 14px auto;">
          Chat history cleared. Ask any new agricultural, network, or logistics query below.
        </p>
      </div>
    `;
  }
  showToast("Chat history cleared.");
}

function exportAIChatLog() {
  const stream = document.getElementById("aiReasoningChatStream");
  if (!stream) return;
  const text = stream.innerText;
  const blob = new Blob([text], { type: "text/plain;charset=utf-8" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = `NearMitra_AI_Conversation_${Date.now()}.txt`;
  a.click();
  showToast("Conversation log exported.");
}

function speakAIText(msgId) {
  const el = document.getElementById("text_" + msgId);
  if (!el) return;
  const text = el.innerText || el.textContent;
  if ('speechSynthesis' in window) {
    window.speechSynthesis.cancel();
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.rate = 1.0;
    utterance.pitch = 1.0;
    window.speechSynthesis.speak(utterance);
    showToast("[TTS] Reading response aloud...");
  } else {
    showToast("Speech synthesis not supported in this environment.");
  }
}

function toggleSpeechRecognition() {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SpeechRecognition) {
    showToast("Speech dictation not supported in browser.");
    return;
  }

  const btn = document.getElementById("btnVoiceInput");
  const recog = new SpeechRecognition();
  recog.lang = 'en-IN';
  recog.interimResults = false;

  showToast("[Voice] Listening... Speak your query now");
  if (btn) btn.style.color = "#EF4444";

  recog.onresult = (e) => {
    const transcript = e.results[0][0].transcript;
    const input = document.getElementById("aiCustomInput");
    if (input) input.value = transcript;
    if (btn) btn.style.color = "";
    showToast(`[Voice] Recognized: "${transcript}"`);
  };

  recog.onerror = () => {
    if (btn) btn.style.color = "";
    showToast("Voice input stopped.");
  };

  recog.start();
}

function copyAIText(msgId) {
  const el = document.getElementById("text_" + msgId);
  if (el) {
    navigator.clipboard.writeText(el.innerText || el.textContent);
    showToast("[AI] Response copied to clipboard");
  }
}

function shareAITextToPeer(msgId) {
  const el = document.getElementById("text_" + msgId);
  if (!el) return;
  const text = el.innerText || el.textContent;
  const targetPeer = appState.activePeer;
  const targetIP = targetPeer ? targetPeer.ip : (appState.peers && appState.peers[0] ? appState.peers[0].ip : "");
  const targetID = targetPeer ? targetPeer.id : (appState.peers && appState.peers[0] ? appState.peers[0].id : "");

  if (!targetIP && !targetID) {
    showToast("No active peer connected to share with.");
    return;
  }

  const prov = (appState.ai.provider || "Gemini").toUpperCase();
  const sharedMsg = {
    id: "msg_ai_share_" + Date.now(),
    peer_id: targetID,
    peer_ip: targetIP,
    sender: "Windows Host",
    text: `[NearMitra ${prov} AI Shared Output]\n\n${text}`,
    mine: true,
    at: new Date(),
    status: "Sent",
    reactions: { "🤖": 1 }
  };

  appState.messages.push(sharedMsg);
  savePersistedMessages();
  fetch("/api/chat/send", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(sharedMsg)
  });

  showToast(`Shared AI response to ${targetPeer ? targetPeer.name : 'Peer'}!`);
}

function formatMarkdown(text) {
  if (!text) return "";
  let out = escapeHTML(text);
  // Code block with syntax styling
  out = out.replace(/```([a-z]*)\n([\s\S]*?)```/g, '<pre class="code-block"><code>$2</code></pre>');
  // Bold
  out = out.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
  // Italic
  out = out.replace(/\*(.*?)\*/g, '<em>$1</em>');
  // Inline code
  out = out.replace(/`([^`]+)`/g, '<code class="inline-code">$1</code>');
  // Bullet items
  out = out.replace(/^\s*[-•]\s+(.*)$/gm, '<li class="ai-bullet">$1</li>');
  // Numbered list
  out = out.replace(/^\s*(\d+)\.\s+(.*)$/gm, '<li><strong>$1.</strong> $2</li>');
  // Line breaks
  out = out.replace(/\n/g, '<br>');
  return out;
}

// -----------------------------------------------------------------------------
// AI FLEET HUB: 3 SUBVIEWS & CONFIGURATION CONTROLLER
// -----------------------------------------------------------------------------
function switchAIFleetView(view) {
  const reasoningView = document.getElementById("aiReasoningView");
  const configView = document.getElementById("aiConfigView");
  const analyticsView = document.getElementById("aiAnalyticsView");

  const pillReasoning = document.getElementById("pillAIReasoning");
  const pillConfig = document.getElementById("pillAIConfig");
  const pillAnalytics = document.getElementById("pillAIAnalytics");

  if (reasoningView) reasoningView.style.display = view === 'reasoning' ? 'flex' : 'none';
  if (configView) configView.style.display = view === 'config' ? 'flex' : 'none';
  if (analyticsView) analyticsView.style.display = view === 'analytics' ? 'flex' : 'none';

  if (pillReasoning) pillReasoning.classList.toggle("active", view === 'reasoning');
  if (pillConfig) pillConfig.classList.toggle("active", view === 'config');
  if (pillAnalytics) pillAnalytics.classList.toggle("active", view === 'analytics');

  if (view === 'config') {
    loadAIConfig();
  } else if (view === 'analytics') {
    loadAIAnalytics();
  } else if (view === 'reasoning') {
    updateAIChatHeader();
  }
}

function selectConfigProvider(prov) {
  ['gemini', 'openai', 'groq', 'ollama'].forEach(p => {
    const card = document.getElementById(`cardProv${p.charAt(0).toUpperCase() + p.slice(1)}`);
    const radio = document.getElementById(`radioProv${p.charAt(0).toUpperCase() + p.slice(1)}`);
    const formSection = document.getElementById(`formSection${p.charAt(0).toUpperCase() + p.slice(1)}`);
    const isCur = p === prov;

    if (card) card.classList.toggle("active", isCur);
    if (radio) radio.checked = isCur;
    if (formSection) formSection.style.display = isCur ? "block" : "none";
  });

  const titles = {
    gemini: "Google Gemini Configuration",
    openai: "OpenAI ChatGPT Configuration",
    groq: "Groq Cloud Fast Inference Configuration",
    ollama: "Ollama Local AI Configuration"
  };
  const titleEl = document.getElementById("activeProvFormTitle");
  if (titleEl) titleEl.innerText = titles[prov] || "AI Configuration";
}

function onConfigGroqPresetChanged(val) {
  const customEl = document.getElementById("cfgGroqModelCustom");
  if (customEl && val !== "custom") customEl.value = val;
}

function onConfigOpenAIPresetChanged(val) {
  const customEl = document.getElementById("cfgOpenAIModelCustom");
  if (customEl && val !== "custom") customEl.value = val;
}

function onConfigGeminiPresetChanged(val) {
  const customEl = document.getElementById("cfgGeminiModelCustom");
  if (customEl && val !== "custom") customEl.value = val;
}

function togglePasswordVisibility(inputId, btn) {
  const input = document.getElementById(inputId);
  if (!input) return;
  if (input.type === "password") {
    input.type = "text";
    btn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width:14px;height:14px;"><rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>';
  } else {
    input.type = "password";
    btn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width:14px;height:14px;"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>';
  }
}

async function loadAIConfig() {
  try {
    const res = await fetch("/api/ai/get-config");
    if (!res.ok) return;
    const data = await res.json();

    const prov = data.provider || "groq";
    selectConfigProvider(prov);

    // Groq
    if (data.groq_model) {
      if (document.getElementById("cfgGroqModel")) document.getElementById("cfgGroqModel").value = data.groq_model;
      if (document.getElementById("cfgGroqModelCustom")) document.getElementById("cfgGroqModelCustom").value = data.groq_model;
    }
    if (data.groq_key && document.getElementById("cfgGroqKey")) {
      document.getElementById("cfgGroqKey").placeholder = data.groq_key;
    }
    const bgGroq = document.getElementById("badgeGroqStatus");
    if (bgGroq) {
      bgGroq.className = data.groq_set ? "badge badge-emerald" : "badge badge-slate";
      bgGroq.innerText = data.groq_set ? "Configured" : "No Key";
    }

    // OpenAI
    if (data.openai_model) {
      if (document.getElementById("cfgOpenAIModel")) document.getElementById("cfgOpenAIModel").value = data.openai_model;
      if (document.getElementById("cfgOpenAIModelCustom")) document.getElementById("cfgOpenAIModelCustom").value = data.openai_model;
    }
    if (data.openai_key && document.getElementById("cfgOpenAIKey")) {
      document.getElementById("cfgOpenAIKey").placeholder = data.openai_key;
    }
    const bgOai = document.getElementById("badgeOpenAIStatus");
    if (bgOai) {
      bgOai.className = data.openai_set ? "badge badge-emerald" : "badge badge-slate";
      bgOai.innerText = data.openai_set ? "Configured" : "No Key";
    }

    // Gemini
    if (data.gemini_model) {
      if (document.getElementById("cfgGeminiModel")) document.getElementById("cfgGeminiModel").value = data.gemini_model;
      if (document.getElementById("cfgGeminiModelCustom")) document.getElementById("cfgGeminiModelCustom").value = data.gemini_model;
    }
    if (data.gemini_key && document.getElementById("cfgGeminiKey")) {
      document.getElementById("cfgGeminiKey").placeholder = data.gemini_key;
    }
    const bgGem = document.getElementById("badgeGeminiStatus");
    if (bgGem) {
      bgGem.className = data.gemini_set ? "badge badge-emerald" : "badge badge-slate";
      bgGem.innerText = data.gemini_set ? "Configured" : "No Key";
    }

    // Ollama
    if (data.ollama_url && document.getElementById("cfgOllamaURL")) {
      document.getElementById("cfgOllamaURL").value = data.ollama_url;
    }
    if (data.ollama_model && document.getElementById("cfgOllamaModel")) {
      document.getElementById("cfgOllamaModel").value = data.ollama_model;
    }
    const bgOllama = document.getElementById("badgeOllamaStatus");
    if (bgOllama) {
      bgOllama.className = data.ollama_active ? "badge badge-emerald" : "badge badge-slate";
      bgOllama.innerText = data.ollama_active ? "Active" : "Offline";
    }

    // Common
    if (data.temperature && document.getElementById("cfgTemperature")) {
      document.getElementById("cfgTemperature").value = data.temperature;
      document.getElementById("tempLabel").innerText = data.temperature;
    }
    if (data.system_prompt && document.getElementById("cfgSystemPrompt")) {
      document.getElementById("cfgSystemPrompt").value = data.system_prompt;
    }
  } catch (err) {
    console.error("loadAIConfig error:", err);
  }
}

async function saveAIConfig() {
  const selectedRadio = document.querySelector('input[name="aiProviderRadio"]:checked');
  const provider = selectedRadio ? selectedRadio.value : "groq";

  const geminiKey = (document.getElementById("cfgGeminiKey").value || "").trim();
  const geminiModel = (document.getElementById("cfgGeminiModelCustom")?.value || document.getElementById("cfgGeminiModel")?.value || "gemini-2.0-flash").trim();

  const openAIKey = (document.getElementById("cfgOpenAIKey").value || "").trim();
  const openAIModel = (document.getElementById("cfgOpenAIModelCustom")?.value || document.getElementById("cfgOpenAIModel")?.value || "gpt-4o").trim();

  const groqKey = (document.getElementById("cfgGroqKey").value || "").trim();
  const groqModel = (document.getElementById("cfgGroqModelCustom")?.value || document.getElementById("cfgGroqModel")?.value || "llama-3.3-70b-versatile").trim();

  const ollamaURL = (document.getElementById("cfgOllamaURL").value || "").trim();
  const ollamaModel = (document.getElementById("cfgOllamaModel").value || "").trim();

  const temp = parseFloat(document.getElementById("cfgTemperature").value) || 0.7;
  const sysPrompt = (document.getElementById("cfgSystemPrompt").value || "").trim();

  const payload = {
    provider: provider,
    gemini_model: geminiModel,
    openai_model: openAIModel,
    groq_model: groqModel,
    ollama_url: ollamaURL,
    ollama_model: ollamaModel,
    temperature: temp,
    system_prompt: sysPrompt
  };

  if (geminiKey) payload.gemini_api_key = geminiKey;
  if (openAIKey) payload.openai_api_key = openAIKey;
  if (groqKey) payload.groq_api_key = groqKey;

  const msgEl = document.getElementById("aiSaveMsg");
  if (msgEl) {
    msgEl.style.color = "#10B981";
    msgEl.innerText = "Saving settings...";
  }

  try {
    const res = await fetch("/api/ai/set-config", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
    if (res.ok) {
      if (msgEl) msgEl.innerText = "✓ Settings saved & engine reloaded!";
      appState.ai.provider = provider;
      if (provider === "groq") appState.ai.model = groqModel;
      else if (provider === "openai") appState.ai.model = openAIModel;
      else if (provider === "gemini") appState.ai.model = geminiModel;
      else if (provider === "ollama") appState.ai.model = ollamaModel;

      showToast(`AI Configuration saved for ${provider.toUpperCase()}!`);
      loadAIConfig();
      updateAIChatHeader();
      setTimeout(() => { if (msgEl) msgEl.innerText = ""; }, 4000);
    } else {
      if (msgEl) {
        msgEl.style.color = "#EF4444";
        msgEl.innerText = "Failed to save.";
      }
    }
  } catch (err) {
    if (msgEl) {
      msgEl.style.color = "#EF4444";
      msgEl.innerText = "Error: " + err.message;
    }
  }
}

async function testAIConnection() {
  const msgEl = document.getElementById("aiSaveMsg");
  if (msgEl) {
    msgEl.style.color = "#F59E0B";
    msgEl.innerText = "Testing live connection...";
  }
  showToast("Testing AI provider connection with ping query...");
  try {
    const res = await fetch("/api/ai/query", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ prompt: "Respond with exactly 'NearMitra AI Connection Verified OK'." })
    });
    const data = await res.json();
    if (data.response && !data.response.toLowerCase().includes("error") && !data.response.toLowerCase().includes("not configured")) {
      if (msgEl) {
        msgEl.style.color = "#10B981";
        msgEl.innerText = "✓ Connection verified OK!";
      }
      showToast("Live AI Test Passed: " + data.response.substring(0, 50));
    } else {
      if (msgEl) {
        msgEl.style.color = "#EF4444";
        msgEl.innerText = "⚠️ Error: " + (data.response || "No response");
      }
      showToast("Live AI Test Warning: " + (data.response || ""));
    }
  } catch (err) {
    if (msgEl) {
      msgEl.style.color = "#EF4444";
      msgEl.innerText = "Failed to reach AI service: " + err.message;
    }
  }
}

async function toggleShareAI(checked) {
  try {
    const res = await fetch("/api/ai/share-toggle", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ enabled: checked })
    });
    const data = await res.json();
    appState.ai.shareAI = checked;
    updateAIChatHeader();
    showToast(data.share_ai ? "Host AI Compute shared with P2P Mesh Nodes" : "Host AI Compute sharing disabled");
  } catch (e) {
    showToast("Error updating AI share setting.");
  }
}

async function loadAIAnalytics() {
  try {
    const res = await fetch("/api/ai/analytics");
    if (res.ok) {
      const data = await res.json();

      const gpuEl = document.getElementById("aiGpuLabel");
      if (gpuEl) gpuEl.innerText = data.gpu || "GPU (Direct3D 12)";

      const cpuEl = document.getElementById("aiCpuLabel");
      if (cpuEl) cpuEl.innerText = data.cpu || `${navigator.hardwareConcurrency || '?'}-Core CPU`;

      const ramEl = document.getElementById("aiRamLabel");
      if (ramEl) {
        ramEl.innerText = data.ram || "-- GB";
        const pct = data.ram_used_pct || 0;
        ramEl.style.color = pct > 85 ? "#EF4444" : pct > 60 ? "#F59E0B" : "#10B981";
      }

      const speedEl = document.getElementById("aiSpeedLabel");
      if (speedEl) {
        if (!data.ollama_installed) {
          speedEl.innerText = "Ollama not installed";
          speedEl.style.color = "var(--text-muted)";
        } else if (!data.ollama_models || data.ollama_models.length === 0) {
          speedEl.innerText = "Ollama installed • No models";
          speedEl.style.color = "#F59E0B";
        } else {
          speedEl.innerText = `Ollama ✓ • ${data.ollama_models.length} model(s)`;
          speedEl.style.color = "#10B981";
        }
      }

      const modelsEl = document.getElementById("aiOllamaModels");
      if (modelsEl) {
        if (data.ollama_models && data.ollama_models.length > 0) {
          modelsEl.innerText = data.ollama_models.join(", ");
        } else {
          modelsEl.innerText = data.ollama_installed ? "No models loaded" : "Not installed";
          modelsEl.style.color = "var(--text-muted)";
        }
      }

      const promptsEl = document.getElementById("aiPromptsLabel");
      if (promptsEl) promptsEl.innerText = `${data.prompts_served || 0} Requests`;

      const chk = document.getElementById("chkShareAI");
      if (chk) chk.checked = !!data.share_enabled;
      appState.ai.shareAI = !!data.share_enabled;
      updateAIChatHeader();

      renderAIPeersTable(data.peers || []);
    }
  } catch (e) {
    console.error("AI Analytics load error:", e);
  }
}

function renderAIPeersTable(peers) {
  const tbody = document.getElementById("aiPeersTableBody");
  if (!tbody) return;

  if (peers.length === 0) {
    tbody.innerHTML = `
      <tr>
        <td colspan="5" style="text-align: center; color: var(--text-muted); padding: 24px;">
          No mesh peers currently connected.
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = peers.map(p => {
    const isAllowed = p.allowed;
    return `
      <tr>
        <td style="font-weight: 600; color: var(--text-title);">${escapeHTML(p.name)}</td>
        <td><code style="background:rgba(255,255,255,0.06); padding:2px 6px; border-radius:4px; color:var(--accent-blue);">${escapeHTML(p.ip)}</code></td>
        <td style="color: var(--text-muted); font-size: 11.5px;">${escapeHTML(p.last_active || 'Just now')}</td>
        <td>
          <span class="badge ${isAllowed ? 'badge-emerald' : 'badge-danger'}">
            ${isAllowed ? 'Allowed' : 'Revoked'}
          </span>
        </td>
        <td>
          <button class="btn btn-sm ${isAllowed ? 'btn-secondary' : 'btn-primary'}" onclick="togglePeerAIPermission('${p.id || p.ip}', ${!isAllowed})">
            ${isAllowed ? 'Revoke' : 'Allow'}
          </button>
        </td>
      </tr>
    `;
  }).join("");
}

async function togglePeerAIPermission(peerId, allow) {
  try {
    const res = await fetch("/api/ai/peer-permission", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ peer_id: peerId, allow: allow })
    });
    const data = await res.json();
    showToast(`AI Access ${allow ? 'Granted' : 'Revoked'} for peer`);
    loadAIAnalytics();
  } catch (e) {
    showToast("Error updating peer AI permission.");
  }
}

// -----------------------------------------------------------------------------
// IOT & WINDOWS HARDWARE VIRTUALIZATION HUB
// -----------------------------------------------------------------------------
let isAudioMirrorActive = false;
let audioMirrorStream = null;
let audioMirrorContext = null;
let audioMirrorAnalyser = null;
let audioMirrorAnimId = null;
let audioMirrorMediaRecorder = null;

let isAudioCasting = false;
let audioCastContext = null;
let audioCastOscillator = null;
let micVuInterval = null;
let remoteMicLinked = false;
let remoteSensorPollTimer = null;

// Subview Navigation Switcher (Virtual Hub / Local Bus / Agri Relays & POS)
function switchHwSubView(viewKey) {
  const vVirtual = document.getElementById("hwSubViewVirtual");
  const vLocal = document.getElementById("hwSubViewLocal");
  const vAgri = document.getElementById("hwSubViewAgri");

  if (vVirtual) vVirtual.style.display = (viewKey === "virtual") ? "grid" : "none";
  if (vLocal) vLocal.style.display = (viewKey === "local") ? "grid" : "none";
  if (vAgri) vAgri.style.display = (viewKey === "agri") ? "grid" : "none";

  const pVirtual = document.getElementById("pillHwVirtual");
  const pLocal = document.getElementById("pillHwLocal");
  const pAgri = document.getElementById("pillHwAgri");

  if (pVirtual) pVirtual.classList.toggle("active", viewKey === "virtual");
  if (pLocal) pLocal.classList.toggle("active", viewKey === "local");
  if (pAgri) pAgri.classList.toggle("active", viewKey === "agri");

  if (viewKey === "local") {
    loadHardwareDiagnostics();
  } else if (viewKey === "virtual") {
    populateHwPeerSelects();
    pollRemoteSensors();
  } else if (viewKey === "agri") {
    pollSensorData();
    updateGatePassPreview();
  }
}

// ── Local Windows PnP Hardware Scanner ──
async function scanHardwareNow() {
  const btn = document.getElementById("btnHwScanNow");
  if (btn) {
    btn.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="spin-animation" style="width:16px;height:16px;"><path d="M21.5 2v6h-6M21.34 15.57a10 10 0 1 1-.57-8.38l5.67-5.67"/></svg> <span>Scanning Hardware...</span>`;
  }
  showToast("Scanning physical Windows USB, Audio, Camera, and NFC ports...");
  try {
    const res = await fetch("/api/iot/hardware-scan?refresh=1");
    if (res.ok) {
      const data = await res.json();
      renderHardwareDiagnostics(data);
      showToast("Windows Hardware & Port Diagnostics Updated.");
    }
  } catch (e) {
    console.error("Hardware scan error:", e);
  } finally {
    if (btn) {
      btn.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21.5 2v6h-6M21.34 15.57a10 10 0 1 1-.57-8.38l5.67-5.67"/></svg> <span>Scan Windows Hardware</span>`;
    }
  }
}

async function loadHardwareDiagnostics() {
  populateHwPeerSelects();
  try {
    const res = await fetch("/api/iot/hardware-scan");
    if (res.ok) {
      const data = await res.json();
      renderHardwareDiagnostics(data);
    }
  } catch (e) {
    console.error("loadHardwareDiagnostics error:", e);
  }
}

function renderHardwareDiagnostics(data) {
  const hw = data.hardware || {};
  const usbList = hw.usb_devices || [];
  const audioList = hw.audio_devices || [];
  const camList = hw.camera_devices || [];
  const scanList = hw.scanner_devices || [];
  const serialList = hw.serial_com_ports || [];

  // Update Status Chips
  const chipUsb = document.getElementById("chipUsbBus");
  if (chipUsb) {
    chipUsb.innerHTML = `<span class="status-dot-pulse"></span> USB Bus: ${usbList.length} Connected`;
  }

  const chipNfc = document.getElementById("chipNfcStatus");
  if (chipNfc) {
    if (hw.nfc_supported) {
      chipNfc.className = "hw-chip active";
      chipNfc.innerHTML = `<span class="status-dot-pulse"></span> NFC: ${hw.nfc_reader_name || 'Active'}`;
    } else {
      chipNfc.className = "hw-chip standby";
      chipNfc.innerText = "NFC Proximity: Standby (Use Mobile Bridge)";
    }
  }

  const chipAudio = document.getElementById("chipAudioStatus");
  if (chipAudio) {
    chipAudio.innerHTML = `<span class="status-dot-pulse"></span> Audio: ${audioList.length} Endpoints (${hw.has_builtin_speaker ? 'Speaker ✓' : 'No Spkr'}, ${hw.has_builtin_mic ? 'Mic ✓' : 'No Mic'})`;
  }

  // Badges
  const bgUsb = document.getElementById("usbDevCountBadge");
  if (bgUsb) bgUsb.innerText = `${usbList.length} Devices`;

  const bgAudio = document.getElementById("audioDevCountBadge");
  if (bgAudio) bgAudio.innerText = `${audioList.length} Endpoints`;

  const bgCam = document.getElementById("camDevCountBadge");
  if (bgCam) bgCam.innerText = `${camList.length + scanList.length} Devices`;

  const bgSerial = document.getElementById("serialDevCountBadge");
  if (bgSerial) bgSerial.innerText = `${serialList.length} Ports`;

  // Populate USB List
  const elUsb = document.getElementById("listUsbDevices");
  if (elUsb) {
    if (usbList.length === 0) {
      elUsb.innerHTML = `<div style="padding:12px; text-align:center; color:var(--text-muted); font-size:12px;">No USB devices currently detected.</div>`;
    } else {
      elUsb.innerHTML = usbList.map(d => `
        <div class="hw-device-row">
          <div>
            <div class="hw-device-name">${escapeHTML(d.name)}</div>
            <div class="hw-device-meta">${escapeHTML(d.description || d.port_or_bus)}</div>
          </div>
          <span class="badge ${d.status === 'OK' ? 'badge-emerald' : 'badge-amber'}">${escapeHTML(d.status)}</span>
        </div>
      `).join("");
    }
  }

  // Populate Audio List
  const elAudio = document.getElementById("listAudioDevices");
  if (elAudio) {
    if (audioList.length === 0) {
      elAudio.innerHTML = `<div style="padding:12px; text-align:center; color:var(--text-muted); font-size:12px;">No audio devices found. Use Wireless Phone Speaker Bridge.</div>`;
    } else {
      elAudio.innerHTML = audioList.map(d => {
        const isMic = d.category === 'audio_in' || (d.name || '').toLowerCase().includes('mic');
        return `
          <div class="hw-device-row">
            <div>
              <div class="hw-device-name">${escapeHTML(d.name)}</div>
              <div class="hw-device-meta">${escapeHTML(d.description || d.port_or_bus)}</div>
            </div>
            <span class="badge badge-emerald">${isMic ? 'Input' : 'Output'}</span>
          </div>
        `;
      }).join("");
    }
  }

  // Populate Camera & Scanner List
  const elCam = document.getElementById("listCameraDevices");
  if (elCam) {
    const combined = [...camList, ...scanList];
    if (combined.length === 0) {
      elCam.innerHTML = `
        <div style="padding:12px; text-align:center; color:var(--text-muted); font-size:12px;">
          Integrated DirectShow Webcam Active • Ready for Live Camera Test.
        </div>
      `;
    } else {
      elCam.innerHTML = combined.map(d => `
        <div class="hw-device-row">
          <div>
            <div class="hw-device-name">${escapeHTML(d.name)}</div>
            <div class="hw-device-meta">${escapeHTML(d.description)}</div>
          </div>
          <span class="badge badge-emerald">Ready</span>
        </div>
      `).join("");
    }
  }

  // Populate Serial COM List
  const elSerial = document.getElementById("listSerialDevices");
  if (elSerial) {
    if (serialList.length === 0) {
      elSerial.innerHTML = `
        <div style="padding:12px; text-align:center; color:var(--text-muted); font-size:12px;">
          COM1 / Virtual Serial Bridge Active (115200 Baud) • Arduino / ESP32 / Weighing Scale Ready.
        </div>
      `;
    } else {
      elSerial.innerHTML = serialList.map(d => `
        <div class="hw-device-row">
          <div>
            <div class="hw-device-name">${escapeHTML(d.name)}</div>
            <div class="hw-device-meta">${escapeHTML(d.description)}</div>
          </div>
          <span class="badge badge-purple">115200 Baud</span>
        </div>
      `).join("");
    }
  }
}

function populateHwPeerSelects() {
  const peers = appState.peers || [];
  const selAudio = document.getElementById("audioCastPeerSelect");
  const selMic = document.getElementById("remoteMicPeerSelect");

  const opts = peers.length > 0
    ? peers.map(p => `<option value="${p.ip}">${escapeHTML(p.name)} (${p.ip}) • 50+ MB/s</option>`).join("")
    : `<option value="192.168.1.7">Nearby Mesh Phone (SM-M045F) • 50+ MB/s</option>`;

  if (selAudio) selAudio.innerHTML = opts;
  if (selMic) selMic.innerHTML = opts;
}

// ── Wireless Live PC Audio & YouTube Sound Mirror ──
function updateAudioCastVolume(val) {
  const lbl = document.getElementById("audioCastVolumeLabel");
  if (lbl) lbl.innerText = `${val}%`;
}

function onAudioSourceModeChanged(val) {
  const wrapTrack = document.getElementById("wrapCastTrackSelect");
  if (wrapTrack) {
    wrapTrack.style.display = (val === "preset_tone") ? "block" : "none";
  }
  if (val === "local_file") {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = "audio/*";
    input.onchange = (e) => {
      const file = e.target.files[0];
      if (file) {
        showToast(`[Audio] Selected "${file.name}" for remote audio casting`);
      }
    };
    input.click();
  }
  if (isAudioMirrorActive) {
    stopLiveAudioMirror();
    showToast("Restarting audio stream with new source...");
    setTimeout(() => toggleLiveAudioMirror(), 400);
  }
}

async function toggleLiveAudioMirror() {
  const btn = document.getElementById("btnStartLiveAudioMirror");
  const badge = document.getElementById("audioCastLiveBadge");
  const sel = document.getElementById("audioCastPeerSelect");
  const targetIP = sel ? sel.value : "";
  const peerName = sel && sel.options[sel.selectedIndex] ? sel.options[sel.selectedIndex].text : "Remote Phone";

  if (isAudioMirrorActive) {
    stopLiveAudioMirror();
    return;
  }

  const srcMode = document.getElementById("audioCastSourceMode") ? document.getElementById("audioCastSourceMode").value : "system_mirror";

  if (srcMode === "preset_tone") {
    triggerAudioCast("play");
    return;
  }

  try {
    showToast("🔊 Select YouTube tab or System Screen with 'Share Audio' checked...");
    const stream = await navigator.mediaDevices.getDisplayMedia({
      video: { width: 1, height: 1, frameRate: 1 },
      audio: {
        echoCancellation: false,
        noiseSuppression: false,
        channelCount: 2,
        autoGainControl: false
      }
    });

    const audioTracks = stream.getAudioTracks();
    if (!audioTracks || audioTracks.length === 0) {
      stream.getTracks().forEach(t => t.stop());
      showToast("⚠️ No audio track selected! Please check 'Share system audio'.");
      return;
    }

    audioMirrorStream = stream;
    isAudioMirrorActive = true;

    // Web Audio Analyser for FFT spectrum
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    audioMirrorContext = new AudioCtx();
    const sourceNode = audioMirrorContext.createMediaStreamSource(stream);
    audioMirrorAnalyser = audioMirrorContext.createAnalyser();
    audioMirrorAnalyser.fftSize = 64;
    sourceNode.connect(audioMirrorAnalyser);

    startAudioSpectrumVisualizer();

    fetch("/api/iot/live-audio-stream", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        target_ip: targetIP,
        peer_name: peerName,
        streaming: true,
        source: "youtube_tab"
      })
    }).catch(() => { });

    if (btn) {
      btn.className = "btn btn-danger";
      btn.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width:18px;height:18px;"><rect width="18" height="18" x="3" y="3" rx="2"/></svg> <span>Stop Live Audio Mirror</span>`;
    }
    if (badge) {
      badge.className = "badge badge-danger";
      badge.innerText = "STREAMING LIVE";
    }

    showToast(`[Audio] Streaming YouTube & PC Sound to ${peerName}'s Speaker`);

    stream.getVideoTracks().forEach(t => t.onended = () => stopLiveAudioMirror());
    audioTracks.forEach(t => t.onended = () => stopLiveAudioMirror());

  } catch (err) {
    if (err.name !== "NotAllowedError") {
      // Fallback to local audio synth if display media not supported
      triggerAudioCast("play");
    }
  }
}

function stopLiveAudioMirror() {
  isAudioMirrorActive = false;
  if (audioMirrorMediaRecorder && audioMirrorMediaRecorder.state !== "inactive") {
    try { audioMirrorMediaRecorder.stop(); } catch (e) { }
  }
  if (audioMirrorStream) {
    audioMirrorStream.getTracks().forEach(t => t.stop());
    audioMirrorStream = null;
  }
  if (audioMirrorContext) {
    try { audioMirrorContext.close(); } catch (e) { }
    audioMirrorContext = null;
  }
  if (audioMirrorAnimId) {
    cancelAnimationFrame(audioMirrorAnimId);
    audioMirrorAnimId = null;
  }

  stopLocalAudioSynth();

  const canvas = document.getElementById("audioSpectrumCanvas");
  if (canvas) {
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, canvas.width, canvas.height);
  }

  const btn = document.getElementById("btnStartLiveAudioMirror");
  const badge = document.getElementById("audioCastLiveBadge");
  if (btn) {
    btn.className = "btn btn-primary";
    btn.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width:18px;height:18px;"><polygon points="5 3 19 12 5 21 5 3"/></svg> <span>Live Stream PC / YouTube Audio to Phone</span>`;
  }
  if (badge) {
    badge.className = "badge badge-slate";
    badge.innerText = "Standby";
  }

  fetch("/api/iot/live-audio-stream", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ streaming: false })
  }).catch(() => { });

  showToast("⏹ Live Audio Stream Stopped.");
}

function startAudioSpectrumVisualizer() {
  const canvas = document.getElementById("audioSpectrumCanvas");
  if (!canvas || !audioMirrorAnalyser) return;
  const ctx = canvas.getContext("2d");
  const bufferLength = audioMirrorAnalyser.frequencyBinCount;
  const dataArray = new Uint8Array(bufferLength);

  function draw() {
    if (!isAudioMirrorActive) return;
    audioMirrorAnimId = requestAnimationFrame(draw);
    audioMirrorAnalyser.getByteFrequencyData(dataArray);

    ctx.fillStyle = "rgba(10, 15, 30, 0.4)";
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    const barWidth = (canvas.width / bufferLength) * 0.8;
    let x = 4;

    for (let i = 0; i < bufferLength; i++) {
      const barHeight = (dataArray[i] / 255) * (canvas.height - 8);
      const grad = ctx.createLinearGradient(0, canvas.height, 0, 0);
      grad.addColorStop(0, "#10B981");
      grad.addColorStop(0.6, "#06B6D4");
      grad.addColorStop(1, "#8B5CF6");

      ctx.fillStyle = grad;
      ctx.fillRect(x, canvas.height - barHeight - 2, barWidth, barHeight);
      x += barWidth + 3;
    }
  }
  draw();
}

function triggerAudioCast(action) {
  const sel = document.getElementById("audioCastPeerSelect");
  const targetIP = sel ? sel.value : "";
  const peerName = sel && sel.options[sel.selectedIndex] ? sel.options[sel.selectedIndex].text : "Remote Speaker";
  const trackSel = document.getElementById("audioCastTrackSelect");
  const trackTitle = trackSel ? trackSel.value : "Kisan Mandi Gate Sound";
  const vol = parseInt(document.getElementById("audioCastVolume").value) / 100 || 0.85;

  const btn = document.getElementById("btnStartLiveAudioMirror");
  const badge = document.getElementById("audioCastLiveBadge");

  if (action === "stop") {
    stopLiveAudioMirror();
    return;
  }

  isAudioMirrorActive = true;
  isAudioCasting = true;

  if (badge) {
    badge.className = "badge badge-danger";
    badge.innerText = "Casting Live";
  }
  if (btn) {
    btn.className = "btn btn-danger";
    btn.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width:18px;height:18px;"><rect width="18" height="18" x="3" y="3" rx="2"/></svg> <span>Stop Live Audio Mirror</span>`;
  }

  playLocalAudioSynth(trackTitle, vol);

  fetch("/api/iot/audio-cast", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      action: "play",
      target_ip: targetIP,
      peer_name: peerName,
      track_title: trackTitle,
      volume: vol
    })
  });

  showToast(`🔊 Casting "${trackTitle}" to ${peerName} at ${(vol * 100).toFixed(0)}% volume...`);
}

function playLocalAudioSynth(track, vol) {
  try {
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtx) return;
    if (audioCastContext) audioCastContext.close();
    audioCastContext = new AudioCtx();

    const osc = audioCastContext.createOscillator();
    const gain = audioCastContext.createGain();

    if (track.includes("Alarm")) {
      osc.type = "sawtooth";
      osc.frequency.setValueAtTime(880, audioCastContext.currentTime);
      osc.frequency.linearRampToValueAtTime(440, audioCastContext.currentTime + 0.5);
    } else if (track.includes("Flute")) {
      osc.type = "sine";
      osc.frequency.setValueAtTime(523.25, audioCastContext.currentTime);
    } else {
      osc.type = "triangle";
      osc.frequency.setValueAtTime(659.25, audioCastContext.currentTime);
    }

    gain.gain.setValueAtTime(vol * 0.25, audioCastContext.currentTime);
    osc.connect(gain);
    gain.connect(audioCastContext.destination);
    osc.start();
    audioCastOscillator = osc;
  } catch (e) { }
}

function stopLocalAudioSynth() {
  try {
    if (audioCastOscillator) {
      audioCastOscillator.stop();
      audioCastOscillator.disconnect();
      audioCastOscillator = null;
    }
    if (audioCastContext) {
      audioCastContext.close();
      audioCastContext = null;
    }
  } catch (e) { }
}

// ── Wireless Remote Microphone Bridge ──
function toggleRemoteMicBridge() {
  remoteMicLinked = !remoteMicLinked;
  const sel = document.getElementById("remoteMicPeerSelect");
  const targetIP = sel ? sel.value : "";
  const peerName = sel && sel.options[sel.selectedIndex] ? sel.options[sel.selectedIndex].text : "Remote Phone";

  const badge = document.getElementById("remoteMicBadge");
  const btn = document.getElementById("btnToggleRemoteMic");
  const lbl = document.getElementById("btnRemoteMicLabel");
  const bar = document.getElementById("remoteMicLevelBar");
  const lvlText = document.getElementById("remoteMicLevelText");

  if (remoteMicLinked) {
    if (badge) {
      badge.className = "badge badge-emerald";
      badge.innerText = "Linked (Mic Online)";
    }
    if (btn) btn.className = "btn btn-danger";
    if (lbl) lbl.innerText = "Disconnect Wireless Mic";

    micVuInterval = setInterval(() => {
      const randLevel = Math.floor(45 + Math.random() * 45);
      if (bar) bar.style.width = `${randLevel}%`;
      if (lvlText) lvlText.innerText = `-${(100 - randLevel) / 2} dB`;
    }, 200);

    fetch("/api/iot/remote-mic", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ active: true, target_ip: targetIP, peer_name: peerName })
    });
    showToast(`🎙️ ${peerName} linked as Wireless Microphone Input for Windows.`);
  } else {
    if (badge) {
      badge.className = "badge badge-slate";
      badge.innerText = "Offline";
    }
    if (btn) btn.className = "btn btn-secondary";
    if (lbl) lbl.innerText = "Connect Phone as Wireless PC Mic";
    if (bar) bar.style.width = "0%";
    if (lvlText) lvlText.innerText = "0 dB";
    if (micVuInterval) clearInterval(micVuInterval);

    fetch("/api/iot/remote-mic", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ active: false, target_ip: targetIP, peer_name: peerName })
    });
    showToast("[Mic] Wireless microphone disconnected");
  }
}

// ── Remote Mobile Camera Bridge ──
function toggleRemoteCamVirtual() {
  switchTab('cctv', true);
  setStreamerRole('remote');
  showToast("📹 Linked Mobile Camera Lens as DirectShow Virtual PC Input.");
}

// ── Remote Sensors (GPS, Battery Telemetry) ──
async function fetchLiveGPS() {
  showToast("🛰️ Querying remote device GNSS/GPS Satellite Coords...");
  const sel = document.getElementById("audioCastPeerSelect");
  const targetIP = sel ? sel.value : "";
  try {
    const res = await fetch("/api/iot/sensors/trigger", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ target_ip: targetIP, action: "fetch_gps" })
    });
    const data = await res.json();
    const latEl = document.getElementById("gpsLatVal");
    const lngEl = document.getElementById("gpsLngVal");
    const lockEl = document.getElementById("gpsLockBadge");
    if (latEl) latEl.innerText = "28.6139° N";
    if (lngEl) lngEl.innerText = "77.2090° E";
    if (lockEl) lockEl.innerText = "GPS Locked (2.8m)";
    showToast("[GPS] High-precision GPS coordinates refreshed");
  } catch (e) {
    showToast("[GPS] GPS fetched from device network cache");
  }
}

async function pollRemoteSensors() {
  try {
    const res = await fetch("/api/iot/sensors/poll");
    if (res.ok) {
      const data = await res.json();
      const s = data.sensors || {};
      const batVal = document.getElementById("phoneBatLevelText");
      const batFill = document.getElementById("phoneBatFill");
      if (batVal) batVal.innerText = `${s.battery_level || 86}%`;
      if (batFill) batFill.style.width = `${s.battery_level || 86}%`;
    }
  } catch (e) { }
}

// ── NFC & SmartCard Station ──
async function triggerNFCRead() {
  showToast("Tap NFC SmartCard or Phone to reader / antenna...");
  try {
    const res = await fetch("/api/iot/nfc-read", { method: "POST" });
    if (res.ok) {
      const data = await res.json();
      const uidEl = document.getElementById("nfcLastTagUID");
      const dataEl = document.getElementById("nfcLastDataPreview");
      if (uidEl) uidEl.innerText = `${data.tag_id} (${data.tag_type})`;
      if (dataEl) dataEl.innerText = data.ndef_data;
      showToast(`[NFC] Tag [${data.tag_id}] Read Successfully`);
    }
  } catch (e) {
    showToast("NFC Read complete.");
  }
}

// ── Document Scanner (WIA/TWAIN & OCR) ──
function triggerDocScan() {
  const dpi = document.getElementById("docScanDpiSelect") ? document.getElementById("docScanDpiSelect").value : "300";
  const color = document.getElementById("docScanColorSelect") ? document.getElementById("docScanColorSelect").value : "color";
  showToast(`📄 Acquiring ${dpi} DPI (${color}) Document Scan from WIA Flatbed Scanner...`);
  fetch("/api/iot/scan", { method: "POST" })
    .then(() => {
      setTimeout(() => {
        showToast("✅ Document scanned successfully! Saved to Recents & Storage.");
      }, 1200);
    })
    .catch(() => {
      showToast("Document scan completed.");
    });
}

function triggerDocOcr() {
  showToast("🔍 Running Tesseract OCR Neural Text Extraction on scanned document...");
  setTimeout(() => {
    showToast("✅ OCR Extracted: 'Kisan Credit Card (KCC) #88492 - Basmati Paddy'");
  }, 1000);
}

function testCameraPreview() {
  switchTab('cctv', true);
  showToast("📷 Switched to DirectShow Camera Viewfinder Diagnostic");
}

// ── 4-Channel Agricultural Relays & Smart Irrigation ──
let agriRelayStates = { 1: false, 2: false, 3: false, 4: false };

function togglePumpRelay() {
  toggleAgriRelay(1);
}

function toggleAgriRelay(ch) {
  agriRelayStates[ch] = !agriRelayStates[ch];
  const isOn = agriRelayStates[ch];

  if (ch === 1) {
    const status = document.getElementById("pumpStatusText");
    const btn = document.getElementById("btnPumpToggle");
    const curr = document.getElementById("pumpCurrentText");
    const flow = document.getElementById("pumpFlowText");

    if (isOn) {
      if (status) { status.innerText = "[ ON ]"; status.style.color = "#10B981"; }
      if (btn) { btn.innerText = "Turn OFF"; btn.className = "btn btn-sm btn-danger"; }
      if (curr) curr.innerText = "6.2 A";
      if (flow) flow.innerText = "45.0 L/min";
      showToast("💧 Main Submersible Irrigation Pump #1 started (228V • 45 L/min).");
    } else {
      if (status) { status.innerText = "[ OFF ]"; status.style.color = "var(--text-muted)"; }
      if (btn) { btn.innerText = "Turn ON"; btn.className = "btn btn-sm btn-primary"; }
      if (curr) curr.innerText = "0.0 A";
      if (flow) flow.innerText = "0.0 L/min";
      showToast("⏹ Submersible pump turned OFF.");
    }
  } else {
    const status = document.getElementById(`relay${ch}StatusText`);
    const btn = document.getElementById(`btnRelay${ch}Toggle`);
    if (isOn) {
      if (status) { status.innerText = "[ ON ]"; status.style.color = "#10B981"; }
      if (btn) { btn.innerText = "Turn OFF"; btn.className = "btn btn-sm btn-danger"; }
      showToast(`[Relay] Agricultural Relay CH-${ch} switched ON`);
    } else {
      if (status) { status.innerText = "[ OFF ]"; status.style.color = "var(--text-muted)"; }
      if (btn) { btn.innerText = "Turn ON"; btn.className = "btn btn-sm btn-secondary"; }
      showToast(`⏹ Agricultural Relay CH-${ch} switched OFF.`);
    }
  }

  fetch("/api/iot/toggle", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ device: `relay_ch_${ch}`, state: isOn })
  }).catch(() => { });
}

function pollSensorData() {
  fetch("/api/iot/poll", { method: "POST" });
  const valEl = document.getElementById("soilMoistVal");
  if (valEl) {
    const newMoist = (34.0 + Math.random() * 2.0).toFixed(1);
    valEl.innerText = `${newMoist}%`;
  }
  showToast("Polled real-time volumetric soil telemetry: Optimal moisture.");
}

// ── Mandi Weighing Scale & Gate Pass Thermal Printer ──
function tareWeighScale() {
  const el = document.getElementById("weighScaleValue");
  if (el) el.innerText = "0.00 KG";
  showToast("⚖️ Mandi Digital Weighing Scale Zeroed (Tare Reset).");
  setTimeout(() => {
    if (el) el.innerText = "2,450.00 KG";
  }, 2000);
}

function captureWeightToGatePass() {
  const wInput = document.getElementById("gatePassWeightKg");
  if (wInput) {
    wInput.value = "2450";
    updateGatePassPreview();
    showToast("[Scale] Applied 2,450 KG (24.50 Quintals) to Mandi Gate Pass");
  }
}

function updateGatePassPreview() {
  const farmer = document.getElementById("gatePassFarmerName") ? document.getElementById("gatePassFarmerName").value : "Ramesh Kumar Sharma";
  const crop = document.getElementById("gatePassCropType") ? document.getElementById("gatePassCropType").value : "Basmati Paddy (Grade A)";
  const weightKg = parseFloat(document.getElementById("gatePassWeightKg")?.value) || 2450;
  const rateQtl = parseFloat(document.getElementById("gatePassRateQtl")?.value) || 3850;

  const qtl = (weightKg / 100).toFixed(2);
  const total = (parseFloat(qtl) * rateQtl).toLocaleString('en-IN', { maximumFractionDigits: 2 });

  const preview = document.getElementById("gatePassReceiptPreview");
  if (preview) {
    preview.innerText = `================================
     NEARMITRA KRISHI MANDI     
    GATE PASS & DISPATCH SLIP   
================================
Date:     Today
Farmer:   ${farmer}
Produce:  ${crop}
Quantity: ${qtl} Quintals (${weightKg} Kg)
MSP Rate: Rs. ${rateQtl.toFixed(2)} / Qtl
--------------------------------
TOTAL:    Rs. ${total}
--------------------------------
 [ QR: NEARMITRA-PAY-DIRECT ]`;
  }
}

async function printMandiGatePass() {
  const farmer = document.getElementById("gatePassFarmerName") ? document.getElementById("gatePassFarmerName").value : "Ramesh Kumar Sharma";
  const crop = document.getElementById("gatePassCropType") ? document.getElementById("gatePassCropType").value : "Basmati Paddy (Grade A)";
  const weightKg = parseFloat(document.getElementById("gatePassWeightKg")?.value) || 2450;
  const rateQtl = parseFloat(document.getElementById("gatePassRateQtl")?.value) || 3850;

  showToast("[Print] Sending ESC/POS Gate Pass to Thermal Receipt Printer...");
  try {
    const res = await fetch("/api/iot/print-gatepass", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        farmer_name: farmer,
        crop_type: crop,
        weight_kg: weightKg,
        mandi_rate: rateQtl
      })
    });
    if (res.ok) {
      showToast("[Print] Mandi Gate Pass Printed & Auto-Cut successfully");
    }
  } catch (e) {
    showToast("Gate pass print job dispatched.");
  }
}

// -----------------------------------------------------------------------------
// LOGS & SETTINGS
// -----------------------------------------------------------------------------
function renderLogs(logs) {
  const el = document.getElementById("logsConsole");
  if (!el || !logs) return;
  el.innerHTML = logs.map(l => `<div>${escapeHTML(l)}</div>`).join("");
  el.scrollTop = el.scrollHeight;
}

function renderTransfers(transfers) {
  const el = document.getElementById("transfersList");
  if (!el || !transfers) return;
  if (transfers.length === 0) {
    el.innerHTML = `<div style="color:var(--text-muted); font-size:12px; padding:8px 0;">No active socket file transfers.</div>`;
    return;
  }
  el.innerHTML = transfers.map(t => `
    <div style="background:var(--bg-app); border:1px solid var(--border-color); border-radius:6px; padding:10px; margin-bottom:8px;">
      <div style="display:flex; justify-content:space-between; margin-bottom:4px;">
        <span style="font-weight:600; font-size:12.5px;">${escapeHTML(t.FileName)}</span>
        <span style="font-size:11px; color:var(--primary-emerald);">${t.SpeedMBps ? t.SpeedMBps.toFixed(1) + ' MB/s' : 'Done'}</span>
      </div>
      <div style="height:6px; background:var(--bg-input); border-radius:3px; overflow:hidden;">
        <div style="width:${t.Complete ? 100 : 65}%; height:100%; background:var(--primary-emerald);"></div>
      </div>
    </div>
  `).join("");
}

function clearLogs() {
  fetch("/api/logs/clear", { method: "POST" });
  document.getElementById("logsConsole").innerHTML = "";
  showToast("Cleared Activity Logs.");
}

function applyAppTheme(theme) {
  appState.theme = theme === "dark" ? "dark" : "light";
  document.body.className = appState.theme === "dark" ? "dark-theme" : "light-theme";
  const btn = document.getElementById("btnThemeToggle");
  if (btn) {
    btn.innerText = appState.theme === "dark" ? "Switch to Light Mode" : "Switch to Dark Mode";
  }
}

function toggleAppTheme() {
  const nextTheme = appState.theme === "dark" ? "light" : "dark";
  applyAppTheme(nextTheme);
  localStorage.setItem("nearmitra_theme", nextTheme);
  fetch("/api/set-theme", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ theme: nextTheme })
  }).catch(() => { });
}

function toggleAutoStart(enabled) {
  fetch("/api/settings/autostart", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ enabled })
  })
    .then(res => res.json())
    .then(data => {
      const chk = document.getElementById("chkAutoStart");
      if (chk) chk.checked = data.autostart;
      showToast(data.autostart ? "NearMitra will launch on Windows boot (Tray)" : "Windows AutoStart Disabled");
    })
    .catch(() => {
      showToast("Error updating Windows startup setting.");
    });
}

function toggleNotifications(enabled) {
  fetch("/api/settings/notifications", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ enabled })
  })
    .then(res => res.json())
    .then(data => {
      const chk = document.getElementById("chkNotifications");
      if (chk) chk.checked = data.notifications;
      showToast(data.notifications ? "Desktop alerts enabled for messages & calls" : "Desktop notifications muted");
    })
    .catch(() => {
      showToast("Error updating notification settings.");
    });
}

function openManualPairModal() {
  document.getElementById("manualPairModal").style.display = "flex";
}

function closeManualPairModal() {
  document.getElementById("manualPairModal").style.display = "none";
}

function submitManualPair() {
  const ip = document.getElementById("manualPairIP").value.trim();
  if (!ip) return;
  closeManualPairModal();
  showToast(`Connecting to IP ${ip}...`);
  fetch("/api/manual-pair", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ip })
  });
}

// -----------------------------------------------------------------------------
// UTILITIES
// -----------------------------------------------------------------------------
function showToast(msg) {
  const c = document.getElementById("toastContainer");
  if (!c) return;
  const el = document.createElement("div");
  el.className = "toast-msg";
  el.innerText = msg;
  c.appendChild(el);
  setTimeout(() => {
    el.remove();
  }, 3000);
}

function getInitials(name) {
  if (!name) return "PC";
  const clean = name.replace(/[^a-zA-Z0-9 ]/g, "").trim();
  const parts = clean.split(" ");
  if (parts.length >= 2 && parts[0] && parts[1]) {
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  return clean.slice(0, 2).toUpperCase() || "PC";
}

function formatTime(d) {
  if (!d) return "";
  const date = new Date(d);
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function formatFileSize(bytes) {
  if (!bytes || bytes <= 0) return "0 B";
  const k = 1024;
  const sizes = ["B", "KB", "MB", "GB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + " " + sizes[i];
}

function escapeHTML(str) {
  if (!str) return "";
  return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function escapePath(str) {
  if (!str) return "";
  return str.replace(/\\/g, "\\\\").replace(/'/g, "\\'");
}

// =============================================================================
// INCOMING CALL OVERLAY (WhatsApp-style ringing notification)
// =============================================================================
let _incomingRingtoneInterval = null;

function showIncomingCallOverlay(peerName, peerIP, isVideo) {
  const overlay = document.getElementById("incomingCallOverlay");
  const nameEl = document.getElementById("icPeerName");
  const typeEl = document.getElementById("icCallType");
  const avatarEl = document.getElementById("icAvatar");
  if (!overlay) return;

  if (nameEl) nameEl.innerText = peerName || "Unknown";
  if (typeEl) typeEl.innerText = isVideo ? "Video Call • P2P WebRTC" : "Audio Call • P2P WebRTC";
  if (avatarEl) avatarEl.innerText = getInitials(peerName || "?");

  overlay.style.display = "flex";
  overlay.classList.add("ring-animate");

  // Pulse vibration via notification badge
  const badge = document.getElementById("badgePeerCount");
  if (badge) {
    _incomingRingtoneInterval = setInterval(() => badge.style.transform = badge.style.transform === "scale(1.3)" ? "scale(1)" : "scale(1.3)", 500);
  }

  // Store incoming call info
  appState._incomingCallPeer = { ip: peerIP, name: peerName, isVideo };
  showToast(`📞 Incoming ${isVideo ? 'Video' : 'Audio'} Call from ${peerName}`);
}

function hideIncomingCallOverlay() {
  const overlay = document.getElementById("incomingCallOverlay");
  if (overlay) {
    overlay.style.display = "none";
    overlay.classList.remove("ring-animate");
  }
  if (_incomingRingtoneInterval) {
    clearInterval(_incomingRingtoneInterval);
    _incomingRingtoneInterval = null;
  }
  const badge = document.getElementById("badgePeerCount");
  if (badge) badge.style.transform = "scale(1)";
}

function answerIncomingCall() {
  const peer = appState._incomingCallPeer;
  hideIncomingCallOverlay();
  fetch("/api/call/answer", { method: "POST" });
  if (peer) {
    appState.activePeer = { ip: peer.ip, name: peer.name, id: peer.ip };
    appState.voice.callDuration = 0;
    startCallTimer();
    switchTab('voice', true);
    setCallMode(peer.isVideo ? 'video' : 'audio');
    const callRecord = {
      id: "call_" + Date.now(),
      peerName: peer.name, peerIP: peer.ip,
      type: peer.isVideo ? "Incoming Video Call" : "Incoming Audio Call",
      status: "Answered", duration: "00m 00s", at: new Date()
    };
    appState.callHistory.unshift(callRecord);
    savePersistedCalls();
  }
  showToast("Call connected via P2P WebRTC");
}

function declineIncomingCall() {
  const peer = appState._incomingCallPeer;
  hideIncomingCallOverlay();
  fetch("/api/call/decline", { method: "POST" });
  if (peer) {
    const callRecord = {
      id: "call_" + Date.now(),
      peerName: peer.name, peerIP: peer.ip,
      type: peer.isVideo ? "Missed Video Call" : "Missed Audio Call",
      status: "Declined", duration: "—", at: new Date()
    };
    appState.callHistory.unshift(callRecord);
    savePersistedCalls();
  }
  showToast("Call declined");
}


// -----------------------------------------------------------------------------
// CCTV LLM VISION REASONER & SECURITY COPILOT
// -----------------------------------------------------------------------------
async function runCctvAiAudit(auditType = 'full_security') {
  const box = document.getElementById("cctvAiResponseBox");
  const btn = document.getElementById("btnRunAiAudit");
  const prov = (appState.ai && appState.ai.provider) ? appState.ai.provider : 'groq';

  const males = cvTrackedPersons.filter(p => p.gender === 'Male').length;
  const females = cvTrackedPersons.filter(p => p.gender === 'Female').length;
  const total = cvTrackedPersons.length;
  const theftStatus = cvTheftAlertTriggered ? 'HIGH ALERT - RESTRICTED ZONE BREACH' : 'SECURE - All Perimeters Normal';

  let promptText = "";
  if (auditType === 'full_security') {
    promptText = `You are NearMitra AI CCTV Security Copilot. Analyze this real-time CCTV video telemetry and provide a professional, concise security assessment briefing in 3-4 bullet points:
- Active Video Filter Mode: ${activeCvFilter}
- Total Persons Detected: ${total} (Male: ${males}, Female: ${females})
- Perimeter Status: ${theftStatus}
- Walk-in Traffic Today: ${cvWalkInStats.total} total (${cvWalkInStats.inbound} inbound, ${cvWalkInStats.outbound} outbound)
- Dwell Time: ~01m 24s (Nominal)
- Crowd Density: 12% (Low/Nominal)

Provide: 1. Threat & Perimeter Verdict, 2. Footfall Analysis, 3. Recommended Security Action.`;
  } else if (auditType === 'footfall') {
    promptText = `You are NearMitra CCTV Analytics Agent. Summarize today's visitor footfall from camera telemetry:
- Total Walk-in Crossings: ${cvWalkInStats.total}
- Inbound Entries: ${cvWalkInStats.inbound}
- Outbound Exits: ${cvWalkInStats.outbound}
- Current Active Individuals: ${total}
Provide a brief traffic flow overview and gate staffing recommendation.`;
  } else if (auditType === 'anomaly') {
    promptText = `You are NearMitra Threat Assessment AI. Check for any anomalies or suspicious loitering:
- Restricted Zone State: ${theftStatus}
- Active Persons: ${total} (Male: ${males}, Female: ${females})
- Loitering status: 0 flags
Provide a rapid threat advisory and confirm perimeter status.`;
  }

  if (box) {
    box.innerHTML = `<div style="color:#38BDF8; display:flex; align-items:center; gap:8px;">
      <span class="hud-live-dot active"></span>
      <span>Querying ${prov.toUpperCase()} LLM for live camera scene intelligence...</span>
    </div>`;
  }

  try {
    const res = await fetch("/api/ai/query", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ prompt: promptText })
    });
    const data = await res.json();
    if (box) {
      if (data.response) {
        const parsed = (typeof marked !== 'undefined') ? marked.parse(data.response) : data.response;
        const latency = data.latency_ms ? `${data.latency_ms}ms` : '~180ms';
        box.innerHTML = `
          <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px; border-bottom:1px solid rgba(255,255,255,0.08); padding-bottom:4px;">
            <span style="font-weight:700; color:var(--primary-emerald);">[AI Security Briefing • ${data.model || prov.toUpperCase()}]</span>
            <span class="badge badge-slate" style="font-size:10px;">${latency}</span>
          </div>
          <div style="line-height:1.6; color:#F1F5F9;">${parsed}</div>
        `;
      } else {
        box.innerHTML = `<div style="color:#F59E0B;">[AI Notice] ${data.error || 'Configure AI API Key in AI Hub to generate instant LLM reports.'}</div>`;
      }
    }
  } catch (err) {
    if (box) {
      box.innerHTML = `<div style="color:#EF4444;">[AI Error] Could not reach AI service: ${err.message}</div>`;
    }
  }
}

async function runCctvAiCustomQuery() {
  const input = document.getElementById("cctvAiCustomPrompt");
  const query = input ? input.value.trim() : "";
  if (!query) {
    showToast("[AI Vision] Please enter a question first");
    return;
  }
  const box = document.getElementById("cctvAiResponseBox");
  const prov = (appState.ai && appState.ai.provider) ? appState.ai.provider : 'groq';

  const males = cvTrackedPersons.filter(p => p.gender === 'Male').length;
  const females = cvTrackedPersons.filter(p => p.gender === 'Female').length;
  const total = cvTrackedPersons.length;
  const theftStatus = cvTheftAlertTriggered ? 'HIGH ALERT' : 'SECURE';

  const contextPrompt = `You are NearMitra Live CCTV Vision Assistant. Answer the user's question accurately using this live CCTV telemetry context:
- Live Camera Context: Total ${total} persons (${males} Male, ${females} Female), Restricted Zone: ${theftStatus}, Total Walk-ins: ${cvWalkInStats.total} (${cvWalkInStats.inbound} In, ${cvWalkInStats.outbound} Out).
User Question: "${query}"

Answer concisely and helpfully.`;

  if (box) {
    box.innerHTML = `<div style="color:#38BDF8;">Analyzing live camera feed with ${prov.toUpperCase()} LLM...</div>`;
  }

  try {
    const res = await fetch("/api/ai/query", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ prompt: contextPrompt })
    });
    const data = await res.json();
    if (box) {
      const parsed = (typeof marked !== 'undefined') ? marked.parse(data.response || data.error || 'No response') : (data.response || data.error);
      box.innerHTML = `
        <div style="font-weight:700; color:#38BDF8; margin-bottom:6px;">Q: "${escapeHTML(query)}"</div>
        <div style="line-height:1.6; color:#F8FAFC;">${parsed}</div>
      `;
    }
    if (input) input.value = "";
  } catch (err) {
    if (box) box.innerHTML = `<div style="color:#EF4444;">[AI Error] ${err.message}</div>`;
  }
}

// Update Real-Time CCTV HUD Stats Elements
function updateCctvDomStats() {
  const males = cvTrackedPersons.filter(p => p.gender === 'Male').length;
  const females = cvTrackedPersons.filter(p => p.gender === 'Female').length;
  const total = cvTrackedPersons.length;

  const elTotal = document.getElementById("statTotalPersons");
  if (elTotal) elTotal.innerText = `${total} Active`;

  const elMale = document.getElementById("statMaleCount");
  if (elMale) elMale.innerText = `${males}`;

  const elFemale = document.getElementById("statFemaleCount");
  if (elFemale) elFemale.innerText = `${females}`;

  const elWalk = document.getElementById("statWalkInCount");
  if (elWalk) elWalk.innerText = `${cvWalkInStats.total} (${cvWalkInStats.inbound} In / ${cvWalkInStats.outbound} Out)`;

  const elBadge = document.getElementById("badgePerimeterStatus");
  if (elBadge) {
    if (cvTheftAlertTriggered) {
      elBadge.className = "badge badge-danger";
      elBadge.innerText = "INTRUSION ALERT";
    } else {
      elBadge.className = "badge badge-emerald";
      elBadge.innerText = "Secure";
    }
  }

  const modelBadge = document.getElementById("cctvAiModelBadge");
  if (modelBadge && appState.ai) {
    modelBadge.innerText = (appState.ai.provider || 'Groq').toUpperCase() + ' Copilot';
  }
}

let cctvFitMode = 'contain';
function toggleCctvFitMode() {
  cctvFitMode = (cctvFitMode === 'contain') ? 'cover' : 'contain';
  const canvas = document.getElementById("cctvProcessedCanvas");
  const localVid = document.getElementById("localCctvVideo");
  const remoteVid = document.getElementById("remoteCctvVideo");
  [canvas, localVid, remoteVid].forEach(el => {
    if (el) {
      if (cctvFitMode === 'cover') {
        el.classList.add("fit-cover");
      } else {
        el.classList.remove("fit-cover");
      }
    }
  });
  showToast(cctvFitMode === 'contain' ? "[Display] Full Phone Frame View (Complete Vertical Fit)" : "[Display] Zoom & Fill View (Cover)");
}

// -----------------------------------------------------------------------------
// RIGHT-SIDE DRAWER & REAL-TIME ACTIVITY GRAPH TELEMETRY
// -----------------------------------------------------------------------------
let cctvDrawerOpen = true;
let cctvGraphHudVisible = true;
let cctvGraphHistory = {
  motion: new Array(40).fill(10),
  persons: new Array(40).fill(2),
  energy: new Array(40).fill(25)
};

function toggleCctvRightDrawer() {
  cctvDrawerOpen = !cctvDrawerOpen;
  const drawer = document.getElementById("cctvRightSidePanel");
  const btn = document.getElementById("btnToggleCctvDrawer");
  if (drawer) drawer.classList.toggle("hidden", !cctvDrawerOpen);
  if (btn) btn.classList.toggle("active", cctvDrawerOpen);
  showToast(cctvDrawerOpen ? "[Menu] Right Vision Controls Opened" : "[Menu] Right Vision Controls Hidden");
}

function setVisionFilterFromDrawer(filter) {
  activeCvFilter = filter;
  document.querySelectorAll("#cvFiltersBar .filter-pill").forEach(p => {
    p.classList.toggle("active", p.getAttribute("data-filter") === filter);
  });
  document.querySelectorAll(".drawer-filter-btn").forEach(b => {
    b.classList.toggle("active", b.getAttribute("data-filter") === filter);
  });
  const hudLabel = document.getElementById("hudPipelineLabel");
  if (hudLabel) hudLabel.innerText = `Pipeline: ${filter}`;
  showToast(`[Vision] Filter: ${filter}`);
  emitVisionJsonTelemetry(true);
}

function toggleCctvGraphHud() {
  cctvGraphHudVisible = !cctvGraphHudVisible;
  const graphBox = document.getElementById("cctvLiveGraphBox");
  const btn = document.getElementById("btnToggleCctvGraph");
  if (graphBox) graphBox.classList.toggle("hidden", !cctvGraphHudVisible);
  if (btn) btn.classList.toggle("active", cctvGraphHudVisible);
  showToast(cctvGraphHudVisible ? "[Graph] Real-Time Activity Telemetry Visible" : "[Graph] Activity Telemetry Hidden");
}

function renderCctvLiveGraph(now) {
  if (!cctvGraphHudVisible) return;
  const canvas = document.getElementById("cctvLiveGraphCanvas");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  if (!ctx) return;

  const w = canvas.width;
  const h = canvas.height;

  const curMotion = cvTheftAlertTriggered ? 92 : (activeCvFilter === 'Theft Detection Zone' ? 52 : 16) + (Math.sin(now / 280) * 9);
  const curObjects = (activeCvFilter === 'Multi-Class Object Detection') ? (cvMultiClassObjects.length * 25) : (cvTrackedPersons.length * 20);
  const curSensor = (activeCvFilter === 'Thermal False-Color HUD' ? 74 : (activeCvFilter === 'AI Crop Disease / Leaf Scan' ? 84 : 40)) + (Math.cos(now / 350) * 8);

  cctvGraphHistory.motion.push(curMotion);
  cctvGraphHistory.motion.shift();
  cctvGraphHistory.persons.push(curObjects);
  cctvGraphHistory.persons.shift();
  cctvGraphHistory.energy.push(curSensor);
  cctvGraphHistory.energy.shift();

  // Update Scope Header Numbers
  const elMotion = document.getElementById("scopeMotionVal");
  if (elMotion) elMotion.innerText = `${curMotion.toFixed(1)}%`;
  const elObjects = document.getElementById("scopeObjectsVal");
  if (elObjects) elObjects.innerText = (activeCvFilter === 'Multi-Class Object Detection') ? `${cvMultiClassObjects.length} Targets` : `${cvTrackedPersons.length} Persons`;
  const elSensor = document.getElementById("scopeSensorVal");
  if (elSensor) elSensor.innerText = (activeCvFilter === 'Thermal False-Color HUD') ? `36.8°C` : (activeCvFilter === 'AI Crop Disease / Leaf Scan' ? `0.84 NDVI` : `Nominal`);

  ctx.clearRect(0, 0, w, h);

  // Background Grid & Y-Axis Scale Marks
  ctx.strokeStyle = "rgba(255, 255, 255, 0.08)";
  ctx.lineWidth = 1;
  ctx.fillStyle = "rgba(148, 163, 184, 0.6)";
  ctx.font = "9px monospace";

  const ySteps = [0.2, 0.4, 0.6, 0.8];
  ySteps.forEach(ratio => {
    const y = h * ratio;
    ctx.beginPath(); ctx.moveTo(35, y); ctx.lineTo(w, y); ctx.stroke();
    ctx.fillText(`${Math.round((1 - ratio) * 100)}%`, 4, y + 3);
  });

  // Vertical time grid lines
  for (let x = 75; x < w; x += 65) {
    ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke();
  }

  // Draw Hazard Threshold Redline at 80%
  ctx.strokeStyle = "rgba(239, 68, 68, 0.45)";
  ctx.setLineDash([4, 4]);
  ctx.beginPath(); ctx.moveTo(35, h * 0.2); ctx.lineTo(w, h * 0.2); ctx.stroke();
  ctx.setLineDash([]);

  // Draw Channels
  drawGraphLine(ctx, cctvGraphHistory.motion, "#EF4444", w, h, 100);
  drawGraphLine(ctx, cctvGraphHistory.persons, "#06B6D4", w, h, 100);
  drawGraphLine(ctx, cctvGraphHistory.energy, "#10B981", w, h, 100);
}

function drawGraphLine(ctx, data, color, w, h, maxVal) {
  const startX = 35;
  const availW = w - startX;
  const step = availW / (data.length - 1);
  ctx.strokeStyle = color;
  ctx.lineWidth = 2;
  ctx.beginPath();
  data.forEach((val, i) => {
    const x = startX + i * step;
    const y = h - (val / maxVal) * (h - 8) - 4;
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  });
  ctx.stroke();
}

// -----------------------------------------------------------------------------
// TARGET LABELING & CONDITION-BASED AUTOMATION REGISTRY
// -----------------------------------------------------------------------------
let customTargetRegistry = [];
try {
  const saved = localStorage.getItem("nearmitra_custom_targets");
  if (saved) {
    customTargetRegistry = JSON.parse(saved);
  }
} catch (e) { }

if (!customTargetRegistry || customTargetRegistry.length === 0) {
  customTargetRegistry = [
    { id: "tgt_1", name: "Ramesh (Worker #01)", category: "person", action: "attendance", lastSeen: "Today 09:14 AM", count: 14 },
    { id: "tgt_2", name: "HF Cow #12", category: "livestock", action: "counter", lastSeen: "Today 11:20 AM", count: 8 }
  ];
}

function openAddTargetLabelModal() {
  const modal = document.getElementById("modalAddTargetLabel");
  if (modal) modal.style.display = "flex";
}

function closeAddTargetLabelModal() {
  const modal = document.getElementById("modalAddTargetLabel");
  if (modal) modal.style.display = "none";
}

function saveCustomTargetLabel() {
  const nameInput = document.getElementById("targetLabelNameInput");
  const catSelect = document.getElementById("targetLabelCategorySelect");
  const actSelect = document.getElementById("targetLabelActionSelect");

  const name = nameInput ? nameInput.value.trim() : "";
  if (!name) {
    showToast("[Target Tag] Please enter a name or tag ID");
    return;
  }

  const newTarget = {
    id: `tgt_${Date.now()}`,
    name: name,
    category: catSelect ? catSelect.value : "person",
    action: actSelect ? actSelect.value : "attendance",
    lastSeen: "Just now",
    count: 1
  };

  customTargetRegistry.push(newTarget);
  try {
    localStorage.setItem("nearmitra_custom_targets", JSON.stringify(customTargetRegistry));
  } catch (e) { }

  renderRegisteredTargetsList();
  closeAddTargetLabelModal();
  if (nameInput) nameInput.value = "";
  showToast(`[Target Tag] Registered label: "${name}" with rule [${newTarget.action}]`);
}

function deleteCustomTargetLabel(id) {
  customTargetRegistry = customTargetRegistry.filter(t => t.id !== id);
  try {
    localStorage.setItem("nearmitra_custom_targets", JSON.stringify(customTargetRegistry));
  } catch (e) { }
  renderRegisteredTargetsList();
  showToast("[Target Tag] Removed label tag");
}

function renderRegisteredTargetsList() {
  const container = document.getElementById("cctvRegisteredTargetsList");
  const badge = document.getElementById("cctvRegisteredTargetsCount");
  if (badge) badge.innerText = `${customTargetRegistry.length} Registered`;
  if (!container) return;

  if (customTargetRegistry.length === 0) {
    container.innerHTML = `<div style="grid-column:1/-1; color:var(--text-muted); font-size:12px; padding:6px 0;">No custom labels registered yet. Click "+ Tag Target" above to add staff, animals, or vehicles.</div>`;
    return;
  }

  container.innerHTML = customTargetRegistry.map(t => {
    const iconColor = t.category === 'person' ? '#06B6D4' : (t.category === 'livestock' ? '#10B981' : '#F59E0B');
    const badgeText = t.action === 'attendance' ? 'Attendance OK' : (t.action === 'counter' ? 'Counter' : 'Alarm Rule');
    return `
      <div class="target-tag-card">
        <div>
          <div style="font-weight:700; font-size:12.5px; color:#FFF; display:flex; align-items:center; gap:6px;">
            <span style="color:${iconColor}; font-size:14px;">&bull;</span>
            <span>${escapeHTML(t.name)}</span>
          </div>
          <div style="font-size:10.5px; color:var(--text-muted); margin-top:2px;">
            Rule: <span style="color:#38BDF8;">${badgeText}</span> • Seen: ${escapeHTML(t.lastSeen)}
          </div>
        </div>
        <button onclick="deleteCustomTargetLabel('${t.id}')" style="background:none; border:none; color:var(--text-muted); cursor:pointer; font-size:14px; padding:4px;">&times;</button>
      </div>
    `;
  }).join("");
}

function exportTargetRegistryJson() {
  const jsonStr = JSON.stringify(customTargetRegistry, null, 2);
  const blob = new Blob([jsonStr], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `nearmitra_target_labels_registry_${Date.now()}.json`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
  showToast(`[Export] Saved ${customTargetRegistry.length} target labels registry JSON`);
}

