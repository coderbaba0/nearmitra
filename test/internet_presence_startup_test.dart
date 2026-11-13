import 'dart:async';

import 'package:farmitra_nearby/services/internet_presence_startup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('App startup restores presence without opening a WAN screen', () async {
    final calls = <String>[];
    final startup = InternetPresenceStartup(
      initialize: () async => calls.add('firebase'),
      restoreMode: () async => calls.add('restore'),
      onError: (error) => fail('$error'),
    );
    addTearDown(startup.dispose);
    await startup.ensureStarted();
    expect(calls, ['firebase', 'restore']);
  });

  testWidgets('Initialization failure retries in background without a tab change', (tester) async {
    var attempts = 0, restores = 0;
    final errors = <Object>[];
    final startup = InternetPresenceStartup(
      initialize: () async { if (++attempts == 1) throw StateError('not ready'); },
      restoreMode: () async { restores++; },
      onError: errors.add,
    );
    addTearDown(startup.dispose);
    await startup.ensureStarted();
    expect(restores, 0);
    await tester.pump(const Duration(seconds: 15));
    expect(attempts, 2);
    expect(restores, 1);
    expect(errors, hasLength(1));
  });

  test('Startup and resume share an in-flight attempt', () async {
    final ready = Completer<void>();
    var initializes = 0, restores = 0;
    final startup = InternetPresenceStartup(
      initialize: () { initializes++; return ready.future; },
      restoreMode: () async { restores++; },
      onError: (error) => fail('$error'),
    );
    addTearDown(startup.dispose);
    final first = startup.ensureStarted(), resumed = startup.ensureStarted();
    expect(initializes, 1);
    ready.complete();
    await Future.wait([first, resumed]);
    expect(restores, 1);
  });

  testWidgets('Failed mode restore retries, but disposal cancels future retries', (tester) async {
    var attempts = 0;
    final startup = InternetPresenceStartup(
      initialize: () async {},
      restoreMode: () async { attempts++; throw StateError('listener startup failed'); },
      onError: (_) {},
    );
    await startup.ensureStarted();
    await tester.pump(const Duration(seconds: 15));
    expect(attempts, 2);
    startup.dispose();
    await tester.pump(const Duration(seconds: 30));
    expect(attempts, 2);
  });
}
