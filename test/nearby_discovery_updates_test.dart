import 'dart:convert';

import 'package:farmitra_nearby/services/nearby_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Repeated heartbeats update presence without repeatedly rebuilding UI',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = NearbyService(deviceId: 'me', deviceName: 'Phone');
    await Future<void>.delayed(Duration.zero);
    var updates = 0;
    service.addListener(() => updates++);
    final announcement = utf8.encode(jsonEncode({
      'id': 'other-phone',
      'name': 'Other Phone',
      'platform': 'android',
      'delivery_ack': true,
    }));
    try {
      service.handleDiscoveryAnnouncement(announcement, '127.0.0.2');
      final peer = service.getPeer('other-phone')!;
      final discoveredUpdates = updates;
      for (var i = 0; i < 100; i++) {
        service.handleDiscoveryAnnouncement(announcement, '127.0.0.2');
      }
      expect(updates, discoveredUpdates);
      expect(service.peers, hasLength(1));
      expect(peer.isOnline, isTrue);

      peer.lastSeen = DateTime.now().subtract(const Duration(seconds: 40));
      service.handleDiscoveryAnnouncement(announcement, '127.0.0.2');
      expect(peer.isOnline, isTrue);
      expect(updates, discoveredUpdates + 1);

      service.handleDiscoveryAnnouncement(
          utf8.encode(jsonEncode({
            'id': 'other-phone',
            'name': 'Renamed Phone',
            'platform': 'android',
          })),
          '127.0.0.2');
      expect(peer.name, 'Renamed Phone');
      expect(updates, discoveredUpdates + 2);
    } finally {
      service.dispose();
    }
  });
}
