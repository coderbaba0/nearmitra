import 'dart:async';

class Peer {
  Peer({
    required this.id,
    required this.name,
    required this.ip,
    DateTime? lastSeen,
    this.unreadCount = 0,
    this.isTyping = false,
    this.isAiHost = false,
  }) : lastSeen = lastSeen ?? DateTime.now();

  final String id;
  String name;
  String ip;
  DateTime lastSeen;
  int unreadCount;
  bool isTyping;
  bool isAiHost;
  Timer? typingTimer;

  bool get isOnline => DateTime.now().difference(lastSeen).inSeconds < 15;
}
