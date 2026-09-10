import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';


import 'about_screen.dart';
import 'active_call_screen.dart';
import 'activity_logs_screen.dart';
import 'ai_fleet_screen.dart';
import 'ai_settings_screen.dart';
import 'device_profile_screen.dart';
import 'qr_scanner_screen.dart';
import 'stream_hub_screen.dart';
import '../main.dart';
import '../providers/ai_settings_providers.dart';
import '../services/ai_settings_service.dart';
import '../services/call_service.dart';
import '../services/streaming_service.dart';
import '../models/chat_item.dart';
import '../models/p2p_peer.dart';
import '../models/peer.dart';
import '../services/file_opener_service.dart';
import '../services/history_service.dart';
import '../services/nearby_service.dart';
import '../services/notification_service.dart';
import '../services/wifi_direct_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/p2p_qr_widget.dart';
import '../widgets/p2p_radar_view.dart';
import '../widgets/peer_tile.dart';
import '../widgets/transfer_card.dart';
import 'wan_active_session_screen.dart';
import '../models/wan_models.dart';
import '../services/wan_service.dart';
import '../services/wan_webrtc_manager.dart';
import '../services/firebase_presence_service.dart';
import '../widgets/wan_pair_dialog.dart';
import '../widgets/wan_radar_view.dart';
import '../widgets/home_walkthrough_guide.dart';
import '../widgets/forward_message_dialog.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.service});

  final NearbyService service;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

enum ChatMode { people, ai }
enum ConnectionMode { lan, p2p, wan }

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  final _message = TextEditingController();
  final _scroll = ScrollController();
  final _historyService = HistoryService();
  final _wifiDirectService = WifiDirectService();
  StreamSubscription<String?>? _notificationSub;
  StreamSubscription<Map<String, String>>? _replySub;
  ConnectionMode _connectionMode = ConnectionMode.lan;
  final List<ChatItem> _history = [];
  String? _selectedPeerId;
  bool _showLogs = false;
  bool _scanning = false;
  ChatMode _chatMode = ChatMode.people;
  bool _aiThinking = false;
  int _chatDisplayCount = 20;
  int _bottomNavIndex = 0;
  DateTime? _lastBackPressTime;
  Timer? _peerStatusRefreshTimer;
  final GlobalKey _nearbyTabKey = GlobalKey();
  final GlobalKey _p2pTabKey = GlobalKey();
  final GlobalKey _wanTabKey = GlobalKey();
  bool _showWalkthrough = false;
  final WanService _wanService = WanService();
  final WanWebRtcManager _wanRtcManager = WanWebRtcManager();
  final FirebasePresenceService _firebasePresenceService = FirebasePresenceService();
  ChatItem? _replyingToItem;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.service.addListener(_onServiceChanged);
    _wanService.addListener(_onServiceChanged);
    _wanRtcManager.addListener(_onServiceChanged);
    _firebasePresenceService.addListener(_onServiceChanged);
    _historyService.addListener(_onHistoryChanged);
    _scroll.addListener(_onScroll);
    _peerStatusRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() {});
    });
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      widget.service.isAppInForeground = true;
      _wanService.isAppInForeground = true;
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.inactive ||
               state == AppLifecycleState.hidden) {
      widget.service.isAppInForeground = false;
      _wanService.isAppInForeground = false;
    }
  }

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.pixels <= 40) {
      final fullLen = _fullCurrentChat.length;
      if (_chatDisplayCount < fullLen) {
        setState(() {
          _chatDisplayCount = math.min(_chatDisplayCount + 20, fullLen);
        });
      }
    }
  }

  Future<void> _init() async {
    await AiSettingsService().load();
    _history.addAll(await _historyService.load());
    await widget.service.start();
    await _wanService.init();
    _wanRtcManager.init();
    _wanService.addListener(() {
      if (mounted) setState(() {});
    });
    _wanRtcManager.addListener(() {
      if (mounted) setState(() {});
    });
    _wanService.onIncomingPairRequest = (request) {
      if (!mounted) return;
      _showIncomingPairRequestDialog(request);
    };
    _wanRtcManager.onIncomingSessionRequest = (session) async {
      if (!mounted) return;
      if (_wanService.isDeviceTrusted(session.callerId)) {
        final peer = _wanService.trustedDevicesList.firstWhere(
          (d) => d.id == session.callerId,
          orElse: () => WanDevice(
            id: session.callerId,
            name: session.callerName,
            platform: session.callerPlatform,
            isOnline: true,
            isTrusted: true,
          ),
        );
        await _wanRtcManager.acceptIncomingSession(session);
        if (mounted && !WanActiveSessionScreen.isScreenOpen) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WanActiveSessionScreen(peer: peer),
            ),
          ).then((_) async {
            final updated = await _historyService.load();
            if (mounted) {
              setState(() {
                _history.clear();
                _history.addAll(updated);
              });
            }
          });
        }
        return;
      }
      _showIncomingSessionDialog(session);
    };
    _initCallService();
    _initShareHandler();

    final walkthroughDone = await HomeWalkthroughGuide.isCompleted();
    if (!walkthroughDone && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted && !_showWalkthrough) {
            _startWalkthrough(force: false);
          }
        });
      });
    }

    _notificationSub = NotificationService().onNotificationClick.listen((peerId) {
      if (peerId != null && mounted) {
        if (peerId.startsWith('wan:')) {
          final cleanId = peerId.substring(4);
          final wanDev = _wanService.trustedDevicesList.where((d) => d.id == cleanId).firstOrNull ??
              _wanService.publicDevices.where((d) => d.id == cleanId).firstOrNull;
          if (wanDev != null && !WanActiveSessionScreen.isScreenOpen) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WanActiveSessionScreen(peer: wanDev),
              ),
            );
          }
          return;
        }

        final peer = widget.service.peers.where(
          (p) => p.id == peerId || p.ip == peerId,
        ).firstOrNull ?? widget.service.getPeer(peerId);

        if (peer != null) {
          _selectPeer(peer);
        } else {
          final wanDev = _wanService.trustedDevicesList.where((d) => d.id == peerId).firstOrNull ??
              _wanService.publicDevices.where((d) => d.id == peerId).firstOrNull;
          if (wanDev != null && !WanActiveSessionScreen.isScreenOpen) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WanActiveSessionScreen(peer: wanDev),
              ),
            );
          }
        }
      }
    });

    _replySub = NotificationService().onNotificationReply.listen((data) async {
      final targetPeerId = data['peerId'];
      final replyText = data['text'];
      if (targetPeerId == null || replyText == null || replyText.trim().isEmpty) return;

      final trimmedReply = replyText.trim();
      final isWan = targetPeerId.startsWith('wan:') ||
          _wanService.isDeviceTrusted(targetPeerId) ||
          _wanService.publicDevices.any((d) => d.id == targetPeerId) ||
          (_wanRtcManager.activePeerId != null && _wanRtcManager.activePeerId == targetPeerId);

      if (isWan) {
        final cleanPeerId = targetPeerId.startsWith('wan:') ? targetPeerId.substring(4) : targetPeerId;
        await _wanRtcManager.sendDirectMessage(trimmedReply, cleanPeerId);
        if (mounted) setState(() {});
        return;
      }

      // Nearby LAN resolution:
      Peer? peer = widget.service.peers.where(
        (p) => p.id == targetPeerId || p.ip == targetPeerId,
      ).firstOrNull;

      peer ??= widget.service.getPeer(targetPeerId);

      if (peer != null) {
        final itemId = '${DateTime.now().millisecondsSinceEpoch}_${peer.id}';
        final ok = await widget.service.sendChat(peer, trimmedReply);
        final status = ok ? 'Sent' : 'Queued';

        if (!ok) {
          await widget.service.queueOutboxItem(QueuedOutboxItem(
            id: itemId,
            peerId: peer.id,
            peerName: peer.name,
            kind: ChatKind.text,
            text: trimmedReply,
            createdAt: DateTime.now(),
          ));
        }

        _history.add(ChatItem(
          id: itemId,
          peerId: peer.id,
          sender: widget.service.deviceName,
          mine: true,
          createdAt: DateTime.now(),
          kind: ChatKind.text,
          text: trimmedReply,
          status: status,
          isAi: false,
        ));
        await _historyService.save(_history);
        if (mounted) setState(() {});
      }
    });

    widget.service.onPeerAutoConnected = (peerId) {
      if (!mounted) return;
      setState(() {});
    };

    widget.service.onReactionReceived = (peerId, msgId, reaction) async {
      for (final item in _history) {
        if (item.id == msgId) {
          item.reaction = (reaction != null && reaction.isNotEmpty) ? reaction : null;
          break;
        }
      }
      await _historyService.save(_history);
      if (mounted) setState(() {});
    };

    _wifiDirectService.onP2pConnected = (peerIp, localIp) async {
      await widget.service.bindP2pPeer(peerIp, localIp);
      if (mounted) {
        setState(() {});
      }
    };

    await _wifiDirectService.init();
    if (mounted) setState(() {});

    widget.service.onStreamOffer = (peerId, offer) async {
      if (!mounted) return;
      final streamType = offer['stream_type']?.toString() ?? 'camera';
      final remoteIp = offer['remote_ip']?.toString() ?? offer['sender_ip']?.toString() ?? '';
      final senderName = offer['sender']?.toString() ?? offer['name']?.toString() ?? 'Remote Device';
      
      Peer peer = widget.service.peers.where(
        (p) => p.id == peerId || (remoteIp.isNotEmpty && p.ip == remoteIp),
      ).firstOrNull ?? Peer(id: peerId, name: senderName, ip: remoteIp.isNotEmpty ? remoteIp : peerId);

      if (remoteIp.isNotEmpty) {
        peer = Peer(
          id: peer.id.isNotEmpty ? peer.id : peerId,
          name: senderName.isNotEmpty && senderName != 'Remote Device' ? senderName : peer.name,
          ip: remoteIp,
        );
      }

      final streamingService = StreamingService();
      final isPermitted = streamType == 'camera'
          ? streamingService.allowCamera
          : (streamType == 'audio'
              ? streamingService.allowAudio
              : streamingService.allowScreen);

      // If already trusted and permitted, start stream directly
      if (isPermitted &&
          (streamingService.isTrusted(peer.id) ||
              streamingService.isTrusted(peer.ip))) {
        _respondToStreamOffer(peer, streamType, offer);
        return;
      }

      // Otherwise, prompt user with explicit Security Authorization Dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(
                streamType == 'camera'
                    ? Icons.videocam_rounded
                    : (streamType == 'audio'
                        ? Icons.mic_rounded
                        : Icons.screen_share_rounded),
                color: const Color(0xFF10B981),
              ),
              const SizedBox(width: 8),
              const Text('Stream Permission Request',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            '${peer.name} (${peer.ip}) wants to access your live ${streamType.toUpperCase()} stream.\n\nDo you want to allow this remote session?',
            style: const TextStyle(fontSize: 13.5),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                widget.service.sendWebRtcSignal(peer, 'stream_rejected', {
                  'reason': 'Host user denied stream access request',
                });
              },
              child: const Text('Deny',
                  style: TextStyle(color: Colors.redAccent)),
            ),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (streamType == 'camera') streamingService.setAllowCamera(true);
                if (streamType == 'audio') streamingService.setAllowAudio(true);
                if (streamType == 'screen') streamingService.setAllowScreen(true);
                _respondToStreamOffer(peer, streamType, offer);
              },
              child: const Text('Allow Once'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (streamType == 'camera') streamingService.setAllowCamera(true);
                if (streamType == 'audio') streamingService.setAllowAudio(true);
                if (streamType == 'screen') streamingService.setAllowScreen(true);
                streamingService.addTrustedDevice(peer.id);
                streamingService.addTrustedDevice(peer.ip);
                _respondToStreamOffer(peer, streamType, offer);
              },
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981)),
              child: const Text('Always Allow'),
            ),
          ],
        ),
      );
    };

    _scan(); // Automatic scan on launch
  }

  Future<void> _respondToStreamOffer(
      Peer peer, String streamType, Map<String, dynamic> offer) async {
    try {
      final sdp = offer['sdp']?.toString();
      if (sdp == null || sdp.isEmpty) return;

      final pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
      });

      final mediaConstraints = <String, dynamic>{
        'audio': streamType == 'audio' || streamType == 'camera',
        'video': streamType == 'camera'
            ? {
                'facingMode': 'environment',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
                'frameRate': {'ideal': 30},
              }
            : false,
      };

      pc.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        widget.service.sendWebRtcSignal(peer, 'stream_ice', {
          'candidate': candidate.candidate,
          'sdp_mid': candidate.sdpMid,
          'sdp_mline_index': candidate.sdpMLineIndex,
        });
      };

      widget.service.onStreamIceCandidate = (pId, data) async {
        final candidateStr = data['candidate']?.toString();
        if (candidateStr != null && candidateStr.isNotEmpty) {
          final candidate = RTCIceCandidate(
            candidateStr,
            data['sdp_mid']?.toString(),
            int.tryParse('${data['sdp_mline_index'] ?? 0}'),
          );
          try {
            await pc.addCandidate(candidate);
          } catch (_) {}
        }
      };

      final localStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      for (final track in localStream.getTracks()) {
        track.enabled = true;
        await pc.addTrack(track, localStream);
      }

      widget.service.onStreamControl = (pId, control) async {
        final action = control['action']?.toString();
        if (action == 'toggle_torch') {
          final val = control['value'] == true;
          final videoTrack = localStream.getVideoTracks().firstOrNull;
          if (videoTrack != null) {
            try {
              if (await videoTrack.hasTorch()) {
                await videoTrack.setTorch(val);
                widget.service.sendWebRtcSignal(peer, 'stream_control', {
                  'action': 'torch_status',
                  'value': val,
                });
              }
            } catch (_) {}
          }
        } else if (action == 'switch_camera') {
          final videoTrack = localStream.getVideoTracks().firstOrNull;
          if (videoTrack != null) {
            try {
              await Helper.switchCamera(videoTrack);
            } catch (_) {}
          }
        } else if (action == 'toggle_mic') {
          final val = control['value'] == true;
          for (final t in localStream.getAudioTracks()) {
            t.enabled = !val;
          }
        }
      };

      await pc.setRemoteDescription(
          RTCSessionDescription(sdp, offer['sdp_type']?.toString() ?? 'offer'));
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      widget.service.sendWebRtcSignal(peer, 'stream_answer', {
        'sdp': answer.sdp,
        'sdp_type': answer.type,
      });

      _toast('Streaming live ${streamType.toUpperCase()} to ${peer.name}');
    } catch (e) {
      debugPrint('Error responding to stream offer: $e');
    }
  }

  void _initShareHandler() {
    const MethodChannel('farmitra_nearby/network')
        .setMethodCallHandler((call) async {
      if (call.method == 'onSharedFilesReceived') {
        final List<dynamic>? files = call.arguments as List<dynamic>?;
        if (files != null && files.isNotEmpty) {
          final paths = files.map((e) => e.toString()).toList();
          _handleExternalSharedFiles(paths);
        }
      }
    });

    const MethodChannel('farmitra_nearby/network')
        .invokeMethod<List<dynamic>>('getInitialSharedFiles')
        .then((initial) {
      if (initial != null && initial.isNotEmpty) {
        final paths = initial.map((e) => e.toString()).toList();
        _handleExternalSharedFiles(paths);
      }
    }).catchError((_) {});
  }

  void _handleExternalSharedFiles(List<String> paths) {
    if (paths.isEmpty || !mounted) return;

    if (_selectedPeer != null) {
      _sendExternalFilesToPeer(_selectedPeer!, paths);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final peers = widget.service.peers;
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.35),
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.share_rounded,
                        color: Color(0xFF10B981)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'NearMitra Direct Share',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${paths.length} file(s) ready to send',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'SELECT NEARBY DEVICE:',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              if (peers.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  alignment: Alignment.center,
                  child: const Text(
                    'No nearby devices discovered yet.\nMake sure the receiver device has NearMitra open.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: peers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final p = peers[idx];
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        tileColor: const Color(0xFF1E293B),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF10B981),
                          child: Text(
                            p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          p.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          p.ip,
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.send_rounded,
                            color: Color(0xFF10B981)),
                        onTap: () {
                          Navigator.pop(ctx);
                          _selectPeer(p);
                          _sendExternalFilesToPeer(p, paths);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendExternalFilesToPeer(Peer peer, List<String> paths) async {
    for (final path in paths) {
      final isDir = await FileSystemEntity.isDirectory(path);
      if (isDir) {
        final folderName = path
                .split(Platform.pathSeparator)
                .where((s) => s.isNotEmpty)
                .lastOrNull ??
            'Folder';
        _history.add(ChatItem(
          peerId: peer.id,
          sender: widget.service.deviceName,
          mine: true,
          createdAt: DateTime.now(),
          kind: ChatKind.folder,
          fileName: folderName,
          filePath: path,
          status: 'Sending…',
        ));
        await _historyService.save(_history);
        if (mounted) setState(() {});
        final ok = await widget.service.sendFolder(peer, path);
        if (!ok) _toast('Failed to send folder $folderName');
      } else {
        final file = File(path);
        if (await file.exists()) {
          final name = path.split(Platform.pathSeparator).last;
          final size = await file.length();
          _history.add(ChatItem(
            peerId: peer.id,
            sender: widget.service.deviceName,
            mine: true,
            createdAt: DateTime.now(),
            kind: ChatKind.file,
            fileName: name,
            filePath: path,
            fileSize: size,
            status: 'Sending…',
          ));
          await _historyService.save(_history);
          if (mounted) setState(() {});
          final ok = await widget.service.sendFile(peer, file);
          if (!ok) _toast('Failed to send $name');
        }
      }
    }
  }

  bool _isCallScreenOpen = false;

  void _initCallService() {
    CallService().registerCallAcceptedCallback((peer, isVideoCall, isIncoming) {
      if (!mounted) return;
      _openActiveCallScreen(peer, isVideoCall, true);
    });

    CallService().registerCallDeclinedCallback((peer) {
      widget.service.sendCallSignal(peer, 'call_declined');
    });

    // Auto-sync outbox status updates in chat history
    widget.service.onOutboxItemStatusChanged = (itemId, newStatus) {
      if (!mounted) return;
      final idx = _history.indexWhere((x) => x.id == itemId);
      if (idx != -1) {
        _history[idx].status = newStatus;
        _historyService.save(_history);
        if (mounted) setState(() {});
      }
    };

    // Handle native Kotlin background / killed-state call accept / decline events
    const MethodChannel('farmitra_nearby/network').setMethodCallHandler((call) async {
      if (call.method == 'onNativeCallEvent' && call.arguments is Map) {
        _handleNativeCallEvent(Map<String, dynamic>.from(call.arguments as Map));
      }
    });

    // Check if app was launched via Accept button from cold start
    Future.microtask(() async {
      try {
        final pending = await const MethodChannel('farmitra_nearby/network')
            .invokeMethod<Map<dynamic, dynamic>>('getPendingCallEvent');
        if (pending != null && mounted) {
          _handleNativeCallEvent(Map<String, dynamic>.from(pending));
        }
      } catch (_) {}
    });
  }

  void _handleNativeCallEvent(Map<String, dynamic> data) {
    final action = data['action']?.toString() ?? 'accept';
    final peerId = data['peerId']?.toString() ?? '';
    final peerName = data['peerName']?.toString() ?? 'Peer Device';
    final peerIp = data['peerIp']?.toString() ?? '';
    final isVideo = data['isVideo'] == true;

    final peer = widget.service.peers.where(
      (p) => p.id == peerId || p.ip == peerId || (peerIp.isNotEmpty && p.ip == peerIp),
    ).firstOrNull ?? Peer(id: peerId.isNotEmpty ? peerId : peerIp, name: peerName, ip: peerIp);

    if (action == 'accept') {
      if (!mounted) return;
      _openActiveCallScreen(peer, isVideo, true);
    } else if (action == 'decline') {
      widget.service.sendCallSignal(peer, 'call_declined');
    }
  }

  void _openActiveCallScreen(Peer peer, bool isVideoCall, bool isIncoming) {
    if (_isCallScreenOpen) return;
    _isCallScreenOpen = true;

    // Resolve peer accurately in case of partial peer data from background CallKit event
    Peer resolvedPeer = peer;
    if (resolvedPeer.ip.isEmpty || resolvedPeer.name == 'Peer Device') {
      final matched = widget.service.peers.where((p) =>
        p.id == peer.id || (peer.id.isNotEmpty && p.ip == peer.id) || (peer.ip.isNotEmpty && p.ip == peer.ip)
      ).firstOrNull;
      if (matched != null) {
        resolvedPeer = matched;
      }
    }

    CallService().setCallActive(true);

    final nav = rootNavigatorKey.currentState ?? Navigator.of(context);
    nav.push<int>(
      MaterialPageRoute(
        builder: (_) => ActiveCallScreen(
          peer: resolvedPeer,
          service: widget.service,
          isVideoCall: isVideoCall,
          isIncoming: isIncoming,
        ),
      ),
    ).then((durationSecs) {
      _isCallScreenOpen = false;
      CallService().setCallActive(false);
      final callTypeStr = isVideoCall ? 'Video Call' : 'Audio Call';
      final durationStr = durationSecs != null && durationSecs > 0
          ? '${(durationSecs ~/ 60).toString().padLeft(2, '0')}:${(durationSecs % 60).toString().padLeft(2, '0')}'
          : 'Ended';
      widget.service.addCallLog(
        peerId: resolvedPeer.id,
        peerName: resolvedPeer.name,
        text: '$callTypeStr • $durationStr',
        mine: !isIncoming,
      );
      if (mounted) setState(() {});
    });
  }

  bool _isWindowsDevice(Peer peer) {
    final n = peer.name.toLowerCase();
    final id = peer.id.toLowerCase();
    return n.contains('win') ||
        n.contains('pc') ||
        n.contains('desktop') ||
        n.contains('laptop') ||
        id.contains('win');
  }

  Future<void> _startCall(Peer peer, bool isVideoCall) async {
    if (_isWindowsDevice(peer)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    'Voice & Video calls are supported between mobile devices only (${peer.name} is a Windows PC).'),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF334155),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Microphone permission is required for calling.')),
        );
      }
      return;
    }

    if (isVideoCall) {
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Camera permission is required for video calling.')),
          );
        }
        return;
      }
    }

    if (!mounted) return;
    widget.service.sendCallInvite(peer, isVideoCall);
    _openActiveCallScreen(peer, isVideoCall, false);
  }

  void _openActivityLogsScreen({int initialTabIndex = 0}) {
    setState(() => _bottomNavIndex = 0);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActivityLogsScreen(
          service: widget.service,
          historyService: _historyService,
          initialTabIndex: initialTabIndex,
          onStartCall: (peer, isVideo) {
            _startCall(peer, isVideo);
          },
          onOpenChatWithPeer: (peer) {
            _selectPeer(peer);
          },
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _bottomNavIndex = 0);
    });
  }

  void _openStreamingHubScreen({String initialType = 'camera'}) {
    setState(() => _bottomNavIndex = 0);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StreamHubScreen(
          service: widget.service,
          targetPeer: _selectedPeer,
          initialStreamType: initialType,
          onOpenSettings: _openSettingsModal,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _bottomNavIndex = 0);
    });
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _peerStatusRefreshTimer?.cancel();
    _notificationSub?.cancel();
    _replySub?.cancel();
    _scroll.removeListener(_onScroll);
    widget.service.removeListener(_onServiceChanged);
    _wanService.removeListener(_onServiceChanged);
    _wanRtcManager.removeListener(_onServiceChanged);
    _firebasePresenceService.removeListener(_onServiceChanged);
    _historyService.removeListener(_onHistoryChanged);
    widget.service.stop();
    _message.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onHistoryChanged() async {
    final updated = await _historyService.load();
    if (mounted) {
      setState(() {
        _history.clear();
        _history.addAll(updated);
      });
    }
  }

  bool _isPeerOnline(Peer peer) {
    if (peer.id == 'local_ai_assistant') return true;
    for (final p in widget.service.peers) {
      if ((p.id == peer.id || p.ip == peer.ip) && p.isOnline) {
        return true;
      }
    }
    return peer.isOnline;
  }

  bool _isUserNearBottom() {
    if (!_scroll.hasClients) return true;
    final max = _scroll.position.maxScrollExtent;
    final current = _scroll.position.pixels;
    return (max - current) <= 150;
  }

  void _onServiceChanged() {
    final incoming = widget.service.takeIncomingItems();
    final bool hasNewChat = incoming.isNotEmpty;
    if (hasNewChat) {
      _history.addAll(incoming);
      _historyService.save(_history);
    }
    if (mounted) {
      final wasNearBottom = _isUserNearBottom();
      setState(() {});
      if (hasNewChat && wasNearBottom) {
        _triggerScrollToBottom();
      }
    }
  }

  void _selectPeer(Peer p) async {
    final updated = await _historyService.load();
    if (mounted) {
      setState(() {
        _history.clear();
        _history.addAll(updated);
        _selectedPeerId = p.id;
        _lastSelectedPeer = p;
        p.unreadCount = 0;
        _chatDisplayCount = 20;
        widget.service.activeChatPeerId = p.id;
      });
      _triggerScrollToBottom();
    }
  }

  void _triggerScrollToBottom({bool immediate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (immediate) {
        _scrollToBottomImmediate();
      } else {
        _scrollToBottom();
      }
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) {
          if (immediate) {
            _scrollToBottomImmediate();
          } else {
            _scrollToBottom();
          }
        }
      });
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) {
          if (immediate) {
            _scrollToBottomImmediate();
          } else {
            _scrollToBottom();
          }
        }
      });
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          if (immediate) {
            _scrollToBottomImmediate();
          } else {
            _scrollToBottom();
          }
        }
      });
    });
  }

  Peer? _lastSelectedPeer;

  Peer? get _selectedPeer {
    if (_selectedPeerId == null) return null;
    for (final p in widget.service.peers) {
      if (p.id == _selectedPeerId || p.ip == _selectedPeerId) {
        _lastSelectedPeer = p;
        return p;
      }
    }
    return _lastSelectedPeer;
  }

  List<ChatItem> get _fullCurrentChat {
    final peer = _selectedPeer;
    if (peer == null) return [];
    final pId = peer.id.toLowerCase();
    final pIp = peer.ip.toLowerCase();
    final pName = peer.name.toLowerCase();

    return _history.where((e) {
      final eId = e.peerId.toLowerCase();
      final eSender = e.sender.toLowerCase();

      final isMatch = eId == pId ||
          eId == pIp ||
          (pIp.isNotEmpty && eId == pIp) ||
          (!e.mine && (
            eSender == pName ||
            (pName.isNotEmpty && eSender.contains(pName)) ||
            (eSender.isNotEmpty && pName.contains(eSender))
          ));
      if (!isMatch) return false;
      if (e.isAi && (e.text == null || e.text!.isEmpty)) return false;
      return _chatMode == ChatMode.ai ? (e.isAi == true) : (e.isAi != true);
    }).toList();
  }

  List<ChatItem> get _currentChat {
    final full = _fullCurrentChat;
    if (full.length <= _chatDisplayCount) return full;
    return full.sublist(full.length - _chatDisplayCount);
  }

  void _confirmClearChat(Peer peer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat History?'),
        content: Text('Are you sure you want to delete all messages with ${peer.name}? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _history.removeWhere((item) => item.peerId == peer.id || item.peerId == peer.ip);
                _historyService.save(_history);
              });
              _toast('Chat history cleared for ${peer.name}');
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Clear Chat'),
          ),
        ],
      ),
    );
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    await widget.service.announce();
    await widget.service.scanSubnet();
    if (mounted) setState(() => _scanning = false);
  }

  Timer? _typingDebounce;
  DateTime? _lastTypingSent;

  void _onTextChanged(String text) {
    final peer = _selectedPeer;
    if (peer == null) return;
    final now = DateTime.now();
    if (text.isNotEmpty) {
      if (_lastTypingSent == null || now.difference(_lastTypingSent!).inMilliseconds > 1800) {
        _lastTypingSent = now;
        widget.service.sendTypingStatus(peer, true);
      }
      _typingDebounce?.cancel();
      _typingDebounce = Timer(const Duration(milliseconds: 3000), () {
        _lastTypingSent = null;
        widget.service.sendTypingStatus(peer, false);
      });
    } else {
      _typingDebounce?.cancel();
      _lastTypingSent = null;
      widget.service.sendTypingStatus(peer, false);
    }
  }

  Future<void> _sendMessage() async {
    final peer = _selectedPeer;
    final text = _message.text.trim();
    if (peer == null || text.isEmpty) return;
    _message.clear();
    _typingDebounce?.cancel();
    widget.service.sendTypingStatus(peer, false);

    if (_chatMode == ChatMode.ai) {
      final userPromptItem = ChatItem(
        peerId: peer.id,
        sender: widget.service.deviceName,
        mine: true,
        createdAt: DateTime.now(),
        kind: ChatKind.text,
        text: text,
        isAi: true,
      );
      _history.add(userPromptItem);

      final aiResponseItem = ChatItem(
        peerId: peer.id,
        sender: peer.name.toLowerCase().endsWith('ai') ? peer.name : '${peer.name} AI',
        mine: false,
        createdAt: DateTime.now(),
        kind: ChatKind.text,
        text: '',
        isAi: true,
      );
      _history.add(aiResponseItem);
      await _historyService.save(_history);

      setState(() {
        _aiThinking = true;
      });
      _triggerScrollToBottom();

      final typeQueue = <String>[];
      var isStreamFinished = false;
      Timer? typewriterTimer;

      void processTypeQueue() {
        if (!mounted) return;
        if (typeQueue.isEmpty) {
          if (isStreamFinished && typewriterTimer != null) {
            typewriterTimer?.cancel();
            typewriterTimer = null;
          }
          return;
        }

        // Adaptive batch size: fast, smooth character typing
        final batchSize = typeQueue.length > 100 ? 8 : (typeQueue.length > 40 ? 4 : 2);
        final toTake = batchSize < typeQueue.length ? batchSize : typeQueue.length;

        final chars = typeQueue.sublist(0, toTake).join();
        typeQueue.removeRange(0, toTake);

        aiResponseItem.text = (aiResponseItem.text ?? '') + chars;

        if (_aiThinking) {
          _aiThinking = false;
        }

        setState(() {});
        if (_isUserNearBottom()) {
          _scrollToBottomImmediate();
        }
      }

      typewriterTimer = Timer.periodic(const Duration(milliseconds: 14), (_) {
        processTypeQueue();
      });

      if (peer.id == 'local_ai_assistant') {
        final res = await AiSettingsService().queryAi(text);
        typeQueue.addAll(res.split(''));
      } else {
        await for (final chunk in widget.service.streamAiPrompt(peer, text)) {
          if (chunk.isNotEmpty) {
            typeQueue.addAll(chunk.split(''));
          }
        }
      }

      isStreamFinished = true;

      // Drain remaining typing queue smoothly
      while (typeQueue.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 15));
      }

      typewriterTimer?.cancel();
      typewriterTimer = null;

      if (aiResponseItem.text == null || aiResponseItem.text!.isEmpty) {
        final hasIncomingAi = _history.any((e) =>
            e != aiResponseItem &&
            (e.peerId == peer.id || e.peerId == peer.ip) &&
            e.isAi &&
            !e.mine &&
            e.text != null &&
            e.text!.isNotEmpty);
        if (hasIncomingAi) {
          _history.remove(aiResponseItem);
        } else {
          aiResponseItem.text = 'Nearby AI is not enabled on this device.';
        }
      }

      await _historyService.save(_history);

      if (mounted) {
        setState(() {
          _aiThinking = false;
        });
        _triggerScrollToBottom();
      }
      return;
    }

    final replyingTo = _replyingToItem;
    if (mounted) {
      setState(() {
        _replyingToItem = null;
      });
    }

    final itemId = '${DateTime.now().millisecondsSinceEpoch}_${peer.id}';

    // 1. Immediately create and show queued item in chat UI
    final chatItem = ChatItem(
      id: itemId,
      peerId: peer.id,
      sender: widget.service.deviceName,
      mine: true,
      createdAt: DateTime.now(),
      kind: ChatKind.text,
      text: text,
      status: 'Queued',
      isAi: false,
      replyToId: replyingTo?.id,
      replyToSender: replyingTo?.sender,
      replyToText: replyingTo?.text ?? replyingTo?.fileName,
    );
    _history.add(chatItem);
    await _historyService.save(_history);
    if (mounted) setState(() {});
    _triggerScrollToBottom();

    // 2. Attempt sending over network
    final ok = await widget.service.sendChat(
      peer,
      text,
      msgId: itemId,
      replyToId: replyingTo?.id,
      replyToSender: replyingTo?.sender,
      replyToText: replyingTo?.text ?? replyingTo?.fileName,
    );

    if (ok) {
      chatItem.status = 'Sent';
      await _historyService.save(_history);
      if (mounted) setState(() {});
    } else {
      chatItem.status = 'Queued';
      await widget.service.queueOutboxItem(QueuedOutboxItem(
        id: itemId,
        peerId: peer.id,
        peerName: peer.name,
        kind: ChatKind.text,
        text: text,
        createdAt: DateTime.now(),
      ));
      await _historyService.save(_history);
      _toast('Peer is offline • Message queued (auto-sends when online)');
      if (mounted) setState(() {});
    }
  }

  Future<void> _cancelQueuedMessage(ChatItem item) async {
    await widget.service.cancelQueuedItem(item.id);
    item.status = 'Cancelled';
    await _historyService.save(_history);
    if (mounted) {
      setState(() {});
      _toast('Queued message cancelled');
    }
  }

  Future<void> _toggleReactionOnMessage(ChatItem item, String emoji, Peer peer) async {
    setState(() {
      item.reaction = emoji.isEmpty ? null : emoji;
    });
    await _historyService.save(_history);

    if (peer.id != 'local_ai_assistant' && peer.ip.isNotEmpty) {
      widget.service.sendReaction(peer, item.id, item.reaction);
    }
  }

  Future<void> _pickAndSend({FileType fileType = FileType.any}) async {
    final peer = _selectedPeer;
    if (peer == null) {
      _toast('Select a nearby device first');
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: fileType,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final filesToSend = result.files.where((f) => f.path != null).toList();
    if (filesToSend.isEmpty) return;

    if (filesToSend.length > 1) {
      _toast('Sending ${filesToSend.length} files to ${peer.name}…');
    }

    for (int i = 0; i < filesToSend.length; i++) {
      final f = filesToSend[i];
      final path = f.path!;
      final file = File(path);
      if (!await file.exists()) continue;

      final name = f.name;
      final size = await file.length();
      final itemId = '${DateTime.now().millisecondsSinceEpoch}_${i}_${peer.id}';

      final fileItem = ChatItem(
        id: itemId,
        peerId: peer.id,
        sender: widget.service.deviceName,
        mine: true,
        createdAt: DateTime.now(),
        kind: ChatKind.file,
        fileName: name,
        filePath: path,
        fileSize: size,
        status: 'Queued',
      );
      _history.add(fileItem);
      await _historyService.save(_history);
      if (mounted) setState(() {});
      _triggerScrollToBottom();

      final ok = await widget.service.sendFile(peer, file, displayName: name);
      if (ok) {
        fileItem.status = 'Sent';
        await _historyService.save(_history);
        if (mounted) setState(() {});
      } else {
        fileItem.status = 'Queued';
        await widget.service.queueOutboxItem(QueuedOutboxItem(
          id: itemId,
          peerId: peer.id,
          peerName: peer.name,
          kind: ChatKind.file,
          fileName: name,
          filePath: path,
          fileSize: size,
          createdAt: DateTime.now(),
        ));
        await _historyService.save(_history);
        if (mounted) setState(() {});
      }
    }

    if (!widget.service.peers.any((p) => p.id == peer.id && p.ip.isNotEmpty)) {
      _toast('Peer is offline • ${filesToSend.length > 1 ? "${filesToSend.length} files" : "File"} queued in Outbox');
    }
  }

  Future<void> _pickAndSendFolder() async {
    final peer = _selectedPeer;
    if (peer == null) {
      _toast('Select a nearby device first');
      return;
    }
    final folderPath = await FilePicker.platform.getDirectoryPath();
    if (folderPath == null || folderPath.isEmpty) return;

    final dir = Directory(folderPath);
    if (!await dir.exists()) return;

    final folderName =
        dir.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'Folder';
    _toast('Compressing and sending folder: $folderName…');

    final ok = await widget.service.sendFolder(peer, folderPath);
    if (!ok) {
      _toast('Failed to send folder');
      return;
    }

    _history.add(ChatItem(
      peerId: peer.id,
      sender: widget.service.deviceName,
      mine: true,
      createdAt: DateTime.now(),
      kind: ChatKind.folder,
      fileName: folderName,
      filePath: folderPath,
      status: 'Sent',
    ));
    await _historyService.save(_history);
    setState(() {});
    _triggerScrollToBottom();
  }

  void _showAttachmentOptions() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2C34) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -2)),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top drag bar and close button
              Row(
                children: [
                  const SizedBox(width: 30),
                  const Spacer(),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: _attachmentOption(
                      icon: Icons.insert_drive_file_rounded,
                      color: const Color(0xFF10B981),
                      label: 'Files (Multi)',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSend(fileType: FileType.any);
                      },
                    ),
                  ),
                  Expanded(
                    child: _attachmentOption(
                      icon: Icons.photo_library_rounded,
                      color: const Color(0xFF6366F1),
                      label: 'Photos/Media',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSend(fileType: FileType.media);
                      },
                    ),
                  ),
                  Expanded(
                    child: _attachmentOption(
                      icon: Icons.folder_rounded,
                      color: const Color(0xFFF59E0B),
                      label: 'Send Folder',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendFolder();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachmentOption({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border:
                    Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    _scroll.animateTo(
      max,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToBottomImmediate() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    _scroll.jumpTo(max);
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  Future<void> _openFolderLocation(String folderPath) async {
    Clipboard.setData(ClipboardData(text: folderPath));
    _toast('Opening location: $folderPath');
    final opened = await _wifiDirectService.openFolder(folderPath);
    if (!opened) {
      await OpenFilex.open(folderPath);
    }
  }


  void _startWalkthrough({bool force = false}) async {
    if (!force) {
      final completed = await HomeWalkthroughGuide.isCompleted();
      if (completed) return;
    }
    if (mounted) {
      setState(() {
        _showWalkthrough = true;
        _bottomNavIndex = 0;
        _selectedPeerId = null;
        _connectionMode = ConnectionMode.lan;
      });
    }
  }

  bool _handleBackPress() {
    // 0. If walkthrough is open, dismiss it
    if (_showWalkthrough) {
      setState(() {
        _showWalkthrough = false;
      });
      HomeWalkthroughGuide.markCompleted();
      return false;
    }

    // 1. If a peer chat is selected on compact layout, close the chat first
    if (_selectedPeerId != null) {
      setState(() {
        _selectedPeerId = null;
        widget.service.activeChatPeerId = null;
      });
      return false;
    }

    // 2. If on another bottom nav tab, switch to main Chats tab first
    if (_bottomNavIndex != 0) {
      setState(() {
        _bottomNavIndex = 0;
      });
      return false;
    }

    // 3. Double press back check within 2 seconds
    final now = DateTime.now();
    if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.exit_to_app_rounded, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text(
                'Press back again to exit',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1F2C34),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
      return false;
    }

    // Allow exit
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 760;
    final peer = _selectedPeer;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (ModalRoute.of(context)?.isCurrent != true) return;
        final shouldExit = _handleBackPress();
        if (shouldExit) {
          SystemNavigator.pop();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: isDark ? const Color(0xFF111B21) : Colors.white,
          systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        ),
        child: Stack(
          children: [
            Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
      floatingActionButton: (_selectedPeer == null)
          ? _AnimatedAiFab(
              onPressed: () {
                final aiConfig = AiSettingsService().config;
                final isKeyConfigured = (aiConfig.provider == 'gemini' &&
                        aiConfig.geminiApiKey.trim().isNotEmpty) ||
                    (aiConfig.provider == 'openai' &&
                        aiConfig.openaiApiKey.trim().isNotEmpty);

                if (!isKeyConfigured) {
                  _toast('Please configure your AI API key first');
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const AiSettingsScreen()),
                  );
                  return;
                }

                final aiPeer = Peer(
                  id: 'local_ai_assistant',
                  name: 'My AI',
                  ip: '127.0.0.1',
                  isAiHost: true,
                );
                _selectPeer(aiPeer);
                setState(() {
                  _chatMode = ChatMode.ai;
                });
              },
            )
          : null,
      bottomNavigationBar: (compact && peer == null)
          ? Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: NavigationBar(
                selectedIndex: _bottomNavIndex,
                height: 64,
                labelBehavior:
                    NavigationDestinationLabelBehavior.alwaysShow,
                indicatorColor:
                    const Color(0xFF10B981).withValues(alpha: 0.18),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.devices_rounded),
                    selectedIcon:
                        Icon(Icons.devices_rounded, color: Color(0xFF10B981)),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.sensors_rounded),
                    selectedIcon:
                        Icon(Icons.sensors_rounded, color: Color(0xFF10B981)),
                    label: 'Streaming',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.sync_alt_rounded),
                    selectedIcon:
                        Icon(Icons.sync_alt_rounded, color: Color(0xFF10B981)),
                    label: 'Recent',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_rounded),
                    selectedIcon:
                        Icon(Icons.settings_rounded, color: Color(0xFF10B981)),
                    label: 'Settings',
                  ),
                ],
                onDestinationSelected: (index) {
                  if (index == 0) {
                    setState(() => _bottomNavIndex = 0);
                  } else if (index == 1) {
                    _openStreamingHubScreen();
                  } else if (index == 2) {
                    _openActivityLogsScreen(initialTabIndex: 0);
                  } else if (index == 3) {
                    _openSettingsModal();
                  }
                },
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            if (!compact || peer == null) _topBar(),
            Expanded(
              child: compact
                  ? _mobileBody()
                  : Row(
                      children: [
                        SizedBox(width: 320, child: _devicePane()),
                        VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .45)),
                        Expanded(child: _chatPane()),
                      ],
                    ),
            ),
          ],
        ),
      ),
    ),
    if (_showWalkthrough)
      HomeWalkthroughGuide(
        steps: [
          WalkthroughStepItem(
            key: _nearbyTabKey,
            title: 'Nearby',
            description: 'Find NearMitra devices on the same Wi-Fi or local network. Tap a discovered device to connect.',
            howToUse: 'Open Nearby and NearMitra will scan for nearby Android and Windows devices. When a device appears, tap it to connect.',
            icon: Icons.wifi_rounded,
            onEnter: () {
              if (_connectionMode != ConnectionMode.lan) {
                setState(() {
                  _connectionMode = ConnectionMode.lan;
                });
                _firebasePresenceService.setInternetMode(false);
                _wanService.setInternetMode(false);
              }
            },
          ),
          WalkthroughStepItem(
            key: _p2pTabKey,
            title: 'P2P',
            description: 'Connect directly to another device for private device-to-device communication and file sharing.',
            howToUse: 'Select a compatible device and establish a direct P2P connection for supported features such as chat and file sharing.',
            icon: Icons.radar_rounded,
            onEnter: () {
              if (_connectionMode != ConnectionMode.p2p) {
                setState(() {
                  _connectionMode = ConnectionMode.p2p;
                });
                _wanService.setInternetMode(false);
              }
            },
          ),
          WalkthroughStepItem(
            key: _wanTabKey,
            title: 'WAN',
            description: 'Connect to your paired NearMitra devices across different networks, including mobile data and remote Wi-Fi.',
            howToUse: 'Enable Internet Mode, pair a remote device once, and connect whenever both devices are online.',
            icon: Icons.public_rounded,
            onEnter: () {
              if (_connectionMode != ConnectionMode.wan) {
                setState(() {
                  _connectionMode = ConnectionMode.wan;
                });
                _wanService.setInternetMode(true);
              }
            },
          ),
        ],
        onFinish: () {
          if (mounted) {
            setState(() {
              _showWalkthrough = false;
            });
          }
        },
        onSkip: () {
          if (mounted) {
            setState(() {
              _showWalkthrough = false;
            });
          }
        },
      ),
    ],
  ),
  ),
  );
}

  Widget _topBar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Row(
        children: [
          // Title and Status Stack on Left: NearMitra + Online
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.connect_without_contact_rounded,
                    size: 22,
                    color: Color(0xFF10B981),
                  ),
                  const SizedBox(width: 6),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Near',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                            letterSpacing: -0.6,
                            height: 1.1,
                          ),
                        ),
                        const TextSpan(
                          text: 'Mitra',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF10B981),
                            letterSpacing: -0.6,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6.5,
                    height: 6.5,
                    decoration: const BoxDecoration(
                      color: Color(0xFF22C55E),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4.5),
                  const Text(
                    'Online • Local Network',
                    style: TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          // 1. Simple Clean My AI Assistant Button
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
            iconSize: 20,
            tooltip: 'My AI Assistant',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
            ),
            color: const Color(0xFF10B981),
            onPressed: _openMyAiAssistant,
            icon: const Icon(Icons.auto_awesome_rounded),
          ),
          const SizedBox(width: 8),

          // 2. Window / AI Fleet Dashboard Button
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
            iconSize: 20,
            tooltip: 'AI Fleet & Device Hub',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
            ),
            color: const Color(0xFF6366F1),
            onPressed: _openAiFleetDashboardScreen,
            icon: const Icon(Icons.window_rounded),
          ),
          const SizedBox(width: 6),

          // 3. Scan Network Refresh Button
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
            iconSize: 19,
            tooltip: 'Scan network',
            style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh),
            onPressed: _scan,
            icon: AnimatedRotation(
              turns: _scanning ? 1 : 0,
              duration: const Duration(milliseconds: 700),
              child: const Icon(Icons.refresh_rounded),
            ),
          ),
        ],
      ),
    );
  }

  void _openMyAiAssistant() {
    final aiConfig = ref.read(aiConfigProvider);
    final isKeyConfigured = (aiConfig.provider == 'gemini' &&
            aiConfig.geminiApiKey.trim().isNotEmpty) ||
        (aiConfig.provider == 'openai' &&
            aiConfig.openaiApiKey.trim().isNotEmpty);

    if (!isKeyConfigured) {
      _toast('Please configure your AI API key first');
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
      );
      return;
    }

    final aiPeer = Peer(
      id: 'local_ai_assistant',
      name: 'My AI',
      ip: '127.0.0.1',
      isAiHost: true,
    );
    _selectPeer(aiPeer);
    setState(() {
      _chatMode = ChatMode.ai;
    });
  }

  void _openAiFleetDashboardScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiFleetScreen(
          service: widget.service,
          onOpenChatWithPeer: (peer) {
            _selectPeer(peer);
          },
          onStartCall: (peer, isVideo) {
            _startCall(peer, isVideo);
          },
        ),
      ),
    );
  }

  Future<void> _openSettingsModal() async {
    setState(() => _bottomNavIndex = 0);
    final currentDir = await widget.service.getReceiveDirectory();
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;

            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(22, 20, 22, MediaQuery.of(context).viewInsets.bottom + 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[400],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF169B62).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.settings_rounded, color: Color(0xFF169B62)),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Settings',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Close Settings',
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const Divider(height: 28),
                      
                      // 0. Device Profile & Identity Card (Custom Name & Avatar Emoji)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () async {
                            final res = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DeviceProfileScreen(service: widget.service),
                              ),
                            );
                            if (res == true || mounted) {
                              setModalState(() {});
                              setState(() {});
                            }
                          },
                          child: Ink(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isDark
                                    ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                                    : [const Color(0xFFE8F5E9), const Color(0xFFFFFFFF)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.35 : 0.5),
                                width: 1.4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.1 : 0.08),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 54,
                                      height: 54,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isDark ? const Color(0xFF0F172A) : Colors.white,
                                        border: Border.all(
                                          color: const Color(0xFF10B981),
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        widget.service.avatarEmoji.isNotEmpty ? widget.service.avatarEmoji : '📱',
                                        style: const TextStyle(fontSize: 27),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: Container(
                                        width: 13,
                                        height: 13,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isDark ? const Color(0xFF0F172A) : Colors.white,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.service.deviceName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          letterSpacing: 0.2,
                                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Broadcasting identity on LAN, P2P & WAN',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark ? Colors.white60 : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.edit_rounded, size: 14, color: Color(0xFF10B981)),
                                      SizedBox(width: 4),
                                      Text(
                                        'Edit',
                                        style: TextStyle(
                                          color: Color(0xFF10B981),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 1. App Theme Mode Switcher
                      const Text('App Theme', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _themeOptionCard(
                              context,
                              title: 'System',
                              icon: Icons.brightness_auto_rounded,
                              mode: ThemeMode.system,
                              current: themeNotifier.value,
                              onTap: () async {
                                themeNotifier.value = ThemeMode.system;
                                try {
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.setString('app_theme_mode', 'system');
                                } catch (_) {}
                                setModalState(() {});
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _themeOptionCard(
                              context,
                              title: 'Light',
                              icon: Icons.light_mode_rounded,
                              mode: ThemeMode.light,
                              current: themeNotifier.value,
                              onTap: () async {
                                themeNotifier.value = ThemeMode.light;
                                try {
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.setString('app_theme_mode', 'light');
                                } catch (_) {}
                                setModalState(() {});
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _themeOptionCard(
                              context,
                              title: 'Dark',
                              icon: Icons.dark_mode_rounded,
                              mode: ThemeMode.dark,
                              current: themeNotifier.value,
                              onTap: () async {
                                themeNotifier.value = ThemeMode.dark;
                                try {
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.setString('app_theme_mode', 'dark');
                                } catch (_) {}
                                setModalState(() {});
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // 2. Local Notifications Toggle
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: const Color(0xFF169B62),
                        title: const Text('Local Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                        subtitle: const Text('Show alerts when chat messages or files arrive', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        value: widget.service.notificationsEnabled,
                        onChanged: (val) async {
                          await widget.service.setNotificationsEnabled(val);
                          setModalState(() {});
                          setState(() {});
                          _toast(val
                              ? 'Local Notifications Enabled 🔔'
                              : 'Local Notifications Disabled 🔕');
                        },
                      ),
                      const SizedBox(height: 8),

                      // 2b. Background Service Toggle (Default: ON)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: const Color(0xFF169B62),
                        title: const Text('Run in Background', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                        subtitle: const Text(
                          'Keep app active in background to receive P2P files & messages when app is closed',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        value: widget.service.backgroundServiceEnabled,
                        onChanged: (val) async {
                          await widget.service.setBackgroundServiceEnabled(val);
                          setModalState(() {});
                          setState(() {});
                          _toast(val
                              ? 'Background Service ON: Active to receive files & messages'
                              : 'Background Service OFF: Stopped background listener');
                        },
                      ),
                      const SizedBox(height: 8),

                      // 2c. Offline Mesh Relay Toggle (Multi-Hop Messaging)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: const Color(0xFF169B62),
                        title: Row(
                          children: [
                            const Text('Offline Mesh Relay',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14.5)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'MULTI-HOP',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: const Text(
                          'Securely forward off-grid messages between distant peers through intermediate devices in large spaces & off-grid zones',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        value: widget.service.meshRelayEnabled,
                        onChanged: (val) async {
                          await widget.service.setMeshRelayEnabled(val);
                          setModalState(() {});
                          setState(() {});
                          _toast(val
                              ? 'Offline Mesh Relay Enabled 🌐'
                              : 'Offline Mesh Relay Disabled');
                        },
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // 2d. Remote Streaming Security & Access Permissions
                      Row(
                        children: [
                          const Icon(Icons.videocam_rounded, color: Color(0xFF10B981), size: 20),
                          const SizedBox(width: 8),
                          const Text('Remote Streaming Permissions',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'CCTV / RELAY',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Control which live streaming feeds nearby peers can request from this device',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),

                      // 1. Camera Access
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: const Color(0xFF10B981),
                        title: const Text('Allow Incoming Camera Access',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        subtitle: const Text(
                            'Allows trusted nearby peers to request live CCTV stream',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                        value: StreamingService().allowCamera,
                        onChanged: (val) async {
                          await StreamingService().setAllowCamera(val);
                          setModalState(() {});
                          setState(() {});
                          _toast(val ? 'Camera Access Allowed 📹' : 'Camera Access Disabled 🚫');
                        },
                      ),

                      // 2. Audio Access
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: const Color(0xFF10B981),
                        title: const Text('Allow Incoming Audio Access',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        subtitle: const Text('Allows peers to stream microphone audio relay',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                        value: StreamingService().allowAudio,
                        onChanged: (val) async {
                          await StreamingService().setAllowAudio(val);
                          setModalState(() {});
                          setState(() {});
                          _toast(val ? 'Audio Access Allowed 🎙️' : 'Audio Access Disabled 🚫');
                        },
                      ),

                      // 3. Screen Casting Access
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: const Color(0xFF10B981),
                        title: const Text('Allow Screen Casting Stream',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        subtitle: const Text('Allows remote viewing of phone screen',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                        value: StreamingService().allowScreen,
                        onChanged: (val) async {
                          await StreamingService().setAllowScreen(val);
                          setModalState(() {});
                          setState(() {});
                          _toast(val ? 'Screen Stream Allowed 📱' : 'Screen Stream Disabled 🚫');
                        },
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // 2e. WAN Discovery & Privacy Mode
                      Row(
                        children: [
                          const Icon(Icons.public_rounded, color: Color(0xFF10B981), size: 20),
                          const SizedBox(width: 8),
                          const Text('WAN Discovery & Privacy Mode',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'INTERNET RADAR',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Control how your device appears to other users on the global WAN radar',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      _buildWanPrivacySettingTile(
                        context,
                        title: 'Public Radar Mode',
                        subtitle: 'Visible on Radar for instant 1-tap connection requests from nearby online users',
                        icon: Icons.public_rounded,
                        color: const Color(0xFF10B981),
                        isSelected: _wanService.discoveryMode == WanDiscoveryMode.publicRadar,
                        onTap: () async {
                          await _wanService.setDiscoveryMode(WanDiscoveryMode.publicRadar);
                          setModalState(() {});
                          setState(() {});
                          _toast('Public Radar Mode Active 🌐');
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildWanPrivacySettingTile(
                        context,
                        title: 'Ghost / Private Mode',
                        subtitle: 'Invisible on public radar. Only previously paired trusted contacts can connect',
                        icon: Icons.visibility_off_rounded,
                        color: const Color(0xFF6366F1),
                        isSelected: _wanService.discoveryMode == WanDiscoveryMode.privateGhost,
                        onTap: () async {
                          await _wanService.setDiscoveryMode(WanDiscoveryMode.privateGhost);
                          setModalState(() {});
                          setState(() {});
                          _toast('Ghost / Private Mode Active 👻');
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildWanPrivacySettingTile(
                        context,
                        title: 'PIN Code Only',
                        subtitle: 'Hidden from radar. New devices must enter your 6-digit pair PIN code to connect',
                        icon: Icons.pin_rounded,
                        color: const Color(0xFFF59E0B),
                        isSelected: _wanService.discoveryMode == WanDiscoveryMode.pinOnly,
                        onTap: () async {
                          await _wanService.setDiscoveryMode(WanDiscoveryMode.pinOnly);
                          setModalState(() {});
                          setState(() {});
                          _toast('PIN Code Only Mode Active 🔢');
                        },
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // 3. Received File Save Location
                      const Text('Received File Storage Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black26 : Colors.grey[100],
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.folder_open_rounded, color: Color(0xFF169B62), size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.service.customSavePath ?? currentDir.path,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () async {
                                    final path = widget.service.customSavePath ?? currentDir.path;
                                    await _openFolderLocation(path);
                                  },

                                  icon: const Icon(Icons.folder_open_rounded, size: 16, color: Color(0xFF169B62)),
                                  label: const Text('Open Location', style: TextStyle(color: Color(0xFF169B62), fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                                const SizedBox(width: 2),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () async {
                                    if (Platform.isAndroid) {
                                      if (!await Permission.manageExternalStorage.isGranted) {
                                        await Permission.manageExternalStorage.request();
                                      }
                                    }
                                    final selected = await FilePicker.platform.getDirectoryPath();
                                    if (selected != null && selected.trim().isNotEmpty) {
                                      try {
                                        final dir = Directory(selected.trim());
                                        if (!await dir.exists()) await dir.create(recursive: true);

                                        setModalState(() {
                                          widget.service.customSavePath = selected.trim();
                                        });
                                        setState(() {});
                                        _toast('Storage location updated: $selected');
                                      } catch (e) {
                                        _toast('Selected folder permission error. Please pick an accessible folder.');
                                      }
                                    }
                                  },
                                  child: const Text('Change', style: TextStyle(color: Color(0xFF169B62), fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ],
                            ),

                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 4),

                      // 4. Nearby AI Settings Button
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF10B981), size: 22),
                        ),
                        title: const Text('Nearby AI Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                        subtitle: const Text('Google Gemini, ChatGPT & Custom Prompts', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        trailing: const Icon(Icons.chevron_right_rounded, size: 22),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
                          );
                        },
                      ),
                      const SizedBox(height: 6),

                      // 4b. Show Feature Guide (Walkthrough)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.explore_rounded, color: Color(0xFF6366F1), size: 22),
                        ),
                        title: const Text('Show Feature Guide', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                        subtitle: const Text('Interactive tour of Nearby, P2P & WAN modes', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        trailing: const Icon(Icons.chevron_right_rounded, size: 22),
                        onTap: () {
                          Navigator.pop(context);
                          _startWalkthrough(force: true);
                        },
                      ),
                      const SizedBox(height: 6),

                      // 5. About App Button
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.info_outline_rounded, color: Color(0xFF10B981), size: 22),
                        ),
                        title: const Text('About NearMitra', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                        subtitle: const Text('App overview, offline P2P info & branding', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        trailing: const Icon(Icons.chevron_right_rounded, size: 22),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AboutScreen()),
                          );
                        },
                      ),
                      const SizedBox(height: 14),

                      // Footer Branding & Support
                      Divider(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.mail_outline_rounded,
                            size: 13,
                            color: Color(0xFF10B981),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'For support or suggestions: theflutterfever@gmail.com',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Built with ',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey,
                            ),
                          ),
                          const Icon(
                            Icons.favorite_rounded,
                            size: 14,
                            color: Color(0xFFEF4444),
                          ),
                          const Text(
                            ' Flutter and Kotlin',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: Text(
                          '© 2026 NearMitra Ecosystem • All Rights Reserved',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark ? Colors.white38 : Colors.black38,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (mounted) setState(() => _bottomNavIndex = 0);
  }

  Widget _themeOptionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required ThemeMode mode,
    required ThemeMode current,
    required VoidCallback onTap,
  }) {
    final selected = current == mode;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF169B62).withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF169B62) : Colors.grey.withValues(alpha: 0.3),
            width: selected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: selected ? const Color(0xFF169B62) : Colors.grey),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? const Color(0xFF169B62) : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWanPrivacySettingTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isSelected
          ? color.withValues(alpha: isDark ? 0.18 : 0.10)
          : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? color : (isDark ? Colors.white10 : Colors.black12),
              width: isSelected ? 1.6 : 1.0,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.2),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: isSelected ? color : (isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                        const Spacer(),
                        if (isSelected)
                          Icon(Icons.check_circle_rounded, color: color, size: 18),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white60 : Colors.black54,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openReceivedFilesModal() async {
    final dir = await widget.service.getReceiveDirectory();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final receivedFiles = _history
            .where((e) => e.kind != ChatKind.text && !e.mine)
            .toList()
            .reversed
            .toList();

        return Container(
          height: MediaQuery.sizeOf(context).height * 0.75,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1F2C34) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF169B62).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.folder_shared_rounded, color: Color(0xFF169B62), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Received Files Location',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                        ),
                        Text(
                          dir.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF169B62),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () async {
                      await _openFolderLocation(dir.path);
                    },

                    icon: const Icon(Icons.folder_open_rounded, size: 16),
                    label: const Text('Open Folder', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const Divider(height: 28),
              Row(
                children: [
                  const Text('File History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const Spacer(),
                  Text('${receivedFiles.length} files', style: const TextStyle(color: Colors.grey, fontSize: 12.5)),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: receivedFiles.isEmpty
                    ? const Center(
                        child: Text(
                          'No received files yet',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        itemCount: receivedFiles.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                        itemBuilder: (context, index) {
                          final item = receivedFiles[index];
                          final hasPath = item.filePath != null;
                          final parentDir = hasPath ? File(item.filePath!).parent.path : null;
                          final isApk = FileOpenerService.isApkFile(item.fileName ?? item.filePath);

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  onTap: !hasPath
                                      ? null
                                      : () => FileOpenerService.openOrInstallFile(context, item.filePath!),
                                  leading: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: isApk
                                          ? const Color(0xFF10B981).withValues(alpha: 0.18)
                                          : const Color(0xFF169B62).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      isApk
                                          ? Icons.android_rounded
                                          : (item.kind == ChatKind.folder
                                              ? Icons.folder_rounded
                                              : Icons.insert_drive_file_rounded),
                                      color: isApk ? const Color(0xFF10B981) : const Color(0xFF169B62),
                                    ),
                                  ),
                                  title: Text(
                                    item.fileName ?? 'File',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    'From ${item.sender} • ${item.formattedTime}${item.formattedSize.isNotEmpty ? " • ${item.formattedSize}" : ""}',
                                    style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                                  ),
                                  trailing: isApk
                                      ? FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xFF10B981),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            visualDensity: VisualDensity.compact,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                          ),
                                          onPressed: !hasPath
                                              ? null
                                              : () => FileOpenerService.openOrInstallFile(context, item.filePath!),
                                          icon: const Icon(Icons.install_mobile_rounded, size: 15),
                                          label: const Text(
                                            'Install',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                        )
                                      : IconButton(
                                          icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF169B62)),
                                          onPressed: !hasPath
                                              ? null
                                              : () => FileOpenerService.openOrInstallFile(context, item.filePath!),
                                          tooltip: 'Open File',
                                        ),
                                ),
                                if (hasPath && parentDir != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 56, bottom: 2),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(6),
                                      onTap: () async {
                                        await _openFolderLocation(parentDir);
                                      },

                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.folder_open_rounded, size: 14, color: Color(0xFF169B62)),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Open File Location',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF169B62),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _mobileBody() {
    if (_selectedPeer == null) return _devicePane();
    return Column(
      children: [
        _whatsappPeerHeader(_selectedPeer!),
        Expanded(child: _chatPane(isMobile: true)),
      ],
    );
  }

  String? _resolvePeerAvatar(Peer peer) {
    if (peer.avatarEmoji != null && peer.avatarEmoji!.trim().isNotEmpty) {
      return peer.avatarEmoji!.trim();
    }
    final trimmed = peer.name.trim();
    if (trimmed.isNotEmpty) {
      final firstRune = trimmed.runes.first;
      if ((firstRune >= 0x1F300 && firstRune <= 0x1F9FF) ||
          (firstRune >= 0x2600 && firstRune <= 0x27BF) ||
          (firstRune >= 0x1FA70 && firstRune <= 0x1FAFF) ||
          (firstRune >= 0xFE00 && firstRune <= 0xFE0F) ||
          (firstRune >= 0x1F000 && firstRune <= 0x1F2FF)) {
        return String.fromCharCode(firstRune);
      }
    }
    try {
      final peerNameClean = peer.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      for (final wd in _wanService.trustedDevicesList) {
        if (wd.avatarEmoji != null && wd.avatarEmoji!.trim().isNotEmpty) {
          final wdNameClean = wd.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (wd.id == peer.id ||
              wd.name.toLowerCase() == peer.name.toLowerCase() ||
              (peerNameClean.isNotEmpty && wdNameClean.isNotEmpty &&
                  (wdNameClean.contains(peerNameClean) || peerNameClean.contains(wdNameClean)))) {
            return wd.avatarEmoji!.trim();
          }
        }
      }
      for (final pd in _wanService.publicDevices) {
        if (pd.avatarEmoji != null && pd.avatarEmoji!.trim().isNotEmpty) {
          final pdNameClean = pd.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (pd.id == peer.id ||
              pd.name.toLowerCase() == peer.name.toLowerCase() ||
              (peerNameClean.isNotEmpty && pdNameClean.isNotEmpty &&
                  (pdNameClean.contains(peerNameClean) || peerNameClean.contains(pdNameClean)))) {
            return pd.avatarEmoji!.trim();
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Widget _whatsappPeerHeader(Peer peer) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2C34) : const Color(0xFF075E54),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => setState(() {
              _selectedPeerId = null;
              _lastSelectedPeer = null;
              widget.service.activeChatPeerId = null;
            }),
          ),
          Builder(
            builder: (context) {
              final isOnline = _isPeerOnline(peer);
              final avatar = _resolvePeerAvatar(peer);
              return Stack(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: isOnline ? Colors.white24 : Colors.white12,
                    child: (avatar != null && avatar.isNotEmpty)
                        ? Center(
                            child: Text(
                              avatar,
                              style: const TextStyle(fontSize: 20),
                            ),
                          )
                        : (peer.id == 'local_ai_assistant'
                            ? const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20)
                            : Icon(
                                _isWindowsDevice(peer)
                                    ? Icons.laptop_windows_rounded
                                    : Icons.smartphone_rounded,
                                color: Colors.white,
                                size: 20,
                              )),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: isOnline ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Builder(
              builder: (context) {
                final isOnline = _isPeerOnline(peer);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            peer.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _isWindowsDevice(peer) ? 'PC' : 'Mobile',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    peer.isTyping
                        ? const Text(
                            'typing…',
                            style: TextStyle(
                              color: Color(0xFF25D366),
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        : Text(
                            isOnline ? 'Online • ${peer.ip}' : 'Offline • ${peer.ip}',
                            style: TextStyle(
                              color: isOnline ? Colors.white70 : Colors.white54,
                              fontSize: 12,
                              fontWeight: isOnline ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                  ],
                );
              },
            ),
          ),
          if (peer.id != 'local_ai_assistant') ...[
            IconButton(
              icon: Icon(
                Icons.call_rounded,
                color: _isWindowsDevice(peer) ? Colors.white54 : Colors.white,
              ),
              tooltip: _isWindowsDevice(peer) ? 'Calls supported on mobile only' : 'Audio call',
              onPressed: () => _startCall(peer, false),
            ),
            IconButton(
              icon: Icon(
                Icons.videocam_rounded,
                color: _isWindowsDevice(peer) ? Colors.white54 : Colors.white,
              ),
              tooltip: _isWindowsDevice(peer) ? 'Calls supported on mobile only' : 'Video call',
              onPressed: () => _startCall(peer, true),
            ),
          ],
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            tooltip: 'More options',
            onSelected: (value) async {
              if (value == 'files') {
                _openReceivedFilesModal();
              } else if (value == 'log') {
                setState(() => _showLogs = !_showLogs);
              } else if (value == 'toggle_ai_access') {
                final aiService = AiSettingsService();
                final currentlyAllowed = aiService.isPeerAllowed(peer.id, peer.ip);
                await aiService.setPeerAllowed(peer.id, !currentlyAllowed);
                if (mounted) {
                  setState(() {});
                  _toast(!currentlyAllowed
                      ? 'Allowed ${peer.name} to use My AI'
                      : 'Revoked My AI access for ${peer.name}');
                }
              } else if (value == 'clear') {
                _confirmClearChat(peer);
              }
            },
            itemBuilder: (context) {
              final isAiAllowed = AiSettingsService().isPeerAllowed(peer.id, peer.ip);
              return [
                if (peer.id != 'local_ai_assistant')
                  PopupMenuItem(
                    value: 'toggle_ai_access',
                    child: Row(
                      children: [
                        Icon(
                          isAiAllowed
                              ? Icons.auto_awesome_rounded
                              : Icons.auto_awesome_outlined,
                          size: 18,
                          color: isAiAllowed
                              ? const Color(0xFF10B981)
                              : Colors.grey,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isAiAllowed
                                ? 'Revoke My AI Access'
                                : 'Allow Peer to Use My AI',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isAiAllowed
                                  ? const Color(0xFF10B981)
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'files',
                  child: Row(
                    children: [
                      Icon(Icons.folder_shared_rounded, size: 18, color: Color(0xFF10B981)),
                      SizedBox(width: 10),
                      Text('View Received Files'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'log',
                  child: Row(
                    children: [
                      Icon(_showLogs ? Icons.article_rounded : Icons.article_outlined, size: 18, color: Theme.of(context).iconTheme.color),
                      const SizedBox(width: 10),
                      Text(_showLogs ? 'Hide Activity Log' : 'Show Activity Log'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                      SizedBox(width: 10),
                      Text('Clear Chat', style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionModeSwitch(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2C34) : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              key: _nearbyTabKey,
              onTap: () {
                setState(() => _connectionMode = ConnectionMode.lan);
                _firebasePresenceService.setInternetMode(false);
                _wanService.setInternetMode(false);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: _connectionMode == ConnectionMode.lan
                      ? (isDark ? const Color(0xFF005C4B) : const Color(0xFF075E54))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.wifi_rounded,
                      size: 14,
                      color: _connectionMode == ConnectionMode.lan ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Nearby',
                      style: TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.bold,
                        color: _connectionMode == ConnectionMode.lan ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              key: _p2pTabKey,
              onTap: () {
                setState(() => _connectionMode = ConnectionMode.p2p);
                _wanService.setInternetMode(false);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: _connectionMode == ConnectionMode.p2p
                      ? const Color(0xFF10B981)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.radar_rounded,
                      size: 14,
                      color: _connectionMode == ConnectionMode.p2p ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Direct P2P',
                      style: TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.bold,
                        color: _connectionMode == ConnectionMode.p2p ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              key: _wanTabKey,
              onTap: () {
                setState(() => _connectionMode = ConnectionMode.wan);
                _wanService.setInternetMode(true);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: _connectionMode == ConnectionMode.wan
                      ? (isDark ? const Color(0xFF005C4B) : const Color(0xFF075E54))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.public_rounded,
                      size: 14,
                      color: _connectionMode == ConnectionMode.wan ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'WAN Mesh',
                      style: TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.bold,
                        color: _connectionMode == ConnectionMode.wan ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showIncomingPairRequestDialog(WanPairRequest request) {
    final isRadar = request.isDirectRadar;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isRadar ? Icons.public_rounded : Icons.phonelink_lock_rounded,
              color: const Color(0xFF10B981),
            ),
            const SizedBox(width: 8),
            Text(
              isRadar ? 'Radar Connection Request' : 'PIN Pairing Request',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isRadar
                  ? '${request.fromDeviceName} (${request.fromPlatform}) discovered your device on WAN Radar and wants to connect.'
                  : '${request.fromDeviceName} (${request.fromPlatform}) entered your pair PIN code to connect.',
              style: const TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: Color(0xFF10B981), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Accepting will add ${request.fromDeviceName} as a trusted contact for direct messaging & file sharing.',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF005C4B)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _wanService.rejectPairRequest(request);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Connection request declined'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Decline', style: TextStyle(color: Colors.redAccent)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _wanService.acceptPairRequest(request);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Connected with ${request.fromDeviceName}!'),
                  backgroundColor: const Color(0xFF005C4B),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF005C4B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Accept & Connect'),
          ),
        ],
      ),
    );
  }

  void _showIncomingSessionDialog(WanSignalingSession session) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.hub_rounded, color: Color(0xFF10B981)),
            const SizedBox(width: 8),
            const Text('Incoming Internet P2P', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '${session.callerName} (${session.callerPlatform}) is requesting a direct WebRTC P2P connection.\n\nAccept connection?',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _wanRtcManager.rejectIncomingSession(session.sessionId);
            },
            child: const Text('Decline', style: TextStyle(color: Colors.redAccent)),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final peer = _wanService.trustedDevicesList.firstWhere(
                (d) => d.id == session.callerId,
                orElse: () => WanDevice(
                  id: session.callerId,
                  name: session.callerName,
                  platform: session.callerPlatform,
                  isOnline: true,
                  isTrusted: true,
                ),
              );
              await _wanRtcManager.acceptIncomingSession(session);
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WanActiveSessionScreen(peer: peer),
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF005C4B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Accept & Connect'),
          ),
        ],
      ),
    );
  }

  void _handleUnpairDevice(WanDevice device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Unpair Device', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to unpair "${device.name}"? You will need to enter a pair code again to reconnect.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _wanService.removeTrustedDevice(device.id);
              if (mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Unpaired ${device.name}'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
  }

  Future<void> _openWanPairingModal() async {
    final paired = await showDialog<WanDevice>(
      context: context,
      builder: (_) => const WanPairDialog(),
    );
    if (paired != null && mounted) {
      setState(() {});
    }
  }

  Future<void> _connectToWanPeer(WanDevice peer) async {
    _wanService.clearUnreadCount(peer.id);
    if (peer.isOnline && _wanService.isOnline) {
      _wanRtcManager.connectToPeer(peer).catchError((e) {
        debugPrint('[HomeScreen] WAN connect error: $e');
      });
    }
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WanActiveSessionScreen(peer: peer),
        ),
      ).then((_) async {
        final updated = await _historyService.load();
        if (mounted) {
          setState(() {
            _history.clear();
            _history.addAll(updated);
          });
        }
      });
    }
  }

  Widget _devicePane() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final peers = widget.service.peers;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildConnectionModeSwitch(isDark),
          if (_connectionMode == ConnectionMode.p2p)
            Expanded(
              child: P2pRadarView(
                p2pService: _wifiDirectService,
                onPeerConnectedTap: (peerName) {
                  Peer? matched;
                  for (final p in widget.service.peers) {
                    if (p.name.toLowerCase().contains(peerName.toLowerCase()) ||
                        peerName.toLowerCase().contains(p.name.toLowerCase()) ||
                        p.ip.startsWith('192.168.49.') ||
                        p.id == peerName ||
                        p.ip == peerName) {
                      matched = p;
                    }
                  }
                  if (matched != null) {
                    _selectPeer(matched);
                  } else if (widget.service.peers.isNotEmpty) {
                    _selectPeer(widget.service.peers.first);
                  }
                },
                onManualPairingTap: _openManualPairingModal,
              ),
            )
          else if (_connectionMode == ConnectionMode.wan)
            Expanded(
              child: WanRadarView(
                devices: _wanService.allRadarDevices,
                isOnline: _wanService.isOnline,
                isFirebaseConnected: _wanService.isFirebaseConnected,
                isInternetModeOn: _wanService.isInternetModeEnabled,
                currentDeviceId: _wanService.deviceId,
                currentDeviceName: _wanService.deviceName,
                onPairCodePressed: _openWanPairingModal,
                onDeviceSelected: (wanDevice) => _connectToWanPeer(wanDevice),
                onUnpairDevice: _handleUnpairDevice,
              ),
            )
          else ...[
            Row(
              children: [
                const Text('Nearby devices', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${peers.length} active',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_scanning && peers.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Scanning local network for devices…',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Expanded(
              child: peers.isEmpty
                  ? _RadarPulseScanner(
                      isScanning: _scanning,
                      onScanPressed: _scan,
                      onOpenWanPressed: () {
                        setState(() {
                          _connectionMode = ConnectionMode.wan;
                        });
                        _wanService.setInternetMode(true);
                      },
                    )
                  : ListView.separated(
                      itemCount: peers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final p = peers[index];
                        final isPinned = widget.service.isPeerPinned(p.id);
                        return PeerTile(
                          peer: p,
                          selected: p.id == _selectedPeerId,
                          isPinned: isPinned,
                          onTap: () => _selectPeer(p),
                          onLongPress: () => _showPeerContextMenu(p),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  String _getPeerAvatar(Peer peer) {
    if (peer.avatarEmoji != null && peer.avatarEmoji!.trim().isNotEmpty) {
      return peer.avatarEmoji!.trim();
    }
    final lowerName = peer.name.toLowerCase();
    if (lowerName.contains('windows') || lowerName.contains('pc') || lowerName.contains('desktop') || lowerName.contains('laptop') || lowerName.contains('win')) {
      return '💻';
    }
    return '📱';
  }

  void _showPeerContextMenu(Peer peer) {
    final isPinned = widget.service.isPeerPinned(peer.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: scheme.primary.withValues(alpha: 0.15),
                        child: Text(
                          _getPeerAvatar(peer),
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              peer.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              peer.isMeshPeer ? 'Mesh Relay Device' : peer.ip,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isPinned)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.push_pin_rounded, size: 12, color: scheme.primary),
                              const SizedBox(width: 4),
                              Text(
                                'Pinned',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 16),
                ListTile(
                  leading: Icon(
                    isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                    color: isPinned ? Colors.orange : scheme.primary,
                  ),
                  title: Text(
                    isPinned ? 'Unpin from top' : 'Pin to top',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final nowPinned = await widget.service.togglePinPeer(peer.id);
                    _toast(nowPinned ? '📌 Pinned ${peer.name} to top' : 'Unpinned ${peer.name}');
                    setState(() {});
                  },
                ),
                ListTile(
                  leading: Icon(Icons.chat_bubble_outline_rounded, color: scheme.primary),
                  title: const Text('Open Chat', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _selectPeer(peer);
                  },
                ),
                if (peer.unreadCount > 0)
                  ListTile(
                    leading: const Icon(Icons.mark_chat_read_outlined, color: Color(0xFF22C55E)),
                    title: const Text('Mark as read', style: TextStyle(fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        peer.unreadCount = 0;
                      });
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _processP2pPairingInput(String rawInput) async {
    final input = rawInput.trim();
    if (input.isEmpty) return;

    String? targetMac;
    String? targetIp;

    if (input.startsWith('farmitra_p2p:')) {
      final parts = input.split(':');
      // Format: farmitra_p2p:deviceName:macAddress:ip OR farmitra_p2p:deviceName:ip
      if (parts.length >= 4) {
        targetIp = parts.last;
        final middle = parts.sublist(2, parts.length - 1).join(':');
        if (middle.contains(':') || middle.length >= 12) {
          targetMac = middle;
        }
      } else if (parts.length == 3) {
        targetIp = parts[2];
      }
    } else if (input.contains(':') && input.length >= 12 && !input.contains('.')) {
      targetMac = input;
    } else {
      targetIp = input;
    }

    // 1. If MAC address is present, trigger native Wi-Fi Direct connection directly!
    if (targetMac != null && targetMac.isNotEmpty) {
      _toast('Sending native P2P connection request to MAC $targetMac…');
      final ok = await _wifiDirectService.connectP2pByAddress(targetMac);
      if (ok) {
        _toast('Native P2P request sent! Accept prompt on target device.');
        return;
      }
    }

    // 2. Check if matching peer exists in current scanned peers list
    P2pPeer? matchedPeer;
    for (final p in _wifiDirectService.peers) {
      if ((targetMac != null && p.deviceAddress.toLowerCase() == targetMac.toLowerCase()) ||
          (targetIp != null && (p.name.contains(targetIp) || p.deviceAddress.contains(targetIp)))) {
        matchedPeer = p;
        break;
      }
    }

    if (matchedPeer != null) {
      _toast('Connecting to ${matchedPeer.name}…');
      await _wifiDirectService.connectP2p(matchedPeer);
      return;
    }

    // 3. Fallback: bind via socket link
    if (targetIp != null && targetIp.isNotEmpty) {
      final peerId = await widget.service.bindP2pPeer(targetIp, null);
      if (peerId != null && mounted) {
        setState(() {});
        _toast('P2P connected to $targetIp!');
      } else {
        _toast('Pairing invitation sent to $targetIp');
      }
    }
  }

  Future<void> _openManualPairingModal() async {
    final ipController = TextEditingController();
    int activeTab = 0; // 0 = QR Code, 1 = Manual IP

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;
            final myMac = _wifiDirectService.thisDeviceAddress ?? '';
            final myIp = _wifiDirectService.localP2pIp ?? '192.168.49.1';
            final qrData = 'farmitra_p2p:${widget.service.deviceName}:$myMac:$myIp';

            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 36),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF10B981)),
                          const SizedBox(width: 8),
                          const Text('P2P QR Code & Manual Pairing', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Tab Switcher (My QR Code | Direct IP Input)
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setModalState(() => activeTab = 0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: activeTab == 0 ? const Color(0xFF10B981) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.qr_code_rounded, size: 16, color: activeTab == 0 ? Colors.white : Colors.grey),
                                      const SizedBox(width: 6),
                                      Text('My QR Code', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: activeTab == 0 ? Colors.white : Colors.grey)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setModalState(() => activeTab = 1),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: activeTab == 1 ? const Color(0xFF10B981) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.lan_rounded, size: 16, color: activeTab == 1 ? Colors.white : Colors.grey),
                                      const SizedBox(width: 6),
                                      Text('Direct IP Input', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: activeTab == 1 ? Colors.white : Colors.grey)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (activeTab == 0) ...[
                        // QR Code Display
                        P2pQrWidget(data: qrData, size: 210),
                        const SizedBox(height: 14),
                        Text(
                          '${widget.service.deviceName} ${myMac.isNotEmpty ? "• $myMac" : ""} • $myIp',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Show this QR code to peer device for instant P2P pairing',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: myMac.isNotEmpty ? myMac : myIp));
                                  _toast('Copied: ${myMac.isNotEmpty ? myMac : myIp}');
                                },
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                label: const Text('Copy Address'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () async {
                                  Navigator.pop(context);
                                  final rawScanned = await Navigator.push<String>(
                                    context,
                                    MaterialPageRoute(builder: (_) => const QrScannerScreen()),
                                  );
                                  if (rawScanned != null && rawScanned.isNotEmpty) {
                                    await _processP2pPairingInput(rawScanned);
                                  }
                                },
                                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                                icon: const Icon(Icons.camera_alt_rounded, size: 18),
                                label: const Text('Scan QR Code', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        // Direct IP / Payload Input View
                        Text(
                          'Enter target device IP address (e.g. 192.168.49.1) or MAC Address / QR payload to pair directly.',
                          style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white60 : Colors.black54),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: ipController,
                          keyboardType: TextInputType.text,
                          decoration: InputDecoration(
                            labelText: 'Target Device IP or QR Payload / MAC',
                            hintText: '192.168.49.1 or fa:4b:9c:12:34:56',
                            prefixIcon: const Icon(Icons.lan_rounded),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () async {
                              final input = ipController.text.trim();
                              if (input.isNotEmpty) {
                                Navigator.pop(context);
                                await _processP2pPairingInput(input);
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.link_rounded),
                            label: const Text('Connect IP / MAC Directly', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }


  Widget _chatPane({bool isMobile = false}) {
    final peer = _selectedPeer;
    if (peer == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 64, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text(
              'Select a device to start chatting',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      );
    }
    final chat = _currentChat;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // WhatsApp-like chat background color
    final chatBg = isDark ? const Color(0xFF0B141A) : const Color(0xFFEFEAE2);

    return Container(
      color: chatBg,
      child: Column(
        children: [
          if (!isMobile) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: isDark ? const Color(0xFF1F2C34) : Colors.white,
              child: Row(
                children: [
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final isOnline = _isPeerOnline(peer);
                      return Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: isOnline ? const Color(0xFF10B981) : Colors.grey.shade600,
                            child: peer.id == 'local_ai_assistant'
                                ? const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22)
                                : Text(
                                    peer.name.isNotEmpty ? peer.name[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                peer.id == 'local_ai_assistant' ? 'My AI' : peer.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              peer.id == 'local_ai_assistant'
                                  ? const Text('Configured Local AI • Saved Settings', style: TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.w600))
                                  : (peer.isTyping
                                      ? const Text(
                                          'typing…',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF25D366),
                                            fontWeight: FontWeight.bold,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        )
                                      : Row(
                                          children: [
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: isOnline ? const Color(0xFF10B981) : Colors.grey,
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              isOnline ? 'Online • ${peer.ip}' : 'Offline • ${peer.ip}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isOnline ? (isDark ? Colors.white70 : Colors.black87) : Colors.grey,
                                                fontWeight: isOnline ? FontWeight.w600 : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        )),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
                  if (peer.id != 'local_ai_assistant') ...[
                    IconButton(
                      icon: Icon(
                        Icons.call_rounded,
                        color: _isWindowsDevice(peer) ? Colors.white54 : Theme.of(context).iconTheme.color,
                      ),
                      tooltip: _isWindowsDevice(peer) ? 'Calls supported on mobile only' : 'Audio call',
                      onPressed: () => _startCall(peer, false),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.videocam_rounded,
                        color: _isWindowsDevice(peer) ? Colors.white54 : Theme.of(context).iconTheme.color,
                      ),
                      tooltip: _isWindowsDevice(peer) ? 'Calls supported on mobile only' : 'Video call',
                      onPressed: () => _startCall(peer, true),
                    ),
                    IconButton(onPressed: _pickAndSend, tooltip: 'Send file', icon: const Icon(Icons.attach_file_rounded)),
                  ],
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded),
                    tooltip: 'More options',
                    onSelected: (value) {
                      if (value == 'files') {
                        _openReceivedFilesModal();
                      } else if (value == 'ai_toggle') {
                        final aiService = AiSettingsService();
                        final isCurrentlyAllowed = aiService.isPeerAllowed(peer.id, peer.ip);
                        final nextAllowed = !isCurrentlyAllowed;
                        peer.isAiHostAllowed = nextAllowed;
                        aiService.setPeerAllowed(peer.id, nextAllowed);
                        setState(() {});
                        _toast(nextAllowed
                            ? 'Nearby AI access allowed for ${peer.name}'
                            : 'Nearby AI access revoked for ${peer.name}');
                      } else if (value == 'cctv') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StreamHubScreen(
                              service: widget.service,
                              targetPeer: peer,
                              initialStreamType: 'camera',
                              onOpenSettings: _openSettingsModal,
                            ),
                          ),
                        );
                      } else if (value == 'audio_stream') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StreamHubScreen(
                              service: widget.service,
                              targetPeer: peer,
                              initialStreamType: 'audio',
                              onOpenSettings: _openSettingsModal,
                            ),
                          ),
                        );
                      } else if (value == 'log') {
                        setState(() => _showLogs = !_showLogs);
                      } else if (value == 'clear') {
                        _confirmClearChat(peer);
                      }
                    },
                    itemBuilder: (context) {
                      final isAiAllowed = AiSettingsService().isPeerAllowed(peer.id, peer.ip);
                      final isNotAiPeer = peer.id != 'local_ai_assistant';

                      return [
                        const PopupMenuItem(
                          value: 'files',
                          child: Row(
                            children: [
                              Icon(Icons.folder_shared_rounded, size: 18, color: Color(0xFF10B981)),
                              SizedBox(width: 10),
                              Text('View Received Files'),
                            ],
                          ),
                        ),
                        if (isNotAiPeer) ...[
                          PopupMenuItem(
                            value: 'ai_toggle',
                            child: Row(
                              children: [
                                Icon(
                                  isAiAllowed ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined,
                                  size: 18,
                                  color: isAiAllowed ? const Color(0xFF10B981) : Colors.grey,
                                ),
                                SizedBox(width: 10),
                                Text(isAiAllowed ? 'Disable Nearby AI Access' : 'Allow Nearby AI Access'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'cctv',
                            child: Row(
                              children: [
                                Icon(Icons.videocam_rounded, size: 18, color: Color(0xFF3B82F6)),
                                SizedBox(width: 10),
                                Text('CCTV Stream (Video)'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'audio_stream',
                            child: Row(
                              children: [
                                Icon(Icons.mic_rounded, size: 18, color: Color(0xFF8B5CF6)),
                                SizedBox(width: 10),
                                Text('Live Audio Stream'),
                              ],
                            ),
                          ),
                        ],
                        PopupMenuItem(
                          value: 'log',
                          child: Row(
                            children: [
                              Icon(_showLogs ? Icons.article_rounded : Icons.article_outlined, size: 18, color: Theme.of(context).iconTheme.color),
                              const SizedBox(width: 10),
                              Text(_showLogs ? 'Hide Activity Log' : 'Show Activity Log'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'clear',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                              SizedBox(width: 10),
                              Text('Clear Chat', style: TextStyle(color: Colors.redAccent)),
                            ],
                          ),
                        ),
                      ];
                    },
                  ),
                ],
              ),
            ),
          ],

          // People | Nearby AI Mode Switcher
          _buildChatModeSwitch(isDark, peer),

          Expanded(
            child: (chat.isEmpty && !_aiThinking)
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF182229) : const Color(0xFFFFF5C4),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: Text(
                        _chatMode == ChatMode.ai
                            ? 'Nearby AI Mode: Prompts are handled by ${peer.name}'
                            : 'End-to-end local network chat with ${peer.name}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? Colors.white70 : const Color(0xFF54656F),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  )
                : Builder(
                    builder: (context) {
                      final hasMore = chat.length < _fullCurrentChat.length;
                      final showTyping = peer.isTyping;
                      final totalCount = chat.length + (hasMore ? 1 : 0) + (_aiThinking ? 1 : 0) + (showTyping ? 1 : 0);

                      return ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        itemCount: totalCount,
                        itemBuilder: (context, index) {
                          if (hasMore && index == 0) {
                            final remaining = _fullCurrentChat.length - chat.length;
                            return Center(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _chatDisplayCount += 20;
                                  });
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1F2C34) : const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.arrow_upward_rounded, size: 14, color: Color(0xFF10B981)),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Load earlier messages ($remaining more)',
                                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }

                          final itemIndex = index - (hasMore ? 1 : 0);
                          if (_aiThinking && itemIndex == chat.length) {
                            return _buildAiThinkingBubble(isDark, peer);
                          }
                          if (showTyping && itemIndex == (chat.length + (_aiThinking ? 1 : 0))) {
                            return _buildTypingBubble(isDark, peer);
                          }
                          return ChatBubble(
                            item: chat[itemIndex],
                            onCancel: chat[itemIndex].status == 'Queued'
                                ? () => _cancelQueuedMessage(chat[itemIndex])
                                : null,
                            onReact: (emoji) => _toggleReactionOnMessage(
                                chat[itemIndex], emoji, peer),
                            onReply: (item) {
                              setState(() {
                                _replyingToItem = item;
                              });
                            },
                            onForward: (item) {
                              ForwardMessageDialog.show(
                                context,
                                item: item,
                                onForwardComplete: (targetName) async {
                                  _toast('Forwarded to $targetName');
                                  final updated = await _historyService.load();
                                  if (mounted) {
                                    setState(() {
                                      _history.clear();
                                      _history.addAll(updated);
                                    });
                                  }
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
          if (_chatMode == ChatMode.people &&
              widget.service.transfer.active &&
              (widget.service.transfer.peerId == peer.id ||
               widget.service.transfer.peerId == peer.ip))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: TransferCard(state: widget.service.transfer),
            ),
          if (_showLogs) ...[
            Container(
              height: 120,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: isDark ? const Color(0xFF1F2C34) : Colors.black87,
              child: ListView(
                children: widget.service.logs.reversed.take(30).map((e) => Text(e, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Colors.greenAccent))).toList(),
              ),
            ),
          ],
          // WhatsApp Quoted Reply Preview Bar
          if (_replyingToItem != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2C34) : const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(12),
                border: Border(
                  left: BorderSide(
                    color: isDark ? const Color(0xFF25D366) : const Color(0xFF00A884),
                    width: 4,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _replyingToItem!.mine ? 'You' : _replyingToItem!.sender,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFF25D366) : const Color(0xFF00A884),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _replyingToItem!.kind == ChatKind.text
                              ? (_replyingToItem!.text ?? '')
                              : '📁 ${_replyingToItem!.fileName ?? "Attachment"}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: isDark ? Colors.white60 : Colors.black54,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    splashRadius: 16,
                    onPressed: () {
                      setState(() {
                        _replyingToItem = null;
                      });
                    },
                    tooltip: 'Cancel reply',
                  ),
                ],
              ),
            ),
          // Floating Input Box
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            color: Colors.transparent,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF202C33) : Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        if (_chatMode == ChatMode.people) ...[
                          IconButton(
                            icon: Icon(Icons.attach_file_rounded,
                                color: isDark
                                    ? Colors.grey[400]
                                    : const Color(0xFF54656F)),
                            onPressed: _showAttachmentOptions,
                            tooltip: 'Attach file or folder',
                          ),
                        ] else ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.auto_awesome_rounded, color: Color(0xFF10B981), size: 20),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: TextField(
                            controller: _message,
                            textInputAction: TextInputAction.send,
                            onChanged: _onTextChanged,
                            onSubmitted: (_) => _sendMessage(),
                            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
                            decoration: InputDecoration(
                              hintText: _chatMode == ChatMode.ai ? 'Ask ${peer.name} Nearby AI…' : 'Message…',
                              hintStyle: TextStyle(color: isDark ? Colors.grey[500] : const Color(0xFF8696A0)),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _chatMode == ChatMode.ai ? const Color(0xFF10B981) : const Color(0xFF169B62),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_chatMode == ChatMode.ai ? const Color(0xFF10B981) : const Color(0xFF169B62)).withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: _aiThinking
                        ? const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatModeSwitch(bool isDark, Peer peer) {
    if (peer.id == 'local_ai_assistant') return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2C34) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeSegmentButton(
            title: 'Normal',
            icon: Icons.chat_bubble_outline_rounded,
            mode: ChatMode.people,
            isDark: isDark,
          ),
          _modeSegmentButton(
            title: 'Nearby AI',
            icon: Icons.auto_awesome_rounded,
            mode: ChatMode.ai,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _modeSegmentButton({
    required String title,
    required IconData icon,
    required ChatMode mode,
    required bool isDark,
  }) {
    final active = _chatMode == mode;
    return GestureDetector(
      onTap: () {
        if (_chatMode == mode) return;
        setState(() {
          _chatMode = mode;
        });
        _triggerScrollToBottom();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? (mode == ChatMode.ai ? const Color(0xFF10B981) : const Color(0xFF169B62))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: active ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
                color: active ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiThinkingBubble(bool isDark, Peer peer) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Waiting for ${peer.name} Nearby AI…',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF10B981),
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingBubble(bool isDark, Peer peer) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF25D366),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${peer.name} is typing…',
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF25D366),
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarPulseScanner extends StatefulWidget {
  const _RadarPulseScanner({
    required this.isScanning,
    required this.onScanPressed,
    this.onOpenWanPressed,
  });

  final bool isScanning;
  final VoidCallback onScanPressed;
  final VoidCallback? onOpenWanPressed;

  @override
  State<_RadarPulseScanner> createState() => _RadarPulseScannerState();
}

class _RadarPulseScannerState extends State<_RadarPulseScanner> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.isScanning) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _RadarPulseScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning != oldWidget.isScanning) {
      if (widget.isScanning) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _RadarPainter(_controller.value, isDark: isDark, isScanning: widget.isScanning),
                    child: Center(
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? const Color(0xFF10B981).withValues(alpha: 0.2)
                              : const Color(0xFF10B981).withValues(alpha: 0.12),
                          border: Border.all(color: const Color(0xFF10B981), width: 2),
                        ),
                        child: Transform.rotate(
                          angle: widget.isScanning ? _controller.value * 2 * 3.1415926535 : 0,
                          child: const Icon(Icons.radar_rounded, size: 30, color: Color(0xFF10B981)),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.isScanning ? 'Scanning local network…' : 'No devices found',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            const SizedBox(height: 8),
            Text(
              'Ensure NearMitra is open on another device connected to the same Wi‑Fi.',
              textAlign: TextAlign.center,
              style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600], fontSize: 12.5),
            ),
            if (widget.onOpenWanPressed != null) ...[
              const SizedBox(height: 14),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onOpenWanPressed,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 320),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.public_rounded, size: 16, color: Color(0xFF10B981)),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Open WAN / Internet to connect with Global devices →',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: widget.onScanPressed,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.search_rounded),
              label: Text(
                widget.isScanning ? 'Scanning…' : 'Scan Network',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.progress, {required this.isDark, required this.isScanning});

  final double progress;
  final bool isDark;
  final bool isScanning;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    if (!isScanning) return;

    for (int i = 0; i < 3; i++) {
      final waveProgress = (progress + (i * 0.333)) % 1.0;
      final radius = waveProgress * maxRadius;
      final opacity = (1.0 - waveProgress).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: opacity * 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) => true;
}

class _AnimatedAiFab extends StatefulWidget {
  const _AnimatedAiFab({required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<_AnimatedAiFab> createState() => _AnimatedAiFabState();
}

class _AnimatedAiFabState extends State<_AnimatedAiFab> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _pulseAnimation = Tween<double>(begin: 8.0, end: 20.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.45),
                  blurRadius: _pulseAnimation.value,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: SizedBox(
              width: 44,
              height: 44,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: const Color(0xFF10B981),
                elevation: 3,
                tooltip: 'My AI Assistant',
                onPressed: widget.onPressed,
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ),
        );
      },
    );
  }
}
