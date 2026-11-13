import 'dart:async';

import 'package:farmitra_nearby/services/native_app_events.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Call Accept still reaches the reopened app after share handler setup',
      () async {
    final calls = <Map<String, dynamic>>[];
    final files = <List<String>>[];
    final events = NativeAppEvents(onCall: calls.add, onFiles: files.add);
    Future<void> nativeEvent(String method, Object arguments) {
      final complete = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
              'farmitra_nearby/network',
              const StandardMethodCodec()
                  .encodeMethodCall(MethodCall(method, arguments)),
              (_) => complete.complete());
      return complete.future;
    }

    try {
      events.attach(); // Call setup.
      events.attach(); // Share setup must preserve Call Accept handling.
      await nativeEvent('onSharedFilesReceived', ['/downloads/photo.jpg']);
      await nativeEvent('onNativeCallEvent', {
        'action': 'accept',
        'peerId': 'caller',
        'peerIp': '192.168.1.2',
        'isVideo': true,
      });
      expect(files.single, ['/downloads/photo.jpg']);
      expect(calls.single['peerId'], 'caller');
      expect(calls.single['isVideo'], isTrue);
    } finally {
      events.detach();
    }
  });
}
