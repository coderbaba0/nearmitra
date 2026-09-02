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
import 'notification_service.dart';

class NearbyService extends ChangeNotifier {
  static NearbyService? _instance;
  static NearbyService get instance => _instance!;

  NearbyService({required this.deviceId, required this.deviceName}) {
    _instance = this;
  }

  static const int discoveryPort = 43888;
  static const int transferPort = 43889;
  static final InternetAddress multicastAddress =
      InternetAddress('239.255.43.88');

  final String deviceId;
  final String deviceName;
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

  final List<ChatItem> _incomingItems = [];
  final List<String> _logs = [];
  TransferState _transfer = const TransferState();

  RawDatagramSocket? _udp;
  ServerSocket? _server;
  Timer? _announceTimer;
  Timer? _cleanupTimer;
  Timer? _keepaliveTimer;
  bool _started = false;

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
    list.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return list;
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

  Future<void> sendCallInvite(Peer peer, bool isVideoCall) async {
    try {
      final socket = await Socket.connect(peer.ip, transferPort,
          timeout: const Duration(seconds: 3));
      final payload = jsonEncode({
        'type': 'call_invite',
        'sender': deviceName,
        'sender_id': deviceId,
        'is_video': isVideoCall,
      });
      socket.write('$payload\n');
      await socket.flush();
      socket.destroy();
    } catch (e) {
      log('Error sending call invite to ${peer.name}: $e');
    }
  }

  Future<void> sendCallSignal(Peer peer, String signalType,
      {bool? isVideo}) async {
    try {
      final socket = await Socket.connect(peer.ip, transferPort,
          timeout: const Duration(seconds: 3));
      final payload = jsonEncode({
        'type': signalType,
        'sender': deviceName,
        'sender_id': deviceId,
        if (isVideo != null) 'is_video': isVideo,
      });
      socket.write('$payload\n');
      await socket.flush();
      socket.destroy();
    } catch (e) {
      log('Error sending call signal $signalType to ${peer.name}: $e');
    }
  }

  Future<void> sendWebRtcSignal(
    Peer peer,
    String signalType,
    Map<String, dynamic> data,
  ) async {
    try {
      final socket = await Socket.connect(peer.ip, transferPort,
          timeout: const Duration(seconds: 3));
      final payload = jsonEncode({
        'type': signalType,
        'sender': deviceName,
        'sender_id': deviceId,
        ...data,
      });
      socket.write('$payload\n');
      await socket.flush();
      socket.destroy();
    } catch (e) {
      log('Error sending WebRTC signal $signalType to ${peer.name}: $e');
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
      if (id.isEmpty || id == deviceId) return;
      _upsertPeer(id, name, datagram.address.address);
    } catch (_) {}
  }

  Future<void> announce() async {
    if (_udp == null) {
      await _startDiscovery();
    }
    final data = utf8.encode(jsonEncode({'id': deviceId, 'name': deviceName}));
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
            'sender_id': deviceId
          })}\n');
      await socket.flush();
      final line =
          await _readLine(socket, timeout: const Duration(milliseconds: 3000));
      if (line == null) return null;
      final map = jsonDecode(line) as Map<String, dynamic>;
      if (map['type'] == 'hello') {
        final id = map['sender_id']?.toString() ?? '';
        final peerId = id.isNotEmpty ? id : ip;
        if (id != deviceId) {
          _upsertPeer(peerId, map['sender']?.toString() ?? 'Nearby device', ip);
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
      final remoteIp = socket.remoteAddress.address;
      final resolvedPeerId = _resolvePeerId(senderId, sender, remoteIp);

      if (type == 'hello') {
        socket.write('${jsonEncode({
              'type': 'hello',
              'sender': deviceName,
              'sender_id': deviceId
            })}\n');
        await socket.flush();
        // Do NOT auto-open chat here — incoming hello is from ANY LAN device probing us
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
        onStreamOffer?.call(resolvedPeerId, Map<String, dynamic>.from(h));
        return;
      }

      if (type == 'stream_answer') {
        onStreamAnswer?.call(resolvedPeerId, Map<String, dynamic>.from(h));
        return;
      }

      if (type == 'stream_ice') {
        onStreamIceCandidate?.call(
            resolvedPeerId, Map<String, dynamic>.from(h));
        return;
      }

      if (type == 'stream_control') {
        onStreamControl?.call(resolvedPeerId, Map<String, dynamic>.from(h));
        return;
      }

      if (type == 'stream_rejected') {
        onStreamRejected?.call(resolvedPeerId, Map<String, dynamic>.from(h));
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

  Peer _upsertPeer(String id, String name, String ip) {
    if (id == deviceId ||
        name.toLowerCase() == deviceName.toLowerCase() ||
        id == 'local_ai_assistant') {
      return Peer(id: id, name: name, ip: ip);
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
          ip: ip);
      _peers[p.id] = p;
      if (id.isNotEmpty) _peers[id] = p;
      if (ip.isNotEmpty) _peers[ip] = p;
      existing = p;
      log('Discovered $name ($ip)');
    } else {
      existing
        ..name = name.isNotEmpty ? name : existing.name
        ..ip = ip.isNotEmpty ? ip : existing.ip
        ..lastSeen = DateTime.now();
      _peers[existing.id] = existing;
      if (id.isNotEmpty) _peers[id] = existing;
      if (ip.isNotEmpty) _peers[ip] = existing;
    }
    notifyListeners();
    return existing;
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
