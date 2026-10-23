import 'package:flutter_test/flutter_test.dart';
import 'package:farmitra_nearby/models/wan_models.dart';
import 'package:farmitra_nearby/models/wan_presence.dart';

void main() {
  final now = DateTime.utc(2026, 10, 17, 12);
  Map<String, dynamic> presence(
          {String platform = 'windows', bool online = true, DateTime? seen}) =>
      {
        'platform': platform,
        'online': online,
        if (seen != null) 'lastSeen': seen.millisecondsSinceEpoch,
        'deviceName': 'Desktop',
      };
  test(
      'Windows heartbeat is online while fresh and expires without a new snapshot',
      () {
    final device = WanDevice.fromMap('pc', presence(seen: now),
        now: now, isTrusted: true, unreadCount: 3);
    expect(device.isOnline, isTrue);
    expect(device.presenceAt(now.add(const Duration(seconds: 74))).isOnline,
        isTrue);
    final expired = device.presenceAt(now.add(const Duration(seconds: 75)));
    expect(expired.isOnline, isFalse);
    expect(expired.isTrusted, isTrue);
    expect(expired.unreadCount, 3);
  });
  test('A record left by a powered-off older Windows build is offline', () {
    expect(
        WanDevice.fromMap(
                'pc', presence(seen: now.subtract(const Duration(days: 2))),
                now: now)
            .isOnline,
        isFalse);
  });
  test(
      'Explicit Windows offline is immediate and a later heartbeat restores online',
      () {
    expect(
        WanDevice.fromMap('pc', presence(online: false, seen: now), now: now)
            .isOnline,
        isFalse);
    expect(WanDevice.fromMap('pc', presence(seen: now), now: now).isOnline,
        isTrue);
  });
  test('Windows missing or invalid timestamps never claim online', () {
    expect(WanDevice.fromMap('pc', presence(), now: now).isOnline, isFalse);
    expect(
        WanDevice.fromMap(
                'pc',
                {
                  ...presence(),
                  'lastSeen': {'.sv': 'timestamp'}
                },
                now: now)
            .isOnline,
        isFalse);
    expect(
        WanDevice.fromMap(
                'pc', presence(seen: now.add(const Duration(days: 1))),
                now: now)
            .isOnline,
        isFalse);
  });
  test('Existing mobile-to-mobile SDK presence keeps onDisconnect semantics',
      () {
    final old = presence(
        platform: 'android', seen: now.subtract(const Duration(days: 1)));
    expect(WanDevice.fromMap('phone', old, now: now).isOnline, isTrue);
    expect(
        WanDevice.fromMap('phone', {...old, 'online': false}, now: now)
            .isOnline,
        isFalse);
  });
  test(
      'Server-adjusted time controls the lease despite an incorrect phone clock',
      () {
    final data = presence(seen: now);
    final wrongClock = now.add(const Duration(hours: 4));
    expect(WanDevice.fromMap('pc', data, now: wrongClock).isOnline, isFalse);
    expect(
        WanDevice.fromMap('pc', data,
                now: wrongClock.subtract(const Duration(hours: 4)))
            .isOnline,
        isTrue);
  });
  test(
      'Lease metadata survives copies and numeric Firebase timestamps parse safely',
      () {
    final data = {
      ...presence(seen: now),
      'presenceLeaseMs': 45000,
      'lastSeen': now.millisecondsSinceEpoch.toDouble()
    };
    final device =
        WanDevice.fromMap('pc', data, now: now).copyWith(unreadCount: 2);
    expect(device.presenceLeaseMs, 45000);
    expect(device.presenceAt(now.add(const Duration(seconds: 46))).isOnline,
        isFalse);
    expect(WanPresence.lease('windows', 99999999), 120000);
  });
}
