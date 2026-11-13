import 'dart:async';

import 'package:farmitra_nearby/services/firebase_presence_service.dart';
import 'package:farmitra_nearby/services/nearby_service.dart';
import 'package:farmitra_nearby/services/wan_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final channels = <String, String>{};
  const dbChannel = MethodChannel('plugins.flutter.io/firebase_database');
  var nextChannel = 0;

  Future<void> sendValue(String channel, Object? value) async {
    await messenger.handlePlatformMessage(channel, const StandardMethodCodec().encodeSuccessEnvelope({
      'eventType': 'value',
      'snapshot': {'value': value, 'key': 'key', 'childKeys': <String>[]},
    }), (_) {});
  }

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) { await Future<void>.delayed(Duration.zero); }
  }

  setUpAll(() async {
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({'nearmitra_internet_device_id':'test-phone'});
    messenger.setMockMethodCallHandler(dbChannel, (call) async {
      calls.add(call);
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      final path = args['path'] as String? ?? '';
      if (call.method == 'Query#observe') {
        final channel = 'test-db-${nextChannel++}';
        channels[channel] = path;
        messenger.setMockMethodCallHandler(MethodChannel(channel), (event) async {
          if (event.method == 'listen') {
            scheduleMicrotask(() => sendValue(channel, path == '.info/connected' ? true : path == '.info/serverTimeOffset' ? 0 : null));
          }
          return null;
        });
        return channel;
      }
      if (call.method == 'Query#get') return {'snapshot':{'value':null,'key':'key','childKeys':<String>[]}};
      return null;
    });
  });

  setUp(() async {
    await (await SharedPreferences.getInstance()).remove(WanService.internetModePreferenceKey);
    calls.clear();
  });

  tearDown(() async {
    await WanService().setInternetMode(false);
    await settle();
    calls.clear();
  });

  test('Default startup publishes online and starts listeners without a WAN tab', () async {
    await WanService().restoreInternetMode();
    await settle();
    expect(WanService().isInternetModeEnabled, isTrue);
    expect(FirebasePresenceService().isPresenceOnline, isTrue);
    expect(channels.values, contains('trustedDevices/test-phone'));
    final writes = calls.where((c) => c.method == 'DatabaseReference#update');
    expect(writes.any((c) => (c.arguments as Map)['path'] == 'presence/test-phone' &&
        ((c.arguments as Map)['value'] as Map)['online'] == true), isTrue);
    final count = calls.where((c) => c.method == 'Query#observe').length;
    await WanService().restoreInternetMode();
    await settle();
    expect(calls.where((c) => c.method == 'Query#observe').length, count);
  });

  test('Saved Internet OFF survives restore and does not attach presence listeners', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(WanService.internetModePreferenceKey, false);
    expect(prefs.getBool(WanService.internetModePreferenceKey), isFalse);
    await WanService().restoreInternetMode();
    await settle();
    expect(WanService().isInternetModeEnabled, isFalse);
    expect(calls.where((c) => c.method == 'Query#observe'), isEmpty);
  });

  test('Rapid ON then OFF leaves presence offline and preserves the OFF choice', () async {
    await Future.wait([WanService().setInternetMode(true), WanService().setInternetMode(false)]);
    await settle();
    expect(WanService().isInternetModeEnabled, isFalse);
    expect(FirebasePresenceService().isPresenceOnline, isFalse);
    expect((await SharedPreferences.getInstance()).getBool(WanService.internetModePreferenceKey), isFalse);
  });

  test('Background ON requests task minimization; OFF does not minimize', () async {
    final native = <String>[];
    const network = MethodChannel('farmitra_nearby/network');
    messenger.setMockMethodCallHandler(network, (call) async { native.add(call.method); return true; });
    final service = NearbyService(deviceId:'background-phone',deviceName:'Phone');
    try {
      expect(await service.moveToBackground(), isTrue);
      expect(native, ['moveTaskToBackground']);
      await service.setBackgroundServiceEnabled(false);
      native.clear();
      expect(await service.moveToBackground(), isFalse);
      expect(native, isEmpty);
    } finally {
      service.dispose();
      messenger.setMockMethodCallHandler(network, null);
    }
  });
}
