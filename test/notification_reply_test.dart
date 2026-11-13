import 'dart:async';
import 'dart:convert';

import 'package:farmitra_nearby/models/notification_target.dart';
import 'package:farmitra_nearby/providers/conversation_providers.dart';
import 'package:farmitra_nearby/services/history_service.dart';
import 'package:farmitra_nearby/services/notification_reply_pump.dart';
import 'package:farmitra_nearby/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notification_reply_bridge/notification_reply_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'conversation_routing_test.dart'
    show TestNearby, TestWan, TestRtc, local, remote, until;

class FakeReplyInbox implements NotificationReplyInbox {
  final items = <String, PendingNotificationReply>{};
  final acknowledged = <String>[];
  final events = StreamController<void>.broadcast();
  bool failAck = false;
  Future<void> Function(String)? beforeAck;
  @override
  Stream<void> get changes => events.stream;
  @override
  Future<void> registerNotification(int id, String nonce) async {}
  @override
  Future<void> save(
      {required String peerId,
      required String text,
      String? nonce,
      int? notificationId}) async {}
  @override
  Future<List<PendingNotificationReply>> pending() async =>
      items.values.toList();
  @override
  Future<void> acknowledge(String id) async {
    await beforeAck?.call(id);
    if (failAck) throw StateError('Simulated interrupted ack');
    acknowledged.add(id);
    items.remove(id);
  }
}

class FailingPreferences extends SharedPreferencesStorePlatform {
  FailingPreferences(this.delegate);
  final SharedPreferencesStorePlatform delegate;
  String? failKey;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      key == failKey ? false : delegate.setValue(valueType, key, value);
  @override
  Future<Map<String, Object>> getAll() => delegate.getAll();
  @override
  Future<bool> remove(String key) => delegate.remove(key);
  @override
  Future<bool> clear() => delegate.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestNearby nearby;
  late TestWan wan;
  late TestRtc rtc;
  late ConversationController controller;
  late NotificationReplyPump pump;
  late FakeReplyInbox inbox;
  late FailingPreferences preferences;
  final history = HistoryService();
  PendingNotificationReply reply(
          {String id = 'notification-reply-1',
          String peer = 'peer-a',
          String text = 'हाँ, ठीक है 👍'}) =>
      PendingNotificationReply(
          id: id,
          peerId: peer,
          text: text,
          createdAt: DateTime(2026, 11, 13, 12));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = FailingPreferences(SharedPreferencesStorePlatform.instance);
    SharedPreferencesStorePlatform.instance = preferences;
    nearby = TestNearby();
    wan = TestWan();
    rtc = TestRtc();
    inbox = FakeReplyInbox();
    controller = ConversationController(nearby, wan, rtc);
    await controller.ready;
    pump = NotificationReplyPump(inbox, controller,
        retryInterval: const Duration(days: 1));
  });
  tearDown(() async {
    pump.dispose();
    controller.dispose();
    nearby.dispose();
    wan.dispose();
    rtc.dispose();
    await inbox.events.close();
    SharedPreferencesStorePlatform.instance = preferences.delegate;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidNotificationReplyInbox.channel, null);
  });

  test(
      'Offline reply is durably queued before native ack and keeps its recipient',
      () async {
    final item = reply();
    inbox.items[item.id] = item;
    inbox.beforeAck = (_) async {
      final queue = (await SharedPreferences.getInstance())
          .getStringList('unified_chat_outbox_v1')!;
      expect((jsonDecode(queue.single) as Map)['id'], item.id);
      expect((await history.load()).single.peerId, 'peer-a');
    };
    await pump.start();
    expect(inbox.acknowledged, [item.id]);
    expect(nearby.sent, isEmpty);
    expect((await history.load()).single.status, 'Queued');
  });

  test(
      'Offline reply survives controller restart and sends when that peer returns',
      () async {
    final item = reply();
    inbox.items[item.id] = item;
    await pump.start();
    pump.dispose();
    controller.dispose();
    controller = ConversationController(nearby, wan, rtc);
    await controller.ready;
    pump = NotificationReplyPump(inbox, controller);
    nearby.devices.add(local(id: 'peer-a', wanId: null));
    nearby.update();
    await until(() => nearby.sent.contains(item.id));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(nearby.sent, [item.id]);
    expect((await history.load()).single.status, 'Sent');
  });

  test('Interrupted native ack reimports the same reply without a second send',
      () async {
    final item = reply();
    inbox.items[item.id] = item;
    inbox.failAck = true;
    nearby.devices.add(local(id: 'peer-a', wanId: null));
    await pump.start();
    await until(() => nearby.sent.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    inbox.failAck = false;
    await pump.drain();
    expect(nearby.sent, [item.id]);
    expect(inbox.acknowledged, [item.id]);
    expect(await history.load(), hasLength(1));
  });

  test('Concurrent drains and import calls preserve one message', () async {
    final item = reply();
    inbox.items[item.id] = item;
    await Future.wait(
        [pump.drain(), pump.drain(), controller.importNotificationReply(item)]);
    expect(await history.load(), hasLength(1));
    expect(
        (await SharedPreferences.getInstance())
            .getStringList('unified_chat_outbox_v1'),
        hasLength(1));
  });

  for (final key in [
    'flutter.unified_chat_outbox_v1',
    'flutter.farmitra_nearby_chat_history_v1'
  ]) {
    test('A failed durable write retains the native reply for retry ($key)',
        () async {
      final item = reply();
      inbox.items[item.id] = item;
      preferences.failKey = key;
      await pump.start();
      expect(inbox.acknowledged, isEmpty);
      expect(inbox.items, contains(item.id));
      expect(nearby.sent, isEmpty);
      preferences.failKey = null;
      await pump.drain();
      expect(inbox.acknowledged, [item.id]);
      expect((await history.load()).single.id, item.id);
    });
  }

  test(
      'Concurrent ordinary chat and notification reply cannot overwrite the queue',
      () async {
    await Future.wait([
      controller.importNotificationReply(reply()),
      controller.sendText(
          local(id: 'peer-b', wanId: null), 'Other conversation')
    ]);
    expect(
        (await SharedPreferences.getInstance())
            .getStringList('unified_chat_outbox_v1'),
        hasLength(2));
    expect((await history.load()).map((e) => e.peerId).toSet(),
        {'peer-a', 'peer-b'});
  });

  test('WAN-prefixed reply uses enabled trusted WAN and the same message ID',
      () async {
    wan.enabled = true;
    wan.devices.add(remote());
    final item = reply(peer: 'wan:wan-phone');
    inbox.items[item.id] = item;
    await pump.start();
    await until(() => rtc.sent.isNotEmpty);
    expect(rtc.sent, [item.id]);
    expect((await history.load()).single.peerId, 'wan-phone');
  });

  test('Cancelled reply cannot be resurrected by a repeated callback',
      () async {
    final item = reply();
    inbox.items[item.id] = item;
    inbox.failAck = true;
    await pump.start();
    await controller.cancel(item.id);
    inbox.failAck = false;
    await pump.drain();
    expect((await history.load()).single.status, 'Cancelled');
    expect(
        (await SharedPreferences.getInstance())
            .getStringList('unified_chat_outbox_v1'),
        isEmpty);
  });

  test(
      'Background callback saves through native bridge without a HomeScreen listener',
      () async {
    final saved = Completer<MethodCall>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidNotificationReplyInbox.channel,
            (call) async {
      if (!saved.isCompleted) saved.complete(call);
      return null;
    });
    notificationTapBackground(NotificationResponse(
        id: 42,
        actionId: 'reply_action',
        input: '  Reply from lock screen  ',
        payload: const NotificationTarget('peer-a', nonce: 'nonce-1').encode(),
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction));
    final call = await saved.future;
    expect(call.method, 'save');
    expect((call.arguments as Map)['peerId'], 'peer-a');
    expect((call.arguments as Map)['text'], 'Reply from lock screen');
    expect((call.arguments as Map)['nonce'], 'nonce-1');
  });

  test(
      'New and legacy notification payloads keep click and reply routing intact',
      () {
    final original =
        const NotificationTarget('wan:remote', nonce: 'unique-message');
    final parsed = NotificationTarget.decode(original.encode());
    expect(parsed.peerId, 'wan:remote');
    expect(parsed.nonce, 'unique-message');
    expect(NotificationTarget.decode('legacy-lan-id').peerId, 'legacy-lan-id');
  });
}
