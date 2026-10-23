import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:farmitra_nearby/services/call_video_session.dart';

class TestTrack implements MediaStreamTrack {
  TestTrack(this.kind);
  @override
  final String kind;
  @override
  bool enabled = true;
  bool stopped = false;
  @override
  StreamTrackCallback? onEnded;
  @override
  Future<void> stop() async => stopped = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestStream implements MediaStream {
  TestStream(this.tracks);
  final List<MediaStreamTrack> tracks;
  bool disposed = false;
  @override
  List<MediaStreamTrack> getTracks() => tracks;
  @override
  List<MediaStreamTrack> getAudioTracks() =>
      tracks.where((t) => t.kind == 'audio').toList();
  @override
  List<MediaStreamTrack> getVideoTracks() =>
      tracks.where((t) => t.kind == 'video').toList();
  @override
  Future<void> addTrack(MediaStreamTrack track,
          {bool addToNative = true}) async =>
      tracks.add(track);
  @override
  Future<void> dispose() async => disposed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late TestTrack mic, camera, display;
  late TestStream local;
  late CallVideoSession session;
  late List<bool> signals;
  MediaStreamTrack? sender;
  int cameras = 0;
  Future<MediaStream> Function()? acquireScreen;
  setUp(() {
    mic = TestTrack('audio');
    camera = TestTrack('video');
    display = TestTrack('video');
    local = TestStream([mic]);
    signals = [];
    sender = null;
    cameras = 0;
    acquireScreen = null;
    session = CallVideoSession(
      localStream: local,
      cameraEnabled: false,
      replaceVideo: (track) async {
        sender = track;
      },
      openCamera: () async {
        cameras++;
        return TestStream([camera]);
      },
      openScreen: () =>
          acquireScreen?.call() ?? Future.value(TestStream([display])),
      signalVideo: (enabled) async {
        signals.add(enabled);
      },
      onChanged: () {},
      onError: (error) => fail('$error'),
    );
  });
  tearDown(() => session.dispose());
  test('Audio -> camera -> audio preserves the microphone and informs remote',
      () async {
    await session.setCamera(true);
    expect(sender, same(camera));
    expect(local.getVideoTracks(), [camera]);
    expect(session.cameraEnabled, isTrue);
    await session.setCamera(false);
    expect(sender, isNull);
    expect(session.cameraEnabled, isFalse);
    expect(signals, [true, false]);
    expect(mic.stopped, isFalse);
    expect(mic.enabled, isTrue);
  });
  test('Audio-only share never opens camera and returns to audio on stop',
      () async {
    await session.setScreenSharing(true);
    expect(sender, same(display));
    expect(cameras, 0);
    expect(session.sharing, isTrue);
    await session.setScreenSharing(false);
    expect(sender, isNull);
    expect(display.stopped, isTrue);
    expect(session.sharing, isFalse);
    expect(signals, [true, false]);
    expect(mic.stopped, isFalse);
  });
  test('Video call restores camera when sharing ends from system UI', () async {
    await session.setCamera(true);
    await session.setScreenSharing(true);
    display.onEnded!();
    await Future<void>.delayed(Duration.zero);
    expect(sender, same(camera));
    expect(session.sharing, isFalse);
    expect(session.cameraEnabled, isTrue);
    expect(display.stopped, isTrue);
    expect(camera.stopped, isFalse);
  });
  test('Switching to audio while sharing detaches display and camera',
      () async {
    await session.setCamera(true);
    await session.setScreenSharing(true);
    await session.setCamera(false);
    expect(sender, isNull);
    expect(session.sharing, isFalse);
    expect(session.cameraEnabled, isFalse);
    expect(display.stopped, isTrue);
    expect(signals.last, isFalse);
    expect(mic.stopped, isFalse);
  });
  test('Cancelled sharing leaves the connected audio untouched', () async {
    acquireScreen = () => Future.error(StateError('Permission declined'));
    await expectLater(session.setScreenSharing(true), throwsStateError);
    expect(session.sharing, isFalse);
    expect(session.busy, isFalse);
    expect(signals, isEmpty);
    expect(mic.stopped, isFalse);
  });
  test('Concurrent capture changes are rejected while permission is pending',
      () async {
    final grant = Completer<MediaStream>();
    acquireScreen = () => grant.future;
    final pending = session.setScreenSharing(true);
    await expectLater(session.setCamera(true), throwsStateError);
    grant.complete(TestStream([display]));
    await pending;
    expect(sender, same(display));
  });
  test('Call ending during permission dialog releases late display capture',
      () async {
    final grant = Completer<MediaStream>();
    acquireScreen = () => grant.future;
    final pending = session.setScreenSharing(true);
    await session.dispose();
    grant.complete(TestStream([display]));
    await pending;
    expect(display.stopped, isTrue);
    expect(sender, isNull);
    expect(signals, isEmpty);
  });
}
