# Windows IoT setup and supported hardware

Install `build/windows-release/NearMitra_Setup_2.1.19_x64.exe` for Windows. For standalone wireless audio and the latest mobile call/presence fixes, the phone needs a newer Android build from the current source; the existing Android 1.0.1 APK predates these updates. Close older portable desktop copies before opening the installed version.

## Phone battery and location

Run the updated Android source and keep NearMitra open on the phone; no new APK accompanies this Windows build. Select its Nearby IP in Windows IoT, then choose **Request Phone Sensors**. The phone owner approves one snapshot: battery only, or battery and location. Android location permission and an enabled location provider are required for GPS. Permission denial, missing fixes and older mobile builds produce visible errors. A battery-only snapshot clears previously shared coordinates. No background location tracking is started.

## LAN relay, soil sensor and weighing scale

Open **Device connections & compatibility** and save the URLs of devices or gateways implementing this JSON HTTP contract. A generic USB or Bluetooth device is not automatically an HTTP gateway; its firmware or adapter must implement the contract. No physical command is sent when saving settings.

| Device | Request | Required response |
|---|---|---|
| Relay channel | POST configured URL, `{"power":true}` or `{"power":false}` | Matching boolean `{"power":true}` / `{"power":false}` |
| Soil sensor | GET configured URL | `{"moisture_pct":42,"temp_c":28,"humidity_pct":62}`; moisture 0–100 required |
| Scale | GET configured URL | `{"weight_kg":125.5}`, non-negative |
| Scale tare | POST configured URL, `{"action":"tare"}` | `{"weight_kg":0}` |
| NFC gateway | GET configured URL | `{"tag_id":"04A288","ndef_data":"optional decoded content"}` |

Requests have a five-second timeout and require a successful HTTP status and valid JSON response. Relay state changes in the UI only after the device acknowledges the requested state. Settings persist under `%AppData%\NearMitra\hardware.json`.

## Relay timers

Configure the relay URL, channel, local start time and duration. Both ON and OFF operations are saved before scheduling. NearMitra must remain open for timers to execute. After restart, overdue starts are skipped when their execution window has passed; pending OFF requests are recovered and retried. Scheduled commands retain their original endpoint even if connection settings change. Cancel/stop must confirm OFF for a started timer before removing its recovery operation. Offline Windows software cannot guarantee a physical pump cutoff; use the controller's hardware watchdog for unattended equipment.

## USB NFC readers

Leave the NFC gateway URL empty to use Windows Smart Card (PC/SC). Connect a contactless PC/SC reader, place a tag on it, then scan. The reader must support the GET DATA UID command `FF CA 00 00 00`. This reads a UID, not arbitrary encrypted MIFARE/NDEF contents. Reader/service errors and timeouts are shown. NFC writes are not implemented.

## Diagnostics and audio

Hardware scan uses Windows PnP with a bounded timeout. It does not invent devices when detection fails. Presence and driver status do not guarantee that another application has released a device. Normal Nearby audio/video calls use only the microphone/camera and do not open the Share Tab picker. The broadcast source selector applies only to explicit PC-audio broadcasts. Audio sharing uses the shared Nearby WebRTC call, with phone acceptance. Enable Share audio in the Windows picker. Stopping screen/audio sharing releases the capture and ends the matching call.

## Validation limits

Automated checks cover actual local HTTP exchanges, acknowledgement failures, gateway persistence, timer restart/cancel recovery, phone TCP response/denial, empty/failing hardware scans and capture cleanup. Physical relay, sensor, scale, NFC and two-device audio/GPS operation still require the corresponding real hardware.

Implementation references: [Windows SCardConnect](https://learn.microsoft.com/en-us/windows/win32/api/winscard/nf-winscard-scardconnectw), [Windows SCardTransmit](https://learn.microsoft.com/en-us/windows/win32/api/winscard/nf-winscard-scardtransmit), [Android LocationManager](https://developer.android.com/reference/android/location/LocationManager), [Android BatteryManager](https://developer.android.com/reference/android/os/BatteryManager).

## PC capture-device availability (Windows 2.1.1)

“Requested device not found” from media capture refers to a PC microphone or camera. It does not mean the selected Nearby phone is disconnected. Removed microphone selections retry the default/available physical input. A missing camera preserves microphone capture; absent local tracks negotiate incoming audio/video instead of blocking the invitation. The call UI explicitly reports which local capture device is unavailable. Receiving media does not create a Windows speaker, microphone or camera: local playback/capture still requires enabled hardware/drivers. Permission denial remains a visible permission error.

## Nearby calling update (Windows 2.1.2 / Android 1.0.1)

Both devices need this update. Mobile chat enables audio/video calling for a direct Nearby or Wi-Fi Direct/P2P route, including Windows peers. WAN-only and relayed mesh routes do not enable these call buttons. The open phone app displays an Answer/Decline dialog without relying on native incoming-call notification permission; background invitations use CallKit with a UUID call ID. Invitations expire and busy calls reject new invitations.

Windows requests a `call_ringing` acknowledgement from the mobile TCP handler; a busy response is reported as busy. Older mobile versions without this acknowledgement remain compatible, but successful socket delivery alone does not prove that a ringing screen appeared. Outgoing mobile calls register listeners and initialize WebRTC before sending the invitation. Media is marked connected only after the actual WebRTC/ICE connection succeeds.

Regression tests cover direct Windows/Wi-Fi Direct eligibility, WAN-only rejection, foreground incoming calls, background CallKit UUIDs, duplicate/busy invitations and a Windows-format invite sent over a real local TCP socket to the mobile handler. Physical two-device media playback still needs verification after updating both apps.

## Standalone wireless speaker and microphone (source update)

The Streaming section now includes **Wireless Audio** on Android and wireless audio controls under **Voice → Broadcast PC Audio to Phone** on Windows. This is a separate, one-way audio session with its own session ID and signalling; it does not open the call UI or camera. Windows setup 2.1.8 includes this feature. The phone also needs the corresponding updated Android source; the older Android 1.0.1 APK in the release folder does not include standalone wireless audio. No new Android APK was generated with this Windows-only release.

- **PC music/YouTube → phone speaker:** In Windows **Voice**, use the shared Audio target selector to select the Nearby phone, choose **System audio** in **PC audio broadcast source**, and press **Broadcast Selected Audio** under **Broadcast PC Audio to Phone**. In the OS picker, choose a tab/screen and enable **Share audio**. Approve playback on the phone. Alternatively, on Android choose **Streaming → Wireless Audio → Speaker → Listen to PC audio**, then approve the request and choose the source in Windows. The phone's microphone remains off.
- **Phone microphone → PC playback:** In Windows **Voice**, select the phone in the shared Audio target selector and choose **Use phone microphone** under **Broadcast PC Audio to Phone**. On the phone, approve the request and grant microphone permission. Alternatively, start **Streaming → Wireless Audio → Microphone → Share phone microphone** from Android and approve playback in Windows. No PC microphone or camera is opened for receiving.
- Both sides provide Stop controls. Outgoing audio can be muted and incoming playback has a volume control. If Windows blocks autoplay, **Play audio** appears and requires a click. Android shows a foreground notification for an active speaker/microphone stream; reopen the app to reach Stop controls.

Keep NearMitra open on both devices to approve a request. Direct Nearby LAN or Wi-Fi Direct/P2P is required; WAN-only/relayed devices are not supported. Calls and other camera/audio streams must be stopped before starting wireless audio. A pending request times out after 35 seconds. Session ID and peer IP checks prevent delayed/unrelated signals from stopping another stream. Owner approval is required for every new remote microphone or playback request; existing CCTV trust does not bypass it.

Windows microphone reception is **playback inside NearMitra**, not a virtual Windows recording device. To select the phone microphone in another program, install/configure a separate virtual audio device; no audio driver is bundled or installed by this feature. PC system capture depends on the browser/Windows providing a shared audio track; the picker reports missing audio instead of claiming success. Live two-device latency and playback still require hardware verification.

### Wireless audio connection update

Mobile tab: **Streaming → Wi-Fi Audio** (equalizer icon). Keep the updated mobile app open while approving the first audio session. In Windows **Voice → Broadcast PC Audio to Phone**, select the phone above and use **Send PC audio** in Wireless audio controls. System audio is now the default; choose a YouTube/music tab or screen and enable **Share audio**, then allow playback on the phone. **Use phone mic** reverses the direction and asks for microphone permission on the phone.

Source selection, remote approval, and media connection now have separate deadlines. A received permission acknowledgment shows that the peer was reached; it does not mark audio as live. The selected direct device remains available across discovery expiry. Audio uses direct ICE candidates plus the same STUN fallback as Nearby calls; STUN is optional and does not relay the audio. Android speaker playback uses the media audio configuration and restores the communication configuration after stopping. Old Android APKs without wireless-audio handling still need an updated build.

Windows 2.1.7 fixed a desktop asset-serving bug: wireless-audio.js was embedded but its URL returned 404, preventing both outgoing audio and incoming phone approval. Exit old tray/portable instances before installing. This desktop-only fix does not require another mobile APK. Validation now checks every page script through the actual embedded HTTP handler and executes scripts in HTML order.

### YouTube sound / phone speaker correction (Windows 2.1.8)

The wireless-only capture requests unprocessed music audio and keeps the selected tab audio track. The Windows panel shows actual source level and packet flow after connection. If it says captured audio is silent, check that the selected YouTube video is playing and its tab is unmuted. A connected state alone cannot confirm that the tab contains sound.

The Android receive path now uses the communication configuration matching the existing WebRTC audio device instead of switching AudioSwitch to MODE_NORMAL/music, which can disable explicit speaker routing on affected phones. It selects the loudspeaker again when the receive connection becomes live. **Use phone speaker** allows manual recovery. This stream uses the phone's call-volume control; the in-app slider controls track gain. This mobile change requires running updated mobile source; no new APK was generated. Do not change global WebRTC initialization because calls share that audio device.

### Share-time capture compatibility (Windows 2.1.9)

Removed post-capture applyConstraints calls on the shared audio track. The picker supplies its actual tab audio without restarting the live source. The optional music content hint is now best-effort and cannot abort capture. Disconnect status includes the stage (opening audio, preparing connection, or sending offer); stop/reject reasons are persisted to the local NearMitra log for diagnosing actual device failures. This Windows-only correction does not change mobile code. Live YouTube playback still requires verification on the user's devices.

### All-PC capture, speaker switching and live meter (Windows 2.1.10)

In Voice → Wireless audio controls, **All PC apps** requests Entire screen capture with system audio. Select **Entire screen** and enable **Share system audio** to capture Chrome while NearMitra runs in Edge. **A tab in this app’s browser** instead prefers that browser’s tab picker. The browser retains source selection and sharing permission; all-PC audio can include other audible apps. Screen video is not added to the audio connection. See https://developer.chrome.com/docs/web-platform/screen-sharing-controls .

Mobile source adds a speaker/earpiece toggle with busy state and Android communication-device selection result. A failed output switch preserves the previous selection and displays an error. The animated meter reads actual WebRTC energy every 500 ms, becomes idle on silence/stop, and respects reduced motion. Interval jitter-buffer delay is displayed when available; supported native fast-acceleration is enabled to reduce accumulated playout buffering. None of these changes establishes that the reported low-pitch/slow-speed playback is resolved; actual audio-rate playback still needs device verification.

Run the updated mobile source with a full restart/rebuild for the new native output method. No APK was generated. Do not change playback speed or force a guessed sample rate to conceal an unmeasured clock problem.

### Native all-PC playback capture (Windows 2.1.11)

**Voice → Wireless audio controls → All PC apps** now uses native WASAPI shared-mode loopback of the selected Windows render endpoint. It no longer relies on Edge’s screen-sharing audio for Chrome or desktop players. Choose the same Windows playback output used by your player, click Send PC audio, and allow playback on the phone. **A tab in this app’s browser** preserves the existing browser-tab capture path. No camera, microphone or screen capture is opened in native system-only mode. No audio driver is bundled or installed.

The native capture reads the real device mix format (PCM16/24/32 or float32/64), transmits stereo float PCM only to the local browser using an explicitly requested, same-origin HTTP stream, and uses an AudioWorklet to convert the actual device sample rate to the AudioContext rate before WebRTC transmission. PCM packet fragmentation is preserved. A bounded buffer drops old backlog rather than allowing seconds of delayed playback to accumulate. Stop/abort closes the Windows capture and browser graph.

**Windows output requirement:** desktop players need an active physical or virtual playback device. On the tested PC, Core Audio enumerated zero active render endpoints, and selecting the default returned 0x80070490. Both audio services were running and the diagnostic process used the same Windows session/user as NearMitra. A brief hardware-tone capture could not run because of that missing endpoint; real native sound has not yet been verified on that PC. Browser tab capture works through a different audio path and remains usable.

Without a physical speaker/headphone, a virtual playback driver is required. One option is the official VB-CABLE package: https://vb-audio.com/Cable/ . Its vendor instructs administrator installation and reboot. This setup does not install it. After installing an output, choose its playback side (for VB-CABLE: CABLE Input) in Windows Sound output and for the player, then select that playback endpoint in NearMitra and refresh outputs. Capture uses the playback endpoint, not the microphone/recording side.

References: https://learn.microsoft.com/windows/win32/coreaudio/loopback-recording and https://developer.chrome.com/docs/web-platform/screen-sharing-controls .

### Phone location snapshot fix

An approved request now checks a recent (up to 60 seconds) cached reading from permitted GPS/network providers, then requests both providers instead of waiting only eight seconds for GPS. Approximate-only permission uses the network provider; older Android versions request a fresh update too. A fresh fix is allowed up to twenty seconds after approval/permission, and all pending provider callbacks are cancelled when the request finishes. Windows displays the phone's actual location status when no fix is available instead of hiding it behind generic GPS text. This is one approved snapshot, not continuous or background tracking. The mobile native change needs a full updated build/run; no APK or Windows installer was generated for this source-only fix.

### Incoming file progress and unread indicators (Windows 2.1.12)

Nearby files/folders now publish a stable transfer/message ID with sender ID/IP before receiving their payload. The sender's chat projects incoming progress, byte counts, average speed and estimated remaining transfer time; saving/extracting keeps the entry below 100% until history persistence succeeds. Completion replaces the live item instead of creating a duplicate. Failures retain sender identity and show the actual error. A folder's size/ETA covers its compressed payload; extraction time is not predicted.

Theme-coloured unread counts appear on Nearby/P2P device cards and the Chat navigation button. Progress updates and the completed message share one unread item. The sender's chat must be open and the app visible/focused to mark it read; opening another device does not clear it. Read IDs persist locally. Existing history is treated as a baseline on first use. State polls update every second and preserve chat scroll position when reading older messages. Tests cover live receive-before-payload, failures, same filenames, completion replacement, peer-scoped rendering and badge clearing. Live cross-device UI verification remains required. This Windows setup also includes the GPS status/timeout changes; the Android GPS-provider fix still requires updated mobile code, and no APK was generated.

### Native installer and startup defaults (Windows 2.1.13)

Auto-start minimized with Windows is checked by default and can be unchecked. Setup registers the selected preference for the current user. Shortcuts use the native Windows shell; startup and installed-app registration use Windows registry tools. Installation and the installed Uninstall.exe do not run PowerShell or depend on its execution policy. Upgrades replace the legacy PowerShell uninstall entry and remove the two obsolete installer scripts; chats and received files are preserved.

Private-network firewall setup remains optional and checked by default. It requests Windows administrator approval for the NearMitra setup executable itself, then applies program-specific TCP/UDP inbound rules limited to the private profile and local subnet using netsh. Declining that approval does not roll back installation: the completion screen explains that incoming Nearby discovery, files and calls may be blocked until NearMitra is allowed in Windows Firewall. Unchecking the option skips this elevation step. Windows can still display its standard security/unsigned-publisher prompts.

### Desktop reactions, quoted replies and forwarding (Windows 2.1.14)

The current launcher now handles incoming Nearby reactions, and desktop chat normalizes the backend reaction fields instead of reading only its old local emoji map. The local selection and remote reaction are stored separately; reaction removal clears the badge after polling/restart. WAN reaction controls are handled too, scoped to the channel peer. Delivery refreshes preserve independently stored reactions.

Nearby reply_to_id/reply_to_sender/reply_to_text and WAN replyToId/replyToSender/replyToText survive receipt, storage and outbound transmission. Quoted cards show the original sender/text and jump to the original message when it still exists. Desktop Reply opens a cancellable composer preview; switching conversations clears it.

Hover/focus a completed message or file for Reply, Forward and Select. Select several items, then Forward to choose/search a connected Nearby/P2P or enabled trusted WAN recipient. Items are forwarded in order with fresh IDs, without carrying a private quote from the source conversation. Successfully forwarded items leave the pending selection; failures remain available for retry and show an error. In-progress and failed transfers cannot be forwarded.

New desktop file/folder sends now share the same message ID on the wire and in persistent history. Native-picker files retain their original path. Browser-selected outgoing bytes are retained in the chat data directory under SentAttachments, including WAN uploads, for later forwarding. Received files retain their saved paths. Deleted/moved files and older attachment records that never saved their bytes/path show a clear unavailable-file error rather than reporting a successful forward. No mobile APK was generated; the existing mobile reaction and reply protocols are used. Live two-device validation is still required.

### Publisher branding and signing (Windows 2.1.15)

Installer UI and Windows Apps registration now use flutterfever.com. UAC obtains its verified publisher from a trusted Authenticode certificate, so branding alone cannot change Unknown publisher. Both the app and 2.1.14 setup were checked and reported NotSigned; the current Windows user had no code-signing certificate. The 2.1.15 output remains unsigned unless signing is explicitly configured. See WINDOWS_SIGNING.md. The release script now supports certificate-store signing and verification of the app before embedding, followed by signing and verification of setup; configured signing failures abort the build. The certificate's verified identity, not an arbitrary domain string, determines the UAC publisher.

### Selected-device Nearby AI and Ollama streaming (Windows 2.1.16)

**Device chat → Nearby AI** queries that selected Nearby/P2P device over its direct TCP AI protocol. It does not query the Windows local engine. The provider buttons that previously changed Windows settings were removed from this view. A missing send handler has been implemented, responses stream into a device-specific conversation, Stop aborts the request, and switching devices cancels the previous request. Permission denial, offline devices and truncated streams show explicit errors. **My AI settings** opens the owner's existing local engine configuration. WAN-only AI queries are not added by this change.

In the selected chat, **Share my AI with this device → Allow** enables the desktop sharing gate if needed and grants only the selected device's identity aliases. The owner must first configure and enable My AI, for example Ollama with an installed model. Allow does not switch the engine to the phone's model. Revoke removes that device's grant. The sharing panel displays both global sharing status and the selected device's permission. Other devices still need their own grant.

The Windows host now requests actual Ollama streaming (`/api/generate`, stream true), emits deltas as `ai_stream` packets and sends a separate done packet. It preserves the owner's My AI state, reports missing provider credentials rather than simulated shared output, and rechecks access before each token chunk. Model-loading heartbeats avoid the phone's line-reader timeout. Remote disconnect/Stop cancels generation. Other configured cloud providers retain their existing one-response generation behavior; this update does not claim token streaming for them. The existing phone receiver accepts this wire protocol.

Mobile source also removes silent fallback to its own engine when remote Nearby AI fails and preserves the remote host's denial reason. That mobile-source correction needs a future mobile rebuild; no APK was generated. The Windows host-stream fix can be tested with the existing mobile streaming receiver. Automated tests use a controlled Ollama HTTP server and an actual TCP-to-HTTP relay to verify early chunks, completion, denied access, mid-stream revocation, selected-device routing and separate conversations. Actual phone/Windows/Ollama hardware validation is still required.

Ollama streaming protocol reference: https://github.com/ollama/ollama/blob/main/docs/api.md

### Explorer foreground fix (Windows 2.1.17)

The top-right folder action, Received Files / Open Folder, CCTV recordings folder and Show in Folder now use native SHOpenFolderAndSelectItems rather than starting explorer.exe and assuming it takes focus. Show in Folder selects the literal file in its parent directory. Shell Automation resolves the exact full folder path to its Explorer window, including spaces, apostrophes, Unicode and UNC shares; matching a window title alone is avoided. Existing/minimized folder windows are raised/restored using normal z-order and foreground activation, without permanent topmost state, simulated keyboard input, registry focus-policy changes or PowerShell. If the user switches to another application while opening, the code avoids taking focus away from it. Windows can still enforce its foreground policy.

Invalid or removed files return a visible error. Browser actions wait for the native request result rather than showing an unconditional success toast. Tests cover native COM ABI and shell enumeration, decoded full-path matching and invalid items. An opt-in interactive Windows test opens a new temporary folder, puts a temporary app-style window in front, invokes Show in Folder and verifies the exact target Explorer window is foreground; it closes only its own test windows afterward.

Publisher status is unchanged: setup remains unsigned. The flutterfever.com branding does not establish a UAC verified publisher; a trusted code-signing certificate is still required, as documented in WINDOWS_SIGNING.md.

### Mobile Nearby AI reply visibility correction

The installed desktop was checked without changing its AI settings or grants: Ollama was running with the configured installed model, and a local TCP diagnostic using an already allowed identity received nine response chunks and a final done packet. This verifies the desktop host path, not an end-to-end phone UI session.

Two mobile UI defects were identified: prompt and response IDs were derived from the same millisecond/peer and could collide, and history notifications replaced the visible reply object while the typewriter continued updating a detached object. Mobile AI requests now use independent UUIDs and a draft that preserves the active reply through history reloads, peer selection and forwarding refreshes. Only the prompt/reply records are merged into storage; unrelated incoming history is retained. Overlapping AI sends are blocked, errors are visible, and disposing/clearing the active conversation cancels its pending stream and timer. Truncated answers retain their text with an incomplete-response warning.

Validation: all 60 mobile tests pass, including seven new cases for ID uniqueness, visible draft preservation across real history persistence, cancellation/deletion, actual TCP loading/chunk/completion packets, denial reasons and truncated streams. Static analysis of the affected mobile files and tests reports no issues. No Windows backend change, installer rebuild, mobile APK generation/installation or GitHub push was performed for this correction. Running the fix on the phone requires the updated mobile source; its currently installed binary does not change automatically.

### Mobile connected-call media switching correction

The mobile call screen now resolves the current video transceiver/sender from the live peer connection before replacing camera/display tracks, matching the existing sender identity or negotiated MID. It no longer relies only on the pre-negotiation wrapper. A receive-only/inactive video slot is explicitly set to sendrecv before a video-upgrade offer; previously an offer could be generated without changing that desired direction. Failed replacement/renegotiation restores the previously published video track and direction. If publishing an offer fails, its local SDP is rolled back when possible so a later retry is not blocked by a leftover local offer. The existing microphone sender and camera/screen permission flow are preserved.

Eight new sender-controller tests cover refreshed wrappers, negotiated MID recovery, audio-only upgrades, camera/display/audio switching, rollback, busy SDP and ended/missing-slot handling. Together with the AI reply regressions and existing app tests, all 68 mobile tests pass; affected call files pass static analysis. The exact reported RTP error was not present in the available phone logs, so its resolution still needs an actual updated-phone call test. This is a mobile source correction; no APK build/install, Windows setup rebuild or GitHub push was performed.

### Windows connected-call media switching correction

Windows now checks the live reserved video transceiver before camera/screen changes. When the negotiated slot is receive-only or inactive, it sets the desired direction to sendrecv before generating the upgrade offer. A pending negotiation rejects an upgrade before replacing the existing track. Failed offer delivery rolls back the local offer where possible and restores the prior video track/direction; the microphone sender is preserved. Camera off returns to audio, and stopping display capture restores the previous camera/audio state using the existing controls.

Validation: all 124 JavaScript UI/installer tests pass, including six new regression cases for receive-only/inactive upgrades, screen-offer failure rollback, pending SDP, refreshed transceiver lookup and missing video sender. The adapter test double now exposes its actual reserved transceivers, matching the browser API. Actual updated Windows/mobile device validation remains necessary. This change updates source only; it does not rebuild an installer or mobile APK and is not pushed to GitHub.

### Windows 2.1.18 installer

Built `build/windows-release/NearMitra_Setup_2.1.18_x64.exe` from the updated Windows source, including the connected-call media switching correction above. Go backend/installer tests pass, including offline payload extraction and exact app-payload equality; all 124 JavaScript UI/installer tests pass. SHA-256 manifests were regenerated. Existing installer defaults and per-user installation behavior are retained. Setup remains unsigned. No mobile APK, installation on either device or GitHub push was performed; live cross-device call testing remains necessary.

### Windows 2.1.19 installer

Built `build/windows-release/NearMitra_Setup_2.1.19_x64.exe` with Copy beside Select in message hover actions and desktop avatar handshake/rescan fixes. All 124 JavaScript tests and `go test ./...` pass, including configured-avatar handshake, installer extraction and embedded app equality. Both SHA-256 manifests were regenerated from the final artifacts. Setup remains unsigned. Live cross-device verification is still pending.
