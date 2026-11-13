import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:notification_reply_bridge/notification_reply_bridge.dart';

import '../providers/conversation_providers.dart';
import 'call_service.dart';
import 'history_service.dart';
import 'nearby_service.dart';
import 'notification_reply_pump.dart';
import 'wan_service.dart';
import 'wan_webrtc_manager.dart';

/// Engine-owned networking. Starting or retaining it never requires HomeScreen
/// to build, so a sticky service restart can receive messages without a view.
class NetworkRuntime with WidgetsBindingObserver {
  NetworkRuntime({
    required this.nearby,
    required this.wan,
    required this.rtc,
    required this.conversations,
    required bool foreground,
    NotificationReplyInbox? replyInbox,
  }) {
    final inbox = replyInbox ??
        (Platform.isAndroid ? AndroidNotificationReplyInbox() : null);
    if (inbox != null) _replies = NotificationReplyPump(inbox, conversations);
    _setForeground(foreground);
    WidgetsBinding.instance.addObserver(this);
    nearby.addListener(_saveBackgroundItems);
    rtc.init();
    rtc.onIncomingSessionRequest = (session) async {
      if (wan.isInternetModeEnabled && wan.isDeviceTrusted(session.callerId)) {
        await rtc.acceptIncomingSession(session);
      } else {
        await wan.rejectSignalingSession(session.sessionId);
      }
    };
  }

  factory NetworkRuntime.forService(NearbyService nearby,
      {required bool foreground}) {
    final wan = WanService();
    final rtc = WanWebRtcManager();
    return NetworkRuntime(
      nearby: nearby,
      wan: wan,
      rtc: rtc,
      conversations: ConversationController(nearby, wan, rtc),
      foreground: foreground,
    );
  }

  final NearbyService nearby;
  final WanService wan;
  final WanWebRtcManager rtc;
  final ConversationController conversations;
  Future<void>? _starting;
  NotificationReplyPump? _replies;

  Future<void> start() =>
      _starting ??= _start().whenComplete(() => _starting = null);

  Future<void> _start() async {
    await conversations.ready;
    await nearby.start();
    await _replies?.start();
  }

  void _setForeground(bool foreground) {
    nearby.isAppInForeground = foreground;
    wan.isAppInForeground = foreground;
    CallService().isAppInForeground = foreground;
  }

  void _saveBackgroundItems() {
    if (nearby.isAppInForeground) return;
    // With no view attached nobody drains HomeScreen's incoming UI queue.
    // Persist every kind of item and release those references in the runtime.
    final items = nearby.takeIncomingItems();
    if (items.isNotEmpty) {
      unawaited(HistoryService().addItems(items).catchError((Object error) {
        debugPrint('[Runtime] Background history write failed: $error');
      }));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // In particular, detached after a Recents swipe must never suppress the
    // incoming message/call notification just because a chat was open before.
    _setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) unawaited(_replies?.drain());
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    nearby.removeListener(_saveBackgroundItems);
    _replies?.dispose();
  }
}
