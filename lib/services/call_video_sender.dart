import 'package:flutter_webrtc/flutter_webrtc.dart';

/// addTrack-created transceivers can be associated with an incoming offer.
/// An explicit addTransceiver(camera) before that offer leaves the answerer's
/// camera on an unassociated slot, so its first answer only receives video.
Future<RTCRtpTransceiver> addCallVideo(
    RTCPeerConnection connection, MediaStream stream) async {
  final camera = stream.getVideoTracks().firstOrNull;
  if (camera == null) {
    return connection.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(
        direction: TransceiverDirection.SendRecv,
        streams: [stream],
      ),
    );
  }
  final sender = await connection.addTrack(camera, stream);
  final transceivers = await connection.getTransceivers();
  return transceivers.firstWhere(
    (t) => t.sender.senderId == sender.senderId,
    orElse: () => throw StateError('Camera sender has no video transceiver'),
  );
}

/// Resolves the live negotiated video sender before each camera/display change.
/// Native transceiver wrappers captured before SDP negotiation can become stale.
class CallVideoSender {
  CallVideoSender({
    required this.connection,
    required RTCRtpTransceiver reserved,
    required this.negotiate,
    required this.isActive,
    MediaStreamTrack? initialTrack,
  })  : _reserved = reserved,
        _published = initialTrack;

  final RTCPeerConnection connection;
  final Future<void> Function() negotiate;
  final bool Function() isActive;
  RTCRtpTransceiver _reserved;
  MediaStreamTrack? _published;
  bool _busy = false;

  bool _isVideo(RTCRtpTransceiver transceiver) =>
      transceiver.sender.track?.kind == 'video' ||
      transceiver.receiver.track?.kind == 'video';

  Future<RTCRtpTransceiver> _liveVideo() async {
    final all = await connection.getTransceivers();
    final senderId = _reserved.sender.senderId;
    final mid = _reserved.mid;
    final byMid = all.where((t) => mid.isNotEmpty && t.mid == mid);
    if (byMid.isNotEmpty) return _reserved = byMid.first;
    final bySender =
        all.where((t) => senderId.isNotEmpty && t.sender.senderId == senderId);
    final associatedSender = bySender.where((t) => t.mid.isNotEmpty);
    if (associatedSender.isNotEmpty) return _reserved = associatedSender.first;
    final videos = all.where(_isVideo).toList();
    // Prefer an associated video slot over an unnegotiated spare transceiver.
    final negotiated = videos.where((t) => t.mid.isNotEmpty);
    if (negotiated.length == 1) return _reserved = negotiated.first;
    if (bySender.isNotEmpty) return _reserved = bySender.first;
    if (videos.length == 1) return _reserved = videos.first;
    throw StateError('The call has no available negotiated video sender');
  }

  /// Bind the local camera to the offered slot before createAnswer, including
  /// when a native peer created a separate receive slot for an audio-only call.
  Future<void> prepareAnswer() async {
    if (!isActive()) throw StateError('Call has ended');
    final video = await _liveVideo();
    if (!isActive()) throw StateError('Call has ended');
    await video.setDirection(TransceiverDirection.SendRecv);
    await video.sender.replaceTrack(_published);
  }

  Future<void> replace(MediaStreamTrack? track) async {
    if (!isActive()) throw StateError('Call has ended');
    if (_busy) throw StateError('A video change is already in progress');
    _busy = true;
    RTCRtpTransceiver? video;
    TransceiverDirection? oldDirection;
    final previous = _published;
    var replaced = false;
    try {
      video = await _liveVideo();
      if (!isActive()) throw StateError('Call has ended');
      final current = await video.getCurrentDirection();
      final needsNegotiation = track != null &&
          current != TransceiverDirection.SendRecv &&
          current != TransceiverDirection.SendOnly;
      if (needsNegotiation) {
        if (await connection.getSignalingState() !=
            RTCSignalingState.RTCSignalingStateStable) {
          throw StateError('Call negotiation is in progress; try again');
        }
        oldDirection = await video.getDirection();
        await video.setDirection(TransceiverDirection.SendRecv);
      }
      await video.sender.replaceTrack(track);
      replaced = true;
      if (!isActive()) throw StateError('Call has ended');
      if (needsNegotiation) await negotiate();
      _published = track;
    } catch (_) {
      if (video != null && isActive()) {
        if (replaced) {
          try {
            await video.sender.replaceTrack(previous);
          } catch (_) {}
        }
        if (oldDirection != null) {
          try {
            await video.setDirection(oldDirection);
          } catch (_) {}
        }
      }
      rethrow;
    } finally {
      _busy = false;
    }
  }
}
