# Background notification Reply (unreleased source)

Inline replies use a native SQLite inbox shared by the notification callback
engine and the retained networking engine. They do not depend on HomeScreen,
an in-memory Dart stream or an isolate's cached preferences.

1. Each displayed chat notification carries its recipient and a fresh nonce.
2. Reply invokes the declared Android ActionBroadcastReceiver and background
   callback. The app-local Flutter plugin is registered in that engine too.
3. The plugin commits the reply to SQLite before dismissing its notification.
   It checks the notification nonce, so an older reply cannot cancel a newer
   incoming notification for the same conversation. A failed save leaves the
   original notification available.
4. Native events wake an existing runtime, and a user-triggered service start
   can bootstrap the networking engine without opening the UI. Startup/resume
   and a retry timer also drain pending replies if an event was missed.
5. The runtime imports the original message ID into the existing durable outbox
   and history before acknowledging the native inbox. Unknown/offline recipients
   remain queued. Nearby is preferred; Internet OFF and WAN trust still apply.

New notification callbacks have deterministic reply IDs. Repeated imports reuse
the outbox/history entry; native receipt IDs remain after handoff so later
callback replay does not create another send. Identical replies to a *new*
notification remain allowed. Notifications created by earlier APKs keep their
plain recipient payload compatibility. Imported native reply bodies are erased;
the common chat history/outbox own the message from then on.

With **Run in Background OFF**, an explicit Reply can start a temporary service
for up to two minutes; it does not change the saved preference. An existing
call/cast/audio foreground service is left in its current mode. If Android
blocks a background start, the saved reply remains for the next available
runtime; delivery is not claimed merely because the notification was dismissed.
Network retries retain the message ID; this is not an exactly-once guarantee
across every possible transport/receiver failure.

The local plugin performs SQLite work on a worker thread. Only the networking
engine modifies the unified outbox, whose writes are serialized. Storage errors
prevent inbox acknowledgement and are retried instead of discarding the reply.

## Device checks before release

- Reply from a locked phone and from a task removed from Recents, without opening
  HomeScreen. Verify the recipient, outgoing history and actual delivery.
- Turn the recipient offline, reply, restart the sending app and reconnect the
  recipient. Verify one queued message is sent with the original ID.
- Reply while another conversation is open and while a file/call/audio stream
  is active. Check that routing and active media are preserved.
- Send a newer incoming notification while replying to an older one. Verify the
  new notification remains visible.
- Check Background OFF: a reply gets a temporary sending session and the service
  ends afterward; OFF stays saved. Check both Nearby and enabled/trusted WAN.
- Check denied notification permission, unavailable storage, network loss,
  notification taps and repeated identical replies to different notifications.

Automated tests and Android compilation do not establish physical-device
lock-screen or manufacturer-specific background behavior. Samsung notification
Reply checks are recorded in [the device verification report](background-verification.md).
Notification action setup follows the
[notifications plugin's documented Android requirements](https://pub.dev/packages/flutter_local_notifications/versions/17.2.4#notification-actions).
