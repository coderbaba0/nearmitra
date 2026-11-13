import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notification_reply_bridge/notification_reply_bridge.dart';

import '../providers/conversation_providers.dart';

/// Only the networking engine imports replies into the unified outbox. The
/// notification callback engine just saves to the native inbox and wakes it.
class NotificationReplyPump {
  NotificationReplyPump(this.inbox, this.conversations,
      {this.retryInterval = const Duration(seconds: 10)});

  final NotificationReplyInbox inbox;
  final ConversationController conversations;
  final Duration retryInterval;
  StreamSubscription<void>? _subscription;
  Timer? _retry;
  Future<void>? _draining;
  bool _requested = false, _disposed = false, _started = false;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _subscription = inbox.changes.listen((_) => unawaited(drain()),
        onError: (Object error) =>
            debugPrint('[Reply] Inbox event error: $error'));
    _retry = Timer.periodic(retryInterval, (_) => unawaited(drain()));
    await drain();
  }

  Future<void> drain() {
    if (_disposed) return Future<void>.value();
    _requested = true;
    return _draining ??= _drain().whenComplete(() => _draining = null);
  }

  Future<void> _drain() async {
    try {
      while (_requested && !_disposed) {
        _requested = false;
        final replies = await inbox.pending();
        for (final reply in replies) {
          if (_disposed) return;
          await conversations.importNotificationReply(reply);
          // Ack only after outbox and history are durably saved. A crash before
          // this point reimports the same message ID rather than creating a send.
          await inbox.acknowledge(reply.id);
        }
        if (replies.length >= 100) _requested = true;
      }
    } catch (error) {
      debugPrint('[Reply] Saved reply will retry: $error');
    }
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    unawaited(_subscription?.cancel());
  }
}
