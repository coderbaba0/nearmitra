import 'dart:async';

class Peer {
  Peer({
    required this.id,
    required this.name,
    required this.ip,
    this.avatarEmoji,
    this.platform,
    DateTime? lastSeen,
    this.unreadCount = 0,
    this.isTyping = false,
    this.isAiHost = false,
    this.isAiHostAllowed = true,
    this.isMeshPeer = false,
    this.relayViaName,
  }) : lastSeen = lastSeen ?? DateTime.now();

  final String id;
  String name;
  String ip;
  String? avatarEmoji;
  String? platform;
  DateTime lastSeen;
  int unreadCount;
  bool isTyping;
  bool isAiHost;
  bool isAiHostAllowed;
  bool isMeshPeer;
  String? relayViaName;
  Timer? typingTimer;

  bool get isOnline => DateTime.now().difference(lastSeen).inSeconds < 25;
}
