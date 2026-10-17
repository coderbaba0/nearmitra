import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:farmitra_nearby/models/chat_item.dart';
import 'package:farmitra_nearby/models/chat_route.dart';
import 'package:farmitra_nearby/models/peer.dart';
import 'package:farmitra_nearby/models/wan_models.dart';
import 'package:farmitra_nearby/providers/conversation_providers.dart';
import 'package:farmitra_nearby/services/history_service.dart';
import 'package:farmitra_nearby/services/nearby_service.dart';
import 'package:farmitra_nearby/services/wan_service.dart';
import 'package:farmitra_nearby/services/wan_webrtc_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestNearby extends ChangeNotifier implements NearbyService {
  final devices = <Peer>[];
  final sent = <String>[];
  bool sendSucceeds = true;
  @override
  bool useUnifiedOutbox = false;
  @override
  String get deviceName => 'My Phone';
  @override
  List<Peer> get peers => devices;
  @override
  Future<bool> sendChat(Peer peer, String text,
      {String? msgId,
      String? replyToId,
      String? replyToSender,
      String? replyToText,
      bool isForwarded = false}) async {
    sent.add(msgId!);
    return sendSucceeds;
  }

  @override
  Future<bool> sendFile(Peer peer, File file,
      {bool folderArchive = false, String? displayName, String? msgId}) async {
    sent.add(file.path);
    return sendSucceeds;
  }

  @override
  Future<bool> cancelQueuedItem(String id) async => false;
  void update() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestWan extends ChangeNotifier implements WanService {
  final devices = <WanDevice>[];
  bool enabled = false;
  @override
  List<WanDevice> get trustedDevicesList => devices;
  @override
  bool get isInternetModeEnabled => enabled;
  void update() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestRtc extends ChangeNotifier implements WanWebRtcManager {
  bool connected = false;
  String? peerId;
  Completer<void>? negotiation;
  final sent = <String>[];
  String? replyId;
  @override
  bool useUnifiedOutbox = false;
  @override
  bool get isConnected => connected;
  @override
  String? get activePeerId => peerId;
  @override
  Future<void> connectToPeer(WanDevice peer) async {
    peerId = peer.id;
    if (negotiation != null) await negotiation!.future;
    connected = true;
    notifyListeners();
  }

  @override
  Future<void> sendDirectMessage(String text,
      [String? overridePeerId,
      String? replyToId,
      String? replyToSender,
      String? replyToText,
      bool isForwarded = false,
      String? messageId]) async {
    expect(overridePeerId, peerId);
    sent.add(messageId!);
    replyId = replyToId;
  }

  @override
  Future<void> sendDirectFile(File file,
      [String? overridePeerId,
      bool isForwarded = false,
      String? messageId,
      bool folder = false]) async {
    expect(overridePeerId, peerId);
    sent.add(messageId!);
  }

  @override
  bool isItemQueued(String id) => false;
  @override
  Future<bool> cancelQueuedItem(String id) async => false;
  void update() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Peer local(
        {String id = 'lan-phone',
        String? wanId = 'wan-phone',
        bool online = true}) =>
    Peer(
        id: id,
        name: 'Same model',
        ip: '192.168.1.5',
        internetDeviceId: wanId,
        platform: 'android',
        lastSeen:
            online ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(0));
WanDevice remote({String id = 'wan-phone', bool trusted = true}) => WanDevice(
    id: id,
    name: 'Same model',
    platform: 'android',
    isOnline: true,
    isTrusted: trusted);

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 300 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Nearby wins over WAN for either entry point; calls only use Nearby',
      () {
    final phone = local();
    final entry = Peer(id: 'wan-phone', name: phone.name, ip: '');
    for (final peer in [phone, entry]) {
      final route = ChatRoute.resolve(
          peer, [phone], [remote()], {'lan-phone': 'wan-phone'},
          internetEnabled: true);
      expect(route.transport, ChatTransport.nearby);
      expect(route.canCall, isTrue);
    }
    final wan = ChatRoute.resolve(
        entry, [local(online: false)], [remote()], {'lan-phone': 'wan-phone'},
        internetEnabled: true);
    expect(wan.transport, ChatTransport.internet);
    expect(wan.canCall, isFalse);
    final connected = ChatRoute.resolve(
        entry, [], [remote().copyWith(isOnline: false)], {},
        internetEnabled: true, connectedInternetPeerId: 'wan-phone');
    expect(connected.transport, ChatTransport.internet);
  });

  test(
      'WAN requires explicit enablement and trust; matching names do not link devices',
      () {
    final entry = Peer(id: 'wan-phone', name: 'Same model', ip: '');
    expect(
        ChatRoute.resolve(entry, [], [remote()], {}, internetEnabled: false)
            .transport,
        ChatTransport.offline);
    expect(
        ChatRoute.resolve(entry, [], [remote(trusted: false)], {},
                internetEnabled: true)
            .transport,
        ChatTransport.offline);
    final unrelated = local(id: 'another-phone', wanId: null);
    expect(
        ChatRoute.resolve(entry, [unrelated], [remote()], {},
                internetEnabled: true)
            .transport,
        ChatTransport.internet);
    expect(
        ChatRoute.resolve(entry, [unrelated], [], {}, internetEnabled: true)
            .transport,
        ChatTransport.offline);
  });

  test('Riverpod route updates from WAN to Nearby without recreating the queue',
      () async {
    final nearby = TestNearby();
    final wan = TestWan()..enabled = true;
    wan.devices.add(remote());
    final rtc = TestRtc();
    final controller = ConversationController(nearby, wan, rtc);
    final container = ProviderContainer(overrides: [
      conversationControllerProvider.overrideWith((ref) => controller),
    ]);
    final peer = controller.peerForWan(remote());
    final subscription = container.listen(chatRouteProvider(peer), (_, __) {});
    await controller.ready;
    expect(container.read(chatRouteProvider(peer)).transport,
        ChatTransport.internet);
    nearby.devices.add(local());
    nearby.update();
    expect(container.read(chatRouteProvider(peer)).transport,
        ChatTransport.nearby);
    expect(container.read(conversationControllerProvider), same(controller));
    expect(controller.aliases(peer), contains('lan-phone'));
    subscription.close();
    container.dispose();
  });

  test(
      'One queued message drains over WAN after negotiation, preserving reply and ID',
      () async {
    final nearby = TestNearby();
    final wan = TestWan();
    wan.devices.add(remote());
    final rtc = TestRtc()..negotiation = Completer<void>();
    final controller = ConversationController(nearby, wan, rtc);
    final peer = controller.peerForWan(remote());
    await controller.ready;
    final reply = ChatItem(
        id: 'original',
        peerId: peer.id,
        sender: 'Peer',
        mine: false,
        createdAt: DateTime.now(),
        kind: ChatKind.text,
        text: 'Question');
    await controller.sendText(peer, 'Answer', reply: reply);
    var items = await HistoryService().load();
    expect(items, hasLength(1));
    final id = items.single.id;
    expect(items.single.status, 'Queued');
    wan.enabled = true;
    wan.update();
    await until(() => rtc.peerId != null);
    expect(rtc.sent, isEmpty);
    rtc.negotiation!.complete();
    await until(() => rtc.sent.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    items = await HistoryService().load();
    expect(items, hasLength(1));
    expect(items.single.id, id);
    expect(items.single.status, 'Sent');
    expect(rtc.sent, [id]);
    expect(rtc.replyId, 'original');
    await controller.flush();
    expect(rtc.sent, [id]);
    controller.dispose();
  });

  test('A LAN failure falls back to WAN using the same outgoing message ID',
      () async {
    final nearby = TestNearby()..sendSucceeds = false;
    nearby.devices.add(local());
    final wan = TestWan()..enabled = true;
    wan.devices.add(remote());
    final rtc = TestRtc();
    final controller = ConversationController(nearby, wan, rtc);
    await controller.ready;
    await controller.sendText(local(), 'Fallback');
    await until(() => rtc.sent.isNotEmpty);
    expect(nearby.sent, rtc.sent);
    controller.dispose();
  });

  test('Offline queue survives restart and sends via Nearby when it appears',
      () async {
    final nearby = TestNearby();
    final wan = TestWan();
    final rtc = TestRtc();
    var controller = ConversationController(nearby, wan, rtc);
    await controller.ready;
    await controller.sendText(
        Peer(id: 'lan-phone', name: 'Phone', ip: ''), 'Later');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final id = (await HistoryService().load()).single.id;
    controller.dispose();
    controller = ConversationController(nearby, wan, rtc);
    await controller.ready;
    nearby.devices.add(local());
    nearby.update();
    await until(() => nearby.sent.isNotEmpty);
    expect(nearby.sent, [id]);
    expect(rtc.sent, isEmpty);
    controller.dispose();
  });

  test('Cancelling a queued message prevents sends when connectivity returns',
      () async {
    final nearby = TestNearby();
    final wan = TestWan();
    final rtc = TestRtc();
    final controller = ConversationController(nearby, wan, rtc);
    await controller.ready;
    await controller.sendText(
        Peer(id: 'lan-phone', name: 'Phone', ip: ''), 'Cancel me');
    final id = (await HistoryService().load()).single.id;
    await controller.cancel(id);
    nearby.devices.add(local());
    await controller.flush();
    expect(nearby.sent, isEmpty);
    expect((await HistoryService().load()).single.status, 'Cancelled');
    controller.dispose();
  });

  test('Concurrent history updates retain both transports and sort by time',
      () async {
    final history = HistoryService();
    final now = DateTime.now();
    final newer = ChatItem(
        id: 'wan',
        peerId: 'phone',
        sender: 'Peer',
        mine: false,
        createdAt: now,
        kind: ChatKind.text,
        text: 'WAN');
    final older = ChatItem(
        id: 'lan',
        peerId: 'phone',
        sender: 'Me',
        mine: true,
        createdAt: now.subtract(const Duration(seconds: 1)),
        kind: ChatKind.text,
        text: 'LAN');
    await Future.wait([history.addItem(newer), history.addItem(older)]);
    expect((await history.load()).map((e) => e.id), ['lan', 'wan']);
    older.status = 'Sent';
    await history.addItem(older);
    expect(await history.load(), hasLength(2));
  });

  test('Viewing another history does not redirect the active WAN connection',
      () async {
    final rtc = WanWebRtcManager();
    expect(rtc.activePeerId, isNull);
    await rtc.loadChatHistory('unrelated-device');
    expect(rtc.activePeerId, isNull);
  });
  test('Files use Nearby first and WAN when the same device leaves Nearby',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('chat_routing_test');
    final file =
        await File('${directory.path}/sample.txt').writeAsString('sample');
    final nearby = TestNearby();
    nearby.devices.add(local());
    final wan = TestWan()..enabled = true;
    wan.devices.add(remote());
    final rtc = TestRtc();
    final controller = ConversationController(nearby, wan, rtc);
    try {
      await controller.ready;
      await controller.sendFile(local(), file);
      await until(() => nearby.sent.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(rtc.sent, isEmpty);
      nearby.devices.clear();
      nearby.update();
      await controller.sendFile(controller.peerForWan(remote()), file);
      await until(() => rtc.sent.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final items = await HistoryService().load();
      expect(items, hasLength(2));
      expect(items.every((item) => item.status == 'Sent'), isTrue);
      expect(items.map((item) => item.peerId).toSet(), {'wan-phone'});
    } finally {
      controller.dispose();
      await directory.delete(recursive: true);
    }
  });

  test(
      'Legacy history and queued sends migrate without losing the original message ID',
      () async {
    final previous = ChatItem(
        id: 'legacy-message',
        peerId: 'wan-phone',
        sender: 'Me',
        mine: true,
        createdAt: DateTime.now(),
        kind: ChatKind.text,
        text: 'Old queued text',
        status: 'Queued');
    final queued = QueuedOutboxItem(
        id: previous.id,
        peerId: previous.peerId,
        peerName: 'Phone',
        kind: ChatKind.text,
        text: previous.text,
        createdAt: previous.createdAt);
    SharedPreferences.setMockInitialValues({
      'nearmitra_wan_chat_history_wan-phone': jsonEncode([previous.toJson()]),
      'nearmitra_wan_outbox_queue_v1': [jsonEncode(queued.toJson())],
    });
    final nearby = TestNearby();
    final wan = TestWan()..enabled = true;
    wan.devices.add(remote());
    final rtc = TestRtc();
    final controller = ConversationController(nearby, wan, rtc);
    await controller.ready;
    expect((await HistoryService().load()).single.id, previous.id);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('nearmitra_wan_outbox_queue_v1'), isFalse);
    await controller.flush();
    expect(rtc.sent, [previous.id]);
    expect((await HistoryService().load()).single.status, 'Sent');
    controller.dispose();
  });
}
