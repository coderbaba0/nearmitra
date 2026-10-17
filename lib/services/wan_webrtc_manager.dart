import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_item.dart';
import '../models/wan_models.dart';
import 'history_service.dart';
import 'ice_config.dart';
import 'nearby_service.dart';
import 'notification_service.dart';
import 'wan_service.dart';

class WanWebRtcManager extends ChangeNotifier {
  static final WanWebRtcManager _instance = WanWebRtcManager._internal();
  factory WanWebRtcManager() => _instance;
  WanWebRtcManager._internal();

  final WanService _wanService = WanService();

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  String? _activeSessionId;
  String? _activePeerId;
  WanDevice? _activePeer;
  bool _isCaller = false;
  bool _remoteDeliveryAck = false;
  Completer<void>? _handshakeReceived;
  final Map<String, Completer<bool>> _deliveryWaiters = {};
  bool _isManuallyDisconnected = false;

  WanConnectionState _state = WanConnectionState.disconnected;

  StreamSubscription? _answerSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _candidatesSub;
  Timer? _sessionTimeoutTimer;
  Timer? _heartbeatTimer;

  // Reconnect state
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  Timer? _reconnectTimer;

  // Pending candidate queues for proper sequencing
  final List<RTCIceCandidate> _pendingLocalCandidates = [];
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _hasRemoteDescription = false;
  bool _isSessionPublished = false;

  // Deduplication for ICE candidates
  final Set<String> _processedCandidates = {};

  // File Transfer tracking
  final Map<String, WanFileTransferProgress> _activeTransfers = {};
  IOSink? _currentFileSink;
  String? _currentReceivingFileId;
  String? _currentReceivingFileName;
  int _currentReceivingFileSize = 0;
  int _currentReceivingBytes = 0;
  DateTime? _transferStartTime;
  String? _currentSavedFilePath;
  bool _isCurrentTransferCancelled = false;
  bool _currentReceivingFolder = false;

  // Direct chat history (Rich ChatItems)
  final List<ChatItem> _directChatItems = [];

  // Offline Outbox Queue
  final List<QueuedOutboxItem> _outbox = [];
  static const _kWanOutboxKey = 'nearmitra_wan_outbox_queue_v1';
  bool _isFlushingOutbox = false;
  bool useUnifiedOutbox = false;

  // Typing Indicator
  bool _peerIsTyping = false;
  Timer? _peerTypingTimer;
  bool get peerIsTyping => _peerIsTyping;

  // Callback for incoming session requests
  Function(WanSignalingSession session)? onIncomingSessionRequest;

  WanConnectionState get state => _state;
  WanDevice? get activePeer => _activePeer;
  bool get isCaller => _isCaller;
  String? get activePeerId => _activePeerId;
  List<WanFileTransferProgress> get activeTransfers =>
      _activeTransfers.values.toList();
  List<ChatItem> get directChatItems => List.unmodifiable(_directChatItems);
  List<QueuedOutboxItem> get outbox => List.unmodifiable(_outbox);
  List<Map<String, dynamic>> get directMessages =>
      _directChatItems.map((e) => e.toJson()).toList();
  bool get isConnected =>
      _state == WanConnectionState.connected &&
      _dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen;

  void init() {
    _wanService.onIncomingSessionRequest = _handleIncomingSession;
    _loadOutbox();
  }

  void _setState(WanConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      debugPrint('[WanWebRtc] State changed to: ${newState.name}');
      notifyListeners();
    }
  }

  /// Connect to an online trusted peer via WebRTC STUN/TURN NAT traversal
  Future<void> connectToPeer(WanDevice peer) async {
    if (!peer.isTrusted) {
      throw Exception('Device is not trusted. Please pair first.');
    }

    if (_state == WanConnectionState.connecting ||
        _state == WanConnectionState.signaling ||
        _state == WanConnectionState.negotiating ||
        _state == WanConnectionState.connected) {
      if (_activePeerId == peer.id) return;
      await disconnect();
    }

    _activePeer = peer;
    _activePeerId = peer.id;
    _remoteDeliveryAck = false;
    _handshakeReceived = Completer<void>();
    _isCaller = true;
    _isManuallyDisconnected = false;
    _reconnectAttempts = 0;
    _processedCandidates.clear();
    _pendingLocalCandidates.clear();
    _pendingRemoteCandidates.clear();
    _hasRemoteDescription = false;
    _isSessionPublished = false;

    _activeSessionId = const Uuid().v4();
    _setState(WanConnectionState.connecting);

    try {
      await loadChatHistory(_activePeerId!);
      // 1. Create RTCPeerConnection with centralized STUN/TURN config
      _peerConnection = await createPeerConnection(
        IceConfig.getRtcConfiguration(),
        IceConfig.peerConnectionConstraints,
      );
      _setupPeerConnectionListeners();

      // 2. Set up local candidate gathering handler IMMEDIATELY before setting local description
      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
          debugPrint(
              '[WanWebRtc] Local ICE candidate gathered: ${candidate.candidate}');
          if (_isSessionPublished && _activeSessionId != null) {
            _wanService.addIceCandidate(
              sessionId: _activeSessionId!,
              isCaller: true,
              candidateMap: {
                'candidate': candidate.candidate,
                'sdpMid': candidate.sdpMid,
                'sdpMLineIndex': candidate.sdpMLineIndex,
              },
            );
          } else {
            _pendingLocalCandidates.add(candidate);
          }
        }
      };

      // 3. Create RTCDataChannel as caller (ordered, reliable)
      final dcInit = RTCDataChannelInit()
        ..ordered = true
        ..maxRetransmits = 30;
      _dataChannel =
          await _peerConnection!.createDataChannel('nearmitra_wan_dc', dcInit);
      _setupDataChannelListeners();

      // 4. Create WebRTC Offer
      _setState(WanConnectionState.signaling);
      final offer =
          await _peerConnection!.createOffer(IceConfig.offerConstraints);
      await _peerConnection!.setLocalDescription(offer);

      // 5. Write Offer to Firebase RTDB: sessions/{sessionId}
      await _wanService.createSignalingSession(
        sessionId: _activeSessionId!,
        receiverId: peer.id,
        offerSdp: {'type': offer.type, 'sdp': offer.sdp},
      );
      _isSessionPublished = true;

      // Drain any local ICE candidates that were gathered during setLocalDescription
      for (final cand in _pendingLocalCandidates) {
        await _wanService.addIceCandidate(
          sessionId: _activeSessionId!,
          isCaller: true,
          candidateMap: {
            'candidate': cand.candidate,
            'sdpMid': cand.sdpMid,
            'sdpMLineIndex': cand.sdpMLineIndex,
          },
        );
      }
      _pendingLocalCandidates.clear();

      // 6. Start timeout timer (40 seconds)
      _sessionTimeoutTimer?.cancel();
      _sessionTimeoutTimer = Timer(const Duration(seconds: 40), () {
        if (_state != WanConnectionState.connected) {
          debugPrint('[WanWebRtc] Session connection timed out');
          _setState(WanConnectionState.failed);
          disconnect();
        }
      });

      // 7. Listen to Answer, Status, and Receiver ICE candidates from Firebase
      _listenToCallerSessionUpdates(_activeSessionId!);
    } catch (e) {
      debugPrint('[WanWebRtc] Connect error: $e');
      _setState(WanConnectionState.failed);
      await disconnect();
    }
  }

  /// Handle incoming session notification from WanService
  void _handleIncomingSession(WanSignalingSession session) {
    if (_state == WanConnectionState.connected) {
      // Already in an active session, auto-reject busy
      _wanService.rejectSignalingSession(session.sessionId);
      return;
    }

    onIncomingSessionRequest?.call(session);
  }

  /// Accept incoming session and establish WebRTC connection
  Future<void> acceptIncomingSession(WanSignalingSession session) async {
    _activeSessionId = session.sessionId;
    _activePeerId = session.callerId;
    _remoteDeliveryAck = false;
    _handshakeReceived = Completer<void>();
    _isCaller = false;
    _isManuallyDisconnected = false;
    _reconnectAttempts = 0;
    _processedCandidates.clear();
    _pendingLocalCandidates.clear();
    _pendingRemoteCandidates.clear();
    _hasRemoteDescription = false;
    _isSessionPublished = true;

    _activePeer = _wanService.trustedDevicesList.firstWhere(
      (d) => d.id == session.callerId,
      orElse: () => WanDevice(
        id: session.callerId,
        name: session.callerName,
        platform: session.callerPlatform,
        isOnline: true,
        isTrusted: true,
      ),
    );

    _setState(WanConnectionState.connecting);

    try {
      await loadChatHistory(_activePeerId!);
      // 1. Create RTCPeerConnection
      _peerConnection = await createPeerConnection(
        IceConfig.getRtcConfiguration(),
        IceConfig.peerConnectionConstraints,
      );
      _setupPeerConnectionListeners();

      // Listen for remote DataChannel
      _peerConnection!.onDataChannel = (channel) {
        debugPrint('[WanWebRtc] Received remote DataChannel: ${channel.label}');
        _dataChannel = channel;
        _setupDataChannelListeners();
      };

      // Set up local candidate gathering handler IMMEDIATELY
      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
          debugPrint(
              '[WanWebRtc] Local receiver ICE candidate gathered: ${candidate.candidate}');
          if (_isSessionPublished && _activeSessionId != null) {
            _wanService.addIceCandidate(
              sessionId: _activeSessionId!,
              isCaller: false,
              candidateMap: {
                'candidate': candidate.candidate,
                'sdpMid': candidate.sdpMid ?? '0',
                'sdpMLineIndex': candidate.sdpMLineIndex ?? 0,
              },
            );
          } else {
            _pendingLocalCandidates.add(candidate);
          }
        }
      };

      // 2. Listen to Caller ICE candidates and Status from Firebase
      _listenToReceiverSessionUpdates(session.sessionId);

      // 3. Set Remote Description (Caller Offer)
      final offerMap = session.offer;
      if (offerMap == null || offerMap['sdp'] == null) {
        throw Exception('Invalid offer SDP in signaling session');
      }
      final offerSdp = RTCSessionDescription(
          offerMap['sdp'] as String, offerMap['type'] as String? ?? 'offer');
      await _peerConnection!.setRemoteDescription(offerSdp);
      _hasRemoteDescription = true;

      // Drain queued remote candidates if any arrived before setRemoteDescription
      for (final cand in _pendingRemoteCandidates) {
        try {
          await _peerConnection!.addCandidate(cand);
          debugPrint(
              '[WanWebRtc] Added queued remote ICE candidate on receiver');
        } catch (e) {
          debugPrint('[WanWebRtc] Error adding queued remote candidate: $e');
        }
      }
      _pendingRemoteCandidates.clear();

      // 4. Create WebRTC Answer
      _setState(WanConnectionState.negotiating);
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // 5. Submit Answer SDP to Firebase: sessions/{sessionId}/answer
      await _wanService.acceptSignalingSession(
        sessionId: session.sessionId,
        answerSdp: {'type': answer.type, 'sdp': answer.sdp},
      );
      _isSessionPublished = true;

      // Drain any local ICE candidates gathered during receiver setLocalDescription
      for (final cand in _pendingLocalCandidates) {
        await _wanService.addIceCandidate(
          sessionId: session.sessionId,
          isCaller: false,
          candidateMap: {
            'candidate': cand.candidate,
            'sdpMid': cand.sdpMid ?? '0',
            'sdpMLineIndex': cand.sdpMLineIndex ?? 0,
          },
        );
      }
      _pendingLocalCandidates.clear();

      // 6. Start timeout timer
      _sessionTimeoutTimer?.cancel();
      _sessionTimeoutTimer = Timer(const Duration(seconds: 40), () {
        if (_state != WanConnectionState.connected) {
          debugPrint('[WanWebRtc] Receiver connection timed out');
          _setState(WanConnectionState.failed);
          disconnect();
        }
      });
    } catch (e) {
      debugPrint('[WanWebRtc] Accept incoming session error: $e');
      _setState(WanConnectionState.failed);
      await disconnect();
    }
  }

  /// Reject incoming session
  Future<void> rejectIncomingSession(String sessionId) async {
    await _wanService.rejectSignalingSession(sessionId);
  }

  /// Listen to Answer, Status, and Candidates for Caller
  void _listenToCallerSessionUpdates(String sessionId) {
    _answerSub?.cancel();
    _answerSub = _wanService.listenToAnswer(sessionId, (answerMap) async {
      if (_peerConnection == null || _state == WanConnectionState.connected) {
        return;
      }
      try {
        final answerSdp = RTCSessionDescription(answerMap['sdp'] as String,
            answerMap['type'] as String? ?? 'answer');
        await _peerConnection!.setRemoteDescription(answerSdp);
        _hasRemoteDescription = true;
        _setState(WanConnectionState.negotiating);
        debugPrint('[WanWebRtc] Caller applied remote Answer SDP successfully');

        // Drain queued remote candidates on caller
        for (final cand in _pendingRemoteCandidates) {
          try {
            await _peerConnection!.addCandidate(cand);
            debugPrint(
                '[WanWebRtc] Added queued remote ICE candidate on caller');
          } catch (e) {
            debugPrint('[WanWebRtc] Error adding queued remote candidate: $e');
          }
        }
        _pendingRemoteCandidates.clear();
      } catch (e) {
        debugPrint('[WanWebRtc] Error setting remote description: $e');
      }
    });

    _statusSub?.cancel();
    _statusSub = _wanService.listenToSessionStatus(sessionId, (status) {
      debugPrint('[WanWebRtc] Session status updated: $status');
      if (status == 'rejected') {
        _setState(WanConnectionState.failed);
        disconnect();
      }
    });

    _listenToIceCandidates(sessionId, isCaller: true);
  }

  /// Listen to Candidates for Receiver
  void _listenToReceiverSessionUpdates(String sessionId) {
    _statusSub?.cancel();
    _statusSub = _wanService.listenToSessionStatus(sessionId, (status) {
      debugPrint('[WanWebRtc] Receiver session status: $status');
      if (status == 'rejected' || status == 'ended') {
        _setState(WanConnectionState.disconnected);
        disconnect();
      }
    });

    _listenToIceCandidates(sessionId, isCaller: false);
  }

  /// Exchange ICE candidates via Firebase
  void _listenToIceCandidates(String sessionId, {required bool isCaller}) {
    // Receive remote candidates from Firebase
    _candidatesSub?.cancel();
    _candidatesSub =
        _wanService.listenToCandidates(sessionId, isCaller, (candMap) async {
      if (_peerConnection == null) return;
      final candStr = candMap['candidate'] as String?;
      final sdpMid = (candMap['sdpMid'] as String?) ?? '0';
      final sdpMLineIndex = candMap['sdpMLineIndex'] != null
          ? ((candMap['sdpMLineIndex'] is num)
              ? (candMap['sdpMLineIndex'] as num).toInt()
              : int.tryParse(candMap['sdpMLineIndex'].toString()) ?? 0)
          : 0;

      if (candStr != null &&
          candStr.isNotEmpty &&
          !_processedCandidates.contains(candStr)) {
        _processedCandidates.add(candStr);
        final iceCandidate = RTCIceCandidate(candStr, sdpMid, sdpMLineIndex);

        if (_hasRemoteDescription) {
          try {
            await _peerConnection!.addCandidate(iceCandidate);
            debugPrint('[WanWebRtc] Added remote ICE candidate');
          } catch (e) {
            debugPrint('[WanWebRtc] Error adding candidate: $e');
          }
        } else {
          _pendingRemoteCandidates.add(iceCandidate);
          debugPrint(
              '[WanWebRtc] Queued remote ICE candidate (waiting for remote description)');
        }
      }
    });
  }

  Timer? _iceDisconnectTimer;

  void _setupPeerConnectionListeners() {
    _peerConnection?.onIceConnectionState = (state) {
      debugPrint('[WanWebRtc] ICE Connection State: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _iceDisconnectTimer?.cancel();
        _sessionTimeoutTimer?.cancel();
        _setState(WanConnectionState.connected);
        // Clean up temporary Firebase signaling session after a safety delay so both peers finish ICE candidate pairing!
        final sId = _activeSessionId;
        if (sId != null) {
          Timer(const Duration(seconds: 25), () {
            _wanService.deleteSignalingSession(sId);
          });
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _iceDisconnectTimer?.cancel();
        _handleConnectionFailure();
      } else if (state ==
          RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        // Transient cellular/Wi-Fi route change grace period (8 seconds)
        _iceDisconnectTimer?.cancel();
        _iceDisconnectTimer = Timer(const Duration(seconds: 8), () {
          if (_state != WanConnectionState.connected) {
            _handleConnectionDisconnected();
          }
        });
      }
    };

    _peerConnection?.onConnectionState = (state) {
      debugPrint('[WanWebRtc] PeerConnection State: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _iceDisconnectTimer?.cancel();
        _sessionTimeoutTimer?.cancel();
        _setState(WanConnectionState.connected);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _iceDisconnectTimer?.cancel();
        _handleConnectionFailure();
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _iceDisconnectTimer?.cancel();
        _handleConnectionDisconnected();
      }
    };
  }

  Future<void> _incomingMessages = Future<void>.value();

  void _setupDataChannelListeners() {
    if (_dataChannel == null) return;

    _dataChannel!.onDataChannelState = (state) {
      debugPrint('[WanWebRtc] DataChannel State: $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _iceDisconnectTimer?.cancel();
        _sessionTimeoutTimer?.cancel();
        _reconnectAttempts = 0;
        _setState(WanConnectionState.connected);
        _startHeartbeat();

        // Send application-level handshake sync to guarantee both sides are connected
        try {
          _dataChannel!.send(RTCDataChannelMessage(
            jsonEncode({
              'type': 'handshake_syn',
              'senderId': _wanService.deviceId,
              'deliveryAck': true
            }),
          ));
        } catch (_) {}

        if (_activePeerId != null) {
          flushQueueForPeer(_activePeerId!);
        }
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _stopHeartbeat();
        _handleConnectionDisconnected();
      }
    };

    final channel = _dataChannel;
    _dataChannel!.onMessage = (RTCDataChannelMessage message) {
      _incomingMessages = _incomingMessages.then((_) async {
        if (channel != _dataChannel) return;
        if (message.isBinary) {
          _handleBinaryMessage(message.binary);
        } else {
          await _handleTextMessage(message.text);
        }
      }).catchError((Object error, StackTrace stack) {
        debugPrint('[WanWebRtc] Incoming message error: $error');
      });
    };
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
        try {
          _dataChannel!.send(
              RTCDataChannelMessage(WanDataMessage.ping().toJsonString()));
        } catch (_) {}
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _handleConnectionFailure() {
    _stopHeartbeat();
    _setState(WanConnectionState.failed);
    _scheduleReconnect();
  }

  void _handleConnectionDisconnected() {
    _stopHeartbeat();
    _setState(WanConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_isManuallyDisconnected ||
        _activePeer == null ||
        !_activePeer!.isOnline) {
      return;
    }

    if (_reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      final delaySeconds = _reconnectAttempts * 3;
      debugPrint(
          '[WanWebRtc] Scheduling auto-reconnect attempt $_reconnectAttempts in $delaySeconds seconds...');

      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
        if (!_isManuallyDisconnected &&
            _activePeer != null &&
            _state != WanConnectionState.connected) {
          connectToPeer(_activePeer!);
        }
      });
    }
  }

  Future<void> _loadOutbox() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kWanOutboxKey) ?? [];
      _outbox.clear();
      for (final raw in list) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          _outbox.add(QueuedOutboxItem.fromJson(map));
        } catch (_) {}
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveOutbox() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = _outbox.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList(_kWanOutboxKey, rawList);
    } catch (_) {}
  }

  Future<void> queueOutboxItem(QueuedOutboxItem item) async {
    _outbox.removeWhere((x) => x.id == item.id);
    _outbox.add(item);
    await _saveOutbox();
    notifyListeners();
    debugPrint(
        '[WanWebRtc] Queued outbox item ${item.id} (${item.kind.name}) for ${item.peerName}');
  }

  Future<bool> cancelQueuedItem(String itemId) async {
    final index = _outbox.indexWhere((x) => x.id == itemId);
    if (index != -1) {
      _outbox.removeAt(index);
      await _saveOutbox();
      for (final item in _directChatItems) {
        if (item.id == itemId) {
          item.status = 'Cancelled';
          break;
        }
      }
      saveChatHistory();
      notifyListeners();
      debugPrint('[WanWebRtc] Cancelled queued item $itemId');
      return true;
    }
    return false;
  }

  bool isItemQueued(String itemId) {
    return _outbox.any((x) => x.id == itemId);
  }

  Future<void> flushQueueForPeer(String peerId) async {
    if (useUnifiedOutbox || _isFlushingOutbox || _activePeerId != peerId) {
      return;
    }
    if (_dataChannel == null ||
        _dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }

    final pending = _outbox.where((x) => x.peerId == peerId).toList();
    if (pending.isEmpty) return;

    _isFlushingOutbox = true;
    debugPrint(
        '[WanWebRtc] Flushing ${pending.length} pending items to $peerId');

    for (final q in pending) {
      if (_dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) break;

      if (q.kind == ChatKind.text && q.text != null && q.text!.isNotEmpty) {
        try {
          final msg = WanDataMessage.text(q.text!, id: q.id);
          await _dataChannel!.send(RTCDataChannelMessage(msg.toJsonString()));
          _outbox.removeWhere((x) => x.id == q.id);
          await _saveOutbox();

          for (final item in _directChatItems) {
            if (item.id == q.id) {
              item.status = 'Sent';
              await HistoryService().addItem(item);
              break;
            }
          }
          await saveChatHistory(peerId);
          notifyListeners();
          debugPrint(
              '[WanWebRtc] Successfully flushed queued text message ${q.id}');
        } catch (e) {
          debugPrint('[WanWebRtc] Error sending queued message: $e');
          break;
        }
      } else if (q.kind == ChatKind.file && q.filePath != null) {
        final f = File(q.filePath!);
        if (await f.exists()) {
          try {
            _outbox.removeWhere((x) => x.id == q.id);
            await _saveOutbox();

            for (final item in _directChatItems) {
              if (item.id == q.id) {
                item.status = 'sending';
                break;
              }
            }
            saveChatHistory();
            notifyListeners();

            await _streamFileInternal(
              f,
              fileId: q.id,
              fileName: q.fileName ?? f.uri.pathSegments.last,
            );
          } catch (e) {
            debugPrint('[WanWebRtc] Error sending queued file: $e');
            break;
          }
        } else {
          _outbox.removeWhere((x) => x.id == q.id);
          await _saveOutbox();
          for (final item in _directChatItems) {
            if (item.id == q.id) {
              item.status = 'failed';
              break;
            }
          }
          saveChatHistory();
          notifyListeners();
        }
      }
    }

    _isFlushingOutbox = false;
  }

  /// Load persistent chat history for a specific peer
  Future<void> loadChatHistory(String peerId) async {
    if (_activePeerId != peerId) return;
    _directChatItems.clear();
    try {
      _directChatItems.addAll((await HistoryService().load())
          .where((item) => item.peerId == peerId));
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('nearmitra_wan_chat_history_$peerId');
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          final parsed =
              ChatItem.fromJson(Map<String, dynamic>.from(item as Map));
          if (!_directChatItems.any((existing) => existing.id == parsed.id)) {
            _directChatItems.add(parsed);
          }
        }
      }
    } catch (e) {
      debugPrint('[WanWebRtc] Load chat history error: $e');
    }
    notifyListeners();
  }

  /// Save current chat history to persistent storage
  Future<void> saveChatHistory([String? peerId]) async {
    final targetId = peerId ?? _activePeerId;
    if (targetId == null || targetId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final items =
          _directChatItems.where((item) => item.peerId == targetId).toList();
      final trimmed =
          items.length > 500 ? items.sublist(items.length - 500) : items;
      await prefs.setString(
        'nearmitra_wan_chat_history_$targetId',
        jsonEncode(trimmed.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[WanWebRtc] Save chat history error: $e');
    }
  }

  /// Clear persistent chat history for a specific peer
  Future<void> clearChatHistory(String peerId) async {
    if (_activePeerId == peerId) _directChatItems.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('nearmitra_wan_chat_history_$peerId');
    } catch (e) {
      debugPrint('[WanWebRtc] Clear chat history error: $e');
    }
    notifyListeners();
  }

  /// Helper to append a single item to a specific peer's persistent history
  Future<void> _appendItemToPeerHistory(String peerId, ChatItem item) async {
    if (peerId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'nearmitra_wan_chat_history_$peerId';
      final raw = prefs.getString(key);
      List<ChatItem> items = [];
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        items = list
            .map((e) => ChatItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      final idx = items.indexWhere((e) => e.id == item.id);
      if (idx != -1) {
        items[idx] = item;
      } else {
        items.add(item);
      }
      final trimmed =
          items.length > 500 ? items.sublist(items.length - 500) : items;
      await prefs.setString(
          key, jsonEncode(trimmed.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('[WanWebRtc] _appendItemToPeerHistory error: $e');
    }
  }

  /// Send a direct text message via RTCDataChannel (or queue to Outbox if offline)
  Future<void> sendDirectMessage(
    String text, [
    String? overridePeerId,
    String? replyToId,
    String? replyToSender,
    String? replyToText,
    bool isForwarded = false,
    String? messageId,
  ]) async {
    final effectivePeerId =
        (overridePeerId != null && overridePeerId.isNotEmpty)
            ? overridePeerId
            : (_activePeerId ?? WanService().activeChatPeerId ?? '');
    if (effectivePeerId.isEmpty) {
      debugPrint('[WanWebRtc] sendDirectMessage: effectivePeerId is empty!');
      return;
    }

    // If WebRTC is currently negotiating/connecting, allow a brief grace period (up to 1500ms)
    if (_dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen &&
        (_state == WanConnectionState.connecting ||
            _state == WanConnectionState.signaling ||
            _state == WanConnectionState.negotiating)) {
      final watch = Stopwatch()..start();
      while (watch.elapsedMilliseconds < 1500 &&
          _dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen &&
          _state != WanConnectionState.failed &&
          _state != WanConnectionState.disconnected) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    final isChannelOpen = _dataChannel != null &&
        _dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen &&
        (overridePeerId == null ||
            overridePeerId == _activePeerId ||
            overridePeerId == _activePeer?.id);

    if (!isChannelOpen) {
      // Offline Outbox Queuing
      final itemId = messageId ?? const Uuid().v4();
      final item = ChatItem(
        id: itemId,
        peerId: effectivePeerId,
        sender: 'Me',
        mine: true,
        createdAt: DateTime.now(),
        kind: ChatKind.text,
        text: text,
        status: 'Queued',
        replyToId: replyToId,
        replyToSender: replyToSender,
        replyToText: replyToText,
        isForwarded: isForwarded,
      );
      if (effectivePeerId == _activePeerId ||
          effectivePeerId == WanService().activeChatPeerId) {
        _directChatItems.removeWhere((e) => e.id == item.id);
        _directChatItems.add(item);
        await saveChatHistory(effectivePeerId);
      } else {
        await _appendItemToPeerHistory(effectivePeerId, item);
      }
      await HistoryService().addItem(item);

      final peerName = _activePeerId == effectivePeerId
          ? (_activePeer?.name ?? 'Peer')
          : (WanService()
              .trustedDevicesList
              .firstWhere((d) => d.id == effectivePeerId,
                  orElse: () => WanDevice(
                      id: effectivePeerId,
                      name: 'Peer',
                      platform: '',
                      isOnline: false,
                      isTrusted: true))
              .name);

      await queueOutboxItem(QueuedOutboxItem(
        id: itemId,
        peerId: effectivePeerId,
        peerName: peerName,
        kind: ChatKind.text,
        text: text,
        createdAt: DateTime.now(),
      ));
      notifyListeners();
      return;
    }

    final msg = WanDataMessage.text(
      text,
      id: messageId,
      replyToId: replyToId,
      replyToSender: replyToSender,
      replyToText: replyToText,
      isForwarded: isForwarded,
    );
    await _sendConfirmed(msg, msg.id);

    final item = ChatItem(
      id: msg.id,
      peerId: effectivePeerId,
      sender: 'Me',
      mine: true,
      createdAt: DateTime.now(),
      kind: ChatKind.text,
      text: text,
      status: 'Sent',
      replyToId: replyToId,
      replyToSender: replyToSender,
      replyToText: replyToText,
      isForwarded: isForwarded,
    );
    if (effectivePeerId == _activePeerId ||
        effectivePeerId == WanService().activeChatPeerId) {
      _directChatItems.removeWhere((e) => e.id == item.id);
      _directChatItems.add(item);
      await saveChatHistory(effectivePeerId);
    } else {
      await _appendItemToPeerHistory(effectivePeerId, item);
    }
    await HistoryService().addItem(item);
    notifyListeners();
  }

  /// Toggle or send an emoji reaction for a message
  Future<void> sendReaction(String messageId, String emoji) async {
    for (final item in _directChatItems) {
      if (item.id == messageId) {
        item.reaction = emoji.isEmpty ? null : emoji;
        break;
      }
    }
    saveChatHistory();
    notifyListeners();

    if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      try {
        final controlMsg = WanDataMessage.control('reaction', {
          'messageId': messageId,
          'reaction': emoji,
        });
        await _dataChannel!
            .send(RTCDataChannelMessage(controlMsg.toJsonString()));
      } catch (_) {}
    }
  }

  /// Send real-time typing indicator to remote peer
  Future<void> sendTypingIndicator(bool isTyping) async {
    if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      try {
        final controlMsg = WanDataMessage.control('typing', {
          'isTyping': isTyping,
        });
        await _dataChannel!
            .send(RTCDataChannelMessage(controlMsg.toJsonString()));
      } catch (_) {}
    }
  }

  /// Send a file directly (or queue to Outbox if offline)
  Future<void> sendDirectFile(File file,
      [String? overridePeerId,
      bool isForwarded = false,
      String? messageId,
      bool folder = false]) async {
    final fileName = file.uri.pathSegments.last;
    final fileSize = await file.length();
    final fileId = messageId ?? const Uuid().v4();
    final effectivePeerId =
        (overridePeerId != null && overridePeerId.isNotEmpty)
            ? overridePeerId
            : (_activePeerId ?? WanService().activeChatPeerId ?? '');
    if (effectivePeerId.isEmpty) return;

    // If WebRTC is currently negotiating/connecting, allow a brief grace period (up to 1500ms)
    if (_dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen &&
        (_state == WanConnectionState.connecting ||
            _state == WanConnectionState.signaling ||
            _state == WanConnectionState.negotiating)) {
      final watch = Stopwatch()..start();
      while (watch.elapsedMilliseconds < 1500 &&
          _dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen &&
          _state != WanConnectionState.failed &&
          _state != WanConnectionState.disconnected) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    final isChannelOpen = _dataChannel != null &&
        _dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen &&
        (overridePeerId == null ||
            overridePeerId == _activePeerId ||
            overridePeerId == _activePeer?.id);

    if (!isChannelOpen) {
      // Offline Outbox Queuing for File
      final fileChatItem = ChatItem(
        id: fileId,
        peerId: effectivePeerId,
        sender: 'Me',
        mine: true,
        createdAt: DateTime.now(),
        kind: ChatKind.file,
        fileName: fileName,
        filePath: file.path,
        fileSize: fileSize,
        status: 'Queued',
        isForwarded: isForwarded,
      );
      if (effectivePeerId == _activePeerId ||
          effectivePeerId == WanService().activeChatPeerId) {
        _directChatItems.removeWhere((e) => e.id == fileChatItem.id);
        _directChatItems.add(fileChatItem);
        await saveChatHistory(effectivePeerId);
      } else {
        await _appendItemToPeerHistory(effectivePeerId, fileChatItem);
      }
      await HistoryService().addItem(fileChatItem);

      final peerName = _activePeerId == effectivePeerId
          ? (_activePeer?.name ?? 'Peer')
          : (WanService()
              .trustedDevicesList
              .firstWhere((d) => d.id == effectivePeerId,
                  orElse: () => WanDevice(
                      id: effectivePeerId,
                      name: 'Peer',
                      platform: '',
                      isOnline: false,
                      isTrusted: true))
              .name);

      await queueOutboxItem(QueuedOutboxItem(
        id: fileId,
        peerId: effectivePeerId,
        peerName: peerName,
        kind: ChatKind.file,
        fileName: fileName,
        filePath: file.path,
        fileSize: fileSize,
        createdAt: DateTime.now(),
      ));
      notifyListeners();
      return;
    }

    final fileChatItem = ChatItem(
      id: fileId,
      peerId: effectivePeerId,
      sender: 'Me',
      mine: true,
      createdAt: DateTime.now(),
      kind: ChatKind.file,
      fileName: fileName,
      filePath: file.path,
      fileSize: fileSize,
      status: 'sending',
      isForwarded: isForwarded,
    );
    if (effectivePeerId == _activePeerId ||
        effectivePeerId == WanService().activeChatPeerId) {
      _directChatItems.removeWhere((e) => e.id == fileChatItem.id);
      _directChatItems.add(fileChatItem);
      await saveChatHistory(effectivePeerId);
    } else {
      await _appendItemToPeerHistory(effectivePeerId, fileChatItem);
    }
    await HistoryService().addItem(fileChatItem);
    notifyListeners();

    await _streamFileInternal(file,
        fileId: fileId,
        fileName: fileName,
        existingItem: fileChatItem,
        folder: folder);
  }

  Future<void> _streamFileInternal(File file,
      {required String fileId,
      required String fileName,
      ChatItem? existingItem,
      bool folder = false}) async {
    if (_dataChannel == null ||
        _dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }

    final fileSize = await file.length();
    const chunkSize = 64 * 1024; // 64 KB high-throughput chunk size
    final totalChunks = (fileSize / chunkSize).ceil();

    // 1. Send File Meta
    final metaMsg = WanDataMessage.fileMeta(
      fileId: fileId,
      fileName: fileName,
      fileSize: fileSize,
      folder: folder,
      mimeType: 'application/octet-stream',
      chunkSize: chunkSize,
      totalChunks: totalChunks,
    );
    await _dataChannel!.send(RTCDataChannelMessage(metaMsg.toJsonString()));

    // 2. Stream chunks incrementally from disk with backpressure monitoring
    final progress = WanFileTransferProgress(
      fileId: fileId,
      fileName: fileName,
      totalBytes: fileSize,
      bytesTransferred: 0,
      speedMBps: 0.0,
      etaSeconds: 0,
      isSender: true,
      filePath: file.path,
    );
    _activeTransfers[fileId] = progress;
    notifyListeners();

    final reader = file.openRead();
    int bytesSent = 0;
    final startTime = DateTime.now();
    DateTime lastNotifyTime = DateTime.now();

    await for (final chunk in reader) {
      if (_state != WanConnectionState.connected ||
          _dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) {
        break;
      }

      // Check for file cancellation (by sender or remote receiver)
      if (_activeTransfers[fileId]?.isCancelled ?? false) {
        break;
      }

      // Backpressure check: if bufferedAmount is high, pause briefly to drain
      while ((_dataChannel?.bufferedAmount ?? 0) > 1024 * 1024) {
        if (!isConnected || (_activeTransfers[fileId]?.isCancelled ?? false)) {
          throw StateError('File transfer interrupted');
        }
        await Future.delayed(const Duration(milliseconds: 2));
      }

      await _dataChannel!
          .send(RTCDataChannelMessage.fromBinary(Uint8List.fromList(chunk)));
      bytesSent += chunk.length;

      final now = DateTime.now();
      if (now.difference(lastNotifyTime).inMilliseconds >= 250 ||
          bytesSent == fileSize) {
        lastNotifyTime = now;
        final elapsed = now.difference(startTime).inMilliseconds / 1000.0;
        final speed = elapsed > 0 ? (bytesSent / (1024 * 1024)) / elapsed : 0.0;
        final remainingBytes = fileSize - bytesSent;
        final eta =
            speed > 0 ? (remainingBytes / (speed * 1024 * 1024)).ceil() : 0;

        _activeTransfers[fileId] = WanFileTransferProgress(
          fileId: fileId,
          fileName: fileName,
          totalBytes: fileSize,
          bytesTransferred: bytesSent,
          speedMBps: speed,
          etaSeconds: eta,
          isSender: true,
          filePath: file.path,
        );
        notifyListeners();
      }
    }

    final targetItem =
        existingItem ?? _directChatItems.firstWhere((x) => x.id == fileId);

    if (!(_activeTransfers[fileId]?.isCancelled ?? false)) {
      if (bytesSent != fileSize || !isConnected) {
        targetItem.status = 'Queued';
        await HistoryService().addItem(targetItem);
        throw StateError('File transfer interrupted');
      }
      // 3. Send File End
      final endMsg = WanDataMessage.fileEnd(fileId: fileId);
      await _sendConfirmed(endMsg, fileId);

      _activeTransfers[fileId] = WanFileTransferProgress(
        fileId: fileId,
        fileName: fileName,
        totalBytes: fileSize,
        bytesTransferred: fileSize,
        speedMBps: 0.0,
        etaSeconds: 0,
        isSender: true,
        isCompleted: true,
        filePath: file.path,
      );
      targetItem.status = 'sent';
      saveChatHistory();
      HistoryService().addItem(targetItem);
      notifyListeners();
    } else {
      targetItem.status = 'cancelled';
      saveChatHistory();
      notifyListeners();
    }
  }

  /// Cancel an ongoing file transfer (sender or receiver)
  Future<void> cancelFileTransfer(String fileId) async {
    if (_activeTransfers.containsKey(fileId)) {
      final t = _activeTransfers[fileId]!;
      _activeTransfers[fileId] = WanFileTransferProgress(
        fileId: fileId,
        fileName: t.fileName,
        totalBytes: t.totalBytes,
        bytesTransferred: t.bytesTransferred,
        speedMBps: 0.0,
        etaSeconds: 0,
        isSender: t.isSender,
        isCancelled: true,
        filePath: t.filePath,
      );
      for (final item in _directChatItems) {
        if (item.id == fileId) {
          item.status = 'cancelled';
          break;
        }
      }
      saveChatHistory();
      notifyListeners();
    }

    if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      try {
        final cancelMsg =
            WanDataMessage.fileCancel(fileId: fileId, reason: 'User cancelled');
        await _dataChannel!
            .send(RTCDataChannelMessage(cancelMsg.toJsonString()));
      } catch (_) {}
    }

    if (_currentReceivingFileId == fileId) {
      _closeCurrentFileSink(isComplete: false);
    }
  }

  Future<void> _sendConfirmed(WanDataMessage message, String id) async {
    if (_handshakeReceived != null) {
      await _handshakeReceived!.future
          .timeout(const Duration(seconds: 2), onTimeout: () {});
    }
    final requiresAck = _remoteDeliveryAck;
    final confirmation = Completer<bool>();
    if (requiresAck) _deliveryWaiters[id] = confirmation;
    try {
      await _dataChannel!.send(RTCDataChannelMessage(message.toJsonString()));
      if (requiresAck &&
          !await confirmation.future.timeout(const Duration(seconds: 60))) {
        throw StateError('Receiver could not save the message or file');
      }
    } finally {
      _deliveryWaiters.remove(id);
    }
  }

  Future<void> _sendDeliveryAck(String id, bool delivered) async {
    await _dataChannel?.send(RTCDataChannelMessage(jsonEncode({
      'type': 'delivery_ack',
      'id': id,
      'status': delivered ? 'delivered' : 'failed',
    })));
  }

  Future<void> _handleTextMessage(String rawJson) async {
    try {
      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      final type = map['type'] as String?;
      if (type == 'delivery_ack') {
        final pending = _deliveryWaiters[map['id']];
        if (pending != null && !pending.isCompleted) {
          pending.complete(map['status'] == 'delivered');
        }
        return;
      }
      if (type == 'handshake_syn') {
        _remoteDeliveryAck = map['deliveryAck'] == true;
        if (_handshakeReceived != null && !_handshakeReceived!.isCompleted) {
          _handshakeReceived!.complete();
        }
        _sessionTimeoutTimer?.cancel();
        _setState(WanConnectionState.connected);
        try {
          _dataChannel?.send(RTCDataChannelMessage(
            jsonEncode({
              'type': 'handshake_ack',
              'senderId': _wanService.deviceId,
              'deliveryAck': true
            }),
          ));
        } catch (_) {}
        return;
      } else if (type == 'handshake_ack') {
        _remoteDeliveryAck = map['deliveryAck'] == true;
        if (_handshakeReceived != null && !_handshakeReceived!.isCompleted) {
          _handshakeReceived!.complete();
        }
        _sessionTimeoutTimer?.cancel();
        _setState(WanConnectionState.connected);
        return;
      }
    } catch (_) {}

    final msg = WanDataMessage.fromJsonString(rawJson);
    switch (msg.type) {
      case WanDataMessageType.text:
        final text = msg.payload?['text'] as String? ?? '';
        final replyToId = msg.payload?['replyToId'] as String?;
        final replyToSender = msg.payload?['replyToSender'] as String?;
        final replyToText = msg.payload?['replyToText'] as String?;
        final isForwarded = msg.payload?['isForwarded'] == true;

        if (_directChatItems.any((item) => item.id == msg.id)) {
          await _sendDeliveryAck(msg.id, true);
          return;
        }
        final item = ChatItem(
          id: msg.id,
          peerId: _activePeerId ?? '',
          sender: _activePeer?.name ?? 'Peer',
          mine: false,
          createdAt: DateTime.now(),
          kind: ChatKind.text,
          text: text,
          status: 'received',
          replyToId: replyToId,
          replyToSender: replyToSender,
          replyToText: replyToText,
          isForwarded: isForwarded,
        );
        _directChatItems.add(item);
        saveChatHistory();
        await HistoryService().addItem(item);
        await _sendDeliveryAck(msg.id, true);

        final isChatOpen = _wanService.isAppInForeground &&
            _activePeerId != null &&
            _wanService.activeChatPeerId == _activePeerId;

        if (!isChatOpen && _activePeerId != null) {
          _wanService.incrementUnreadCount(_activePeerId!);
          NotificationService().showIncomingMessageNotification(
            peerId: 'wan:$_activePeerId',
            senderName: _activePeer?.name ?? 'Internet Peer',
            message: text,
          );
        }

        notifyListeners();
        break;

      case WanDataMessageType.fileMeta:
        if (_currentReceivingFileId != null) {
          await _closeCurrentFileSink(isComplete: false);
        }
        _currentSavedFilePath = null;
        _currentReceivingFolder = msg.payload?['folder'] == true;
        _currentReceivingFileId = msg.payload?['transferId'] as String?;
        _currentReceivingFileName =
            msg.payload?['fileName'] as String? ?? 'received_file';
        _currentReceivingFileSize = msg.payload?['fileSize'] as int? ?? 0;
        _currentReceivingBytes = 0;
        _isCurrentTransferCancelled = false;
        _transferStartTime = DateTime.now();

        await _prepareFileSink(_currentReceivingFileName!);
        break;

      case WanDataMessageType.fileEnd:
        final receivedFileId = _currentReceivingFileId;
        await _closeCurrentFileSink(
            isComplete: _currentFileSink != null &&
                _currentReceivingBytes == _currentReceivingFileSize);
        if (receivedFileId != null) {
          await _sendDeliveryAck(receivedFileId,
              _activeTransfers[receivedFileId]?.isCompleted == true);
        }
        break;

      case WanDataMessageType.fileCancel:
        final cancelId = msg.payload?['transferId'] as String? ??
            msg.payload?['fileId'] as String? ??
            _currentReceivingFileId;
        if (cancelId != null && _activeTransfers.containsKey(cancelId)) {
          final t = _activeTransfers[cancelId]!;
          _activeTransfers[cancelId] = WanFileTransferProgress(
            fileId: cancelId,
            fileName: t.fileName,
            totalBytes: t.totalBytes,
            bytesTransferred: t.bytesTransferred,
            speedMBps: 0.0,
            etaSeconds: 0,
            isSender: t.isSender,
            isCancelled: true,
            filePath: t.filePath,
          );
          for (final item in _directChatItems) {
            if (item.id == cancelId) {
              item.status = 'cancelled';
              break;
            }
          }
          saveChatHistory();
          notifyListeners();
        }
        _closeCurrentFileSink(isComplete: false);
        break;

      case WanDataMessageType.ping:
        if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
          try {
            _dataChannel!.send(
                RTCDataChannelMessage(WanDataMessage.pong().toJsonString()));
          } catch (_) {}
        }
        break;

      case WanDataMessageType.control:
        final action = msg.payload?['action'] as String?;
        if (action == 'reaction') {
          final targetId = msg.payload?['messageId'] as String?;
          final emoji = msg.payload?['reaction'] as String?;
          if (targetId != null) {
            for (final item in _directChatItems) {
              if (item.id == targetId) {
                item.reaction = item.reaction == emoji ? null : emoji;
                await HistoryService().addItem(item);
                saveChatHistory();
                notifyListeners();
                break;
              }
            }
          }
        } else if (action == 'typing') {
          final isTyping = msg.payload?['isTyping'] == true;
          _peerIsTyping = isTyping;
          _peerTypingTimer?.cancel();
          if (isTyping) {
            _peerTypingTimer = Timer(const Duration(seconds: 4), () {
              _peerIsTyping = false;
              notifyListeners();
            });
          }
          notifyListeners();
        } else if (action == 'disconnect') {
          disconnect(notifyRemote: false);
        }
        break;

      default:
        break;
    }
  }

  DateTime _lastReceiverNotifyTime = DateTime.now();

  Future<void> _prepareFileSink(String fileName) async {
    try {
      fileName = fileName.replaceAll('\\', '/').split('/').last;
      if (fileName.isEmpty || fileName == '.' || fileName == '..') {
        fileName = 'received_file';
      }
      final dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${dir.path}/NearMitra/Downloads');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      // Handle name collision
      var savePath = '${downloadDir.path}/$fileName';
      if (await File(savePath).exists()) {
        final extIndex = fileName.lastIndexOf('.');
        final nameWithoutExt =
            extIndex != -1 ? fileName.substring(0, extIndex) : fileName;
        final ext = extIndex != -1 ? fileName.substring(extIndex) : '';
        savePath =
            '${downloadDir.path}/${nameWithoutExt}_${DateTime.now().millisecondsSinceEpoch}$ext';
      }

      _currentSavedFilePath = savePath;
      final file = File(savePath);
      _currentFileSink = file.openWrite();
      _lastReceiverNotifyTime = DateTime.now();

      if (_currentReceivingFileId != null) {
        _activeTransfers[_currentReceivingFileId!] = WanFileTransferProgress(
          fileId: _currentReceivingFileId!,
          fileName: fileName,
          totalBytes: _currentReceivingFileSize,
          bytesTransferred: 0,
          speedMBps: 0.0,
          etaSeconds: 0,
          isSender: false,
          filePath: savePath,
        );

        final fileItem = ChatItem(
          id: _currentReceivingFileId!,
          peerId: _activePeerId ?? '',
          sender: _activePeer?.name ?? 'Peer',
          mine: false,
          createdAt: DateTime.now(),
          kind: ChatKind.file,
          fileName: fileName,
          filePath: savePath,
          fileSize: _currentReceivingFileSize,
          status: 'downloading',
        );
        _directChatItems.add(fileItem);
        saveChatHistory();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[WanWebRtc] Prepare sink error: $e');
    }
  }

  void _handleBinaryMessage(Uint8List binary) {
    if (_currentFileSink != null && !_isCurrentTransferCancelled) {
      _currentFileSink!.add(binary);
      _currentReceivingBytes += binary.length;

      final now = DateTime.now();
      if (now.difference(_lastReceiverNotifyTime).inMilliseconds >= 250 ||
          _currentReceivingBytes == _currentReceivingFileSize) {
        _lastReceiverNotifyTime = now;
        final elapsed = _transferStartTime != null
            ? now.difference(_transferStartTime!).inMilliseconds / 1000.0
            : 1.0;
        final speed = elapsed > 0
            ? (_currentReceivingBytes / (1024 * 1024)) / elapsed
            : 0.0;
        final remaining = _currentReceivingFileSize - _currentReceivingBytes;
        final eta = speed > 0 ? (remaining / (speed * 1024 * 1024)).ceil() : 0;

        if (_currentReceivingFileId != null) {
          _activeTransfers[_currentReceivingFileId!] = WanFileTransferProgress(
            fileId: _currentReceivingFileId!,
            fileName: _currentReceivingFileName ?? 'File',
            totalBytes: _currentReceivingFileSize,
            bytesTransferred: _currentReceivingBytes,
            speedMBps: speed,
            etaSeconds: eta,
            isSender: false,
            filePath: _currentSavedFilePath,
          );
          notifyListeners();
        }
      }
    }
  }

  Future<void> _closeCurrentFileSink({required bool isComplete}) async {
    if (_currentFileSink != null) {
      try {
        await _currentFileSink!.flush();
        await _currentFileSink!.close();
      } catch (error) {
        isComplete = false;
        debugPrint('[WanWebRtc] File write failed: $error');
      }
      _currentFileSink = null;
    }

    if (isComplete &&
        _currentReceivingFolder &&
        _currentSavedFilePath != null) {
      final archive = File(_currentSavedFilePath!);
      final name = (_currentReceivingFileName ?? 'Folder')
          .replaceFirst(RegExp(r'\.zip$'), '');
      final destination =
          '${archive.parent.path}/${name}_${DateTime.now().millisecondsSinceEpoch}';
      try {
        await Directory(destination).create(recursive: true);
        await extractFileToDisk(archive.path, destination);
        await archive.delete();
        _currentSavedFilePath = destination;
        final index = _directChatItems
            .indexWhere((item) => item.id == _currentReceivingFileId);
        if (index >= 0) {
          _directChatItems[index] = ChatItem.fromJson({
            ..._directChatItems[index].toJson(),
            'filePath': destination,
            'kind': 'folder',
          });
        }
      } catch (error) {
        isComplete = false;
        debugPrint('[WanWebRtc] Folder extraction failed: $error');
      }
    }

    if (!isComplete && _currentSavedFilePath != null) {
      try {
        final f = File(_currentSavedFilePath!);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }

    if (_currentReceivingFileId != null) {
      _activeTransfers[_currentReceivingFileId!] = WanFileTransferProgress(
        fileId: _currentReceivingFileId!,
        fileName: _currentReceivingFileName ?? 'File',
        totalBytes: _currentReceivingFileSize,
        bytesTransferred: _currentReceivingBytes,
        speedMBps: 0.0,
        etaSeconds: 0,
        isSender: false,
        isCompleted: isComplete,
        isCancelled: !isComplete,
        filePath: isComplete ? _currentSavedFilePath : null,
      );

      ChatItem? receivedItem;
      for (final item in _directChatItems) {
        if (item.id == _currentReceivingFileId) {
          item.status = isComplete ? 'received' : 'failed';
          receivedItem = item;
          break;
        }
      }

      saveChatHistory();

      if (isComplete) {
        final itemToSave = receivedItem ??
            ChatItem(
              id: _currentReceivingFileId ?? const Uuid().v4(),
              peerId: _activePeerId ?? '',
              sender: _activePeer?.name ?? 'WAN Peer',
              mine: false,
              createdAt: DateTime.now(),
              kind: ChatKind.file,
              fileName: _currentReceivingFileName,
              filePath: _currentSavedFilePath,
              fileSize: _currentReceivingFileSize,
              status: 'received',
            );
        await HistoryService().addItem(itemToSave);

        final isChatOpen = _wanService.isAppInForeground &&
            _activePeerId != null &&
            _wanService.activeChatPeerId == _activePeerId;

        if (!isChatOpen && _activePeerId != null) {
          _wanService.incrementUnreadCount(_activePeerId!);
          NotificationService().showIncomingFileNotification(
            peerId: 'wan:$_activePeerId',
            senderName: _activePeer?.name ?? 'Internet Peer',
            fileName: _currentReceivingFileName ?? 'File',
            fileSizeText: _formatFileSize(_currentReceivingFileSize),
          );
        }
      }

      notifyListeners();
    }

    _currentReceivingFileId = null;
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Disconnect active WebRTC session and free all resources
  Future<void> disconnect({bool notifyRemote = true}) async {
    _isManuallyDisconnected = true;
    for (final pending in _deliveryWaiters.values) {
      if (!pending.isCompleted) pending.complete(false);
    }
    _deliveryWaiters.clear();
    _reconnectTimer?.cancel();
    _sessionTimeoutTimer?.cancel();
    _stopHeartbeat();

    if (notifyRemote &&
        _dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      try {
        final msg = WanDataMessage.control('disconnect');
        await _dataChannel!.send(RTCDataChannelMessage(msg.toJsonString()));
      } catch (_) {}
    }

    await _answerSub?.cancel();
    _answerSub = null;
    await _statusSub?.cancel();
    _statusSub = null;
    await _candidatesSub?.cancel();
    _candidatesSub = null;

    if (_activeSessionId != null) {
      await _wanService.deleteSignalingSession(_activeSessionId!);
      _activeSessionId = null;
    }

    await _closeCurrentFileSink(isComplete: false);

    await _dataChannel?.close();
    _dataChannel = null;

    await _peerConnection?.close();
    _peerConnection = null;

    _activePeerId = null;
    _activePeer = null;
    _isCaller = false;
    _processedCandidates.clear();

    _setState(WanConnectionState.disconnected);
  }
}
