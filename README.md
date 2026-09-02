# NearMitra — Fast, Offline P2P & LAN Communication App

**NearMitra** is a high-speed, private, local network and direct peer-to-peer (P2P) messaging, file-sharing, live streaming, and offline AI interaction application. It operates **100% offline without needing internet connections, cellular data, or cloud servers**.

---

## Cross-Platform Ecosystem (Android Mobile & Windows PC)

NearMitra bridges mobile devices and desktop computers seamlessly across your local network or direct Wi-Fi Direct links:

- **Android App**: Native Flutter + Kotlin integration with 60 FPS P2P Radar, live camera QR pairing, scoped storage file saving, real-time audio/video calling, live CCTV & audio streaming, and smart active notifications.
- **Windows PC App**: Desktop application with direct P2P link support, real-time activity log tracker, local Ollama AI hosting, and system tray integration.

---

## App Screenshots & Visual Showcase

### Section 1: Android Mobile App Interface

| 60 FPS P2P Radar View | Nearby LAN Devices List | Chat & File Transfer |
| :---: | :---: | :---: |
| ![Android P2P Radar](screenshot/androidapp/android_p2p_radar.jpeg) | ![Android LAN Peers](screenshot/androidapp/android_lan_peers.jpeg) | ![Android Chat File](screenshot/androidapp/android_chat_file.jpeg) |

| Nearby AI Client Chat | Streaming Hub | App Settings |
| :---: | :---: | :---: |
| ![Android Nearby AI](screenshot/androidapp/android_nearby_ai.jpeg) | ![Android Streaming](screenshot/androidapp/android_streaming.jpeg) | ![Android Settings](screenshot/androidapp/android_settings.jpeg) |

---

### Section 2: Windows PC Desktop Application Interface

| Windows Interface & Device List | Windows Chat & High-Speed File Transfer (Dark Theme) |
| :---: | :---: |
| ![Windows App Overview](screenshot/windowsapp/win_app_overview.png) | ![Windows Chat Transfer](screenshot/windowsapp/win_p2p_chat_transfer.png) |

| Windows Local Ollama Nearby AI Host | Windows AI Host Security & Model Settings |
| :---: | :---: |
| ![Windows Nearby AI Host](screenshot/windowsapp/win_nearby_ai_host.png) | ![Windows AI Settings](screenshot/windowsapp/win_ai_settings.png) |

---

## Who Can Use NearMitra?

**NearMitra is built for EVERYONE!** Designed for universal offline communication across all environments:

- **Farmers & Agricultural Workers**: Share field photos, crop reports, weather logs, and farming tips in remote fields without cellular data.
- **Students & Teachers**: Share notes, PDFs, assignment folders, and project files instantly inside classrooms or campuses without internet.
- **Office Teams & Workers**: Transfer large files, documents, and chat securely within offices or field sites without exposing sensitive data to external servers.
- **Travelers, Campers & Hikers**: Stay connected in off-grid zones, mountains, or rural areas where mobile signals are unavailable.
- **Emergency Responders & Disaster Relief**: Communicate and coordinate in areas affected by network outages or infrastructure failures.
- **Family & Friends**: Send photo albums, videos, movies, and messages at home at maximum hardware Wi-Fi speeds.
- **Security & Surveillance**: Monitor live CCTV video feeds and audio streams across devices on your local network with zero internet exposure.

---

## Key Features & Highlights

### 1. Dual Connection Modes
- **Direct P2P Mode (Wi-Fi Direct v7.1 Radar)**: Connects devices **directly device-to-device via Wi-Fi Direct without any Wi-Fi router or internet connection**!
- **Nearby Mode (LAN)**: Automatically discovers devices connected to the same Wi-Fi router or mobile hotspot via UDP multicast/broadcast (Port `43888`) and subnet scanning.
- **Smart Device Type Detection**: Automatically identifies connected nodes as Android phones, Windows PCs, or generic devices with appropriate icons.

### 2. 60 FPS Continuous P2P Radar & Smart Setup
- **Continuous 60 FPS Sweep**: Smooth 60 FPS rotating radar sweep arc, expanding pulse waves, and fading trailing trail running continuously without UI reload flickers.
- **Auto Wi-Fi & Location GPS Detection**: Detects if Wi-Fi or Location (GPS) is turned OFF on Android with **1-Tap Action Banners** to enable Wi-Fi or GPS directly.
- **Unified Single Header Box**: Replaces multiple warning boxes with a single clean dynamic top card that automatically disappears as soon as GPS/Wi-Fi is enabled.

### 3. Live Camera QR Scanner & Manual Pairing
- **Live Camera QR Reader**: Built-in QR scanner screen with flash toggle, camera flip, and animated green scanning laser line.
- **Smart P2P QR Code Generator**: Generates `farmitra_p2p:[deviceName]:[macAddress]:[ip]` QR code containing the device's native Wi-Fi Direct MAC Address.
- **1-Tap Pairing**: Scanning QR code automatically triggers native Android `WifiP2pManager` pairing dialog on the target device.
- **Direct IP & MAC Input**: Fallback manual entry tab to connect using IP (`192.168.49.1`) or MAC Address (`FA:4B:9C:12:34:56`).

### 4. Instant Offline Messaging & High-Speed File Transfer
- **High-Speed Transfer**: Send text messages, documents, photos, videos, APKs, zip files, and folders at maximum Wi-Fi speeds (up to 50+ MB/s).
- **Real-Time Progress & Speed**: Dynamic progress bar with live transfer rate (MB/s) and estimated time remaining (ETA).
- **1-Tap File Opener**: Native integration with `OpenFilex` to instantly open received files from chat bubbles or file history.
- **Recent Transfers Tab**: Dedicated `Recent` tab (`⇄` icon) to view full bidirectional file and data exchange history.

### 5. Real-Time Audio & Video Calling (WebRTC P2P)
- **1-Tap Audio & Video Calls**: Initiate crystal-clear audio or HD video calls directly over the local network with zero internet dependency.
- **Full-Screen Call UI**: Beautiful active call screen with local/remote video, mute, camera flip, and speaker toggle controls.
- **Background & Lock Screen Calls**: Incoming calls surface as full-screen native CallKit notifications even when the app is backgrounded or the screen is locked.
- **Activity Log**: Every call (missed, answered, rejected) is timestamped and logged per peer.

### 6. Live Streaming Hub (CCTV & Audio)
- **CCTV Live Video Streaming**: Stream live camera feed from one device and view it on any other connected peer on the local network.
- **Live Audio Streaming**: Broadcast live audio (microphone) to all peers simultaneously with configurable quality.
- **Security Hub**: Fine-grained permission control (Camera, Audio, Screen access) with per-device trusted device management — all persisted locally.
- **In-Chat Quick Access**: Launch CCTV or Audio Streaming instantly from the 3-dot menu inside any chat conversation.

### 7. Nearby AI Assistant (Google Gemini & ChatGPT Integration)
- **Toggle Normal / Nearby AI Mode**: Switch between messaging peers and asking questions to AI directly from the chat tab bar.
- **Google Gemini & OpenAI Integration**: Real-time streaming responses with custom model names and persona configuration.
- **AI Permission Control**: Per-peer AI access grants and revocations stored persistently in local storage.
- **Markdown & Code Highlighting**: Rich text formatting (bold, italics, lists, code blocks) with **1-Tap Copy** and **Share** options.

### 8. Smart Notification Suppression & Lazy Pagination
- **Context-Aware Notifications**: In-app active chat view suppresses redundant notification popups and unread badges while chatting live. Notifications pop up only when backgrounded or viewing other tabs.
- **Lazy Message Pagination**: Loads the latest 20 chat messages initially for instant performance. Automatically fetches 20 older messages when scrolling up to the top.
- **Per-Device 3-Dot Menu**: Quick access to Activity Log, Received Files, CCTV Streaming, and Live Audio Streaming per device.

### 9. Custom Storage & Android Scoped Storage Safety
- **Flexible Path Selection**: Pick any custom save folder for incoming files.
- **Instant Write Permission Test**: Tests write access upon folder selection and provides fail-safe fallback to Public Downloads (`/storage/emulated/0/Download/NearMitra`).

### 10. Offline Message & File Auto-Queue (Store & Forward Auto-Sync)
- **Persistent Outbox Queue**: When sending messages or sharing files with an offline or unreachable peer, NearMitra automatically stores them in a persistent local Outbox queue (`SharedPreferences`).
- **Visual Status Badges**: Queued messages display an amber **🕒 Queued** badge in the chat bubble.
- **Auto-Sync on Reconnect**: As soon as the target peer comes back online (detected via UDP beacon, Wi-Fi Direct link, or TCP hello), the background queue manager automatically delivers pending items in chronological order and updates their status to **Delivered (Double Blue Checkmarks)**.
- **1-Tap Cancellation**: Users can tap the inline **✕ Cancel** button on any queued message/file card to delete it from the outbox before it is sent.

### 11. Android Quick Settings Tile (`NearMitra Share`)
- **Native Notification Shade Tile**: Integrated `TileService` allows 1-tap quick access directly from the Android Quick Settings shade (alongside Wi-Fi, Bluetooth, and Torch).
- **Monochrome Dynamic Vector Icon**: Crisp vector icon (`ic_qs_nearmitra.xml`) styled to match Android's Dark and Light system themes.
- **Live Status Subtitle**: Displays `P2P Active` when the background service is running or `Ready to Share` when idle.

### 12. Native Android Background Foreground Service
- **Persistent Socket Listener**: Native `FarmitraForegroundService` with `WAKE_LOCK`, `WifiLock`, and `MulticastLock` keeps TCP/UDP socket listeners alive even when the app is minimized or closed.
- **Settings Switch (Default: ON)**: \"Run in Background\" toggle in App Settings. When enabled, incoming messages, calls, and file transfers arrive seamlessly with heads-up notifications even when the app is in the background or killed state.

### 13. Fully Persistent Settings (Local Storage)
All user preferences and security settings are saved locally and restored on every app launch:

| Setting | Default | Storage Key |
| :--- | :---: | :--- |
| App Theme Mode (Light / Dark / System) | System | `app_theme_mode` |
| Local Notifications | **ON** | `local_notifications_enabled` |
| Run in Background | **ON** | `background_service_enabled` |
| AI Permission (per peer) | Varies | `ai_allowed_peers` / `ai_revoked_peers` |
| Streaming Camera Permission | OFF | `streaming_camera_enabled` |
| Streaming Audio Permission | OFF | `streaming_audio_enabled` |
| Streaming Security Mode | OFF | `streaming_security_enabled` |
| Trusted Streaming Devices | — | `streaming_trusted_devices` |

---

## 🔮 Upcoming Features & Roadmap

NearMitra is evolving into the ultimate off-grid decentralized communication and intelligence platform:

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                           NearMitra Future Roadmap                            │
├───────────────────────┬───────────────────────────────┬───────────────────────┤
│    Edge AI & Vision   │     Acoustic Protection       │ Universal Ecosystem   │
│  • On-Device SLMs     │  • Dog Bark & Theft Audio     │  • iOS, macOS, Linux  │
│  • Real-Time CV Alert │  • Anomaly Sound Detection    │  • Multi-Hop Mesh P2P │
│  • Edge Object Filter │  • Acoustic Alarm Trigger     │  • Shared Clipboard   │
└───────────────────────┴───────────────────────────────┴───────────────────────┘
```

### 🧠 1. On-Device Offline AI Models (Local SLM / NPU Execution)
- **Zero-Cloud Generative AI**: Run quantized Small Language Models (e.g., Google Gemma 2B, Llama 3.2 1B/3B, Microsoft Phi-3) directly on-device using mobile NPU/GPU hardware acceleration (MediaPipe / GGML / TFLite).
- **100% Offline Intelligence**: Query AI assistants for document summarization, code generation, medical first-aid, farming diagnosis, and translations in remote areas with **0% internet dependency**.

### 🌐 2. Universal Cross-Platform Ecosystem (iOS, macOS & Linux)
- **Unified P2P Protocol**: Expanding native Wi-Fi Direct, Multipeer Connectivity, and LAN discovery across **iOS, macOS, and Linux** devices.
- **Decentralized Multi-Hop Mesh Network**: Automatic packet relaying across intermediate neighbor nodes, enabling long-range multi-hop message forwarding through dense crowds, campsites, and university campuses without central routers.
- **Universal Cross-Device Clipboard**: Seamless, encrypted copy-paste synchronization across all active devices on your local network.

### 👁️ 3. Condition-Based AI Vision Filtering in Live Camera Streaming
- **Edge AI Video Analytics**: Real-time on-device computer vision processing applied directly over CCTV video streams:
  - **Intruder & Human Motion Detection**: Automatically triggers silent alerts to connected peers when human presence is detected in restricted zones.
  - **Property & Crop Protection**: Recognizes livestock, stray animals, or vehicle entry with bounding-box metadata sent over P2P.
  - **Fire, Smoke & Hazard Detection**: Edge alert triggers during live field or warehouse surveillance.
- **Smart Bandwidth Optimization**: Streams high-bitrate video only when AI condition triggers are met, conserving device battery and local network bandwidth.

### 🎙️ 4. AI-Powered Audio Protection & Voice Anomaly Streaming
- **Acoustic Threat & Theft Recognition**: Real-time sound classification running locally on audio streams:
  - **Dog Barking & Distress Detection**: Identifies aggressive dog barking, cattle distress sounds, or unusual nocturnal livestock noise to prevent farm/property theft.
  - **Burglary & Break-In Acoustic Alerts**: Detects glass shattering, door tampering, and distress calls.
  - **Automated P2P Siren / Deterrence Broadcast**: Triggers automated audible alarms or flashlights on remote CCTV nodes upon anomaly detection.

---

## How to Use

### Mode A: Direct P2P (No Router / No Internet Required)
1. Open **NearMitra** on both Android devices (or Android and Windows PC).
2. Select the **Direct P2P** tab.
3. Ensure **Wi-Fi** and **Location (GPS)** are turned ON (use the 1-tap banner if prompted).
4. Nearby devices will appear on the **60 FPS Radar**.
5. Tap any device node on the radar **OR** tap **"Scan QR / Manual Pairing"** to pair using the camera.
6. Accept the native Wi-Fi Direct connection prompt on the receiving device.
7. Start chatting, transferring files, calling, streaming, or querying Nearby AI!

### Mode B: Nearby Mode (Local Wi-Fi Router / Hotspot)
1. Connect both devices to the same Wi-Fi router or mobile hotspot.
2. Select the **Nearby** tab on Android.
3. Active devices on the network will appear automatically.
4. Tap any peer to start chatting, transferring files, or initiating a live call/stream.

---

## Technical Architecture & Protocol Specifications

NearMitra uses a transparent, low-overhead JSON-over-Socket wire protocol compatible across Android and Windows desktop applications:

| Component | Protocol / Port | Purpose |
| :--- | :--- | :--- |
| **UDP Discovery** | `UDP 239.255.43.88:43888` / Broadcast | Device presence announcement & IP discovery |
| **TCP Socket Transport** | `TCP 0.0.0.0:43889` | Chat messages, file headers, typing indicators, AI prompts |
| **WebRTC Signaling** | TCP overlay via Socket | Audio/video call offer, answer, ICE candidates |
| **Wi-Fi Direct P2P** | Android `WifiP2pManager` | Peer-to-peer Wi-Fi Direct link formation (`192.168.49.x`) |

### Wire Packet Headers (JSON + `\n`):
- **Hello Handshake**: `{"type":"hello","sender":"Pixel 9","sender_id":"uuid-id"}`
- **Chat Message**: `{"type":"chat","sender":"Pixel 9","sender_id":"uuid-id","message":"Hello!"}`
- **Typing Indicator**: `{"type":"typing","sender":"Pixel 9","sender_id":"uuid-id","is_typing":true}`
- **File Transfer**: `{"type":"file","sender":"Pixel 9","sender_id":"uuid-id","name":"doc.pdf","size":5242880}` *(File bytes follow immediately)*
- **Nearby AI Prompt**: `{"type":"ai_chat","sender":"Pixel 9","sender_id":"uuid-id","prompt":"Explain photosynthesis","ai":true}`
- **Call Offer**: `{"type":"call_offer","sender":"Pixel 9","sender_id":"uuid-id","is_video":true}`

---

## Building Release APK

To build the release APK for Android:

```bash
flutter pub get
flutter build apk --split-per-abi
```

**Output Split APKs**:
```text
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
```

To install directly to a connected Android phone via USB:
```bash
flutter install
```

---

## Privacy & Security

- **100% Offline & Private**: Zero data leaves your local network or P2P link.
- **Zero Cloud Infrastructure**: No registration, no user account, no tracking servers.
- **Persistent Device ID**: Unique device identity stored locally on device without analytics.
- **Streaming Security Hub**: Fine-grained permission management for camera, audio, and screen access with trusted device whitelisting.

---

© 2026 **NearMitra Ecosystem** • Built with Flutter & Kotlin Native.

