import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class InternetDeviceIdentityService {
  static final InternetDeviceIdentityService _instance = InternetDeviceIdentityService._internal();
  factory InternetDeviceIdentityService() => _instance;
  InternetDeviceIdentityService._internal();

  static const _deviceIdKey = 'nearmitra_internet_device_id';
  static const _deviceNameKey = 'nearmitra_internet_device_name';

  String? _deviceId;
  String? _deviceName;
  String _platform = 'android';
  bool _isInitialized = false;

  String get deviceId => _deviceId ?? 'unknown_device_id';
  String get deviceName => _deviceName ?? 'NearMitra Device';
  String get platform => _platform;
  bool get isInitialized => _isInitialized;

  /// Load or generate persistent device identity
  Future<void> init({String? customName}) async {
    if (_isInitialized) return;

    final prefs = await SharedPreferences.getInstance();

    // 1. Persistent Device UUID
    var storedId = prefs.getString(_deviceIdKey);
    if (storedId == null || storedId.trim().isEmpty) {
      storedId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, storedId);
      debugPrint('[InternetIdentity] Generated new persistent deviceId: $storedId');
    } else {
      debugPrint('[InternetIdentity] Persistent deviceId loaded: $storedId');
    }
    _deviceId = storedId;

    // 2. Platform detection
    if (kIsWeb) {
      _platform = 'web';
    } else if (Platform.isAndroid) {
      _platform = 'android';
    } else if (Platform.isWindows) {
      _platform = 'windows';
    } else if (Platform.isIOS) {
      _platform = 'ios';
    } else if (Platform.isMacOS) {
      _platform = 'macos';
    } else if (Platform.isLinux) {
      _platform = 'linux';
    }

    // 3. Device Name
    if (customName != null && customName.trim().isNotEmpty) {
      _deviceName = customName.trim();
      await prefs.setString(_deviceNameKey, _deviceName!);
    } else {
      final savedName = prefs.getString(_deviceNameKey);
      if (savedName != null && savedName.trim().isNotEmpty) {
        _deviceName = savedName.trim();
      } else {
        _deviceName = await _resolveDeviceModel();
        await prefs.setString(_deviceNameKey, _deviceName!);
      }
    }

    _isInitialized = true;
    debugPrint('[InternetIdentity] Identity ready: ID=$_deviceId, Name=$_deviceName, Platform=$_platform');
  }

  Future<String> _resolveDeviceModel() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (!kIsWeb && Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        final model = androidInfo.model.trim();
        return model.isNotEmpty ? model : 'Android Phone';
      } else if (!kIsWeb && Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        final computerName = windowsInfo.computerName.trim();
        return computerName.isNotEmpty ? computerName : 'Windows PC';
      }
    } catch (_) {}
    return 'NearMitra Device';
  }

  Future<void> updateDeviceName(String newName) async {
    if (newName.trim().isEmpty) return;
    _deviceName = newName.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceNameKey, _deviceName!);
    debugPrint('[InternetIdentity] Updated device name: $_deviceName');
  }
}
