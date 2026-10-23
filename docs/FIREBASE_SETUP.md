# Bring your own Firebase for Internet/WAN

NearMitra does not include a maintainer-owned Firebase project or shared production database. A fresh checkout builds for Nearby LAN/P2P without Firebase. Internet/WAN requires your own Firebase project/configuration, and both endpoints must use the same Realtime Database.

The Flutter Android app uses the Firebase SDK. The native Go Windows app uses the Realtime Database REST API; it does **not** use `google-services.json`. Do not copy Android API keys or service-account credentials into the Windows app.

## 1. Create your project and Realtime Database

1. Open the [Firebase Console](https://console.firebase.google.com/) and create your own development project.
2. Register an Android app with package name **`com.farmitra.nearby`**. If you change `applicationId`, register that new package instead.
3. Download that project's `google-services.json` into **`android/app/google-services.json`**. This file is ignored by Git. Do not reuse another project's file.
4. Open **Build → Realtime Database**, create a database and choose a region. This feature uses **Realtime Database**, not Cloud Firestore.
5. Copy the database's exact URL from the Console. Depending on the region, it can end in `.firebaseio.com` or `.firebasedatabase.app`. Do not append `.json` or a node name to the configured base URL.
6. Start with locked security rules. Before using a hosted database, implement authentication and rules appropriate to your deployment; see the security limitation below. Use the local emulator for the current unauthenticated development protocol.

Official references: [Flutter setup](https://firebase.google.com/docs/flutter/setup), [Realtime Database setup](https://firebase.google.com/docs/database/flutter/start), [REST setup](https://firebase.google.com/docs/database/rest/start), [database security rules](https://firebase.google.com/docs/database/security).

## 2. Configure the Flutter Android app

### Normal Android run/build with local native config

Keep your downloaded `android/app/google-services.json` in the project; Git ignores it, so publishing source does not remove your local copy. Ensure `project_info.firebase_url` contains your exact Realtime Database URL (download a fresh file after creating the database, or add that field locally). Android uses this native configuration automatically when Dart defines are absent. Your usual `flutter run` and `flutter build apk --release` commands work with it. Keep `firebase.json` local too; it is ignored.

### Optional explicit Dart configuration

Copy the placeholder example to an ignored local file:

```powershell
Copy-Item config/firebase.example.json config/firebase.local.json
```

Replace every placeholder in `config/firebase.local.json` with values from **your Android app**:

| Dart define | Source |
|---|---|
| `FIREBASE_API_KEY` | `client[].api_key[].current_key` in your `google-services.json` |
| `FIREBASE_APP_ID` | Matching client's `client_info.mobilesdk_app_id` |
| `FIREBASE_MESSAGING_SENDER_ID` | `project_info.project_number` |
| `FIREBASE_PROJECT_ID` | `project_info.project_id` |
| `FIREBASE_DATABASE_URL` | Exact Realtime Database URL from your Console |
| `FIREBASE_STORAGE_BUCKET` | `project_info.storage_bucket`, if present; otherwise leave empty |
| `FIREBASE_AUTH_DOMAIN` | Optional for this Android build; leave empty |

If the JSON contains multiple Android clients, choose the client whose `android_client_info.package_name` matches your app. The Dart defines and native JSON must refer to the same project and Android app. Do not use a web/iOS app ID for an Android build.

From the repository root:

```powershell
flutter pub get
flutter run --dart-define-from-file=config/firebase.local.json
flutter build apk --release --dart-define-from-file=config/firebase.local.json
```

`lib/firebase_options.dart` is a tracked, configuration-free loader of these build-time values. Do not overwrite it with generated project credentials. If using FlutterFire CLI, generate options to the ignored `lib/firebase_options.local.dart` for reference and copy the corresponding values into your local JSON. Keep generated `firebase.json`, `.firebaserc` and platform configuration files local.

Without Dart defines, startup attempts the native platform configuration. If no local configuration exists, Firebase initialization fails inside the background error handler while Nearby LAN/P2P remains available. The Android Google Services Gradle plugin is applied only when your local `google-services.json` exists. A missing config is not replaced with the maintainer's project.

## 3. Configure the native Windows app

There is no Windows `google-services.json`. For normal local Go builds, create **`nearmitra-windows-app/internal/wan/firebase_config.local.go`** (Git-ignored):

```go
package wan

func init() {
    DefaultFirebaseRTDBUrl = "https://YOUR_DATABASE_HOST"
}
```

Your existing Go run/build and installer build commands include that local configuration automatically. Binaries made this way contain your chosen endpoint; only distribute them if you intend them to use that backend. Keep this file on your computer when publishing source. New contributors create their own file with their own database URL.

Alternatively, choose an environment variable or your own runtime configuration.

In PowerShell, before starting the app:

```powershell
$env:NEARMITRA_FIREBASE_RTDB_URL = 'https://YOUR_DATABASE_HOST'
& '.\nearmitra-windows-app\build\windows-release\NearMitra.exe'
```

Alternatively, exit NearMitra from the tray, copy `nearmitra-windows-app/wan_config.example.json` to **`%LOCALAPPDATA%\NearMitra\wan_config.json`**, replace `firebase_rtdb_url` with your database URL and restart. If you already have a config, update its URL instead of overwriting your other settings. The environment variable takes precedence at startup. Do not check the runtime config into Git.

Windows has no default Firebase endpoint. With no endpoint configured, WAN workers do not start; Nearby, chat and local file transfers remain available. WAN activation accepts HTTPS, or HTTP on `localhost`/`127.0.0.1` for local emulator development. Reopening an older installed build can still use its old embedded configuration: rebuild and replace old app/tray copies.

## 4. Use the local emulator for development

The current clients do not provide a Firebase Authentication login/token flow. Use an isolated local Realtime Database emulator for integration tests; never solve authorization failures by making a production database publicly writable.

Install the Firebase CLI, then run from `config/firebase-emulator`:

```powershell
firebase emulators:start --only database --project demo-nearmitra
```

The included emulator configuration binds port **9000** to localhost and loads **development-only** rules. No cloud deploy command is needed. For a USB-connected phone:

```powershell
adb reverse tcp:9000 tcp:9000
```

Use a local JSON with these additional/replacement values (the remaining required keys still come from `config/firebase.example.json`):

```json
{
  "FIREBASE_PROJECT_ID": "demo-nearmitra",
  "FIREBASE_DATABASE_URL": "https://demo-nearmitra-default-rtdb.firebaseio.com",
  "FIREBASE_DATABASE_EMULATOR_HOST": "127.0.0.1",
  "FIREBASE_DATABASE_EMULATOR_PORT": "9000"
}
```

For emulator-only SDK initialization, replace the other required placeholders with nonempty dummy values, for example `FIREBASE_API_KEY: "demo-api-key"`, `FIREBASE_APP_ID: "1:1234567890:android:abcdef123456"`, `FIREBASE_MESSAGING_SENDER_ID: "1234567890"`. Remove any real native JSON when building an emulator-only app so it cannot auto-initialize a real project. Run a debug build using `flutter run --dart-define-from-file=config/firebase.local.json`. The debug-only Android manifest permits local HTTP emulator traffic; release builds retain their normal HTTPS policy.

For Windows, use the same emulator namespace:

```powershell
$env:NEARMITRA_FIREBASE_RTDB_URL = 'http://127.0.0.1:9000/?ns=demo-nearmitra-default-rtdb'
& '.\nearmitra-windows-app\build\windows-release\NearMitra.exe'
```

The Windows REST client appends each node path and `.json`, preserving the `ns` query. On a physical phone without USB port reversal, configure and secure your own reachable emulator host; `127.0.0.1` on the phone refers to the phone, not your PC.

## 5. Data paths and verification

Clients create their own records; there is no initial database import to copy from the maintainer.

| RTDB path | Purpose |
|---|---|
| `presence/{deviceId}` | Online status, device metadata and last-seen time |
| `public_presence/{deviceId}` | Public radar visibility |
| `trustedDevices/{deviceId}/{peerId}` | Paired peer relationships |
| `pairCodes/{code}` | Temporary pairing codes |
| `pairRequests/{deviceId}/{requestId}` | Pair request/acceptance records |
| `sessions/{sessionId}` | WebRTC offers/answers, status and ICE candidates |

The incoming session query filters on `receiverId`; add an RTDB `.indexOn` for `sessions/receiverId` when deploying your own rules. The included emulator rules demonstrate that index. Firebase carries WAN discovery/pairing/signaling; chat/file payloads use the negotiated WebRTC data channel.

Run both devices against your backend, enable Internet mode and verify presence and pairing records there. Use different networks or remove local reachability when specifically testing WAN: the app prefers Nearby LAN/P2P whenever available. Test disable/disconnect and heartbeat expiry as well as the online case. Do not point automated tests at any live maintainer database.

## Hosted database security limitation

An API key, a random device ID and an application-level paired-peer list do not establish authenticated database ownership. The current mobile SDK and Windows REST calls do not attach Firebase user ID tokens. Locked/authenticated rules will reject them; merely selecting your own URL does not make hosted WAN production-ready.

Before a public hosted deployment, add compatible Firebase Authentication/token refresh to both clients and enforce ownership and paired-peer authorization for presence, pairing and sessions. Validate payloads and restrict queries and cleanup privileges. Keep private Admin SDK/service-account keys out of clients, source commits and binaries. Do not deploy the permissive emulator rules to a hosted database.

## Already-public config and old releases

Removing files from a branch tip does not erase older commits, forks or downloaded APK/EXE files. Earlier releases and existing `%LOCALAPPDATA%\NearMitra\wan_config.json` can retain an old endpoint. Do not redistribute those builds as backend-isolated releases. Maintainers should review the previously exposed project's rules, access restrictions and credentials separately; source cleanup cannot revoke access to that cloud project.
