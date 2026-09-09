import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_item.dart';
import '../models/peer.dart';
import '../models/transfer_state.dart';
import 'ai_settings_service.dart';
import 'android_network_bridge.dart';
import 'call_service.dart';
import 'device_identity.dart';
import 'firebase_presence_service.dart';
import 'internet_device_identity_service.dart';
import 'notification_service.dart';

const int discoveryPort = 43888;
const int transferPort = 43889;
final InternetAddress multicastAddress = InternetAddress('239.255.43.88');

class QueuedOutboxItem {
  final String id;
  final String peerId;
  final String peerName;
  final ChatKind kind;
  final String? text;
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final DateTime createdAt;

  QueuedOutboxItem({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.kind,
    this.text,
    this.filePath,
    this.fileName,
    this.fileSize,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'peerId': peerId,
        'peerName': peerName,
        'kind': kind.name,
        'text': text,
        'filePath': filePath,
        'fileName': fileName,
        'fileSize': fileSize,
        'createdAt': createdAt.toIso8601String(),
      };

  factory QueuedOutboxItem.fromJson(Map<String, dynamic> json) =>
      QueuedOutboxItem(
        id: json['id'] as String,
        peerId: json['peerId'] as String,
        peerName: json['peerName'] as String? ?? 'Peer Device',
        kind: ChatKind.values.firstWhere(
          (e) => e.name == json['kind'],
          orElse: () => ChatKind.text,
        ),
        text: json['text'] as String?,
        filePath: json['filePath'] as String?,
        fileName: json['fileName'] as String?,
        fileSize: json['fileSize'] as int?,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class NearbyService extends ChangeNotifier {
  static NearbyService? _instance;
  static NearbyService get instance => _instance!;

  final String deviceId;
  String _deviceName;
  String get deviceName => _deviceName;
  String _avatarEmoji;
  String get avatarEmoji => _avatarEmoji;

  NearbyService({required this.deviceId, required String deviceName, String avatarEmoji = '📱'})
      : _deviceName = deviceName,
        _avatarEmoji = avatarEmoji {
    _instance = this;
    _loadOutbox();
  }

  /// Updates device display name & avatar emoji across all services (LAN, P2P, WAN)
  Future<void> updateDeviceIdentity({required String name, required String emoji}) async {
    final cleanName = name.trim();
    final cleanEmoji = emoji.trim();
    if (cleanName.isNotEmpty) {
      _deviceName = cleanName;
    }
    if (cleanEmoji.isNotEmpty) {
      _avatarEmoji = cleanEmoji;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('farmitra_nearby_device_name', _deviceName);
    await prefs.setString('farmitra_device_avatar_emoji', _avatarEmoji);

    final identity = DeviceIdentity();
    await identity.setName(_deviceName);
    await identity.setAvatarEmoji(_avatarEmoji);

    await InternetDeviceIdentityService().updateDeviceIdentity(newName: _deviceName, newEmoji: _avatarEmoji);
    await FirebasePresenceService().updateDeviceIdentity(newName: _deviceName, newEmoji: _avatarEmoji);

    await announce();
    notifyListeners();
  }
  final AndroidNetworkBridge _bridge = AndroidNetworkBridge();
  final NotificationService _notificationService = NotificationService();

  String? _customSavePath;
  String? get customSavePath => _customSavePath;
  set customSavePath(String? val) {
    _customSavePath = val;
    _saveCustomSavePath(val);
    notifyListeners();
  }

  Future<void> _saveCustomSavePath(String? val) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (val == null || val.isEmpty) {
        await prefs.remove('custom_save_path');
      } else {
        await prefs.setString('custom_save_path', val);
      }
    } catch (_) {}
  }

  Future<void> _loadCustomSavePath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _customSavePath = prefs.getString('custom_save_path');
    } catch (_) {}
  }

  bool _meshRelayEnabled = false;
  bool get meshRelayEnabled => _meshRelayEnabled;
  static const _kMeshRelayEnabled = 'mesh_relay_enabled';
  final Set<String> _seenMeshMsgIds = {};

  Future<void> _loadMeshRelaySetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _meshRelayEnabled = prefs.getBool(_kMeshRelayEnabled) ?? false;
    } catch (_) {
      _meshRelayEnabled = false;
    }
  }

  Future<void> setMeshRelayEnabled(bool value) async {
    _meshRelayEnabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kMeshRelayEnabled, value);
    } catch (_) {}
    notifyListeners();
  }

  bool _backgroundServiceEnabled = true;
  bool get backgroundServiceEnabled => _backgroundServiceEnabled;

  static const MethodChannel _networkChannel =
      MethodChannel('farmitra_nearby/network');

  Future<void> _loadBackgroundServiceSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _backgroundServiceEnabled =
          prefs.getBool('background_service_enabled') ?? true;
    } catch (_) {
      _backgroundServiceEnabled = true;
    }
  }

  Future<void> setBackgroundServiceEnabled(bool value) async {
    _backgroundServiceEnabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('background_service_enabled', value);
    } catch (_) {}

    if (value) {
      await startBackgroundService();
    } else {
      await stopBackgroundService();
    }
    notifyListeners();
  }

  Future<bool> startBackgroundService() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok =
          await _networkChannel.invokeMethod<bool>('startForegroundService');
      return ok ?? false;
    } catch (e) {
      log('Error starting background service: $e');
      return false;
    }
  }

  Future<bool> stopBackgroundService() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok =
          await _networkChannel.invokeMethod<bool>('stopForegroundService');
      return ok ?? false;
    } catch (e) {
      log('Error stopping background service: $e');
      return false;
    }
  }

  bool _notificationsEnabled = true;
  bool get notificationsEnabled => _notificationsEnabled;
  static const _kNotificationsEnabled = 'local_notifications_enabled';

  Future<void> _loadNotificationsSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _notificationsEnabled =
          prefs.getBool(_kNotificationsEnabled) ?? true;
    } catch (_) {
      _notificationsEnabled = true;
    }
  }

  Future<void> setNotificationsEnabled(bool value) async {
    _notificationsEnabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kNotificationsEnabled, value);
    } catch (_) {}
    notifyListeners();
  }

  Function(String peerId)? onPeerAutoConnected;

  final Map<String, Peer> _peers = {};

  final List<QueuedOutboxItem> _outbox = [];
  List<QueuedOutboxItem> get outbox => List.unmodifiable(_outbox);
  Function(String itemId, String newStatus)? onOutboxItemStatusChanged;
  static const _kOutboxKey = 'nearby_outbox_queue_v1';
  bool _isFlushingQueue = false;

  Future<void> _loadOutbox() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kOutboxKey) ?? [];
      _outbox.clear();
      for (final raw in list) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          _outbox.add(QueuedOutboxItem.fromJson(map));
        } catch (_) {}
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveOutbox() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = _outbox.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList(_kOutboxKey, rawList);
    } catch (_) {}
  }

  Future<void> queueOutboxItem(QueuedOutboxItem item) async {
    _outbox.removeWhere((x) => x.id == item.id);
    _outbox.add(item);
    await _saveOutbox();
    notifyListeners();
    log('[Outbox] Queued item ${item.id} (${item.kind.name}) for ${item.peerName}');
  }

  Future<bool> cancelQueuedItem(String itemId) async {
    final index = _outbox.indexWhere((x) => x.id == itemId);
    if (index != -1) {
      final removed = _outbox.removeAt(index);
      await _saveOutbox();
      onOutboxItemStatusChanged?.call(itemId, 'Cancelled');
      notifyListeners();
      log('[Outbox] Cancelled queued item $itemId for ${removed.peerName}');
      return true;
    }
    return false;
  }

  bool isItemQueued(String itemId) {
    return _outbox.any((x) => x.id == itemId);
  }

  Future<void> flushQueueForPeer(Peer peer) async {
    if (_isFlushingQueue) return;
    final targetIp = _resolveTargetIp(peer);
    if (targetIp.isEmpty || targetIp == '0.0.0.0' || targetIp.startsWith('127.')) {
      return;
    }

    final pendingForPeer = _outbox
        .where((x) =>
            x.peerId == peer.id ||
            x.peerId == peer.ip ||
            (targetIp.isNotEmpty && x.peerId == targetIp))
        .toList();

    if (pendingForPeer.isEmpty) return;

    _isFlushingQueue = true;
    log('[Outbox] Flushing ${pendingForPeer.length} pending items to ${peer.name} ($targetIp)');

    for (final item in pendingForPeer) {
      if (!_outbox.any((x) => x.id == item.id)) {
        // Was cancelled while flushing
        continue;
      }

      bool success = false;
      if (item.kind == ChatKind.text &&
          item.text != null &&
          item.text!.isNotEmpty) {
        success = await sendChat(peer, item.text!);
      } else if (item.kind == ChatKind.file && item.filePath != null) {
        final file = File(item.filePath!);
        if (await file.exists()) {
          success = await sendFile(peer, file, displayName: item.fileName);
        } else {
          // File was deleted on disk
          _outbox.removeWhere((x) => x.id == item.id);
          await _saveOutbox();
          onOutboxItemStatusChanged?.call(item.id, 'Failed (File missing)');
          continue;
        }
      }

      if (success) {
        _outbox.removeWhere((x) => x.id == item.id);
        await _saveOutbox();
        onOutboxItemStatusChanged?.call(item.id, 'Sent');
        notifyListeners();
        log('[Outbox] Successfully delivered queued item ${item.id} to ${peer.name}');
      } else {
        log('[Outbox] Failed delivering queued item ${item.id} to ${peer.name}, will retry later');
        break; // Stop flushing this peer if connection failed
      }
    }

    _isFlushingQueue = false;
  }

  final List<ChatItem> _incomingItems = [];
  final List<String> _logs = [];
  TransferState _transfer = const TransferState();

  RawDatagramSocket? _udp;
  ServerSocket? _server;
  Timer? _announceTimer;
  Timer? _cleanupTimer;
  Timer? _keepaliveTimer;
  bool _started = false;

  final Set<String> _pinnedPeerIds = {};
  static const _kPinnedPeersKey = 'nearby_pinned_peer_ids_v1';

  bool isPeerPinned(String peerId) {
    return _pinnedPeerIds.contains(peerId);
  }

  Future<void> _loadPinnedPeers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kPinnedPeersKey) ?? [];
      _pinnedPeerIds.clear();
      _pinnedPeerIds.addAll(list);
    } catch (_) {}
  }

  Future<void> _savePinnedPeers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kPinnedPeersKey, _pinnedPeerIds.toList());
    } catch (_) {}
  }

  Future<bool> togglePinPeer(String peerId) async {
    if (peerId.isEmpty) return false;
    final isNowPinned = !_pinnedPeerIds.contains(peerId);
    if (isNowPinned) {
      _pinnedPeerIds.add(peerId);
    } else {
      _pinnedPeerIds.remove(peerId);
    }
    await _savePinnedPeers();
    notifyListeners();
    return isNowPinned;
  }

  List<Peer> get peers {
    final uniquePeers = <Peer>{};
    for (final p in _peers.values) {
      if (p.id != deviceId &&
          p.name.toLowerCase() != deviceName.toLowerCase() &&
          p.id != 'local_ai_assistant') {
        uniquePeers.add(p);
      }
    }
    final list = uniquePeers.toList();
    list.sort((a, b) {
      final aPinned = _pinnedPeerIds.contains(a.id) || _pinnedPeerIds.contains(a.ip);
      final bPinned = _pinnedPeerIds.contains(b.id) || _pinnedPeerIds.contains(b.ip);
      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }
      if (a.unreadCount != b.unreadCount) {
        return b.unreadCount.compareTo(a.unreadCount);
      }
      final nameComp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (nameComp != 0) return nameComp;
      return a.id.compareTo(b.id);
    });
    return list;
  }

  Peer? getPeer(String idOrIp) {
    if (idOrIp.isEmpty) return null;
    if (_peers.containsKey(idOrIp)) return _peers[idOrIp];
    for (final p in _peers.values) {
      if (p.id == idOrIp || p.ip == idOrIp) return p;
    }
    return null;
  }

  List<ChatItem> takeIncomingItems() {
    final copy = List<ChatItem>.from(_incomingItems);
    _incomingItems.clear();
    return copy;
  }

  List<String> get logs => List.unmodifiable(_logs);
  TransferState get transfer => _transfer;

  Function(String peerId)? onCallAcceptedByPeer;
  Function(String peerId)? onCallDeclinedByPeer;
  Function(String peerId)? onCallEndedByPeer;
  Function(String peerId, bool isVideo)? onCallVideoToggledByPeer;
  Function(String peerId, Map<String, dynamic> offer)? onWebRtcOffer;
  Function(String peerId, Map<String, dynamic> answer)? onWebRtcAnswer;
  Function(String peerId, Map<String, dynamic> candidate)? onWebRtcIceCandidate;
  Function(String peerId, Map<String, dynamic> offer)? onStreamOffer;
  Function(String peerId, Map<String, dynamic> answer)? onStreamAnswer;
  Function(String peerId, Map<String, dynamic> candidate)? onStreamIceCandidate;
  Function(String peerId, Map<String, dynamic> control)? onStreamControl;
  Function(String peerId, Map<String, dynamic> data)? onStreamRejected;
  Function(String peerId, Map<String, dynamic> data)? onStreamStopped;
  void Function(String peerId, String msgId, String? reaction)? onReactionReceived;

  Future<void> sendCallInvite(Peer peer, bool isVideoCall) async {
    final targetIp = _resolveTargetIp(peer);
    if (targetIp.isEmpty) {
      log('[CallInvite] Cannot send invite: IP not resolved for ${peer.name} (${peer.id})');
      return;
    }
    try {
      final socket = await Socket.connect(targetIp, transferPort,
          timeout: const Duration(seconds: 4));
      final payload = jsonEncode({
        'type': 'call_invite',
        'sender': deviceName,
        'sender_id': deviceId,
        'is_video': isVideoCall,
      });
      socket.write('$payload\n');
      await socket.flush();
      socket.destroy();
      log('[CallInvite] Sent call_invite to ${peer.name} ($targetIp)');
    } catch (e) {
      log('Error sending call invite to ${peer.name} ($targetIp): $e');
    }
  }

  String _resolveTargetIp(Peer peer) {
    if (peer.ip.trim().isNotEmpty && peer.ip != '0.0.0.0' && !peer.ip.startsWith('127.')) {
      return peer.ip.trim();
    }
    if (_peers.containsKey(peer.id) && _peers[peer.id]!.ip.trim().isNotEmpty) {
      return _peers[peer.id]!.ip.trim();
    }
    for (final p in _peers.values) {
      if ((p.id == peer.id || p.name == peer.name) && p.ip.trim().isNotEmpty) {
        return p.ip.trim();
      }
    }
    if (peer.id.contains('.') && !peer.id.contains(':')) {
      return peer.id.trim();
    }
    return peer.ip.trim();
  }

  Future<void> sendCallSignal(Peer peer, String signalType,
      {bool? isVideo}) async {
    final targetIp = _resolveTargetIp(peer);
    if (targetIp.isEmpty) {
      log('[CallSignal] Cannot send $signalType: IP not resolved for ${peer.name} (${peer.id})');
      return;
    }
    try {
      final socket = await Socket.connect(targetIp, transferPort,
          timeout: const Duration(seconds: 4));
      final payload = jsonEncode({
        'type': signalType,
        'sender': deviceName,
        'sender_id': deviceId,
        if (isVideo != null) 'is_video': isVideo,
      });
      socket.write('$payload\n');
      await socket.flush();
      await socket.close();
      log('[CallSignal] Sent $signalType to ${peer.name} ($targetIp)');
    } catch (e) {
      log('Error sending call signal $signalType to ${peer.name} ($targetIp): $e');
    }
  }

  Future<void> sendWebRtcSignal(
    Peer peer,
    String signalType,
    Map<String, dynamic> data,
  ) async {
    final targetIp = _resolveTargetIp(peer);
    if (targetIp.isEmpty) {
      log('[WebRtcSignal] Cannot send $signalType: IP not resolved for ${peer.name} (${peer.id})');
      return;
    }
    try {
      final socket = await Socket.connect(targetIp, transferPort,
          timeout: const Duration(seconds: 4));
      final payload = jsonEncode({
        'type': signalType,
        'sender': deviceName,
        'sender_id': deviceId,
        ...data,
      });
      socket.write('$payload\n');
      await socket.flush();
      await socket.close();
      log('[WebRtcSignal] Sent $signalType to ${peer.name} ($targetIp)');
    } catch (e) {
      log('Error sending WebRTC signal $signalType to ${peer.name} ($targetIp): $e');
    }
  }

  void addCallLog({
    required String peerId,
    String? peerName,
    required String text,
    required bool mine,
  }) {
    String resolvedName =
        (peerName != null && peerName.trim().isNotEmpty) ? peerName.trim() : '';
    if (resolvedName.isEmpty) {
      try {
        final p = _peers.values.firstWhere(
          (x) => x.id == peerId || x.ip == peerId,
          orElse: () => Peer(id: peerId, name: '', ip: ''),
        );
        resolvedName = p.name;
      } catch (_) {}
    }
    if (resolvedName.isEmpty) {
      resolvedName = peerId.isNotEmpty ? peerId : 'Peer Device';
    }

    final item = ChatItem(
      peerId: peerId,
      sender: resolvedName,
      mine: mine,
      createdAt: DateTime.now(),
      kind: ChatKind.text,
      text: text,
    );
    _incomingItems.add(item);
    notifyListeners();
  }

  bool isAppInForeground = true;
  String? activeChatPeerId;

  bool _isChatActive(String resolvedPeerId, String remoteIp) {
    if (!isAppInForeground) return false;
    if (activeChatPeerId == null) return false;
    final act = activeChatPeerId!.toLowerCase();
    final res = resolvedPeerId.toLowerCase();
    final ip = remoteIp.toLowerCase();
    return act == res ||
        act == ip ||
        (act.isNotEmpty && (res.contains(act) || act.contains(res)));
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _loadPinnedPeers();
    await _loadNotificationsSetting();
    await _loadCustomSavePath();
    await _loadBackgroundServiceSetting();
    await _loadMeshRelaySetting();
    if (_backgroundServiceEnabled && Platform.isAndroid) {
      await startBackgroundService();
    }
    await _bridge.acquireMulticastLock();
    await _startTransferServer();
    await _startDiscovery();
    _announceTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => announce());
    _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _peers.removeWhere(
          (_, p) => DateTime.now().difference(p.lastSeen).inSeconds > 120);
      notifyListeners();
    });
    _keepaliveTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _pingPeers());
    announce();
    scanSubnet();
    log('NearMitra is ready on local network');
  }

  Future<void> _pingPeers() async {
    for (final p in _peers.values.toList()) {
      _probe(p.ip);
    }
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _cleanupTimer?.cancel();
    _keepaliveTimer?.cancel();
    _udp?.close();
    await _server?.close();
    await _bridge.releaseMulticastLock();
    _started = false;
  }

  Future<void> _startDiscovery() async {
    try {
      RawDatagramSocket socket;
      try {
        socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          discoveryPort,
          reuseAddress: true,
          reusePort: false,
        );
      } catch (_) {
        socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          discoveryPort,
          reuseAddress: true,
        );
      }
      socket.broadcastEnabled = true;
      socket.multicastHops = 1;
      try {
        socket.joinMulticast(multicastAddress);
      } catch (e) {
        log('Multicast join warning: $e');
      }
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        _handleDiscoveryDatagram(datagram);
      });
      _udp = socket;
    } catch (e) {
      log('Discovery listener unavailable: $e');
    }
  }

  void _handleDiscoveryDatagram(Datagram datagram) {
    try {
      final map =
          jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      final id = map['id']?.toString() ?? '';
      final name = map['name']?.toString() ?? 'Nearby device';
      final avatar = map['avatar']?.toString() ?? map['avatarEmoji']?.toString();
      final platform = map['platform']?.toString();
      if (id.isEmpty || id == deviceId) return;
      _upsertPeer(id, name, datagram.address.address,
          avatarEmoji: avatar, platform: platform);
    } catch (_) {}
  }

  Future<void> announce() async {
    if (_udp == null) {
      await _startDiscovery();
    }
    final data = utf8.encode(jsonEncode({
      'id': deviceId,
      'name': deviceName,
      'avatar': avatarEmoji,
      'avatarEmoji': avatarEmoji,
      'platform': Platform.isWindows
          ? 'windows'
          : (Platform.isAndroid ? 'android' : 'ios'),
    }));
    try {
      _udp?.send(data, multicastAddress, discoveryPort);
      _udp?.send(data, InternetAddress('255.255.255.255'), discoveryPort);
      final localIp = await _findLocalIpv4();
      if (localIp != null && localIp.contains('.')) {
        final parts = localIp.split('.');
        if (parts.length == 4) {
          final bcastIp = '${parts[0]}.${parts[1]}.${parts[2]}.255';
          _udp?.send(data, InternetAddress(bcastIp), discoveryPort);
        }
      }
    } catch (_) {
      try {
        _udp?.close();
      } catch (_) {}
      _udp = null;
      await _startDiscovery();
    }
  }

  Future<void> scanSubnet() async {
    final localIp = await _findLocalIpv4();
    if (localIp == null) {
      log('Could not determine local IPv4 for active scan');
      return;
    }
    final parts = localIp.split('.');
    if (parts.length != 4) return;
    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}.';
    log('Scanning local network $prefix*');

    const chunk = 24;
    for (var start = 1; start <= 254; start += chunk) {
      final futures = <Future<void>>[];
      for (var i = start; i < start + chunk && i <= 254; i++) {
        final ip = '$prefix$i';
        if (ip == localIp) continue;
        futures.add(_probe(ip));
      }
      await Future.wait(futures);
    }
    log('Network scan complete');
  }

  Future<String?> bindP2pPeer(String peerIp, String? localIp) async {
    log('P2P link active. Peer IP: $peerIp, Local IP: ${localIp ?? "Unknown"}');
    await announce();
    String? connectedId;
    if (peerIp.isNotEmpty) {
      // Retry probing target peerIp up to 3 times
      for (int attempt = 0; attempt < 3; attempt++) {
        connectedId = await _probe(peerIp);
        if (connectedId != null) break;
        await Future.delayed(const Duration(milliseconds: 400));
      }
      if (connectedId == null && peerIp != '192.168.49.1') {
        connectedId = await _probe('192.168.49.1');
      }
      if (connectedId == null && peerIp != '192.168.49.2') {
        connectedId = await _probe('192.168.49.2');
      }
      // If still null on P2P subnet, check common client IPs
      if (connectedId == null &&
          (peerIp.startsWith('192.168.49.') ||
              (localIp != null && localIp.startsWith('192.168.49.')))) {
        for (int i = 100; i <= 105; i++) {
          final testIp = '192.168.49.$i';
          if (testIp != localIp && testIp != peerIp) {
            connectedId = await _probe(testIp);
            if (connectedId != null) break;
          }
        }
      }
    }
    if (connectedId != null) {
      onPeerAutoConnected?.call(connectedId);
    }
    return connectedId;
  }

  Future<String?> _probe(String ip) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, transferPort,
          timeout: const Duration(milliseconds: 3000));
      socket.write('${jsonEncode({
            'type': 'hello',
            'sender': deviceName,
            'sender_id': deviceId,
            'avatar': avatarEmoji,
            'avatarEmoji': avatarEmoji,
            'platform': Platform.isWindows
                ? 'windows'
                : (Platform.isAndroid ? 'android' : 'ios'),
          })}\n');
      await socket.flush();
      final line =
          await _readLine(socket, timeout: const Duration(milliseconds: 3000));
      if (line == null) return null;
      final map = jsonDecode(line) as Map<String, dynamic>;
      if (map['type'] == 'hello') {
        final id = map['sender_id']?.toString() ?? '';
        final peerId = id.isNotEmpty ? id : ip;
        final avatar =
            map['avatar']?.toString() ?? map['avatarEmoji']?.toString();
        final platform = map['platform']?.toString();
        if (id != deviceId) {
          _upsertPeer(peerId, map['sender']?.toString() ?? 'Nearby device', ip,
              avatarEmoji: avatar, platform: platform);
          return peerId;
        }
      }
    } catch (e) {
      log('Probe error for $ip: $e');
    } finally {
      socket?.destroy();
    }
    return null;
  }

  Future<void> _startTransferServer() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, transferPort,
          shared: true);
      _server!.listen((socket) => _handleConnection(socket));
      log('Listening for chat/files on TCP $transferPort');
    } catch (e) {
      log('Could not open TCP $transferPort: $e');
    }
  }

  String _resolvePeerId(String senderId, String senderName, String remoteIp) {
    if (senderId.isNotEmpty && _peers.containsKey(senderId)) {
      final p = _peers[senderId]!;
      p.lastSeen = DateTime.now();
      if (remoteIp.isNotEmpty) {
        p.ip = remoteIp;
        _peers[remoteIp] = p;
      }
      if (senderName.isNotEmpty) p.name = senderName;
      return p.id;
    }
    if (remoteIp.isNotEmpty && _peers.containsKey(remoteIp)) {
      final p = _peers[remoteIp]!;
      p.lastSeen = DateTime.now();
      if (senderId.isNotEmpty) {
        _peers[senderId] = p;
      }
      if (senderName.isNotEmpty) p.name = senderName;
      return p.id;
    }
    for (final p in _peers.values) {
      if ((remoteIp.isNotEmpty && p.ip == remoteIp) ||
          (senderId.isNotEmpty && p.id == senderId) ||
          (senderName.isNotEmpty &&
              (p.name == senderName ||
                  p.name.contains(senderName) ||
                  senderName.contains(p.name)))) {
        p.lastSeen = DateTime.now();
        if (remoteIp.isNotEmpty) {
          p.ip = remoteIp;
          _peers[remoteIp] = p;
        }
        if (senderId.isNotEmpty) _peers[senderId] = p;
        if (senderName.isNotEmpty) p.name = senderName;
        return p.id;
      }
    }
    final idToUse = senderId.isNotEmpty
        ? senderId
        : (remoteIp.isNotEmpty
            ? remoteIp
            : 'peer_${DateTime.now().millisecondsSinceEpoch}');
    _upsertPeer(idToUse, senderName.isNotEmpty ? senderName : 'Nearby device',
        remoteIp);
    return idToUse;
  }

  Future<void> _handleConnection(Socket socket) async {
    final reader = _SocketReader(socket);
    try {
      final line = await reader.readLine();
      if (line == null) return;
      final h = jsonDecode(line) as Map<String, dynamic>;
      final type = h['type']?.toString();
      final sender =
          h['sender']?.toString() ?? h['name']?.toString() ?? 'Nearby device';
      final senderId = h['sender_id']?.toString() ?? h['id']?.toString() ?? '';
      final senderAvatar =
          h['avatar']?.toString() ?? h['avatarEmoji']?.toString();
      final senderPlatform = h['platform']?.toString();
      final remoteIp = socket.remoteAddress.address;
      final resolvedPeerId = _resolvePeerId(senderId, sender, remoteIp);

      if (type == 'hello') {
        if (senderAvatar != null && senderAvatar.isNotEmpty) {
          final peerObj = _peers[resolvedPeerId] ?? _peers[remoteIp];
          if (peerObj != null) {
            peerObj.avatarEmoji = senderAvatar;
            if (senderPlatform != null) peerObj.platform = senderPlatform;
          }
        }
        socket.write('${jsonEncode({
              'type': 'hello',
              'sender': deviceName,
              'sender_id': deviceId,
              'avatar': avatarEmoji,
              'avatarEmoji': avatarEmoji,
              'platform': Platform.isWindows
                  ? 'windows'
                  : (Platform.isAndroid ? 'android' : 'ios'),
            })}\n');
        await socket.flush();
        final peerObj = _peers[resolvedPeerId] ?? _peers[remoteIp];
        if (peerObj != null && peerObj.ip.isNotEmpty) {
          Future.microtask(() => flushQueueForPeer(peerObj));
        }
        return;
      }

      // 1. Incoming AI Prompt Request from a Connected Peer
      if (type == 'ai_request' ||
          type == 'ai_prompt' ||
          (type == 'ai_chat' && h.containsKey('prompt'))) {
        final prompt = h['prompt']?.toString() ??
            h['message']?.toString() ??
            h['text']?.toString() ??
            '';

        final aiService = AiSettingsService();
        final isAllowed = aiService.isPeerAllowed(resolvedPeerId, remoteIp);

        if (!isAllowed) {
          final resPayload = jsonEncode({
            'type': 'ai_response',
            'sender': '$deviceName AI',
            'sender_id': deviceId,
            'status': 'disabled',
            'error_code': 'ai_disabled',
            'reply': 'Nearby AI access has not been granted by $deviceName.',
            'message': 'Nearby AI access has not been granted by $deviceName.',
          });
          socket.write('$resPayload\n');
          await socket.flush();
          socket.destroy();
          return;
        }

        if (prompt.trim().isEmpty) {
          socket.write('${jsonEncode({
            'type': 'ai_response',
            'sender': '$deviceName AI',
            'sender_id': deviceId,
            'status': 'error',
            'reply': 'Prompt was empty.',
          })}\n');
          await socket.flush();
          socket.destroy();
          return;
        }

        final aiReply = await aiService.generateAiResponse(prompt.trim(), senderId);
        final resPayload = jsonEncode({
          'type': 'ai_response',
          'sender': '$deviceName AI',
          'sender_id': deviceId,
          'status': 'ok',
          'reply': aiReply,
          'message': aiReply,
          'text': aiReply,
          'is_ai': true,
          'ai': true,
        });
        socket.write('$resPayload\n');
        await socket.flush();
        socket.destroy();
        return;
      }

      // 2. Incoming AI Response received from a remote AI Host
      final isAiPacket = type == 'ai_response' ||
          type == 'ai_reply' ||
          type == 'ai_stream' ||
          h['is_ai'] == true ||
          h['ai'] == true ||
          sender.toLowerCase().contains('ai');

      if (isAiPacket) {
        final responseText = h['reply']?.toString() ??
            h['response']?.toString() ??
            h['message']?.toString() ??
            h['text']?.toString() ??
            h['content']?.toString() ??
            '';
        final status = h['status']?.toString();
        final finalMessage =
            (status == 'disabled' || h['error_code'] == 'ai_disabled')
                ? 'Nearby AI is not enabled on this device.'
                : (status == 'error' || h.containsKey('error')
                    ? (h['error']?.toString() ?? responseText)
                    : responseText);

        if (finalMessage.isNotEmpty) {
          final peerObj = _peers[resolvedPeerId] ?? _peers[remoteIp];
          if (peerObj != null) {
            peerObj.unreadCount++;
            peerObj.isAiHost = true;
          }
          _incomingItems.add(ChatItem(
            peerId: resolvedPeerId,
            sender: sender.toLowerCase().contains('ai') ? sender : '$sender AI',
            mine: false,
            createdAt: DateTime.now(),
            kind: ChatKind.text,
            text: finalMessage,
            isAi: true,
          ));
          log('AI response received from $sender: ${finalMessage.length > 30 ? finalMessage.substring(0, 30) : finalMessage}');
          notifyListeners();
        }
        return;
      }

      if (type == 'call_invite') {
        final isVideo = h['is_video'] == true;
        final pId = resolvedPeerId.isNotEmpty
            ? resolvedPeerId
            : (senderId.isNotEmpty ? senderId : remoteIp);
        final pName = sender.isNotEmpty ? sender : 'Peer Device';
        final peerObj = _peers[resolvedPeerId] ??
            _peers[remoteIp] ??
            _upsertPeer(pId, pName, remoteIp);

        CallService().showIncomingCall(
          peerId: peerObj.id,
          peerName: peerObj.name,
          peerIp: peerObj.ip.isNotEmpty ? peerObj.ip : remoteIp,
          isVideoCall: isVideo,
        );
        return;
      }

      if (type == 'call_accepted') {
        onCallAcceptedByPeer?.call(resolvedPeerId);
        return;
      }

      if (type == 'call_declined') {
        CallService().endAllCalls();
        onCallDeclinedByPeer?.call(resolvedPeerId);
        return;
      }

      if (type == 'call_ended') {
        CallService().endAllCalls();
        onCallEndedByPeer?.call(resolvedPeerId);
        return;
      }

      if (type == 'call_video_toggle') {
        final isVideo = h['is_video'] == true;
        onCallVideoToggledByPeer?.call(resolvedPeerId, isVideo);
        return;
      }

      if (type == 'webrtc_offer') {
        onWebRtcOffer?.call(resolvedPeerId, Map<String, dynamic>.from(h));
        return;
      }

      if (type == 'webrtc_answer') {
        onWebRtcAnswer?.call(resolvedPeerId, Map<String, dynamic>.from(h));
        return;
      }

      if (type == 'webrtc_ice') {
        onWebRtcIceCandidate?.call(
            resolvedPeerId, Map<String, dynamic>.from(h));
        return;
      }

      if (type == 'stream_offer') {
        final payload = Map<String, dynamic>.from(h);
        payload['remote_ip'] = remoteIp;
        onStreamOffer?.call(resolvedPeerId, payload);
        return;
      }

      if (type == 'stream_answer') {
        final payload = Map<String, dynamic>.from(h);
        payload['remote_ip'] = remoteIp;
        onStreamAnswer?.call(resolvedPeerId, payload);
        return;
      }

      if (type == 'stream_ice') {
        final payload = Map<String, dynamic>.from(h);
        payload['remote_ip'] = remoteIp;
        onStreamIceCandidate?.call(resolvedPeerId, payload);
        return;
      }

      if (type == 'stream_control') {
        final payload = Map<String, dynamic>.from(h);
        payload['remote_ip'] = remoteIp;
        onStreamControl?.call(resolvedPeerId, payload);
        return;
      }

      if (type == 'stream_rejected') {
        final payload = Map<String, dynamic>.from(h);
        payload['remote_ip'] = remoteIp;
        onStreamRejected?.call(resolvedPeerId, payload);
        return;
      }

      if (type == 'stream_stopped' || type == 'stream_reset' || type == 'stream_ended') {
        onStreamStopped?.call(resolvedPeerId, Map<String, dynamic>.from(h));
        return;
      }

      if (type == 'mesh_relay') {
        final msgId = h['msg_id']?.toString() ?? '';
        if (msgId.isNotEmpty) {
          if (_seenMeshMsgIds.contains(msgId)) {
            return; // Drop duplicate to prevent loops
          }
          _seenMeshMsgIds.add(msgId);
          if (_seenMeshMsgIds.length > 600) {
            _seenMeshMsgIds.remove(_seenMeshMsgIds.first);
          }
        }

        final targetId = h['target_id']?.toString() ?? '';
        final originId = h['origin_id']?.toString() ?? '';
        final originName = h['origin_name']?.toString() ?? 'Remote Peer';
        final ttl = int.tryParse('${h['ttl']}') ?? 0;
        final hops = (h['hops'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        final payload = h['payload'] as Map<dynamic, dynamic>? ?? {};
        final payloadType = payload['type']?.toString() ?? 'chat';
        final payloadMsg = payload['message']?.toString() ?? '';

        // Case 1: Message is meant for this device!
        if (targetId.isNotEmpty &&
            (targetId.toLowerCase() == deviceId.toLowerCase() ||
                targetId.toLowerCase() == deviceName.toLowerCase())) {
          if (payloadType == 'chat' && payloadMsg.isNotEmpty) {
            var peerObj = _peers[originId];
            if (peerObj == null) {
              peerObj = _upsertPeer(originId, originName, remoteIp);
              peerObj.isMeshPeer = true;
              peerObj.relayViaName = sender;
            }

            final isCurrentlyOpen = _isChatActive(originId, remoteIp);
            if (!isCurrentlyOpen) {
              peerObj.unreadCount++;
              if (notificationsEnabled) {
                _notificationService.showIncomingMessageNotification(
                  peerId: originId,
                  senderName: '$originName (Mesh Relay)',
                  message: payloadMsg,
                );
              }
            }

            _incomingItems.add(ChatItem(
              peerId: originId,
              sender: originName,
              mine: false,
              createdAt: DateTime.now(),
              kind: ChatKind.text,
              text: payloadMsg,
              isMeshRelay: true,
              relayHops: hops,
            ));
            log('[Mesh Relay] Delivered message from $originName ($originId) via ${hops.join(" -> ")}');
            notifyListeners();
          }
          return;
        }

        // Case 2: We are an intermediary relay node. Forward if enabled!
        if (_meshRelayEnabled && ttl > 1) {
          final updatedHops = List<String>.from(hops)..add(deviceName);
          final forwardedPacket = jsonEncode({
            'type': 'mesh_relay',
            'msg_id': msgId,
            'origin_id': originId,
            'origin_name': originName,
            'target_id': targetId,
            'ttl': ttl - 1,
            'hops': updatedHops,
            'payload': payload,
          });

          for (final peer in peers) {
            if (peer.ip != remoteIp && peer.id != originId) {
              _forwardMeshPacket(peer.ip, forwardedPacket);
            }
          }
          log('[Mesh Relay] Relayed message from $originName to $targetId (Hop ${updatedHops.length})');
        }
        return;
      }

      if (type == 'typing') {
        final isTyping = h['is_typing'] == true;
        var p = _peers[resolvedPeerId] ?? _peers[remoteIp];
        if (p == null && remoteIp.isNotEmpty) {
          final pId = resolvedPeerId.isNotEmpty
              ? resolvedPeerId
              : (senderId.isNotEmpty ? senderId : remoteIp);
          final pName = sender.isNotEmpty ? sender : 'Peer ($remoteIp)';
          p = _upsertPeer(pId, pName, remoteIp);
        }
        if (p != null) {
          p.isTyping = isTyping;
          p.typingTimer?.cancel();
          if (isTyping) {
            p.typingTimer = Timer(const Duration(milliseconds: 3500), () {
              p?.isTyping = false;
              notifyListeners();
            });
          }
          notifyListeners();
        }
        return;
      }

      if (type == 'reaction') {
        final msgId = h['msg_id']?.toString() ?? '';
        final reaction = h['reaction']?.toString();
        if (msgId.isNotEmpty) {
          onReactionReceived?.call(resolvedPeerId, msgId, reaction);
          notifyListeners();
        }
        return;
      }

      if (type == 'chat') {
        final text = h['message']?.toString() ?? '';
        if (text.isNotEmpty) {
          final isCurrentlyOpen = _isChatActive(resolvedPeerId, remoteIp);
          final peerObj = _peers[resolvedPeerId] ?? _peers[remoteIp];
          if (!isCurrentlyOpen && peerObj != null) {
            peerObj.unreadCount++;
          }
          _incomingItems.add(ChatItem(
            peerId: resolvedPeerId,
            sender: sender,
            mine: false,
            createdAt: DateTime.now(),
            kind: ChatKind.text,
            text: text,
          ));
          log('Message received from $sender');
          if (notificationsEnabled && !isCurrentlyOpen) {
            _notificationService.showIncomingMessageNotification(
              peerId: resolvedPeerId,
              senderName: sender,
              message: text,
            );
          }
          notifyListeners();
        }
        return;
      }

      if (type == 'file') {
        final rawName = h['name']?.toString() ?? 'file';
        final name = _safeFileName(rawName);
        final size = int.tryParse(h['size']?.toString() ?? '') ?? -1;
        final folder = h['folder'] == true;
        if (size < 0) return;
        final dir = await _receiveDirectory();
        final path = await _uniquePath('${dir.path}/$name');
        final file = File(path);
        final sink = file.openWrite();
        var received = 0;
        final watch = Stopwatch()..start();
        var previous = 0;
        var previousMs = 0;
        _setTransfer(
            TransferState(active: true, label: 'Receiving $name', progress: 0));
        while (received < size) {
          final chunk = await reader
              .readBytes((size - received).clamp(1, 256 * 1024).toInt());
          if (chunk.isEmpty) {
            throw const SocketException('Connection closed during transfer');
          }
          sink.add(chunk);
          received += chunk.length;
          final nowMs = watch.elapsedMilliseconds;
          var speed = _transfer.speedBytesPerSec;
          if (nowMs - previousMs >= 100) {
            final deltaSec = (nowMs - previousMs) / 1000.0;
            final instant = (received - previous) / deltaSec;
            speed = speed == 0 ? instant : speed * .72 + instant * .28;
            previous = received;
            previousMs = nowMs;
          }
          final eta = speed > 0 ? ((size - received) / speed).round() : null;
          _setTransfer(TransferState(
            active: true,
            label: 'Receiving $name',
            progress: size == 0 ? 1 : received / size,
            speedBytesPerSec: speed,
            etaSeconds: eta,
          ));
        }
        await sink.flush();
        await sink.close();

        String finalSavedPath = path;
        if (folder) {
          try {
            _setTransfer(TransferState(
                active: true, label: 'Extracting $name…', progress: 1));
            final extractParentPath = await _uniquePath('${dir.path}/$name');
            final extractDir = Directory(extractParentPath);
            await extractDir.create(recursive: true);
            await extractFileToDisk(path, extractParentPath);
            finalSavedPath = extractParentPath;
            try {
              await file.delete();
            } catch (_) {}
          } catch (e) {
            log('Error extracting received folder archive: $e');
          }
        }

        _setTransfer(TransferState(label: 'Received $name', progress: 1));
        final isCurrentlyOpen = _isChatActive(resolvedPeerId, remoteIp);
        if (!isCurrentlyOpen && _peers.containsKey(resolvedPeerId)) {
          _peers[resolvedPeerId]!.unreadCount++;
        }
        _incomingItems.add(ChatItem(
          peerId: resolvedPeerId,
          sender: sender,
          mine: false,
          createdAt: DateTime.now(),
          kind: folder ? ChatKind.folder : ChatKind.file,
          fileName: name,
          filePath: finalSavedPath,
          fileSize: size,
          status: 'Received',
        ));
        log('Received $name from $sender');
        if (notificationsEnabled && !isCurrentlyOpen) {
          _notificationService.showIncomingFileNotification(
            peerId: resolvedPeerId,
            senderName: sender,
            fileName: name,
            fileSizeText: _sizeText(size),
          );
        }
        notifyListeners();
        return;
      }
    } catch (e) {
      log('Incoming connection error: $e');
      _setTransfer(const TransferState(label: 'Transfer failed'));
    } finally {
      socket.destroy();
    }
  }

  Future<void> sendTypingStatus(Peer peer, bool isTyping) async {
    try {
      final socket = await Socket.connect(peer.ip, transferPort,
          timeout: const Duration(milliseconds: 1500));
      socket.write('${jsonEncode({
            'type': 'typing',
            'sender': deviceName,
            'sender_id': deviceId,
            'is_typing': isTyping,
          })}\n');
      await socket.flush();
      socket.destroy();
    } catch (_) {}
  }

  Future<void> sendReaction(Peer peer, String msgId, String? reaction) async {
    final targetIp = _resolveTargetIp(peer);
    if (targetIp.isEmpty) return;
    try {
      final socket = await Socket.connect(targetIp, transferPort,
          timeout: const Duration(milliseconds: 2000));
      socket.write('${jsonEncode({
            'type': 'reaction',
            'msg_id': msgId,
            'reaction': reaction,
            'sender': deviceName,
            'sender_id': deviceId,
          })}\n');
      await socket.flush();
      socket.destroy();
    } catch (_) {}
  }

  Stream<String> streamAiPrompt(Peer peer, String prompt) async* {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) {
      log('[AI DEBUG] AI error response: Prompt was empty');
      yield 'Nearby AI is not enabled on this device.';
      return;
    }

    log('[AI DEBUG] Selected Windows host IP: ${peer.ip}');
    log('[AI DEBUG] AI request sent: $cleanPrompt');

    final typesToTry = ['ai_chat', 'ai_prompt', 'ai_request'];

    for (final pType in typesToTry) {
      log('[AI DEBUG] Outgoing packet type: $pType');
      Socket? socket;
      var receivedAnyChunk = false;
      var explicitDisabled = false;

      try {
        socket = await Socket.connect(peer.ip, transferPort,
            timeout: const Duration(seconds: 8));
        final payload = jsonEncode({
          'type': pType,
          'sender': deviceName,
          'sender_id': deviceId,
          'prompt': cleanPrompt,
          'message': cleanPrompt,
          'text': cleanPrompt,
          'ai': true,
          'is_ai': true,
        });
        socket.write('$payload\n');
        await socket.flush();

        final reader = _SocketReader(socket);

        while (true) {
          final line = await reader
              .readLine()
              .timeout(const Duration(seconds: 45), onTimeout: () => null);
          if (line == null) break;
          if (line.trim().isEmpty) continue;

          String? chunkToYield;

          try {
            final h = jsonDecode(line);
            if (h is Map<String, dynamic>) {
              final incomingType = h['type']?.toString() ?? 'unknown';
              final status = h['status']?.toString();
              log('[AI DEBUG] Incoming packet type: $incomingType, status: ${status ?? "ok"}');

              if (status == 'disabled' || h['error_code'] == 'ai_disabled') {
                explicitDisabled = true;
                const msg = 'Nearby AI is not enabled on this device.';
                log('[AI DEBUG] AI error response: $msg');
                yield msg;
                break;
              }

              if (status == 'error' ||
                  h.containsKey('error') ||
                  h.containsKey('err')) {
                final errText = h['error']?.toString() ??
                    h['err']?.toString() ??
                    h['message']?.toString() ??
                    'AI processing error';
                log('[AI DEBUG] AI error response: $errText');
                yield errText;
                receivedAnyChunk = true;
                break;
              }

              final chunk = h['reply']?.toString() ??
                  h['response']?.toString() ??
                  h['text']?.toString() ??
                  h['message']?.toString() ??
                  h['content']?.toString() ??
                  h['delta']?.toString() ??
                  h['result']?.toString();

              if (chunk != null && chunk.isNotEmpty) {
                chunkToYield = chunk;
              }

              if (h['done'] == true ||
                  status == 'done' ||
                  status == 'success') {
                if (chunkToYield != null) yield chunkToYield;
                receivedAnyChunk = true;
                break;
              }
            } else if (h is String) {
              chunkToYield = h;
            }
          } catch (_) {
            chunkToYield = '$line\n';
          }

          if (chunkToYield != null) {
            receivedAnyChunk = true;
            yield chunkToYield;
          }
        }
      } catch (e) {
        log('[AI DEBUG] Socket error with $pType to ${peer.ip}: $e');
      } finally {
        socket?.destroy();
      }

      if (receivedAnyChunk || explicitDisabled) {
        peer.isAiHost = true;
        notifyListeners();
        return;
      }
    }

    log('[AI DEBUG] Querying configured AiSettingsService engine...');
    final localAiResult = await AiSettingsService().queryAi(cleanPrompt);
    yield localAiResult;
  }

  Future<String> sendAiPrompt(Peer peer, String prompt) async {
    final buffer = StringBuffer();
    await for (final chunk in streamAiPrompt(peer, prompt)) {
      buffer.write(chunk);
    }
    final result = buffer.toString().trim();
    return result.isEmpty ? 'Nearby AI is not enabled on this device.' : result;
  }

  static String _sizeText(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  Future<void> _forwardMeshPacket(String peerIp, String packetJson) async {
    try {
      final socket = await Socket.connect(peerIp, transferPort,
          timeout: const Duration(seconds: 3));
      socket.write('$packetJson\n');
      await socket.flush();
      socket.destroy();
    } catch (_) {}
  }

  Future<bool> sendChat(Peer peer, String text) async {
    if (text.trim().isEmpty) return false;

    // 1. Direct TCP attempt if peer has IP and is not purely a mesh peer
    if (!peer.isMeshPeer && peer.ip.isNotEmpty) {
      for (var attempt = 1; attempt <= 2; attempt++) {
        Socket? socket;
        try {
          socket = await Socket.connect(peer.ip, transferPort,
              timeout: const Duration(seconds: 4));
          socket.write('${jsonEncode({
                'type': 'chat',
                'sender': deviceName,
                'sender_id': deviceId,
                'message': text.trim(),
              })}\n');
          await socket.flush();
          log('Direct message sent to ${peer.name}');
          return true;
        } catch (e) {
          log('Direct message attempt $attempt failed (${peer.ip}): $e');
          if (attempt == 2) break;
          await Future.delayed(const Duration(milliseconds: 250));
        } finally {
          socket?.destroy();
        }
      }
    }

    // 2. Mesh Relay Fallback: Broadcast packet through connected neighbors
    if (_meshRelayEnabled) {
      final msgId =
          '${deviceId}_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(99999)}';
      _seenMeshMsgIds.add(msgId);
      final meshPacket = jsonEncode({
        'type': 'mesh_relay',
        'msg_id': msgId,
        'origin_id': deviceId,
        'origin_name': deviceName,
        'target_id': peer.id,
        'ttl': 4,
        'hops': [deviceName],
        'payload': {
          'type': 'chat',
          'message': text.trim(),
        },
      });

      var relayedAny = false;
      for (final p in peers) {
        if (p.id != peer.id && p.ip.isNotEmpty && !p.isMeshPeer) {
          _forwardMeshPacket(p.ip, meshPacket);
          relayedAny = true;
        }
      }
      if (relayedAny) {
        log('[Mesh Relay] Dispatched multi-hop message for ${peer.name} (${peer.id})');
        return true;
      }
    }

    return false;
  }

  Future<bool> sendFile(Peer peer, File file,
      {bool folderArchive = false, String? displayName}) async {
    if (!await file.exists()) return false;
    final size = await file.length();
    final name = displayName ?? file.uri.pathSegments.last;

    for (var attempt = 1; attempt <= 2; attempt++) {
      Socket? socket;
      RandomAccessFile? raf;
      try {
        socket = await Socket.connect(peer.ip, transferPort,
            timeout: const Duration(seconds: 10));
        socket.write('${jsonEncode({
              'type': 'file',
              'sender': deviceName,
              'sender_id': deviceId,
              'name': name,
              'size': size,
              if (folderArchive) 'folder': true,
            })}\n');
        await socket.flush();
        raf = await file.open();
        var sent = 0;
        final watch = Stopwatch()..start();
        var previous = 0;
        var previousMs = 0;
        double speed = 0;
        _setTransfer(
            TransferState(active: true, label: 'Sending $name', progress: 0));
        while (sent < size) {
          final chunk =
              await raf.read((size - sent).clamp(1, 256 * 1024).toInt());
          if (chunk.isEmpty) break;
          socket.add(chunk);
          sent += chunk.length;
          final nowMs = watch.elapsedMilliseconds;
          if (nowMs - previousMs >= 100) {
            final deltaSec = (nowMs - previousMs) / 1000.0;
            final instant = (sent - previous) / deltaSec;
            speed = speed == 0 ? instant : speed * .72 + instant * .28;
            previous = sent;
            previousMs = nowMs;
          }
          final eta = speed > 0 ? ((size - sent) / speed).round() : null;
          _setTransfer(TransferState(
            active: true,
            label: 'Sending $name',
            progress: size == 0 ? 1 : sent / size,
            speedBytesPerSec: speed,
            etaSeconds: eta,
          ));
          if (sent % (1024 * 1024) < 256 * 1024) await socket.flush();
        }
        await socket.flush();
        _setTransfer(TransferState(label: 'Sent $name', progress: 1));
        log('Sent $name to ${peer.name}');
        return sent == size;
      } catch (e) {
        log('Transfer attempt $attempt failed: $e');
        if (attempt == 2) {
          _setTransfer(const TransferState(label: 'Transfer failed'));
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 300));
      } finally {
        await raf?.close();
        socket?.destroy();
      }
    }
    return false;
  }

  Future<bool> sendFolder(Peer peer, String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return false;

    final folderName = dir.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'Folder';
    final tempDir = await getTemporaryDirectory();
    final zipPath =
        '${tempDir.path}/${folderName}_${DateTime.now().millisecondsSinceEpoch}.zip';

    try {
      _setTransfer(TransferState(
          active: true, label: 'Compressing $folderName…', progress: 0));
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      await encoder.addDirectory(dir);
      encoder.close();

      final zipFile = File(zipPath);
      final ok = await sendFile(
        peer,
        zipFile,
        folderArchive: true,
        displayName: folderName,
      );

      try {
        if (await zipFile.exists()) {
          await zipFile.delete();
        }
      } catch (_) {}

      return ok;
    } catch (e) {
      log('Error creating/sending folder archive: $e');
      _setTransfer(const TransferState(label: 'Folder transfer failed'));
      return false;
    }
  }

  Peer _upsertPeer(String id, String name, String ip,
      {String? avatarEmoji, String? platform}) {
    String? resolvedAvatar = avatarEmoji;
    if (resolvedAvatar == null || resolvedAvatar.trim().isEmpty) {
      final trimmed = name.trim();
      if (trimmed.isNotEmpty) {
        final firstRune = trimmed.runes.first;
        if ((firstRune >= 0x1F300 && firstRune <= 0x1F9FF) ||
            (firstRune >= 0x2600 && firstRune <= 0x27BF) ||
            (firstRune >= 0x1FA70 && firstRune <= 0x1FAFF) ||
            (firstRune >= 0xFE00 && firstRune <= 0xFE0F) ||
            (firstRune >= 0x1F000 && firstRune <= 0x1F2FF)) {
          resolvedAvatar = String.fromCharCode(firstRune);
        }
      }
    }

    if (id == deviceId ||
        name.toLowerCase() == deviceName.toLowerCase() ||
        id == 'local_ai_assistant') {
      return Peer(
          id: id,
          name: name,
          ip: ip,
          avatarEmoji: resolvedAvatar,
          platform: platform);
    }

    Peer? existing = _peers[id];
    if (existing == null && ip.isNotEmpty) {
      existing = _peers[ip];
    }
    if (existing == null) {
      for (final p in _peers.values) {
        if ((id.isNotEmpty && p.id == id) ||
            (ip.isNotEmpty && p.ip == ip) ||
            (name.isNotEmpty && p.name == name)) {
          existing = p;
          break;
        }
      }
    }

    if (existing == null) {
      final p = Peer(
          id: id.isNotEmpty
              ? id
              : (ip.isNotEmpty
                  ? ip
                  : 'peer_${DateTime.now().millisecondsSinceEpoch}'),
          name: name,
          ip: ip,
          avatarEmoji: resolvedAvatar,
          platform: platform);
      _peers[p.id] = p;
      if (id.isNotEmpty) _peers[id] = p;
      if (ip.isNotEmpty) _peers[ip] = p;
      existing = p;
      log('Discovered $name ($ip)');
    } else {
      existing
        ..name = name.isNotEmpty ? name : existing.name
        ..ip = ip.isNotEmpty ? ip : existing.ip
        ..avatarEmoji = resolvedAvatar ?? existing.avatarEmoji
        ..platform = platform ?? existing.platform
        ..lastSeen = DateTime.now();
      _peers[existing.id] = existing;
      if (id.isNotEmpty) _peers[id] = existing;
      if (ip.isNotEmpty) _peers[ip] = existing;
    }
    notifyListeners();
    final targetPeer = existing;
    if (targetPeer.ip.isNotEmpty &&
        targetPeer.ip != '0.0.0.0' &&
        !targetPeer.ip.startsWith('127.')) {
      Future.microtask(() => flushQueueForPeer(targetPeer));
    }
    return targetPeer;
  }

  Future<String?> _findLocalIpv4() async {
    final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final ip = address.address;
        if (_isPrivateIpv4(ip)) return ip;
      }
    }
    return null;
  }

  bool _isPrivateIpv4(String ip) {
    final p = ip.split('.').map(int.tryParse).toList();
    if (p.length != 4 || p.any((e) => e == null)) return false;
    final a = p[0]!;
    final b = p[1]!;
    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }

  Future<String?> getLocalIp() => _findLocalIpv4();

  Future<Directory> getReceiveDirectory() => _receiveDirectory();

  Future<Directory> _receiveDirectory() async {
    if (_customSavePath != null && _customSavePath!.trim().isNotEmpty) {
      final customDir = Directory(_customSavePath!.trim());
      try {
        if (!await customDir.exists()) {
          await customDir.create(recursive: true);
        }
        return customDir;
      } catch (e) {
        log('Error accessing custom save directory ($e)');
      }
    }

    if (Platform.isAndroid) {
      final pubDownload =
          Directory('/storage/emulated/0/Download/NearMitra');
      try {
        if (!await pubDownload.exists()) {
          await pubDownload.create(recursive: true);
        }
        return pubDownload;
      } catch (_) {}
    }

    final external = await getExternalStorageDirectory();
    final base = external ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/NearMitra');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> _uniquePath(String path) async {
    var candidate = path;
    final dot = path.lastIndexOf('.');
    final base = dot > path.lastIndexOf('/') ? path.substring(0, dot) : path;
    final ext = dot > path.lastIndexOf('/') ? path.substring(dot) : '';
    var i = 1;
    while (await File(candidate).exists()) {
      candidate = '$base ($i)$ext';
      i++;
    }
    return candidate;
  }

  String _safeFileName(String input) {
    final normalized = input.replaceAll('\\', '/');
    final last = normalized.split('/').last.trim();
    return last.isEmpty || last == '.' || last == '..' ? 'received_file' : last;
  }

  Future<String?> _readLine(Socket socket,
      {Duration timeout = const Duration(seconds: 3)}) async {
    final reader = _SocketReader(socket);
    return reader.readLine().timeout(timeout, onTimeout: () => null);
  }

  void _setTransfer(TransferState value) {
    _transfer = value;
    notifyListeners();
  }

  void log(String message) {
    final now = DateTime.now();
    final stamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    _logs.add('$stamp  $message');
    if (_logs.length > 160) _logs.removeRange(0, _logs.length - 160);
    notifyListeners();
  }
}

class _SocketReader {
  _SocketReader(this.socket) {
    _subscription = socket.listen(
      _onData,
      onError: (Object e, StackTrace s) {
        _error = e;
        _done = true;
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
      cancelOnError: false,
    );
  }

  final Socket socket;
  late final StreamSubscription<Uint8List> _subscription;
  final List<int> _buffer = [];
  Completer<void>? _waiter;
  bool _done = false;
  Object? _error;

  Future<void> cancel() async {
    await _subscription.cancel();
  }

  void _onData(Uint8List data) {
    _buffer.addAll(data);
    _wake();
  }

  void _wake() {
    if (_waiter != null && !_waiter!.isCompleted) _waiter!.complete();
    _waiter = null;
  }

  Future<void> _wait() async {
    if (_buffer.isNotEmpty || _done) return;
    _waiter ??= Completer<void>();
    await _waiter!.future;
    if (_error != null) throw _error!;
  }

  Future<String?> readLine() async {
    while (true) {
      final i = _buffer.indexOf(10);
      if (i >= 0) {
        final bytes = _buffer.sublist(0, i);
        _buffer.removeRange(0, i + 1);
        return utf8.decode(bytes).trimRight();
      }
      if (_done) {
        if (_buffer.isEmpty) return null;
        final bytes = List<int>.from(_buffer);
        _buffer.clear();
        return utf8.decode(bytes).trimRight();
      }
      await _wait();
    }
  }

  Future<List<int>> readBytes(int maxBytes) async {
    while (_buffer.isEmpty && !_done) {
      await _wait();
    }
    if (_buffer.isEmpty) return const [];
    final count = _buffer.length < maxBytes ? _buffer.length : maxBytes;
    final out = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return out;
  }
}
