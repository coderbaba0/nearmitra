import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/peer.dart';
import '../services/nearby_service.dart';
import '../services/streaming_service.dart';

enum StreamerRole { hostCamera, remoteViewer }
enum AudioStreamRole { broadcastMic, listenRemote }

class StreamHubScreen extends ConsumerStatefulWidget {
  const StreamHubScreen({
    super.key,
    required this.service,
    this.targetPeer,
    this.initialStreamType = 'camera',
  });

  final NearbyService service;
  final Peer? targetPeer;
  final String initialStreamType;

  @override
  ConsumerState<StreamHubScreen> createState() => _StreamHubScreenState();
}

class _StreamHubScreenState extends ConsumerState<StreamHubScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final StreamingService _streamingService = StreamingService();
  late TabController _tabController;

  // Video Renderers
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCPeerConnection? _peerConnection;
  final List<RTCIceCandidate> _pendingStreamCandidates = [];

  // Default: OFF (idle). Camera only starts when user explicitly taps Start Host Camera.
  StreamerRole _role = StreamerRole.remoteViewer;
  AudioStreamRole _audioRole = AudioStreamRole.listenRemote;

  bool _isHostActive = false;
  bool _isRemoteConnected = false;
  bool _isConnecting = false;

  // Audio Relay States
  bool _isAudioActive = false;
  bool _isAudioConnecting = false;
  bool _isSpeakerphoneOn = true;
  bool _isMicMuted = false;

  // Local Host Hardware States
  bool _isTorchOn = false;
  bool _isFrontCamera = false;
  bool _isMuted = false;

  // Remote Hardware Controls State
  bool _remoteTorchState = false;
  bool _remoteMicMuted = false;
  bool _isFullScreen = false;

  String _streamStatus = 'Ready to stream';
  String _audioStatus = 'Ready to stream audio';
  Peer? _selectedPeer;
  bool _isDisposing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    _selectedPeer = widget.targetPeer ??
        (widget.service.peers.isNotEmpty ? widget.service.peers.first : null);

    _streamingService.addListener(_onServiceUpdate);
    _setupSignalListeners();
    _initPermissionsAndMedia();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        duration: const Duration(milliseconds: 1800),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _resetStreamState(notifyPeer: true);
    }
  }

  Future<void> _resetStreamState({bool notifyPeer = true}) async {
    if (notifyPeer && _selectedPeer != null) {
      try {
        widget.service.sendWebRtcSignal(_selectedPeer!, 'stream_stopped', {
          'reason': 'Stream reset by user',
        });
      } catch (_) {}
    }

    try {
      _localStream?.getTracks().forEach((t) => t.stop());
      _localStream?.dispose();
    } catch (_) {}
    _localStream = null;

    try {
      _remoteStream?.getTracks().forEach((t) => t.stop());
      _remoteStream?.dispose();
    } catch (_) {}
    _remoteStream = null;

    try {
      _peerConnection?.close();
      _peerConnection?.dispose();
    } catch (_) {}
    _peerConnection = null;
    _pendingStreamCandidates.clear();

    try {
      _localRenderer.srcObject = null;
    } catch (_) {}
    try {
      _remoteRenderer.srcObject = null;
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isHostActive = false;
        _isRemoteConnected = false;
        _isConnecting = false;
        _isAudioActive = false;
        _isAudioConnecting = false;
        _isTorchOn = false;
        _remoteTorchState = false;
        _streamStatus = 'Stream Reset • Normal';
        _audioStatus = 'Audio Reset • Normal';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.restart_alt_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Live stream reset to normal state'),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _initPermissionsAndMedia() async {
    // Only initialize renderers — do NOT auto-start camera.
    // Camera starts only when user explicitly taps "Start Host Camera" button.
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
    } catch (e) {
      debugPrint('[StreamHub] Renderer init error: $e');
    }
    try { Helper.setSpeakerphoneOn(true); } catch (_) {}
  }


  void _setupSignalListeners() {
    // 1. Host receives Remote Control Signals from Viewer
    widget.service.onStreamControl = (peerId, control) async {
      final action = control['action']?.toString();
      if (action == 'toggle_torch') {
        final val = control['value'] == true;
        await _setLocalTorch(val);
        _broadcastStatus();
      } else if (action == 'switch_camera') {
        await _switchLocalCamera();
        _broadcastStatus();
      } else if (action == 'toggle_mic') {
        final val = control['value'] == true;
        _setLocalMicMute(val);
        _broadcastStatus();
      } else if (action == 'torch_status') {
        if (mounted) setState(() => _remoteTorchState = control['value'] == true);
      }
    };

    // 2. Remote Viewer receives Answer from Host
    widget.service.onStreamAnswer = (peerId, answer) async {
      final pc = _peerConnection;
      final sdp = answer['sdp']?.toString();
      if (pc != null && sdp != null && sdp.isNotEmpty) {
        try {
          await pc.setRemoteDescription(
            RTCSessionDescription(
                sdp, answer['sdp_type']?.toString() ?? 'answer'),
          );
          for (final c in _pendingStreamCandidates) {
            await pc.addCandidate(c);
          }
          _pendingStreamCandidates.clear();
          if (mounted) {
            setState(() {
              _isRemoteConnected = true;
              _isAudioActive = true;
              _isConnecting = false;
              _isAudioConnecting = false;
              _streamStatus = 'Live Stream Connected';
              _audioStatus = 'Live Audio Relay Active';
            });
          }
        } catch (e) {
          debugPrint('Error setting remote stream description: $e');
        }
      }
    };

    // 3. Host receives Stream Offer from Remote Viewer
    widget.service.onStreamOffer = (peerId, offer) async {
      final remoteIp = offer['remote_ip']?.toString() ?? offer['sender_ip']?.toString() ?? '';
      final senderName = offer['sender']?.toString() ?? offer['name']?.toString() ?? 'Remote Device';

      Peer peer = _selectedPeer ??
          widget.service.peers.where((p) => p.id == peerId || (remoteIp.isNotEmpty && p.ip == remoteIp)).firstOrNull ??
          Peer(id: peerId, name: senderName, ip: remoteIp.isNotEmpty ? remoteIp : peerId);

      if (remoteIp.isNotEmpty) {
        peer = Peer(
          id: peer.id.isNotEmpty ? peer.id : peerId,
          name: senderName.isNotEmpty && senderName != 'Remote Device' ? senderName : peer.name,
          ip: remoteIp,
        );
      }
      await _handleIncomingStreamOfferAsHost(peer, offer);
    };

    // 4. Remote Viewer receives Stream Rejected
    widget.service.onStreamRejected = (peerId, data) {
      final reason =
          data['reason']?.toString() ?? 'Stream request declined by host';
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isRemoteConnected = false;
          _isAudioConnecting = false;
          _isAudioActive = false;
          _streamStatus = 'Request Denied: $reason';
          _audioStatus = 'Request Denied: $reason';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Access Denied: $reason'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    };

    // 5. Remote Host / Viewer receives Stream Stopped
    widget.service.onStreamStopped = (peerId, data) {
      _resetStreamState(notifyPeer: false);
    };

    // 6. ICE Candidate Exchange
    widget.service.onStreamIceCandidate = (peerId, data) async {
      final candidateStr = data['candidate']?.toString();
      if (candidateStr == null || candidateStr.isEmpty) return;
      final candidate = RTCIceCandidate(
        candidateStr,
        data['sdp_mid']?.toString(),
        int.tryParse('${data['sdp_mline_index'] ?? 0}'),
      );
      final pc = _peerConnection;
      if (pc != null && (await pc.getRemoteDescription()) != null) {
        try {
          await pc.addCandidate(candidate);
        } catch (e) {
          debugPrint('Error adding remote stream candidate: $e');
        }
      } else {
        _pendingStreamCandidates.add(candidate);
      }
    };
  }

  void _broadcastStatus() {
    if (_selectedPeer != null) {
      widget.service.sendWebRtcSignal(_selectedPeer!, 'stream_control', {
        'action': 'torch_status',
        'value': _isTorchOn,
      });
    }
  }

  Future<void> _handleIncomingStreamOfferAsHost(
      Peer peer, Map<String, dynamic> offer) async {
    try {
      final sdp = offer['sdp']?.toString();
      if (sdp == null || sdp.isEmpty) return;

      final streamType = offer['stream_type']?.toString() ?? 'camera';

      // 1. Check OS Hardware Permissions
      final camGranted = await Permission.camera.isGranted;
      final micGranted = await Permission.microphone.isGranted;
      if (!camGranted || !micGranted) {
        final statuses =
            await [Permission.camera, Permission.microphone].request();
        if (statuses[Permission.camera] != PermissionStatus.granted) {
          widget.service.sendWebRtcSignal(peer, 'stream_rejected', {
            'reason': 'Host camera hardware permission not granted',
          });
          return;
        }
      }

      // 2. Check Host Authorization (Trusted vs User Approval)
      final isTrusted = _streamingService.isTrusted(peer.id) ||
          _streamingService.isTrusted(peer.ip);

      if (!isTrusted) {
        if (!mounted) return;
        final bool? allowed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.security_rounded, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                const Text('Stream Permission',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              '${peer.name} (${peer.ip}) wants to access your live ${streamType.toUpperCase()} stream.\n\nDo you allow this remote device to connect?',
              style: const TextStyle(fontSize: 13.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Deny',
                    style: TextStyle(color: Colors.redAccent)),
              ),
              OutlinedButton(
                onPressed: () {
                  if (streamType == 'camera') _streamingService.setAllowCamera(true);
                  if (streamType == 'audio') _streamingService.setAllowAudio(true);
                  Navigator.pop(ctx, true);
                },
                child: const Text('Allow Once'),
              ),
              FilledButton(
                onPressed: () {
                  if (streamType == 'camera') _streamingService.setAllowCamera(true);
                  if (streamType == 'audio') _streamingService.setAllowAudio(true);
                  _streamingService.addTrustedDevice(peer.id);
                  _streamingService.addTrustedDevice(peer.ip);
                  Navigator.pop(ctx, true);
                },
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981)),
                child: const Text('Always Allow'),
              ),
            ],
          ),
        );

        if (allowed != true) {
          widget.service.sendWebRtcSignal(peer, 'stream_rejected', {
            'reason': 'Host user denied stream access request',
          });
          return;
        }
      }

      if (_localStream == null) {
        await _startHostCamera();
      }

      _peerConnection?.close();
      _peerConnection?.dispose();
      _peerConnection = null;
      _pendingStreamCandidates.clear();

      final pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
      });

      pc.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        widget.service.sendWebRtcSignal(peer, 'stream_ice', {
          'candidate': candidate.candidate,
          'sdp_mid': candidate.sdpMid,
          'sdp_mline_index': candidate.sdpMLineIndex,
        });
      };

      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          track.enabled = true;
          await pc.addTrack(track, _localStream!);
        }
      }

      await pc.setRemoteDescription(
        RTCSessionDescription(
            sdp, offer['sdp_type']?.toString() ?? 'offer'),
      );

      for (final c in _pendingStreamCandidates) {
        await pc.addCandidate(c);
      }
      _pendingStreamCandidates.clear();

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      _peerConnection = pc;

      widget.service.sendWebRtcSignal(peer, 'stream_answer', {
        'sdp': answer.sdp,
        'sdp_type': answer.type,
      });

      if (mounted) {
        setState(() {
          _isHostActive = true;
          _streamStatus = 'Streaming Live to ${peer.name}';
        });
      }
    } catch (e) {
      debugPrint('Error handling incoming stream offer on host: $e');
    }
  }

  // --- HOST CAMERA OPERATIONS ---

  Future<void> _startHostCamera() async {
    try {
      _stopHostMediaOnly();

      final mediaConstraints = <String, dynamic>{
        'audio': true,
        'video': {
          'facingMode': _isFrontCamera ? 'user' : 'environment',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 30},
        },
      };

      _localStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;

      if (mounted) {
        setState(() {
          _role = StreamerRole.hostCamera;
          _isHostActive = true;
          _streamStatus = 'Hosting Live Camera • CCTV Ready';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isHostActive = false;
          _streamStatus = 'Camera Error: $e';
        });
      }
    }
  }

  void _stopHostMediaOnly() {
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;
    _localRenderer.srcObject = null;
  }

  Future<void> _stopHostCamera() async {
    _stopHostMediaOnly();
    if (mounted) {
      setState(() {
        _isHostActive = false;
        _isTorchOn = false;
        _streamStatus = 'Host Camera Stopped';
      });
    }
  }

  Future<void> _setLocalTorch(bool on) async {
    if (_localStream == null || _isFrontCamera) return;
    try {
      final videoTrack = _localStream!.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        final hasTorch = await videoTrack.hasTorch();
        if (hasTorch) {
          await videoTrack.setTorch(on);
          if (mounted) setState(() => _isTorchOn = on);
        }
      }
    } catch (e) {
      debugPrint('Torch error: $e');
    }
  }

  Future<void> _switchLocalCamera() async {
    if (_localStream == null) return;
    try {
      final videoTrack = _localStream!.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        await Helper.switchCamera(videoTrack);
        if (mounted) {
          setState(() {
            _isFrontCamera = !_isFrontCamera;
            _isTorchOn = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Switch camera error: $e');
    }
  }

  void _setLocalMicMute(bool muted) {
    if (_localStream == null) return;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !muted;
    }
    if (mounted) setState(() => _isMuted = muted);
  }

  // --- STREAM CONNECTION (CAMERA / AUDIO) ---

  Future<void> _connectToRemoteViewer(String streamType) async {
    final peer = _selectedPeer;
    if (peer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a target device first')),
      );
      return;
    }

    // ── Pre-flight: OS hardware permission check ──────────────────────────
    final isAudio = streamType == 'audio';
    final neededPerms = isAudio
        ? [Permission.microphone]
        : [Permission.camera, Permission.microphone];

    for (final p in neededPerms) {
      final s = await p.status;
      if (!s.isGranted) {
        final granted = await p.request();
        if (!granted.isGranted) {
          if (!mounted) return;
          // Show security/settings dialog instead of crashing
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(
                    p == Permission.camera ? Icons.videocam_off_rounded : Icons.mic_off_rounded,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(width: 8),
                  const Text('Permission Required', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Text(
                p == Permission.camera
                    ? 'Camera permission is required to start CCTV streaming.\n\nPlease allow Camera access in App Settings.'
                    : 'Microphone permission is required to start Audio streaming.\n\nPlease allow Microphone access in App Settings.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    openAppSettings();
                  },
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
          return; // Abort streaming — don't crash
        }
      }
    }
    // ── End permission check ──────────────────────────────────────────────

    setState(() {
      _role = StreamerRole.remoteViewer;
      if (isAudio) {
        _isAudioConnecting = true;
        _isAudioActive = false;
        _audioStatus = 'Connecting audio to ${peer.name}…';
      } else {
        _isConnecting = true;
        _isRemoteConnected = false;
        _streamStatus = 'Connecting to ${peer.name}…';
      }
    });


    try {
      _peerConnection?.close();
      _peerConnection?.dispose();
      _peerConnection = null;
      _pendingStreamCandidates.clear();

      Helper.setSpeakerphoneOn(_isSpeakerphoneOn);

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

      if (!isAudio) {
        await pc.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.RecvOnly,
          ),
        );
      }
      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(
          direction: (isAudio && _audioRole == AudioStreamRole.broadcastMic)
              ? TransceiverDirection.SendRecv
              : TransceiverDirection.RecvOnly,
        ),
      );

      // If user chose to broadcast mic to the other phone:
      if (isAudio && _audioRole == AudioStreamRole.broadcastMic) {
        final micStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
        _localStream = micStream;
        for (final track in micStream.getTracks()) {
          track.enabled = true;
          await pc.addTrack(track, micStream);
        }
      }

      pc.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        widget.service.sendWebRtcSignal(peer, 'stream_ice', {
          'candidate': candidate.candidate,
          'sdp_mid': candidate.sdpMid,
          'sdp_mline_index': candidate.sdpMLineIndex,
        });
      };

      pc.onAddStream = (stream) {
        _remoteStream = stream;
        _remoteRenderer.srcObject = stream;
        if (mounted) {
          setState(() {
            _role = StreamerRole.remoteViewer;
            _isRemoteConnected = true;
            _isConnecting = false;
            _streamStatus = 'Live Feed • ${peer.name}';
          });
        }
      };

      pc.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams.first;
          _remoteRenderer.srcObject = event.streams.first;
        } else if (_remoteStream != null) {
          _remoteStream!.addTrack(event.track);
          _remoteRenderer.srcObject = _remoteStream;
        }
        if (mounted) {
          setState(() {
            _role = StreamerRole.remoteViewer;
            if (isAudio) {
              _isAudioActive = true;
              _isAudioConnecting = false;
              _audioStatus = 'Live Audio Relay • ${peer.name}';
            } else {
              _isRemoteConnected = true;
              _isConnecting = false;
              _streamStatus = 'Live Feed • ${peer.name}';
            }
          });
        }
      };

      pc.onConnectionState = (state) {
        if (!mounted) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          setState(() {
            if (isAudio) {
              _isAudioActive = true;
              _isAudioConnecting = false;
              _audioStatus = 'Connected to ${peer.name}';
            } else {
              _isRemoteConnected = true;
              _isConnecting = false;
              _streamStatus = 'Connected to ${peer.name}';
            }
          });
        } else if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          setState(() {
            if (isAudio) {
              _isAudioActive = false;
              _isAudioConnecting = false;
              _audioStatus = 'Audio Relay Disconnected';
            } else {
              _isRemoteConnected = false;
              _isConnecting = false;
              _streamStatus = 'Stream Disconnected';
            }
          });
        }
      };

      _peerConnection = pc;

      final offer = await pc.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': isAudio ? 0 : 1,
      });
      await pc.setLocalDescription(offer);

      widget.service.sendWebRtcSignal(peer, 'stream_offer', {
        'sdp': offer.sdp,
        'sdp_type': offer.type,
        'stream_type': streamType,
        'audio_mode': _audioRole == AudioStreamRole.broadcastMic ? 'mic' : 'listen',
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          if (isAudio) {
            _isAudioConnecting = false;
            _isAudioActive = false;
            _audioStatus = 'Audio error: $e';
          } else {
            _isConnecting = false;
            _isRemoteConnected = false;
            _streamStatus = 'Failed to connect stream: $e';
          }
        });
      }
    }
  }

  void _sendRemoteControl(String action, [dynamic value]) {
    final peer = _selectedPeer;
    if (peer == null) return;
    widget.service.sendWebRtcSignal(peer, 'stream_control', {
      'action': action,
      if (value != null) 'value': value,
    });
  }

  void _disconnectStream() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _localStream = null;
    _remoteStream?.getTracks().forEach((track) => track.stop());
    _remoteStream?.dispose();
    _remoteStream = null;
    _remoteRenderer.srcObject = null;
    _peerConnection?.close();
    _peerConnection?.dispose();
    _peerConnection = null;
    _isRemoteConnected = false;
    _isConnecting = false;
    _isAudioActive = false;
    _isAudioConnecting = false;
    _isFullScreen = false;
    _streamStatus = 'Disconnected';
    _audioStatus = 'Audio Relay Disconnected';
    if (mounted && !_isDisposing) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    _streamingService.removeListener(_onServiceUpdate);
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _stopHostMediaOnly();
    _disconnectStream();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_isFullScreen) {
      return _buildFullScreenView();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote Streaming',
            style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF10B981),
          labelColor: const Color(0xFF10B981),
          unselectedLabelColor: scheme.onSurfaceVariant,
          tabs: const [
            Tab(icon: Icon(Icons.videocam_rounded), text: 'Camera CCTV'),
            Tab(icon: Icon(Icons.mic_rounded), text: 'Live Audio'),
            Tab(icon: Icon(Icons.security_rounded), text: 'Security'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCameraCctvTab(scheme),
          _buildLiveAudioTab(scheme),
          _buildSecurityHubTab(scheme),
        ],
      ),
    );
  }

  Widget _buildCameraCctvTab(ColorScheme scheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mediaHeight = MediaQuery.sizeOf(context).height;
    final videoCardHeight = mediaHeight * 0.44;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode Switcher (Host Camera vs Remote Viewer)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      if (_role != StreamerRole.hostCamera) {
                        // Request permissions before starting camera
                        final camOk = await Permission.camera.request();
                        final micOk = await Permission.microphone.request();
                        if (!camOk.isGranted) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Camera permission required to host CCTV stream.'),
                                backgroundColor: const Color(0xFF7C3AED),
                                behavior: SnackBarBehavior.floating,
                                action: SnackBarAction(
                                  label: 'Settings',
                                  textColor: Colors.white,
                                  onPressed: openAppSettings,
                                ),
                              ),
                            );
                          }
                          return;
                        }
                        if (!micOk.isGranted && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Microphone permission denied — audio will be muted.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                        setState(() => _role = StreamerRole.hostCamera);
                        await _startHostCamera();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _role == StreamerRole.hostCamera
                            ? const Color(0xFF10B981)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt_rounded,
                              size: 17,
                              color: _role == StreamerRole.hostCamera
                                  ? Colors.white
                                  : scheme.onSurface),
                          const SizedBox(width: 6),
                          Text(
                            'Host Camera (CCTV)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _role == StreamerRole.hostCamera
                                  ? Colors.white
                                  : scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (_role != StreamerRole.remoteViewer) {
                        setState(() => _role = StreamerRole.remoteViewer);
                        _stopHostMediaOnly();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _role == StreamerRole.remoteViewer
                            ? const Color(0xFF10B981)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.monitor_rounded,
                              size: 17,
                              color: _role == StreamerRole.remoteViewer
                                  ? Colors.white
                                  : scheme.onSurface),
                          const SizedBox(width: 6),
                          Text(
                            'Remote Monitor',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _role == StreamerRole.remoteViewer
                                  ? Colors.white
                                  : scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Main Video Feed Canvas Container
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            height: videoCardHeight,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: (_role == StreamerRole.hostCamera && _isHostActive) ||
                        (_role == StreamerRole.remoteViewer &&
                            _isRemoteConnected)
                    ? const Color(0xFF10B981)
                    : Colors.white12,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Camera Renderer or Placeholders
                  if (_role == StreamerRole.hostCamera) ...[
                    if (_isHostActive && _localStream != null)
                      RTCVideoView(
                        _localRenderer,
                        mirror: _isFrontCamera,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    else
                      _buildPlaceholder(
                        icon: Icons.videocam_off_rounded,
                        title: 'Host Camera Inactive',
                        subtitle: 'Tap "Start Host Camera" below',
                      ),
                  ] else ...[
                    if (_remoteRenderer.srcObject != null ||
                        _isRemoteConnected ||
                        _remoteStream != null)
                      RTCVideoView(
                        _remoteRenderer,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    else if (_isConnecting)
                      _buildLoadingPlaceholder('Negotiating Camera Feed…')
                    else
                      _buildPlaceholder(
                        icon: Icons.sensors_off_rounded,
                        title: 'No Remote Feed Connected',
                        subtitle:
                            'Select a peer device below and tap "Connect Feed"',
                      ),
                  ],

                  // Top Professional CCTV HUD (Status, Live Tag, Reset Button, Fullscreen)
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left: Live Status & Resolution Pill (Flexible to prevent right overflow)
                        Flexible(
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: (_role == StreamerRole.hostCamera &&
                                            _isHostActive) ||
                                        (_role == StreamerRole.remoteViewer &&
                                            _isRemoteConnected)
                                    ? const Color(0xFF10B981)
                                    : Colors.white24,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: (_role == StreamerRole.hostCamera &&
                                                _isHostActive) ||
                                            (_role ==
                                                    StreamerRole.remoteViewer &&
                                                _isRemoteConnected)
                                        ? const Color(0xFF10B981)
                                        : Colors.amberAccent,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      if ((_role == StreamerRole.hostCamera &&
                                              _isHostActive) ||
                                          (_role == StreamerRole.remoteViewer &&
                                              _isRemoteConnected))
                                        BoxShadow(
                                          color: const Color(0xFF10B981)
                                              .withValues(alpha: 0.8),
                                          blurRadius: 6,
                                          spreadRadius: 2,
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    _streamStatus,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                                if ((_role == StreamerRole.hostCamera &&
                                        _isHostActive) ||
                                    (_role == StreamerRole.remoteViewer &&
                                        _isRemoteConnected)) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981)
                                          .withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      '1080P HD',
                                      style: TextStyle(
                                        color: Color(0xFF10B981),
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        // Right: Quick Actions (1-Tap Reset & Fullscreen)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 1-Tap Reset / Stop Stream Icon Button (Only in Remote Monitor)
                            if (_role == StreamerRole.remoteViewer)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: (_isRemoteConnected || _isConnecting)
                                      ? Colors.redAccent.withValues(alpha: 0.85)
                                      : Colors.black.withValues(alpha: 0.70),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white24,
                                    width: 1,
                                  ),
                                ),
                                child: IconButton(
                                  constraints: const BoxConstraints(
                                    minWidth: 34,
                                    minHeight: 34,
                                  ),
                                  padding: const EdgeInsets.all(6),
                                  icon: const Icon(
                                    Icons.restart_alt_rounded,
                                    color: Colors.white,
                                    size: 19,
                                  ),
                                  tooltip: 'Reset & Clear Stream',
                                  onPressed: () =>
                                      _resetStreamState(notifyPeer: true),
                                ),
                              ),
                            if (_role == StreamerRole.remoteViewer &&
                                _isRemoteConnected)
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white24,
                                    width: 1,
                                  ),
                                ),
                                child: IconButton(
                                  constraints: const BoxConstraints(
                                    minWidth: 34,
                                    minHeight: 34,
                                  ),
                                  padding: const EdgeInsets.all(6),
                                  icon: const Icon(
                                    Icons.fullscreen_rounded,
                                    color: Colors.white,
                                    size: 19,
                                  ),
                                  tooltip: 'Full Screen View',
                                  onPressed: () =>
                                      setState(() => _isFullScreen = true),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Host Quick Floating Toolbar (Flashlight & Lens Flip)
                  if (_role == StreamerRole.hostCamera && _isHostActive)
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                _isTorchOn
                                    ? Icons.flash_on_rounded
                                    : Icons.flash_off_rounded,
                                color: _isTorchOn
                                    ? Colors.amberAccent
                                    : Colors.white,
                                size: 22,
                              ),
                              tooltip: 'Torch',
                              onPressed: () => _setLocalTorch(!_isTorchOn),
                            ),
                            IconButton(
                              icon: const Icon(Icons.flip_camera_ios_rounded,
                                  color: Colors.white, size: 22),
                              tooltip: 'Flip Camera',
                              onPressed: _switchLocalCamera,
                            ),
                            IconButton(
                              icon: Icon(
                                _isMuted
                                    ? Icons.mic_off_rounded
                                    : Icons.mic_rounded,
                                color: _isMuted
                                    ? Colors.redAccent
                                    : const Color(0xFF10B981),
                                size: 22,
                              ),
                              tooltip: 'Mute Host Mic',
                              onPressed: () => _setLocalMicMute(!_isMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Dynamic Action Controls (Host vs Remote)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _role == StreamerRole.hostCamera
                ? _buildHostControls(scheme)
                : _buildRemoteControls(scheme),
          ),

          const SizedBox(height: 14),

          // Step-by-Step Professional Usage Guide
          _buildUsageGuideCard(isDark, scheme),
        ],
      ),
    );
  }

  Widget _buildHostControls(ColorScheme scheme) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _isHostActive ? _stopHostCamera : _startHostCamera,
            style: FilledButton.styleFrom(
              backgroundColor: _isHostActive
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF10B981),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            icon: Icon(
              _isHostActive
                  ? Icons.stop_circle_rounded
                  : Icons.videocam_rounded,
            ),
            label: Text(
              _isHostActive ? 'Stop Host Camera' : 'Start Host Camera',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRemoteControls(ColorScheme scheme) {
    return Column(
      children: [
        // Peer Device Dropdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              hint: const Text('Select Host Device to Monitor'),
              value: widget.service.peers.contains(_selectedPeer)
                  ? _selectedPeer?.id
                  : (widget.service.peers.isNotEmpty
                      ? widget.service.peers.first.id
                      : null),
              items: widget.service.peers.map((peer) {
                return DropdownMenuItem<String>(
                  value: peer.id,
                  child: Row(
                    children: [
                      const Icon(Icons.phone_android_rounded,
                          size: 18, color: Color(0xFF10B981)),
                      const SizedBox(width: 8),
                      Text(peer.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      Text('(${peer.ip})',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (peerId) {
                final p = widget.service.peers
                    .where((peer) => peer.id == peerId)
                    .firstOrNull;
                if (p != null) {
                  setState(() => _selectedPeer = p);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Connect / Disconnect Buttons
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _isRemoteConnected
                    ? _disconnectStream
                    : () => _connectToRemoteViewer('camera'),
                style: FilledButton.styleFrom(
                  backgroundColor: _isRemoteConnected
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                icon: Icon(
                  _isRemoteConnected
                      ? Icons.link_off_rounded
                      : Icons.sensors_rounded,
                ),
                label: Text(
                  _isRemoteConnected
                      ? 'Disconnect Stream'
                      : (_isConnecting ? 'Connecting…' : 'Connect Camera Feed'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ],
        ),

        // Hardware Controls Over Remote Host
        if (_isRemoteConnected) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final nextTorch = !_remoteTorchState;
                    setState(() => _remoteTorchState = nextTorch);
                    _sendRemoteControl('toggle_torch', nextTorch);
                  },
                  icon: Icon(
                    _remoteTorchState
                        ? Icons.flash_on_rounded
                        : Icons.flash_off_rounded,
                    color: _remoteTorchState
                        ? Colors.amberAccent
                        : const Color(0xFF10B981),
                  ),
                  label: Text(_remoteTorchState ? 'Torch ON' : 'Torch OFF'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _sendRemoteControl('switch_camera'),
                  icon: const Icon(Icons.flip_camera_ios_rounded,
                      color: Color(0xFF10B981)),
                  label: const Text('Flip Lens'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final nextMute = !_remoteMicMuted;
                    setState(() => _remoteMicMuted = nextMute);
                    _sendRemoteControl('toggle_mic', nextMute);
                  },
                  icon: Icon(
                    _remoteMicMuted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                    color: _remoteMicMuted
                        ? Colors.redAccent
                        : const Color(0xFF10B981),
                  ),
                  label: Text(_remoteMicMuted ? 'Host Muted' : 'Host Mic'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildLiveAudioTab(ColorScheme scheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 50),
      child: Column(
        children: [
          // Audio Mode Selector (Listen vs Broadcast)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _audioRole = AudioStreamRole.listenRemote),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _audioRole == AudioStreamRole.listenRemote
                            ? const Color(0xFF10B981)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.hearing_rounded,
                              size: 17,
                              color: _audioRole == AudioStreamRole.listenRemote
                                  ? Colors.white
                                  : scheme.onSurface),
                          const SizedBox(width: 6),
                          Text(
                            'Listen Remote Mic',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _audioRole == AudioStreamRole.listenRemote
                                  ? Colors.white
                                  : scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _audioRole = AudioStreamRole.broadcastMic),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _audioRole == AudioStreamRole.broadcastMic
                            ? const Color(0xFF10B981)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mic_rounded,
                              size: 17,
                              color: _audioRole == AudioStreamRole.broadcastMic
                                  ? Colors.white
                                  : scheme.onSurface),
                          const SizedBox(width: 6),
                          Text(
                            'Broadcast My Voice',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _audioRole == AudioStreamRole.broadcastMic
                                  ? Colors.white
                                  : scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Glowing Audio Visualizer Circle
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isAudioActive
                  ? const Color(0xFF10B981).withValues(alpha: 0.2)
                  : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
              border: Border.all(
                color: _isAudioActive ? const Color(0xFF10B981) : Colors.transparent,
                width: 3,
              ),
              boxShadow: _isAudioActive
                  ? [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.35),
                        blurRadius: 28,
                        spreadRadius: 4,
                      ),
                    ]
                  : [],
            ),
            child: Icon(
              _audioRole == AudioStreamRole.broadcastMic
                  ? Icons.mic_rounded
                  : Icons.surround_sound_rounded,
              size: 58,
              color: _isAudioActive ? const Color(0xFF10B981) : Colors.grey,
            ),
          ),

          const SizedBox(height: 18),

          Text(
            _audioStatus,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            _audioRole == AudioStreamRole.broadcastMic
                ? 'Relaying your microphone live to remote device speakers'
                : 'Listening to remote room microphone in real-time (Baby Monitor / Surveillance)',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
          ),

          const SizedBox(height: 22),

          // Peer Device Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                hint: const Text('Select Target Device'),
                value: widget.service.peers.contains(_selectedPeer)
                    ? _selectedPeer?.id
                    : (widget.service.peers.isNotEmpty
                        ? widget.service.peers.first.id
                        : null),
                items: widget.service.peers.map((peer) {
                  return DropdownMenuItem<String>(
                    value: peer.id,
                    child: Row(
                      children: [
                        const Icon(Icons.phone_android_rounded,
                            size: 18, color: Color(0xFF10B981)),
                        const SizedBox(width: 8),
                        Text(peer.name,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        Text('(${peer.ip})',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (peerId) {
                  final p = widget.service.peers
                      .where((peer) => peer.id == peerId)
                      .firstOrNull;
                  if (p != null) {
                    setState(() => _selectedPeer = p);
                  }
                },
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Audio Start / Stop Button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isAudioActive
                  ? _disconnectStream
                  : () => _connectToRemoteViewer('audio'),
              style: FilledButton.styleFrom(
                backgroundColor: _isAudioActive
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              icon: Icon(
                _isAudioActive
                    ? Icons.stop_circle_rounded
                    : Icons.play_arrow_rounded,
              ),
              label: Text(
                _isAudioActive
                    ? 'Stop Audio Relay'
                    : (_isAudioConnecting ? 'Connecting…' : 'Start Live Audio Relay'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),

          if (_isAudioActive) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final nextMute = !_isMicMuted;
                      setState(() => _isMicMuted = nextMute);
                      _setLocalMicMute(nextMute);
                    },
                    icon: Icon(
                      _isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      color: _isMicMuted ? Colors.redAccent : const Color(0xFF10B981),
                    ),
                    label: Text(_isMicMuted ? 'Muted' : 'Mic ON'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final nextSpeaker = !_isSpeakerphoneOn;
                      setState(() => _isSpeakerphoneOn = nextSpeaker);
                      Helper.setSpeakerphoneOn(nextSpeaker);
                    },
                    icon: Icon(
                      _isSpeakerphoneOn ? Icons.volume_up_rounded : Icons.phone_in_talk_rounded,
                      color: const Color(0xFF10B981),
                    ),
                    label: Text(_isSpeakerphoneOn ? 'Speaker ON' : 'Earpiece'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ],

          // How to Use Audio Guide Card
          _buildAudioUsageGuideCard(isDark, scheme),
        ],
      ),
    );
  }

  Widget _buildFullScreenView() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_remoteStream != null)
              RTCVideoView(
                _remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Text(
                      'Live • ${_selectedPeer?.name ?? "Host"}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        _remoteTorchState
                            ? Icons.flash_on_rounded
                            : Icons.flash_off_rounded,
                        color: _remoteTorchState
                            ? Colors.amberAccent
                            : Colors.white,
                      ),
                      onPressed: () {
                        final nextTorch = !_remoteTorchState;
                        setState(() => _remoteTorchState = nextTorch);
                        _sendRemoteControl('toggle_torch', nextTorch);
                      },
                      tooltip: 'Toggle Remote Torch',
                    ),
                    IconButton(
                      icon: const Icon(Icons.flip_camera_ios_rounded,
                          color: Colors.white),
                      onPressed: () => _sendRemoteControl('switch_camera'),
                      tooltip: 'Flip Remote Lens',
                    ),
                    IconButton(
                      icon: const Icon(Icons.fullscreen_exit_rounded,
                          color: Colors.white),
                      onPressed: () => setState(() => _isFullScreen = false),
                      tooltip: 'Exit Full Screen',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 54, color: Colors.white30),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingPlaceholder(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF10B981)),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityHubTab(ColorScheme scheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trusted = _streamingService.trustedDevices.toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Security Banner Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF064E3B).withValues(alpha: 0.5), const Color(0xFF0F172A)]
                    : [const Color(0xFFECFDF5), const Color(0xFFF1F5F9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.security_rounded, color: Color(0xFF10B981), size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'P2P Local Security',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'All permissions are stored locally on your device. Unverified peers must prompt for permission.',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'STREAMING ACCESS PERMISSIONS',
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.1),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  activeThumbColor: const Color(0xFF10B981),
                  title: const Text('Allow Incoming Camera Access',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text(
                      'Allows trusted nearby peers to request live CCTV stream',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                  value: _streamingService.allowCamera,
                  onChanged: (val) async {
                    await _streamingService.setAllowCamera(val);
                    setState(() {});
                    _toast(val ? 'Camera Access Allowed 📹' : 'Camera Access Disabled 🚫');
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  activeThumbColor: const Color(0xFF10B981),
                  title: const Text('Allow Incoming Audio Access',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Allows peers to stream microphone audio',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                  value: _streamingService.allowAudio,
                  onChanged: (val) async {
                    await _streamingService.setAllowAudio(val);
                    setState(() {});
                    _toast(val ? 'Audio Access Allowed 🎙️' : 'Audio Access Disabled 🚫');
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  activeThumbColor: const Color(0xFF10B981),
                  title: const Text('Allow Screen Casting Stream',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Allows remote viewing of phone screen',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                  value: _streamingService.allowScreen,
                  onChanged: (val) async {
                    await _streamingService.setAllowScreen(val);
                    setState(() {});
                    _toast(val ? 'Screen Stream Allowed 📱' : 'Screen Stream Disabled 🚫');
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Text(
            'ALWAYS-TRUSTED DEVICES',
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.1),
          ),
          const SizedBox(height: 10),
          if (trusted.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
              ),
              alignment: Alignment.center,
              child: const Text(
                'No always-trusted devices configured yet.\nWhen streaming requests arrive, you can choose "Always Trust".',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
              ),
            )
          else
            ...trusted.map((peerId) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.3),
                  ),
                ),
                child: ListTile(
                  leading: const CircleAvatar(
                    radius: 18,
                    backgroundColor: Color(0xFF10B981),
                    child: Icon(Icons.verified_user_rounded, color: Colors.white, size: 18),
                  ),
                  title: Text(peerId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                  subtitle: const Text('Auto-authorized for local media streams', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                    tooltip: 'Revoke Trust',
                    onPressed: () async {
                      await _streamingService.removeTrustedDevice(peerId);
                      setState(() {});
                      _toast('Revoked trust for $peerId');
                    },
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildUsageGuideCard(bool isDark, ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 8),
              const Text(
                'How to Use Remote Streaming:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '1. On Phone A (CCTV Camera): Select "Host Camera (CCTV)" and tap "Start Host Camera".\n'
            '2. On Phone B (Monitor Viewer): Select "Remote Monitor", choose Phone A from the list, and tap "Connect Camera Feed".\n'
            '3. Phone B can remotely flip camera lens, toggle flashlight 🔦, or view in immersive full screen!',
            style: TextStyle(fontSize: 12.5, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioUsageGuideCard(bool isDark, ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 8),
              const Text(
                'How to Use Live Audio Relay:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '1. Listen Mode: Select "Listen Remote Mic", choose the peer device from the dropdown, and tap "Start Audio Relay" to hear live surroundings.\n'
            '2. Walkie-Talkie Broadcast: Select "Broadcast My Mic" to speak directly to the remote phone\'s speaker.\n'
            '3. Seamless Controls: Easily toggle Speakerphone / Earpiece mode or Mute your mic anytime during the active audio session.',
            style: TextStyle(fontSize: 12.5, height: 1.45),
          ),
        ],
      ),
    );
  }
}
