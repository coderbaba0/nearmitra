import 'dart:convert';

class NotificationTarget {
  const NotificationTarget(this.peerId, {this.nonce});
  final String peerId;
  final String? nonce;

  String encode() => jsonEncode({'v': 1, 'peerId': peerId, 'nonce': nonce});
  factory NotificationTarget.decode(String payload) {
    try {
      final value = jsonDecode(payload);
      if (value is Map &&
          value['v'] == 1 &&
          value['peerId'] is String &&
          (value['peerId'] as String).trim().isNotEmpty) {
        return NotificationTarget(value['peerId'] as String,
            nonce: value['nonce'] is String ? value['nonce'] as String : null);
      }
    } catch (_) {}
    // Notifications displayed by earlier APKs carried just the recipient ID.
    return NotificationTarget(payload);
  }
}
