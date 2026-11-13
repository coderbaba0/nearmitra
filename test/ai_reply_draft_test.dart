import 'package:farmitra_nearby/models/ai_reply_draft.dart';
import 'package:farmitra_nearby/models/chat_item.dart';
import 'package:farmitra_nearby/services/history_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  AiReplyDraft draft() => AiReplyDraft(
      peerId: 'desktop',
      sender: 'Phone',
      responder: 'PC AI',
      text: 'Question',
      now: DateTime(2026, 10, 17));

  test('Prompt and reply cannot collide in the same millisecond', () async {
    final first = draft(), second = draft();
    expect({first.prompt.id, first.reply.id, second.prompt.id, second.reply.id},
        hasLength(4));
    final history = HistoryService();
    await history.addItems([first.prompt, first.reply]);
    expect(await history.load(), hasLength(2));
  });

  test(
      'History reload keeps the visible streaming object, not a stale saved copy',
      () async {
    final history = HistoryService(), active = draft();
    await history.addItems([active.prompt, active.reply]);
    final reloaded = await history.load();
    expect(identical(reloaded.last, active.reply), isFalse);
    final visible = active.mergeInto(reloaded);
    active.enqueue('Hello from Ollama');
    while (active.hasPending) {
      active.pump();
    }
    expect(visible.singleWhere((item) => item.id == active.reply.id).text,
        'Hello from Ollama');
    expect(identical(visible.last, active.reply), isTrue);

    final unrelated = ChatItem(
        id: 'file-arrived',
        peerId: 'other-device',
        sender: 'Other',
        mine: false,
        createdAt: DateTime.now(),
        kind: ChatKind.text,
        text: 'Unrelated message');
    await history.addItem(unrelated);
    final afterIncoming = active.mergeInto(await history.load());
    expect(afterIncoming.singleWhere((item) => item.id == active.reply.id).text,
        'Hello from Ollama');
    expect(afterIncoming.any((item) => item.id == unrelated.id), isTrue);
    active.enqueue(' — completed');
    active.flush();
    await history.addItems([active.prompt, active.reply]);
    final saved = await history.load();
    expect(saved.singleWhere((item) => item.id == active.reply.id).text,
        'Hello from Ollama — completed');
    expect(saved.any((item) => item.id == unrelated.id), isTrue);
  });

  test(
      'Cancelled draft cannot reinsert a deleted conversation or append late tokens',
      () async {
    final active = draft();
    active.enqueue('late');
    active.cancel();
    await active.cancelled;
    active.enqueue('more');
    active.flush();
    expect(active.pump(), isFalse);
    expect(active.mergeInto([]), isEmpty);
    expect(active.reply.text, isEmpty);
  });
}
