import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../models/peer.dart';
import 'package:uuid/uuid.dart';

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

  final incomingCall=ValueNotifier<AcceptedCallData?>(null);
  bool isAppInForeground=false;
  Timer? _incomingTimeout;

  bool _initialized = false;

  void acceptPendingIncomingCall(){
    final call=incomingCall.value;if(call==null || _isCallActive)return;
    _incomingTimeout?.cancel();_isCallActive=true;incomingCall.value=null;
    _pendingAcceptedCall=call;
    final callback=_onCallAccepted;
    if(callback!=null){_pendingAcceptedCall=null;callback(call.peer,call.isVideo,true);}
  }
  void declinePendingIncomingCall(){
    final call=incomingCall.value;if(call==null)return;
    _incomingTimeout?.cancel();incomingCall.value=null;
    if(_onCallDeclined!=null){_onCallDeclined!(call.peer);}else{unawaited(_sendDeclinedSignalDirect(call.peer));}
    unawaited(FlutterCallkitIncoming.endAllCalls().catchError((_){ }));
  }
  void clearPendingIncomingCall(){_incomingTimeout?.cancel();incomingCall.value=null;}

  bool _isCallActive = false;
  AcceptedCallData? _pendingAcceptedCall;
  Function(Peer peer, bool isVideoCall, bool isIncoming)? _onCallAccepted;
  Function(Peer peer)? _onCallDeclined;
  final Map<String, Peer> _cachedPeers = {};

  AcceptedCallData? get pendingAcceptedCall => _pendingAcceptedCall;
  bool get hasPendingAcceptedCall => _pendingAcceptedCall != null;
  bool get isCallActive => _isCallActive;

  void setCallActive(bool active) {
    _isCallActive = active;
    if(active)clearPendingIncomingCall();
    if (!active) {
      _pendingAcceptedCall = null;
    }
  }

  void resetCallActiveState() => setCallActive(false);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      FlutterCallkitIncoming.onEvent.listen((event) {
        if (event == null) return;
        final ev = event.event;
        debugPrint('[CallService] Received CallKit event: $ev (isCallActive: $_isCallActive)');

        if (ev == Event.actionCallAccept) {
          final body = event.body as Map<dynamic, dynamic>?;
          if (body != null) {
            if(_isCallActive)return;
            _isCallActive = true;
            clearPendingIncomingCall();
            _handleAcceptedCallEvent(body);
          }
        } else if (ev == Event.actionCallDecline) {
          if (_isCallActive) {
            debugPrint('[CallService] Ignoring CallKit decline event because a call is currently active');
            return;
          }
          final body = event.body as Map<dynamic, dynamic>?;
          if (body != null) {
            _handleDeclinedCallEvent(body);
          }
          clearPendingIncomingCall();
          _pendingAcceptedCall = null;
        } else if (ev == Event.actionCallTimeout || ev == Event.actionCallEnded) {
          if (!_isCallActive) {
            clearPendingIncomingCall();
            _pendingAcceptedCall = null;
          }
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
    } else if (body['extra'] is String) {
      try {
        final decoded = jsonDecode(body['extra'] as String);
        if (decoded is Map) {
          extra = decoded;
        }
      } catch (_) {}
    }

    final peerId = extra?['peerId']?.toString() ??
        body['peerId']?.toString() ??
        body['id']?.toString() ??
        '';

    final cached = _cachedPeers[peerId] ??
        _cachedPeers[body['id']?.toString() ?? ''] ??
        (extra?['peerIp'] != null ? _cachedPeers[extra!['peerIp'].toString()] : null) ??
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
        extra?['is_video'] == true ||
        body['type'] == 1 ||
        body['isVideo'] == true;

    final peer = Peer(
      id: peerId.isNotEmpty ? peerId : (cached?.id ?? (peerIp.isNotEmpty ? peerIp : 'peer_incoming')),
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
    } else if (body['extra'] is String) {
      try {
        final decoded = jsonDecode(body['extra'] as String);
        if (decoded is Map) {
          extra = decoded;
        }
      } catch (_) {}
    }

    final peerId = extra?['peerId']?.toString() ??
        body['peerId']?.toString() ??
        body['id']?.toString() ??
        '';

    final cached = _cachedPeers[peerId] ??
        _cachedPeers[body['id']?.toString() ?? ''] ??
        (extra?['peerIp'] != null ? _cachedPeers[extra!['peerIp'].toString()] : null) ??
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

    if(_onCallDeclined!=null){_onCallDeclined!(peer);}else{unawaited(_sendDeclinedSignalDirect(peer));}
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
      debugPrint('[CallService] Active calls on startup: $calls');
      if (calls is List && calls.isNotEmpty && !_isCallActive) {
        for (final item in calls) {
          if (item is Map<dynamic, dynamic> && item['isAccepted']==true) {
            _handleAcceptedCallEvent(item);
            break;
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

  Future<bool> showIncomingCall({
    required String peerId,
    required String peerName,
    required String peerIp,
    required bool isVideoCall,
  }) async {
    if(_isCallActive)return false;
    if(incomingCall.value!=null)return incomingCall.value!.peer.ip==peerIp;
    final peerObj = Peer(
      id: peerId,
      name: peerName,
      ip: peerIp,
      lastSeen: DateTime.now(),
    );
    _cachedPeers[peerId] = peerObj;
    _cachedPeers[peerIp] = peerObj;

    final uuid = const Uuid().v4();
    final pending=AcceptedCallData(peer:peerObj,isVideo:isVideoCall);
    incomingCall.value=pending;
    _incomingTimeout?.cancel();
    _incomingTimeout=Timer(const Duration(seconds:35),(){if(incomingCall.value==pending){declinePendingIncomingCall();}});
    if(isAppInForeground)return true;
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
    return incomingCall.value==pending || _isCallActive;
  }

  Future<void> endAllCalls() async {
    try {
      clearPendingIncomingCall();
      _pendingAcceptedCall = null;
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
  }
}
