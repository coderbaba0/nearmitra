# NearMitra for Windows (Windows 11 Native Architecture)

NearMitra Windows App is an ultra-fast, local-first distributed edge computing, real-time communication, media streaming, and IoT hardware hub built in Go with native Win32/GDI+ Windows 11 Fluent UI rendering.

---

## 🎨 Windows 11 Fluent UI & Visual Aesthetics

- **Typography**: ClearType Subpixel Anti-Aliased `Segoe UI` (22px Title, 15px Subhead, 13px Body, 11px Small)
- **Modern Themes**:
  - **Dark Mode (Default)**: Deep Mica `#0B0F19`, Slate `#111827`, Card `#161F30`, Emerald Accent `#10B981`
  - **Light Mode**: Crisp Snow `#F8FAFC`, Pure White `#FFFFFF`, Slate Text `#0F172A`
- **8 Dedicated Modules**:
  1. 📡 **Discovery & Wi-Fi Radar**: Dynamic concentric radar HUD, instant peer cards, direct file/folder sharing
  2. 💬 **P2P Encrypted Chat**: Bubble conversation stream, emoji reactions (👍, ❤️, 👎, 🤔, 😂), 1-click clipboard copy
  3. 📹 **CCTV & Computer Vision AI**: OpenCV-style real-time filter pipelines, live MP4 stream recording, high-res snapshot capture, remote torch/lens flip
  4. 📞 **Voice & Walkie-Talkie Hub**: WebRTC HD low-latency voice, Push-To-Talk (PTT), real-time animated audio visualizer waveform, AI noise reduction
  5. 🧠 **AI Fleet Hub & Multi-LLM**: Gemini 3.5 Pro, ChatGPT-4o, Local Ollama (Qwen 2.5 / DeepSeek-R1), 1-click Kisan & Agricultural diagnostic presets
  6. 🔌 **IoT & Hardware Peripherals**: Multi-protocol support (Wi-Fi, Bluetooth, LAN, NFC, USB), Smart Irrigation Relays, Soil Moisture Sensors, Mandi Thermal Gate Pass Printers, Document Scanners
  7. 📊 **Transfers & Activity Logs**: Real-time MB/s speedometer progress bars, colorized timestamped event logs
  8. ⚙️ **Settings & About NearMitra**: Save directory browser, theme switcher, complete ecosystem specs & Kisan dedication

---

## 📹 Computer Vision Filter Pipelines

- **Normal Feed**: Standard uncompressed camera stream
- **Motion & Intruder Alert**: Activity index tracking & cattle/intruder alert grid
- **AI Crop Disease / Leaf Scan**: Spectral leaf health diagnosis & chlorophyll analysis
- **Night Vision IR Boost**: High-contrast low-light enhancement
- **Edge Contour Analysis**: Sobel/Canny edge boundary detection HUD
- **Thermal False-Color HUD**: Infrared false-color temperature mapping

---

## 📁 Project Structure

```
nearmitra-windows-app/
├── assets/                          # Branding assets, icons, and manifests
│   ├── nearmitra.ico                # Embedded multi-resolution icon
│   └── NearMitra.exe.manifest       # Windows 11 High-DPI & Theme Manifest
├── internal/
│   ├── ai/                          # Dual-tier LLM reasoning engine (Gemini, OpenAI, Ollama, presets)
│   ├── calling/                     # WebRTC voice signaling, Push-To-Talk, audio visualizer telemetry
│   ├── chat/                        # P2P chat history, emoji reactions, message wire
│   ├── config/                      # JSON configuration manager in %AppData%\NearMitra\
│   ├── iot/                         # Multi-protocol IoT drivers, support matrix, AI timer automation
│   ├── models/                      # Shared data models for peers, transfers, IoT, AI, headers
│   ├── network/                     # UDP 43888 multicast discovery & net.Interfaces() radar telemetry
│   ├── streaming/                   # CCTV video receiver, OpenCV filters, live stream video recorder
│   ├── transfer/                    # TCP 43889 chunk server, resume engine, SHA-256 verification
│   └── ui/                          # Windows 11 GDI Fluent UI renderer, ClearType fonts, event pump
├── main.go                          # Application entry point
├── build-windows.bat                # Fast build script (-ldflags="-H windowsgui -s -w")
├── install.ps1                      # Windows installer & shortcut generator
├── install-windows.bat              # 1-Click Windows installer batch script
└── README.md                        # Documentation
```

---

## 🌐 Network Protocol Specification

1. **LAN Network Mode (Primary / Default)**:
   - **Subnet Directed Scanning**: Instant ARP & TCP port probe across local network subnet (`192.168.x.x`).
   - **Direct IP / Hotspot Fallback**: 1-Click pairing via IP address, local gateway discovery, or QR code payload.
2. **P2P Mesh Mode**:
   - **UDP Port 43888** (`239.255.43.88`): Zero-Config Multicast Discovery & Compute Capability Advertisement.
   - **TCP Port 43889**: High-Speed File/Folder Streaming (50+ MB/s), WebRTC HD Voice Signaling, Live CCTV & Distributed AI Transport.
   - **Security**: AES-GCM 256-Bit end-to-end local socket encryption.
