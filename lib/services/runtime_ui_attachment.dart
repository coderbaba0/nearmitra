import 'package:flutter/services.dart';

/// Start the widget tree only when an Activity is present. A sticky service
/// restart should not build HomeScreen or run its UI/plugin permission flows.
class RuntimeUiAttachment {
  RuntimeUiAttachment({required this.mount});

  final void Function() mount;
  static const _channel = MethodChannel('farmitra_nearby/runtime');
  bool _mounted = false;

  Future<void> attach({required bool backgroundStartup}) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'attachUi') _mountOnce();
    });
    if (!backgroundStartup) {
      _mountOnce();
      return;
    }
    // Covers an Activity opening before this Dart handler was registered.
    if (await _channel.invokeMethod<bool>('hasActivity') == true) _mountOnce();
  }

  void _mountOnce() {
    if (_mounted) return;
    _mounted = true;
    mount();
  }
}
