# Windows IoT setup and supported hardware

Install `build/windows-release/NearMitra_Setup_2.1.2_x64.exe` and update the phone with `build/windows-release/NearMitra-Android-1.0.1.apk`. Close older portable desktop copies before opening the installed version.

## Phone battery and location

Install the accompanying updated Android APK and keep NearMitra open on the phone. Select its Nearby IP in Windows IoT, then choose **Request Phone Sensors**. The phone owner approves one snapshot: battery only, or battery and location. Android location permission and an enabled location provider are required for GPS. Permission denial, missing fixes and older mobile builds produce visible errors. A battery-only snapshot clears previously shared coordinates. No background location tracking is started.

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
