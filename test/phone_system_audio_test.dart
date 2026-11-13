import 'dart:async';

import 'package:farmitra_nearby/models/peer.dart';
import 'package:farmitra_nearby/services/phone_audio_bridge.dart';
import 'package:farmitra_nearby/services/wireless_audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePhoneAudio implements PhoneAudioBridge {
  final controller = StreamController<Map<String, dynamic>>.broadcast();
  final stopped = <String>[];
  final outputs = <bool>[];
  final volumes = <double>[];
  int preparations = 0, receivers = 0, senders = 0;
  Completer<void>? consent;
  void Function(String)? connected;
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  Future<void> prepareCapture(String id) async {
    preparations++;
    await consent?.future;
  }

  @override
  Future<Map<String, dynamic>> receive(String id, String peerIp) async {
    receivers++;
    return {'port': 50123, 'token': 'a' * 64};
  }

  @override
  Future<void> send(String id, String peerIp, int port, String token) async {
    expect(port, 50123);
    expect(token, 'a' * 64);
    senders++;
    connected?.call(id);
  }

  @override
  Future<void> stop(String id) async => stopped.add(id);
  @override
  Future<void> volume(String id, double value) async => volumes.add(value);
  @override
  Future<void> speaker(String id, bool value) async => outputs.add(value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WirelessAudioService listener, source;
  late FakePhoneAudio listenerNative, sourceNative;
  late List<String> packets;
  final listenerPeer = Peer(
      id: 'listener', name: 'Phone A', ip: '192.168.1.10', platform: 'android');
  final sourcePeer = Peer(
      id: 'source', name: 'Phone B', ip: '192.168.1.11', platform: 'android');

  setUp(() {
    listenerNative = FakePhoneAudio();
    sourceNative = FakePhoneAudio();
    packets = [];
    listener = WirelessAudioService(
      isOccupied: () => false,
      phoneAudio: listenerNative,
      createConnection: () async =>
          throw StateError('Phone app audio must not open WebRTC'),
      openMicrophone: (_) async =>
          throw StateError('Receiver must not capture a microphone'),
      stopNative: () async {},
      send: (_, type, data) async {
        packets.add('A:$type');
        await source.handle(listenerPeer, {'type': type, ...data});
      },
    );
    source = WirelessAudioService(
      isOccupied: () => false,
      phoneAudio: sourceNative,
      createConnection: () async =>
          throw StateError('App audio must use playback capture'),
      openMicrophone: (_) async =>
          throw StateError('App audio must never substitute microphone audio'),
      stopNative: () async {},
      send: (_, type, data) async {
        packets.add('B:$type');
        await listener.handle(sourcePeer, {'type': type, ...data});
      },
    );
    sourceNative.connected = (id) {
      for (final bridge in [listenerNative, sourceNative]) {
        bridge.controller.add({'id': id, 'type': 'connected'});
      }
    };
  });

  tearDown(() async {
    await listener.stop(notify: false);
    await source.stop(notify: false);
    listener.dispose();
    source.dispose();
    await listenerNative.controller.close();
    await sourceNative.controller.close();
  });

  test(
      'Two phones approve and connect app audio without opening either microphone',
      () async {
    await listener.requestDeviceAudio(sourcePeer);
    expect(source.needsApproval, isTrue);
    expect(sourceNative.preparations, 0);
    expect(listenerNative.receivers, 0);
    await source.approve();
    await Future<void>.delayed(Duration.zero);
    expect(sourceNative.preparations, 1);
    expect(sourceNative.senders, 1);
    expect(listenerNative.receivers, 1);
    expect(source.session!.sending, isTrue);
    expect(listener.session!.sending, isFalse);
    expect(source.session!.live, isTrue);
    expect(listener.session!.live, isTrue);
    expect(listenerNative.outputs, [true]);
    await listener.setVolume(.4);
    expect(listenerNative.volumes.last, .4);
    await listener.setPhoneSpeaker(false);
    expect(listenerNative.outputs.last, false);
    await listener.stop();
    await Future<void>.delayed(Duration.zero);
    expect(source.busy, isFalse);
    expect(sourceNative.stopped, isNotEmpty);
    expect(listenerNative.stopped, isNotEmpty);
  });

  test('Declining phone app audio never captures or starts playback', () async {
    await listener.requestDeviceAudio(sourcePeer);
    await source.decline();
    expect(sourceNative.preparations, 0);
    expect(listenerNative.receivers, 0);
    expect(listener.busy, isFalse);
    expect(source.busy, isFalse);
  });

  test(
      'Stopping during Android consent prevents a late offer or capture sender',
      () async {
    sourceNative.consent = Completer<void>();
    await listener.requestDeviceAudio(sourcePeer);
    final approving = source.approve();
    await Future<void>.delayed(Duration.zero);
    await listener.stop();
    await Future<void>.delayed(Duration.zero);
    sourceNative.consent!.complete();
    await approving;
    expect(packets, isNot(contains('B:wireless_audio_offer')));
    expect(sourceNative.senders, 0);
    expect(sourceNative.stopped, isNotEmpty);
    expect(source.busy, isFalse);
  });

  test('Duplicate phone offer cannot create another playback server', () async {
    await listener.requestDeviceAudio(sourcePeer);
    final id = listener.session!.id;
    final offer = {
      'type': 'wireless_audio_offer',
      'session_id': id,
      'audio_mode': 'system',
      'audio_transport': 'android_pcm_v1',
      'sample_rate': 48000,
      'channels': 2,
      'sample_format': 's16le'
    };
    await Future.wait([
      listener.handle(sourcePeer, offer),
      listener.handle(sourcePeer, offer)
    ]);
    expect(listenerNative.receivers, 1);
  });

  test('Unsupported PCM format never falls back to the microphone', () async {
    await listener.requestDeviceAudio(sourcePeer);
    await listener.handle(sourcePeer, {
      'type': 'wireless_audio_offer',
      'session_id': listener.session!.id,
      'audio_mode': 'system',
      'audio_transport': 'android_pcm_v1',
      'sample_rate': 44100,
      'channels': 2,
      'sample_format': 's16le'
    });
    expect(listenerNative.receivers, 0);
    expect(listener.session!.live, isFalse);
  });

  test('Native projection revocation stops the remote listener too', () async {
    await listener.requestDeviceAudio(sourcePeer);
    await source.approve();
    final id = source.session!.id;
    sourceNative.controller.add(
        {'id': id, 'type': 'stopped', 'reason': 'Android stopped capture'});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(source.busy, isFalse);
    expect(listener.busy, isFalse);
    expect(listener.status, contains('Android stopped capture'));
  });
}
