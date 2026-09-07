import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_item.dart';

class HistoryService {
  static const _key = 'farmitra_nearby_chat_history_v1';

  Future<List<ChatItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ChatItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<ChatItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = items.length > 800 ? items.sublist(items.length - 800) : items;
    await prefs.setString(_key, jsonEncode(trimmed.map((e) => e.toJson()).toList()));
  }

  Future<void> addItem(ChatItem item) async {
    final list = await load();
    final idx = list.indexWhere((e) => e.id == item.id);
    if (idx != -1) {
      list[idx] = item;
    } else {
      list.add(item);
    }
    await save(list);
  }

  Future<void> addItems(List<ChatItem> newItems) async {
    if (newItems.isEmpty) return;
    final list = await load();
    for (final item in newItems) {
      final idx = list.indexWhere((e) => e.id == item.id);
      if (idx != -1) {
        list[idx] = item;
      } else {
        list.add(item);
      }
    }
    await save(list);
  }
}
