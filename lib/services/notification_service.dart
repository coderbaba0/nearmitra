import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse details) {
  if (details.notificationResponseType == NotificationResponseType.selectedNotificationAction &&
      details.actionId == 'reply_action' &&
      details.input != null &&
      details.input!.trim().isNotEmpty &&
      details.payload != null) {
    NotificationService().handleReplyAction(
      peerId: details.payload!,
      text: details.input!.trim(),
      notificationId: details.id,
    );
  }
}

class NotificationService {
  factory NotificationService() => _instance;
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  final StreamController<String?> _onNotificationClick = StreamController<String?>.broadcast();
  Stream<String?> get onNotificationClick => _onNotificationClick.stream;

  final StreamController<Map<String, String>> _onNotificationReply = StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get onNotificationReply => _onNotificationReply.stream;

  Future<void> handleReplyAction({
    required String peerId,
    required String text,
    int? notificationId,
  }) async {
    if (notificationId != null) {
      try {
        await _notifications.cancel(notificationId);
      } catch (e) {
        debugPrint('[NotificationService] Failed to cancel notification: $e');
      }
    }
    _onNotificationReply.add({
      'peerId': peerId,
      'text': text,
    });
  }

  Future<void> cancelNotification(int id) async {
    try {
      await _notifications.cancel(id);
    } catch (_) {}
  }

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        if (details.notificationResponseType == NotificationResponseType.selectedNotificationAction &&
            details.actionId == 'reply_action' &&
            details.input != null &&
            details.input!.trim().isNotEmpty &&
            details.payload != null) {
          handleReplyAction(
            peerId: details.payload!,
            text: details.input!.trim(),
            notificationId: details.id,
          );
        } else if (details.payload != null) {
          _onNotificationClick.add(details.payload);
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // Create Notification Channel for Android 8.0+
    const channel = AndroidNotificationChannel(
      'farmitra_nearby_messages',
      'NearMitra Messages & Files',
      description: 'Notifications for incoming chat messages and file transfers',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(channel);
      await androidPlugin.requestNotificationsPermission();
    }

    _initialized = true;
  }

  Future<void> showIncomingMessageNotification({
    required String peerId,
    required String senderName,
    required String message,
  }) async {
    await init();

    final androidDetails = AndroidNotificationDetails(
      'farmitra_nearby_messages',
      'NearMitra Messages & Files',
      channelDescription: 'Notifications for incoming chat messages and file transfers',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'New message from $senderName',
      styleInformation: BigTextStyleInformation(
        message,
        contentTitle: senderName,
        summaryText: 'NearMitra',
      ),
      icon: '@mipmap/ic_launcher',
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'reply_action',
          'Reply',
          inputs: <AndroidNotificationActionInput>[
            AndroidNotificationActionInput(
              label: 'Type a reply…',
            ),
          ],
        ),
      ],
    );

    final details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      peerId.hashCode,
      senderName,
      message,
      details,
      payload: peerId,
    );
  }

  Future<void> showIncomingFileNotification({
    required String peerId,
    required String senderName,
    required String fileName,
    required String fileSizeText,
  }) async {
    await init();

    final androidDetails = AndroidNotificationDetails(
      'farmitra_nearby_messages',
      'NearMitra Messages & Files',
      channelDescription: 'Notifications for incoming chat messages and file transfers',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'File received from $senderName',
      styleInformation: BigTextStyleInformation(
        'Received: $fileName ($fileSizeText)',
        contentTitle: 'File from $senderName',
        summaryText: 'NearMitra',
      ),
      icon: '@mipmap/ic_launcher',
    );

    final details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      (peerId + fileName).hashCode,
      'File from $senderName',
      'Received $fileName ($fileSizeText)',
      details,
      payload: peerId,
    );
  }
}
