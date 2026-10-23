/// REST desktop presence is a heartbeat lease; mobile SDK presence continues
/// using its existing Firebase onDisconnect hook.
class WanPresence {
  static const desktopLeaseMs = 75000;

  static DateTime? timestamp(dynamic value) {
    final millis = value is num ? value.toInt() : int.tryParse('$value');
    if (millis == null || millis <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  static int? lease(String platform, dynamic declared) {
    if (declared is num && declared > 0) {
      return declared.toInt().clamp(30000, 120000);
    }
    // Also expire records left behind by older Windows releases.
    return platform.toLowerCase() == 'windows' ? desktopLeaseMs : null;
  }

  static bool isAlive({
    required bool online,
    required String platform,
    required DateTime? lastSeen,
    int? leaseMs,
    required DateTime now,
  }) {
    if (!online) return false;
    final ttl = lease(platform, leaseMs);
    if (ttl == null) return true;
    if (lastSeen == null) return false;
    final age = now.difference(lastSeen).inMilliseconds;
    return age >= -15000 && age < ttl;
  }
}
