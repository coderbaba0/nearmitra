# NearMitra — Connect Android & Windows

**Local-first communication, file sharing and permission-based AI across your devices.**

NearMitra connects Android phones and Windows PCs for chat, file and folder transfers, WebRTC calls, camera/audio streams and shared AI engines. Use a reachable LAN or supported Wi-Fi Direct/P2P connection for nearby devices, with optional Internet/WAN discovery and signaling for remote connections. WAN and cloud AI require internet access; supported local workflows start with your own devices and network.

[Website](https://coderbaba0.github.io/nearmitra/) · [Source code](https://github.com/coderbaba0/nearmitra) · [Downloads](#latest-releases) · [Getting started](#first-cross-device-test) · [Contributing](CONTRIBUTING.md) · [GPL-3.0-only license](LICENSE)

## Latest releases

Android **1.0.3** and Windows **2.1.23** are available through GitHub Releases.

| Platform | Version | Download | Release notes |
|---|---|---|---|
| Android | 1.0.3 · build 4 | [Download Android APK](https://github.com/coderbaba0/nearmitra/releases/download/v1.0.3/NearMitra-Android-1.0.3.apk) | [Android v1.0.3](https://github.com/coderbaba0/nearmitra/releases/tag/v1.0.3) |
| Windows 10/11 x64 | 2.1.23 | [Download Windows setup](https://github.com/coderbaba0/nearmitra/releases/download/v2.1.23/NearMitra_Setup_2.1.23_x64.exe) | [Windows v2.1.23](https://github.com/coderbaba0/nearmitra/releases/tag/v2.1.23) |

[Browse all releases](https://github.com/coderbaba0/nearmitra/releases). For platform setup, see the [Windows guide](nearmitra-windows-app/README.md), [hardware and feature notes](nearmitra-windows-app/IOT_SETUP.md), and [Windows signing guide](nearmitra-windows-app/WINDOWS_SIGNING.md).

## Video walkthrough

See how to use NearMitra in this YouTube walkthrough. Click the preview or **▶ Play video** to open the video at **0:24**.

<p align="center">
  <a href="https://www.youtube.com/watch?v=M79xzZUn_0Q&amp;t=24s" title="Play the NearMitra usage walkthrough on YouTube">
    <img src="https://i.ytimg.com/vi/M79xzZUn_0Q/hqdefault.jpg" alt="NearMitra usage walkthrough — click to watch on YouTube" width="640" />
  </a>
  <br />
  <a href="https://www.youtube.com/watch?v=M79xzZUn_0Q&amp;t=24s"><strong>▶ Play video — How to use NearMitra</strong></a>
</p>

## Latest updates — 24 October 2026

**Windows 2.1.23** restores drag-and-drop file sending from the dashboard and chat: online devices receive dropped files through the existing Nearby-first/WAN routing, multiple files stay targeted to the selected recipient, and offline devices show a clear message. Android **1.0.3** includes background presence startup, retry and Back-to-background changes; the Recent apps swipe-away limitation is documented below.

| Area | Current behavior |
|---|---|
| Chat and transfers | Nearby/P2P and WAN identities share conversation routing, with an available direct route preferred. Windows shows incoming file/folder progress, byte counts, speed and ETA in the sender's chat. Per-device and Chat unread badges use the active theme and count a transfer once across completion. |
| Reactions and replies | Windows handles mobile reactions and removal over Nearby and WAN. Quoted replies preserve the original sender/text and can jump to the original message. Desktop messages/files support Reply, Select, Copy and Forward, including forwarding multiple selected items. Typing indicators refresh while composing and preserve WAN state across polling. |
| Calling | Connected-call controls support camera/audio switching and screen sharing, with cleanup on stop/disconnect. Normal microphone/camera calls do not open a screen-share picker. Nearby device resolution and receive-only PCs without a microphone are handled separately from explicit audio broadcast. |
| Wi-Fi Audio | A standalone speaker/microphone session, separate from calls and CCTV. Windows Voice → Broadcast PC Audio to Phone pairs with Android Streaming → Wi-Fi Audio. Requests require owner approval; both sides can stop. Android includes output-route feedback and a meter based on actual audio energy. |
| All-PC sound | Windows uses native WASAPI loopback of the chosen playback output for Chrome, YouTube and desktop players. PCM conversion follows the device's actual sample rate. An active physical or virtual playback output is required; no audio driver is bundled. Browser-tab capture remains a separate option. |
| Nearby AI | A device chat's Nearby AI uses that selected device's shared engine. My AI configures the current device's own engine. Windows can allow/revoke a selected phone's access to its configured Ollama; actual response chunks stream to the phone, with loading heartbeats, cancellation and permission checks during generation. |
| Presence | Nearby LAN/P2P is preferred; enabled, trusted WAN is the fallback. Windows verifies quiet local peers through TCP hello before expiring presence and keeps its Go workers active in the tray. Mobile restores Internet presence at startup without opening the WAN tab, retries failed initialization and respects saved Internet OFF. |
| Phone sensors | Windows can request an owner-approved battery/location snapshot. Android handles permission levels, recent readings and fresh GPS/network fixes; Windows displays the actual location status. This is not continuous tracking. |
| Windows integration | Theme-aware sidebar icons, tray/startup support, native file-picker ownership, and native Explorer Open Folder / Show in Folder. Exact folder matching raises/restores the requested Explorer window rather than assuming a launched process takes focus. |
| Installer | Per-user setup, default-checked minimized auto-start, native shortcut/registry/uninstall steps with no PowerShell dependency. Private-network firewall setup is optional and still requests administrator approval. Declining it completes installation with a firewall warning. |

### Building your own copy

Use the release downloads above to install the app. Contributors can build from source using the platform instructions later in this README and the Windows guide.

<details>
<summary>Local build output paths</summary>

| Artifact | Build output |
|---|---|
| Windows setup 2.1.23 | `nearmitra-windows-app/build/windows-release/NearMitra_Setup_2.1.23_x64.exe` |
| Windows portable executable | `nearmitra-windows-app/build/windows-release/NearMitra.exe` |
| Android distribution APK 1.0.3 | `build/releases/NearMitra-Android-1.0.3.apk` |

Windows SHA-256 hashes are recorded in [SHA256SUMS.txt](nearmitra-windows-app/SHA256SUMS.txt). Android builds also produce a local `build/releases/SHA256SUMS.txt`. Compare a downloaded artifact only with a checksum published for that exact release asset.

</details>

### Android background behavior and known issue

With **Settings → Run in Background** ON, double-Back from the home screen minimizes the Android task instead of finishing its Flutter activity. Home/minimize keeps the existing networking runtime available. Internet mode restores at startup without selecting the WAN tab; explicitly switching Internet mode OFF remains saved. Nearby remains the preferred route.

**Removing the app by swiping it from Recent apps still has an unresolved delivery/notification issue.** The foreground-service notification can remain while the activity-owned Flutter networking runtime is no longer available; messages may appear only after reopening. Android 1.0.3 is a rebuild of the current source and does not add an activity-independent engine or fix this reported swipe-away behavior. Automated test results do not establish reliable killed-state or screen-off delivery.

### First cross-device test

1. Exit older Windows tray/portable copies, install Windows 2.1.23, and update the phone to Android 1.0.3 using the release downloads above.
2. Connect both devices through Nearby LAN or a working Wi-Fi Direct/P2P link. Approve requests on the receiving device.
3. Test text, a file and a folder. Check the sender's Windows chat while receiving, then test reaction removal, quoted Reply, hover → Copy and Select → Forward.
4. For PC sound, open Windows **Voice → Broadcast PC Audio to Phone**, choose **All PC apps** and the same playback output used by your player, then **Send PC audio**. Approve on Android. Without a physical output, configure a separately installed virtual playback device first. Tab mode requires selecting an audible tab and sharing its audio.
5. For phone microphone playback in NearMitra, choose **Use phone mic** and approve microphone access on Android. Using it as another Windows application's microphone requires a separate virtual audio routing device.
6. For Windows Ollama sharing, configure/enable the engine in **My AI settings**, select the phone's chat and choose **Share my AI with this device → Allow**. On the phone, open that Windows device's Nearby AI. To query the phone's engine from Windows, its owner must separately allow the Windows device on the phone.

### Release and validation limits

- **Unsigned installer:** `flutterfever.com` is installer/Apps branding. UAC still shows **Unknown publisher** until a trusted Authenticode certificate signs the app/setup. The current installer still offers optional firewall elevation; a no-UAC installer was discussed but was not implemented. See [signing requirements](nearmitra-windows-app/WINDOWS_SIGNING.md).
- **Build artifacts:** setup EXEs, APKs, user data and logs are not versioned. Build the Windows installer with `nearmitra-windows-app/build-installer.bat`; local output is `nearmitra-windows-app/build/windows-release/NearMitra_Setup_2.1.23_x64.exe`. Release binaries are distributed separately through [GitHub Releases](https://github.com/coderbaba0/nearmitra/releases).
- **Compatibility:** standalone Wi-Fi Audio, native Android speaker routing and the GPS-provider changes require updated mobile source. Existing older APKs do not acquire those features when Windows is upgraded. The Windows Ollama stream uses the existing mobile streaming protocol.
- **Transport:** standalone Wi-Fi Audio and device-chat Nearby AI require a direct Nearby/P2P connection. They are not WAN-only features. Ollama has incremental host streaming; cloud engines retain their current provider response behavior.
- **AI vision:** the warehouse/person-counting database, persistent identities, male/female classification and production object-counting pipeline were discussed and deferred. Screenshot labels and visual filters do not establish that these models or a counting database are implemented. IoT devices require the supported gateway/driver contract described in [IOT_SETUP.md](nearmitra-windows-app/IOT_SETUP.md).
- **Security:** local TCP chat/file/AI paths use newline-delimited JSON and payload bytes; do not assume AES/end-to-end encryption for every LAN packet. WebRTC media/data-channel security is a separate transport. Owner permission is an application access control, not cryptographic device authentication.
- **Verification:** Windows Go tests and 136 desktop/installer JavaScript checks pass. An interactive Windows test verified Explorer foreground activation with an existing folder behind a temporary app window. All 77 mobile tests pass; the Android 1.0.3 release APK and native Kotlin build succeed; source-analysis details are listed in the Windows README. Physical phone–Windows audio/call/GPS/AI behavior still needs device testing; improved buffering does not establish that every reported low-pitch/slow-playback case is resolved.

---


---

## Distributed System Architecture

<div align="center">
  <img src="screenshot/androidapp/archtech.png" alt="NearMitra Distributed System Architecture" width="100%"/>
</div>

---

## Cross-Platform Architecture (Android Mobile & Windows Desktop)

NearMitra bridges mobile devices and desktop workstations across local Wi-Fi networks, direct Wi-Fi Direct links, and global WAN:

- **Android Mobile Application**: Native Flutter + Kotlin integration featuring a 60 FPS P2P Radar, live camera QR pairing, Triple-Mode Switch (Nearby / P2P / WAN), scoped storage file pipeline, WebRTC audio/video calling, live CCTV/audio streaming, persistent outbox queue, first-time interactive walkthrough, and Android Quick Settings Tile.
- **Windows PC Desktop Application**: Desktop workstation application with direct P2P link support, real-time activity tracker, local Ollama AI hosting, CCTV vision telemetry node, and system tray integration.

---

## App Visual Showcase

Screenshots illustrate earlier UI versions. In particular, CCTV vision labels are not proof of deployed person-counting, identity or classification models; use the current release notes above for implementation status.

### Series 1: P2P Discovery, 60 FPS Radar & WebRTC Calling

| 60 FPS Continuous P2P Radar | Real-Time LAN Discovery & Typing Status | Encrypted P2P Voice & Video Calling |
| :---: | :---: | :---: |
| ![P2P Radar](screenshot/androidapp/Screenshot_20260902_184448.jpg) | ![LAN Discovery](screenshot/androidapp/Screenshot_20260902_191425.jpg) | ![P2P Calling](screenshot/androidapp/Screenshot_20260902_184926.jpg) |

---

### Series 2: P2P Chat, File Transfers, Reactions & Outbox Queue

| P2P Chat & High-Speed APK Transfer | In-Chat Emoji Reactions | Multi-File & Folder Selection Sheet | Offline Persistent Outbox Queue |
| :---: | :---: | :---: | :---: |
| ![P2P Chat](screenshot/androidapp/Screenshot_20260902_184508.jpg) | ![Emoji Reactions](screenshot/androidapp/Screenshot_20260902_191342.jpg) | ![Multi-File Sheet](screenshot/androidapp/Screenshot_20260902_190320.jpg) | ![Outbox Queue](screenshot/androidapp/Screenshot_20260902_191205.jpg) |

---

### Series 3: Decentralized Nearby AI & Fleet Device Management

| Nearby AI Mode & Query Handling | AI Fleet Devices Dashboard | Nearby AI Engine Configuration |
| :---: | :---: | :---: |
| ![Nearby AI Chat](screenshot/androidapp/Screenshot_20260902_191302.jpg) | ![AI Fleet Devices](screenshot/androidapp/Screenshot_20260902_184751.jpg) | ![AI Settings](screenshot/androidapp/Screenshot_20260902_184729.jpg) |

---

### Series 4: Real-Time CCTV Streaming, Audio Relay & Security

| Remote CCTV Camera Streaming | Live Audio & Walkie-Talkie Stream | P2P Streaming Access Security |
| :---: | :---: | :---: |
| ![CCTV Streaming](screenshot/androidapp/Screenshot_20260902_184643.jpg) | ![Audio Streaming](screenshot/androidapp/Screenshot_20260902_184655.jpg) | ![P2P Security](screenshot/androidapp/Screenshot_20260902_184704.jpg) |

---

### Series 5: Activity History, Call Logs & System Settings

| Activity & Call History Hub | System Settings & Mesh Relay Toggle |
| :---: | :---: |
| ![Activity History](screenshot/androidapp/Screenshot_20260902_184821.jpg) | ![App Settings](screenshot/androidapp/Screenshot_20260902_184719.jpg) |

---

### Series 6: Windows Desktop Workstation Hub & High-Speed P2P Transfers

| Windows Network Dashboard & 50+ MB/s Dropzone | Encrypted Direct P2P Chat & File Transfers |
| :---: | :---: |
| ![Windows Dashboard](screenshot/windowsapp/0.png) | ![Windows P2P Chat](screenshot/windowsapp/1.png) |

---

### Series 7: Windows AI Fleet, Local Ollama Host & Neural Studio

| Multi-Provider Nearby AI Engine | AI Fleet & Local GPU Ollama Compute Node |
| :---: | :---: |
| ![Nearby AI Windows](screenshot/windowsapp/3.png) | ![AI Fleet Studio](screenshot/windowsapp/08.png) |

---

### Series 8: AI Vision CCTV Surveillance & Telemetry Diagnostics

| CCTV Surveillance Node (OpenCV Engine) | AI Vision Telemetry (Intruder, Theft, NDVI) |
| :---: | :---: |
| ![Windows CCTV Node](screenshot/windowsapp/04.png) | ![AI Vision Telemetry](screenshot/windowsapp/05.png) |

---

### Series 9: HD Audio Intercom Studio, WebRTC Call, IoT & Storage

| HD Voice & Live Audio Intercom Studio | Active Encrypted WebRTC Voice Stream |
| :---: | :---: |
| ![Audio Intercom Studio](screenshot/windowsapp/06.png) | ![Encrypted Voice Call](screenshot/windowsapp/07.png) |

| Hardware & IoT Virtualization Hub | Recents Storage & CCTV Recordings Hub |
| :---: | :---: |
| ![Hardware IoT Hub](screenshot/windowsapp/09.png) | ![Recents & Storage](screenshot/windowsapp/10.png) |

| Windows System Settings & Streaming Security |
| :---: |
| ![Windows Settings](screenshot/windowsapp/11.png) |

---

## Core Pillars & Key Features

### 1. Decentralized Nearby AI & Heterogeneous Model Sharing Hub (Primary Feature)

#### The Problem:
Modern artificial intelligence workflows require diverse, specialized models:
- **Vision Models**: For image analysis, crop disease inspection, and visual defect detection.
- **Deep Reasoning Models**: For mathematical logic, coding, and structured planning.
- **Domain-Specific Models**: Specialized weights for healthcare/first-aid, agriculture, or engineering.
- **Lightweight General Chat Models**: Fast conversational assistants.

No single mobile smartphone possesses sufficient RAM, GPU compute, or battery capacity to host and execute multiple heavy on-device models simultaneously. Furthermore, individual users cannot maintain multiple paid API subscriptions for diverse models.

#### The NearMitra Solution:
NearMitra introduces a **Local Peer-to-Peer AI Model Sharing Protocol**:
- **Device as AI Host**: A Windows PC running Ollama, or a phone with its own supported AI provider configuration, can share its configured engine with approved peers.
- **Permission-Based LAN Querying**: An allowed client can query the selected host’s configured engine over Nearby/P2P. Windows Ollama responses stream incrementally; cloud-hosted engines still require internet access.
- **Host-Owned Model Selection**: Each owner selects the engine/model in My AI settings. Clients use that selected host’s engine without downloading its weights; model capability discovery and specialist vision pipelines remain separate work.
- **Granular Security Controls**: AI Host nodes maintain complete control with persistent per-peer access whitelisting and revocations.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                 NearMitra Decentralized AI Sharing Topology                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   [ Client Phone A ] ───(P2P / LAN Socket)───► [ Local AI Host (PC) ]       │
│   • Asks Vision Prompt                         • Runs Ollama / GPU Weights  │
│                                                • Llama-3 / Gemma / Phi-3    │
│                                                                             │
│   [ Client Phone B ] ───(P2P / LAN Socket)───► [ Domain AI Node (Phone) ]   │
│   • Asks Medical / Crop Prompt                 • Runs Domain-Specific SLM   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

### 2. Integrated Multi-Hop Mesh Relay Architecture

NearMitra contains a built-in **Multi-Hop Mesh Networking Engine** designed for off-grid scenarios:

#### Why Mesh Relay is Integrated:
- In remote areas, disaster zones, or dense buildings, two devices may be out of direct Wi-Fi range or separated by physical obstacles with no central router available.
- NearMitra nodes automatically act as cooperative relay bridges. When Node A sends a packet to Node C, intermediate Node B forwards the packet transparently.
- **Loop Prevention & TTL**: Includes unique 64-bit message deduplication rings, dynamic Hop-Count tracing (`A -> B -> C`), and Time-To-Live (TTL) decrements to ensure network bandwidth efficiency.

---

### 3. Triple Link Layer: Nearby (LAN), Direct P2P & Global WAN (Internet)

NearMitra offers a flexible multi-mode connectivity layer to seamlessly connect devices whether they are offline, in close proximity, or across the globe:

- **Nearby Mode (LAN Discovery)**: Automatically discovers all peers on a shared Wi-Fi network or mobile hotspot using zero-configuration UDP multicast (`239.255.43.88:43888`) and subnet scans.
- **Direct P2P Mode (Wi-Fi Direct v7.1 Radar)**: Establishes a direct high-throughput hardware link between two devices without requiring an external Wi-Fi router, hotspot, or internet connectivity.
- **Global WAN Mode (Internet / Cloud Relay)**: Extends NearMitra beyond local boundaries, allowing users to securely chat, transfer files, and initiate encrypted WebRTC calls with global remote peers over cellular data or public internet when offline local transport is unavailable.
- **Hardware Type Identification**: Automatically identifies nodes as Android phones, Windows PCs, or generic hardware with dedicated indicators.

---

### 4. Interactive Guided Walkthrough & Onboarding Tour

- **Smart First-Time Tour**: An animated, non-intrusive spotlight onboarding tour on first launch highlighting Nearby, P2P, and WAN modes.
- **Dynamic Pointer & Replay Support**: Features dynamic focus target bounds, step indicators, and instant replay capability anytime from App Settings.

---

### 5. 60 FPS Continuous P2P Radar & Smart Setup

- **60 FPS Hardware Sweep**: Continuous rotating radar sweep arc with expanding wave pulses and fading trails.
- **Dynamic Hardware Diagnostics**: Detects Wi-Fi or Location (GPS) states on Android and presents 1-tap action banners to enable required radios without navigating through settings menus.
- **Built-in QR Scanner**: Integrated camera scanner with animated laser reticle for 1-tap Wi-Fi Direct MAC pairing.

---

### 6. Offline Outbox Queue (Store & Forward Auto-Sync)

- **Persistent Outbox Queue**: Messages and files sent to offline or temporarily unreachable peers are preserved in local storage (`SharedPreferences`).
- **Visual Status Badges**: Displays a distinct **Queued** status indicator on pending bubbles.
- **Auto-Sync on Reconnect**: When the target peer is discovered online, the background queue manager automatically flushes pending items in chronological order.
- **In-Chat Cancellation**: Users can cancel or delete queued items directly from the chat bubble prior to delivery.

---

### 7. Real-Time Audio & Video Calling

- **Nearby/P2P Voice & Video Calls**: Direct device-to-device audio and video powered by WebRTC with local signaling. Conversation transport routing keeps normal chat separate from direct-call availability.
- **Full-Screen Call Interface**: Audio mute, camera flip, speakerphone switching, and call duration tracking.
- **Background Call Delivery**: Integrated with native Android full-screen incoming call notifications even when the application is backgrounded or the screen is locked.

---

### 8. Live Streaming Hub (CCTV & Audio)

- **CCTV Video Feed**: Stream live camera feeds from one device to any authorized peer on the network.
- **Live Microphone Audio**: Broadcast live low-latency audio to connected nodes.
- **Security & Authorization**: Persistent per-device permission management for camera, audio, and screen streaming access.

---

### 9. High-Speed Offline File & Folder Transfer

- **High Throughput Transfers**: Exchange documents, media, APKs, and compressed archives at full hardware Wi-Fi link speeds (up to 50+ MB/s).
- **Live Transfer Metrics**: Real-time progress indicators, transfer speed (MB/s), and estimated time remaining (ETA).
- **1-Tap File Opener**: Native integration to open or install received files directly from chat history.

---

### 10. Android Quick Settings Tile (`NearMitra Share`)

- **Notification Shade Tile**: Native `TileService` allows 1-tap application launch directly from Android Quick Settings (alongside Wi-Fi and Bluetooth).
- **Monochrome Vector Icon**: Clean vector drawable (`ic_qs_nearmitra.xml`) that dynamically tints across Android Light and Dark system themes.
- **Status Indicator**: Displays current P2P background listener state.

---

### 11. Native Android Background Service

- **Foreground Socket Daemon**: Native `FarmitraForegroundService` with `WAKE_LOCK`, `WifiLock`, and `MulticastLock` maintains socket listeners when minimized or locked.
- **Run in Background Switch**: Configurable toggle in App Settings with persistent state.

---

## Technical Architecture & Wire Protocol

NearMitra uses a low-overhead JSON-over-Socket wire protocol compatible across Android and Windows implementations:

| Component | Protocol / Port | Purpose |
| :--- | :--- | :--- |
| **UDP Discovery** | `UDP 239.255.43.88:43888` / Broadcast | Device presence announcement & IP discovery |
| **TCP Socket Transport** | `TCP 0.0.0.0:43889` | Chat messages, file payloads, typing indicators, AI prompts |
| **WebRTC Signaling** | TCP Socket Overlay / WAN Relay | Session Description Protocol (SDP) and ICE candidate exchange |
| **Wi-Fi Direct P2P** | Android `WifiP2pManager` | Point-to-point Wi-Fi Direct subnet link formation (`192.168.49.x`) |
| **WAN / Internet Relay** | Firebase RTDB / WebSocket | Global presence, discovery, and signaling for remote devices |

### Packet Header Schema (JSON + `\n`):

```json
{"type":"hello","sender":"Device Name","sender_id":"uuid-id"}
{"type":"chat","sender":"Device Name","sender_id":"uuid-id","message":"Message content"}
{"type":"ai_chat","sender":"Device Name","sender_id":"uuid-id","prompt":"Prompt query","ai":true}
{"type":"file","sender":"Device Name","sender_id":"uuid-id","name":"document.pdf","size":1048576}
{"type":"mesh_relay","msg_id":"unique_id","origin_id":"origin_uuid","target_id":"target_uuid","ttl":4,"hops":["NodeA"],"payload":{"type":"chat","message":"Mesh content"}}
{"type":"webrtc_offer","sender":"Device Name","sender_id":"uuid-id","sdp":"...","is_video":true}
```

---

## Future Roadmap & Technical Vision

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                           NearMitra Future Roadmap                            │
├───────────────────────┬───────────────────────────────┬───────────────────────┤
│    Edge AI & Vision   │     Acoustic Protection       │ Universal Ecosystem   │
│  • On-Device SLMs     │  • Theft & Intrusion Audio    │  • iOS, macOS, Linux  │
│  • Real-Time CV Alert │  • Anomaly Sound Detection    │  • Advanced Mesh P2P  │
│  • Compute Discovery  │  • Acoustic Alarm Trigger     │  • Shared Clipboard   │
└───────────────────────┴───────────────────────────────┴───────────────────────┘
```

### 1. Intelligent Compute Discovery & AI Capability Advertisement
Every NearMitra node on the local network automatically advertises its real-time hardware profile, loaded AI models, and available compute headroom:

```yaml
Node Capability Advertisement:
  Device: Desktop-PC
  RAM: 32 GB
  GPU: RTX 4060
  AI Models:
    - qwen2.5:7b
    - gemma2:9b
    - llama-3.2-vision
  Capabilities:
    - text
    - vision
    - embeddings
    - reasoning
  Compute Load: 28%
```

- **Autonomous Workload Routing**: Lightweight client nodes automatically discover and route complex queries (e.g., image reasoning vs fast text) to the most suitable idle node with available GPU/NPU headroom.
- **Dynamic Load Balancing**: Distributes concurrent prompt requests across multiple LAN hosts to maximize throughput and minimize latency.

### 2. On-Device Local SLM Execution (NPU / GPU Acceleration)
- Execute quantized Small Language Models (e.g., Google Gemma 2B, Llama 3.2 1B/3B, Microsoft Phi-3) directly on-device using MediaPipe, GGML, and TFLite runtimes.
- Enables zero-network, zero-cloud text generation and assistance on standalone hardware.

### 3. Condition-Based AI Vision Filtering in CCTV Streaming
- Real-time computer vision inference applied directly to CCTV camera streams:
  - **Intrusion Detection**: Automatic silent alerts dispatched over P2P upon human presence in restricted zones.
  - **Property & Agricultural Protection**: Object classification for livestock, stray animals, or vehicle entry with bounding-box telemetry.
  - **Hazard Detection**: Edge alerts for fire, smoke, and industrial hazards.
  - **Bandwidth Optimization**: Streams high-bitrate video feeds only when specified visual trigger conditions are met.

### 4. AI-Powered Acoustic Anomaly & Theft Protection
- Real-time local sound classification applied to live audio streams:
  - **Animal Distress & Barking Recognition**: Identifies canine distress or unusual nocturnal livestock sounds to deter farm/property theft.
  - **Break-In Detection**: Acoustic recognition for glass shattering, door tampering, and distress calls.
  - **Automated P2P Siren Broadcast**: Triggers automated sirens or flashlights on remote CCTV nodes upon anomaly detection.

### 5. Cross-Platform Ecosystem Expansion
- Extending native P2P direct connectivity across **iOS, macOS, and Linux**.
- Encrypted cross-device shared clipboard synchronization.

---

## Building the Application

For Windows Go/installer build steps and tests, see the [Windows README](nearmitra-windows-app/README.md).

### Prerequisites:
- Flutter SDK compatible with the Dart SDK constraint in `pubspec.yaml` (Dart 3.4 or newer)
- Android SDK and build tools matching the Gradle configuration (current APK minimum: Android 7.0 / API 24; target/compile SDK 36)
- Java JDK 17

### Build Commands:

```bash
# Get dependencies
flutter pub get

# Run mobile regression tests
flutter test

# Build the universal Release APK
flutter build apk --release

# Optional: architecture-specific Release APKs
flutter build apk --release --split-per-abi
```

**Generated Binaries**:
- `build/app/outputs/flutter-apk/app-release.apk` (universal APK; current distribution copy: `build/releases/NearMitra-Android-1.0.3.apk`)
- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (64-bit Modern Android)
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` (32-bit Android)
- `build/app/outputs/flutter-apk/app-x86_64-release.apk` (x86-64 Android)

The Android release build currently uses the debug signing configuration in `android/app/build.gradle.kts`. Use your own release signing configuration before store distribution.

---

## Privacy & Security Model

- **Local transport**: Nearby chat/file/AI requests use direct local connections. WebRTC sessions may use STUN/ICE services depending on configuration.
- **Optional external services**: WAN uses Firebase presence/signaling; cloud AI requests reach the selected provider. These modes require their configured services and internet access.
- **Local application data**: Chat history, received files, device permissions and desktop configuration are stored locally. Browser-selected sent attachments are retained locally for forwarding. Protect the host and its configured provider credentials.

---

## License

NearMitra's Android app and Windows desktop source code are licensed under the **GNU General Public License, version 3 only** (`GPL-3.0-only`). See the full [LICENSE](LICENSE).

When distributing covered software or modified versions, comply with GPLv3's source-code and license-notice requirements. The software is provided without warranty, as described in the license. Third-party dependencies and bundled components retain their respective licenses.

## Configure your own Firebase for WAN / Internet

The repository includes **no shared Firebase project or maintainer database endpoint**. Nearby LAN/P2P works without Firebase. For Internet/WAN, follow the [Firebase setup guide](docs/FIREBASE_SETUP.md) and use your own development project on both devices.

1. Register your Android package in Firebase, create a **Realtime Database**, and keep your downloaded `android/app/google-services.json` local (Git-ignored).
2. Keep your own `google-services.json` locally with `project_info.firebase_url` set to your RTDB URL; normal Android run/build commands use it automatically. Alternatively, copy `config/firebase.example.json` to the ignored `config/firebase.local.json` and pass `--dart-define-from-file=config/firebase.local.json`.
3. The native Windows app does **not** use `google-services.json`. For normal builds, keep your own endpoint in the ignored `internal/wan/firebase_config.local.go` described in the guide. Alternatively, set `NEARMITRA_FIREBASE_RTDB_URL` before launching it, or configure `firebase_rtdb_url` in `%LOCALAPPDATA%\NearMitra\wan_config.json`. Use the same database as the phone.
4. Use the documented local emulator for integration tests. Current clients lack Firebase Authentication tokens; locked hosted rules reject them. Add authentication/authorization before public hosted deployment; never deploy the permissive emulator rules to production.

See the guide for exact config fields, emulator commands, required data paths and old-release/history limitations. Old APKs/EXEs and previously saved runtime settings can retain the former project; branch cleanup does not revoke access to those copies.

## Contributing

Contributions to the Android and Windows apps are welcome. Read the [contribution guide](CONTRIBUTING.md) for development setup, the `develop` branch workflow, relevant checks, device testing and pull request expectations. Bug reports, documentation, accessibility improvements and regression tests are welcome too.

© 2026 **NearMitra Ecosystem** • Built with Flutter & Native Android Frameworks.
