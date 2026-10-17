import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:farmitra_nearby/models/peer.dart';
import 'package:farmitra_nearby/services/wireless_audio_service.dart';
import 'package:farmitra_nearby/services/nearby_service.dart';
import 'call_video_session_test.dart' show TestTrack, TestStream;

class AudioTrack extends TestTrack {
  AudioTrack(super.kind);
  @override
  String get id => 'wireless-$kind';
}

class AudioTransceiver implements RTCRtpTransceiver {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AudioConnection extends RTCPeerConnection {
  final directions = <TransceiverDirection?>[];
  final candidates = <RTCIceCandidate>[];
  RTCSessionDescription? remote, local;
  bool closed = false;
  List<StatsReport> reports = [];
  @override
  Future<List<StatsReport>> getStats([MediaStreamTrack? track]) async =>
      reports;
  @override
  Future<RTCRtpTransceiver> addTransceiver(
      {MediaStreamTrack? track,
      RTCRtpMediaType? kind,
      RTCRtpTransceiverInit? init}) async {
    directions.add(init?.direction);
    return AudioTransceiver();
  }

  @override
  Future<RTCSessionDescription> createOffer(
          [Map<String, dynamic>? constraints]) async =>
      RTCSessionDescription('phone mic SDP', 'offer');
  @override
  Future<RTCSessionDescription> createAnswer(
          [Map<String, dynamic>? constraints]) async =>
      RTCSessionDescription('phone speaker SDP', 'answer');
  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    local = description;
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    remote = description;
  }

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    candidates.add(candidate);
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peer = Peer(id: 'desktop', name: 'PC', ip: '192.168.1.2');
  const id = 'wa-12345678-abcd';
  Map<String, dynamic> packet(String type,
          [Map<String, dynamic> extra = const {}]) =>
      {
        'type': 'wireless_audio_$type',
        'session_id': id,
        'audio_mode': 'mic',
        ...extra,
      };
  late WirelessAudioService audio;
  late AudioConnection pc;
  late List<Map<String, dynamic>> sent;
  late AudioTrack mic;
  late TestStream capture;
  int captures = 0, playbackStarts = 0, nativeStops = 0, plays = 0;
  bool occupied = false;
  Future<MediaStream> Function()? grantMic;
  setUp(() {
    pc = AudioConnection();
    sent = [];
    mic = AudioTrack('audio');
    capture = TestStream([mic]);
    captures = 0;
    playbackStarts = 0;
    nativeStops = 0;
    plays = 0;
    occupied = false;
    grantMic = null;
    audio = WirelessAudioService(
      send: (peer, type, data) async {
        sent.add({'type': type, ...data});
      },
      isOccupied: () => occupied,
      createConnection: () async => pc,
      openMicrophone: (_) async {
        captures++;
        return grantMic?.call() ?? capture;
      },
      startPlayback: () async {
        playbackStarts++;
      },
      stopNative: () async {
        nativeStops++;
      },
      playAudio: (_) async {
        plays++;
      },
    );
  });
  tearDown(() async {
    await audio.stop(notify: false);
    audio.dispose();
  });
  test(
      'Incoming desktop audio waits for explicit playback approval and never opens phone mic',
      () async {
    await audio.handle(peer,
        packet('offer', {'sdp': 'PC system audio', 'audio_mode': 'system'}));
    expect(audio.needsApproval, isTrue);
    expect(sent.single['type'], 'wireless_audio_pending');
    expect(playbackStarts, 0);
    expect(captures, 0);
    await audio.approve();
    expect(playbackStarts, 1);
    expect(captures, 0);
    expect(pc.remote?.sdp, 'PC system audio');
    expect(sent.last['type'], 'wireless_audio_answer');
    expect(audio.session!.live, isFalse);
    pc.onConnectionState!(
        RTCPeerConnectionState.RTCPeerConnectionStateConnected);
    expect(audio.session!.live, isTrue);
    final remote = TestStream([AudioTrack('audio')]);
    pc.onTrack!(
        RTCTrackEvent(streams: [remote], track: remote.getTracks().first));
    await Future<void>.delayed(Duration.zero);
    expect(plays, 1);
  });
  test(
      'PC mic request captures only after approval and uses a send-only audio slot',
      () async {
    await audio.handle(peer, packet('request'));
    expect(captures, 0);
    expect(audio.needsApproval, isTrue);
    await audio.approve();
    expect(captures, 1);
    expect(pc.directions, [TransceiverDirection.SendOnly]);
    expect(sent.last['type'], 'wireless_audio_offer');
    expect(sent.last['session_id'], id);
    audio.toggleMute();
    expect(mic.enabled, isFalse);
    audio.toggleMute();
    expect(mic.enabled, isTrue);
    await audio.handle(peer, packet('answer', {'sdp': 'PC receive answer'}));
    expect(pc.remote?.sdp, 'PC receive answer');
    await audio.stop();
    expect(mic.stopped, isTrue);
    expect(pc.closed, isTrue);
    expect(nativeStops, 1);
  });
  test('Phone requests PC audio and accepts only the matching requested offer',
      () async {
    await audio.requestPcAudio(peer);
    final session = audio.session!;
    expect(sent.single['type'], 'wireless_audio_request');
    expect(captures, 0);
    await audio.handle(peer, {
      'type': 'wireless_audio_offer',
      'session_id': session.id,
      'sdp': 'PC audio',
      'audio_mode': 'system'
    });
    expect(audio.needsApproval, isFalse);
    expect(playbackStarts, 1);
    expect(captures, 0);
    expect(sent.last['type'], 'wireless_audio_answer');
  });
  test(
      'Deny does not capture or play, duplicate requests preserve the existing approval',
      () async {
    await audio.handle(peer, packet('request'));
    final current = audio.session;
    await audio.handle(peer, packet('request'));
    expect(audio.session, same(current));
    await audio.decline();
    expect(sent.last['type'], 'wireless_audio_reject');
    expect(captures, 0);
    expect(playbackStarts, 0);
    expect(audio.busy, isFalse);
  });
  test(
      'Existing calls/CCTV reject new wireless audio without changing current resources',
      () async {
    occupied = true;
    await audio.handle(peer, packet('request'));
    expect(sent.single['reason'], 'Device is busy');
    expect(audio.session, isNull);
    await expectLater(audio.sendMicrophone(peer), throwsStateError);
    expect(captures, 0);
  });
  test(
      'ICE before offer queues until consent/SDP and unrelated sessions cannot stop stream',
      () async {
    await audio.handle(
        peer, packet('ice', {'candidate': 'early', 'sdp_mline_index': 0}));
    await audio.handle(peer, packet('offer', {'sdp': 'desktop audio'}));
    await audio.approve();
    expect(pc.candidates.single.candidate, 'early');
    await audio.handle(
        Peer(id: 'other', name: 'Other', ip: '192.168.1.99'), packet('stop'));
    expect(audio.session, isNotNull);
    await audio.handle(peer, packet('stop', {'session_id': 'wa-99999999'}));
    expect(audio.session, isNotNull);
    final before = sent.length;
    await audio.handle(peer, packet('stop'));
    expect(audio.busy, isFalse);
    expect(sent.length, before);
  });
  test(
      'Late microphone permission after stop releases capture and never sends an offer',
      () async {
    final grant = Completer<MediaStream>();
    grantMic = () => grant.future;
    final pending = audio.sendMicrophone(peer);
    await audio.stop(notify: false);
    grant.complete(capture);
    await pending;
    expect(mic.stopped, isTrue);
    expect(sent, isEmpty);
    expect(audio.busy, isFalse);
  });
  test(
      'Microphone permission failure closes session and communicates stop without call signalling',
      () async {
    grantMic = () => Future.error(StateError('Permission denied'));
    await audio.sendMicrophone(peer);
    expect(audio.busy, isFalse);
    expect(audio.status, contains('Permission denied'));
    expect(
        sent.every((h) => h['type'].toString().startsWith('wireless_audio_')),
        isTrue);
  });
  test('WAN-only/mesh targets cannot start standalone Nearby audio', () async {
    await expectLater(
        audio.sendMicrophone(Peer(id: 'wan', name: 'WAN', ip: '')),
        throwsStateError);
    final mesh = Peer(id: 'mesh', name: 'Mesh', ip: '192.168.1.9')
      ..isMeshPeer = true;
    await expectLater(audio.requestPcAudio(mesh), throwsStateError);
    expect(sent, isEmpty);
  });
  test('Unanswered wireless request times out with actionable message',
      () async {
    final limited = WirelessAudioService(
        send: (p, t, d) async {},
        isOccupied: () => false,
        stopNative: () async {},
        timeout: const Duration(milliseconds: 10));
    await limited.requestPcAudio(peer);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(limited.busy, isFalse);
    expect(limited.status, contains('did not respond'));
    limited.dispose();
  });
  test(
      'Speaker routing is reasserted after receive connection and never captures the microphone',
      () async {
    var routes = 0;
    final receiver = WirelessAudioService(
      send: (_, __, ___) async {},
      isOccupied: () => false,
      createConnection: () async => pc,
      startPlayback: () async {},
      stopNative: () async {},
      openMicrophone: (_) async {
        fail('Speaker receiver opened the microphone');
      },
      playAudio: (_) async {},
      routeSpeaker: () async {
        routes++;
      },
    );
    await receiver.handle(
        peer, packet('offer', {'sdp': 'music', 'audio_mode': 'system'}));
    await receiver.usePhoneSpeaker();
    expect(routes, 0, reason: 'Pending audio must not change phone routing');
    await receiver.approve();
    pc.onConnectionState!(
        RTCPeerConnectionState.RTCPeerConnectionStateConnected);
    await Future<void>.delayed(Duration.zero);
    expect(routes, 1);
    await receiver.usePhoneSpeaker();
    expect(routes, 2);
    expect(pc.directions, isEmpty);
    await receiver.stop(notify: false);
    await receiver.usePhoneSpeaker();
    expect(routes, 2);
    receiver.dispose();
  });
  test(
      'Speaker toggle reports successful output and preserves output after failure',
      () async {
    final selected = <bool>[];
    var reject = false;
    final receiver = WirelessAudioService(
      send: (_, __, ___) async {},
      isOccupied: () => false,
      createConnection: () async => pc,
      startPlayback: () async {},
      stopNative: () async {},
      playAudio: (_) async {},
      routeOutput: (speaker) async {
        if (reject) throw StateError('route unavailable');
        selected.add(speaker);
      },
    );
    await receiver.handle(peer, packet('offer', {'sdp': 'music'}));
    await receiver.approve();
    await receiver.setPhoneSpeaker(false);
    expect(receiver.speakerEnabled, false);
    expect(receiver.outputStatus, 'Phone earpiece');
    await receiver.setPhoneSpeaker(true);
    expect(selected, [false, true]);
    expect(receiver.outputStatus, 'Phone speaker');
    reject = true;
    await receiver.setPhoneSpeaker(false);
    expect(receiver.speakerEnabled, true);
    expect(receiver.routingOutput, false);
    expect(receiver.outputStatus, contains('could not change'));
    await receiver.stop(notify: false);
    receiver.dispose();
  });
  test(
      'Meter uses actual inbound audio energy and interval playback buffer statistics',
      () async {
    await audio.handle(peer, packet('offer', {'sdp': 'music'}));
    await audio.approve();
    audio.session!.live = true;
    pc.reports = [
      StatsReport('in', 'inbound-rtp', 0, {
        'kind': 'audio',
        'audioLevel': 0.25,
        'totalAudioEnergy': 1.0,
        'totalSamplesDuration': 2.0,
        'jitterBufferDelay': 1.0,
        'jitterBufferEmittedCount': 100.0
      })
    ];
    await audio.sampleAudioStats();
    expect(audio.audioLevel, 0.25);
    pc.reports = [
      StatsReport('in', 'inbound-rtp', 1, {
        'kind': 'audio',
        'totalAudioEnergy': 1.02,
        'totalSamplesDuration': 2.5,
        'jitterBufferDelay': 2.0,
        'jitterBufferEmittedCount': 200.0
      })
    ];
    await audio.sampleAudioStats();
    expect(audio.audioLevel, closeTo(0.2, 0.001));
    expect(audio.bufferDelayMs, 10);
    pc.reports = [];
    await audio.sampleAudioStats();
    expect(audio.audioLevel, 0);
    await audio.stop(notify: false);
    expect(audio.audioLevel, 0);
    expect(audio.bufferDelayMs, isNull);
  });
  test(
      'Real Windows TCP wireless offer routes independently of legacy stream/call listeners',
      () async {
    final service = NearbyService(deviceId: 'phone', deviceName: 'Phone');
    service.onStreamOffer =
        (_, __) => fail('Wireless packet reached CCTV listener');
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(service.handleIncomingConnection);
    final socket =
        await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    socket.write('${jsonEncode({
          ...packet('offer', {'sdp': 'desktop audio', 'audio_mode': 'system'}),
          'sender': 'Windows',
          'sender_id': 'desktop'
        })}\n');
    await socket.flush();
    for (var i = 0; i < 30 && !service.wirelessAudio.needsApproval; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(service.wirelessAudio.needsApproval, isTrue);
    expect(service.wirelessAudio.session?.id, id);
    await service.wirelessAudio.stop(notify: false);
    socket.destroy();
    await server.close();
    service.dispose();
  });
}
