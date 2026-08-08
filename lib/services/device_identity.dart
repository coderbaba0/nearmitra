import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentity {
  static const _idKey = 'farmitra_nearby_device_id';

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
    final info = await DeviceInfoPlugin().androidInfo;
    final model = info.model.trim();
    return model.isEmpty ? 'Android device' : model;
  }
}
