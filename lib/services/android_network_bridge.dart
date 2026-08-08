import 'package:flutter/services.dart';

class AndroidNetworkBridge {
  static const _channel = MethodChannel('farmitra_nearby/network');

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
