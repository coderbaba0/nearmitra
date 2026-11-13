import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

abstract class PhoneAudioBridge {
  Stream<Map<String, dynamic>> get events;
  Future<void> prepareCapture(String id);
  Future<Map<String, dynamic>> receive(String id, String peerIp);
  Future<void> send(String id, String peerIp, int port, String token);
  Future<void> stop(String id);
  Future<void> volume(String id, double value);
  Future<void> speaker(String id, bool value);
}

class AndroidPhoneAudioBridge implements PhoneAudioBridge {
  static const _methods = MethodChannel('farmitra_nearby/phone_audio');
  static const _events = EventChannel('farmitra_nearby/phone_audio_events');

  @override
  Stream<Map<String, dynamic>> get events => _events
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map));

  @override
  Future<void> prepareCapture(String id) async {
    final supported = await _methods.invokeMethod<bool>('canCapture');
    if (supported != true) {
      throw StateError('Phone app audio requires Android 10 or newer');
    }
    // Playback capture requires RECORD_AUDIO even though no microphone is read.
    if (!(await Permission.microphone.request()).isGranted) {
      throw StateError('Audio capture permission was declined');
    }
    await _methods.invokeMethod<void>('prepareCapture', {'id': id});
  }

  @override
  Future<Map<String, dynamic>> receive(String id, String peerIp) async =>
      Map<String, dynamic>.from((await _methods
          .invokeMapMethod<String, dynamic>(
              'receive', {'id': id, 'peerIp': peerIp}))!);

  @override
  Future<void> send(String id, String peerIp, int port, String token) =>
      _methods.invokeMethod<void>(
          'send', {'id': id, 'peerIp': peerIp, 'port': port, 'token': token});
  @override
  Future<void> stop(String id) =>
      _methods.invokeMethod<void>('stop', {'id': id});
  @override
  Future<void> volume(String id, double value) =>
      _methods.invokeMethod<void>('volume', {'id': id, 'value': value});
  @override
  Future<void> speaker(String id, bool value) =>
      _methods.invokeMethod<void>('speaker', {'id': id, 'value': value});
}
