import 'dart:async';
import 'dart:io';
import 'dart:math' show sqrt;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../models/peer.dart';

class WirelessAudioSession {
  WirelessAudioSession(this.id, this.peer, this.source);
  final String id;
  final Peer peer;
  final String source;
  bool sending = false, pending = false, awaitingOffer = false, live = false;
  Map<String, dynamic>? offer;
  RTCPeerConnection? pc;
  MediaStream? local, remote;
  RTCVideoRenderer? renderer;
  bool hasRemoteDescription = false;
  bool answering = false;
  final List<RTCIceCandidate> candidates = [];
  Timer? timer, statsTimer;
  bool readingStats = false;
  double? previousEnergy,
      previousDuration,
      previousBufferDelay,
      previousEmitted;
}

/// One-way, audio-only streaming. It never uses call signalling or camera media.
class WirelessAudioService extends ChangeNotifier {
  WirelessAudioService({
    required this.send,
    required this.isOccupied,
    Future<RTCPeerConnection> Function()? createConnection,
    Future<MediaStream> Function(bool Function())? openMicrophone,
    this.playAudio,
    this.startPlayback,
    this.stopNative,
    this.routeSpeaker,
    this.routeOutput,
    this.timeout = const Duration(seconds: 35),
    this.permissionTimeout = const Duration(minutes: 2),
  })  : createConnection = createConnection ??
            (() => createPeerConnection({
                  'iceServers': [
                    {'urls': 'stun:stun.l.google.com:19302'}
                  ],
                  'iceTransportPolicy': 'all',
                  'sdpSemantics': 'unified-plan',
                  'audioJitterBufferMaxPackets': 50,
                  'audioJitterBufferFastAccelerate': true,
                })),
        openMicrophone = openMicrophone ?? _openMicrophone;

  final Future<void> Function(Peer, String, Map<String, dynamic>) send;
  final bool Function() isOccupied;
  final Future<RTCPeerConnection> Function() createConnection;
  final Future<MediaStream> Function(bool Function()) openMicrophone;
  final Future<void> Function(MediaStream)? playAudio;
  final Future<void> Function()? startPlayback, stopNative, routeSpeaker;
  final Future<void> Function(bool)? routeOutput;
  final Duration timeout, permissionTimeout;
  WirelessAudioSession? session;
  String status = 'Ready for wireless audio';
  bool muted = false;
  double volume = 1, audioLevel = 0;
  double? bufferDelayMs;
  bool speakerEnabled = true, routingOutput = false;
  String outputStatus = 'Phone speaker';
  final Map<String, List<RTCIceCandidate>> _earlyIce = {};
  bool Function()? otherMediaBusy;
  bool get _occupied => isOccupied() || otherMediaBusy?.call() == true;
  bool _stopping = false;
  bool get busy => session != null || _stopping;
  bool get needsApproval => session?.pending == true;
  static const channel = MethodChannel('farmitra_nearby/network');

  static Future<MediaStream> _openMicrophone(bool Function() current) async {
    if (!(await Permission.microphone.request()).isGranted) {
      throw StateError('Microphone permission was declined');
    }
    if (!current()) throw StateError('Audio request has ended');
    if (WebRTC.platformIsAndroid) {
      await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.communication);
      await channel
          .invokeMethod('startWirelessAudioService', {'microphone': true});
    }
    if (!current()) throw StateError('Audio request has ended');
    return navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true
      },
      'video': false,
    });
  }

  bool _current(WirelessAudioSession s) => identical(session, s);
  void _changed(String text) {
    status = text;
    notifyListeners();
  }

  void _arm(WirelessAudioSession s, String reason, [Duration? duration]) {
    s.timer?.cancel();
    s.timer = Timer(duration ?? timeout, () {
      if (_current(s)) unawaited(stop(reason: reason));
    });
  }

  Future<void> _signal(WirelessAudioSession s, String kind,
          [Map<String, dynamic> extra = const {}]) =>
      send(s.peer, 'wireless_audio_$kind', {
        'session_id': s.id,
        'stream_type': 'wireless_audio',
        'audio_mode': s.source,
        ...extra
      });

  WirelessAudioSession _new(Peer peer, String source, {String? id}) {
    if (busy || _occupied) {
      throw StateError('Stop the current call or stream first');
    }
    if (InternetAddress.tryParse(peer.ip) == null || peer.isMeshPeer) {
      throw StateError('Select a direct Nearby / P2P device');
    }
    final s =
        WirelessAudioSession(id ?? 'wa-${const Uuid().v4()}', peer, source);
    session = s;
    muted = false;
    audioLevel = 0;
    bufferDelayMs = null;
    speakerEnabled = true;
    outputStatus = 'Phone speaker';
    routingOutput = false;
    _arm(
        s, 'Peer did not respond. Update NearMitra on both devices and retry.');
    return s;
  }

  Future<void> requestPcAudio(Peer peer) async {
    final s = _new(peer, 'system');
    s.awaitingOffer = true;
    _changed('Waiting for ${peer.name} to share PC audio');
    try {
      await _signal(s, 'request');
    } catch (e) {
      if (_current(s)) {
        await stop(notify: false, reason: 'Could not request PC audio: $e');
      }
    }
  }

  Future<void> sendMicrophone(Peer peer) async {
    final s = _new(peer, 'mic');
    await _sendMicrophone(s);
  }

  Future<void> _sendMicrophone(WirelessAudioSession s) async {
    s.sending = true;
    s.pending = false;
    _arm(
        s,
        'Microphone permission request expired. Retry and allow microphone access.',
        permissionTimeout);
    _changed('Opening microphone…');
    try {
      final stream = await openMicrophone(() => _current(s));
      if (!_current(s)) {
        await _release(stream);
        await _stopNativeIfIdle();
        return;
      }
      s.local = stream;
      if (stream.getAudioTracks().isEmpty) {
        throw StateError('No microphone audio is available');
      }
      final pc = await _connection(s);
      if (pc == null) return;
      for (final track in stream.getAudioTracks()) {
        await pc.addTransceiver(
            track: track,
            init: RTCRtpTransceiverInit(
              direction: TransceiverDirection.SendOnly,
              streams: [stream],
            ));
      }
      final offer = await pc.createOffer(
          {'offerToReceiveAudio': false, 'offerToReceiveVideo': false});
      await pc.setLocalDescription(offer);
      if (!_current(s)) return;
      _arm(s,
          'No audio response. Open the updated NearMitra app on the other device and retry.');
      _changed('Waiting for ${s.peer.name} to allow wireless microphone');
      await _signal(s, 'offer', {'sdp': offer.sdp, 'sdp_type': offer.type});
    } catch (e) {
      if (_current(s)) {
        await stop(reason: 'Microphone stream failed: $e');
      } else {
        await _stopNativeIfIdle();
      }
    }
  }

  Future<RTCPeerConnection?> _connection(WirelessAudioSession s) async {
    final pc = await createConnection();
    if (!_current(s)) {
      await pc.close();
      await pc.dispose();
      return null;
    }
    s.pc = pc;
    pc.onIceCandidate = (c) {
      if (_current(s) && c.candidate != null) {
        unawaited(_signal(s, 'ice', {
          'candidate': c.candidate,
          'sdp_mid': c.sdpMid,
          'sdp_mline_index': c.sdpMLineIndex
        }).catchError((Object e) {
          if (_current(s)) return stop(reason: 'Audio signalling failed: $e');
        }));
      }
    };
    pc.onConnectionState = (state) {
      if (!_current(s)) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        s.live = true;
        s.timer?.cancel();
        if (!s.sending) unawaited(setPhoneSpeaker(speakerEnabled));
        _startAudioStats(s);
        _changed(s.sending
            ? 'Wireless microphone live • ${s.peer.name}'
            : 'Wireless speaker live • ${s.peer.name}');
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(stop(reason: 'Wireless audio connection failed'));
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        s.live = false;
        audioLevel = 0;
        _changed('Reconnecting to ${s.peer.name}…');
        _arm(s,
            'Wireless audio connection lost. Reconnect to the same Wi-Fi and retry.');
      }
    };
    pc.onTrack = (event) async {
      if (!_current(s) || s.sending || event.track.kind != 'audio') return;
      try {
        if (s.remote == null) {
          final remote = event.streams.firstOrNull ??
              await createLocalMediaStream('wireless_${s.id}');
          if (!_current(s)) {
            await _release(remote);
            return;
          }
          s.remote = remote;
        }
        if (!s.remote!.getTracks().any((t) => t.id == event.track.id)) {
          await s.remote!.addTrack(event.track);
        }
        if (!_current(s)) return;
        if (playAudio != null) {
          await playAudio!(s.remote!);
        } else {
          final renderer = s.renderer ??= RTCVideoRenderer();
          await renderer.initialize();
          if (!_current(s)) {
            await renderer.dispose();
            return;
          }
          renderer.srcObject = s.remote;
          await usePhoneSpeaker();
          await Helper.setVolume(volume, event.track);
        }
      } catch (e) {
        if (_current(s)) await stop(reason: 'Audio playback failed: $e');
      }
    };
    return pc;
  }

  Future<void> _drain(WirelessAudioSession s) async {
    for (final c in s.candidates.toList()) {
      if (!_current(s)) return;
      await s.pc!.addCandidate(c);
    }
    s.candidates.clear();
  }

  Future<void> approve() async {
    final s = session;
    if (s == null || !s.pending) return;
    s.pending = false;
    _arm(s,
        'Audio could not connect. Check the Wi-Fi connection and Windows private-network firewall permission.');
    _changed('Connecting wireless audio…');
    if (s.offer == null) {
      await _sendMicrophone(s);
      return;
    }
    await _receive(s, s.offer!);
  }

  Future<void> decline() async {
    final s = session;
    if (s == null || !s.pending) return;
    await _signal(
            s, 'reject', {'reason': 'Device owner declined wireless audio'})
        .catchError((_) {});
    if (_current(s)) {
      await stop(notify: false, reason: 'Wireless audio declined');
    }
  }

  Future<void> _receive(
      WirelessAudioSession s, Map<String, dynamic> offer) async {
    try {
      s.sending = false;
      s.awaitingOffer = false;
      _arm(s,
          'Audio could not connect. Check Wi-Fi and the Windows private-network firewall permission.');
      if (startPlayback != null) {
        await startPlayback!();
      } else if (WebRTC.platformIsAndroid) {
        await Helper.setAndroidAudioConfiguration(
            // The shared WebRTC audio device uses voice-communication attributes.
            // MODE_NORMAL/music disabled AudioSwitch routing on some phones.
            AndroidAudioConfiguration.communication);
        await channel
            .invokeMethod('startWirelessAudioService', {'microphone': false});
      }
      if (!_current(s)) {
        await _stopNativeIfIdle();
        return;
      }
      final pc = await _connection(s);
      if (pc == null) return;
      await pc.setRemoteDescription(
          RTCSessionDescription(offer['sdp'] as String, 'offer'));
      s.hasRemoteDescription = true;
      await _drain(s);
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      if (!_current(s)) return;
      await _signal(s, 'answer', {'sdp': answer.sdp, 'sdp_type': answer.type});
      if (_current(s) && !s.live) _changed('Connecting to ${s.peer.name}…');
    } catch (e) {
      if (_current(s)) await stop(reason: 'Wireless speaker failed: $e');
    }
  }

  Future<void> handle(Peer peer, Map<String, dynamic> h) async {
    final id = h['session_id']?.toString() ?? '';
    if (!RegExp(r'^wa-[A-Za-z0-9-]{8,80}$').hasMatch(id)) return;
    final kind = h['type'];
    var s = session;
    final matches = s != null && s.id == id && s.peer.ip == peer.ip;
    if (kind == 'wireless_audio_request' || kind == 'wireless_audio_offer') {
      if (matches) {
        if (kind == 'wireless_audio_offer' &&
            s.awaitingOffer &&
            h['sdp'] is String &&
            (h['sdp'] as String).isNotEmpty) {
          await _receive(s, h);
        }
        return;
      }
      if (busy || _occupied) {
        await send(peer, 'wireless_audio_reject',
            {'session_id': id, 'reason': 'Device is busy'});
        return;
      }
      final source = h['audio_mode']?.toString() ?? 'mic';
      if (!['system', 'mic', 'both'].contains(source)) return;
      if (kind == 'wireless_audio_request' && source != 'mic') {
        await send(peer, 'wireless_audio_reject', {
          'session_id': id,
          'reason':
              'This phone can share its microphone; PC system audio must be shared from Windows'
        });
        return;
      }
      if (kind == 'wireless_audio_offer' &&
          (h['sdp'] is! String || (h['sdp'] as String).isEmpty)) {
        return;
      }
      s = _new(peer, source, id: id);
      s.pending = true;
      s.offer = kind == 'wireless_audio_offer' ? Map.of(h) : null;
      s.candidates.addAll(_earlyIce.remove('${peer.ip}/$id') ?? []);
      _arm(s, 'Audio permission request expired. Retry from the other device.',
          permissionTimeout);
      await _signal(s, 'pending').catchError((_) {});
      if (!_current(s)) return;
      _changed(s.offer == null
          ? '${peer.name} requests your microphone'
          : '${peer.name} wants to play audio on this phone');
      return;
    }
    if (kind == 'wireless_audio_ice' && !matches) {
      if (_earlyIce.length >= 8) _earlyIce.remove(_earlyIce.keys.first);
      final list = _earlyIce.putIfAbsent('${peer.ip}/$id', () => []);
      if (list.length < 64 && h['candidate'] is String) list.add(_candidate(h));
      return;
    }
    if (!matches) return;
    try {
      if (kind == 'wireless_audio_pending') {
        _arm(
            s,
            'The other device did not approve audio. Open NearMitra there and allow the request.',
            permissionTimeout);
        _changed('Device reached: ${s.peer.name} • waiting for approval');
      } else if (kind == 'wireless_audio_answer' &&
          s.sending &&
          s.pc != null &&
          !s.hasRemoteDescription &&
          !s.answering) {
        if (h['sdp'] is! String || (h['sdp'] as String).isEmpty) return;
        s.answering = true;
        await s.pc!.setRemoteDescription(
            RTCSessionDescription(h['sdp'] as String, 'answer'));
        s.hasRemoteDescription = true;
        await _drain(s);
      } else if (kind == 'wireless_audio_ice' && h['candidate'] is String) {
        final c = _candidate(h);
        if (s.hasRemoteDescription && s.pc != null) {
          await s.pc!.addCandidate(c);
        } else if (s.candidates.length < 64) {
          s.candidates.add(c);
        }
      } else if (kind == 'wireless_audio_stop' ||
          kind == 'wireless_audio_reject') {
        await stop(
            notify: false,
            reason:
                h['reason']?.toString() ?? 'Wireless audio stopped by peer');
      }
    } catch (e) {
      if (_current(s)) await stop(reason: 'Wireless audio error: $e');
    }
  }

  RTCIceCandidate _candidate(Map<String, dynamic> h) => RTCIceCandidate(
        h['candidate'] as String,
        h['sdp_mid']?.toString(),
        int.tryParse('${h['sdp_mline_index'] ?? 0}'),
      );
  void toggleMute() {
    final s = session;
    if (s?.sending != true) return;
    muted = !muted;
    for (final t in s!.local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
    notifyListeners();
  }

  Future<void> usePhoneSpeaker() => setPhoneSpeaker(true);

  Future<void> setPhoneSpeaker(bool speaker) async {
    final s = session;
    if (s == null || s.sending || s.pending || routingOutput) return;
    routingOutput = true;
    notifyListeners();
    try {
      if (routeOutput != null) {
        await routeOutput!(speaker);
      } else if (routeSpeaker != null && speaker) {
        await routeSpeaker!();
      } else if (playAudio == null) {
        await Helper.setSpeakerphoneOn(speaker);
        if (!_current(s)) return;
        if (WebRTC.platformIsAndroid) {
          await Helper.selectAudioOutput(speaker ? 'speaker' : 'earpiece');
          if (!_current(s)) return;
          try {
            final applied = await channel.invokeMethod<bool>(
                'setWirelessAudioOutput', {'speaker': speaker});
            if (applied != true) {
              throw StateError('Android did not select this output');
            }
          } on MissingPluginException {
            // Existing installations retain the plugin routing fallback.
          }
        }
      }
      if (_current(s)) {
        speakerEnabled = speaker;
        outputStatus = speaker ? 'Phone speaker' : 'Phone earpiece';
      }
    } catch (e) {
      if (_current(s)) outputStatus = 'Output could not change: $e';
    } finally {
      if (_current(s) || session == null) routingOutput = false;
      if (_current(s)) notifyListeners();
    }
  }

  void _startAudioStats(WirelessAudioSession s) {
    s.statsTimer ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
      unawaited(sampleAudioStats());
    });
  }

  @visibleForTesting
  Future<void> sampleAudioStats() async {
    final s = session;
    if (s == null || !s.live || s.pc == null || s.readingStats) return;
    s.readingStats = true;
    try {
      final reports = await s.pc!.getStats();
      if (!_current(s)) return;
      double? level;
      for (final report in reports) {
        final v = report.values;
        if ((v['kind'] ?? v['mediaType']) != 'audio') continue;
        if (report.type == (s.sending ? 'media-source' : 'inbound-rtp')) {
          if (v['audioLevel'] is num) {
            level = (v['audioLevel'] as num).toDouble();
          }
          final energy = v['totalAudioEnergy'],
              duration = v['totalSamplesDuration'];
          if (energy is num && duration is num) {
            final deltaTime = duration.toDouble() -
                (s.previousDuration ?? duration.toDouble());
            if (deltaTime > 0) {
              final delta = (energy.toDouble() -
                      (s.previousEnergy ?? energy.toDouble())) /
                  deltaTime;
              level = delta > 0 ? sqrt(delta) : 0;
            }
            s.previousEnergy = energy.toDouble();
            s.previousDuration = duration.toDouble();
          }
          final delay = v['jitterBufferDelay'],
              emitted = v['jitterBufferEmittedCount'];
          if (!s.sending && delay is num && emitted is num) {
            final count =
                emitted.toDouble() - (s.previousEmitted ?? emitted.toDouble());
            if (count > 0) {
              bufferDelayMs = ((delay.toDouble() -
                          (s.previousBufferDelay ?? delay.toDouble())) /
                      count *
                      1000)
                  .clamp(0, 10000);
            }
            s.previousBufferDelay = delay.toDouble();
            s.previousEmitted = emitted.toDouble();
          }
        }
      }
      audioLevel = muted && s.sending ? 0 : (level ?? 0).clamp(0, 1);
      notifyListeners();
    } catch (_) {
      // Older platforms may omit statistics; do not interrupt working playback.
    } finally {
      s.readingStats = false;
    }
  }

  Future<void> setVolume(double value) async {
    volume = value.clamp(0, 1);
    for (final t in session?.remote?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      await Helper.setVolume(volume, t);
    }
    notifyListeners();
  }

  Future<void> _release(MediaStream? stream) async {
    if (stream == null) return;
    for (final t in stream.getTracks()) {
      try {
        await t.stop();
      } catch (_) {}
    }
    try {
      await stream.dispose();
    } catch (_) {}
  }

  Future<void> _stopNativeIfIdle() async {
    if (session != null) return;
    try {
      if (stopNative != null) {
        await stopNative!();
      } else if (WebRTC.platformIsAndroid) {
        await channel.invokeMethod('stopWirelessAudioService');
        await Helper.clearAndroidCommunicationDevice();
        await Helper.setAndroidAudioConfiguration(
            AndroidAudioConfiguration.communication);
      }
    } catch (_) {}
  }

  Future<void> stop(
      {bool notify = true, String reason = 'Wireless audio stopped'}) async {
    final s = session;
    if (s == null) return;
    _stopping = true;
    session = null;
    s.timer?.cancel();
    s.statsTimer?.cancel();
    audioLevel = 0;
    bufferDelayMs = null;
    _earlyIce.remove('${s.peer.ip}/${s.id}');
    if (notify) {
      unawaited(_signal(s, 'stop', {'reason': reason}).catchError((_) {}));
    }
    if (s.pc != null) {
      s.pc!.onTrack = null;
      s.pc!.onConnectionState = null;
      s.pc!.onIceCandidate = null;
      try {
        await s.pc!.close();
        await s.pc!.dispose();
      } catch (_) {}
    }
    await _release(s.local);
    await _release(s.remote);
    try {
      s.renderer?.srcObject = null;
      await s.renderer?.dispose();
    } catch (_) {}
    await _stopNativeIfIdle();
    _stopping = false;
    _changed(reason);
  }
}
