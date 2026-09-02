import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../models/peer.dart';

class AcceptedCallData {
  final Peer peer;
  final bool isVideo;

  const AcceptedCallData({
    required this.peer,
    required this.isVideo,
  });
}

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  bool _initialized = false;
  bool _isCallActive = false;
  AcceptedCallData? _pendingAcceptedCall;
  Function(Peer peer, bool isVideoCall, bool isIncoming)? _onCallAccepted;
  Function(Peer peer)? _onCallDeclined;
  final Map<String, Peer> _cachedPeers = {};

  AcceptedCallData? get pendingAcceptedCall => _pendingAcceptedCall;
  bool get hasPendingAcceptedCall => _pendingAcceptedCall != null;
  void resetCallActiveState() => _isCallActive = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // Fix 4: Clear any stale CallKit sessions from previous app runs
      await FlutterCallkitIncoming.endAllCalls();
      debugPrint('[CallService] Cleared stale CallKit sessions on startup');

      FlutterCallkitIncoming.onEvent.listen((event) {
        if (event == null) return;
        final ev = event.event;
        debugPrint('[CallService] Received CallKit event: $ev');

        if (ev == Event.actionCallAccept) {
          final body = event.body as Map<dynamic, dynamic>?;
          if (body != null) {
            _isCallActive = true;
            _handleAcceptedCallEvent(body);
          }
        } else if (ev == Event.actionCallDecline) {
          if (_isCallActive) {
            debugPrint('[CallService] Ignoring CallKit decline event during active call');
            return;
          }
          final body = event.body as Map<dynamic, dynamic>?;
          if (body != null) {
            _handleDeclinedCallEvent(body);
          }
          _pendingAcceptedCall = null;
          FlutterCallkitIncoming.endAllCalls();
        } else if (ev == Event.actionCallTimeout || ev == Event.actionCallEnded) {
          _pendingAcceptedCall = null;
        }
      });

      // Check active calls on startup in case app was launched via Accept action
      await _checkActiveCalls();
    } catch (e) {
      debugPrint('CallKit init error: $e');
    }
  }

  void _handleAcceptedCallEvent(Map<dynamic, dynamic> body) {
    Map<dynamic, dynamic>? extra;
    if (body['extra'] is Map) {
      extra = body['extra'] as Map<dynamic, dynamic>;
    }

    final peerId = extra?['peerId']?.toString() ??
        body['peerId']?.toString() ??
        body['id']?.toString() ??
        '';

    final cached = _cachedPeers[peerId] ??
        _cachedPeers[body['id']?.toString() ?? ''] ??
        _cachedPeers.values.lastOrNull;

    final peerName = extra?['peerName']?.toString() ??
        body['peerName']?.toString() ??
        body['nameCaller']?.toString() ??
        cached?.name ??
        'Peer Device';

    var peerIp = extra?['peerIp']?.toString() ??
        body['peerIp']?.toString() ??
        cached?.ip ??
        '';

    if (peerIp.isEmpty && body['handle'] != null) {
      final handle = body['handle'].toString();
      if (handle.contains('•')) {
        peerIp = handle.split('•').last.trim();
      }
    }

    final isVideo = extra?['isVideo'] == true ||
        body['type'] == 1 ||
        body['isVideo'] == true;

    final peer = Peer(
      id: peerId.isNotEmpty ? peerId : (cached?.id ?? 'peer_incoming'),
      name: peerName,
      ip: peerIp,
      lastSeen: DateTime.now(),
    );

    _pendingAcceptedCall = AcceptedCallData(peer: peer, isVideo: isVideo);

    if (_onCallAccepted != null) {
      final callData = _pendingAcceptedCall!;
      _pendingAcceptedCall = null;
      _onCallAccepted?.call(callData.peer, callData.isVideo, true);
    }
  }

  void _handleDeclinedCallEvent(Map<dynamic, dynamic> body) {
    Map<dynamic, dynamic>? extra;
    if (body['extra'] is Map) {
      extra = body['extra'] as Map<dynamic, dynamic>;
    }

    final peerId = extra?['peerId']?.toString() ??
        body['peerId']?.toString() ??
        body['id']?.toString() ??
        '';

    final cached = _cachedPeers[peerId] ??
        _cachedPeers[body['id']?.toString() ?? ''] ??
        _cachedPeers.values.lastOrNull;

    final peerName = extra?['peerName']?.toString() ??
        body['peerName']?.toString() ??
        body['nameCaller']?.toString() ??
        cached?.name ??
        'Peer Device';

    var peerIp = extra?['peerIp']?.toString() ??
        body['peerIp']?.toString() ??
        cached?.ip ??
        '';

    if (peerIp.isEmpty && body['handle'] != null) {
      final handle = body['handle'].toString();
      if (handle.contains('•')) {
        peerIp = handle.split('•').last.trim();
      }
    }

    final peer = Peer(
      id: peerId.isNotEmpty ? peerId : (cached?.id ?? 'peer_incoming'),
      name: peerName,
      ip: peerIp,
      lastSeen: DateTime.now(),
    );

    _onCallDeclined?.call(peer);
    _sendDeclinedSignalDirect(peer);
  }

  Future<void> _sendDeclinedSignalDirect(Peer peer) async {
    if (peer.ip.isEmpty) return;
    try {
      final socket = await Socket.connect(peer.ip, 43889,
          timeout: const Duration(seconds: 2));
      final payload = jsonEncode({
        'type': 'call_declined',
        'sender': 'Peer Device',
        'sender_id': 'peer_incoming',
      });
      socket.write('$payload\n');
      await socket.flush();
      socket.destroy();
    } catch (_) {}
  }

  Future<void> _checkActiveCalls() async {
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      if (calls is List && calls.isNotEmpty) {
        for (final item in calls) {
          if (item is Map<dynamic, dynamic>) {
            final isAccepted = item['isAccepted'] == true;
            if (isAccepted) {
              _handleAcceptedCallEvent(item);
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[CallService] Error checking active calls: $e');
    }
  }

  void registerCallAcceptedCallback(
      Function(Peer peer, bool isVideoCall, bool isIncoming) callback) {
    _onCallAccepted = callback;

    if (_pendingAcceptedCall != null) {
      final callData = _pendingAcceptedCall!;
      _pendingAcceptedCall = null;
      Future.microtask(() {
        callback(callData.peer, callData.isVideo, true);
      });
    } else {
      _checkActiveCalls().then((_) {
        if (_pendingAcceptedCall != null) {
          final callData = _pendingAcceptedCall!;
          _pendingAcceptedCall = null;
          callback(callData.peer, callData.isVideo, true);
        }
      });
    }
  }

  void registerCallDeclinedCallback(Function(Peer peer) callback) {
    _onCallDeclined = callback;
  }

  Future<void> showIncomingCall({
    required String peerId,
    required String peerName,
    required String peerIp,
    required bool isVideoCall,
  }) async {
    final peerObj = Peer(
      id: peerId,
      name: peerName,
      ip: peerIp,
      lastSeen: DateTime.now(),
    );
    _cachedPeers[peerId] = peerObj;
    _cachedPeers[peerIp] = peerObj;

    final uuid = DateTime.now().millisecondsSinceEpoch.toString();
    _cachedPeers[uuid] = peerObj;

    final params = CallKitParams(
      id: uuid,
      nameCaller: peerName,
      appName: 'NearMitra',
      avatar: '',
      handle: 'P2P Direct • $peerIp',
      type: isVideoCall ? 1 : 0,
      duration: 35000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      extra: <String, dynamic>{
        'peerId': peerId,
        'peerName': peerName,
        'peerIp': peerIp,
        'isVideo': isVideoCall,
      },
      android: AndroidParams(
        // Fix 2: Use default CallKit notification (isCustomNotification: false)
        // Custom notification style is unreliable on many Android ROMs
        isCustomNotification: false,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0F172A',
        actionColor: '#10B981',
        textColor: '#FFFFFF',
      ),
    );

    try {
      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (e) {
      debugPrint('Error showing incoming call: $e');
    }
  }

  Future<void> endAllCalls() async {
    try {
      _pendingAcceptedCall = null;
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
  }
}
