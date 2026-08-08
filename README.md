# Farmitra Nearby — Flutter Android

Android client compatible with the existing **Farmitra Nearby Windows v5.3** local-network protocol.

## What works

- Windows ↔ Android device discovery on the same Wi-Fi/LAN
- Android ↔ Android discovery
- UDP multicast discovery: `239.255.43.88:43888`
- TCP hello/chat/file protocol: `43889`
- Active `/24` LAN scan fallback for networks that filter multicast
- Direct text chat (no cloud/server)
- File picker and direct file send
- Incoming file receive to the app-specific external `Farmitra Nearby` folder
- Chat attachment cards and persistent local chat history
- Live transfer percentage, speed and ETA
- Responsive Material 3 UI for phone/tablet
- Light/dark system theme
- Real-time activity log
- Android Wi-Fi multicast lock for more reliable peer discovery

## Windows compatibility

The Flutter app intentionally uses the same wire headers as Windows v5.3:

```json
{"type":"hello","sender":"Pixel 9","sender_id":"device-id"}
{"type":"chat","sender":"Pixel 9","sender_id":"device-id","message":"Hello"}
{"type":"file","sender":"Pixel 9","sender_id":"device-id","name":"report.pdf","size":12345}
```

Headers are UTF-8 JSON followed by `\n`. File bytes immediately follow the file header.

## Build APK

Install Flutter stable and Android Studio/Android SDK, then from this project folder:

```bash
flutter pub get
flutter build apk --release
```

APK output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

For quick USB install:

```bash
flutter install
```

## Testing Windows ↔ Android

1. Run Farmitra Nearby v5.3 on Windows.
2. Open this Flutter app on Android.
3. Put both devices on the same Wi-Fi/router.
4. Allow Windows Firewall access on Private networks.
5. Tap the refresh icon / **Scan network** on Android if discovery does not appear immediately.
6. Select the Windows PC and send chat or a file.

## Notes

- The current Android build is designed for foreground use. Android background receive/foreground-service support can be added later.
- Windows folders arrive as `.zip` files on Android in this first Android build. Regular files are fully compatible.
- Release signing should be configured before Play Store/public distribution. The included Gradle release configuration uses debug signing only for easy local testing.
