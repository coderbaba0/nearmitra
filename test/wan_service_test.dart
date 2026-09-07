import 'package:flutter_test/flutter_test.dart';
import 'package:farmitra_nearby/models/wan_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WAN Models & Pairing Logic Tests', () {
    test('WanPairCode serialization and expiration check', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final futureExpiry = now + 300000;

      final pairCode = WanPairCode(
        code: '123456',
        ownerDeviceId: 'device-test-123',
        ownerName: 'Test Phone',
        ownerPlatform: 'android',
        expiresAt: futureExpiry,
      );

      expect(pairCode.isExpired, isFalse);
      expect(pairCode.code, '123456');
      expect(pairCode.ownerName, 'Test Phone');

      final pastExpiry = now - 1000;
      final expiredCode = WanPairCode(
        code: '654321',
        ownerDeviceId: 'device-test-123',
        ownerName: 'Test Phone',
        ownerPlatform: 'android',
        expiresAt: pastExpiry,
      );

      expect(expiredCode.isExpired, isTrue);
    });

    test('WanPairRequest serialization from map', () {
      final map = {
        'fromDeviceId': 'peer-abc',
        'fromDeviceName': 'Windows Workstation',
        'fromPlatform': 'windows',
        'toDeviceId': 'my-phone',
        'code': '888999',
        'createdAt': 1725620000000,
        'status': 'pending',
      };

      final req = WanPairRequest.fromMap('req-001', map);

      expect(req.requestId, 'req-001');
      expect(req.fromDeviceId, 'peer-abc');
      expect(req.fromDeviceName, 'Windows Workstation');
      expect(req.fromPlatform, 'windows');
      expect(req.code, '888999');
      expect(req.status, 'pending');
    });

    test('WanDevice model test', () {
      final device = WanDevice(
        id: 'peer-1',
        name: 'Farmitra Desktop',
        platform: 'windows',
        isOnline: true,
        isTrusted: true,
      );

      expect(device.id, 'peer-1');
      expect(device.isOnline, isTrue);
      expect(device.isTrusted, isTrue);
      expect(device.platform, 'windows');
    });
  });
}
