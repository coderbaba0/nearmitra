import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmitra_nearby/widgets/ai_assistant_button.dart';

void main() {
  testWidgets('Home AI action stays idle and keeps its click working',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            floatingActionButton: AiAssistantButton(onPressed: () => taps++))));
    await tester.pumpAndSettle();
    final button =
        tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.hasRunningAnimations, isFalse);
    expect(
        tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)),
        same(button));
    await tester.tap(find.byTooltip('My AI Assistant'));
    expect(taps, 1);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });
}
