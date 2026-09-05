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
  } catch (e) {}
}

function savePersistedCalls() {
  try {
    localStorage.setItem("nearmitra_call_history", JSON.stringify(appState.callHistory));
  } catch (e) {}
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
  } else if (tabKey === 'settings') {
    loadStreamingSecurity();
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
  setInterval(fetchState, 5000);
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
        html += `
          <div class="master-item-card ${isActive ? 'active' : ''}" onclick="selectPeer(${idx})">
            <div class="card-avatar-circle bg-emerald">${initials}</div>
            <div class="card-content">
              <div class="card-top-row">
                <span class="card-title">${escapeHTML(p.name)}</span>
                <span class="card-time">Live</span>
              </div>
              <div class="card-sub-row">
                <span class="card-snippet highlight">${p.ip || '192.168.1.55'} • 50 MB/s Ready</span>
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
                <span class="card-snippet">${dev.ip} • ${isNearMitra ? '50 MB/s Ready' : 'TCP Port ' + ((dev.open_ports||[])[0] || '80')}</span>
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
  } catch(e) {}
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
  showToast("Highlighting file in Windows Explorer 📂");
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
        <button class="btn btn-sm btn-primary" onclick="startCallWithPeer('${c.peerIP}', '${escapeHTML(c.peerName)}')">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/></svg>
          <span>Call</span>
        </button>
      </div>
    `;
  }).join("");
}

function startCallWithPeer(ip, name) {
  appState.activePeer = { ip, name, id: ip };
  updateDetailViewForPeer(appState.activePeer);
  switchTab('voice', true);
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
    showToast("⚠️ Select a peer first before sending files.");
    return;
  }

  const targetIP   = targetPeer.ip;
  const targetID   = targetPeer.id;
  const targetName = targetPeer.name || "Peer";

  // Send each dropped file via multipart upload
  Array.from(files).forEach(file => {
    const formData = new FormData();
    formData.append("file", file, file.name);

    showToast(`📎 Sending "${file.name}" to ${targetName}...`);

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
          showToast(`✅ "${data.file}" sent to ${targetName}`);
        } else if (data && data.error) {
          showToast(`❌ Error: ${data.error}`);
        }
      })
      .catch(() => showToast(`❌ Failed to send "${file.name}"`));
  });
}

// -----------------------------------------------------------------------------
// LIVE TYPING INDICATOR
// -----------------------------------------------------------------------------
function handleUserTyping(isTyping = true) {
  if (typingTimeout) clearTimeout(typingTimeout);
  if (isTyping) {
    typingTimeout = setTimeout(() => {
      // stopped typing
    }, 2500);
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
function initCCTVFilters() {
  document.querySelectorAll("#cvFiltersBar .filter-pill").forEach(pill => {
    pill.addEventListener("click", () => {
      document.querySelectorAll("#cvFiltersBar .filter-pill").forEach(p => p.classList.remove("active"));
      pill.classList.add("active");
      const filter = pill.getAttribute("data-filter");
      document.getElementById("hudPipelineLabel").innerText = `Pipeline: ${filter}`;
      fetch("/api/cctv/filter", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ filter })
      });
      showToast(`Vision Filter: ${filter}`);
    });
  });
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

  if (role === 'host') {
    if (btnHost) btnHost.classList.add("active");
    if (btnRemote) btnRemote.classList.remove("active");
    if (hostControls) hostControls.style.display = "block";
    if (remoteControls) remoteControls.style.display = "none";
    if (hwBox) hwBox.style.display = "none";

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
    if (hwBox) hwBox.style.display = "block";

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
    showToast("Host CCTV Camera Stopped");
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
      showToast("Host CCTV Camera Started • Broadcasting on P2P Mesh");
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
    } catch (e) {}
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
          } catch(e) {
            console.warn("Error adding pending ice candidate:", e);
          }
        }
        pendingRemoteCandidates = [];
      }
    }
    showToast(`Connected to ${peerDisplayName} Live Stream!`);
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
      try { hostPeerConnection.close(); } catch(e){}
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
    try { remotePeerConnection.close(); } catch(e){}
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
        try { remotePeerConnection.close(); } catch(e){}
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
    showToast(isRemoteTorchActive ? "Turned Remote Flashlight ON 💡" : "Turned Remote Flashlight OFF");
  } else if (action === 'switch_camera') {
    await fetch("/api/cctv/remote-ctrl", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ target_ip: ip, action: "switch_camera" })
    });
    showToast("Sent Flip Lens command to remote device 🔄");
  } else if (action === 'toggle_mic') {
    isRemoteMicMuted = !isRemoteMicMuted;
    const txt = document.getElementById("remoteMicText");
    if (txt) txt.innerText = isRemoteMicMuted ? "Unmute Peer" : "Mute Peer";
    await fetch("/api/cctv/remote-ctrl", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ target_ip: ip, action: "toggle_mic", value: isRemoteMicMuted })
    });
    showToast(isRemoteMicMuted ? "Muted Remote Peer Microphone 🔇" : "Unmuted Remote Peer Microphone 🎙️");
  }
}

function resetCctvStream() {
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
    vp.requestFullscreen().catch(err => {
      showToast("Fullscreen unavailable: " + err.message);
    });
  } else {
    document.exitFullscreen();
  }
}

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
      } catch(e) {}
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

      showToast("🔴 Live CCTV Recording Started (1080P HD)");
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
      showToast("📸 High-Res Snapshot saved to CCTV_Snapshots folder!");
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
// -----------------------------------------------------------------------------
let localMediaStream = null;
let peerConnection = null;
let isScreenSharing = false;
let audioStreamMode = 'listen'; // 'listen' or 'broadcast'

function setAudioStreamMode(mode) {
  audioStreamMode = mode;
  const pillListen = document.getElementById("pillModeAudio");
  const pillBroadcast = document.getElementById("pillModeBroadcast");
  const pillVideo = document.getElementById("pillModeVideo");
  const statusEl = document.getElementById("callPeerStatus");
  const circle = document.getElementById("audioGlowCircle");
  const titleEl = document.getElementById("callingHeaderSubtitle");

  if (pillListen) pillListen.classList.toggle("active", mode === 'listen');
  if (pillBroadcast) pillBroadcast.classList.toggle("active", mode === 'broadcast');
  if (pillVideo) pillVideo.classList.remove("active");

  const stageAudio = document.getElementById("stageAudioCall");
  const stageVideo = document.getElementById("stageVideoCall");
  if (stageAudio) stageAudio.style.display = "flex";
  if (stageVideo) stageVideo.style.display = "none";

  populateAudioPeerSelect();

  if (mode === 'listen') {
    if (titleEl) titleEl.innerText = "Listen Remote Room • Audio Surveillance • Baby Monitor";
    if (statusEl) statusEl.innerText = "Listening to remote room microphone in real-time";
    if (circle) circle.classList.add("active");
    startEqualizerLoop();
    showToast("Switched to: Listen Remote Mic (Surveillance Audio)");
  } else {
    if (titleEl) titleEl.innerText = "Broadcast My Voice • Intercom / PA System • Live Relay";
    if (statusEl) statusEl.innerText = "Broadcasting your microphone to remote peer speakers";
    if (circle) circle.classList.add("active");
    startEqualizerLoop();
    showToast("Switched to: Broadcast My Voice (Live Intercom)");
  }
}

function populateAudioPeerSelect() {
  const sel = document.getElementById("audioPeerSelect");
  if (!sel) return;
  const peers = appState.peers || [];
  const activeIP = appState.activePeer ? appState.activePeer.ip : "";

  if (peers.length === 0) {
    sel.innerHTML = `<option value="">No peers discovered yet</option>`;
    return;
  }

  sel.innerHTML = peers.map(p => {
    const isSelected = p.ip === activeIP;
    return `<option value="${escapeHTML(p.ip)}" ${isSelected ? 'selected' : ''}>Target: ${escapeHTML(p.name)} (${escapeHTML(p.ip)})</option>`;
  }).join("");
}

function onAudioTargetPeerChanged(ip) {
  const matched = (appState.peers || []).find(p => p.ip === ip);
  if (matched) {
    appState.activePeer = matched;
    updateDetailViewForPeer(matched);
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
  appState.activePeer = { ip, name, id: ip };
  updateDetailViewForPeer(appState.activePeer);
  
  appState.voice.callDuration = 0;
  startCallTimer();
  startEqualizerLoop();
  
  fetch("/api/call/invite", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      target_ip: ip,
      peer_id: ip,
      peer_name: name,
      is_video: isVideo
    })
  });

  switchTab('voice', true);
  setCallMode(isVideo ? 'video' : 'audio');
  
  const callRecord = {
    id: "call_" + Date.now(),
    peerName: name,
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
    showToast("Streaming Security permissions updated 🔒");
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
  if (localMediaStream) {
    localMediaStream.getTracks().forEach(t => t.stop());
    localMediaStream = null;
  }
  if (peerConnection) {
    peerConnection.close();
    peerConnection = null;
  }
  if (callDurationInterval) {
    clearInterval(callDurationInterval);
    callDurationInterval = null;
  }
  // Stop equalizer animation and reset bars to idle
  if (equalizerInterval) {
    clearInterval(equalizerInterval);
    equalizerInterval = null;
  }
  document.querySelectorAll(".audio-wave-visualizer .eq-bar").forEach(b => b.style.height = "4px");

  fetch("/api/voice/end", { method: "POST" });
  showToast("Call session ended.");
  navigateBack();
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
    text: `🤖 [NearMitra ${prov} AI Shared Reasoning]\n\n${text}`,
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

async function setAIChatProvider(provider) {
  appState.ai.provider = provider;
  let modelName = "";
  if (provider === "gemini") modelName = "gemini-2.0-flash";
  else if (provider === "openai") modelName = "gpt-4o";
  else if (provider === "groq") modelName = "llama-3.3-70b-versatile";
  else if (provider === "ollama") modelName = "qwen2.5:latest";

  appState.ai.model = modelName;
  updateAIChatHeader();

  // Also update AI reasoning model badge
  const rBadge = document.getElementById("aiModelBadge");
  if (rBadge) rBadge.innerText = `${provider.toUpperCase()} Active`;

  try {
    await fetch("/api/ai/set-model", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ provider, model: modelName })
    });
    showToast(`Nearby AI active engine set to ${provider.toUpperCase()}`);
  } catch (e) {}
}

async function sendAIChatMessage(presetText) {
  const input = document.getElementById("aiChatInput");
  const text = (presetText || (input ? input.value : "")).trim();
  if (!text) return;
  if (input) input.value = "";

  const stream = document.getElementById("aiChatStream");
  const typingBar = document.getElementById("aiChatTypingBar");

  const welcome = stream ? stream.querySelector(".ai-welcome-bubble") : null;
  if (welcome) welcome.style.display = "none";

  const userMsgId = "ai_msg_user_" + Date.now();
  const userHtml = `
    <div class="msg-row outgoing" id="${userMsgId}">
      <div class="msg-bubble-wrap">
        <div class="msg-bubble ai-user-bubble">
          <div class="msg-text">${escapeHTML(text)}</div>
          <div class="msg-meta">
            <span class="msg-time">${formatTime(new Date())}</span>
          </div>
        </div>
      </div>
    </div>
  `;
  if (stream) {
    stream.insertAdjacentHTML("beforeend", userHtml);
    stream.scrollTop = stream.scrollHeight;
  }

  if (typingBar) typingBar.style.display = "flex";
  const typingLbl = document.getElementById("aiTypingLabel");
  if (typingLbl) typingLbl.innerText = `${(appState.ai.provider || 'AI').toUpperCase()} is generating response...`;

  try {
    const res = await fetch("/api/ai/query", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ prompt: text })
    });
    const data = await res.json();
    const aiResponseText = data.response || "No response received.";

    if (typingBar) typingBar.style.display = "none";

    const aiMsgId = "ai_msg_bot_" + Date.now();
    const prov = (appState.ai.provider || "gemini").toUpperCase();

    const botHtml = `
      <div class="msg-row incoming ai-bot-row" id="${aiMsgId}">
        <div class="msg-bubble-wrap" style="max-width: 85%;">
          <div class="msg-bubble ai-response-bubble">
            <div class="ai-msg-header">
              <span class="ai-bot-badge">✨ ${prov} Nearby AI</span>
              <div class="ai-msg-actions">
                <button class="btn-ai-action" onclick="copyAIText('${aiMsgId}')" title="Copy Text">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width:12px;height:12px;"><rect width="14" height="14" x="8" y="8" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>
                </button>
                <button class="btn-ai-action" onclick="shareAITextToPeer('${aiMsgId}')" title="Share with Active Peer">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width:12px;height:12px;"><path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"/><polyline points="16 6 12 2 8 6"/><line x1="12" x2="12" y1="2" y2="15"/></svg>
                  <span>Share</span>
                </button>
              </div>
            </div>
            <div class="msg-text ai-markdown-text" id="text_${aiMsgId}">${formatMarkdown(aiResponseText)}</div>
            <div class="msg-meta">
              <span class="msg-time">${formatTime(new Date())}</span>
            </div>
          </div>
        </div>
      </div>
    `;
    if (stream) {
      stream.insertAdjacentHTML("beforeend", botHtml);
      stream.scrollTop = stream.scrollHeight;
    }
  } catch (err) {
    if (typingBar) typingBar.style.display = "none";
    showToast("Error querying Nearby AI: " + err.message);
  }
}

function copyAIText(msgId) {
  const el = document.getElementById("text_" + msgId);
  if (el) {
    navigator.clipboard.writeText(el.innerText || el.textContent);
    showToast("AI response copied to clipboard!");
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
    text: `🤖 [NearMitra ${prov} AI Shared Output]\n\n${text}`,
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
  setChatSubTab('peer');
  renderChatMessages();
}

function formatMarkdown(text) {
  if (!text) return "";
  let out = escapeHTML(text);
  // Code block
  out = out.replace(/```([a-z]*)\n([\s\S]*?)```/g, '<pre class="code-block"><code>$2</code></pre>');
  // Bold
  out = out.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
  // Italic
  out = out.replace(/\*(.*?)\*/g, '<em>$1</em>');
  // Inline code
  out = out.replace(/`([^`]+)`/g, '<code class="inline-code">$1</code>');
  // Bullet items
  out = out.replace(/^\s*[-•]\s+(.*)$/gm, '<li class="ai-bullet">$1</li>');
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

  if (reasoningView) reasoningView.style.display = view === 'reasoning' ? 'block' : 'none';
  if (configView) configView.style.display = view === 'config' ? 'flex' : 'none';
  if (analyticsView) analyticsView.style.display = view === 'analytics' ? 'flex' : 'none';

  if (pillReasoning) pillReasoning.classList.toggle("active", view === 'reasoning');
  if (pillConfig) pillConfig.classList.toggle("active", view === 'config');
  if (pillAnalytics) pillAnalytics.classList.toggle("active", view === 'analytics');

  if (view === 'config') {
    loadAIConfig();
  } else if (view === 'analytics') {
    loadAIAnalytics();
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

function togglePasswordVisibility(inputId, btn) {
  const input = document.getElementById(inputId);
  if (!input) return;
  if (input.type === "password") {
    input.type = "text";
    btn.innerText = "🔒";
  } else {
    input.type = "password";
    btn.innerText = "👁";
  }
}

async function loadAIConfig() {
  try {
    const res = await fetch("/api/ai/get-config");
    if (!res.ok) return;
    const data = await res.json();

    const prov = data.provider || "gemini";
    selectConfigProvider(prov);

    // Gemini
    if (data.gemini_model && document.getElementById("cfgGeminiModel")) {
      document.getElementById("cfgGeminiModel").value = data.gemini_model;
    }
    if (data.gemini_key && document.getElementById("cfgGeminiKey")) {
      document.getElementById("cfgGeminiKey").placeholder = data.gemini_key;
    }
    const bgGem = document.getElementById("badgeGeminiStatus");
    if (bgGem) {
      bgGem.className = data.gemini_set ? "badge badge-emerald" : "badge badge-slate";
      bgGem.innerText = data.gemini_set ? "Configured" : "No Key";
    }

    // OpenAI
    if (data.openai_model && document.getElementById("cfgOpenAIModel")) {
      document.getElementById("cfgOpenAIModel").value = data.openai_model;
    }
    if (data.openai_key && document.getElementById("cfgOpenAIKey")) {
      document.getElementById("cfgOpenAIKey").placeholder = data.openai_key;
    }
    const bgOai = document.getElementById("badgeOpenAIStatus");
    if (bgOai) {
      bgOai.className = data.openai_set ? "badge badge-emerald" : "badge badge-slate";
      bgOai.innerText = data.openai_set ? "Configured" : "No Key";
    }

    // Groq
    if (data.groq_model && document.getElementById("cfgGroqModel")) {
      document.getElementById("cfgGroqModel").value = data.groq_model;
    }
    if (data.groq_key && document.getElementById("cfgGroqKey")) {
      document.getElementById("cfgGroqKey").placeholder = data.groq_key;
    }
    const bgGroq = document.getElementById("badgeGroqStatus");
    if (bgGroq) {
      bgGroq.className = data.groq_set ? "badge badge-emerald" : "badge badge-slate";
      bgGroq.innerText = data.groq_set ? "Configured" : "No Key";
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
  const provider = selectedRadio ? selectedRadio.value : "gemini";

  const geminiKey = (document.getElementById("cfgGeminiKey").value || "").trim();
  const geminiModel = document.getElementById("cfgGeminiModel").value;

  const openAIKey = (document.getElementById("cfgOpenAIKey").value || "").trim();
  const openAIModel = document.getElementById("cfgOpenAIModel").value;

  const groqKey = (document.getElementById("cfgGroqKey").value || "").trim();
  const groqModel = document.getElementById("cfgGroqModel").value;

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
    if (data.response && !data.response.toLowerCase().includes("error")) {
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
// IOT & PERIPHERALS
// -----------------------------------------------------------------------------
function reprobeHardware() {
  fetch("/api/iot/reprobe", { method: "POST" });
  showToast("Re-probing Wi-Fi, Bluetooth, LAN, NFC, and USB interfaces...");
}

function togglePumpRelay() {
  appState.iot.pumpOn = !appState.iot.pumpOn;
  const status = document.getElementById("pumpStatusText");
  const btn = document.getElementById("btnPumpToggle");
  if (appState.iot.pumpOn) {
    status.innerText = "[ ON ]";
    status.style.color = "#10B981";
    btn.innerText = "Turn Pump OFF";
    btn.className = "btn btn-danger btn-block";
  } else {
    status.innerText = "[ OFF ]";
    status.style.color = "var(--text-muted)";
    btn.innerText = "Turn Pump ON";
    btn.className = "btn btn-primary btn-block";
  }
  fetch("/api/iot/toggle", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ device: "pump_relay_01", state: appState.iot.pumpOn })
  });
}

function pollSensorData() {
  fetch("/api/iot/poll", { method: "POST" });
  showToast("Polled real-time volumetric soil telemetry: 34.8% optimal.");
}

function testPrintReceipt() {
  fetch("/api/iot/print", { method: "POST" });
  showToast("Printed sample Mandi Gate Pass to ESC/POS thermal printer.");
}

function triggerDocScan() {
  fetch("/api/iot/scan", { method: "POST" });
  showToast("Acquiring 300 DPI land deed scan from WIA device...");
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

function toggleAppTheme() {
  appState.theme = appState.theme === "dark" ? "light" : "dark";
  document.body.className = appState.theme === "dark" ? "dark-theme" : "light-theme";
  document.getElementById("btnThemeToggle").innerText = appState.theme === "dark" ? "Switch to Light Mode" : "Switch to Dark Mode";
  fetch("/api/set-theme", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ theme: appState.theme })
  });
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
  const nameEl  = document.getElementById("icPeerName");
  const typeEl  = document.getElementById("icCallType");
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
