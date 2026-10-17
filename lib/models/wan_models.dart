import 'dart:convert';
import 'package:uuid/uuid.dart';

enum WanDiscoveryMode {
  publicRadar,
  privateGhost,
  pinOnly,
}

enum WanConnectionState {
  offline,
  online,
  connecting,
  signaling,
  negotiating,
  connected,
  disconnected,
  failed,
}

class WanDevice {
  final String id;
  final String name;
  final String platform;
  final String? avatarEmoji;
  final bool isOnline;
  final DateTime? lastSeen;
  final bool isTrusted;
  final int unreadCount;

  WanDevice({
    required this.id,
    required this.name,
    required this.platform,
    this.avatarEmoji,
    required this.isOnline,
    this.lastSeen,
    this.isTrusted = false,
    this.unreadCount = 0,
  });

  factory WanDevice.fromMap(String id, Map<dynamic, dynamic> map,
      {bool isTrusted = false, int unreadCount = 0}) {
    return WanDevice(
      id: id,
      name: (map['name'] as String?) ??
          (map['deviceName'] as String?) ??
          'Unknown Device',
      platform: (map['platform'] as String?) ?? 'unknown',
      avatarEmoji: (map['avatarEmoji'] as String?) ?? (map['emoji'] as String?),
      isOnline: (map['online'] as bool?) ?? false,
      lastSeen: map['lastSeen'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastSeen'] as int)
          : null,
      isTrusted: isTrusted,
      unreadCount: unreadCount,
    );
  }

  Map<String, dynamic> toPresenceMap() {
    return {
      'name': name,
      'platform': platform,
      if (avatarEmoji != null && avatarEmoji!.isNotEmpty)
        'avatarEmoji': avatarEmoji,
      'online': isOnline,
      'lastSeen': DateTime.now().millisecondsSinceEpoch,
    };
  }

  WanDevice copyWith({
    String? id,
    String? name,
    String? platform,
    String? avatarEmoji,
    bool? isOnline,
    DateTime? lastSeen,
    bool? isTrusted,
    int? unreadCount,
  }) {
    return WanDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      isTrusted: isTrusted ?? this.isTrusted,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

class WanPairCode {
  final String code;
  final String ownerDeviceId;
  final String ownerName;
  final String ownerPlatform;
  final int expiresAt;

  WanPairCode({
    required this.code,
    required this.ownerDeviceId,
    required this.ownerName,
    required this.ownerPlatform,
    required this.expiresAt,
  });

  factory WanPairCode.fromMap(String code, Map<dynamic, dynamic> map) {
    return WanPairCode(
      code: code,
      ownerDeviceId: (map['ownerDeviceId'] as String?) ?? '',
      ownerName: (map['ownerName'] as String?) ?? 'NearMitra Peer',
      ownerPlatform: (map['ownerPlatform'] as String?) ?? 'unknown',
      expiresAt: (map['expiresAt'] as int?) ?? 0,
    );
  }

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAt;
}

class WanPairRequest {
  final String requestId;
  final String fromDeviceId;
  final String fromDeviceName;
  final String fromPlatform;
  final String toDeviceId;
  final String code;
  final String status; // 'pending', 'accepted', 'rejected'
  final bool isDirectRadar;
  final String? fromAvatarEmoji;
  final DateTime? createdAt;

  WanPairRequest({
    required this.requestId,
    required this.fromDeviceId,
    required this.fromDeviceName,
    required this.fromPlatform,
    this.fromAvatarEmoji,
    required this.toDeviceId,
    required this.code,
    this.status = 'pending',
    this.isDirectRadar = false,
    this.createdAt,
  });

  factory WanPairRequest.fromMap(String requestId, Map<dynamic, dynamic> map) {
    return WanPairRequest(
      requestId: requestId,
      fromDeviceId: (map['fromDeviceId'] as String?) ?? '',
      fromDeviceName: (map['fromDeviceName'] as String?) ?? 'NearMitra Peer',
      fromPlatform: (map['fromPlatform'] as String?) ?? 'unknown',
      fromAvatarEmoji: (map['fromAvatarEmoji'] as String?) ??
          (map['avatarEmoji'] as String?),
      toDeviceId: (map['toDeviceId'] as String?) ?? '',
      code: (map['code'] as String?) ?? '',
      status: (map['status'] as String?) ?? 'pending',
      isDirectRadar: (map['isDirectRadar'] as bool?) ?? false,
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'requestId': requestId,
      'fromDeviceId': fromDeviceId,
      'fromDeviceName': fromDeviceName,
      'fromPlatform': fromPlatform,
      if (fromAvatarEmoji != null && fromAvatarEmoji!.isNotEmpty)
        'fromAvatarEmoji': fromAvatarEmoji,
      'toDeviceId': toDeviceId,
      'code': code,
      'status': status,
      'isDirectRadar': isDirectRadar,
    };
  }
}

class WanSignalingSession {
  final String sessionId;
  final String callerId;
  final String callerName;
  final String callerPlatform;
  final String receiverId;
  final String status;
  final int createdAt;
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;

  WanSignalingSession({
    required this.sessionId,
    required this.callerId,
    required this.callerName,
    required this.callerPlatform,
    required this.receiverId,
    required this.status,
    required this.createdAt,
    this.offer,
    this.answer,
  });

  factory WanSignalingSession.fromMap(
      String sessionId, Map<dynamic, dynamic> map) {
    return WanSignalingSession(
      sessionId: sessionId,
      callerId: (map['callerId'] as String?) ?? '',
      callerName: (map['callerName'] as String?) ?? 'Remote Peer',
      callerPlatform: (map['callerPlatform'] as String?) ?? 'unknown',
      receiverId: (map['receiverId'] as String?) ?? '',
      status: (map['status'] as String?) ?? 'calling',
      createdAt: (map['createdAt'] is num)
          ? (map['createdAt'] as num).toInt()
          : DateTime.now().millisecondsSinceEpoch,
      offer: map['offer'] != null
          ? Map<String, dynamic>.from(map['offer'] as Map)
          : null,
      answer: map['answer'] != null
          ? Map<String, dynamic>.from(map['answer'] as Map)
          : null,
    );
  }

  bool get isExpired {
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = now - createdAt;
    // Allow up to 90 seconds, and tolerate up to 30s negative clock drift
    return diff > 90000 || diff < -30000;
  }
}

class WanFileTransferProgress {
  final String fileId;
  final String fileName;
  final int totalBytes;
  final int bytesTransferred;
  final double speedMBps;
  final int etaSeconds;
  final bool isSender;
  final bool isCompleted;
  final bool isCancelled;
  final String? filePath;

  WanFileTransferProgress({
    required this.fileId,
    required this.fileName,
    required this.totalBytes,
    required this.bytesTransferred,
    required this.speedMBps,
    required this.etaSeconds,
    required this.isSender,
    this.isCompleted = false,
    this.isCancelled = false,
    this.filePath,
  });

  double get progressPercentage =>
      totalBytes > 0 ? (bytesTransferred / totalBytes).clamp(0.0, 1.0) : 0.0;
}

/// RTCDataChannel Message Framing Protocol
enum WanDataMessageType {
  text,
  control,
  fileMeta,
  fileChunk,
  fileEnd,
  fileCancel,
  ping,
  pong,
  unknown,
}

class WanDataMessage {
  final String id;
  final WanDataMessageType type;
  final int timestamp;
  final Map<String, dynamic>? payload;

  WanDataMessage({
    String? id,
    required this.type,
    int? timestamp,
    this.payload,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  static WanDataMessage text(
    String text, {
    String? id,
    String? replyToId,
    String? replyToSender,
    String? replyToText,
    bool isForwarded = false,
  }) {
    return WanDataMessage(
      id: id,
      type: WanDataMessageType.text,
      payload: {
        'text': text,
        if (replyToId != null) 'replyToId': replyToId,
        if (replyToSender != null) 'replyToSender': replyToSender,
        if (replyToText != null) 'replyToText': replyToText,
        if (isForwarded) 'isForwarded': true,
      },
    );
  }

  static WanDataMessage control(String action, [Map<String, dynamic>? extra]) {
    return WanDataMessage(
      type: WanDataMessageType.control,
      payload: {
        'action': action,
        ...?extra,
      },
    );
  }

  static WanDataMessage fileMeta({
    required String fileId,
    required String fileName,
    required int fileSize,
    required String mimeType,
    required int chunkSize,
    required int totalChunks,
    String? checksum,
    bool folder = false,
  }) {
    return WanDataMessage(
      type: WanDataMessageType.fileMeta,
      payload: {
        'transferId': fileId,
        if (folder) 'folder': true,
        'fileName': fileName,
        'fileSize': fileSize,
        'mimeType': mimeType,
        'chunkSize': chunkSize,
        'totalChunks': totalChunks,
        'checksum': checksum ?? '',
      },
    );
  }

  static WanDataMessage fileEnd({required String fileId, String? checksum}) {
    return WanDataMessage(
      type: WanDataMessageType.fileEnd,
      payload: {
        'transferId': fileId,
        'checksum': checksum ?? '',
      },
    );
  }

  static WanDataMessage fileCancel(
      {required String fileId, required String reason}) {
    return WanDataMessage(
      type: WanDataMessageType.fileCancel,
      payload: {
        'transferId': fileId,
        'reason': reason,
      },
    );
  }

  static WanDataMessage ping() => WanDataMessage(type: WanDataMessageType.ping);
  static WanDataMessage pong() => WanDataMessage(type: WanDataMessageType.pong);

  String toJsonString() {
    return jsonEncode({
      'protocolVersion': 1,
      'id': id,
      'type': type.name.toUpperCase(),
      'timestamp': timestamp,
      'payload': payload ?? {},
    });
  }

  static WanDataMessage fromJsonString(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final typeStr = (map['type'] as String? ?? 'unknown').toLowerCase();
      final id = map['id'] as String? ?? const Uuid().v4();
      final timestamp =
          (map['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
      final payload = map['payload'] as Map<String, dynamic>?;

      final type = WanDataMessageType.values.firstWhere(
        (e) => e.name.toLowerCase() == typeStr,
        orElse: () => WanDataMessageType.unknown,
      );

      return WanDataMessage(
        id: id,
        type: type,
        timestamp: timestamp,
        payload: payload,
      );
    } catch (_) {
      return WanDataMessage(type: WanDataMessageType.unknown);
    }
  }
}
