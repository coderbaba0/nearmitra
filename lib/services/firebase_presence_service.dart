import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'internet_device_identity_service.dart';

class FirebasePresenceService extends ChangeNotifier {
  static final FirebasePresenceService _instance = FirebasePresenceService._internal();
  factory FirebasePresenceService() => _instance;
  FirebasePresenceService._internal();

  static const String rtdbUrl = 'https://nearmitra-beb60-default-rtdb.asia-southeast1.firebasedatabase.app';

  final InternetDeviceIdentityService _identityService = InternetDeviceIdentityService();

  FirebaseDatabase? _db;
  bool _isInitialized = false;
  bool _isInternetModeEnabled = false;
  bool _isFirebaseConnected = false;
  bool _isPresenceOnline = false;

  StreamSubscription<DatabaseEvent>? _connectedSub;

  bool get isInitialized => _isInitialized;
  bool get isInternetModeEnabled => _isInternetModeEnabled;
  bool get isFirebaseConnected => _isFirebaseConnected;
  bool get isPresenceOnline => _isPresenceOnline;

  String get deviceId => _identityService.deviceId;
  String get deviceName => _identityService.deviceName;
  String get platform => _identityService.platform;

  /// Reusable FirebaseDatabase instance with the project RTDB URL
  FirebaseDatabase get database {
    if (_db != null) return _db!;
    try {
      if (Firebase.apps.isNotEmpty) {
        _db = FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL: rtdbUrl,
        );
      } else {
        _db = FirebaseDatabase.instance;
      }
    } catch (e) {
      debugPrint('[FirebasePresence] Fallback to FirebaseDatabase.instance: $e');
      _db = FirebaseDatabase.instance;
    }
    return _db!;
  }

  /// Initialize identity and test Firebase connection
  Future<void> init() async {
    if (_isInitialized) return;

    // 1. Ensure persistent device identity
    await _identityService.init();

    // 2. Test Firebase Connection
    await _testConnection();

    _isInitialized = true;
    notifyListeners();
  }

  /// Temporary connectivity test
  Future<void> _testConnection() async {
    try {
      if (Firebase.apps.isEmpty) {
        debugPrint('[Firebase] Warning: Firebase not initialized');
        return;
      }
      debugPrint('Firebase initialized successfully');

      final db = database;
      debugPrint('Realtime Database connected');

      final testRef = db.ref('test');
      await testRef.set({
        'message': 'NearMitra connected',
        'platform': _identityService.platform,
        'timestamp': ServerValue.timestamp,
      });
      debugPrint('Test write successful');
    } catch (e) {
      debugPrint('[Firebase] Connection test error: $e');
    }
  }

  /// Toggle Internet Mode ON or OFF
  Future<void> setInternetMode(bool enable) async {
    if (_isInternetModeEnabled == enable) return;
    _isInternetModeEnabled = enable;

    if (enable) {
      await _enableInternetMode();
    } else {
      await _disableInternetMode();
    }

    notifyListeners();
  }

  Future<void> _enableInternetMode() async {
    debugPrint('[FirebasePresence] Enabling Internet Mode for $deviceId ($deviceName on $platform)...');

    // 1. Listen to .info/connected
    final connectedRef = database.ref('.info/connected');
    await _connectedSub?.cancel();
    _connectedSub = connectedRef.onValue.listen((event) async {
      final connected = event.snapshot.value as bool? ?? false;
      _isFirebaseConnected = connected;
      debugPrint('[FirebasePresence] .info/connected: $connected');

      if (connected && _isInternetModeEnabled) {
        await _registerPresence();
      } else {
        _isPresenceOnline = false;
      }
      notifyListeners();
    });
  }

  Future<void> _registerPresence() async {
    if (!_isInternetModeEnabled) return;

    final presenceRef = database.ref('presence/$deviceId');

    try {
      // Configure onDisconnect hook before setting online
      await presenceRef.onDisconnect().update({
        'online': false,
        'lastSeen': ServerValue.timestamp,
      });
      debugPrint('[FirebasePresence] onDisconnect hook registered for presence/$deviceId');

      // Set online presence
      await presenceRef.update({
        'deviceId': deviceId,
        'deviceName': deviceName,
        'platform': platform,
        'online': true,
        'lastSeen': ServerValue.timestamp,
      });

      _isPresenceOnline = true;
      debugPrint('[FirebasePresence] Device online registered in Firebase at presence/$deviceId');
    } catch (e) {
      debugPrint('[FirebasePresence] Failed to register presence: $e');
      _isPresenceOnline = false;
    }
  }

  Future<void> _disableInternetMode() async {
    debugPrint('[FirebasePresence] Disabling Internet Mode...');

    // 1. Cancel .info/connected subscription
    await _connectedSub?.cancel();
    _connectedSub = null;
    _isFirebaseConnected = false;

    // 2. Mark device offline in Firebase RTDB
    try {
      final presenceRef = database.ref('presence/$deviceId');
      await presenceRef.onDisconnect().cancel();
      await presenceRef.update({
        'online': false,
        'lastSeen': ServerValue.timestamp,
      });
      debugPrint('[FirebasePresence] Device marked offline in Firebase at presence/$deviceId');
    } catch (e) {
      debugPrint('[FirebasePresence] Error marking offline: $e');
    }

    _isPresenceOnline = false;
  }

  @override
  void dispose() {
    _connectedSub?.cancel();
    super.dispose();
  }
}
