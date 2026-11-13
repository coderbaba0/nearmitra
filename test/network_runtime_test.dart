import 'package:farmitra_nearby/models/chat_item.dart';
import 'package:farmitra_nearby/models/wan_models.dart';
import 'package:farmitra_nearby/providers/conversation_providers.dart';
import 'package:farmitra_nearby/services/call_service.dart';
import 'package:farmitra_nearby/services/history_service.dart';
import 'package:farmitra_nearby/services/network_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notification_reply_bridge/notification_reply_bridge.dart';
import 'notification_reply_test.dart' show FakeReplyInbox;

import 'conversation_routing_test.dart'
    show TestNearby, TestRtc, TestWan, remote;

class RuntimeNearby extends TestNearby {
  bool _foreground = true;
  @override
  bool get isAppInForeground => _foreground;
  @override
  set isAppInForeground(bool value) => _foreground = value;
  int starts = 0;
  int stops = 0;
  final incoming = <ChatItem>[];
  @override
  Future<void> start() async {
    starts++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  List<ChatItem> takeIncomingItems() {
    final items = List<ChatItem>.of(incoming);
    incoming.clear();
    return items;
  }
}

class RuntimeWan extends TestWan {
  bool _foreground = true;
  @override
  bool get isAppInForeground => _foreground;
  @override
  set isAppInForeground(bool value) => _foreground = value;
  final rejected = <String>[];
  @override
  bool isDeviceTrusted(String id) =>
      devices.any((d) => d.id == id && d.isTrusted);
  @override
  Future<void> rejectSignalingSession(String id) async {
    rejected.add(id);
  }
}

class RuntimeRtc extends TestRtc {
  int initialized = 0;
  final accepted = <String>[];
  Function(WanSignalingSession session)? _incoming;
  @override
  Function(WanSignalingSession session)? get onIncomingSessionRequest =>
      _incoming;
  @override
  set onIncomingSessionRequest(Function(WanSignalingSession session)? value) =>
      _incoming = value;
  @override
  void init() {
    initialized++;
  }

  @override
  Future<void> acceptIncomingSession(WanSignalingSession session) async {
    accepted.add(session.sessionId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RuntimeNearby nearby;
  late RuntimeWan wan;
  late RuntimeRtc rtc;
  late ConversationController conversations;
  late NetworkRuntime runtime;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    nearby = RuntimeNearby();
    wan = RuntimeWan();
    rtc = RuntimeRtc();
    conversations = ConversationController(nearby, wan, rtc);
    runtime = NetworkRuntime(
        nearby: nearby,
        wan: wan,
        rtc: rtc,
        conversations: conversations,
        foreground: false);
    await conversations.ready;
  });

  tearDown(() {
    runtime.dispose();
    conversations.dispose();
    nearby.dispose();
    wan.dispose();
    rtc.dispose();
    CallService().isAppInForeground = false;
  });

  test('Service startup starts networking and one queue without any widget',
      () async {
    await Future.wait([runtime.start(), runtime.start()]);
    expect(nearby.starts, 1);
    expect(rtc.initialized, 1);
    expect(nearby.useUnifiedOutbox, isTrue);
    expect(rtc.useUnifiedOutbox, isTrue);
    expect(nearby.isAppInForeground, isFalse);
    expect(CallService().isAppInForeground, isFalse);
  });

  test('Detach enables background notifications without stopping networking',
      () async {
    await runtime.start();
    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(nearby.isAppInForeground, isTrue);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached
    ]) {
      runtime.didChangeAppLifecycleState(state);
      expect(nearby.isAppInForeground, isFalse);
      expect(wan.isAppInForeground, isFalse);
      expect(CallService().isAppInForeground, isFalse);
    }
    expect(nearby.stops, 0);
    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(nearby.isAppInForeground, isTrue);
    expect(nearby.starts, 1);
  });

  test('Headless receive persists history and drains pending UI items',
      () async {
    nearby.incoming.add(ChatItem(
        id: 'background-message',
        peerId: 'other-phone',
        sender: 'Other Phone',
        mine: false,
        createdAt: DateTime.now(),
        kind: ChatKind.text,
        text: 'Received without opening Home'));
    nearby.update();
    expect(nearby.incoming, isEmpty);
    expect((await HistoryService().load()).single.text,
        'Received without opening Home');
  });

  test('Service startup imports a saved notification reply without HomeScreen',
      () async {
    runtime.dispose();
    final inbox = FakeReplyInbox();
    inbox.items['notification-reply-headless'] = PendingNotificationReply(
        id: 'notification-reply-headless',
        peerId: 'offline-peer',
        text: 'Saved from the lock screen',
        createdAt: DateTime.now());
    runtime = NetworkRuntime(
        nearby: nearby,
        wan: wan,
        rtc: rtc,
        conversations: conversations,
        foreground: false,
        replyInbox: inbox);
    try {
      await runtime.start();
      expect(inbox.acknowledged, ['notification-reply-headless']);
      final saved = (await HistoryService().load()).single;
      expect(saved.text, 'Saved from the lock screen');
      expect(saved.status, 'Queued');
      expect(saved.peerId, 'offline-peer');
      expect(nearby.starts, 1);
    } finally {
      runtime.dispose();
      await inbox.events.close();
    }
  });

  test('Headless WAN accepts trusted peers and rejects unknown peers',
      () async {
    wan.enabled = true;
    wan.devices.add(remote());
    WanSignalingSession session(String caller) => WanSignalingSession(
          sessionId: 'session-$caller',
          callerId: caller,
          receiverId: 'me',
          callerName: 'Other Phone',
          callerPlatform: 'android',
          status: 'pending',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
    await rtc.onIncomingSessionRequest!(session('wan-phone'));
    expect(rtc.accepted, ['session-wan-phone']);
    await rtc.onIncomingSessionRequest!(session('unknown'));
    expect(wan.rejected, ['session-unknown']);
    wan.enabled = false;
    await rtc.onIncomingSessionRequest!(session('wan-phone'));
    expect(wan.rejected, contains('session-wan-phone'));
  });
}
