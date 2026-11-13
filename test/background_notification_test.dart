import 'package:farmitra_nearby/services/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notification_reply_bridge/notification_reply_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Background delivery never attempts an Activity-only permission prompt',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'requestNotificationsPermission') {
        throw PlatformException(code: 'NO_ACTIVITY');
      }
      return call.method == 'initialize' ? true : null;
    });
    messenger.setMockMethodCallHandler(
        AndroidNotificationReplyInbox.channel, (_) async => null);
    try {
      await NotificationService().showIncomingMessageNotification(
          peerId: 'other-phone',
          senderName: 'Other Phone',
          message: 'Background message');
      expect(calls.where((c) => c.method == 'requestNotificationsPermission'),
          isEmpty);
      expect(calls.where((c) => c.method == 'show'), hasLength(1));
      final shown =
          calls.singleWhere((c) => c.method == 'show').arguments as Map;
      final actions = (shown['platformSpecifics'] as Map)['actions'] as List;
      expect((actions.single as Map)['cancelNotification'], isFalse);
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(
          AndroidNotificationReplyInbox.channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
