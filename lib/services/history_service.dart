import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_item.dart';

class HistoryService extends ChangeNotifier {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  static const _key = 'farmitra_nearby_chat_history_v1';
  Future<void> _writes = Future<void>.value();

  Future<List<ChatItem>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => ChatItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<ChatItem>> load() async {
    await _writes;
    return _read();
  }

  Future<void> _write(List<ChatItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final unique = {for (final item in items) item.id: item}.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final trimmed =
        unique.length > 800 ? unique.sublist(unique.length - 800) : unique;
    await prefs.setString(
        _key, jsonEncode(trimmed.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  Future<void> _serialize(Future<void> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.then<void>((_) {}, onError: (Object e, StackTrace s) {
      debugPrint('[History] Write failed: $e');
    });
    return result;
  }

  Future<void> save(List<ChatItem> items) {
    final snapshot = items.map((e) => ChatItem.fromJson(e.toJson())).toList();
    return _serialize(() => _write(snapshot));
  }

  Future<void> removePeers(Set<String> peerIds) => _serialize(() async {
        final items = await _read();
        await _write(
            items.where((item) => !peerIds.contains(item.peerId)).toList());
      });

  Future<void> addItem(ChatItem item) => addItems([item]);

  Future<void> addItems(List<ChatItem> newItems) {
    if (newItems.isEmpty) return Future<void>.value();
    final snapshots =
        newItems.map((e) => ChatItem.fromJson(e.toJson())).toList();
    return _serialize(() async {
      final current = {for (final item in await _read()) item.id: item};
      for (final item in snapshots) {
        current[item.id] = item;
      }
      await _write(current.values.toList());
    });
  }
}
