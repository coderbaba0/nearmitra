import 'package:farmitra_nearby/services/call_video_sender.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_video_session_test.dart' show TestTrack, TestStream;

class FakeSender implements RTCRtpSender {
  FakeSender(this.senderId, this.events, {this.track});
  @override
  final String senderId;
  final List<String> events;
  @override
  MediaStreamTrack? track;
  bool fail = false;
  @override
  Future<void> replaceTrack(MediaStreamTrack? value) async {
    if (fail) throw StateError('RTP sender is null');
    track = value;
    events.add(value == null ? 'detach' : 'replace-video');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeReceiver implements RTCRtpReceiver {
  @override
  MediaStreamTrack? get track => TestTrack('video');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTransceiver implements RTCRtpTransceiver {
  FakeTransceiver(this.sender, this.events, {this.mid = '1'});
  @override
  final FakeSender sender;
  final List<String> events;
  @override
  final String mid;
  TransceiverDirection current = TransceiverDirection.SendRecv;
  TransceiverDirection desired = TransceiverDirection.SendRecv;
  @override
  RTCRtpReceiver get receiver => FakeReceiver();
  @override
  Future<TransceiverDirection?> getCurrentDirection() async => current;
  @override
  Future<TransceiverDirection> getDirection() async => desired;
  @override
  Future<void> setDirection(TransceiverDirection direction) async {
    desired = direction;
    events.add('direction:$direction');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeConnection implements RTCPeerConnection {
  List<RTCRtpTransceiver> slots = [];
  RTCSignalingState state = RTCSignalingState.RTCSignalingStateStable;
  @override
  Future<List<RTCRtpTransceiver>> getTransceivers() async => slots;
  @override
  Future<RTCSignalingState?> getSignalingState() async => state;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CameraSetupConnection extends FakeConnection {
  final events = <String>[];
  FakeSender? cameraSender;
  bool createdByAddTrack = false;

  @override
  Future<RTCRtpSender> addTrack(MediaStreamTrack track,
      [MediaStream? stream]) async {
    createdByAddTrack = true;
    cameraSender = FakeSender('camera', events, track: track);
    slots.add(FakeTransceiver(cameraSender!, events, mid: ''));
    return cameraSender!;
  }

  @override
  Future<RTCRtpTransceiver> addTransceiver({
    MediaStreamTrack? track,
    RTCRtpMediaType? kind,
    RTCRtpTransceiverInit? init,
  }) async {
    final transceiver = FakeTransceiver(
        FakeSender('reserved', events, track: track), events,
        mid: '');
    slots.add(transceiver);
    return transceiver;
  }

  // Unified Plan associates an addTrack-created slot with an incoming offer.
  // A pre-created addTransceiver slot is left unassociated instead.
  void receiveOffer() {
    if (createdByAddTrack) {
      slots = [FakeTransceiver(cameraSender!, events, mid: '1')];
    } else {
      slots.add(FakeTransceiver(FakeSender('offered', events), events));
    }
    state = RTCSignalingState.RTCSignalingStateHaveRemoteOffer;
  }
}

void main() {
  late List<String> events;
  late FakeSender stale, live;
  late FakeTransceiver reserved, actual;
  late FakeConnection pc;
  late CallVideoSender sender;
  late bool active;
  setUp(() {
    events = [];
    active = true;
    stale = FakeSender('video-id', events)..fail = true;
    live = FakeSender('video-id', events);
    reserved = FakeTransceiver(stale, events, mid: '');
    actual = FakeTransceiver(live, events);
    pc = FakeConnection()..slots = [actual];
    sender = CallVideoSender(
        connection: pc,
        reserved: reserved,
        isActive: () => active,
        negotiate: () async {
          events.add('offer');
        });
  });
  test(
      'Refreshes the native video sender instead of using stale pre-SDP wrapper',
      () async {
    final camera = TestTrack('video');
    await sender.replace(camera);
    expect(live.track, same(camera));
    expect(stale.track, isNull);
    expect(events, ['replace-video']);
  });
  test(
      'Audio-only recv slot becomes sendrecv before camera/screen renegotiation',
      () async {
    actual.current = TransceiverDirection.RecvOnly;
    actual.desired = TransceiverDirection.RecvOnly;
    await sender.replace(TestTrack('video'));
    expect(events, [
      'direction:${TransceiverDirection.SendRecv}',
      'replace-video',
      'offer'
    ]);
    expect(actual.desired, TransceiverDirection.SendRecv);
  });
  test('Camera -> screen -> camera -> audio uses the same live video slot',
      () async {
    final camera = TestTrack('video'), display = TestTrack('video');
    await sender.replace(camera);
    expect(live.track, same(camera));
    await sender.replace(display);
    expect(live.track, same(display));
    await sender.replace(camera);
    expect(live.track, same(camera));
    await sender.replace(null);
    expect(live.track, isNull);
    expect(
        events, ['replace-video', 'replace-video', 'replace-video', 'detach']);
  });
  test(
      'Failed renegotiation restores the previously published track and direction',
      () async {
    final camera = TestTrack('video');
    sender = CallVideoSender(
        connection: pc,
        reserved: reserved,
        initialTrack: camera,
        isActive: () => active,
        negotiate: () async {
          throw StateError('Signal failed');
        });
    actual.current = TransceiverDirection.RecvOnly;
    actual.desired = TransceiverDirection.RecvOnly;
    await expectLater(sender.replace(TestTrack('video')), throwsStateError);
    expect(live.track, same(camera));
    expect(actual.desired, TransceiverDirection.RecvOnly);
  });
  test(
      'Pending SDP exchange rejects upgrade before modifying the existing sender',
      () async {
    actual.current = TransceiverDirection.Inactive;
    pc.state = RTCSignalingState.RTCSignalingStateHaveLocalOffer;
    await expectLater(sender.replace(TestTrack('video')), throwsStateError);
    expect(events, isEmpty);
  });
  test(
      'Unavailable video slot reports an error instead of touching an audio sender',
      () async {
    pc.slots = [];
    await expectLater(sender.replace(TestTrack('video')), throwsStateError);
    expect(events, isEmpty);
  });
  test('Ended call does not mutate or negotiate media', () async {
    active = false;
    await expectLater(sender.replace(TestTrack('video')), throwsStateError);
    expect(events, isEmpty);
  });
  test('Negotiated MID recovers a sender whose native wrapper ID changed',
      () async {
    reserved = FakeTransceiver(stale, events, mid: '1');
    live = FakeSender('fresh-sender-id', events);
    actual = FakeTransceiver(live, events, mid: '1');
    pc.slots = [actual];
    sender = CallVideoSender(
        connection: pc,
        reserved: reserved,
        isActive: () => active,
        negotiate: () async {
          events.add('offer');
        });
    final display = TestTrack('video');
    await sender.replace(display);
    expect(live.track, same(display));
    expect(events, ['replace-video']);
  });

  test('Both phones keep their camera on the video slot in the first exchange',
      () async {
    final caller = CameraSetupConnection();
    final callee = CameraSetupConnection();
    final callerCamera = TestTrack('video');
    final calleeCamera = TestTrack('video');
    await addCallVideo(caller, TestStream([callerCamera]));
    final reserved = await addCallVideo(callee, TestStream([calleeCamera]));
    callee.receiveOffer();
    final answerSender = CallVideoSender(
      connection: callee,
      reserved: reserved,
      initialTrack: calleeCamera,
      isActive: () => true,
      negotiate: () async => fail('Answer must not create a second offer'),
    );
    await answerSender.prepareAnswer();
    expect(caller.cameraSender!.track, same(callerCamera));
    expect(callee.slots, hasLength(1));
    expect(callee.slots.single.mid, '1');
    expect(callee.slots.single.sender.track, same(calleeCamera));
    expect(await callee.slots.single.getDirection(),
        TransceiverDirection.SendRecv);
  });

  test('Audio-only answer uses offered video slot instead of an unused spare',
      () async {
    final pc = CameraSetupConnection();
    final reserved = await addCallVideo(pc, TestStream([TestTrack('audio')]));
    pc.receiveOffer();
    final offered = pc.slots.last as FakeTransceiver;
    offered.desired = TransceiverDirection.RecvOnly;
    final sender = CallVideoSender(
      connection: pc,
      reserved: reserved,
      isActive: () => true,
      negotiate: () async {},
    );
    await sender.prepareAnswer();
    expect(offered.events, contains('detach'));
    expect(offered.desired, TransceiverDirection.SendRecv);
    expect(reserved.mid, isEmpty);
  });
}
