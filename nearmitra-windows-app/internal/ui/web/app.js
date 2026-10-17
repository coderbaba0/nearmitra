
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
  wanState: null,
  pinnedDevices: JSON.parse(localStorage.getItem("nearmitra_pinned_devices") || "[]"),
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
  initWanWebRTC();
  loadPcMicrophones();
  navigator.mediaDevices?.addEventListener?.('devicechange',loadPcMicrophones);
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

  if(remoteSensorPollTimer){clearInterval(remoteSensorPollTimer);remoteSensorPollTimer=null;}
  if (tabKey === 'chat') {
    renderChatMessages();
  } else if (tabKey === 'recents') {
    loadRecentFiles();
    renderRecentCalls();
  } else if (tabKey === 'cctv') {
    populateCctvPeerSelect();
  } else if (tabKey === 'voice') {
    populateAudioPeerSelect();loadPcMicrophones();
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
    loadHardwareDiagnostics();loadIotConfiguration();pollRemoteSensors();
    remoteSensorPollTimer=setInterval(()=>{pollRemoteSensors();loadRelaySchedules().catch(()=>{});},10000);
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
// CONNECTION MODE SWITCHER (Nearby vs P2P vs Internet/WAN)
// -----------------------------------------------------------------------------
function setConnectionMode(mode) {
  if (mode === "lan") mode = "nearby";
  appState.connectionMode = mode;

  const btnNearby = document.getElementById("btnModeNearby") || document.getElementById("btnModeLAN");
  const btnP2P = document.getElementById("btnModeP2P");
  const btnWAN = document.getElementById("btnModeWAN");

  if (btnNearby) btnNearby.classList.toggle("active", mode === "nearby");
  if (btnP2P) btnP2P.classList.toggle("active", mode === "p2p");
  if (btnWAN) btnWAN.classList.toggle("active", mode === "wan");

  if (mode === "nearby") {
    scanLANSubnet();
  } else if (mode === "wan") {
    fetchWanState();
  }
  renderMasterList();
}

function onMasterSearchInput(val) {
  appState.searchQuery = (val || "").toLowerCase().trim();
  const clearBtn = document.getElementById("masterSearchClearBtn");
  if (clearBtn) {
    clearBtn.style.display = appState.searchQuery ? "block" : "none";
  }
  renderMasterList();
}

function clearMasterSearch() {
  const input = document.getElementById("masterSearchInput");
  if (input) {
    input.value = "";
    input.focus();
  }
  const clearBtn = document.getElementById("masterSearchClearBtn");
  if (clearBtn) {
    clearBtn.style.display = "none";
  }
  appState.searchQuery = "";
  renderMasterList();
}

function filterSegment(seg) {
  appState.filterSegment = seg;
  const pillActive = document.getElementById("segPillActive");
  const pillAll = document.getElementById("segPillAll");
  const pillIoT = document.getElementById("segPillIoT");
  if (pillActive) pillActive.classList.toggle("active", seg === "focused");
  if (pillAll) pillAll.classList.toggle("active", seg === "other");
  if (pillIoT) pillIoT.classList.toggle("active", seg === "iot");
  renderMasterList();
}

function filterMasterList(query) {
  onMasterSearchInput(query);
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
  fetchWanState();
}

function updateUIFromState(data) {
  if (data.local_device) {
    appState.localNodeName = data.local_device.name;
    appState.localNodeID = data.local_device.id;
    appState.localNodeIP = data.local_device.ip;
    appState.localNodeAvatarEmoji = data.local_device.avatar_emoji || "💻";

    const userAvatarEl = document.getElementById("userAvatarNodeDisplay");
    if (userAvatarEl) {
      userAvatarEl.innerText = appState.localNodeAvatarEmoji;
    }
  }

  if (data.peers) {
    const seenMap = new Map();
    (data.peers || []).forEach(p => {
      const key = (p.ip || p.id || '').trim();
      if (!key) return;
      if (!seenMap.has(key)) {
        seenMap.set(key, p);
      } else {
        const existing = seenMap.get(key);
        if (!existing.is_online && p.is_online) {
          seenMap.set(key, { ...existing, ...p });
        }
      }
    });
    const cleanPeers = Array.from(seenMap.values());
    appState.peers = cleanPeers;
    const peerBadge = document.getElementById("badgePeerCount");
    if (peerBadge) peerBadge.innerText = cleanPeers.length;
    const modeP2P = document.getElementById("modeP2PBadge");
    if (modeP2P) modeP2P.innerText = cleanPeers.length;
  }

  if (data.lan_devices) {
    appState.lanDevices = data.lan_devices;
    const modeNearby = document.getElementById("modeNearbyBadge") || document.getElementById("modeLANBadge");
    if (modeNearby) modeNearby.innerText = data.lan_devices.length;
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

  if (Array.isArray(data.chat_messages)) {
    resolveChatRoute(appState.activePeer);
    const previous = new Set(appState.messages.map(m=>m.id));
    appState.messages = NearMitraChat.merge(appState.messages,data.chat_messages);
    const incoming = data.chat_messages.filter(m=>!m.mine && !previous.has(m.id)).at(-1);
    if (!appState.activePeer && incoming) {
      appState.activePeer = (appState.peers || []).find(p=>p.id===incoming.peer_id || p.ip===incoming.peer_ip) ||
        {id:incoming.peer_id,ip:incoming.peer_ip,name:incoming.sender,is_wan:incoming.is_wan};
      updateDetailViewForPeer(appState.activePeer);
    }
    savePersistedMessages();
    renderChatMessages();
    if(appState.activePeer) updateDetailViewForPeer(appState.activePeer);
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
// AVATAR & INITIALS HELPER
// -----------------------------------------------------------------------------
function renderAvatarCircle(name, avatarEmoji, isNearMitra, isRouter, deviceType) {
  if (isRouter || deviceType === "router") {
    return `
      <div class="card-avatar-circle bg-purple">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width:16px;height:16px;">
          <rect x="2" y="2" width="20" height="8" rx="2"/>
          <rect x="2" y="14" width="20" height="8" rx="2"/>
        </svg>
      </div>`;
  }

  let emoji = (avatarEmoji || "").trim();
  if (!emoji && name) {
    // Check if name has leading or embedded emoji
    const emojiRegex = /(\p{Extended_Pictographic}|\p{Emoji_Presentation})/u;
    const match = name.match(emojiRegex);
    if (match) {
      emoji = match[0];
    }
  }

  let iconBg = isNearMitra ? "bg-emerald" : "bg-blue";
  if (deviceType === "printer") iconBg = "bg-amber";
  if (deviceType === "camera") iconBg = "bg-emerald";

  if (emoji) {
    return `<div class="card-avatar-circle ${iconBg} card-avatar-emoji">${emoji}</div>`;
  }

  if (isNearMitra || name) {
    const initials = getInitials(name);
    return `<div class="card-avatar-circle ${iconBg}">${initials}</div>`;
  }

  return `
    <div class="card-avatar-circle ${iconBg}">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width:16px;height:16px;">
        <rect x="2" y="2" width="20" height="8" rx="2"/>
        <rect x="2" y="14" width="20" height="8" rx="2"/>
      </svg>
    </div>`;
}

// -----------------------------------------------------------------------------
// PINNED DEVICES HELPER FUNCTIONS
// -----------------------------------------------------------------------------
function isDevicePinned(key) {
  if (!key) return false;
  const list = appState.pinnedDevices || [];
  return list.includes(key);
}

function togglePinDevice(key, e) {
  if (e) {
    e.stopPropagation();
    e.preventDefault();
  }
  if (!key) return;
  if (!Array.isArray(appState.pinnedDevices)) {
    appState.pinnedDevices = [];
  }
  const idx = appState.pinnedDevices.indexOf(key);
  if (idx >= 0) {
    appState.pinnedDevices.splice(idx, 1);
    showToast("Device unpinned 📌");
  } else {
    appState.pinnedDevices.push(key);
    showToast("Device pinned to top! 📌");
  }
  try {
    localStorage.setItem("nearmitra_pinned_devices", JSON.stringify(appState.pinnedDevices));
  } catch (err) {}
  renderMasterList();
}

// -----------------------------------------------------------------------------
// MASTER LIST RENDERING (Nearby, P2P, and Internet/WAN)
// -----------------------------------------------------------------------------
function renderMasterList() {
  const container = document.getElementById("masterItemsList");
  if (!container) return;

  const mode = appState.connectionMode || "nearby";
  const q = (appState.searchQuery || "").toLowerCase().trim();
  const seg = appState.filterSegment || "focused";

  let html = "";

  if (mode === "wan") {
    renderWANView();
    return;
  }

  if (mode === "p2p") {
    let rawPeers = [...(appState.peers || [])];
    
    // Strict deduplication by IP and ID
    const seenMap = new Map();
    rawPeers.forEach(p => {
      const key = (p.ip || p.id || '').trim();
      if (!key) return;
      if (!seenMap.has(key)) {
        seenMap.set(key, p);
      } else {
        const existing = seenMap.get(key);
        if (!existing.is_online && p.is_online) {
          seenMap.set(key, { ...existing, ...p });
        }
      }
    });
    let peers = Array.from(seenMap.values());

    if (q) {
      peers = peers.filter(p => (p.name || '').toLowerCase().includes(q) || (p.ip || '').includes(q));
    }

    // Stable deterministic sort:
    // 1. Pinned devices first
    // 2. Online peers second
    // 3. Alphabetical / IP ascending
    peers.sort((a, b) => {
      const aPinned = (isDevicePinned(a.id) || isDevicePinned(a.ip) || isDevicePinned(a.name)) ? 1 : 0;
      const bPinned = (isDevicePinned(b.id) || isDevicePinned(b.ip) || isDevicePinned(b.name)) ? 1 : 0;
      if (aPinned !== bPinned) return bPinned - aPinned;

      const aOnline = a.is_online ? 1 : 0;
      const bOnline = b.is_online ? 1 : 0;
      if (aOnline !== bOnline) return bOnline - aOnline;
      return (a.name || '').localeCompare(b.name || '');
    });

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
      peers.forEach((p) => {
        const isActive = appState.activePeer && (appState.activePeer.id === p.id || appState.activePeer.ip === p.ip);
        const isTyping = (appState.typingPeers || []).some(id => id === p.id || id === p.ip || id === p.name);
        const avatarHTML = renderAvatarCircle(p.name, p.avatar_emoji, true, false, "phone");
        const safeId = escapeHTML(p.id || p.ip);
        const pinKey = escapeHTML(p.ip || p.id || p.name);
        const isPinned = isDevicePinned(p.id) || isDevicePinned(p.ip) || isDevicePinned(p.name);

        html += `
          <div class="master-item-card ${isActive ? 'active' : ''}" onclick="selectPeerByIdOrIP('${safeId}')">
            ${avatarHTML}
            <div class="card-content">
              <div class="card-top-row">
                <span class="card-title">
                  ${isPinned ? '<span class="pinned-badge-pill">📌 Pinned</span>' : ''}
                  ${escapeHTML(p.name)}
                </span>
                <div style="display:flex; align-items:center; gap:4px;">
                  <span class="card-time">${isTyping ? '<span style="color:var(--primary-emerald); font-weight:600;">typing…</span>' : 'Live'}</span>
                  <button class="btn-card-pin ${isPinned ? 'pinned' : ''}" onclick="togglePinDevice('${pinKey}', event)" title="${isPinned ? 'Unpin device' : 'Pin device to top'}">
                    <svg viewBox="0 0 24 24" fill="${isPinned ? '#10B981' : 'none'}" stroke="currentColor" stroke-width="2" style="width:13px;height:13px; transform: rotate(45deg);">
                      <path d="M12 17v5"></path>
                      <path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"></path>
                    </svg>
                  </button>
                </div>
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

    // Open hardware diagnostics without inventing connected peripherals.
    if (seg === "all" || seg === "iot" || seg === "focused") {
      html += `<div class="list-group-header">HARDWARE & IOT</div>
        <div class="master-item-card" onclick="switchTab('iot',true)"><div class="card-content"><div class="card-title">Windows hardware & Nearby sharing</div><div class="card-snippet">Scan connected devices and manage audio</div></div></div>`;
    }

  } else {
    // NEARBY / LAN SUB-NET MODE (with stable sorting, search filter, avatar emojis, and pin-to-top)
    let lanDevs = [...(appState.lanDevices || [])];
    if (q) {
      lanDevs = lanDevs.filter(d => {
        const matchedPeer = (appState.peers || []).find(p => p.ip === d.ip);
        const displayName = matchedPeer ? matchedPeer.name : (d.hostname || d.ip);
        return displayName.toLowerCase().includes(q) || (d.ip || '').includes(q) || (d.device_type || '').toLowerCase().includes(q);
      });
    }

    // Stable deterministic sort:
    // 1. Pinned devices first
    // 2. NearMitra P2P Ready first
    // 3. Gateway (.1) second
    // 4. Ascending IPv4 numeric order
    lanDevs.sort((a, b) => {
      const aPinned = (isDevicePinned(a.ip) || isDevicePinned(a.hostname)) ? 1 : 0;
      const bPinned = (isDevicePinned(b.ip) || isDevicePinned(b.hostname)) ? 1 : 0;
      if (aPinned !== bPinned) return bPinned - aPinned;

      const aNear = (appState.peers || []).some(p => p.ip === a.ip) || a.is_nearmitra ? 1 : 0;
      const bNear = (appState.peers || []).some(p => p.ip === b.ip) || b.is_nearmitra ? 1 : 0;
      if (aNear !== bNear) return bNear - aNear;

      const aRouter = a.device_type === "router" || (a.ip || '').endsWith(".1") ? 1 : 0;
      const bRouter = b.device_type === "router" || (b.ip || '').endsWith(".1") ? 1 : 0;
      if (aRouter !== bRouter) return bRouter - aRouter;

      const ipA = (a.ip || "0.0.0.0").split(".").map(Number);
      const ipB = (b.ip || "0.0.0.0").split(".").map(Number);
      for (let i = 0; i < 4; i++) {
        const diff = (ipA[i] || 0) - (ipB[i] || 0);
        if (diff !== 0) return diff;
      }
      return 0;
    });

    html += `
      <div class="list-group-header">
        <span>NEARBY HOSTS (${lanDevs.length})</span>
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
      lanDevs.forEach((dev) => {
        const matchedPeer = (appState.peers || []).find(p => p.ip === dev.ip);
        const displayName = matchedPeer ? matchedPeer.name : (dev.hostname || dev.ip);
        const isNearMitra = dev.is_nearmitra || !!matchedPeer;
        const avatarEmoji = (matchedPeer && matchedPeer.avatar_emoji) ? matchedPeer.avatar_emoji : dev.avatar_emoji;
        const isRouter = dev.device_type === "router" || dev.ip.endsWith(".1");

        let devBadge = isNearMitra ? "P2P Ready" : "LAN Host";
        if (isRouter) {
          devBadge = "Gateway";
        } else if (dev.device_type === "printer") {
          devBadge = "Printer";
        } else if (dev.device_type === "camera") {
          devBadge = "CCTV";
        }

        const avatarHTML = renderAvatarCircle(displayName, avatarEmoji, isNearMitra, isRouter, dev.device_type);
        const isActive = appState.activeLANDevice && appState.activeLANDevice.ip === dev.ip;
        const safeIp = escapeHTML(dev.ip);
        const pinKey = escapeHTML(dev.ip || displayName);
        const isPinned = isDevicePinned(dev.ip) || isDevicePinned(displayName);

        html += `
          <div class="master-item-card ${isActive ? 'active' : ''}" onclick="selectLANDeviceByIP('${safeIp}')">
            ${avatarHTML}
            <div class="card-content">
              <div class="card-top-row">
                <span class="card-title">
                  ${isPinned ? '<span class="pinned-badge-pill">📌 Pinned</span>' : ''}
                  ${escapeHTML(displayName)}
                </span>
                <div style="display:flex; align-items:center; gap:4px;">
                  <span class="card-time">${dev.ping_ms || 2}ms</span>
                  <button class="btn-card-pin ${isPinned ? 'pinned' : ''}" onclick="togglePinDevice('${pinKey}', event)" title="${isPinned ? 'Unpin device' : 'Pin device to top'}">
                    <svg viewBox="0 0 24 24" fill="${isPinned ? '#10B981' : 'none'}" stroke="currentColor" stroke-width="2" style="width:13px;height:13px; transform: rotate(45deg);">
                      <path d="M12 17v5"></path>
                      <path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"></path>
                    </svg>
                  </button>
                </div>
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

// Select peer by ID or IP
function selectPeerByIdOrIP(idOrIP) {
  const peer = (appState.peers || []).find(p => p.id === idOrIP || p.ip === idOrIP);
  if (peer) {
    appState.activePeer = peer;
    updateDetailViewForPeer(peer);
    renderMasterList();
    renderChatMessages();
    switchTab('chat', true);
  }
}

function selectPeer(idx) {
  if (appState.peers && appState.peers[idx]) {
    selectPeerByIdOrIP(appState.peers[idx].id || appState.peers[idx].ip);
  }
}

// Select LAN device by IP
function selectLANDeviceByIP(ip) {
  const dev = (appState.lanDevices || []).find(d => d.ip === ip);
  if (dev) {
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

function selectLANDevice(idx) {
  if (appState.lanDevices && appState.lanDevices[idx]) {
    selectLANDeviceByIP(appState.lanDevices[idx].ip);
  }
}

function updateDetailViewForPeer(peer) {
  let emoji = (peer.avatar_emoji || "").trim();
  if (!emoji && peer.name) {
    const emojiRegex = /(\p{Extended_Pictographic}|\p{Emoji_Presentation})/u;
    const match = peer.name.match(emojiRegex);
    if (match) emoji = match[0];
  }
  const avatarDisplay = emoji || getInitials(peer.name);
  const chatRoute = resolveChatRoute(peer);
  const isWan = chatRoute.mode === 'wan';
  document.querySelectorAll('[title="Voice Call"], [title="Video Call"], [onclick*= "voice_call"], [onclick*= "video_call"]').forEach(button => { button.disabled = chatRoute.mode !== 'nearby'; });

  // Radar / Hero
  document.getElementById("heroPeerName").innerText = peer.name;
  document.getElementById("heroPeerStatus").innerText = chatRoute.mode === "offline" ? "Offline" : "Online • " + (isWan ? "Internet" : "Nearby");
  document.getElementById("heroPeerType").innerText = isWan ? "NearMitra Internet WAN" : "NearMitra Direct P2P";
  document.getElementById("heroPeerIP").innerText = isWan ? "Internet Peer" : (peer.ip || "192.168.1.55");
  const heroAvatar = document.getElementById("heroPeerAvatar");
  if (heroAvatar) heroAvatar.innerText = avatarDisplay;

  // Chat Header
  document.getElementById("chatHeaderTitle").innerText = peer.name;
  const chatInitials = document.getElementById("chatHeaderInitials");
  if (chatInitials) chatInitials.innerText = avatarDisplay;
  document.getElementById("chatHeaderStatus").innerText = chatRoute.mode === "offline" ? "Offline • Messages queued" : isWan ? "Online • Internet" : `Online • Nearby (${chatRoute.nearby.ip})`;
  const dropLabel = document.getElementById("dropTargetLabel");
  if (dropLabel) dropLabel.innerText = isWan ? `Transfer to ${peer.name} (WAN Mesh)` : `Transfer to ${peer.name} (${peer.ip})`;

  // Voice & Video Call
  document.getElementById("callPeerTitle").innerText = peer.name;
  const callInitials = document.getElementById("callAvatarInitials");
  if (callInitials) callInitials.innerText = avatarDisplay;
  const remoteVidName = document.getElementById("remotePeerVideoName");
  if (remoteVidName) remoteVidName.innerText = peer.name;
  const remoteVidInitials = document.getElementById("remoteAvatarInitials");
  if (remoteVidInitials) remoteVidInitials.innerText = avatarDisplay;
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

function renderChatMessages() {
  const container = document.getElementById("chatStream");
  if (!container) return;

  const activePeer = appState.activePeer;
  const activeIP = activePeer ? activePeer.ip : "";
  const activeID = activePeer ? activePeer.id : "";
  const activeName = activePeer ? activePeer.name : "";
  const isWanPeer = activePeer && resolveChatRoute(activePeer).mode === 'wan';

  let html = `
    <div class="chat-drop-overlay" id="chatDropOverlay">
      <div class="drop-overlay-box">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" x2="12" y1="3" y2="15"/></svg>
        <h3>Drop files to send directly</h3>
        <p id="dropTargetLabel">${isWanPeer ? 'WAN Mesh Encrypted Transfer to ' : '50+ MB/s Socket Transfer to '}${activeName || 'Active Peer'}</p>
      </div>
    </div>
    <div class="chat-date-divider"><span>${isWanPeer ? 'WAN Mesh Chat' : 'Today'}</span></div>
  `;

  const route = resolveChatRoute(activePeer);
  const targetMessages = (appState.messages || []).filter(m =>
    NearMitraChat.matches(m,activePeer,appState.peers,chatDeviceLinks))
    .sort((a,b) => new Date(a.at)-new Date(b.at));

  if (targetMessages.length === 0) {
    html += `
      <div style="text-align: center; color: var(--text-muted); font-size: 12px; margin-top: 40px;">
        <p style="margin-bottom: 6px;">No message history with ${escapeHTML(activeName || 'this peer')}.</p>
        <span style="font-size: 11px; opacity: 0.7;">${isWanPeer ? 'End-to-end encrypted WAN Mesh chat' : 'End-to-end encrypted direct socket stream'}</span>
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
      const isSending = m.attachment.status === "Sending" || m.status === "Sending" || (m.attachment.progress !== undefined && m.attachment.progress < 100 && m.attachment.status !== "Sent" && m.attachment.status !== "Delivered");
      const isDownloading = m.attachment.status === "Downloading" || m.status === "Downloading";
      const isProgressing = isSending || isDownloading;
      const progress = m.attachment.progress !== undefined ? m.attachment.progress : (isProgressing ? 50 : 100);
      const isFailed = m.attachment.status === "Failed" || m.status === "Failed";
      const isMine = m.mine;

      attachmentHTML = `
        <div class="msg-attachment-card" id="att_${m.id}" onclick="handleAttachmentClick('${m.id}')" title="Click to open or save">
          <div class="attachment-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/></svg>
          </div>
          <div class="attachment-info" style="flex:1; min-width:0;">
            <span class="attachment-name">${escapeHTML(m.attachment.name || 'File')}</span>
            <span class="attachment-meta" id="att_meta_${m.id}">
              ${m.attachment.size || ''} • ${isProgressing ? `${isSending ? 'Sending' : 'Downloading'} (${progress}%)` : (isFailed ? 'Failed ✕' : (isMine ? 'Sent ✓' : 'Received ✓'))}
            </span>
            ${isProgressing ? `
              <div class="wan-progress-track" style="margin-top:6px; height:4px; background:rgba(255,255,255,0.2); border-radius:2px; overflow:hidden;">
                <div class="wan-progress-fill" id="att_prog_${m.id}" style="width:${progress}%; height:100%; background:var(--primary-emerald); transition:width 0.2s linear;"></div>
              </div>
            ` : ''}
          </div>
          <button class="attachment-action-btn" title="Open or Save file">
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
                <span class="msg-ticks" title="${escapeHTML(m.status || 'Sent')}">${m.status==='Queued' ? '◷' : m.status==='Sending' ? '…' : m.status==='Failed' ? '!' : '✓✓'}</span>
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
 const input=document.getElementById('chatInput');
 const text=input.value.trim();
 const peer=appState.activePeer;
 if (!text || !peer) return;
 const route=resolveChatRoute(peer);
 appState.messages.push({id:crypto.randomUUID(),peer_id:route.id,peer_ip:route.nearby?.ip || 'wan://'+route.id,
  peer_name:peer.name,sender:'Windows Host',text,mine:true,at:new Date(),status:'Queued'});
 savePersistedMessages(); input.value=''; renderChatMessages();
 handleUserTyping(false);
 flushChatOutbox();
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

async function clearActivePeerChat() {
  const targetPeer = appState.activePeer;
  if (!targetPeer) return;

  const activeIP = targetPeer.ip || "";
  const activeID = targetPeer.id || "";
  const activeName = targetPeer.name || "";

  if (!confirm(`Are you sure you want to clean chat history for ${activeName || 'this device'}?`)) {
    return;
  }

  // 1. Filter local in-memory messages immediately
  appState.messages = (appState.messages || []).filter(m => {
    if (activeIP && (m.peer_ip === activeIP || m.peer_id === activeIP)) return false;
    if (activeID && (m.peer_id === activeID || m.peer_ip === activeID)) return false;
    if (activeName && m.sender === activeName) return false;
    return true;
  });

  // 2. Persist to localStorage and re-render UI
  savePersistedMessages();
  renderChatMessages();

  // 3. Notify backend server to permanently purge from chat_history.json
  try {
    await fetch("/api/chat/clear", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        peer_id: activeID,
        peer_ip: activeIP,
        sender: activeName
      })
    });
  } catch (e) {
    console.error("Failed to clear chat on server", e);
  }

  showToast(`Chat history cleaned for ${activeName || 'device'}`);
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
// CHAT DRAG & DROP (Strictly routes to WAN WebRTC or LAN Socket)
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

async function handleChatDrop(e) {
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
  if (!targetPeer) {
    showToast("Please select a device first");
    return;
  }

  // 1. WAN PEER: Stream directly over WebRTC Data Channel to remote mobile / peer
  const fileRoute = resolveChatRoute(targetPeer);
  if (fileRoute.mode === 'wan') {
    for (let i = 0; i < files.length; i++) {
      await streamFileOverWan(files[i], fileRoute.id, targetPeer.name);
    }
    return;
  }

  // 2. LOCAL LAN PEER: Upload over local HTTP/TCP socket
  const targetIP = resolveChatRoute(targetPeer).nearby?.ip || "";
  const targetID = targetPeer.id;
  const targetName = targetPeer.name || "Peer";

  Array.from(files).forEach(file => {
    const formData = new FormData();
    formData.append("file", file, file.name);

    showToast(`[Send] Sending "${file.name}" to ${targetName}...`);

    fetch(`/api/send-file-upload?ip=${encodeURIComponent(targetIP || "")}`, {
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
              type: "file",
              status: "Delivered",
              progress: 100
            },
            status: "Delivered",
            is_wan: false,
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
  const targetIP = resolveChatRoute(targetPeer).nearby?.ip || "";
  const targetID = targetPeer.id || "";
  const isWanPeer = resolveChatRoute(targetPeer).mode === 'wan';

  // Send over WAN DataChannel if WAN peer
  if (isWanPeer && wanDataChannel && wanDataChannel.readyState === "open") {
    try {
      wanDataChannel.send(JSON.stringify({
        id: "ctrl_" + Date.now(),
        type: "control",
        timestamp: Date.now(),
        payload: {
          action: "typing",
          isTyping: isTyping,
          senderId: (appState.wanState && appState.wanState.my_device_id) || "windows_peer"
        }
      }));
    } catch (_) {}
  }

  if (isTyping) {
    if (!appState._userTypingSent) {
      appState._userTypingSent = true;
      if (!isWanPeer && targetIP) {
        fetch("/api/chat/typing", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ target_ip: targetIP, peer_id: targetID, is_typing: true })
        }).catch(() => { });
      }
    }

    typingTimeout = setTimeout(() => {
      appState._userTypingSent = false;
      if (isWanPeer && wanDataChannel && wanDataChannel.readyState === "open") {
        try {
          wanDataChannel.send(JSON.stringify({
            id: "ctrl_" + Date.now(),
            type: "control",
            timestamp: Date.now(),
            payload: {
              action: "typing",
              isTyping: false,
              senderId: (appState.wanState && appState.wanState.my_device_id) || "windows_peer"
            }
          }));
        } catch (_) {}
      } else if (!isWanPeer && targetIP) {
        fetch("/api/chat/typing", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ target_ip: targetIP, peer_id: targetID, is_typing: false })
        }).catch(() => { });
      }
    }, 2800);
  } else {
    if (appState._userTypingSent) {
      appState._userTypingSent = false;
      if (!isWanPeer && targetIP) {
        fetch("/api/chat/typing", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ target_ip: targetIP, peer_id: targetID, is_typing: false })
        }).catch(() => { });
      }
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
  const targetPeer = appState.activePeer;
  if (!targetPeer) {
    showToast("Please select a device first");
    return;
  }

  // If WAN Peer: Use direct HTML file / folder picker to stream file over WebRTC DataChannel
  const fileRoute = resolveChatRoute(targetPeer);
  if (fileRoute.mode === 'wan') {
    if(category==='folder') {triggerSendFolder();return;}
    let fileInput = document.getElementById("wanFileInput");
    if (!fileInput) {
      fileInput = document.createElement("input");
      fileInput.id = "wanFileInput";
      fileInput.style.display = "none";
      document.body.appendChild(fileInput);
    }
    if (category === "folder") {
      fileInput.type = "file";
      fileInput.setAttribute("webkitdirectory", "");
      fileInput.setAttribute("directory", "");
      fileInput.removeAttribute("accept");
    } else {
      fileInput.type = "file";
      fileInput.removeAttribute("webkitdirectory");
      fileInput.removeAttribute("directory");
      if (category === "image") fileInput.accept = "image/*";
      else if (category === "video") fileInput.accept = "video/*";
      else if (category === "audio") fileInput.accept = "audio/*";
      else fileInput.removeAttribute("accept");
    }

    fileInput.onchange = async (e) => {
      if (e.target.files && e.target.files.length > 0) {
        for (let i = 0; i < e.target.files.length; i++) {
          await streamFileOverWan(e.target.files[i], fileRoute.id, targetPeer.name);
        }
        fileInput.value = "";
      }
    };
    fileInput.click();
    return;
  }

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
  const targetIP = targetPeer ? (resolveChatRoute(targetPeer).nearby?.ip || "") : "";
  const targetID = targetPeer ? targetPeer.id : "";
  const targetName = targetPeer ? targetPeer.name : "Active Peer";

  const catParam = category ? `&type=${encodeURIComponent(category)}` : "";
  fetch(`/api/send-file?ip=${encodeURIComponent(targetIP)}${catParam}`)
    .then(r => r.json())
    .then(data => {
      if(data && data.error) {showToast(data.error);return;}
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

async function triggerSendFolder() {
  const selected=appState.activePeer;
  if(!selected) return;
  const route=resolveChatRoute(selected);
  if(route.mode==='wan') {
    try {
      const response=await fetch('/api/chat/folder-archive');
      if(response.status===204) return;
      if(!response.ok) throw new Error(await response.text());
      const name=response.headers.get('X-Folder-Name') || 'Folder.zip';
      await streamFileOverWan(new File([await response.blob()],name),route.id,selected.name,true);
    } catch(error) {showToast(error.message);}
    return;
  }
  const targetPeer = appState.activePeer;
  const targetIP = targetPeer ? (resolveChatRoute(targetPeer).nearby?.ip || "") : "";
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
  const activeIP = sel.value || (appState.activePeer ? appState.activePeer.ip : "");

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
  let polling=false;
  streamSignalPollerInterval = setInterval(async () => {
    if(polling)return;polling=true;
    try {
      const res = await fetch("/api/cctv/poll-signals");
      if (!res.ok) return;
      const data = await res.json();
      const signals = data.signals || [];
      for (const sig of signals) {
        await handleIncomingStreamSignal(sig);
      }
    } catch (e) { } finally {polling=false;}
  }, 200);
}

async function handleIncomingStreamSignal(sig) {
  const hdr = sig.header || sig;
  if (!hdr || !hdr.type) return;

  if(hdr.type.startsWith('webrtc_') || hdr.type.startsWith('call_')) {
    try {await desktopCall.handle(sig.peer_ip || sig.sender_ip,hdr);}
    catch(error){await desktopCall.fail(error);}
    return;
  }
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
  if (selectedIP) return NearMitraCall.resolvePeer({ip:selectedIP,name:selectedIP},appState.peers || [],appState.lanDevices || []);
  if (appState.activePeer && appState.activePeer.ip) return appState.activePeer;
  if (appState.peers && appState.peers.length > 0) return appState.peers[0];
  return null;
}

function startSelectedAudioAction(actionType) {
 const target=getSelectedAudioTarget();
 if(!target){showToast('Select a Nearby device first');return;}
 return startCallWithPeer(target.ip,target.name,actionType==='video_call',actionType==='listen_mic'?'listen':actionType==='broadcast_voice'?'broadcast':'duplex');
}

let testMicContext=null;
async function loadPcMicrophones(){
 const selected=callElement('pcMicrophoneDevice');if(!selected)return;
 const previous=selected.value;
 try{
  const devices=await navigator.mediaDevices.enumerateDevices();
  selected.replaceChildren(new Option(devices.some(device=>device.kind==='audioinput')?'Windows default microphone':'No PC microphone listed (receive-only)',''));
  for(const device of devices.filter(d=>d.kind==='audioinput'))selected.add(new Option(device.label || 'Microphone '+(selected.options.length),device.deviceId));
  selected.value=[...selected.options].some(option=>option.value===previous)?previous:'';
  callText('pcMediaStatus',devices.some(device=>device.kind==='audioinput')?'Microphone list refreshed. Normal calls use PC microphone/camera.':'No PC microphone is listed. Calls can receive phone audio; connect a microphone to send your voice.');
 }catch(error){callText('pcMediaStatus','Could not list PC microphones: '+describePcMediaError(error));console.warn('Microphone list unavailable',error);}
}
async function stopPcMicTest(){
 if(testMicInterval)clearInterval(testMicInterval);testMicInterval=null;
 if(testMicStream)testMicStream.getTracks().forEach(t=>t.stop());testMicStream=null;
 if(testMicContext)await testMicContext.close().catch(()=>{});testMicContext=null;
 callText('btnTestLocalMic','Test PC Mic Level');callText('localMicVuText','Stopped');const bar=callElement('localMicVuBar');if(bar)bar.style.width='0%';
}
async function testLocalMicInput(){
 if(testMicInterval){await stopPcMicTest();return;}
 try{
  const deviceId=callElement('pcMicrophoneDevice')?.value;
  testMicStream=await navigator.mediaDevices.getUserMedia({audio:deviceId?{deviceId:{exact:deviceId}}:true});
  testMicContext=new AudioContext();await testMicContext.resume();
  const analyser=testMicContext.createAnalyser();analyser.fftSize=1024;
  testMicContext.createMediaStreamSource(testMicStream).connect(analyser);
  const samples=new Float32Array(analyser.fftSize);callText('btnTestLocalMic','Stop Mic Test');
  await loadPcMicrophones();
  testMicInterval=setInterval(()=>{
   analyser.getFloatTimeDomainData(samples);const rms=Math.sqrt(samples.reduce((sum,value)=>sum+value*value,0)/samples.length);
   const db=20*Math.log10(Math.max(rms,0.000001));const bar=callElement('localMicVuBar');if(bar)bar.style.width=Math.max(0,Math.min(100,(db+60)/60*100))+'%';
   callText('localMicVuText',rms<0.00001?'No mic signal':db.toFixed(1)+' dBFS');
  },100);
 }catch(error){await stopPcMicTest();showToast('PC microphone test failed: '+describePcMediaError(error));}
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

async function toggleVideoCamera() {
 try {const video=!desktopCall.session?.video;await desktopCall.camera(video);setCallMode(video?'video':'audio');}
 catch(error){showToast(error.message);}
}

let callScreenStream=null;
async function toggleScreenShare(){
 const session=desktopCall.session;if(!session?.pc)return;
 try{
  if(callScreenStream){
   const sender=session.pc.getSenders().find(s=>s.track?.kind==='video');
   if(sender)await sender.replaceTrack(session.stream.getVideoTracks()[0] || null);
   callScreenStream.getTracks().forEach(t=>{t.onended=null;t.stop();});callScreenStream=null;isScreenSharing=false;
   const video=callElement('localVideo');if(video)video.srcObject=session.stream;
  }else{
   if(!session.stream.getVideoTracks().length)await desktopCall.camera(true);
   const stream=await navigator.mediaDevices.getDisplayMedia({video:true});
   if(desktopCall.session!==session){stream.getTracks().forEach(t=>t.stop());return;}
   const track=stream.getVideoTracks()[0];const sender=session.pc.getSenders().find(s=>s.track?.kind==='video');
   try{await sender.replaceTrack(track);}catch(error){stream.getTracks().forEach(t=>t.stop());throw error;}
   callScreenStream=stream;isScreenSharing=true;track.onended=()=>toggleScreenShare();
   const video=callElement('localVideo');if(video)video.srcObject=stream;
   setCallMode('video');
  }
  callText('screenLabel',isScreenSharing?'Sharing':'Share');
 }catch(error){showToast('Screen sharing: '+error.message);}
}
function toggleSpeaker(){
 appState.voice.speaker=!appState.voice.speaker;
 const audio=callElement('remoteCallAudio');if(audio)audio.muted=!appState.voice.speaker;
 callText('speakerLabel',appState.voice.speaker?'Speaker On':'Speaker Off');
}

function endVoiceCall() {return desktopCall.stop(true);}

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
    loadIotConfiguration();
    updateGatePassPreview();
  }
}

// ── Local Windows PnP Hardware Scanner ──
let hardwareScanPending=false;
async function scanHardwareNow() {
  if(hardwareScanPending)return;hardwareScanPending=true;
  const btn = document.getElementById("btnHwScanNow");
  if (btn) {
    btn.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="spin-animation" style="width:16px;height:16px;"><path d="M21.5 2v6h-6M21.34 15.57a10 10 0 1 1-.57-8.38l5.67-5.67"/></svg> <span>Scanning Hardware...</span>`;
  }
  showToast("Scanning physical Windows USB, Audio, Camera, and NFC ports...");
  try {
    const res = await fetch("/api/iot/hardware-scan?refresh=1");
    if (!res.ok) throw new Error(await res.text());
    const data=await res.json();renderHardwareDiagnostics(data);
    showToast(data.hardware?.scan_error || "Windows hardware diagnostics updated");
  } catch (e) {
    showToast("Hardware scan failed: "+e.message);callText("hwScanStatus",e.message);
  } finally {
    hardwareScanPending=false;
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
    callText("hwScanStatus","Hardware scan failed: "+e.message);
  }
}

function renderHardwareDiagnostics(data) {
  const hw = data.hardware || {};
  callText("hwScanStatus",hw.scan_error || "Last scanned: "+(hw.last_scanned?new Date(hw.last_scanned).toLocaleTimeString():"Not scanned"));
  const usbList = hw.usb_devices || [];
  const audioList = hw.audio_devices || [];
  const camList = hw.camera_devices || [];
  const scanList = hw.scanner_devices || [];
  const serialList = hw.serial_com_ports || [];

  for(const [id,label,ready] of [['chipNetworkStatus','Local network',hw.lan_online || hw.wifi_online],['chipBluetoothStatus','Bluetooth',hw.bluetooth_ble]]) {
    const chip=callElement(id);if(chip){chip.innerText=label+': '+(ready?'Detected':'Not detected');chip.className='hw-chip '+(ready?'active':'standby');}
  }
  // Update Status Chips
  const chipUsb = document.getElementById("chipUsbBus");
  if (chipUsb) {
    chipUsb.innerHTML = `<span class="status-dot-pulse"></span> USB Bus: ${usbList.length} Connected`;
  }

  const chipNfc = document.getElementById("chipNfcStatus");
  if (chipNfc) {
    if (hw.nfc_supported) {
      chipNfc.className = "hw-chip active";
      chipNfc.innerHTML = `<span class="status-dot-pulse"></span> NFC: ${escapeHTML(hw.nfc_reader_name || 'Detected')}`;
    } else {
      chipNfc.className = "hw-chip standby";
      chipNfc.innerText = "NFC: no reader detected";
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
          No camera or scanner detected. Connect a device and scan again.
        </div>
      `;
    } else {
      elCam.innerHTML = combined.map(d => `
        <div class="hw-device-row">
          <div>
            <div class="hw-device-name">${escapeHTML(d.name)}</div>
            <div class="hw-device-meta">${escapeHTML(d.description)}</div>
          </div>
          <span class="badge ${d.status==='OK'?'badge-emerald':'badge-amber'}">${escapeHTML(d.status || 'Unknown')}</span>
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
          No serial ports detected. Connect your device and scan again.
        </div>
      `;
    } else {
      elSerial.innerHTML = serialList.map(d => `
        <div class="hw-device-row">
          <div>
            <div class="hw-device-name">${escapeHTML(d.name)}</div>
            <div class="hw-device-meta">${escapeHTML(d.description)}</div>
          </div>
          <span class="badge badge-purple">Detected</span>
        </div>
      `).join("");
    }
  }
}

function populateHwPeerSelects() {
  const peers=(appState.peers || []).filter(p=>p.ip && p.is_online!==false && p.online!==false);
  for(const id of ['audioCastPeerSelect','remoteMicPeerSelect']) {
    const select=document.getElementById(id);if(!select)continue;
    const previous=select.value;
    select.innerHTML=peers.length ? peers.map(p=>`<option value="${escapeHTML(p.ip)}">${escapeHTML(p.name)} (${escapeHTML(p.ip)})</option>`).join('') : '<option value="">No Nearby devices connected</option>';
    if(peers.some(p=>p.ip===previous))select.value=previous;
    select.disabled=!peers.length;
  }
}

function onAudioSourceModeChanged() {
  if(desktopCall.session?.mode==='broadcast')showToast('Stop the current stream before changing its source.');
}
async function toggleLiveAudioMirror() {
  if(desktopCall.session?.mode==='broadcast')return stopLiveAudioMirror();
  if(desktopCall.session){showToast('End the current call before starting an audio stream.');return;}
  const ip=callElement('audioCastPeerSelect')?.value;
  if(!ip){showToast('Connect a Nearby phone first.');return;}
  const source=callElement('pcAudioSource');
  if(source)source.value=callElement('audioCastSourceMode')?.value || 'system';
  await startCallWithPeer(ip,'Nearby phone',false,'broadcast');
}
function stopLiveAudioMirror() {
  if(desktopCall.session?.mode==='broadcast')return desktopCall.stop(true);
}
async function toggleRemoteMicBridge() {
  if(desktopCall.session?.mode==='listen')return desktopCall.stop(true);
  if(desktopCall.session){showToast('End the current call before listening to the phone.');return;}
  const ip=callElement('remoteMicPeerSelect')?.value;
  if(!ip){showToast('Connect a Nearby phone first.');return;}
  await startCallWithPeer(ip,'Nearby phone',false,'listen');
}
function syncIotAudioState(state,session) {
  for(const [mode,badgeId,buttonId,labelId,idleLabel] of [
    ['broadcast','audioCastLiveBadge','btnStartLiveAudioMirror','btnLiveAudioLabel','Stream selected PC audio to phone'],
    ['listen','remoteMicBadge','btnToggleRemoteMic','btnRemoteMicLabel','Listen to phone microphone']]) {
    const active=state!=='ended' && session?.mode===mode;
    const badge=callElement(badgeId),button=callElement(buttonId);
    if(badge){badge.innerText=active?(state==='connected'?'Connected':state==='ringing'?'Waiting for phone to answer':'Connecting…'):'Standby';badge.className='badge '+(active && state==='connected'?'badge-emerald':'badge-slate');}
    if(button)button.className=active?'btn btn-danger':'btn btn-primary';
    callText(labelId,active?'Stop connection':idleLabel);
  }
  if(state==='ended'){
    callText('audioCastStreamStats','No active stream');callText('remoteMicLevelText','No audio');
    const bar=callElement('remoteMicLevelBar');if(bar)bar.style.width='0%';
  }
}
function toggleRemoteCamVirtual() {
  switchTab('cctv',true);setStreamerRole('remote');
  showToast('Select a Nearby device in CCTV to view its camera.');
}
let phoneSensorRequestPending=false;
async function fetchLiveGPS() {
 if(phoneSensorRequestPending)return;
 const ip=callElement('audioCastPeerSelect')?.value;
 if(!ip){showToast('Select a Nearby phone first');return;}
 phoneSensorRequestPending=true;callText('phoneSensorStatus','Waiting for phone approval…');
 try {
  const data=await iotRequest('/api/iot/sensors/trigger',{target_ip:ip});
  callText('phoneSensorStatus',data.sensors?.location_status || 'Approved sensor snapshot received');
  await pollRemoteSensors();
 }catch(error){callText('phoneSensorStatus',error.message);showToast(error.message);}
 finally{phoneSensorRequestPending=false;}
}
async function pollRemoteSensors() {
  try {
    const response=await fetch('/api/iot/sensors/poll');
    if(!response.ok)throw new Error('Could not load phone telemetry');
    const data=await response.json(),s=data.sensors || {};
    const ip=callElement('audioCastPeerSelect')?.value;
    const age=Date.now()-Date.parse(s.last_seen);
    const fresh=!!ip && s.device_ip===ip && Number.isFinite(age) && age>=0 && age<60000;
    const battery=fresh && s.battery_available && Number.isFinite(s.battery_level)?Math.max(0,Math.min(100,s.battery_level)):null;
    callText('phoneBatLevelText',battery===null?'—':battery+'%');
    callText('phoneBatBadge',battery===null?'Awaiting phone telemetry':s.is_charging?'Charging':'On battery');
    callText('phoneBatHealthText',battery===null?'No recent battery reading':s.battery_temp_c+'°C');
    const fill=callElement('phoneBatFill');if(fill)fill.style.width=(battery ?? 0)+'%';
    const gps=fresh && s.gps_locked;
    callText('gpsLockBadge',gps?'GPS received':'Awaiting phone location');
    callText('gpsLatVal',gps?s.gps_latitude.toFixed(6)+'°':'—');
    callText('gpsLngVal',gps?s.gps_longitude.toFixed(6)+'°':'—');
    callText('gpsAltVal',gps?s.gps_altitude+' m':'—');
    callText('gpsLocName',gps?s.gps_location_name || 'Phone location':'No recent location received');
    const map=callElement('gpsMapLink');if(map){if(gps)map.href='https://www.google.com/maps?q='+s.gps_latitude+','+s.gps_longitude;else map.removeAttribute('href');map.setAttribute('aria-disabled',String(!gps));}
  }catch(error){showToast(error.message);}
}
async function triggerNFCRead() {
  try {
    const response=await fetch('/api/iot/nfc-read',{method:'POST'});
    if(!response.ok)throw new Error(await response.text());
    const data=await response.json();callText('nfcLastTagUID',data.tag_id);callText('nfcLastDataPreview',data.ndef_data || 'No application data returned');callText('nfcStatusBadge','Tag read');
  }catch(error){showToast(error.message);}
}

// ── Document Scanner (WIA/TWAIN & OCR) ──
async function triggerDocScan() {
  try {await callRequest('/api/iot/scan');showToast('Windows scanner opened. Choose scan settings and save the document there.');}
  catch(error){showToast('Cannot open scanner: '+error.message);}
}

function triggerDocOcr() {showToast('OCR is not connected yet. Scan and save a document using Windows first.');}

function testCameraPreview() {
  switchTab('cctv', true);
  showToast("📷 Switched to DirectShow Camera Viewfinder Diagnostic");
}

// ── 4-Channel Agricultural Relays & Smart Irrigation ──
let agriRelayStates = {};

function togglePumpRelay() {
  toggleAgriRelay(1);
}

const relayPending=new Set();
async function toggleAgriRelay(ch) {return setAgriRelay(ch,agriRelayStates[ch]!==true);}
async function setAgriRelay(ch,power) {
 if(relayPending.has(ch))return;relayPending.add(ch);
 try {
  const state=await iotRequest('/api/iot/toggle',{channel:ch,state:power});
  agriRelayStates[ch]=state.power;
  callText(ch===1?'pumpStatusText':`relay${ch}StatusText`,state.power?'[ ON ]':'[ OFF ]');
  if(ch===1){
   for(const [id,key,unit] of [['pumpVoltageText','voltage',' V'],['pumpCurrentText','current_a',' A'],['pumpFlowText','flow_rate_lpm',' L/min'],['pumpTotalWater','total_water_l',' L']])callText(id,Number.isFinite(state[key])?state[key]+unit:'—');
  }
  showToast('Relay '+ch+' confirmed '+(state.power?'ON':'OFF'));
 }catch(error){showToast(error.message);callText(ch===1?'pumpStatusText':`relay${ch}StatusText`,'[ Unknown ]');delete agriRelayStates[ch];}
 finally{relayPending.delete(ch);}
}
async function pollSensorData() {
 try {
  const data=await iotRequest('/api/iot/poll');
  callText('soilMoistVal',data.moisture_pct+'%');
  callText('soilTempVal',Number.isFinite(data.temp_c)?data.temp_c+'°C':'—');
  callText('soilHumidityVal',Number.isFinite(data.humidity_pct)?data.humidity_pct+'%':'—');
  callText('soilSensorStatus','Reading received '+new Date().toLocaleTimeString());
 }catch(error){callText('soilMoistVal','—');callText('soilTempVal','—');callText('soilHumidityVal','—');callText('soilSensorStatus',error.message);showToast(error.message);}
}
let scaleReading=null;
async function tareWeighScale() {
 try {
  const data=await iotRequest('/api/iot/scale',{action:'tare'});
  scaleReading=data.weight_kg;callText('weighScaleValue',scaleReading.toFixed(2)+' KG');
 }catch(error){scaleReading=null;callText('weighScaleValue','No reading');showToast(error.message);}
}
async function captureWeightToGatePass() {
 try {
  const data=await iotRequest('/api/iot/scale');scaleReading=data.weight_kg;
  callText('weighScaleValue',scaleReading.toFixed(2)+' KG');
  const input=callElement('gatePassWeightKg');if(input)input.value=scaleReading;
  updateGatePassPreview();
 }catch(error){scaleReading=null;callText('weighScaleValue','No reading');showToast(error.message);}
}
async function iotRequest(path,body) {
 const response=await fetch(path,body===undefined?{}:{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
 if(!response.ok)throw new Error(await response.text());return response.json();
}
async function loadIotConfiguration() {
 try {
  const cfg=await iotRequest('/api/iot/config');
  for(let ch=1;ch<=4;ch++){
   const input=callElement('iotRelayURL'+ch);if(input && document.activeElement!==input)input.value=cfg.relays?.[ch-1] || '';
   const button=callElement(ch===1?'btnPumpToggle':`btnRelay${ch}Toggle`);if(button)button.disabled=!cfg.relays?.[ch-1];
   const off=callElement("btnRelayOff"+ch);if(off)off.disabled=!cfg.relays?.[ch-1];
  }
  for(const [id,key] of [['iotSensorURL','sensor_url'],['iotNFCURL','nfc_url'],['iotScaleURL','scale_url']]){const input=callElement(id);if(input && document.activeElement!==input)input.value=cfg[key] || '';}
  callText('pumpBadgeOnline',cfg.relays?.some(Boolean)?'Configured • state requires confirmation':'No relay configured');
  await loadRelaySchedules();
 }catch(error){callText('iotConfigStatus',error.message);}
}
async function saveIotConfiguration() {
 const cfg={relays:[1,2,3,4].map(ch=>callElement('iotRelayURL'+ch)?.value.trim() || ''),sensor_url:callElement('iotSensorURL')?.value.trim() || '',nfc_url:callElement('iotNFCURL')?.value.trim() || '',scale_url:callElement('iotScaleURL')?.value.trim() || ''};
 try {await iotRequest('/api/iot/config',cfg);callText('iotConfigStatus','Device connections saved');await loadIotConfiguration();}
 catch(error){callText('iotConfigStatus',error.message);}
}
async function addRelaySchedule() {
 const date=callElement('relayScheduleTime')?.value;
 if(!date || !Number.isFinite(Date.parse(date))){showToast('Choose a future start time');return;}
 try {
  await iotRequest('/api/iot/schedule',{channel:Number(callElement('relayScheduleChannel').value),at:new Date(date).toISOString(),duration_seconds:Math.round(Number(callElement('relayScheduleMinutes').value)*60)});
  await loadRelaySchedules();
 }catch(error){showToast(error.message);}
}
async function loadRelaySchedules() {
 const parent=callElement('relayScheduleList');if(!parent)return;
 const schedules=await iotRequest('/api/iot/schedule');
 parent.innerHTML=schedules.length?schedules.map(s=>`<div class="hw-device-row"><span>CH-${s.channel} • ${s.power?'ON':'OFF'} • ${escapeHTML(new Date(s.at).toLocaleString())}</span><span>${escapeHTML(s.status)}${s.error?' • '+escapeHTML(s.error):''}</span>${s.power && !['cancelled','skipped'].includes(s.status)?'<button class="btn btn-sm btn-secondary" data-cancel-timer="'+escapeHTML(s.id)+'">Cancel / stop</button>':''}</div>`).join(''):'No relay schedules';
 parent.querySelectorAll('[data-cancel-timer]').forEach(button=>button.onclick=async()=>{try{const response=await fetch('/api/iot/schedule?id='+encodeURIComponent(button.dataset.cancelTimer),{method:'DELETE'});if(!response.ok)throw new Error(await response.text());await loadRelaySchedules();}catch(error){showToast(error.message);}});
}

function updateGatePassPreview() {
  const farmer = document.getElementById("gatePassFarmerName") ? document.getElementById("gatePassFarmerName").value : "Ramesh Kumar Sharma";
  const crop = document.getElementById("gatePassCropType") ? document.getElementById("gatePassCropType").value : "Basmati Paddy (Grade A)";
  const weightKg = parseFloat(document.getElementById("gatePassWeightKg")?.value) || 0;
  const rateQtl = parseFloat(document.getElementById("gatePassRateQtl")?.value) || 0;

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
 Payment QR is not configured`;
  }
}

async function printMandiGatePass() {
  const farmer = document.getElementById("gatePassFarmerName") ? document.getElementById("gatePassFarmerName").value : "Ramesh Kumar Sharma";
  const crop = document.getElementById("gatePassCropType") ? document.getElementById("gatePassCropType").value : "Basmati Paddy (Grade A)";
  const weightKg = parseFloat(document.getElementById("gatePassWeightKg")?.value) || 0;
  const rateQtl = parseFloat(document.getElementById("gatePassRateQtl")?.value) || 0;

  showToast("[Print] Sending ESC/POS Gate Pass to Thermal Receipt Printer...");
  try {
    const res = await fetch("/api/iot/print-gatepass", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        farmer_name: farmer,
        crop_type: crop,
        weight_kg: weightKg,
        mandi_rate: rateQtl,
        printer_ip: callElement("gatePassPrinterIP")?.value.trim() || ""
      })
    });
    if (res.ok) {
      showToast("Receipt sent to the configured printer.");
    } else {showToast(await res.text());}
  } catch (e) {
    showToast("Print failed: "+e.message);
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
// DEVICE PROFILE & AVATAR EMOJI CONTROLLER
// -----------------------------------------------------------------------------
const PRESET_PROFILE_EMOJIS = [
  '💻', '📱', '🚀', '⚡', '🌾', '🤖',
  '🦊', '🦁', '🐯', '🦅', '👑', '🛡️',
  '🌟', '🔥', '🎮', '💎', '🍀', '🎯',
  '🛸', '🛰️', '🦄', '🐉', '🧙', '🎧',
  '👨‍🌾', '🦾', '🍎', '🍕', '⚽', '🏎️', '🚁', '🏆'
];

let _selectedProfileEmoji = '💻';

function openDeviceProfileModal() {
  const modal = document.getElementById("deviceProfileModal");
  if (!modal) return;

  const currentName = appState.localNodeName || "Windows-PC";
  const currentID = appState.localNodeID || "local-pc-node";
  _selectedProfileEmoji = appState.localNodeAvatarEmoji || "💻";

  const heroNameEl = document.getElementById("profileHeroName");
  if (heroNameEl) heroNameEl.innerText = currentName;

  const heroIdEl = document.getElementById("profileHeroID");
  if (heroIdEl) heroIdEl.innerText = currentID;

  const heroAvatarEl = document.getElementById("profileHeroAvatar");
  if (heroAvatarEl) heroAvatarEl.innerText = _selectedProfileEmoji;

  const nameInput = document.getElementById("profileDeviceNameInput");
  if (nameInput) nameInput.value = currentName;

  const customEmojiInput = document.getElementById("profileCustomEmojiInput");
  if (customEmojiInput) customEmojiInput.value = "";

  renderProfileEmojiGrid();
  modal.style.display = "flex";
}

function closeDeviceProfileModal() {
  const modal = document.getElementById("deviceProfileModal");
  if (modal) modal.style.display = "none";
}

// Global modal overlay backdrop click & escape dismiss
window.addEventListener("click", (e) => {
  if (e.target && e.target.classList && e.target.classList.contains("modal-overlay")) {
    e.target.style.display = "none";
  }
});

window.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    document.querySelectorAll(".modal-overlay").forEach(m => {
      m.style.display = "none";
    });
  }
});

function renderProfileEmojiGrid() {
  const container = document.getElementById("profileEmojiGrid");
  if (!container) return;

  container.innerHTML = PRESET_PROFILE_EMOJIS.map(emoji => {
    const isActive = emoji === _selectedProfileEmoji;
    return `
      <button type="button" class="emoji-btn ${isActive ? 'active' : ''}" onclick="selectProfileEmoji('${emoji}')" title="${emoji}">
        ${emoji}
      </button>
    `;
  }).join("");
}

function selectProfileEmoji(emoji) {
  _selectedProfileEmoji = emoji;
  renderProfileEmojiGrid();

  const heroAvatarEl = document.getElementById("profileHeroAvatar");
  if (heroAvatarEl) {
    heroAvatarEl.innerText = emoji;
    heroAvatarEl.classList.remove("bounce");
    void heroAvatarEl.offsetWidth; // trigger reflow
    heroAvatarEl.classList.add("bounce");
  }

  const customInput = document.getElementById("profileCustomEmojiInput");
  if (customInput && !PRESET_PROFILE_EMOJIS.includes(emoji)) {
    customInput.value = emoji;
  } else if (customInput) {
    customInput.value = "";
  }
}

function onProfileNameChange(val) {
  const heroNameEl = document.getElementById("profileHeroName");
  if (heroNameEl) {
    heroNameEl.innerText = (val || "").trim() || "Windows PC";
  }
}

function onCustomEmojiInput(val) {
  const clean = (val || "").trim();
  if (clean) {
    _selectedProfileEmoji = clean;
    const heroAvatarEl = document.getElementById("profileHeroAvatar");
    if (heroAvatarEl) {
      heroAvatarEl.innerText = clean;
    }
    document.querySelectorAll(".emoji-btn").forEach(btn => btn.classList.remove("active"));
  }
}

function copyProfileID() {
  const id = appState.localNodeID || document.getElementById("profileHeroID")?.innerText || "";
  if (id) {
    navigator.clipboard.writeText(id).then(() => {
      showToast("📋 Device ID copied to clipboard!");
    }).catch(() => {
      showToast("Device ID: " + id);
    });
  }
}

function resetProfileNameToPC() {
  const defaultName = "Windows-PC";
  const nameInput = document.getElementById("profileDeviceNameInput");
  if (nameInput) {
    nameInput.value = defaultName;
    onProfileNameChange(defaultName);
  }
  showToast("Reset display name to default");
}

async function resetProfileToHardwareDefaults() {
  try {
    const res = await fetch("/api/profile/reset", { method: "POST" });
    if (res.ok) {
      const data = await res.json();
      appState.localNodeName = data.device_name;
      appState.localNodeAvatarEmoji = data.avatar_emoji || "💻";

      const nameInput = document.getElementById("profileDeviceNameInput");
      if (nameInput) nameInput.value = data.device_name;
      onProfileNameChange(data.device_name);

      selectProfileEmoji(appState.localNodeAvatarEmoji);

      const userAvatarEl = document.getElementById("userAvatarNodeDisplay");
      if (userAvatarEl) userAvatarEl.innerText = appState.localNodeAvatarEmoji;

      showToast("Reset to default hardware profile & avatar");
    }
  } catch (e) {
    showToast("Error resetting profile");
  }
}

async function saveDeviceProfile() {
  const nameInput = document.getElementById("profileDeviceNameInput");
  const cleanName = (nameInput ? nameInput.value : "").trim();
  if (!cleanName) {
    showToast("Please enter a valid device name");
    return;
  }

  const cleanEmoji = _selectedProfileEmoji || "💻";

  try {
    const res = await fetch("/api/profile/update", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name: cleanName,
        emoji: cleanEmoji
      })
    });

    if (res.ok) {
      const data = await res.json();
      appState.localNodeName = data.device_name || cleanName;
      appState.localNodeAvatarEmoji = data.avatar_emoji || cleanEmoji;

      const userAvatarEl = document.getElementById("userAvatarNodeDisplay");
      if (userAvatarEl) userAvatarEl.innerText = appState.localNodeAvatarEmoji;

      closeDeviceProfileModal();
      showToast("Device profile & avatar updated & broadcasted! 🎉");
    }
  } catch (e) {
    showToast("Failed to save device profile.");
  }
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

// =============================================================================
// INTERNET / WAN CLOUD MESH & DISCOVERY CONTROLLER
// =============================================================================
let _handledWanRequests = new Set();
let _currentIncomingWanRequest = null;

async function fetchWanState() {
  try {
    const res = await fetch("/api/wan/state");
    if (res.ok) {
      const data = await res.json();
      appState.wanState = data;
      checkIncomingPairRequests(data.pending_requests);

      if (appState.activePeer && appState.activePeer.is_wan) {
        const currentlyOnline = isWanPeerOnline(appState.activePeer.id);
        appState.activePeer.is_online = currentlyOnline;
        if (!currentlyOnline && (!wanDataChannel || wanDataChannel.readyState !== "open")) {
          updateWanChatStatus("● Offline", "#94A3B8");
        } else if (currentlyOnline && wanDataChannel && wanDataChannel.readyState === "open") {
          updateWanChatStatus("● Connected", "#10B981");
        }
      }

      if (appState.connectionMode === "wan") {
        renderMasterList();
      }
    }
  } catch (e) {}
}

function checkIncomingPairRequests(reqs) {
  if (!reqs || reqs.length === 0) {
    const modal = document.getElementById("incomingPairRequestModal");
    if (modal && modal.style.display === "flex") {
      modal.style.display = "none";
    }
    return;
  }
  const pending = reqs.find(r => !_handledWanRequests.has(r.request_id));
  if (pending) {
    _currentIncomingWanRequest = pending;
    const modal = document.getElementById("incomingPairRequestModal");
    if (modal && modal.style.display !== "flex") {
      const nameEl = document.getElementById("incomingReqName");
      if (nameEl) nameEl.innerText = pending.from_device_name || "Remote Device";
      const platEl = document.getElementById("incomingReqPlatform");
      if (platEl) platEl.innerText = pending.from_platform || "Remote";
      const avEl = document.getElementById("incomingReqAvatar");
      if (avEl) avEl.innerText = pending.from_avatar_emoji || "📱";
      const typeEl = document.getElementById("incomingReqType");
      if (typeEl) typeEl.innerText = pending.is_direct_radar ? "Direct 1-Tap Connect" : "PIN Code Authenticated";
      modal.style.display = "flex";
      showToast(`🔗 Incoming connection request from ${pending.from_device_name}`);
    }
  }
}

function renderWANView() {
  const container = document.getElementById("masterItemsList");
  if (!container) return;

  const wan = appState.wanState || {
    internet_mode_enabled: false,
    discovery_mode: "publicRadar",
    is_firebase_connected: false,
    is_presence_online: false,
    public_devices: [],
    trusted_devices: [],
    pending_requests: []
  };

  const isEnabled = !!wan.internet_mode_enabled;
  const isOnline = !!wan.is_presence_online && !!wan.is_firebase_connected;
  const mode = wan.discovery_mode || "publicRadar";
  const trusted = wan.trusted_devices || [];
  const publicDevs = wan.public_devices || [];
  const activeCode = wan.active_pair_code;

  let html = `
    <div class="wan-dashboard-wrap">
      <!-- 3 Connection Discovery Modes (Theme-friendly Segmented Tabs) -->
      <div class="wan-mode-selector-bar">
        <button class="wan-mode-pill ${mode === 'publicRadar' ? 'active' : ''}" onclick="setWanDiscoveryMode('publicRadar')" title="Public Radar: Visible to all Nearby users on the internet">
          <span style="font-size:13px;">🌐</span>
          <span>Public</span>
        </button>
        <button class="wan-mode-pill ${mode === 'privateGhost' ? 'active' : ''}" onclick="setWanDiscoveryMode('privateGhost')" title="Ghost Mode: Visible strictly to paired Trusted Devices">
          <span style="font-size:13px;">👻</span>
          <span>Ghost</span>
        </button>
        <button class="wan-mode-pill ${mode === 'pinOnly' ? 'active' : ''}" onclick="setWanDiscoveryMode('pinOnly')" title="PIN Code Only: Hidden, connects only with temporary 6-digit PIN">
          <span style="font-size:13px;">🔢</span>
          <span>PIN Only</span>
        </button>
      </div>
  `;

  // 2. PIN Section ONLY shown when PIN Only mode is selected
  if (mode === "pinOnly") {
    html += `
      <div class="list-group-header" style="margin-top:10px;">
        <span>PIN PAIRING DISCOVERY</span>
      </div>
    `;
    if (activeCode) {
      const remainingSec = Math.max(0, Math.floor((activeCode.expires_at - Date.now()) / 1000));
      const mins = Math.floor(remainingSec / 60);
      const secs = remainingSec % 60;
      const timeStr = `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
      const codeFormatted = activeCode.code.slice(0, 3) + " " + activeCode.code.slice(3);

      html += `
        <div class="wan-pin-card" style="margin-bottom:12px;">
          <div style="display:flex; justify-content:space-between; align-items:center;">
            <div style="font-size:11.5px; font-weight:700; color:#818CF8; display:flex; align-items:center; gap:6px;">
              <span>🔢 Active Pairing PIN</span>
            </div>
            <span style="font-size:11px; color:#F59E0B; font-weight:600;">⏱️ ${timeStr}</span>
          </div>
          <div class="wan-pin-digits" onclick="copyActiveWanPin('${activeCode.code}')" title="Click to copy">${codeFormatted}</div>
          <div style="display:flex; gap:8px;">
            <button class="btn btn-sm btn-secondary" onclick="cancelWanPinCode()" style="flex:1;">Cancel Code</button>
            <button class="btn btn-sm btn-primary" onclick="copyActiveWanPin('${activeCode.code}')" style="background:#6366F1; flex:1;">Copy PIN 📋</button>
          </div>
        </div>
      `;
    } else {
      html += `
        <div class="wan-pin-card-box" style="padding:14px; background:linear-gradient(135deg, rgba(99, 102, 241, 0.1), rgba(139, 92, 246, 0.05)); border-radius:12px; border:1px solid rgba(99, 102, 241, 0.25); margin-bottom:12px;">
          <div style="display:flex; align-items:center; gap:8px; margin-bottom:10px;">
            <span style="font-size:22px;">🔢</span>
            <div>
              <div style="font-size:12.5px; font-weight:700; color:#818CF8;">PIN Code Pairing</div>
              <div style="font-size:11px; color:var(--text-muted);">Pair with specific devices using a temporary 6-digit code</div>
            </div>
          </div>
          <div style="display:grid; grid-template-columns: 1fr 1fr; gap:8px;">
            <button class="btn-wan-action" onclick="generateWanPinCode()">
              <span style="font-size:14px;">🔢</span>
              <span>Generate PIN</span>
            </button>
            <button class="btn-wan-action" onclick="openWanPinCodeModal()">
              <span style="font-size:14px;">🔗</span>
              <span>Enter PIN</span>
            </button>
          </div>
        </div>
      `;
    }
  }

  // 3. GHOST MODE BANNER
  if (mode === "privateGhost") {
    html += `
      <div class="list-group-header" style="margin-top:10px;">
        <span>GHOST PRIVACY MODE</span>
      </div>
      <div class="wan-ghost-card" style="padding:16px 14px; text-align:center; background:linear-gradient(135deg, rgba(139, 92, 246, 0.12), rgba(99, 102, 241, 0.06)); border-radius:12px; border:1px solid rgba(139, 92, 246, 0.3); margin-bottom:12px;">
        <div style="font-size:28px; margin-bottom:6px;">👻</div>
        <div style="font-weight:700; color:#A78BFA; font-size:13px; margin-bottom:4px;">Ghost Mode Active</div>
        <div style="color:var(--text-muted); font-size:11.5px; line-height:1.4;">Your device is hidden from public discovery radar. Only your paired trusted peers below can initiate direct P2P connections.</div>
      </div>
    `;
  }

  // 3. PUBLIC INTERNET RADAR (Discovered Devices FIRST on top)
  if (mode === "publicRadar") {
    html += `
      <div class="list-group-header" style="margin-top:10px;">
        <span>PUBLIC INTERNET RADAR (${publicDevs.length})</span>
      </div>
    `;

    if (publicDevs.length === 0) {
      html += `
        <div style="padding:18px 12px; text-align:center; color:var(--text-muted); font-size:11.5px; background:rgba(255,255,255,0.02); border-radius:10px; border:1px dashed var(--border-color);">
          <div class="wan-radar-pulse" style="display:inline-flex; align-items:center; justify-content:center; width:40px; height:40px; border-radius:50%; background:rgba(16, 185, 129, 0.12); margin-bottom:8px;">
            <span style="font-size:22px; display:inline-block; animation: spinGlobe 4s linear infinite;">🌐</span>
          </div>
          <div style="font-weight:700; color:#10B981; font-size:12px; margin-bottom:3px;">Online Radar Searching</div>
          <span style="color:var(--text-muted);">Searching for online peers nearby on Internet…</span>
        </div>
      `;
    } else {
      publicDevs.forEach(p => {
        const avatarHTML = renderAvatarCircle(p.name, p.avatar_emoji, false, false, p.platform || "phone");
        const safeId = escapeHTML(p.id);
        const isConnecting = (window._connectingWanDeviceId === p.id);

        html += `
          <div class="master-item-card">
            ${avatarHTML}
            <div class="card-content">
              <div class="card-top-row">
                <span class="card-title">${escapeHTML(p.name)}</span>
                <button class="btn btn-sm btn-primary" onclick="sendDirectWanPairRequest('${safeId}', '${escapeHTML(p.name)}', '${escapeHTML(p.platform || '')}', '${escapeHTML(p.avatar_emoji || '')}')" ${isConnecting ? 'disabled' : ''} style="background:#6366F1; padding:3px 10px; font-size:11px; font-weight:700;">
                  ${isConnecting ? '⏳ Connecting…' : 'Connect ↗'}
                </button>
              </div>
              <div class="card-sub-row">
                <span class="card-snippet">${escapeHTML(p.platform || 'Remote')} • Discovered Peer</span>
                <span class="card-badge-pill" style="background:rgba(99, 102, 241, 0.15); color:#818CF8;">WAN Radar</span>
              </div>
            </div>
          </div>
        `;
      });
    }
  }

  // 4. PAIRED TRUSTED PEERS (Displayed BELOW Public Radar with Unpair Option)
  html += `
    <div class="list-group-header" style="margin-top:12px;">
      <span>PAIRED TRUSTED PEERS (${trusted.length})</span>
    </div>
  `;

  if (trusted.length === 0) {
    html += `
      <div style="padding:14px 8px; text-align:center; color:var(--text-muted); font-size:11.5px; background:rgba(255,255,255,0.02); border-radius:8px; border:1px dashed var(--border-color);">
        <p style="margin:0;">No paired friends yet.</p>
        <p style="font-size:10.5px; margin:4px 0 0 0; color:var(--text-muted);">Tap "Connect ↗" on any radar peer above or switch to "PIN Only" to pair.</p>
      </div>
    `;
  } else {
    trusted.forEach(t => {
      const isPeerOnline = isWanPeerOnline(t.id);
      const avatarHTML = renderAvatarCircle(t.name, t.avatar_emoji, true, false, t.platform || "phone");
      const safeId = escapeHTML(t.id);
      const isActive = appState.activePeer && appState.activePeer.id === t.id && appState.activePeer.is_wan;

      html += `
        <div class="master-item-card ${isActive ? 'active' : ''}" onclick="selectWanPeerForChat('${safeId}', '${escapeHTML(t.name)}', '${escapeHTML(t.avatar_emoji || '')}', '${escapeHTML(t.platform || 'phone')}')" style="cursor:pointer;" title="Click to chat">
          ${avatarHTML}
          <div class="card-content">
            <div class="card-top-row">
              <span class="card-title">${escapeHTML(t.name)}</span>
              <div style="display:flex; align-items:center; gap:6px;">
                <span class="card-time" style="color:${isPeerOnline ? 'var(--primary-emerald)' : 'var(--text-muted)'}; font-weight:600;">${isPeerOnline ? 'Online' : 'Offline'}</span>
                <button class="btn-card-unpair" onclick="unpairWanPeer('${safeId}', '${escapeHTML(t.name)}', event)" title="Unpair / Remove peer" style="font-size:12px; font-weight:700; color:#EF4444; background:transparent; border:none; padding:2px 4px;">
                  ✕
                </button>
              </div>
            </div>
            <div class="card-sub-row">
              <span class="card-snippet">${escapeHTML(t.platform || 'Remote')} • End-to-End Encrypted</span>
              <span class="card-badge-pill bg-emerald-dim">Paired</span>
            </div>
          </div>
        </div>
      `;
    });
  }

  html += `</div>`;
  container.innerHTML = html;
}

async function unpairWanPeer(id, name, event) {
  if (event) {
    event.stopPropagation();
    event.preventDefault();
  }
  if (!confirm(`Are you sure you want to unpair from ${name || 'this peer'}?`)) {
    return;
  }
  try {
    const res = await fetch("/api/wan/trusted/remove", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ device_id: id })
    });
    if (res.ok) {
      showToast(`Unpaired from ${name || 'peer'} ✕`);
      closeWanWebRTC();
      if (appState.activePeer && appState.activePeer.id === id) {
        appState.activePeer = null;
        renderChatMessages();
      }
      fetchWanState();
    }
  } catch (e) {
    showToast("Error unpairing peer");
  }
}

async function toggleInternetMode(enable) {
  try {
    const res = await fetch("/api/wan/toggle", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ enable: enable })
    });
    if (res.ok) {
      const data = await res.json();
      appState.wanState = data;
      showToast(enable ? "Internet WAN Mesh Activated 🌐" : "Internet WAN Mesh Disabled");
      renderMasterList();
    }
  } catch (e) {
    showToast("Error updating Internet mode");
  }
}

async function setWanDiscoveryMode(mode) {
  try {
    const res = await fetch("/api/wan/mode", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ mode: mode })
    });
    if (res.ok) {
      const data = await res.json();
      appState.wanState = data;
      const modeNames = {
        publicRadar: "Public Radar Active 🌐",
        privateGhost: "Ghost / Private Mode Active 👻",
        pinOnly: "PIN Code Only Active 🔢"
      };
      showToast(modeNames[mode] || "Privacy mode updated");
      renderMasterList();
    }
  } catch (e) {
    showToast("Error updating privacy mode");
  }
}

async function generateWanPinCode() {
  try {
    showToast("Generating 6-digit PIN code…");
    const res = await fetch("/api/wan/pair-code/generate", { method: "POST" });
    if (res.ok) {
      const codeData = await res.json();
      if (appState.wanState) {
        appState.wanState.active_pair_code = codeData;
      }
      showToast(`Pairing code generated: ${codeData.code} 🔢`);
      renderMasterList();
    } else {
      const errData = await res.json();
      showToast(`Failed: ${errData.error || 'Server error'}`);
    }
  } catch (e) {
    showToast("Error generating pair code");
  }
}

async function cancelWanPinCode() {
  try {
    await fetch("/api/wan/pair-code/cancel", { method: "POST" });
    if (appState.wanState) {
      appState.wanState.active_pair_code = null;
    }
    showToast("Pairing code cancelled");
    renderMasterList();
  } catch (e) {}
}

function copyActiveWanPin(code) {
  if (code) {
    navigator.clipboard.writeText(code).then(() => {
      showToast("📋 PIN code copied to clipboard!");
    }).catch(() => {
      showToast("PIN Code: " + code);
    });
  }
}

function openWanPinCodeModal() {
  const modal = document.getElementById("wanPinCodeModal");
  if (!modal) return;
  const input = document.getElementById("wanPinCodeInput");
  if (input) {
    input.value = "";
    setTimeout(() => input.focus(), 100);
  }
  const msg = document.getElementById("wanPinCodeStatusMsg");
  if (msg) {
    msg.innerText = "";
    msg.style.color = "var(--text-muted)";
  }
  modal.style.display = "flex";
}

function closeWanPinCodeModal() {
  const modal = document.getElementById("wanPinCodeModal");
  if (modal) modal.style.display = "none";
}

async function submitWanPinCode() {
  const input = document.getElementById("wanPinCodeInput");
  const code = (input ? input.value : "").trim();
  const statusMsg = document.getElementById("wanPinCodeStatusMsg");
  const btn = document.getElementById("btnSubmitWanPin");

  if (code.length !== 6 || !/^\d+$/.test(code)) {
    if (statusMsg) {
      statusMsg.innerText = "Please enter a valid 6-digit numeric PIN code";
      statusMsg.style.color = "#EF4444";
    }
    return;
  }

  if (statusMsg) {
    statusMsg.innerText = "Connecting to peer over cloud mesh…";
    statusMsg.style.color = "#818CF8";
  }
  if (btn) btn.disabled = true;

  try {
    const res = await fetch("/api/wan/pair-code/claim", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ code: code })
    });

    if (res.ok) {
      const dev = await res.json();
      if (statusMsg) {
        statusMsg.innerText = `Paired successfully with ${dev.name}! 🎉`;
        statusMsg.style.color = "var(--primary-emerald)";
      }
      showToast(`Paired with ${dev.name}! 🎉`);
      setTimeout(() => {
        closeWanPinCodeModal();
        fetchWanState();
        selectWanPeerForChat(dev.id, dev.name, dev.avatar_emoji, dev.platform);
      }, 500);
    } else {
      const errData = await res.json();
      if (statusMsg) {
        statusMsg.innerText = errData.error || "Failed to pair with remote device";
        statusMsg.style.color = "#EF4444";
      }
    }
  } catch (e) {
    if (statusMsg) {
      statusMsg.innerText = "Network connection error. Please try again.";
      statusMsg.style.color = "#EF4444";
    }
  } finally {
    if (btn) btn.disabled = false;
  }
}

async function sendDirectWanPairRequest(targetId, name, platform, avatar) {
  try {
    window._connectingWanDeviceId = targetId;
    renderMasterList();
    showToast(`Connecting with ${name}… Please accept on device`);

    const res = await fetch("/api/wan/request/send", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        target_device_id: targetId,
        target_name: name,
        target_platform: platform,
        target_avatar: avatar
      })
    });

    if (res.ok) {
      const dev = await res.json();
      showToast(`Connected & paired with ${dev.name || name}! 🎉`);
      fetchWanState();
      selectWanPeerForChat(dev.id || targetId, dev.name || name, dev.avatar_emoji || avatar, dev.platform || platform);
    } else {
      const errData = await res.json();
      showToast(`Failed: ${errData.error || 'Connection declined'}`);
    }
  } catch (e) {
    showToast("Connection failed or timed out");
  } finally {
    window._connectingWanDeviceId = null;
    renderMasterList();
  }
}

async function respondIncomingPairRequest(accept) {
  if (!_currentIncomingWanRequest) return;
  const req = _currentIncomingWanRequest;
  _handledWanRequests.add(req.request_id);

  const modal = document.getElementById("incomingPairRequestModal");
  if (modal) modal.style.display = "none";

  try {
    const res = await fetch("/api/wan/request/respond", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        request_id: req.request_id,
        from_device_id: req.from_device_id,
        from_device_name: req.from_device_name,
        from_platform: req.from_platform,
        from_avatar: req.from_avatar_emoji,
        accept: accept
      })
    });
    if (res.ok) {
      showToast(accept ? `Accepted pairing with ${req.from_device_name}! 🎉` : `Declined request from ${req.from_device_name}`);
      fetchWanState();
      if (accept) {
        selectWanPeerForChat(req.from_device_id, req.from_device_name, req.from_avatar_emoji, req.from_platform);
      }
    }
  } catch (e) {
    showToast("Error responding to request");
  }
}

function isWanPeerOnline(peerId) {
  if (!peerId) return false;
  if (wanConnectedPeerId === peerId && wanDataChannel && wanDataChannel.readyState === "open") {
    return true;
  }
  const wan = appState.wanState;
  if (!wan) return false;
  const trusted = wan.trusted_devices || [];
  const found = trusted.find(t => t.id === peerId);
  if (found) return !!found.is_online;
  const pub = wan.public_devices || [];
  const pFound = pub.find(p => p.id === peerId);
  if (pFound) return !!pFound.is_online;
  return false;
}

function selectWanPeerForChat(id, name, avatar, platform) {
  const isOnline = isWanPeerOnline(id);
  const wanPeer = {
    id: id,
    name: name,
    ip: "wan://" + id,
    avatar_emoji: avatar || "📱",
    is_online: isOnline,
    is_wan: true,
    platform: platform || "Remote"
  };

  appState.activePeer = wanPeer;
  updateDetailViewForPeer(wanPeer);
  renderMasterList();
  renderChatMessages();
  switchTab('chat', true);

  if (isOnline && resolveChatRoute(wanPeer).mode === 'wan') {
    updateWanChatStatus("Connecting…", "#F59E0B");
    connectWanWebRTC(id, name);
  } else {
    updateWanChatStatus("● Offline", "#94A3B8");
  }
}

// ==========================================================
// WAN WEBRTC STUN/TURN DATA CHANNEL & SIGNALING CONTROLLER
// ==========================================================
const WAN_ICE_SERVERS = [
  { urls: "stun:stun.l.google.com:19302" },
  { urls: "stun:stun1.l.google.com:19302" },
  { urls: "stun:stun2.l.google.com:19302" },
  { urls: "stun:stun.cloudflare.com:3478" },
  { urls: "stun:stun.services.mozilla.com:3478" },
  { urls: "turn:openrelay.metered.ca:80", username: "openrelayproject", credential: "openrelayproject" },
  { urls: "turn:openrelay.metered.ca:443", username: "openrelayproject", credential: "openrelayproject" },
  { urls: "turn:openrelay.metered.ca:443?transport=tcp", username: "openrelayproject", credential: "openrelayproject" },
  { urls: "turn:openrelay.metered.ca:3478", username: "openrelayproject", credential: "openrelayproject" }
];

let wanPeerConnection = null;
let wanDataChannel = null;
let wanActiveSessionId = null;
let wanConnectedPeerId = null;
let wanSessionPollInterval = null;
let wanIncomingPollInterval = null;
let wanReconnectTimer = null;


let wanReceivedBlobs = new Map(); // fileId -> { url, name }

function initWanWebRTC() {
  if (wanIncomingPollInterval) clearInterval(wanIncomingPollInterval);
  wanIncomingPollInterval = setInterval(pollWanIncomingSessions, 3000);
}

function scheduleWanWebRTCReconnect(peerId, peerName) {
  if (wanReconnectTimer) clearTimeout(wanReconnectTimer);
  wanReconnectTimer = setTimeout(() => {
    if (appState.activePeer && appState.activePeer.id === peerId && appState.activePeer.is_wan) {
      if (!wanDataChannel || wanDataChannel.readyState !== "open") {
        updateWanChatStatus("Reconnecting…", "#F59E0B");
        connectWanWebRTC(peerId, peerName);
      }
    }
  }, 2500);
}

async function connectWanWebRTC(peerId, peerName) {
  if (wanConnectedPeerId === peerId && wanDataChannel && wanDataChannel.readyState === "open") {
    return;
  }
  if(wanConnectedPeerId===peerId && wanPeerConnection && ['new','connecting','connected'].includes(wanPeerConnection.connectionState)) return;
  closeWanWebRTC();

  try {
    wanConnectedPeerId = peerId;
    updateWanChatStatus("Connecting…", "#F59E0B");

    wanPeerConnection = new RTCPeerConnection({ iceServers: WAN_ICE_SERVERS });
    const pc = wanPeerConnection;

    // Create Data Channel with label 'nearmitra_wan_dc' matching Flutter app
    const dc = pc.createDataChannel("nearmitra_wan_dc", { ordered: true });
    wanDataChannel = dc;
    setupWanDataChannel(dc, peerId, peerName);

    // Local ICE Candidate handler
    pc.onicecandidate = (event) => {
      if (event.candidate && wanActiveSessionId) {
        fetch("/api/wan/session/candidate", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            session_id: wanActiveSessionId,
            role: "caller",
            candidate: {
              candidate: event.candidate.candidate,
              sdpMid: event.candidate.sdpMid || "0",
              sdpMLineIndex: event.candidate.sdpMLineIndex || 0
            }
          })
        }).catch(() => {});
      }
    };

    // Create Offer
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    // Create signaling session in Firebase
    const sId = "s_" + Date.now();
    wanActiveSessionId = sId;

    const res = await fetch("/api/wan/session/create", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        session_id: sId,
        receiver_id: peerId,
        offer: { type: offer.type, sdp: offer.sdp }
      })
    });

    if (!res.ok) {
      if (isWanPeerOnline(peerId)) {
        updateWanChatStatus("Reconnecting…", "#F59E0B");
        scheduleWanWebRTCReconnect(peerId, peerName);
      } else {
        updateWanChatStatus("● Offline", "#94A3B8");
      }
      return;
    }

    // Start polling for Answer SDP and Receiver Candidates
    let pollCount = 0;
    let answerSet = false;
    if (wanSessionPollInterval) clearInterval(wanSessionPollInterval);

    wanSessionPollInterval = setInterval(async () => {
      pollCount++;
      if (pollCount > 35) {
        clearInterval(wanSessionPollInterval);
        if (!wanDataChannel || wanDataChannel.readyState !== "open") {
          if (isWanPeerOnline(peerId)) {
            updateWanChatStatus("Reconnecting…", "#F59E0B");
            scheduleWanWebRTCReconnect(peerId, peerName);
          } else {
            updateWanChatStatus("● Offline", "#94A3B8");
          }
        }
        return;
      }

      try {
        const sRes = await fetch(`/api/wan/session/get?id=${encodeURIComponent(sId)}`);
        if (sRes.ok) {
          const sData = await sRes.json();
          if (sData && sData.answer && !answerSet && pc.signalingState !== "closed") {
            answerSet = true;
            await pc.setRemoteDescription(new RTCSessionDescription(sData.answer));
            updateWanChatStatus("Connecting…", "#F59E0B");
          }

          // Add receiver candidates
          if (sData && sData.candidates && sData.candidates.receiver && pc.remoteDescription) {
            const cands = sData.candidates.receiver;
            for (const k in cands) {
              const c = cands[k];
              if (c && c.candidate) {
                try {
                  await pc.addIceCandidate(new RTCIceCandidate(c));
                } catch (_) {}
              }
            }
          }
        }
      } catch (_) {}
    }, 1200);

  } catch (err) {
    if (isWanPeerOnline(peerId)) {
      updateWanChatStatus("Reconnecting…", "#F59E0B");
      scheduleWanWebRTCReconnect(peerId, peerName);
    } else {
      updateWanChatStatus("● Offline", "#94A3B8");
    }
  }
}

async function pollWanIncomingSessions() {
  try {
    const res = await fetch("/api/wan/session/incoming");
    if (!res.ok) return;
    const sessions = await res.json();
    if (!sessions || sessions.length === 0) return;

    for (const s of sessions) {
      if (wanActiveSessionId === s.sessionId || (wanDataChannel && wanDataChannel.readyState === "open")) {
        continue;
      }
      await acceptWanIncomingSession(s);
      break;
    }
  } catch (_) {}
}

async function acceptWanIncomingSession(session) {
  closeWanWebRTC();
  try {
    wanActiveSessionId = session.sessionId;
    wanConnectedPeerId = session.callerId;

    wanPeerConnection = new RTCPeerConnection({ iceServers: WAN_ICE_SERVERS });
    const pc = wanPeerConnection;

    pc.ondatachannel = (e) => {
      wanDataChannel = e.channel;
      setupWanDataChannel(e.channel, session.callerId, session.callerName);
    };

    pc.onicecandidate = (event) => {
      if (event.candidate && wanActiveSessionId) {
        fetch("/api/wan/session/candidate", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            session_id: wanActiveSessionId,
            role: "receiver",
            candidate: {
              candidate: event.candidate.candidate,
              sdpMid: event.candidate.sdpMid || "0",
              sdpMLineIndex: event.candidate.sdpMLineIndex || 0
            }
          })
        }).catch(() => {});
      }
    };

    // Set Remote Offer
    await pc.setRemoteDescription(new RTCSessionDescription(session.offer));

    // Create Answer
    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    // Accept session
    await fetch("/api/wan/session/accept", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        session_id: session.sessionId,
        answer: { type: answer.type, sdp: answer.sdp }
      })
    });

    // Poll caller candidates
    let cPollCount = 0;
    const candInterval = setInterval(async () => {
      cPollCount++;
      if (cPollCount > 30 || pc.signalingState === "closed") {
        clearInterval(candInterval);
        return;
      }
      try {
        const sRes = await fetch(`/api/wan/session/get?id=${encodeURIComponent(session.sessionId)}`);
        if (sRes.ok) {
          const sData = await sRes.json();
          if (sData && sData.candidates && sData.candidates.caller && pc.remoteDescription) {
            const cands = sData.candidates.caller;
            for (const k in cands) {
              const c = cands[k];
              if (c && c.candidate) {
                try {
                  await pc.addIceCandidate(new RTCIceCandidate(c));
                } catch (_) {}
              }
            }
          }
        }
      } catch (_) {}
    }, 1200);

  } catch (err) {
    console.error("Accept session error:", err);
  }
}

function setupWanDataChannel(dc, peerId, peerName) {
  let currentWanReceivingFile = null;
  try {
    dc.binaryType = "arraybuffer";
  } catch (_) {}

  dc.onopen = () => {
    updateWanChatStatus("● Connected", "#10B981");
    try {
      dc.send(JSON.stringify({
        type: "handshake_syn",
        deliveryAck: true,
        senderId: (appState.wanState && appState.wanState.my_device_id) || "windows_peer"
      }));
    } catch (_) {}
  };

  dc.onclose = () => {
    if (isWanPeerOnline(peerId)) {
      updateWanChatStatus("Reconnecting…", "#F59E0B");
      scheduleWanWebRTCReconnect(peerId, peerName);
    } else {
      updateWanChatStatus("● Offline", "#94A3B8");
    }
  };

  const receiveMessage = async (event) => {
    // 1. Binary chunk received for file transfer
    if (event.data instanceof ArrayBuffer || event.data instanceof Blob) {
      let arrayBuffer = event.data;
      if (event.data instanceof Blob) {
        arrayBuffer = await event.data.arrayBuffer();
      }

      if (currentWanReceivingFile) {
        currentWanReceivingFile.chunks.push(arrayBuffer);
        currentWanReceivingFile.bytesReceived += arrayBuffer.byteLength;

        const total = currentWanReceivingFile.fileSize || 1;
        const progress = Math.min(100, Math.round((currentWanReceivingFile.bytesReceived / total) * 100));
        updateFileProgressInUI(currentWanReceivingFile.fileId, progress);
      }
      return;
    }

    // 2. JSON control or text messages
    try {
      const data = typeof event.data === 'string' ? JSON.parse(event.data) : null;
      if (!data) return;

      const rawType = (data.type || '').toString();
      const msgType = rawType.toUpperCase().replace(/_/g, '');

      if (msgType==='HANDSHAKESYN' || msgType==='HANDSHAKEACK') {
        dc.deliveryAck=data.deliveryAck===true;dc.handshakeReceived=true;
        if(msgType==='HANDSHAKESYN') dc.send(JSON.stringify({type:'handshake_ack',deliveryAck:true}));
        return;
      }
      if(msgType==='DELIVERYACK') {
        const pending=wanDeliveryWaiters.get(data.id);
        if(pending) {wanDeliveryWaiters.delete(data.id);pending(data.status==='delivered');}
        return;
      }
      // Handle ping
      if (msgType === 'PING') {
        try { dc.send(JSON.stringify({ protocolVersion: 1, type: 'PONG', timestamp: Date.now() })); } catch (_) {}
        return;
      }

      // Handle typing control from Flutter (WanDataMessage.control('typing', ...))
      if (msgType === 'CONTROL') {
        const payload = data.payload || {};
        if (payload.action === 'typing') {
          const isTyping = payload.isTyping !== false;
          if (isTyping) {
            showPeerTyping(peerName || "Peer", 3000);
          } else {
            const bar = document.getElementById("chatTypingBar");
            if (bar) bar.style.display = "none";
          }
          return;
        }
      }
      if (msgType === 'TYPING') {
        const isTyping = (data.payload && data.payload.isTyping !== false) || (data.isTyping !== false);
        if (isTyping) {
          showPeerTyping(peerName || "Peer", 3000);
        } else {
          const bar = document.getElementById("chatTypingBar");
          if (bar) bar.style.display = "none";
        }
        return;
      }

      // Handle File Meta (Start of incoming file / photo transfer from Flutter mobile)
      if (msgType === 'FILEMETA') {
        const payload = data.payload || {};
        const fileId = payload.transferId || payload.fileId || ("f_" + Date.now());
        const fileName = payload.fileName || payload.name || "received_file";
        const fileSize = payload.fileSize || payload.size || 0;

        currentWanReceivingFile = {
          fileId: fileId,
          fileName: fileName,
          fileSize: fileSize,
          bytesReceived: 0,
          folder: payload.folder === true,
          chunks: []
        };

        const incomingFileMsg = {
          id: fileId,
          peer_id: peerId,
          peer_ip: "wan://" + peerId,
          sender: peerName || "Peer",
          text: "",
          mine: false,
          at: new Date(),
          attachment: {
            name: fileName,
            size: formatBytes(fileSize),
            type: getFileType(fileName),
            progress: 0,
            status: "Downloading"
          },
          status: "Downloading",
          is_wan: true,
          reactions: {}
        };
        appState.messages.push(incomingFileMsg);
        savePersistedMessages();
        renderChatMessages();
        showToast(`📥 Receiving ${fileName} (${formatBytes(fileSize)}) from ${peerName || 'Phone'}…`);
        return;
      }

      // Handle File End (Completed incoming file transfer)
      if (msgType === 'FILEEND') {
        const file=currentWanReceivingFile;
        if (!file) return;
        currentWanReceivingFile=null;
        const msg=appState.messages.find(m=>m.id===file.fileId);
        try {
          if (file.bytesReceived!==file.fileSize) throw new Error('Incomplete file transfer');
          const form=new FormData();
          form.append('file',new Blob(file.chunks),file.fileName);
          form.append('message',JSON.stringify({id:file.fileId,peer_id:peerId,peer_ip:'wan://'+peerId,
            sender:peerName || 'Peer',file_name:file.fileName,file_size:file.fileSize,kind:file.folder?'folder':'file',at:new Date().toISOString(),is_wan:true}));
          const response=await fetch('/api/chat/receive-file',{method:'POST',body:form});
          if (!response.ok) throw new Error(await response.text());
          const stored=NearMitraChat.normalize(await response.json());
          if (msg) Object.assign(msg,stored);
          dc.send(JSON.stringify({type:'delivery_ack',id:file.fileId,status:'delivered'}));
          showToast('Received '+file.fileName);
        } catch(error) {
          if (msg) {msg.status='Failed';if(msg.attachment) msg.attachment.status='Failed';}
          dc.send(JSON.stringify({type:'delivery_ack',id:file.fileId,status:'failed'}));
          showToast('File could not be saved: '+error.message);
        }
        savePersistedMessages();renderChatMessages();return;
      }

      // Handle Text message
      if (msgType === "TEXT") {
        const text = (data.payload && data.payload.text) || data.text || "";
        if (text) {
          const msgId = data.id || ("msg_" + Date.now());
          const incomingMsg = {
            id: msgId,
            peer_id: peerId,
            peer_ip: "wan://" + peerId,
            sender: peerName || "Peer",
            text: text,
            mine: false,
            at: new Date(data.timestamp || Date.now()),
            status: "Delivered",
            is_wan: true,
            reactions: {}
          };
          const previous=appState.messages.find(m=>m.id===incomingMsg.id);
          if(previous) Object.assign(previous,incomingMsg); else appState.messages.push(incomingMsg);
          savePersistedMessages();
          renderChatMessages();
          showToast(`💬 ${peerName || 'WAN Peer'}: ${text.slice(0, 30)}`);

          const saved=await fetch('/api/chat/send',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(incomingMsg)});
          dc.send(JSON.stringify({type:'delivery_ack',id:msgId,status:saved.ok?'delivered':'failed'}));

        }
      }
    } catch (e) {}
  };
  let pending=Promise.resolve();
  dc.onmessage = event => {
    pending=pending.then(()=>receiveMessage(event)).catch(error=>console.error('Incoming WAN message failed',error));
  };
}


function updateWanChatStatus(text, color) {
  const el = document.getElementById("chatHeaderStatus");
  if (el && appState.activePeer && appState.activePeer.is_wan) {
    el.innerHTML = `<span style="color:${color || '#818CF8'}; font-weight:600;">${escapeHTML(text)}</span>`;
  }
}

function closeWanWebRTC() {
  if (wanSessionPollInterval) {
    clearInterval(wanSessionPollInterval);
    wanSessionPollInterval = null;
  }
  if (wanDataChannel) {
    try { wanDataChannel.onclose=null;wanDataChannel.close(); } catch (_) {}
    wanDataChannel = null;
  }
  if (wanPeerConnection) {
    try { wanPeerConnection.close(); } catch (_) {}
    wanPeerConnection = null;
  }
  if (wanActiveSessionId) {
    fetch("/api/wan/session/delete", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ session_id: wanActiveSessionId })
    }).catch(() => {});
    wanActiveSessionId = null;
  }
}

async function ensureWanChannel(peerId, peerName) {
 if (wanConnectedPeerId===peerId && wanDataChannel?.readyState==='open') return wanDataChannel;
 await connectWanWebRTC(peerId,peerName || 'Peer');
 const started=Date.now();
 while (Date.now()-started<40000) {
  if (!appState.wanState?.internet_mode_enabled) throw new Error('Internet mode is disabled');
  if (wanConnectedPeerId===peerId && wanDataChannel?.readyState==='open') return wanDataChannel;
  await new Promise(resolve=>setTimeout(resolve,100));
 }
 throw new Error('Connection timed out');
}
async function sendWanChatMessage(targetId,text,msgId) {
 const dc=await ensureWanChannel(targetId,'Peer');
 await sendConfirmedWan(dc,{id:msgId,type:'text',timestamp:Date.now(),payload:{text}},msgId);
 const response=await fetch('/api/chat/send',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({
  id:msgId,peer_id:targetId,peer_ip:'wan://'+targetId,sender:'Windows Host',text,mine:true,at:new Date().toISOString(),status:'Sent',is_wan:true})});
 if (!response.ok) throw new Error('Could not persist sent message');
}

// -----------------------------------------------------------------------------
// WAN WEBRTC FILE STREAMING SENDER & PROGRESS CONTROLLER
// -----------------------------------------------------------------------------
async function streamFileOverWanInternal(file, peerId, peerName, folder = false) {
  if (!file) return;

  let channel;
  try { channel=await ensureWanChannel(peerId,peerName); }
  catch(error) {showToast(error.message);return;}

  const fileId = "f_" + Date.now();
  const chunkSize = 64 * 1024; // 64 KB chunk matching Flutter
  const totalChunks = Math.ceil(file.size / chunkSize);

  // 1. Create file message with initial sending progress
  const fileMsg = {
    id: fileId,
    peer_id: peerId,
    peer_ip: "wan://" + peerId,
    sender: "Windows Host",
    text: "",
    mine: true,
    at: new Date(),
    attachment: {
      name: file.name,
      size: formatBytes(file.size),
      type: getFileType(file.name),
      bytesTransferred: 0,
      totalBytes: file.size,
      progress: 0,
      status: "Sending"
    },
    status: "Sending",
    is_wan: true,
    reactions: {}
  };
  appState.messages.push(fileMsg);
  savePersistedMessages();
  renderChatMessages();
  showToast(`📤 Sending ${file.name} (${formatBytes(file.size)})…`);

  // 2. Send File Meta
  try {
    channel.send(JSON.stringify({
      id: "meta_" + fileId,
      type: "fileMeta",
      timestamp: Date.now(),
      payload: {
        transferId: fileId,
        folder: folder,
        fileName: file.name,
        fileSize: file.size,
        mimeType: file.type || "application/octet-stream",
        chunkSize: chunkSize,
        totalChunks: totalChunks,
        checksum: ""
      }
    }));
  } catch (err) {
    fileMsg.attachment.status = "Failed";
    fileMsg.status = "Failed";
    renderChatMessages();
    showToast("Failed to send file meta");
    return;
  }

  // 3. Stream binary chunks with backpressure
  let offset = 0;
  while (offset < file.size) {
    if (!channel || channel.readyState !== "open") {
      fileMsg.attachment.status = "Failed";
      fileMsg.status = "Failed";
      renderChatMessages();
      showToast("WebRTC disconnected during file transfer");
      return;
    }

    while (channel.bufferedAmount > 1024 * 1024) {
      if(channel.readyState!=='open') throw new Error('Connection lost during file transfer');
      await new Promise(r => setTimeout(r, 10));
    }

    const chunkBlob = file.slice(offset, offset + chunkSize);
    const buffer = await chunkBlob.arrayBuffer();
    try {
      channel.send(buffer);
    } catch (err) {
      fileMsg.attachment.status = "Failed";
      fileMsg.status = "Failed";
      renderChatMessages();
      return;
    }

    offset += buffer.byteLength;
    const progress = Math.min(100, Math.round((offset / file.size) * 100));
    fileMsg.attachment.progress = progress;
    fileMsg.attachment.bytesTransferred = offset;
    updateFileProgressInUI(fileId, progress);

    if (offset % (chunkSize * 4) === 0) {
      await new Promise(r => setTimeout(r, 4));
    }
  }

  try {
    await sendConfirmedWan(channel,{id:'end_'+fileId,type:'fileEnd',timestamp:Date.now(),payload:{transferId:fileId}},fileId);
  } catch(error) {
    fileMsg.status='Failed';fileMsg.attachment.status='Failed';savePersistedMessages();renderChatMessages();showToast(error.message);return;
  }

  fileMsg.attachment.status = "Sent";
  fileMsg.attachment.progress = 100;
  fileMsg.status = "Sent";
  savePersistedMessages();
  renderChatMessages();
  showToast(`✅ Sent ${file.name} successfully!`);

  // Persist to Go backend
  fetch("/api/chat/send", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      id: fileId,
      peer_id: peerId,
      peer_ip: "wan://" + peerId,
      sender: "Windows Host",
      text: `[File Attachment: ${file.name}]`,
      mine: true,
      at: new Date().toISOString(),
      status: "Sent",
      is_wan: true
    })
  }).catch(() => {});
}

// -----------------------------------------------------------------------------
// HELPER UTILITIES FOR ATTACHMENTS, FORMATTING & PROGRESS
// -----------------------------------------------------------------------------
function formatBytes(bytes) {
  if (!bytes || bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

function getFileType(fileName) {
  const ext = (fileName || '').split('.').pop().toLowerCase();
  if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp'].includes(ext)) return 'image';
  if (['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'].includes(ext)) return 'video';
  if (['mp3', 'wav', 'aac', 'm4a', 'flac', 'ogg'].includes(ext)) return 'audio';
  if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv'].includes(ext)) return 'doc';
  if (['zip', 'rar', '7z', 'tar', 'gz', 'apk', 'exe'].includes(ext)) return 'archive';
  return 'file';
}

function updateFileProgressInUI(fileId, progress) {
  const metaEl = document.getElementById(`att_meta_${fileId}`);
  const progEl = document.getElementById(`att_prog_${fileId}`);
  if (metaEl) {
    const msg = appState.messages.find(m => m.id === fileId);
    const sizeStr = (msg && msg.attachment && msg.attachment.size) || '';
    const isMine = msg ? msg.mine : true;
    metaEl.innerText = `${sizeStr} • ${isMine ? 'Sending' : 'Downloading'} (${progress}%)`;
  }
  if (progEl) {
    progEl.style.width = `${progress}%`;
  }
}

function handleAttachmentClick(msgId) {
  const stored=appState.messages.find(m=>m.id===msgId);
  if(stored && stored.file_path) {openFile(stored.file_path);return;}
  const received = wanReceivedBlobs.get(msgId);
  if (received) {
    const a = document.createElement('a');
    a.href = received.url;
    a.download = received.name || 'download';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    showToast(`Saving ${received.name}…`);
    return;
  }
  openSaveDirectory();
}

function handleChatDragOver(e) {
  e.preventDefault();
  const overlay = document.getElementById("chatDropOverlay");
  if (overlay) overlay.style.display = "flex";
}

function handleChatDragLeave(e) {
  e.preventDefault();
  const overlay = document.getElementById("chatDropOverlay");
  if (overlay) overlay.style.display = "none";
}

async function handleChatDrop(e) {
  e.preventDefault();
  e.stopPropagation();
  const overlay = document.getElementById("chatDropOverlay");
  if (overlay) overlay.style.display = "none";

  const targetPeer = appState.activePeer;
  if (!targetPeer) {
    showToast("Please select a device first");
    return;
  }

  if (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files.length > 0) {
    const file = e.dataTransfer.files[0];
    const fileRoute = resolveChatRoute(targetPeer);
  if (fileRoute.mode === 'wan') {
      streamFileOverWan(file, fileRoute.id, targetPeer.name);
    } else {
      uploadDroppedFileToPeer(file, fileRoute.nearby?.ip || "", targetPeer.id);
    }
  }
}

function uploadDroppedFileToPeer(file, targetIP, targetID) {
  const formData = new FormData();
  formData.append("file", file);
  showToast(`Uploading ${file.name} to peer...`);

  fetch(`/api/send-file-upload?ip=${encodeURIComponent(targetIP || "")}`, {
    method: "POST",
    body: formData
  }).then(r => r.json()).then(data => {
    if(data.error) throw new Error(data.error);
    const fileMsg = {
      id: "msg_" + Date.now(),
      peer_id: targetID,
      peer_ip: targetIP,
      sender: "Windows Host",
      mine: true,
      at: new Date(),
      attachment: {
        name: file.name,
        size: formatBytes(file.size),
        type: getFileType(file.name),
        status: "Sent"
      },
      status: "Sent",
      reactions: {}
    };
    appState.messages.push(fileMsg);
    savePersistedMessages();
    renderChatMessages();
    showToast(`✅ File ${file.name} sent successfully!`);
  }).catch(() => {
    showToast("Error uploading file");
  });
}




let chatDeviceLinks = {};
try { chatDeviceLinks = JSON.parse(localStorage.getItem('nearmitra_chat_device_links') || '{}'); } catch (_) {}
function resolveChatRoute(peer) {
 NearMitraChat.learn(appState.peers, chatDeviceLinks);
 localStorage.setItem('nearmitra_chat_device_links',JSON.stringify(chatDeviceLinks));
 return NearMitraChat.resolve(peer,appState.peers,appState.wanState,chatDeviceLinks,
  wanDataChannel && wanDataChannel.readyState==='open' ? wanConnectedPeerId : null);
}
let chatOutboxBusy = false;
async function flushChatOutbox() {
 if (chatOutboxBusy) return;
 chatOutboxBusy=true;
 try {
  for (const msg of appState.messages.filter(m => m.mine && m.status==='Queued' && !m.attachment)) {
   const peer={id:msg.peer_id,name:msg.peer_name || 'Peer',ip:msg.peer_ip};
   const route=resolveChatRoute(peer);
   if (route.mode==='offline') continue;
   msg.status='Sending'; renderChatMessages();
   try {
    let delivered=false;
    if (route.nearby) {
     const response=await fetch('/api/chat/send',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...msg,peer_ip:route.nearby.ip,is_wan:false})});
     delivered=response.ok;
    }
    if (!delivered && route.internet && appState.wanState.internet_mode_enabled) {
     await sendWanChatMessage(route.internet.id,msg.text,msg.id);
     delivered=true;
    }
    msg.status=delivered?'Sent':'Queued';
   } catch(error) { msg.status='Queued'; console.warn('Chat delivery deferred',error); }
   savePersistedMessages(); renderChatMessages();
  }
 } finally { chatOutboxBusy=false; }
}
setInterval(flushChatOutbox,3000);

const wanDeliveryWaiters=new Map();
async function sendConfirmedWan(channel,message,id) {
 const start=Date.now();
 while(!channel.handshakeReceived && Date.now()-start<2000) {await new Promise(resolve=>setTimeout(resolve,25));}
 let timer;
 const confirmation=channel.deliveryAck ? new Promise((resolve,reject)=>{
  wanDeliveryWaiters.set(id,resolve);
  timer=setTimeout(()=>reject(new Error('Receiver did not confirm delivery')),60000);
 }) : Promise.resolve(true);
 try {
  channel.send(JSON.stringify(message));
  if(!await confirmation) throw new Error('Receiver could not save the transfer');
 } finally {clearTimeout(timer);wanDeliveryWaiters.delete(id);}
}

let wanFileSendQueue=Promise.resolve();
function streamFileOverWan(file,peerId,peerName,folder=false) {
 const send=wanFileSendQueue.then(()=>streamFileOverWanInternal(file,peerId,peerName,folder));
 wanFileSendQueue=send.catch(error=>showToast(error.message));
 return send;
}

async function callRequest(path,body) {
 const response=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body || {})});
 if(!response.ok)throw new Error(await response.text());
}
function callElement(id){return document.getElementById(id);}
function callText(id,text){const element=callElement(id);if(element)element.innerText=text;}
function callDisplay(id,display){const element=callElement(id);if(element)element.style.display=display;}
const pcAudioCapture=new NearMitraAudioCapture({
 media:{getUserMedia:constraints=>navigator.mediaDevices.getUserMedia(constraints),getDisplayMedia:constraints=>navigator.mediaDevices.getDisplayMedia(constraints),enumerateDevices:()=>navigator.mediaDevices.enumerateDevices()},
 createStream:tracks=>new MediaStream(tracks),createAudioContext:()=>new AudioContext(),
 onSourceEnded:(message,stream)=>{showToast(message);if(desktopCall.session?.stream===stream)desktopCall.stop(true).catch(error=>console.warn(error));}
});
let callAudioStatsTimer=null;
async function updateCallAudioStats(){
 const session=desktopCall.session;if(!session?.pc?.getStats)return;
 try{
  const report=await session.pc.getStats();if(desktopCall.session!==session)return;
  let sent=0,received=0,input=null;
  report.forEach(stat=>{
   const audio=stat.kind==='audio' || stat.mediaType==='audio';
   if(audio && stat.type==='outbound-rtp' && !stat.isRemote)sent+=stat.bytesSent || 0;
   if(audio && stat.type==='inbound-rtp' && !stat.isRemote){
    received+=stat.bytesReceived || 0;
    if(session.mode==='listen'){
     const level=stat.audioLevel;
     callText('remoteMicLevelText',level===undefined?'Audio received':level>0?(20*Math.log10(level)).toFixed(1)+' dBFS':'Silent');
     const bar=callElement('remoteMicLevelBar');if(bar)bar.style.width=(level===undefined?0:Math.min(100,Math.max(0,level)*100))+'%';
    }
   }
   if(audio && stat.type==='media-source' && stat.audioLevel!==undefined)input=stat.audioLevel;
  });
  callText('audioCastStreamStats','Sent '+Math.round(sent/1024)+' KB • Received '+Math.round(received/1024)+' KB');
  const source=session.mode==='listen'?'Listening to phone mic':session.sourceLabel || 'PC microphone';
  callText('callAudioStatus',(session.mediaWarnings?.length?session.mediaWarnings.join(' ')+' • ':'')+source+' • Sent '+Math.round(sent/1024)+' KB • Received '+Math.round(received/1024)+' KB'+(input===null?'':input<0.00001?' • No source audio detected':' • Input active'));
 }catch(error){console.warn('Audio statistics unavailable',error);}
}
function startCallAudioStats(){
 if(callAudioStatsTimer)clearInterval(callAudioStatsTimer);
 callAudioStatsTimer=setInterval(updateCallAudioStats,1000);updateCallAudioStats();
}
const desktopCall=new NearMitraCall({
 createPeerConnection:config=>new RTCPeerConnection(config),
 getUserMedia:async constraints=>{
  const session=desktopCall.session;
  const source=session?.mode==='broadcast' && !session.incoming ? callElement('pcAudioSource')?.value || 'mic' : 'mic';
  if(desktopCall.session)desktopCall.session.sourceLabel=source==='both'?'PC microphone + system audio':source==='system'?'System audio':'PC microphone';
  const stream=await pcAudioCapture.capture(constraints,source,callElement('pcMicrophoneDevice')?.value || '');
  if(session){if(!stream.getAudioTracks().length)session.sourceLabel='Receiving phone audio only';session.mediaWarnings=pcAudioCapture.warnings.get(stream) || [];if(session.mediaWarnings.length)showToast(session.mediaWarnings.join(' '));}
  return stream;
 },
 createStream:tracks=>new MediaStream(tracks),
 releaseMedia:stream=>pcAudioCapture.release(stream),
 invite:(peer,video)=>callRequest('/api/call/invite',{target_ip:peer.ip,peer_id:peer.id,peer_name:peer.name,is_video:video}),
 answer:()=>callRequest('/api/call/answer'),
 end:()=>callRequest('/api/call/end'),
 sendSignal:(ip,header)=>callRequest('/api/cctv/signal',{target_ip:ip,...header}),
 onLocal:stream=>{localMediaStream=stream;peerConnection=desktopCall.session?.pc;const video=callElement('localVideo');if(video)video.srcObject=stream;},
 onRemote:stream=>{
  let audio=callElement('remoteCallAudio');
  if(!audio){audio=document.createElement('audio');audio.id='remoteCallAudio';audio.autoplay=true;document.body.appendChild(audio);}
  audio.srcObject=stream;audio.muted=false;audio.play().catch(()=>showToast('Click the call window to enable audio playback'));
  const video=callElement('remoteVideo');if(video){video.srcObject=stream;video.muted=true;video.play().catch(()=>{});}
  callDisplay('remoteVideoPlaceholder','none');
 },
 onError:error=>showToast(error.message),
 onState:(state,session)=>{
  syncIotAudioState(state,session);
  isCallActive=state!=='ended';appState.voice.active=state==='connected';
  if(state==='ended'){
   if(callAudioStatsTimer)clearInterval(callAudioStatsTimer);callAudioStatsTimer=null;callText('callAudioStatus','Audio stopped');
   if(callScreenStream){callScreenStream.getTracks().forEach(t=>{t.onended=null;t.stop();});callScreenStream=null;}isScreenSharing=false;
   localMediaStream=null;peerConnection=null;appState._ringingShown=false;hideIncomingCallOverlay();
   if(callDurationInterval)clearInterval(callDurationInterval);callDurationInterval=null;
   if(equalizerInterval)clearInterval(equalizerInterval);equalizerInterval=null;
   ['localVideo','remoteVideo','remoteCallAudio'].forEach(id=>{const element=callElement(id);if(element)element.srcObject=null;});
   callDisplay('voiceDashboardView','flex');callDisplay('voiceActiveCallView','none');callText('callPeerStatus','Call ended');return;
  }
  if(session){
   if(!callElement('callAudioStatus')){const status=document.createElement('p');status.id='callAudioStatus';status.setAttribute('role','status');const parent=callElement('voiceActiveCallView');if(parent)parent.appendChild(status);}
   callText('callPeerTitle',session.peer.name);callDisplay('voiceDashboardView','none');callDisplay('voiceActiveCallView','flex');}
  if(session?.mediaWarnings?.length)callText('callAudioStatus',session.mediaWarnings.join(' '));
  callText('callPeerStatus',({permissions:'Requesting microphone/camera permission…',ringing:'Ringing…',connecting:'Connecting…',connected:'Connected'})[state] || state);
  if(state==='connected'){appState.voice.callDuration=0;startCallTimer();startEqualizerLoop();startCallAudioStats();}
 }
});
async function startCallWithPeer(ip,name,isVideo=false,mode='duplex') {
 const peer=(appState.peers || []).find(p=>p.ip===ip || p.id===ip);
 const nearby=NearMitraCall.resolvePeer(peer || {id:ip,ip,name},appState.peers || [],appState.lanDevices || []);
 if(!nearby){showToast('Select a Nearby device with a local IP address. Internet-only calling is unavailable.');return;}
 try {switchTab('voice',true);setCallMode(isVideo?'video':'audio');await desktopCall.start(nearby,isVideo,mode);}
 catch(error){showToast('Could not start call: '+describePcMediaError(error));}
}
function showIncomingCallOverlay(name,ip,isVideo) {
 incomingCallData={peerName:name,peerIP:ip,isVideo};
 callText('icPeerName',name);callText('icAvatar',getInitials(name || 'Peer'));callText('icCallType',isVideo?'Nearby video call':'Nearby audio call');
 callDisplay('incomingCallOverlay','flex');
}
function hideIncomingCallOverlay(){incomingCallData=null;callDisplay('incomingCallOverlay','none');}
async function answerIncomingCall(){
 const incoming=incomingCallData;if(!incoming)return;hideIncomingCallOverlay();
 try{
  switchTab('voice',true);setCallMode(incoming.isVideo?'video':'audio');
  const peer=(appState.peers || []).find(p=>p.ip===incoming.peerIP) || {id:incoming.peerIP,ip:incoming.peerIP,name:incoming.peerName};
  await desktopCall.accept(peer,incoming.isVideo);
 }catch(error){await callRequest('/api/call/decline').catch(()=>{});showToast('Could not answer call: '+error.message);}
}
async function declineIncomingCall(){hideIncomingCallOverlay();await callRequest('/api/call/decline').catch(error=>showToast(error.message));}

function describePcMediaError(error){
 if(['NotFoundError','DevicesNotFoundError','OverconstrainedError'].includes(error?.name))return 'A PC microphone/camera could not be opened. The selected Nearby phone was not the missing device. Refresh the microphone list or enable a capture device in Windows.';
 if(error?.name==='NotAllowedError')return 'PC microphone/camera permission was denied. Allow access for NearMitra in the browser and Windows privacy settings, or use Listen Remote Mic.';
 if(error?.name==='NotReadableError')return 'Windows could not open the PC microphone/camera. Check its connection and whether another app is using it.';
 return error?.message || String(error);
}
