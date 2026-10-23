import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'internet_device_identity_service.dart';

class FirebasePresenceService extends ChangeNotifier {
  static final FirebasePresenceService _instance = FirebasePresenceService._internal();
  factory FirebasePresenceService() => _instance;
  FirebasePresenceService._internal();

  static const String rtdbUrl = String.fromEnvironment('FIREBASE_DATABASE_URL');

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
  String get avatarEmoji => _identityService.avatarEmoji;
  String get platform => _identityService.platform;

  /// Update custom device name & avatar emoji in Firebase presence
  Future<void> updateDeviceIdentity({required String newName, required String newEmoji}) async {
    await _identityService.updateDeviceIdentity(newName: newName, newEmoji: newEmoji);
    if (_isInternetModeEnabled && _isFirebaseConnected && _isPresenceOnline) {
      try {
        await database.ref('presence/$deviceId').update({
          'deviceName': deviceName,
          'avatarEmoji': avatarEmoji,
        });
        if (_isPublicPresence) {
          await database.ref('public_presence/$deviceId').update({
            'deviceName': deviceName,
            'avatarEmoji': avatarEmoji,
          });
        }
      } catch (e) {
        debugPrint('[FirebasePresence] Error updating presence identity: $e');
      }
    }
    notifyListeners();
  }

  /// Reusable FirebaseDatabase instance with the project RTDB URL
  FirebaseDatabase get database {
    if (_db != null) return _db!;
    // Resolve only the explicitly configured app/project; never a shared fallback.
    final app = Firebase.app();
    _db = FirebaseDatabase.instanceFor(
      app: app,
      databaseURL: rtdbUrl.isNotEmpty ? rtdbUrl : app.options.databaseURL,
    );
    const emulatorHost = String.fromEnvironment('FIREBASE_DATABASE_EMULATOR_HOST');
    const emulatorPort = int.fromEnvironment('FIREBASE_DATABASE_EMULATOR_PORT', defaultValue: 9000);
    if (emulatorHost.isNotEmpty) {
      _db!.useDatabaseEmulator(emulatorHost, emulatorPort);
    }
    return _db!;
  }

  /// Initialize local device identity (100% offline-safe, instant)
  Future<void> init() async {
    if (_isInitialized) return;

    // 1. Ensure persistent device identity from local storage
    await _identityService.init();

    _isInitialized = true;
    notifyListeners();
  }

  /// Toggle Internet Mode ON or OFF
  Future<void> setInternetMode(bool enable) async {
    if (_isInternetModeEnabled == enable) return;
    _isInternetModeEnabled = enable;

    if (enable) {
      try {
        await _enableInternetMode();
      } catch (_) {
        _isInternetModeEnabled = false;
        rethrow;
      }
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

  bool _isPublicPresence = true;
  bool get isPublicPresence => _isPublicPresence;

  /// Set whether device is publicly visible on WAN Radar
  Future<void> setPublicRadarPresence(bool isPublic) async {
    _isPublicPresence = isPublic;
    if (!_isInternetModeEnabled || !_isFirebaseConnected) {
      notifyListeners();
      return;
    }

    final publicPresenceRef = database.ref('public_presence/$deviceId');
    try {
      if (isPublic && _isPresenceOnline) {
        await publicPresenceRef.onDisconnect().remove();
        await publicPresenceRef.set({
          'deviceId': deviceId,
          'deviceName': deviceName,
          'avatarEmoji': avatarEmoji,
          'platform': platform,
          'online': true,
          'lastSeen': ServerValue.timestamp,
        });
        debugPrint('[FirebasePresence] Public presence registered at public_presence/$deviceId');
      } else {
        await publicPresenceRef.onDisconnect().cancel();
        await publicPresenceRef.remove();
        debugPrint('[FirebasePresence] Public presence removed (Private/Ghost mode)');
      }
    } catch (e) {
      debugPrint('[FirebasePresence] Error setting public presence: $e');
    }
    notifyListeners();
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
        'avatarEmoji': avatarEmoji,
        'platform': platform,
        'online': true,
        'lastSeen': ServerValue.timestamp,
      });

      _isPresenceOnline = true;
      debugPrint('[FirebasePresence] Device online registered in Firebase at presence/$deviceId');

      // Also register public presence if enabled
      if (_isPublicPresence) {
        await setPublicRadarPresence(true);
      }
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

    // 2. Remove public presence
    try {
      final publicRef = database.ref('public_presence/$deviceId');
      await publicRef.onDisconnect().cancel();
      await publicRef.remove();
    } catch (_) {}

    // 3. Mark device offline in Firebase RTDB
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
