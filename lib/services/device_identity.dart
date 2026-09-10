import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentity {
  static const _idKey = 'farmitra_nearby_device_id';
  static const _nameKey = 'farmitra_nearby_device_name';
  static const _avatarKey = 'farmitra_device_avatar_emoji';

  static const List<String> presetEmojis = [
    '📱', '💻', '🚀', '⚡', '🌾', '🤖',
    '🦊', '🦁', '🐯', '🦅', '👑', '🛡️',
    '🌟', '🔥', '🎮', '💎', '🍀', '🎯',
    '🛸', '🛰️', '🦄', '🐉', '🧙', '🎧',
  ];

  Future<String> getId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_idKey);
    if (id != null && id.isNotEmpty) return id;
    final random = Random.secure();
    id = List.generate(20, (_) => random.nextInt(16).toRadixString(16)).join();
    await prefs.setString(_idKey, id);
    return id;
  }

  Future<String> getName() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_nameKey);
    if (saved != null && saved.trim().isNotEmpty) return saved.trim();

    String defaultName = 'NearMitra Device';
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        final model = info.model.trim();
        defaultName = model.isNotEmpty ? model : 'Android Phone';
      } else if (!kIsWeb && Platform.isWindows) {
        final info = await DeviceInfoPlugin().windowsInfo;
        final name = info.computerName.trim();
        defaultName = name.isNotEmpty ? name : 'Windows PC';
      }
    } catch (_) {}

    await prefs.setString(_nameKey, defaultName);
    return defaultName;
  }

  Future<void> setName(String name) async {
    if (name.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name.trim());
  }

  Future<String> getAvatarEmoji() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_avatarKey);
    if (saved != null && saved.trim().isNotEmpty) return saved.trim();

    String defaultEmoji = '📱';
    if (!kIsWeb && Platform.isWindows) {
      defaultEmoji = '💻';
    }
    await prefs.setString(_avatarKey, defaultEmoji);
    return defaultEmoji;
  }

  Future<void> setAvatarEmoji(String emoji) async {
    if (emoji.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_avatarKey, emoji.trim());
  }
}
