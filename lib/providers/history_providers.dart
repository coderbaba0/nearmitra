import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_item.dart';
import '../services/history_service.dart';

/// Provider for the singleton HistoryService
final historyServiceProvider = Provider<HistoryService>((ref) {
  return HistoryService();
});

/// FutureProvider to load activity and chat history reactively
final chatHistoryProvider = FutureProvider<List<ChatItem>>((ref) async {
  final service = ref.watch(historyServiceProvider);
  return service.load();
});
