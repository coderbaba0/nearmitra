# Android background device verification

Date: 2026-11-13. Device: Samsung SM-M045F, Android 14, reachable over wireless
ADB on the same Wi-Fi as the existing NearMitra Windows peer.

Initially installed and tested the release APK (`1.0.3`, version code `4`), without clearing
application data. Android package flags confirmed a non-debuggable installation.
APK SHA-256:
`fa1725c1dcd9db67d3fc2d945043869917dc5b9358e0f9769f3d4c1f7797be1e`.

Run in Background was already ON. Android notification permission was granted,
but the app's Local Notifications setting was OFF. Local Notifications was
temporarily enabled for these checks.

| Scenario | Observed result |
| --- | --- |
| Screen off / secure keyguard showing | Incoming text and 256 KiB file received; Android held both chat and file notifications. Received file SHA-256 matched the sender. |
| Reply to the screen-off message | After the owner authenticated at the secure lock screen, the native notification Reply sent successfully without opening NearMitra. Windows history contained one matching reply and its stable reply ID. This is not a claim that the secure lock was bypassed or that unauthenticated replies are enabled. |
| Swipe the active peer-chat task out of Recents | Android reported no active NearMitra Activity. The existing process and foreground service remained alive. Text and a second 256 KiB file arrived; the second file's SHA-256 matched. An older installation's empty Recents card (`Activities=[]`) was separately observed. |
| Reply with no NearMitra Activity | Native notification Reply reached Windows exactly once in the observed history; no NearMitra Activity was started. |
| Wi-Fi disconnect / reconnect | The initial release received text and a third 256 KiB file after reconnect; its hash matched. Log inspection found the UDP error described below. On the fixed release, the owner repeated an 8–10 second Wi-Fi OFF/ON cycle without opening NearMitra. The same process/foreground service survived; new text, file and native notification Reply succeeded. The new file hash matched and the recipient recorded one matching reply. |

Verified incoming file hashes:

- Screen off: `0df0f52c879c921eb678a25d36d98499f3ac3132aebfed2cdb81f54bf560204c`.
- Task removed: `18b08c86e0f0ca25ba26b2e86652a8dce3d2ebcc6b0fe90f30a36b0b99c53599`.
- Original release after reconnect: `184a56145151bf871766bd3c118f473e5cc80b360429f213dd490f52edfcabd0`.
- Fixed release after reconnect: `040d0be812e82f99e4c3d65685acd45d83dad6d7693e8e8fb4405a2d9502d5e6`.

The first automated Wi-Fi helper terminated after disabling Wi-Fi; its log did
not reach the planned offline Reply submission. The owner restored Wi-Fi and
wireless debugging. Therefore, this session does not establish offline Reply
queueing on a physical device. The direct TCP outage monitor is also not valid
evidence: its sandboxed socket probes returned `EACCES` even when the phone was
reachable through the running Windows peer. Final Wi-Fi verification used the
owner's manual toggle and actual app transfers, file hashes and process logs.

## Finding and fix

The original release kept receiving after reconnect, but its process log held
two unhandled `SocketException: Network is unreachable` errors from UDP discovery
announcements. A `try/catch` around `send()` did not handle errors delivered
later on the datagram stream. The discovery listener now handles stream errors
and closure, releases the failed socket and lets the next heartbeat rebind.
A delayed callback checks socket identity before changing the active socket.

Both added regression tests failed before the fix: the asynchronous error
escaped and a closed socket was reused. Both pass after the fix; simulated
discovery packets are processed after rebinding. The final analyzer is clean.
All three split release APKs were rebuilt, and ARM64 version code `2004` was
installed without clearing app data. Its APK SHA-256 is
`6bfb17967b5d645630122dd23c730d86a5186d0028a5c00c50b0f1dc544e80fc`.
Background notification Reply on that updated build and after the owner's
physical Wi-Fi retest was received once per test in Windows history. Process
`25444` remained alive throughout that retest. Its final log contained zero
Flutter/AndroidRuntime error, unhandled-exception or MissingPluginException
matches; its crash buffer had no entries. These are observations for the tested
interval, not a guarantee about every crash scenario.

Focused Flutter regression tests: **28 passed**, covering discovery recovery,
background startup, durable notification replies, runtime ownership, foreground presence, UI
attachment and native event dispatch. Captures, generated fixtures, receiver
results and test output are under ignored `build/background-verification/`.
`tool/background_delivery_check.mjs` sends labelled fixtures through the running
Windows peer's local API and inspects only the generated replies.

Scope: short device checks on this Samsung and a Windows Nearby peer. Long idle
Doze, Android Settings Force stop, OS process restart, other manufacturers and
trusted Internet/WAN delivery were not exercised in this session. Screen-lock
and Recents cases ran on the initial release; background Reply and physical
Wi-Fi recovery were repeated on the fixed release.

After testing, the original **Local Notifications OFF** preference was restored
and verified in the UI; **Run in Background stayed ON**. Message/file alerts
require Local Notifications ON. Labelled test messages/files remain available
for inspection.
