import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chat_item.dart';
import '../models/peer.dart';
import '../models/transfer_state.dart';
import 'android_network_bridge.dart';
import 'notification_service.dart';

class NearbyService extends ChangeNotifier {
  NearbyService({required this.deviceId, required this.deviceName});

  static const int discoveryPort = 43888;
  static const int transferPort = 43889;
  static final InternetAddress multicastAddress = InternetAddress('239.255.43.88');

  final String deviceId;
  final String deviceName;
  final AndroidNetworkBridge _bridge = AndroidNetworkBridge();
  final NotificationService _notificationService = NotificationService();

  String? customSavePath;
  bool notificationsEnabled = true;

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
    final list = _peers.values.toList();
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

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _bridge.acquireMulticastLock();
    await _startTransferServer();
    await _startDiscovery();
    _announceTimer = Timer.periodic(const Duration(seconds: 3), (_) => announce());
    _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _peers.removeWhere((_, p) => DateTime.now().difference(p.lastSeen).inSeconds > 120);
      notifyListeners();
    });
    _keepaliveTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pingPeers());
    announce();
    log('Farmitra Nearby is ready on local network');
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
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: false,
      );
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
      final map = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
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

  Future<void> _probe(String ip) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, transferPort, timeout: const Duration(milliseconds: 600));
      socket.write('${jsonEncode({'type': 'hello', 'sender': deviceName, 'sender_id': deviceId})}\n');
      await socket.flush();
      final line = await _readLine(socket, timeout: const Duration(milliseconds: 800));
      if (line == null) return;
      final map = jsonDecode(line) as Map<String, dynamic>;
      if (map['type'] == 'hello') {
        final id = map['sender_id']?.toString() ?? '';
        if (id != deviceId) {
          _upsertPeer(id.isNotEmpty ? id : ip, map['sender']?.toString() ?? 'Nearby device', ip);
        }
      }
    } catch (_) {
      // A closed port is expected for most addresses.
    } finally {
      socket?.destroy();
    }
  }

  Future<void> _startTransferServer() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, transferPort, shared: true);
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
      if (remoteIp.isNotEmpty) p.ip = remoteIp;
      if (senderName.isNotEmpty) p.name = senderName;
      return senderId;
    }
    for (final p in _peers.values) {
      if (p.ip == remoteIp || (senderId.isNotEmpty && p.id == senderId) || p.name == senderName) {
        p.lastSeen = DateTime.now();
        if (remoteIp.isNotEmpty) p.ip = remoteIp;
        return p.id;
      }
    }
    final idToUse = senderId.isNotEmpty ? senderId : (remoteIp.isNotEmpty ? remoteIp : 'peer_${DateTime.now().millisecondsSinceEpoch}');
    _upsertPeer(idToUse, senderName.isNotEmpty ? senderName : 'Nearby device', remoteIp);
    return idToUse;
  }

  Future<void> _handleConnection(Socket socket) async {
    final reader = _SocketReader(socket);
    try {
      final line = await reader.readLine();
      if (line == null) return;
      final h = jsonDecode(line) as Map<String, dynamic>;
      final type = h['type']?.toString();
      final sender = h['sender']?.toString() ?? 'Nearby device';
      final senderId = h['sender_id']?.toString() ?? '';
      final remoteIp = socket.remoteAddress.address;
      final resolvedPeerId = _resolvePeerId(senderId, sender, remoteIp);

      if (type == 'hello') {
        socket.write('${jsonEncode({'type': 'hello', 'sender': deviceName, 'sender_id': deviceId})}\n');
        await socket.flush();
        return;
      }

      final isAiPacket = type == 'ai_response' ||
          type == 'ai_chat' ||
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
        final finalMessage = (status == 'disabled' || h['error_code'] == 'ai_disabled')
            ? 'Nearby AI is not enabled on this device.'
            : (status == 'error' || h.containsKey('error')
                ? (h['error']?.toString() ?? responseText)
                : responseText);

        if (finalMessage.isNotEmpty) {
          if (_peers.containsKey(resolvedPeerId)) {
            _peers[resolvedPeerId]!.unreadCount++;
            _peers[resolvedPeerId]!.isAiHost = true;
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

      if (type == 'typing') {
        final isTyping = h['is_typing'] == true;
        if (_peers.containsKey(resolvedPeerId)) {
          final p = _peers[resolvedPeerId]!;
          p.isTyping = isTyping;
          p.typingTimer?.cancel();
          if (isTyping) {
            p.typingTimer = Timer(const Duration(milliseconds: 2500), () {
              p.isTyping = false;
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
          if (_peers.containsKey(resolvedPeerId)) {
            _peers[resolvedPeerId]!.unreadCount++;
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
          if (notificationsEnabled) {
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
        _setTransfer(TransferState(active: true, label: 'Receiving $name', progress: 0));
        while (received < size) {
          final chunk = await reader.readBytes((size - received).clamp(1, 256 * 1024).toInt());
          if (chunk.isEmpty) throw const SocketException('Connection closed during transfer');
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
        _setTransfer(TransferState(label: 'Received $name', progress: 1));
        if (_peers.containsKey(resolvedPeerId)) {
          _peers[resolvedPeerId]!.unreadCount++;
        }
        _incomingItems.add(ChatItem(
          peerId: resolvedPeerId,
          sender: sender,
          mine: false,
          createdAt: DateTime.now(),
          kind: folder ? ChatKind.folder : ChatKind.file,
          fileName: name,
          filePath: path,
          fileSize: size,
          status: 'Received',
        ));
        log('Received $name from $sender');
        if (notificationsEnabled) {
          _notificationService.showIncomingFileNotification(
            peerId: resolvedPeerId,
            senderName: sender,
            fileName: name,
            fileSizeText: _sizeText(size),
          );
        }
        notifyListeners();
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
      final socket = await Socket.connect(peer.ip, transferPort, timeout: const Duration(milliseconds: 1500));
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
        socket = await Socket.connect(peer.ip, transferPort, timeout: const Duration(seconds: 8));
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
          final line = await reader.readLine().timeout(const Duration(seconds: 45), onTimeout: () => null);
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

              if (status == 'error' || h.containsKey('error') || h.containsKey('err')) {
                final errText = h['error']?.toString() ?? h['err']?.toString() ?? h['message']?.toString() ?? 'AI processing error';
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

              if (h['done'] == true || status == 'done' || status == 'success') {
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

    log('[AI DEBUG] AI error response: Unable to reach AI host on ${peer.ip}');
    yield 'Nearby AI is not enabled on this device.';
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

  Future<bool> sendChat(Peer peer, String text) async {
    if (text.trim().isEmpty) return false;
    for (var attempt = 1; attempt <= 2; attempt++) {
      Socket? socket;
      try {
        socket = await Socket.connect(peer.ip, transferPort, timeout: const Duration(seconds: 10));
        socket.write('${jsonEncode({
          'type': 'chat',
          'sender': deviceName,
          'sender_id': deviceId,
          'message': text.trim(),
        })}\n');
        await socket.flush();
        log('Message sent to ${peer.name}');
        return true;
      } catch (e) {
        log('Message attempt $attempt failed ($peer.ip): $e');
        if (attempt == 2) return false;
        await Future.delayed(const Duration(milliseconds: 300));
      } finally {
        socket?.destroy();
      }
    }
    return false;
  }

  Future<bool> sendFile(Peer peer, File file, {bool folderArchive = false, String? displayName}) async {
    if (!await file.exists()) return false;
    final size = await file.length();
    final name = displayName ?? file.uri.pathSegments.last;

    for (var attempt = 1; attempt <= 2; attempt++) {
      Socket? socket;
      RandomAccessFile? raf;
      try {
        socket = await Socket.connect(peer.ip, transferPort, timeout: const Duration(seconds: 10));
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
        _setTransfer(TransferState(active: true, label: 'Sending $name', progress: 0));
        while (sent < size) {
          final chunk = await raf.read((size - sent).clamp(1, 256 * 1024).toInt());
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

  void _upsertPeer(String id, String name, String ip) {
    final existing = _peers[id];
    if (existing == null) {
      _peers[id] = Peer(id: id, name: name, ip: ip);
      log('Discovered $name ($ip)');
    } else {
      existing
        ..name = name
        ..ip = ip
        ..lastSeen = DateTime.now();
      notifyListeners();
    }
  }

  Future<String?> _findLocalIpv4() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
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
    return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
  }

  Future<Directory> getReceiveDirectory() => _receiveDirectory();

  Future<Directory> _receiveDirectory() async {
    final external = await getExternalStorageDirectory();
    final base = external ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/Farmitra Nearby');
    await dir.create(recursive: true);
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

  Future<String?> _readLine(Socket socket, {Duration timeout = const Duration(seconds: 3)}) async {
    final reader = _SocketReader(socket);
    return reader.readLine().timeout(timeout, onTimeout: () => null);
  }

  void _setTransfer(TransferState value) {
    _transfer = value;
    notifyListeners();
  }

  void log(String message) {
    final now = DateTime.now();
    final stamp = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
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
