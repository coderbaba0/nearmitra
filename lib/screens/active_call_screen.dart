import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/peer.dart';
import '../services/call_service.dart';
import '../services/nearby_service.dart';

class ActiveCallScreen extends ConsumerStatefulWidget {
  const ActiveCallScreen({
    super.key,
    required this.peer,
    required this.service,
    required this.isVideoCall,
    required this.isIncoming,
    this.onEndCall,
  });

  final Peer peer;
  final NearbyService service;
  final bool isVideoCall;
  final bool isIncoming;
  final VoidCallback? onEndCall;

  @override
  ConsumerState<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends ConsumerState<ActiveCallScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  Timer? _callTimer;
  Timer? _ringTimeoutTimer;
  int _secondsElapsed = 0;

  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isVideoEnabled = true;
  bool _peerVideoEnabled = true;
  bool _isScreenSharing = false;
  bool _isCallConnected = false;
  bool _renderersReady = false;
  bool _hasRemoteDescription = false;
  bool _isFrontCamera = true;
  bool _isViewSwapped = false;
  bool _isPipLarge = false;
  Offset _pipPosition = const Offset(16, 76);
  String _statusText = 'Ringing…';

  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  Completer<void>? _prepareCompleter;
  MediaStream? _localStream;
  MediaStream? _screenStream;
  MediaStream? _remoteStream;
  final List<RTCIceCandidate> _pendingCandidates = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _localRenderer = RTCVideoRenderer();
    _remoteRenderer = RTCVideoRenderer();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _isVideoEnabled = widget.isVideoCall;
    _peerVideoEnabled = widget.isVideoCall;
    _isSpeakerOn = widget.isVideoCall;

    // Mark call active so background CallKit event transitions do not abort the call
    CallService().setCallActive(true);

    _setupSignalListeners();
    _initCallFlow();
  }

  bool _matchesCallPeer(String id)=>id==widget.peer.id || id==widget.peer.ip || widget.service.peers.any((peer)=>peer.id==id && peer.ip==widget.peer.ip);
  void _setupSignalListeners() {
    widget.service.onCallAcceptedByPeer = (peerId) {
      if(!_matchesCallPeer(peerId))return;
      if (!mounted) return;
      _ringTimeoutTimer?.cancel();
      _ringTimeoutTimer = null;
      if (!_isCallConnected) {
        setState(() {
          _statusText = 'Connecting…';
        });
        unawaited(_startCallerOffer());
      }
    };

    widget.service.onCallDeclinedByPeer = (peerId) {
      if(!_matchesCallPeer(peerId))return;
      if (!mounted) return;
      setState(() {
        _statusText = 'Call Declined';
      });
      Future.delayed(const Duration(milliseconds: 900), _endCallLocal);
    };

    widget.service.onCallEndedByPeer = (peerId) {
      if(!_matchesCallPeer(peerId))return;
      if (!mounted) return;
      setState(() {
        _statusText = 'Call Ended';
      });
      Future.delayed(const Duration(milliseconds: 700), _endCallLocal);
    };

    widget.service.onCallVideoToggledByPeer = (peerId, isVideo) {
      if(!_matchesCallPeer(peerId))return;
      if (!mounted) return;
      setState(() {
        _peerVideoEnabled = isVideo;
      });
    };

    widget.service.onWebRtcOffer = (peerId, offer) {
      if(!_matchesCallPeer(peerId))return;
      unawaited(_handleOffer(offer));
    };

    widget.service.onWebRtcAnswer = (peerId, answer) {
      if(!_matchesCallPeer(peerId))return;
      unawaited(_handleAnswer(answer));
    };

    widget.service.onWebRtcIceCandidate = (peerId, candidate) {
      if(!_matchesCallPeer(peerId))return;
      unawaited(_handleRemoteCandidate(candidate));
    };
  }

  Future<void> _initCallFlow() async {
    await _prepareWebRtc();
    if (!mounted) return;
    if(widget.isIncoming){
      _ringTimeoutTimer=Timer(const Duration(seconds:40),(){if(mounted&&!_isCallConnected){setState(()=>_statusText='Nearby media connection timed out');widget.service.sendCallSignal(widget.peer,'call_ended');Future.delayed(const Duration(milliseconds:1200),_endCallLocal);}});
    }

    if(_peerConnection==null){if(mounted)setState(()=>_statusText='Could not initialize microphone/camera');if(widget.isIncoming)await widget.service.sendCallSignal(widget.peer,'call_declined');return;}
    if (widget.isIncoming) {
      widget.service.sendCallSignal(widget.peer, 'call_accepted');
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_isCallConnected) {
          widget.service.sendCallSignal(widget.peer, 'call_accepted');
        }
      });
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && !_isCallConnected) {
          widget.service.sendCallSignal(widget.peer, 'call_accepted');
        }
      });
      setState(() {
        _statusText = 'Connecting…';
      });
    } else {
      if(_peerConnection==null){if(mounted)setState(()=>_statusText='Could not open microphone/camera');return;}
      final sent=await widget.service.sendCallInvite(widget.peer,widget.isVideoCall);
      if(!mounted)return;
      if(!sent){setState(()=>_statusText='Could not reach Nearby device');return;}
      setState(() {
        _statusText = 'Ringing…';
      });
      _ringTimeoutTimer?.cancel();
      _ringTimeoutTimer = Timer(const Duration(seconds: 40), () {
        if (mounted && !_isCallConnected) {
          setState(() => _statusText = 'No Answer');
          widget.service.sendCallSignal(widget.peer, 'call_ended');
          Future.delayed(const Duration(milliseconds: 1200), _endCallLocal);
        }
      });
    }
  }

  Future<void> _prepareWebRtc() async {
    if (_peerConnection != null) return;
    if (_prepareCompleter != null) {
      return _prepareCompleter!.future;
    }
    _prepareCompleter = Completer<void>();

    try {
      // 1. Ensure audio permission is granted
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        await Permission.microphone.request();
      }

      // 2. Ensure camera permission if video call
      if (widget.isVideoCall) {
        final camStatus = await Permission.camera.status;
        if (!camStatus.isGranted) {
          await Permission.camera.request();
        }
      }
      try {
        await _localRenderer.initialize();
      } catch (_) {}
      try {
        await _remoteRenderer.initialize();
      } catch (_) {}

      final mediaConstraints = <String, dynamic>{
        'audio': {
          'mandatory': {
            'googEchoCancellation': true,
            'googAutoGainControl': true,
            'googNoiseSuppression': true,
            'googHighpassFilter': true,
          },
          'optional': [],
        },
        'video': widget.isVideoCall
            ? {
                'mandatory': {
                  'minWidth': '640',
                  'minHeight': '480',
                  'minFrameRate': '30',
                },
                'facingMode': 'user',
                'optional': [],
              }
            : false,
      };

      try {
        _localStream =
            await navigator.mediaDevices.getUserMedia(mediaConstraints);
      } catch (mediaError) {
        debugPrint('[ActiveCall] Media capture error: $mediaError, attempting simplified constraints');
        try {
          _localStream = await navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': widget.isVideoCall ? {'facingMode': 'user'} : false,
          });
        } catch (mediaError2) {
          debugPrint('[ActiveCall] Secondary error: $mediaError2, attempting audio-only fallback');
          _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
          if (mounted) {
            setState(() {
              _isVideoEnabled = false;
            });
          }
        }
      }

      if (widget.isVideoCall && _isVideoEnabled && _localStream != null) {
        try {
          _localRenderer.srcObject = _localStream;
        } catch (_) {}
      }

      final pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
        'mandatory': {},
        'optional': [
          {'DtlsSrtpKeyAgreement': true},
        ],
      });

      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          track.enabled = true;
          await pc.addTrack(track, _localStream!);
        }
      }

      pc.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        widget.service.sendWebRtcSignal(widget.peer, 'webrtc_ice', {
          'candidate': candidate.candidate,
          'sdp_mid': candidate.sdpMid,
          'sdp_mline_index': candidate.sdpMLineIndex,
        });
      };

      pc.onAddStream = (stream) {
        _remoteStream = stream;
        _remoteRenderer.srcObject = stream;
        for (final track in stream.getTracks()) {
          track.enabled = true;
        }
        if (mounted) {
          setState(() {
            _renderersReady = true;
          });
        }
        Helper.setSpeakerphoneOn(_isSpeakerOn);
      };

      pc.onTrack = (event) async {
        event.track.enabled = true;
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams.first;
          _remoteRenderer.srcObject = event.streams.first;
        } else {
          _remoteStream ??= await createLocalMediaStream('remote_stream_${widget.peer.id}');
          _remoteStream!.addTrack(event.track);
          _remoteRenderer.srcObject = _remoteStream;
        }
        if (mounted) {
          setState(() {
            _renderersReady = true;
          });
        }
        Helper.setSpeakerphoneOn(_isSpeakerOn);
      };

      pc.onConnectionState = (state) {
        if (!mounted) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _markCallConnected();
        } else if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          if (_isCallConnected) {
            setState(() => _statusText = 'Media disconnected');
          }
        }
      };

      pc.onIceConnectionState = (state) {
        if (!mounted) return;
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _markCallConnected();
        }
      };

      _peerConnection = pc;
      if (mounted) {
        setState(() => _renderersReady = true);
      }
      await Helper.setSpeakerphoneOn(_isSpeakerOn);
      if (!_prepareCompleter!.isCompleted) {
        _prepareCompleter!.complete();
      }
    } catch (e) {
      debugPrint('WebRTC initialization error: $e');
      if (_prepareCompleter != null && !_prepareCompleter!.isCompleted) {
        _prepareCompleter!.complete();
      }
      _prepareCompleter = null;
      if (mounted) {
        setState(() {
          _statusText = 'Media initialization failed';
        });
      }
    }
  }

  void _markCallConnected() {
    if (!mounted) return;
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
    final wasConnected = _isCallConnected;
    if (!wasConnected) {
      _startTimer();
    }
    setState(() {
      _isCallConnected = true;
      _statusText = 'Connected';
    });
  }

  bool _callerOfferStarted=false;
  Future<void> _startCallerOffer() async {
    if (_isCallConnected || _callerOfferStarted || widget.isIncoming) return;
    _callerOfferStarted=true;
    await _prepareWebRtc();
    final pc = _peerConnection;
    if (pc == null) return;

    try {
      final offer = await pc.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.isVideoCall,
      });
      await pc.setLocalDescription(offer);
      await widget.service.sendWebRtcSignal(widget.peer, 'webrtc_offer', {
        'sdp': offer.sdp,
        'sdp_type': offer.type,
        'is_video': widget.isVideoCall,
      });
    } catch (e) {
      _callerOfferStarted=false;
      debugPrint('Error creating WebRTC offer: $e');
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> offer) async {
    await _prepareWebRtc();
    final pc = _peerConnection;
    final sdp = offer['sdp']?.toString();
    if (pc == null || sdp == null || sdp.isEmpty) return;

    try {
      await pc.setRemoteDescription(
          RTCSessionDescription(sdp, offer['sdp_type']?.toString() ?? 'offer'));
      _hasRemoteDescription = true;
      await _drainPendingCandidates();
      final answer = await pc.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.isVideoCall,
      });
      await pc.setLocalDescription(answer);
      await widget.service.sendWebRtcSignal(widget.peer, 'webrtc_answer', {
        'sdp': answer.sdp,
        'sdp_type': answer.type,
      });
      if(mounted)setState(()=>_statusText='Connecting media…');
    } catch (e) {
      debugPrint('Error handling WebRTC offer: $e');
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> answer) async {
    final pc = _peerConnection;
    final sdp = answer['sdp']?.toString();
    if (pc == null || sdp == null || sdp.isEmpty) return;

    try {
      await pc.setRemoteDescription(
          RTCSessionDescription(sdp, answer['sdp_type']?.toString() ?? 'answer'));
      _hasRemoteDescription = true;
      await _drainPendingCandidates();
      if(mounted)setState(()=>_statusText='Connecting media…');
    } catch (e) {
      debugPrint('Error handling WebRTC answer: $e');
    }
  }

  Future<void> _handleRemoteCandidate(Map<String, dynamic> data) async {
    final candidateText = data['candidate']?.toString();
    if (candidateText == null || candidateText.isEmpty) return;
    final candidate = RTCIceCandidate(
      candidateText,
      data['sdp_mid']?.toString() ?? data['sdpMid']?.toString(),
      int.tryParse('${data['sdp_mline_index'] ?? data['sdpMLineIndex'] ?? 0}'),
    );
    if (!_hasRemoteDescription || _peerConnection == null) {
      _pendingCandidates.add(candidate);
      return;
    }
    try {
      await _peerConnection!.addCandidate(candidate);
    } catch (e) {
      debugPrint('Error adding ICE candidate: $e');
    }
  }

  Future<void> _drainPendingCandidates() async {
    final pc = _peerConnection;
    if (pc == null) return;
    for (final candidate in _pendingCandidates) {
      try {
        await pc.addCandidate(candidate);
      } catch (_) {}
    }
    _pendingCandidates.clear();
  }

  void _startTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isCallConnected) {
        setState(() {
          _secondsElapsed++;
        });
      }
    });
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  void _endCall() {
    widget.service.sendCallSignal(widget.peer, 'call_ended');
    _endCallLocal();
  }

  void _endCallLocal() {
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
    _callTimer?.cancel();
    CallService().resetCallActiveState();
    widget.onEndCall?.call();
    if (mounted) {
      Navigator.of(context).pop(_secondsElapsed);
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !_isMuted;
    });
  }

  Future<void> _toggleSpeaker() async {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    try {
      await Helper.setSpeakerphoneOn(_isSpeakerOn);
    } catch (_) {}
  }

  void _toggleVideo() {
    setState(() {
      _isVideoEnabled = !_isVideoEnabled;
    });
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = _isVideoEnabled;
    });
    widget.service.sendCallSignal(widget.peer, 'call_video_toggle',
        isVideo: _isVideoEnabled);
  }

  Future<void> _switchCamera() async {
    if (_localStream == null || _isScreenSharing) return;
    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isNotEmpty) {
      try {
        await Helper.switchCamera(videoTracks.first);
        setState(() {
          _isFrontCamera = !_isFrontCamera;
        });
      } catch (e) {
        debugPrint('Error switching camera: $e');
      }
    }
  }

  Future<void> _handleBackPress() async {
    if (_isScreenSharing) {
      try {
        await const MethodChannel('farmitra_nearby/network')
            .invokeMethod('minimizeApp');
      } catch (_) {
        _toast('Screen sharing active in background');
      }
      return;
    }

    if (_isCallConnected) {
      try {
        final entered = await const MethodChannel('farmitra_nearby/network')
            .invokeMethod<bool>('enterPipMode');
        if (entered != true) {
          await const MethodChannel('farmitra_nearby/network')
              .invokeMethod('minimizeApp');
        }
      } catch (_) {
        _toast('Call is active • Tap red button to end call');
      }
      return;
    }

    _endCall();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool _isRequestingScreenShare = false;

  Future<void> _toggleScreenShare() async {
    if (_isScreenSharing) {
      await _stopScreenShare();
      return;
    }

    final pc = _peerConnection;
    if (pc == null) {
      _toast('Please wait for call to connect');
      return;
    }

    _isRequestingScreenShare = true;
    try {
      if (Theme.of(context).platform == TargetPlatform.android) {
        try {
          await const MethodChannel('farmitra_nearby/network')
              .invokeMethod('startMediaProjectionService');
          await Future.delayed(const Duration(milliseconds: 150));
        } catch (_) {}
      }

      final screenStream = await navigator.mediaDevices.getDisplayMedia({
        'audio': false,
        'video': true,
      });
      _isRequestingScreenShare = false;

      final screenTracks = screenStream.getVideoTracks();
      if (screenTracks.isEmpty) {
        _toast('Could not start screen capture');
        return;
      }

      final screenTrack = screenTracks.first;
      screenTrack.onEnded = () {
        if (mounted && _isScreenSharing) {
          _stopScreenShare();
        }
      };

      final senders = await pc.getSenders();
      bool replaced = false;
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          await sender.replaceTrack(screenTrack);
          replaced = true;
        }
      }

      if (!replaced) {
        await pc.addTrack(screenTrack, screenStream);
        final offer = await pc.createOffer({
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': 1,
        });
        await pc.setLocalDescription(offer);
        await widget.service.sendWebRtcSignal(widget.peer, 'webrtc_offer', {
          'sdp': offer.sdp,
          'sdp_type': offer.type,
          'is_video': true,
          'is_screen': true,
        });
      }

      _screenStream = screenStream;
      try {
        await _localRenderer.initialize();
      } catch (_) {}
      try {
        _localRenderer.srcObject = screenStream;
      } catch (_) {}

      setState(() {
        _isScreenSharing = true;
        _isVideoEnabled = true;
      });

      widget.service.sendCallSignal(widget.peer, 'call_video_toggle',
          isVideo: true);
      _toast('Screen sharing active');
    } catch (e) {
      _isRequestingScreenShare = false;
      debugPrint('Screen sharing start error: $e');
      _toast('Screen sharing cancelled');
    }
  }

  Future<void> _stopScreenShare() async {
    if (!_isScreenSharing) return;

    try {
      for (final track in _screenStream?.getTracks() ?? <MediaStreamTrack>[]) {
        await track.stop();
      }
      await _screenStream?.dispose();
      _screenStream = null;

      final videoTracks = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
      final cameraTrack = videoTracks.isNotEmpty ? videoTracks.first : null;
      final pc = _peerConnection;
      if (pc != null && cameraTrack != null) {
        final senders = await pc.getSenders();
        for (final sender in senders) {
          if (sender.track?.kind == 'video') {
            await sender.replaceTrack(cameraTrack);
          }
        }
      }

      _localRenderer.srcObject = _localStream;

      setState(() {
        _isScreenSharing = false;
      });
      _toast('Screen sharing stopped');
    } catch (e) {
      debugPrint('Screen sharing stop error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_isRequestingScreenShare) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_isCallConnected && _isVideoEnabled && !_isScreenSharing) {
        _enterPipMode();
      }
    }
  }

  Future<void> _enterPipMode() async {
    try {
      const MethodChannel('farmitra_nearby/network')
          .invokeMethod('enterPipMode');
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CallService().setCallActive(false);
    CallService().endAllCalls();
    _pulseController.dispose();
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
    _callTimer?.cancel();
    _closeWebRtc();
    super.dispose();
  }

  Future<void> _closeWebRtc() async {
    try {
      if (_screenStream != null) {
        for (final track in _screenStream!.getTracks()) {
          try {
            await track.stop();
          } catch (_) {}
        }
        try {
          await _screenStream!.dispose();
        } catch (_) {}
        _screenStream = null;
      }

      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          try {
            await track.stop();
          } catch (_) {}
        }
        try {
          await _localStream!.dispose();
        } catch (_) {}
        _localStream = null;
      }

      try {
        _localRenderer.srcObject = null;
        _remoteRenderer.srcObject = null;
      } catch (_) {}

      if (_peerConnection != null) {
        try {
          await _peerConnection!.close();
        } catch (_) {}
        try {
          await _peerConnection!.dispose();
        } catch (_) {}
        _peerConnection = null;
      }

      try {
        await _localRenderer.dispose();
      } catch (_) {}
      try {
        await _remoteRenderer.dispose();
      } catch (_) {}
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final showVideoView = _isVideoEnabled || _peerVideoEnabled || _isScreenSharing;
    final size = MediaQuery.of(context).size;
    final isSystemPip = size.height < 320 || size.width < 250;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackPress();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Stack(
            children: [
              // Main View: Video View or Audio Gradient (no AnimatedSwitcher to avoid SurfaceView/TextureView collisions)
              Positioned.fill(
                child: showVideoView ? _buildVideoView(isSystemPip) : _buildAudioView(),
              ),

              // Top Header: Peer Name & Call Status / Live Timer / Screen Share Indicator (hidden in system PiP)
              if (!isSystemPip)
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: _buildTopHeader(),
                ),

              // Bottom Action Bar Controls (hidden in system PiP)
              if (!isSystemPip)
                Positioned(
                  bottom: 28,
                  left: 16,
                  right: 16,
                  child: _buildControlBar(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.white, size: 26),
            tooltip: 'Minimize Call',
            onPressed: _handleBackPress,
          ),
          CircleAvatar(
            radius: 18,
            backgroundColor: _isScreenSharing
                ? const Color(0xFF3B82F6)
                : const Color(0xFF10B981),
            child: _isScreenSharing
                ? const Icon(
                    Icons.screen_share_rounded,
                    color: Colors.white,
                    size: 20,
                  )
                : Text(
                    widget.peer.name.isNotEmpty
                        ? widget.peer.name[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.peer.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_isScreenSharing) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'SHARING',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _isCallConnected
                      ? _formatDuration(_secondsElapsed)
                      : _statusText,
                  style: TextStyle(
                    color: _isCallConnected
                        ? const Color(0xFF10B981)
                        : Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (widget.isVideoCall && _isVideoEnabled && !_isScreenSharing)
            IconButton(
              icon: const Icon(Icons.flip_camera_ios_rounded,
                  color: Colors.white, size: 22),
              tooltip: 'Switch Camera',
              onPressed: _switchCamera,
            ),
        ],
      ),
    );
  }

  Widget _buildVideoView(bool isSystemPip) {
    final screenSize = MediaQuery.of(context).size;
    final pipWidth = _isPipLarge ? 140.0 : 105.0;
    final pipHeight = _isPipLarge ? 200.0 : 155.0;

    final mainRenderer = _isViewSwapped ? _localRenderer : _remoteRenderer;
    final pipRenderer = _isViewSwapped ? _remoteRenderer : _localRenderer;
    final isMainVideoActive = _isViewSwapped
        ? ((_isVideoEnabled || _isScreenSharing) && _localStream != null)
        : (_peerVideoEnabled && _remoteRenderer.srcObject != null);
    final isPipVideoActive = _isViewSwapped
        ? (_peerVideoEnabled && _remoteRenderer.srcObject != null)
        : ((_isVideoEnabled || _isScreenSharing) && _localStream != null);

    return Container(
      key: const ValueKey('video_view_container'),
      color: const Color(0xFF020617),
      child: Stack(
        children: [
          // 1. Full Screen Video Layer
          Positioned.fill(
            child: (_renderersReady && isMainVideoActive)
                ? RTCVideoView(
                    mainRenderer,
                    key: const ValueKey('main_rtc_view'),
                    mirror: _isViewSwapped && _isFrontCamera && !_isScreenSharing,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: isSystemPip ? 28 : 52,
                          backgroundColor: const Color(0xFF1E293B),
                          child: Icon(
                            _isViewSwapped
                                ? (_isVideoEnabled
                                    ? Icons.videocam_rounded
                                    : Icons.videocam_off_rounded)
                                : (_peerVideoEnabled
                                    ? Icons.videocam_rounded
                                    : Icons.videocam_off_rounded),
                            size: isSystemPip ? 24 : 44,
                            color: const Color(0xFF10B981),
                          ),
                        ),
                        if (!isSystemPip) ...[
                          const SizedBox(height: 16),
                          Text(
                            _isViewSwapped
                                ? 'Your camera is off'
                                : (_peerVideoEnabled
                                    ? (_isCallConnected
                                        ? 'Connecting video stream…'
                                        : 'Ringing ${widget.peer.name}…')
                                    : '${widget.peer.name} turned camera off'),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),

          // 2. Interactive Draggable & Tap-to-Swap Floating PIP Window (only in full app mode)
          if (!isSystemPip && _renderersReady && (_isVideoEnabled || _peerVideoEnabled || _isScreenSharing))
            Positioned(
              left: _pipPosition.dx.clamp(12.0, screenSize.width - pipWidth - 12.0),
              top: _pipPosition.dy.clamp(70.0, screenSize.height - pipHeight - 120.0),
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _pipPosition += details.delta;
                  });
                },
                onTap: () {
                  setState(() {
                    _isViewSwapped = !_isViewSwapped;
                  });
                },
                onDoubleTap: () {
                  setState(() {
                    _isPipLarge = !_isPipLarge;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: pipWidth,
                  height: pipHeight,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _isScreenSharing
                          ? const Color(0xFF3B82F6)
                          : const Color(0xFF10B981).withValues(alpha: 0.85),
                      width: 2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      color: const Color(0xFF000000),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: isPipVideoActive
                                ? ColoredBox(
                                    color: Colors.black,
                                    child: RTCVideoView(
                                      pipRenderer,
                                      key: const ValueKey('pip_rtc_view'),
                                      mirror: !_isViewSwapped &&
                                          _isFrontCamera &&
                                          !_isScreenSharing,
                                      objectFit: RTCVideoViewObjectFit
                                          .RTCVideoViewObjectFitCover,
                                    ),
                                  )
                                : Container(
                                    color: const Color(0xFF0F172A),
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            _isViewSwapped
                                                ? Icons.person_rounded
                                                : Icons.videocam_off_rounded,
                                            color: const Color(0xFF10B981)
                                                .withValues(alpha: 0.7),
                                            size: 26,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _isViewSwapped
                                                ? widget.peer.name
                                                : 'You',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                          ),
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.touch_app_rounded,
                                color: Colors.white70,
                                size: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAudioView() {
    return Container(
      key: const ValueKey('audio_view'),
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.2,
          colors: [
            Color(0xFF1E293B),
            Color(0xFF0F172A),
            Color(0xFF020617),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final scale = _isCallConnected
                    ? 1.0
                    : 1.0 + (_pulseController.value * 0.08);
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF10B981).withValues(
                          alpha: _isCallConnected ? 0.12 : 0.25),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(
                              alpha: _isCallConnected ? 0.15 : 0.4),
                          blurRadius: 36,
                          spreadRadius: _isCallConnected ? 4 : 12,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 64,
                      backgroundColor: const Color(0xFF10B981),
                      child: Text(
                        widget.peer.name.isNotEmpty
                            ? widget.peer.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            Text(
              widget.peer.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isCallConnected
                  ? _formatDuration(_secondsElapsed)
                  : _statusText,
              style: TextStyle(
                color: _isCallConnected
                    ? const Color(0xFF10B981)
                    : Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'P2P Direct • ${widget.peer.ip}',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mute Mic
          _buildActionButton(
            icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            tooltip: _isMuted ? 'Unmute' : 'Mute',
            isActive: _isMuted,
            activeColor: Colors.orangeAccent,
            onPressed: _toggleMute,
          ),

          // Speaker/Earpiece
          _buildActionButton(
            icon: _isSpeakerOn
                ? Icons.volume_up_rounded
                : Icons.volume_down_rounded,
            tooltip: _isSpeakerOn ? 'Speaker' : 'Earpiece',
            isActive: _isSpeakerOn,
            activeColor: const Color(0xFF10B981),
            onPressed: _toggleSpeaker,
          ),

          // Toggle Video
          _buildActionButton(
            icon: _isVideoEnabled
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            tooltip: _isVideoEnabled ? 'Turn off video' : 'Turn on video',
            isActive: _isVideoEnabled,
            activeColor: const Color(0xFF10B981),
            onPressed: _toggleVideo,
          ),

          // Live Screen Share
          _buildActionButton(
            icon: _isScreenSharing
                ? Icons.stop_screen_share_rounded
                : Icons.screen_share_rounded,
            tooltip: !_isCallConnected
                ? 'Screen share available when connected'
                : (_isScreenSharing ? 'Stop Screen Share' : 'Share Screen'),
            isActive: _isScreenSharing,
            isEnabled: _isCallConnected,
            activeColor: const Color(0xFF3B82F6),
            onPressed: () {
              if (!_isCallConnected) {
                _toast('Please wait for call to connect first');
                return;
              }
              _toggleScreenShare();
            },
          ),

          // End Call
          FloatingActionButton.small(
            heroTag: 'end_call_btn',
            backgroundColor: const Color(0xFFEF4444),
            elevation: 4,
            onPressed: _endCall,
            child: const Icon(Icons.call_end_rounded,
                color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    bool isEnabled = true,
    required Color activeColor,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Opacity(
        opacity: isEnabled ? 1.0 : 0.4,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isActive
                ? activeColor.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? activeColor : Colors.white24,
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            color: isActive ? activeColor : Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
