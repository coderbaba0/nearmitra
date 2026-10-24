# Contributing to NearMitra

Contributions to the Android app and Windows desktop app are welcome: bug reports, documentation, tests, accessibility improvements and focused fixes all help. Read the [project README](README.md) and [Windows README](nearmitra-windows-app/README.md) for current behavior and known limitations.

## Before starting

Check the repository's [issues](https://github.com/coderbaba0/nearmitra/issues) and [pull requests](https://github.com/coderbaba0/nearmitra/pulls) for related work. For a large feature, protocol change or dependency replacement, open an issue describing the problem and proposed approach before implementing it. Small fixes and documentation corrections can go straight to a pull request.

Keep discussions respectful and focused on the work. Share enough context for someone with a different device or operating system to reproduce the result.

## Repository layout

| Path | Purpose |
|---|---|
| `lib/` | Flutter app, UI, local networking, WAN services and conversation routing |
| `android/app/src/main/kotlin/com/farmitra/nearby/` | Android platform channels, foreground service, notifications and device integrations |
| `test/` | Flutter unit, widget and protocol regression tests |
| `nearmitra-windows-app/internal/` | Windows Go backend and native integrations |
| `nearmitra-windows-app/internal/ui/web/` | Embedded desktop HTML/CSS/JavaScript and JavaScript tests |
| `nearmitra-windows-app/installer/` | Windows installer and installer tests |
| `nearmitra-windows-app/IOT_SETUP.md` | Feature details, hardware contracts and release validation notes |

## Fork and create a branch

Fork the repository on GitHub, then work from the current `develop` branch:

```bash
git clone https://github.com/YOUR_USERNAME/nearmitra.git
cd nearmitra
git remote add upstream https://github.com/coderbaba0/nearmitra.git
git fetch upstream
git switch -c fix/describe-the-change upstream/develop
```

Use a short branch name such as `fix/background-notifications`, `feat/device-search` or `docs/android-setup`. Keep each pull request focused on one problem.

## Android and Flutter setup

Install Flutter compatible with `pubspec.yaml`, Android SDK/build tools matching the Gradle configuration, and JDK 17. Set your local Flutter/SDK paths using Flutter tooling or `android/local.properties`; do not commit machine-specific paths. The current APK has minimum API 24 and target/compile SDK 36.

From the repository root:

```bash
flutter pub get
flutter devices
flutter run -d YOUR_DEVICE_ID
```

Nearby LAN development should work independently of WAN. For Firebase/WAN, follow [Bring your own Firebase](docs/FIREBASE_SETUP.md): download your own Android `google-services.json`, supply the ignored Dart configuration, and point Windows at your own Realtime Database. For cloud AI work, configure your own provider credentials. Do not use the maintainer's live Firebase project for automated tests, pairing experiments or database cleanup. Keep your local Firebase configuration changes out of the pull request unless the change explicitly concerns configuration.

Useful checks:

```bash
flutter test
flutter analyze
flutter build apk --release
```

Format changed Dart files with `dart format path/to/changed_file.dart`. If analysis reports pre-existing findings, state them in the pull request and avoid introducing new findings in the changed files. The Android release configuration currently uses a debug signing key; release builds are for local validation, not proof of store-ready signing.

## Windows setup

Use Windows 10/11 x64, Go 1.23 or newer, and Node.js with `node --test` support. Run these commands from `nearmitra-windows-app` in a Windows terminal:

```bat
build-installer.bat
go test ./...
node --test --test-reporter=dot internal/ui/web/*.test.cjs installer/web/app.test.cjs
```

Build before testing a fresh checkout: the installer embeds the generated `installer/NearMitra.exe`. Installer tests compare that payload with `build/windows-release/NearMitra.exe`. Linux-only Go checks do not cover the native Windows implementation. Apply `gofmt` to changed Go files. See the [Windows build instructions](nearmitra-windows-app/README.md#build-from-source) and [signing guide](nearmitra-windows-app/WINDOWS_SIGNING.md) for more details.

## Implementation expectations

- Preserve the connection order: available Nearby LAN/P2P first, enabled and trusted WAN as fallback. Keep device identity and conversation history consistent across routes.
- Keep networking and presence independent of the visible discovery tab. Distinguish foreground, minimized, Recent-apps swipe-away and force-stop behavior; they are different lifecycle cases.
- Preserve wire compatibility between Android and Windows. Explain new fields and fallback behavior, and test both sender and receiver when a protocol changes.
- Respect owner approval and per-device grants for shared AI, sensors and media. Propagate failures instead of reporting success before delivery or storage completes.
- Add a regression test for a behavioral bug where practical. Avoid unrelated refactors, mass formatting, dependency upgrades or generated file changes.
- Update the relevant README or feature notes when user-visible behavior changes. Do not claim a known issue is fixed based only on mocks or a successful build.

Run checks relevant to your change. Documentation-only edits need link/path and Markdown checks rather than application builds. For shared protocol changes, run both the mobile and desktop suites. Explain any checks you could not run.

## Device verification

For networking, notification, media or lifecycle changes, record the actual device/OS and the steps tested. Include the connection mode, sender/receiver direction, firewall or permission conditions, and whether the app was open, minimized, screen-locked or removed from Recent apps. Verify recovery after a network interruption and check for duplicate messages or notifications.

The Android Recent-apps swipe-away notification issue is currently unresolved. A foreground-service notification alone does not prove that the message listener is running. Keep that limitation visible until a reproducible device test demonstrates the fix.

## Reporting a bug

Open an issue with:

- App version/build and device model, Android/Windows version.
- Nearby, Wi-Fi Direct/P2P or WAN mode, plus which device sends and receives.
- Exact steps, expected behavior and observed result.
- Relevant settings, especially Run in Background, Internet mode and notification permission.
- Redacted logs, screenshots or a short recording when useful.

Remove message contents, personal filenames, device identifiers, access tokens and other private information from reports. For a suspected security vulnerability, use GitHub's private vulnerability reporting option if available; do not publish exploit details or credentials in a public issue. If no private channel is listed, ask the maintainer for one without disclosing the vulnerability publicly.

## Submitting a pull request

```bash
git add path/to/changed_file
git commit -m "fix(android): describe the resulting behavior"
git push -u origin fix/describe-the-change
```

Open the pull request against **`develop`**. Describe the problem, resulting behavior, related issue, tests run and remaining limitations. Include screenshots for UI changes and device evidence for background/media behavior. Explain cross-platform compatibility when relevant.

Do not include APKs, EXEs, build/cache folders, logs, private chat history, received files, API credentials, signing keystores or machine-specific settings. Review `git diff --cached` before committing. Commit lockfile changes only when needed for an intentional dependency change. Release version bumps, build hashes and published artifacts should be coordinated with the maintainer.

Respond to review comments and update the same branch. Passing tests help review but do not automatically guarantee a merge.

## Contribution license

By submitting a contribution for inclusion in NearMitra, you agree that your contribution may be distributed under the project's **GPL-3.0-only** license. See [LICENSE](LICENSE). Submit only work you have the right to contribute, preserve existing copyright and license notices, and identify any third-party code and its license in your pull request.

## Firebase / Internet contributions

Read [docs/FIREBASE_SETUP.md](docs/FIREBASE_SETUP.md) before testing WAN. The checked-in examples contain placeholders only. `google-services.json`, generated FlutterFire project config and `config/firebase.local.json` are ignored; the tracked `lib/firebase_options.dart` is a build-time configuration loader and must stay free of live project values. Normal Android builds can use the ignored native JSON directly, including `project_info.firebase_url`. Native Windows uses an owner-supplied RTDB REST URL, not Android Google Services configuration; its optional `internal/wan/firebase_config.local.go` is ignored and included automatically in local Go builds. Keep local config files when publishing source.

Use the local emulator for the existing unauthenticated protocol. Hosted deployment requires implementing compatible authentication and rules on both clients; application pairing alone is not database authorization. Never test against the maintainer's database or include credentials, real project IDs or runtime config in a pull request. Check both clean-checkout Nearby operation and your explicitly configured WAN setup.
