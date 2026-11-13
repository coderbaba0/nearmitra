import 'package:flutter/services.dart';

/// A MethodChannel has one Dart handler. Share intents and native call actions
/// must use the same dispatcher, including when a retained engine is reopened.
class NativeAppEvents {
  NativeAppEvents({required this.onCall, required this.onFiles});

  final void Function(Map<String, dynamic>) onCall;
  final void Function(List<String>) onFiles;
  static const channel = MethodChannel('farmitra_nearby/network');

  void attach() => channel.setMethodCallHandler((call) async {
        if (call.method == 'onNativeCallEvent' && call.arguments is Map) {
          onCall(Map<String, dynamic>.from(call.arguments as Map));
        } else if (call.method == 'onSharedFilesReceived' &&
            call.arguments is List) {
          final files =
              (call.arguments as List).map((e) => e.toString()).toList();
          if (files.isNotEmpty) onFiles(files);
        }
      });

  void detach() => channel.setMethodCallHandler(null);
}
