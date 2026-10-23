import 'dart:async';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/wan_models.dart';
import 'firebase_presence_service.dart';
import 'internet_device_identity_service.dart';

class WanService extends ChangeNotifier {
  static final WanService _instance = WanService._internal();
  factory WanService() => _instance;
  static WanService get instance => _instance;
  WanService._internal();

  final InternetDeviceIdentityService _identityService = InternetDeviceIdentityService();
  final FirebasePresenceService _presenceService = FirebasePresenceService();

  bool _isInitialized = false;
  bool _isInternetModeEnabled = false;
  WanDiscoveryMode _discoveryMode = WanDiscoveryMode.publicRadar;
  bool isAppInForeground = true;

  final Map<String, WanDevice> _trustedDevices = {};
  final Map<String, WanDevice> _publicDiscoveredDevices = {};
  final Map<String, StreamSubscription> _presenceSubs = {};
  final Map<String, int> _unreadCounts = {};

  String? activeChatPeerId;

  StreamSubscription<DatabaseEvent>? _trustedDevicesSub;
  StreamSubscription<DatabaseEvent>? _incomingPairRequestsSub;
  StreamSubscription<DatabaseEvent>? _incomingSessionsSub;
  StreamSubscription<DatabaseEvent>? _publicPresenceSub;

  WanPairCode? _activePairCode;
  Timer? _pairCodeTimer;
  Timer? _cleanupTimer;
  Timer? _presenceExpiryTimer;
  StreamSubscription<DatabaseEvent>? _serverTimeOffsetSub;
  int _serverTimeOffsetMs = 0;
  DateTime get _presenceNow => DateTime.now().add(Duration(milliseconds: _serverTimeOffsetMs));

  void _expirePeerPresence() {
    var changed = false;
    final now = _presenceNow;
    for (final id in _trustedDevices.keys.toList()) {
      final device = _trustedDevices[id]!;
      final current = device.presenceAt(now);
      if (current.isOnline != device.isOnline) {
        _trustedDevices[id] = current;
        changed = true;
      }
    }
    _publicDiscoveredDevices.removeWhere((id, device) {
      final expired = !device.presenceAt(now).isOnline;
      if (expired) changed = true;
      return expired;
    });
    if (changed) notifyListeners();
  }

  final StreamController<WanDevice> _onPairSuccessController = StreamController<WanDevice>.broadcast();
  Stream<WanDevice> get onPairSuccess => _onPairSuccessController.stream;

  /// Callback when a remote peer sends a pairing request
  Function(WanPairRequest request)? onIncomingPairRequest;

  /// Callback when a trusted remote peer initiates a WebRTC signaling session
  Function(WanSignalingSession session)? onIncomingSessionRequest;

  String get deviceId => _identityService.deviceId;
  String get deviceName => _identityService.deviceName;
  String get platform => _identityService.platform;

  bool get isInitialized => _isInitialized;
  bool get isInternetModeEnabled => _isInternetModeEnabled;
  bool get isFirebaseConnected => _presenceService.isFirebaseConnected;
  bool get isOnline => _presenceService.isPresenceOnline;
  WanDiscoveryMode get discoveryMode => _discoveryMode;

  List<WanDevice> get trustedDevicesList => _trustedDevices.values.map((device) => device.presenceAt(_presenceNow)).toList();
  List<WanDevice> get publicDiscoveredDevices => _publicDiscoveredDevices.values
      .where((d) => d.id != deviceId && !_trustedDevices.containsKey(d.id) && d.presenceAt(_presenceNow).isOnline)
      .map((d) => d.isTrusted ? d.copyWith(isTrusted: false) : d)
      .toList();
  List<WanDevice> get publicDevices => publicDiscoveredDevices;

  /// Combined list of devices for Radar: Paired trusted devices + Discovered public peers
  List<WanDevice> get allRadarDevices {
    final list = <WanDevice>[];
    list.addAll(trustedDevicesList);
    if (_discoveryMode == WanDiscoveryMode.publicRadar) {
      list.addAll(publicDiscoveredDevices);
    }
    return list;
  }

  WanPairCode? get activePairCode => _activePairCode;

  DatabaseReference get _dbRef => _presenceService.database.ref();

  bool isDeviceTrusted(String id) => _trustedDevices.containsKey(id);

  int getUnreadCount(String peerId) => _unreadCounts[peerId] ?? 0;

  void incrementUnreadCount(String peerId) {
    if (peerId.isEmpty) return;
    _unreadCounts[peerId] = (_unreadCounts[peerId] ?? 0) + 1;
    if (_trustedDevices.containsKey(peerId)) {
      _trustedDevices[peerId] = _trustedDevices[peerId]!.copyWith(
        unreadCount: _unreadCounts[peerId],
      );
    }
    notifyListeners();
  }

  void clearUnreadCount(String peerId) {
    if (peerId.isEmpty) return;
    if ((_unreadCounts[peerId] ?? 0) > 0) {
      _unreadCounts[peerId] = 0;
      if (_trustedDevices.containsKey(peerId)) {
        _trustedDevices[peerId] = _trustedDevices[peerId]!.copyWith(
          unreadCount: 0,
        );
      }
      notifyListeners();
    }
  }

  /// Initialize WanService with persistent device identity and load cached trusted devices
  Future<void> init() async {
    if (_isInitialized) return;

    await _identityService.init();
    await _presenceService.init();

    // 1. Load locally cached trusted devices from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final cachedTrusted = prefs.getStringList('wan_trusted_ids') ?? [];
    for (final tId in cachedTrusted) {
      _trustedDevices[tId] = WanDevice(
        id: tId,
        name: prefs.getString('wan_peer_name_$tId') ?? 'Paired Peer',
        platform: prefs.getString('wan_peer_platform_$tId') ?? 'unknown',
        avatarEmoji: prefs.getString('wan_peer_avatar_$tId'),
        isOnline: false,
        isTrusted: true,
        unreadCount: _unreadCounts[tId] ?? 0,
      );
    }

    final modeIndex = prefs.getInt('wan_discovery_mode_idx');
    if (modeIndex != null && modeIndex >= 0 && modeIndex < WanDiscoveryMode.values.length) {
      _discoveryMode = WanDiscoveryMode.values[modeIndex];
    } else {
      _discoveryMode = WanDiscoveryMode.publicRadar;
    }

    _presenceService.setPublicRadarPresence(_discoveryMode == WanDiscoveryMode.publicRadar);

    _isInitialized = true;
    notifyListeners();
  }

  /// Change WAN Discovery & Privacy Mode
  Future<void> setDiscoveryMode(WanDiscoveryMode mode) async {
    _discoveryMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('wan_discovery_mode_idx', mode.index);

    final isPublic = mode == WanDiscoveryMode.publicRadar;
    await _presenceService.setPublicRadarPresence(isPublic);

    if (isPublic && _isInternetModeEnabled) {
      _listenToPublicPresence();
    } else {
      _stopListeningToPublicPresence();
    }

    notifyListeners();
  }

  /// Enable or disable Internet Mode listeners
  Future<void> setInternetMode(bool enable) async {
    _isInternetModeEnabled = enable;
    try {
      await _presenceService.setInternetMode(enable);
    } catch (_) {
      _isInternetModeEnabled = false;
      notifyListeners();
      rethrow;
    }

    if (enable) {
      await _serverTimeOffsetSub?.cancel();
      _serverTimeOffsetSub = _dbRef.child('.info/serverTimeOffset').onValue.listen((event) {
        final value = event.snapshot.value;
        if (value is num) _serverTimeOffsetMs = value.toInt();
        _expirePeerPresence();
      });
      _presenceExpiryTimer?.cancel();
      _presenceExpiryTimer = Timer.periodic(const Duration(seconds: 5), (_) => _expirePeerPresence());
      _expirePeerPresence();
      _listenToTrustedDevices();
      _listenToIncomingPairRequests();
      _listenToIncomingSessions();
      if (_discoveryMode == WanDiscoveryMode.publicRadar) {
        _listenToPublicPresence();
      }

      // Start periodic database garbage collection and run initial sweep
      _cleanupTimer?.cancel();
      _cleanupTimer = Timer.periodic(const Duration(minutes: 3), (_) {
        performPeriodicCleanup();
      });
      unawaited(performPeriodicCleanup());
    } else {
      _cancelInternetListeners();
    }

    notifyListeners();
  }

  /// Generate a random 6-digit pairing code (valid for ~5 minutes)
  Future<String> generatePairCode() async {
    if (!_presenceService.isFirebaseConnected && !_presenceService.isPresenceOnline) {
      if (!_isInternetModeEnabled) {
        await setInternetMode(true);
      }
    }

    // Cancel existing pair code if any
    if (_activePairCode != null) {
      try {
        await _dbRef.child('pairCodes/${_activePairCode!.code}').remove();
      } catch (_) {}
    }
    _pairCodeTimer?.cancel();

    final rng = Random();
    final code = (100000 + rng.nextInt(900000)).toString();
    final expiresAt = DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch;

    final pairCode = WanPairCode(
      code: code,
      ownerDeviceId: deviceId,
      ownerName: deviceName,
      ownerPlatform: platform,
      expiresAt: expiresAt,
    );

    // Save to Firebase RTDB: pairCodes/{code}
    await _dbRef.child('pairCodes/$code').set({
      'code': code,
      'ownerDeviceId': pairCode.ownerDeviceId,
      'ownerDeviceName': pairCode.ownerName,
      'platform': pairCode.ownerPlatform,
      'createdAt': ServerValue.timestamp,
      'expiresAt': expiresAt,
      'used': false,
    });

    _activePairCode = pairCode;
    _pairCodeTimer = Timer(const Duration(minutes: 5), () {
      cancelPairCode();
    });

    debugPrint('[WanService] Pair code generated: $code');
    notifyListeners();
    return code;
  }

  /// Cancel active pair code
  Future<void> cancelPairCode() async {
    if (_activePairCode != null) {
      try {
        await _dbRef.child('pairCodes/${_activePairCode!.code}').remove();
      } catch (_) {}
      _activePairCode = null;
    }
    _pairCodeTimer?.cancel();
    notifyListeners();
  }

  /// Enter a 6-digit pair code, validate, send pair request, and await acceptance
  Future<WanDevice> claimPairCode(String code) async {
    final cleanCode = code.trim();
    if (cleanCode.length != 6) {
      throw Exception('Please enter a valid 6-digit pairing code');
    }

    if (!_isInternetModeEnabled) {
      await setInternetMode(true);
    }

    // 1. Read pairCodes/{code}
    final snap = await _dbRef.child('pairCodes/$cleanCode').get();
    if (!snap.exists || snap.value == null) {
      throw Exception('Invalid or expired 6-digit pairing code');
    }

    final data = Map<dynamic, dynamic>.from(snap.value as Map);
    final isUsed = data['used'] as bool? ?? false;
    if (isUsed) {
      throw Exception('This pairing code has already been used');
    }

    final expiresAt = data['expiresAt'] as int? ?? 0;
    if (DateTime.now().millisecondsSinceEpoch > expiresAt) {
      debugPrint('[WanService] Pair code expired');
      try {
        await _dbRef.child('pairCodes/$cleanCode').remove();
      } catch (_) {}
      throw Exception('Pairing code has expired. Please ask peer to generate a new code.');
    }

    final targetDeviceId = (data['ownerDeviceId'] as String?) ?? '';
    final targetDeviceName = (data['ownerDeviceName'] as String?) ?? (data['ownerName'] as String?) ?? 'NearMitra Peer';
    final targetPlatform = (data['platform'] as String?) ?? (data['ownerPlatform'] as String?) ?? 'unknown';

    if (targetDeviceId == deviceId) {
      throw Exception('Cannot pair the same device with itself');
    }

    debugPrint('[WanService] Pair code validation successful for $targetDeviceName');

    // 2. Create pairing request: pairRequests/{targetDeviceId}/{requestId}
    final requestId = const Uuid().v4();
    final requestRef = _dbRef.child('pairRequests/$targetDeviceId/$requestId');

    await requestRef.set({
      'requestId': requestId,
      'fromDeviceId': deviceId,
      'fromDeviceName': deviceName,
      'fromPlatform': platform,
      'fromAvatarEmoji': _identityService.avatarEmoji,
      'toDeviceId': targetDeviceId,
      'code': cleanCode,
      'createdAt': ServerValue.timestamp,
      'status': 'pending',
    });

    debugPrint('[WanService] Pairing request sent');

    // 3. Await acceptance / rejection from target device (timeout 45 seconds)
    final completer = Completer<WanDevice>();
    StreamSubscription<DatabaseEvent>? statusSub;
    Timer? timeoutTimer;

    statusSub = requestRef.onValue.listen((event) async {
      if (!event.snapshot.exists || event.snapshot.value == null) return;
      final reqData = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final status = (reqData['status'] as String?) ?? 'pending';

      if (status == 'accepted') {
        timeoutTimer?.cancel();
        await statusSub?.cancel();

        debugPrint('[WanService] Pairing accepted');

        // Add to our trusted devices list
        await addTrustedDevice(
          id: targetDeviceId,
          name: targetDeviceName,
          platform: targetPlatform,
        );

        // Clean up temporary request and mark pair code as used
        try {
          await requestRef.remove();
          await _dbRef.child('pairCodes/$cleanCode').update({'used': true});
          await _dbRef.child('pairCodes/$cleanCode').remove();
        } catch (_) {}

        final remoteDevice = WanDevice(
          id: targetDeviceId,
          name: targetDeviceName,
          platform: targetPlatform,
          isOnline: true,
          isTrusted: true,
          unreadCount: _unreadCounts[targetDeviceId] ?? 0,
        );

        _onPairSuccessController.add(remoteDevice);

        if (!completer.isCompleted) {
          completer.complete(remoteDevice);
        }
      } else if (status == 'rejected') {
        timeoutTimer?.cancel();
        await statusSub?.cancel();

        debugPrint('[WanService] Pairing rejected');
        try {
          await requestRef.remove();
        } catch (_) {}

        if (!completer.isCompleted) {
          completer.completeError(Exception('Pairing request was rejected by remote device'));
        }
      }
    });

    timeoutTimer = Timer(const Duration(seconds: 45), () async {
      await statusSub?.cancel();
      try {
        await requestRef.remove();
      } catch (_) {}
      if (!completer.isCompleted) {
        completer.completeError(Exception('Pairing request timed out. Please try again.'));
      }
    });

    return completer.future;
  }

  /// Send a direct 1-tap connection request to a discovered peer on Radar
  Future<WanDevice> sendDirectPairRequest(WanDevice targetDevice) async {
    if (!_presenceService.isFirebaseConnected && !_presenceService.isPresenceOnline) {
      if (!_isInternetModeEnabled) {
        await setInternetMode(true);
      }
    }

    if (targetDevice.id == deviceId) {
      throw Exception('Cannot connect to your own device');
    }

    final requestId = const Uuid().v4();
    final requestRef = _dbRef.child('pairRequests/${targetDevice.id}/$requestId');

    await requestRef.onDisconnect().remove();
    await requestRef.set({
      'requestId': requestId,
      'fromDeviceId': deviceId,
      'fromDeviceName': deviceName,
      'fromPlatform': platform,
      'fromAvatarEmoji': _identityService.avatarEmoji,
      'toDeviceId': targetDevice.id,
      'code': '',
      'isDirectRadar': true,
      'createdAt': ServerValue.timestamp,
      'status': 'pending',
    });

    debugPrint('[WanService] Direct 1-tap pair request sent to ${targetDevice.name}');

    final completer = Completer<WanDevice>();
    StreamSubscription<DatabaseEvent>? statusSub;
    Timer? timeoutTimer;

    statusSub = requestRef.onValue.listen((event) async {
      if (!event.snapshot.exists || event.snapshot.value == null) return;
      final reqData = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final status = (reqData['status'] as String?) ?? 'pending';

      if (status == 'accepted') {
        timeoutTimer?.cancel();
        await statusSub?.cancel();

        await addTrustedDevice(
          id: targetDevice.id,
          name: targetDevice.name,
          platform: targetDevice.platform,
          avatarEmoji: targetDevice.avatarEmoji,
        );

        try {
          await requestRef.remove();
        } catch (_) {}

        final remoteDevice = WanDevice(
          id: targetDevice.id,
          name: targetDevice.name,
          platform: targetDevice.platform,
          avatarEmoji: targetDevice.avatarEmoji,
          isOnline: true,
          isTrusted: true,
          unreadCount: _unreadCounts[targetDevice.id] ?? 0,
        );

        _onPairSuccessController.add(remoteDevice);
        if (!completer.isCompleted) completer.complete(remoteDevice);
      } else if (status == 'rejected') {
        timeoutTimer?.cancel();
        await statusSub?.cancel();
        try {
          await requestRef.remove();
        } catch (_) {}
        if (!completer.isCompleted) {
          completer.completeError(Exception('Connection request was declined by ${targetDevice.name}'));
        }
      }
    });

    timeoutTimer = Timer(const Duration(seconds: 45), () async {
      await statusSub?.cancel();
      try {
        await requestRef.remove();
      } catch (_) {}
      if (!completer.isCompleted) {
        completer.completeError(Exception('Connection request timed out. Please try again.'));
      }
    });

    return completer.future;
  }

  /// Listen to incoming pair requests at pairRequests/{myDeviceId}
  void _listenToIncomingPairRequests() {
    _incomingPairRequestsSub?.cancel();
    final myRequestsRef = _dbRef.child('pairRequests/$deviceId');

    _incomingPairRequestsSub = myRequestsRef.onChildAdded.listen((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return;
      final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final status = (data['status'] as String?) ?? 'pending';

      if (status == 'pending') {
        final request = WanPairRequest.fromMap(event.snapshot.key ?? '', data);
        debugPrint('[WanService] Pairing request received from ${request.fromDeviceName} (directRadar=${request.isDirectRadar})');
        onIncomingPairRequest?.call(request);
      }
    });
  }

  /// Accept an incoming pairing request
  Future<void> acceptPairRequest(WanPairRequest request) async {
    debugPrint('[WanService] Accepting pair request from ${request.fromDeviceName}');

    // 1. Create mutual trusted device records in Firebase RTDB
    await _dbRef.child('trustedDevices/$deviceId/${request.fromDeviceId}').set({
      'deviceId': request.fromDeviceId,
      'deviceName': request.fromDeviceName,
      'platform': request.fromPlatform,
      if (request.fromAvatarEmoji != null && request.fromAvatarEmoji!.isNotEmpty)
        'avatarEmoji': request.fromAvatarEmoji,
      'pairedAt': ServerValue.timestamp,
    });

    await _dbRef.child('trustedDevices/${request.fromDeviceId}/$deviceId').set({
      'deviceId': deviceId,
      'deviceName': deviceName,
      'platform': platform,
      if (_identityService.avatarEmoji.isNotEmpty)
        'avatarEmoji': _identityService.avatarEmoji,
      'pairedAt': ServerValue.timestamp,
    });

    // 2. Add peer to local trusted list
    await addTrustedDevice(
      id: request.fromDeviceId,
      name: request.fromDeviceName,
      platform: request.fromPlatform,
      avatarEmoji: request.fromAvatarEmoji,
    );

    // 3. Mark pair request as accepted
    final reqRef = _dbRef.child('pairRequests/$deviceId/${request.requestId}');
    await reqRef.update({'status': 'accepted'});

    // 4. Mark pair code as used and cleanup
    if (request.code.isNotEmpty) {
      try {
        await _dbRef.child('pairCodes/${request.code}').update({'used': true});
        await _dbRef.child('pairCodes/${request.code}').remove();
      } catch (_) {}
    }

    final pairedDevice = WanDevice(
      id: request.fromDeviceId,
      name: request.fromDeviceName,
      platform: request.fromPlatform,
      avatarEmoji: request.fromAvatarEmoji,
      isOnline: true,
      isTrusted: true,
      unreadCount: _unreadCounts[request.fromDeviceId] ?? 0,
    );
    _onPairSuccessController.add(pairedDevice);

    Timer(const Duration(seconds: 5), () async {
      try {
        await reqRef.remove();
      } catch (_) {}
    });

    notifyListeners();
  }

  /// Reject an incoming pairing request
  Future<void> rejectPairRequest(WanPairRequest request) async {
    debugPrint('[WanService] Rejecting pair request from ${request.fromDeviceName}');
    final reqRef = _dbRef.child('pairRequests/$deviceId/${request.requestId}');
    try {
      await reqRef.update({'status': 'rejected'});
      Timer(const Duration(seconds: 3), () async {
        try {
          await reqRef.remove();
        } catch (_) {}
      });
    } catch (_) {}
  }

  /// Add device to trusted devices and save locally + subscribe to presence
  Future<void> addTrustedDevice({
    required String id,
    required String name,
    required String platform,
    String? avatarEmoji,
  }) async {
    _trustedDevices[id] = WanDevice(
      id: id,
      name: name,
      platform: platform,
      avatarEmoji: avatarEmoji,
      isOnline: true,
      isTrusted: true,
      unreadCount: _unreadCounts[id] ?? 0,
    );

    final prefs = await SharedPreferences.getInstance();
    final list = _trustedDevices.keys.toList();
    await prefs.setStringList('wan_trusted_ids', list);
    await prefs.setString('wan_peer_name_$id', name);
    await prefs.setString('wan_peer_platform_$id', platform);
    if (avatarEmoji != null && avatarEmoji.isNotEmpty) {
      await prefs.setString('wan_peer_avatar_$id', avatarEmoji);
    }

    _presenceSubs[id]?.cancel();
    _presenceSubs.remove(id);
    _subscribeToPeerPresence(id);

    try {
      final snap = await _dbRef.child('presence/$id').get();
      if (snap.exists && snap.value != null) {
        final map = Map<dynamic, dynamic>.from(snap.value as Map);
        final devAvatar = (map['avatarEmoji'] as String?) ?? (map['emoji'] as String?) ?? avatarEmoji;
        _trustedDevices[id] = WanDevice.fromMap(id, {
          ...map,
          'deviceName': map['deviceName'] ?? map['name'] ?? name,
          'platform': map['platform'] ?? platform,
          'avatarEmoji': devAvatar,
        }, isTrusted: true, unreadCount: _unreadCounts[id] ?? 0, now: _presenceNow);
        if (devAvatar != null && devAvatar.isNotEmpty) {
          await prefs.setString('wan_peer_avatar_$id', devAvatar);
        }
      }
    } catch (_) {}

    notifyListeners();
  }

  /// Remove/Unpair a trusted device
  Future<void> removeTrustedDevice(String id) async {
    _trustedDevices.remove(id);
    _unreadCounts.remove(id);
    _presenceSubs[id]?.cancel();
    _presenceSubs.remove(id);

    final prefs = await SharedPreferences.getInstance();
    final list = _trustedDevices.keys.toList();
    await prefs.setStringList('wan_trusted_ids', list);
    await prefs.remove('wan_peer_name_$id');
    await prefs.remove('wan_peer_platform_$id');
    await prefs.remove('wan_peer_avatar_$id');

    try {
      await _dbRef.child('trustedDevices/$deviceId/$id').remove();
      await _dbRef.child('trustedDevices/$id/$deviceId').remove();
    } catch (_) {}

    // Instantly update public presence discovered devices in real-time
    if (_publicDiscoveredDevices.containsKey(id)) {
      _publicDiscoveredDevices[id] = _publicDiscoveredDevices[id]!.copyWith(
        isTrusted: false,
      );
    } else {
      // Check if peer is currently active on public presence
      try {
        final snap = await _dbRef.child('public_presence/$id').get();
        if (snap.exists && snap.value != null && snap.value is Map) {
          final peerMap = Map<dynamic, dynamic>.from(snap.value as Map);
          _publicDiscoveredDevices[id] = WanDevice.fromMap(
            id,
            peerMap,
            isTrusted: false,
            unreadCount: 0,
            now: _presenceNow,
          );
        }
      } catch (_) {}
    }

    debugPrint('[WanService] Device unpaired: $id');
    notifyListeners();
  }

  /// Listen to changes in our trusted devices in Firebase
  void _listenToTrustedDevices() {
    _trustedDevicesSub?.cancel();
    _trustedDevicesSub = _dbRef.child('trustedDevices/$deviceId').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        map.forEach((peerId, peerData) {
          if (peerId is String && peerData is Map) {
            final name = (peerData['deviceName'] as String?) ?? (peerData['name'] as String?) ?? 'NearMitra Peer';
            final platform = (peerData['platform'] as String?) ?? 'unknown';
            final avatarEmoji = (peerData['avatarEmoji'] as String?) ?? (peerData['emoji'] as String?);
            if (!_trustedDevices.containsKey(peerId)) {
              addTrustedDevice(id: peerId, name: name, platform: platform, avatarEmoji: avatarEmoji);
            }
          }
        });
      }
    });

    for (final id in _trustedDevices.keys) {
      _subscribeToPeerPresence(id);
    }
  }

  /// Subscribe to a single peer's presence in Firebase (presence/{peerId})
  void _subscribeToPeerPresence(String peerId) {
    if (_presenceSubs.containsKey(peerId)) return;

    _presenceSubs[peerId] = _dbRef.child('presence/$peerId').onValue.listen((event) async {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        final existing = _trustedDevices[peerId];
        final avatarEmoji = (map['avatarEmoji'] as String?) ?? (map['emoji'] as String?) ?? existing?.avatarEmoji;
        _trustedDevices[peerId] = WanDevice.fromMap(peerId, {
          ...map,
          'deviceName': map['deviceName'] ?? map['name'] ?? existing?.name ?? 'Peer',
          'platform': map['platform'] ?? existing?.platform ?? 'unknown',
          'avatarEmoji': avatarEmoji,
        }, isTrusted: true, unreadCount: _unreadCounts[peerId] ?? 0, now: _presenceNow);

        if (avatarEmoji != null && avatarEmoji.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('wan_peer_avatar_$peerId', avatarEmoji);
        }

        notifyListeners();
      } else {
        final existing = _trustedDevices[peerId];
        if (existing != null && existing.isOnline) {
          _trustedDevices[peerId] = existing.copyWith(isOnline: false);
          notifyListeners();
        }
      }
    });
  }

  // ===========================================================================
  // WebRTC Signaling Protocol (sessions/{sessionId})
  // ===========================================================================

  /// Listen to incoming sessions where receiverId == currentDeviceId
  void _listenToIncomingSessions() {
    _incomingSessionsSub?.cancel();
    final query = _dbRef.child('sessions').orderByChild('receiverId').equalTo(deviceId);

    _incomingSessionsSub = query.onChildAdded.listen((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return;
      final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final sessionId = event.snapshot.key ?? '';
      final session = WanSignalingSession.fromMap(sessionId, data);

      // Security and validity checks:
      // 1. Caller must be in trusted devices
      // 2. Session must not be expired (< 60 seconds)
      // 3. Caller cannot be self
      // 4. Status must be calling
      if (session.callerId.isNotEmpty &&
          session.callerId != deviceId &&
          isDeviceTrusted(session.callerId) &&
          !session.isExpired &&
          session.status == 'calling') {
        debugPrint('[WanService] Valid incoming signaling session: $sessionId from ${session.callerName}');
        onIncomingSessionRequest?.call(session);
      }
    });
  }

  /// Create WebRTC signaling session in Firebase RTDB: sessions/{sessionId}
  Future<String> createSignalingSession({
    String? sessionId,
    required String receiverId,
    required Map<String, dynamic> offerSdp,
  }) async {
    final sId = sessionId ?? const Uuid().v4();
    final targetDevice = _trustedDevices[receiverId];

    await _dbRef.child('sessions/$sId').set({
      'sessionId': sId,
      'callerId': deviceId,
      'callerName': deviceName,
      'callerPlatform': platform,
      'receiverId': receiverId,
      'receiverName': targetDevice?.name ?? 'Peer',
      'status': 'calling',
      'offer': offerSdp,
      'createdAt': ServerValue.timestamp,
    });

    debugPrint('[WanService] Created signaling session $sId for receiver $receiverId');
    return sId;
  }

  /// Accept incoming session and submit Answer SDP: sessions/{sessionId}/answer
  Future<void> acceptSignalingSession({
    required String sessionId,
    required Map<String, dynamic> answerSdp,
  }) async {
    await _dbRef.child('sessions/$sessionId').update({
      'status': 'accepted',
      'answer': answerSdp,
    });
    debugPrint('[WanService] Accepted signaling session $sessionId');
  }

  /// Reject signaling session
  Future<void> rejectSignalingSession(String sessionId) async {
    try {
      await _dbRef.child('sessions/$sessionId').update({
        'status': 'rejected',
      });
      debugPrint('[WanService] Rejected signaling session $sessionId');
      Timer(const Duration(seconds: 5), () {
        deleteSignalingSession(sessionId);
      });
    } catch (_) {}
  }

  /// Update session status
  Future<void> updateSessionStatus(String sessionId, String status) async {
    try {
      await _dbRef.child('sessions/$sessionId/status').set(status);
    } catch (_) {}
  }

  /// Add local ICE candidate to sessions/{sessionId}/candidates/{caller|receiver}
  Future<void> addIceCandidate({
    required String sessionId,
    required bool isCaller,
    required Map<String, dynamic> candidateMap,
  }) async {
    final role = isCaller ? 'caller' : 'receiver';
    await _dbRef.child('sessions/$sessionId/candidates/$role').push().set(candidateMap);
  }

  /// Listen to Answer SDP when we are caller
  StreamSubscription<DatabaseEvent> listenToAnswer(
    String sessionId,
    Function(Map<String, dynamic> answer) onAnswer,
  ) {
    return _dbRef.child('sessions/$sessionId/answer').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final answerMap = Map<String, dynamic>.from(event.snapshot.value as Map);
        onAnswer(answerMap);
      }
    });
  }

  /// Listen to session status changes
  StreamSubscription<DatabaseEvent> listenToSessionStatus(
    String sessionId,
    Function(String status) onStatus,
  ) {
    return _dbRef.child('sessions/$sessionId/status').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final status = event.snapshot.value as String;
        onStatus(status);
      }
    });
  }

  /// Listen to remote ICE candidates
  StreamSubscription<DatabaseEvent> listenToCandidates(
    String sessionId,
    bool isCaller,
    Function(Map<String, dynamic> candidateMap) onCandidate,
  ) {
    // If caller, listen to receiver candidates; if receiver, listen to caller candidates
    final remoteRole = isCaller ? 'receiver' : 'caller';
    return _dbRef.child('sessions/$sessionId/candidates/$remoteRole').onChildAdded.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final candMap = Map<String, dynamic>.from(event.snapshot.value as Map);
        onCandidate(candMap);
      }
    });
  }

  /// Delete signaling session data after completion or disconnect
  Future<void> deleteSignalingSession(String sessionId) async {
    try {
      await _dbRef.child('sessions/$sessionId').remove();
      debugPrint('[WanService] Cleaned up signaling session $sessionId');
    } catch (_) {}
  }

  /// Realtime Database Garbage Collection:
  /// Periodically cleans up expired pair codes, stale/ended signaling sessions, and old pair requests
  Future<void> performPeriodicCleanup() async {
    if (!_isInternetModeEnabled && !_presenceService.isFirebaseConnected) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    debugPrint('[WanService] Running periodic RTDB cleanup sweep...');

    // 1. Clean up expired / used / stale pair codes
    try {
      final snap = await _dbRef.child('pairCodes').get();
      if (snap.exists && snap.value != null) {
        final codes = Map<dynamic, dynamic>.from(snap.value as Map);
        for (final entry in codes.entries) {
          final codeKey = entry.key.toString();
          if (entry.value is Map) {
            final data = Map<dynamic, dynamic>.from(entry.value as Map);
            final expiresAt = (data['expiresAt'] as int?) ?? 0;
            final isUsed = (data['used'] as bool?) ?? false;
            final createdAt = (data['createdAt'] as int?) ?? 0;

            final isExpired = expiresAt > 0 && now > expiresAt;
            final isStale = createdAt > 0 && (now - createdAt > 10 * 60 * 1000);

            if (isUsed || isExpired || isStale) {
              await _dbRef.child('pairCodes/$codeKey').remove();
              debugPrint('[WanService] Cleaned up expired/used pair code: $codeKey');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[WanService] Error during pairCodes cleanup: $e');
    }

    // 2. Clean up stale / completed / abandoned WebRTC signaling sessions
    try {
      final snap = await _dbRef.child('sessions').get();
      if (snap.exists && snap.value != null) {
        final sessions = Map<dynamic, dynamic>.from(snap.value as Map);
        for (final entry in sessions.entries) {
          final sId = entry.key.toString();
          if (entry.value is Map) {
            final data = Map<dynamic, dynamic>.from(entry.value as Map);
            final status = (data['status'] as String?) ?? 'calling';
            final createdAt = (data['createdAt'] as int?) ?? 0;
            final ageMs = createdAt > 0 ? (now - createdAt) : 999999;

            final isEndedOrRejected = status == 'rejected' || status == 'ended' || status == 'closed';
            final isAcceptedStale = status == 'accepted' && ageMs > 60 * 1000; // 1 min after accepted
            final isCallingStale = status == 'calling' && ageMs > 90 * 1000;   // 1.5 min call timeout
            final isOlderThan3Min = ageMs > 3 * 60 * 1000;

            if (isEndedOrRejected || isAcceptedStale || isCallingStale || isOlderThan3Min) {
              await _dbRef.child('sessions/$sId').remove();
              debugPrint('[WanService] Cleaned up stale session: $sId (status: $status, age: ${ageMs ~/ 1000}s)');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[WanService] Error during sessions cleanup: $e');
    }

    // 3. Clean up stale / completed pair requests targeted to this device
    try {
      final snap = await _dbRef.child('pairRequests/$deviceId').get();
      if (snap.exists && snap.value != null) {
        final requests = Map<dynamic, dynamic>.from(snap.value as Map);
        for (final entry in requests.entries) {
          final reqId = entry.key.toString();
          if (entry.value is Map) {
            final data = Map<dynamic, dynamic>.from(entry.value as Map);
            final status = (data['status'] as String?) ?? 'pending';
            final createdAt = (data['createdAt'] as int?) ?? 0;
            final ageMs = createdAt > 0 ? (now - createdAt) : 999999;

            if (status != 'pending' || ageMs > 5 * 60 * 1000) {
              await _dbRef.child('pairRequests/$deviceId/$reqId').remove();
              debugPrint('[WanService] Cleaned up old pair request: $reqId (status: $status)');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[WanService] Error during pairRequests cleanup: $e');
    }
  }

  /// Listen to public presence node /public_presence for public radar discovery
  void _listenToPublicPresence() {
    _publicPresenceSub?.cancel();
    final publicRef = _dbRef.child('public_presence');

    _publicPresenceSub = publicRef.onValue.listen((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) {
        _publicDiscoveredDevices.clear();
        notifyListeners();
        return;
      }

      final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final newMap = <String, WanDevice>{};

      data.forEach((k, v) {
        final peerId = k.toString();
        if (peerId != deviceId && v is Map) {
          final peerMap = Map<dynamic, dynamic>.from(v);
          final dev = WanDevice.fromMap(
            peerId,
            peerMap,
            isTrusted: _trustedDevices.containsKey(peerId),
            unreadCount: _unreadCounts[peerId] ?? 0,
            now: _presenceNow,
          );
          if (dev.isOnline) newMap[peerId] = dev;
        }
      });

      _publicDiscoveredDevices.clear();
      _publicDiscoveredDevices.addAll(newMap);
      notifyListeners();
    });
  }

  void _stopListeningToPublicPresence() {
    _publicPresenceSub?.cancel();
    _publicPresenceSub = null;
    _publicDiscoveredDevices.clear();
    notifyListeners();
  }

  void _cancelInternetListeners() {
    _presenceExpiryTimer?.cancel();
    _presenceExpiryTimer = null;
    _serverTimeOffsetSub?.cancel();
    _serverTimeOffsetSub = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _trustedDevicesSub?.cancel();
    _trustedDevicesSub = null;
    _incomingPairRequestsSub?.cancel();
    _incomingPairRequestsSub = null;
    _incomingSessionsSub?.cancel();
    _incomingSessionsSub = null;
    _stopListeningToPublicPresence();
    for (final s in _presenceSubs.values) {
      s.cancel();
    }
    _presenceSubs.clear();
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _cancelInternetListeners();
    _pairCodeTimer?.cancel();
    super.dispose();
  }
}
