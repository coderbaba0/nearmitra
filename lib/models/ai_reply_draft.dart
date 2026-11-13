import 'dart:async';

import 'package:uuid/uuid.dart';

import 'chat_item.dart';

/// Keeps a streaming answer attached to the visible conversation across saved
/// history reloads. Prompt/reply IDs must differ even within one millisecond.
class AiReplyDraft {
  AiReplyDraft({
    required String peerId,
    required String sender,
    required String responder,
    required String text,
    DateTime? now,
  }) {
    final time = now ?? DateTime.now();
    prompt = ChatItem(
      id: 'ai_prompt_${const Uuid().v4()}',
      peerId: peerId,
      sender: sender,
      mine: true,
      createdAt: time,
      kind: ChatKind.text,
      text: text,
      isAi: true,
    );
    reply = ChatItem(
      id: 'ai_reply_${const Uuid().v4()}',
      peerId: peerId,
      sender: responder,
      mine: false,
      createdAt: time.add(const Duration(microseconds: 1)),
      kind: ChatKind.text,
      text: '',
      isAi: true,
    );
  }

  late final ChatItem prompt;
  late final ChatItem reply;
  final _cancelled = Completer<void>();
  final List<String> _pending = [];

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get cancelled => _cancelled.future;
  bool get hasPending => _pending.isNotEmpty;

  void enqueue(String text) {
    if (!isCancelled) _pending.addAll(text.split(''));
  }

  bool pump() {
    if (isCancelled || _pending.isEmpty) return false;
    final batch = _pending.length > 100 ? 8 : (_pending.length > 40 ? 4 : 2);
    final count = batch < _pending.length ? batch : _pending.length;
    reply.text = (reply.text ?? '') + _pending.take(count).join();
    _pending.removeRange(0, count);
    return true;
  }

  void flush() {
    if (isCancelled) return;
    reply.text = (reply.text ?? '') + _pending.join();
    _pending.clear();
  }

  List<ChatItem> mergeInto(Iterable<ChatItem> saved) {
    final messages = {for (final item in saved) item.id: item};
    if (!isCancelled) {
      messages[prompt.id] = prompt;
      messages[reply.id] = reply;
    }
    return messages.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
    _pending.clear();
  }
}
