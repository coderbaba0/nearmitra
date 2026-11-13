# Android background delivery

Current source uses one application-context Flutter engine shared by
`MainActivity` and `FarmitraForegroundService`. Removing the Activity from
Recents releases its ownership; the foreground service retains that engine.
Reopening reuses the engine and its existing sockets, conversation queue and
Internet listeners. If Android restarts the sticky service in a fresh process,
the engine starts with `--background`; networking starts independently of
HomeScreen or a rendered widget frame.

Background startup does not request camera, microphone or notification
permissions. Existing permissions are used. The foreground UI requests
notification permission. An explicit **Run in Background OFF** prevents a sticky
restart from bringing networking back. Media capture still requires its existing
permission and foreground-service flow.

Flutter documents externally owned engines and continued Dart execution after
Activity destruction in its [Android embedding guide](https://docs.flutter.dev/add-to-app/android/add-flutter-screen).

## Checks before distributing an updated APK

Automated tests cover engine ownership/reuse/release, startup without a widget,
detached notification state, background history, trusted WAN acceptance,
notification initialization without an Activity, and native call/share dispatch.
These checks do not substitute for the following device tests.

1. Use two phones (and separately a Windows peer), grant notification permission,
   enable Run in Background and establish a reachable Nearby connection.
2. Open the peer chat, swipe NearMitra away from Recents, then send a text and
   file from the other device. Check notification delivery before reopening.
3. Reopen through the notification. Verify saved history, unread state and one
   active connection; repeat swipe/reopen several times.
4. Call the removed-task phone. Check native ringing, Accept, two-way audio/video,
   Decline, and an ordinary call again after reopening.
5. Repeat with the screen locked, then with enabled/trusted Internet mode. Verify
   saved Internet OFF remains OFF and does not auto-accept a WAN session.
6. Toggle Run in Background OFF; remove the task and verify the service does not
   restart. Toggle it ON and repeat delivery. Also check casting/Wi-Fi Audio
   start/stop and Wi-Fi Direct after an Activity recreation.
7. Test an OS service/process restart separately from a Recents swipe. Android
   Settings **Force stop**, user-stopped services and manufacturer battery
   restrictions can prevent background execution; sticky service ownership
   does not override those controls.

The previously released APK does not acquire these changes until rebuilt and
installed. Samsung screen-off and swipe-away delivery checks are recorded in
[the device verification report](background-verification.md), including the
tested builds, network-loss finding and remaining coverage limits.
