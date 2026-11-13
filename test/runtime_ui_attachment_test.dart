import 'dart:async';

import 'package:farmitra_nearby/services/runtime_ui_attachment.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('farmitra_nearby/runtime');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> attachActivity() {
    final complete = Completer<void>();
    messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('attachUi')),
        (_) => complete.complete());
    return complete.future;
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });

  test('A service-only restart does not build UI until Activity attaches',
      () async {
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    var mounts = 0;
    final ui = RuntimeUiAttachment(mount: () => mounts++);
    await ui.attach(backgroundStartup: true);
    expect(mounts, 0);
    await attachActivity();
    expect(mounts, 1);
    await attachActivity();
    expect(mounts, 1);
  });

  test('An Activity opening before Dart is ready still gets its UI', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => true);
    var mounts = 0;
    final ui = RuntimeUiAttachment(mount: () => mounts++);
    await ui.attach(backgroundStartup: true);
    expect(mounts, 1);
    await attachActivity();
    expect(mounts, 1);
  });

  test('An ordinary foreground launch mounts immediately without native query',
      () async {
    var queried = false;
    messenger.setMockMethodCallHandler(channel, (_) async {
      queried = true;
      return false;
    });
    var mounts = 0;
    await RuntimeUiAttachment(mount: () => mounts++)
        .attach(backgroundStartup: false);
    expect(mounts, 1);
    expect(queried, isFalse);
  });
}
