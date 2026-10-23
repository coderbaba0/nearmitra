import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_item.dart';
import '../models/chat_route.dart';
import '../models/peer.dart';
import '../models/wan_models.dart';
import '../services/history_service.dart';
import '../services/nearby_service.dart';
import '../services/wan_service.dart';
import '../services/wan_webrtc_manager.dart';
import 'nearby_providers.dart';

final conversationControllerProvider =
    ChangeNotifierProvider<ConversationController>((ref) {
  // Read rather than watch: NearbyService notifications must not recreate queues.
  return ConversationController(
      ref.read(nearbyServiceProvider), WanService(), WanWebRtcManager());
});

final chatRouteProvider = Provider.family<ChatRoute, Peer>((ref, peer) {
  return ref.watch(conversationControllerProvider).route(peer);
});

/// One durable outbox and identity map for both network transports.
class ConversationController extends ChangeNotifier {
  ConversationController(this.nearby, this.wan, this.rtc) {
    nearby.useUnifiedOutbox = true;
    rtc.useUnifiedOutbox = true;
    nearby.addListener(_changed);
    wan.addListener(_changed);
    rtc.addListener(_changed);
    ready = _load();
    _retryTimer = Timer.periodic(const Duration(seconds: 5), (_) => flush());
  }

  final NearbyService nearby;
  final WanService wan;
  final WanWebRtcManager rtc;
  final HistoryService _history = HistoryService();
  final Map<String, String> _links = {};
  final Map<String, ChatItem> _pending = {};
  late final Future<void> ready;
  Timer? _retryTimer;
  bool _flushing = false;
  bool _disposed = false;
  static const _queueKey = 'unified_chat_outbox_v1';
  static const _linksKey = 'unified_chat_device_links_v1';

  String canonicalId(String id) {
    final clean = id.startsWith('wan:') ? id.substring(4) : id;
    return _links[clean] ?? clean;
  }

  Set<String> aliases(Peer peer) {
    final id = canonicalId(peer.internetDeviceId ?? peer.id);
    return {
      id,
      peer.id,
      if (peer.ip.isNotEmpty) peer.ip,
      ..._links.entries.where((e) => e.value == id).map((e) => e.key)
    };
  }

  ChatRoute route(Peer peer) =>
      ChatRoute.resolve(peer, nearby.peers, wan.trustedDevicesList, _links,
          internetEnabled: wan.isInternetModeEnabled,
          connectedInternetPeerId: rtc.isConnected ? rtc.activePeerId : null);

  Peer peerForWan(WanDevice device) =>
      nearby.peers
          .where((p) =>
              canonicalId(p.id) == device.id || p.internetDeviceId == device.id)
          .firstOrNull ??
      Peer(
          id: device.id,
          name: device.name,
          ip: '',
          internetDeviceId: device.id,
          platform: device.platform,
          avatarEmoji: device.avatarEmoji,
          lastSeen: DateTime.fromMillisecondsSinceEpoch(0));

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawLinks = prefs.getString(_linksKey);
    if (rawLinks != null) {
      try {
        _links.addAll(Map<String, String>.from(jsonDecode(rawLinks) as Map));
      } catch (error) {
        debugPrint('[Conversation] Invalid cached device links: $error');
      }
    }
    for (final raw in prefs.getStringList(_queueKey) ?? <String>[]) {
      try {
        final item = ChatItem.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
        item.status = 'Queued';
        _pending[item.id] = item;
      } catch (error) {
        debugPrint('[Conversation] Invalid cached outbox item: $error');
      }
    }
    // Preserve the old WAN-only history in the common history store.
    final migrated = <ChatItem>[];
    for (final key in prefs
        .getKeys()
        .where((k) => k.startsWith('nearmitra_wan_chat_history_'))) {
      try {
        final list = jsonDecode(prefs.getString(key)!) as List;
        migrated.addAll(list.map(
            (e) => ChatItem.fromJson(Map<String, dynamic>.from(e as Map))));
      } catch (e) {
        debugPrint('[Conversation] History migration skipped for $key: $e');
      }
    }
    if (!prefs.containsKey('unified_chat_history_migrated_v1')) {
      final existing = await _history.load();
      final ids = existing.map((e) => e.id).toSet();
      await _history
          .addItems(migrated.where((e) => !ids.contains(e.id)).toList());
      await prefs.setBool('unified_chat_history_migrated_v1', true);
    }
    // Move legacy queued sends to the same retry owner without changing IDs.
    final history = {for (final item in await _history.load()) item.id: item};
    for (final key in [
      'nearby_outbox_queue_v1',
      'nearmitra_wan_outbox_queue_v1'
    ]) {
      for (final raw in prefs.getStringList(key) ?? <String>[]) {
        try {
          final old = QueuedOutboxItem.fromJson(
              Map<String, dynamic>.from(jsonDecode(raw) as Map));
          final item = history[old.id] ??
              ChatItem(
                  id: old.id,
                  peerId: old.peerId,
                  sender: nearby.deviceName,
                  mine: true,
                  createdAt: old.createdAt,
                  kind: old.kind,
                  text: old.text,
                  fileName: old.fileName,
                  filePath: old.filePath,
                  fileSize: old.fileSize,
                  status: 'Queued');
          _pending.putIfAbsent(item.id, () => item);
        } catch (e) {
          debugPrint('[Conversation] Invalid legacy outbox item: $e');
        }
      }
    }
    await _saveQueue();
    // Remove in-memory copies as well, so legacy owners cannot retry migrated IDs.
    for (final id in _pending.keys.toList()) {
      await nearby.cancelQueuedItem(id);
      await rtc.cancelQueuedItem(id);
    }
    await _history.addItems(_pending.values.toList());
    await prefs.remove('nearby_outbox_queue_v1');
    await prefs.remove('nearmitra_wan_outbox_queue_v1');
    _learnLinks();
    if (!_disposed) notifyListeners();
  }

  bool _learnLinks() {
    var changed = false;
    for (final peer in nearby.peers) {
      final remoteId = peer.internetDeviceId;
      if (remoteId == null ||
          remoteId.isEmpty ||
          remoteId == 'unknown_device_id') {
        continue;
      }
      for (final alias in [peer.id]) {
        if (_links[alias] != remoteId) {
          _links[alias] = remoteId;
          changed = true;
        }
      }
    }
    if (changed) {
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setString(_linksKey, jsonEncode(_links)));
    }
    return changed;
  }

  void _changed() {
    if (_disposed) return;
    _learnLinks();
    notifyListeners();
    // Listener callbacks must not recursively send while a service is notifying.
    scheduleMicrotask(flush);
  }

  Future<void> _saveQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _queueKey, _pending.values.map((e) => jsonEncode(e.toJson())).toList());
  }

  Future<void> sendText(Peer peer, String text,
      {ChatItem? reply, bool forwarded = false}) async {
    if (text.trim().isEmpty) return;
    await _enqueue(ChatItem(
        id: const Uuid().v4(),
        peerId: canonicalId(peer.internetDeviceId ?? peer.id),
        sender: nearby.deviceName,
        mine: true,
        createdAt: DateTime.now(),
        kind: ChatKind.text,
        text: text.trim(),
        status: 'Queued',
        replyToId: reply?.id,
        replyToSender: reply?.sender,
        replyToText: reply?.text ?? reply?.fileName,
        isForwarded: forwarded));
  }

  Future<void> sendFile(Peer peer, File file, {bool forwarded = false}) async {
    await _enqueue(ChatItem(
        id: const Uuid().v4(),
        peerId: canonicalId(peer.internetDeviceId ?? peer.id),
        sender: nearby.deviceName,
        mine: true,
        createdAt: DateTime.now(),
        kind: ChatKind.file,
        fileName: file.uri.pathSegments.last,
        filePath: file.path,
        fileSize: await file.length(),
        status: 'Queued',
        isForwarded: forwarded));
  }

  Future<void> sendFolder(Peer peer, String path) async {
    final dir = Directory(path);
    final name = dir.uri.pathSegments.where((e) => e.isNotEmpty).last;
    final temp = await getTemporaryDirectory();
    final archiveDir =
        await Directory('${temp.path}/chat_outbox_${const Uuid().v4()}')
            .create();
    final archive = File('${archiveDir.path}/$name.zip');
    final encoder = ZipFileEncoder()..create(archive.path);
    try {
      await encoder.addDirectory(dir);
    } finally {
      encoder.close();
    }
    // Keep the archive until a queued send succeeds.
    await _enqueue(ChatItem(
        id: const Uuid().v4(),
        peerId: canonicalId(peer.internetDeviceId ?? peer.id),
        sender: nearby.deviceName,
        mine: true,
        createdAt: DateTime.now(),
        kind: ChatKind.folder,
        fileName: name,
        filePath: archive.path,
        fileSize: await archive.length(),
        status: 'Queued'));
  }

  Future<void> _enqueue(ChatItem item) async {
    await ready;
    _pending[item.id] = item;
    await _saveQueue();
    await _history.addItem(item);
    if (!_disposed) notifyListeners();
    unawaited(flush());
  }

  Future<void> cancel(String id) async {
    await ready;
    final item = _pending.remove(id);
    if (item != null) {
      item.status = 'Cancelled';
      await _saveQueue();
      await _history.addItem(item);
    }
    await nearby.cancelQueuedItem(id);
    await rtc.cancelQueuedItem(id);
  }

  Future<void> clearConversation(Peer peer) async {
    await ready;
    final ids = aliases(peer);
    await _history.removePeers(ids);
    final prefs = await SharedPreferences.getInstance();
    for (final id in ids) {
      await prefs.remove('nearmitra_wan_chat_history_$id');
    }
    final remoteId = canonicalId(peer.internetDeviceId ?? peer.id);
    await rtc.clearChatHistory(remoteId);
  }

  void typing(Peer peer, bool value) {
    final selected = route(peer);
    if (selected.transport == ChatTransport.nearby) {
      nearby.sendTypingStatus(selected.nearby!, value);
    } else if (rtc.isConnected && rtc.activePeerId == selected.internet?.id) {
      rtc.sendTypingIndicator(value);
    }
  }

  Future<void> flush() async {
    await ready;
    if (_flushing || _disposed) return;
    _flushing = true;
    try {
      for (final item in _pending.values.toList()) {
        if (_disposed || !_pending.containsKey(item.id)) continue;
        final id = canonicalId(item.peerId);
        final peer =
            nearby.peers.where((p) => canonicalId(p.id) == id).firstOrNull ??
                Peer(
                    id: id,
                    name: 'Device',
                    ip: '',
                    lastSeen: DateTime.fromMillisecondsSinceEpoch(0));
        final selected = route(peer);
        if (selected.transport == ChatTransport.offline) continue;
        if (item.kind != ChatKind.text &&
            (item.filePath == null || !await File(item.filePath!).exists())) {
          item.status = 'Failed (File missing)';
          _pending.remove(item.id);
          await _saveQueue();
          await _history.addItem(item);
          continue;
        }
        item.status = 'Sending…';
        await _history.addItem(item);
        var sent = false;
        try {
          if (selected.transport == ChatTransport.nearby) {
            sent = item.kind == ChatKind.text
                ? await nearby.sendChat(selected.nearby!, item.text!,
                    msgId: item.id,
                    replyToId: item.replyToId,
                    replyToSender: item.replyToSender,
                    replyToText: item.replyToText,
                    isForwarded: item.isForwarded)
                : await nearby.sendFile(selected.nearby!, File(item.filePath!),
                    folderArchive: item.kind == ChatKind.folder,
                    displayName: item.fileName,
                    msgId: item.id);
          }
          // A failed LAN send may fall back to an explicitly enabled WAN route.
          final remote = selected.internet;
          if (!sent &&
              wan.isInternetModeEnabled &&
              remote != null &&
              remote.isTrusted &&
              (remote.isOnline ||
                  (rtc.isConnected && rtc.activePeerId == remote.id))) {
            if (!rtc.isConnected || rtc.activePeerId != remote.id) {
              await rtc.connectToPeer(remote);
              final watch = Stopwatch()..start();
              while (!rtc.isConnected &&
                  watch.elapsed < const Duration(seconds: 40) &&
                  rtc.activePeerId == remote.id &&
                  wan.isInternetModeEnabled &&
                  !_disposed) {
                await Future<void>.delayed(const Duration(milliseconds: 100));
              }
            }
            if (rtc.isConnected &&
                rtc.activePeerId == remote.id &&
                wan.isInternetModeEnabled &&
                _pending.containsKey(item.id)) {
              if (item.kind == ChatKind.text) {
                await rtc.sendDirectMessage(
                    item.text!,
                    remote.id,
                    item.replyToId,
                    item.replyToSender,
                    item.replyToText,
                    item.isForwarded,
                    item.id);
              } else {
                await rtc.sendDirectFile(File(item.filePath!), remote.id,
                    item.isForwarded, item.id, item.kind == ChatKind.folder);
              }
              sent = !rtc.isItemQueued(item.id);
              // The unified outbox owns retries, including transport changes.
              if (!sent) await rtc.cancelQueuedItem(item.id);
            }
          }
        } catch (e) {
          debugPrint('[Conversation] Send deferred for ${item.id}: $e');
        }
        if (!_pending.containsKey(item.id)) continue;
        item.status = sent ? 'Sent' : 'Queued';
        if (sent) _pending.remove(item.id);
        await _saveQueue();
        await _history.addItem(item);
      }
    } finally {
      _flushing = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    nearby.removeListener(_changed);
    wan.removeListener(_changed);
    rtc.removeListener(_changed);
    super.dispose();
  }
}
