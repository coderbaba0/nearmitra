import 'package:flutter/services.dart';

class AndroidNetworkBridge {
  static const _channel = MethodChannel('farmitra_nearby/network');

  Future<Map<String, dynamic>> requestPhoneTelemetry(String peer) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'requestPhoneTelemetry', {'peer': peer},
    );
    if (result == null) throw StateError('Phone sensor reading is unavailable');
    return Map<String, dynamic>.from(result);
  }

  Future<void> acquireMulticastLock() async {
    try {
      await _channel.invokeMethod<void>('acquireMulticastLock');
    } catch (_) {}
  }

  Future<void> releaseMulticastLock() async {
    try {
      await _channel.invokeMethod<void>('releaseMulticastLock');
    } catch (_) {}
  }
}
