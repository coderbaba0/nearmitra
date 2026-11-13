import 'package:flutter/services.dart';

class PendingNotificationReply {
  const PendingNotificationReply(
      {required this.id,
      required this.peerId,
      required this.text,
      required this.createdAt});
  final String id, peerId, text;
  final DateTime createdAt;
  factory PendingNotificationReply.fromMap(Map<dynamic, dynamic> value) =>
      PendingNotificationReply(
          id: value['id'] as String,
          peerId: value['peerId'] as String,
          text: value['text'] as String,
          createdAt:
              DateTime.fromMillisecondsSinceEpoch(value['createdAt'] as int));
}

abstract class NotificationReplyInbox {
  Stream<void> get changes;
  Future<void> registerNotification(int id, String nonce);
  Future<void> save(
      {required String peerId,
      required String text,
      String? nonce,
      int? notificationId});
  Future<List<PendingNotificationReply>> pending();
  Future<void> acknowledge(String id);
}

/// Registered in every FlutterEngine, including the notifications plugin's
/// background engine. SQLite is shared; Dart preference caches are never used.
class AndroidNotificationReplyInbox implements NotificationReplyInbox {
  static const channel = MethodChannel('farmitra_nearby/notification_replies');
  static const events =
      EventChannel('farmitra_nearby/notification_reply_events');
  @override
  Stream<void> get changes => events.receiveBroadcastStream().map((_) {});
  @override
  Future<void> registerNotification(int id, String nonce) => channel
      .invokeMethod<void>('registerNotification', {'id': id, 'nonce': nonce});
  @override
  Future<void> save(
          {required String peerId,
          required String text,
          String? nonce,
          int? notificationId}) =>
      channel.invokeMethod<void>('save', {
        'peerId': peerId,
        'text': text,
        'nonce': nonce,
        'notificationId': notificationId
      });
  @override
  Future<List<PendingNotificationReply>> pending() async =>
      ((await channel.invokeListMethod<dynamic>('pending')) ?? [])
          .map((e) => PendingNotificationReply.fromMap(e as Map))
          .toList();
  @override
  Future<void> acknowledge(String id) =>
      channel.invokeMethod<void>('acknowledge', {'id': id});
}
