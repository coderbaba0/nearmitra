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
  static const _avatarEmojiKey = 'farmitra_device_avatar_emoji';

  String? _deviceId;
  String? _deviceName;
  String _avatarEmoji = '📱';
  String _platform = 'android';
  bool _isInitialized = false;

  String get deviceId => _deviceId ?? 'unknown_device_id';
  String get deviceName => _deviceName ?? 'NearMitra Device';
  String get avatarEmoji => _avatarEmoji;
  String get platform => _platform;
  bool get isInitialized => _isInitialized;

  /// Load or generate persistent device identity
  Future<void> init({String? customName, String? customEmoji}) async {
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
      _avatarEmoji = '💻';
    } else if (Platform.isAndroid) {
      _platform = 'android';
      _avatarEmoji = '📱';
    } else if (Platform.isWindows) {
      _platform = 'windows';
      _avatarEmoji = '💻';
    } else if (Platform.isIOS) {
      _platform = 'ios';
      _avatarEmoji = '📱';
    } else if (Platform.isMacOS) {
      _platform = 'macos';
      _avatarEmoji = '💻';
    } else if (Platform.isLinux) {
      _platform = 'linux';
      _avatarEmoji = '💻';
    }

    // 3. Avatar Emoji
    if (customEmoji != null && customEmoji.trim().isNotEmpty) {
      _avatarEmoji = customEmoji.trim();
      await prefs.setString(_avatarEmojiKey, _avatarEmoji);
    } else {
      final savedEmoji = prefs.getString(_avatarEmojiKey);
      if (savedEmoji != null && savedEmoji.trim().isNotEmpty) {
        _avatarEmoji = savedEmoji.trim();
      }
    }

    // 4. Device Name
    if (customName != null && customName.trim().isNotEmpty) {
      _deviceName = customName.trim();
      await prefs.setString(_deviceNameKey, _deviceName!);
    } else {
      final savedName = prefs.getString(_deviceNameKey) ?? prefs.getString('farmitra_nearby_device_name');
      if (savedName != null && savedName.trim().isNotEmpty) {
        _deviceName = savedName.trim();
      } else {
        _deviceName = await _resolveDeviceModel();
        await prefs.setString(_deviceNameKey, _deviceName!);
      }
    }

    _isInitialized = true;
    debugPrint('[InternetIdentity] Identity ready: ID=$_deviceId, Name=$_deviceName, Avatar=$_avatarEmoji, Platform=$_platform');
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
    await prefs.setString('farmitra_nearby_device_name', _deviceName!);
    debugPrint('[InternetIdentity] Updated device name: $_deviceName');
  }

  Future<void> updateDeviceIdentity({required String newName, required String newEmoji}) async {
    if (newName.trim().isNotEmpty) {
      _deviceName = newName.trim();
    }
    if (newEmoji.trim().isNotEmpty) {
      _avatarEmoji = newEmoji.trim();
    }
    final prefs = await SharedPreferences.getInstance();
    if (_deviceName != null) {
      await prefs.setString(_deviceNameKey, _deviceName!);
      await prefs.setString('farmitra_nearby_device_name', _deviceName!);
    }
    await prefs.setString(_avatarEmojiKey, _avatarEmoji);
    debugPrint('[InternetIdentity] Updated identity: Name=$_deviceName, Avatar=$_avatarEmoji');
  }
}
