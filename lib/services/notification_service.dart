import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:notification_reply_bridge/notification_reply_bridge.dart';
import 'package:uuid/uuid.dart';
import '../models/notification_target.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse details) async {
  if (details.notificationResponseType ==
          NotificationResponseType.selectedNotificationAction &&
      details.actionId == 'reply_action' &&
      details.input != null &&
      details.input!.trim().isNotEmpty &&
      details.payload != null) {
    try {
      await NotificationService().handleReplyAction(
        peerId: details.payload!,
        text: details.input!.trim(),
        notificationId: details.id,
      );
    } catch (error) {
      // cancelNotification=false keeps the action visible if saving fails.
      debugPrint('[Reply] Could not save notification reply: $error');
    }
  }
}

class NotificationService {
  factory NotificationService() => _instance;
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Future<void>? _initializing;
  final NotificationReplyInbox _replyInbox = AndroidNotificationReplyInbox();

  final StreamController<String?> _onNotificationClick =
      StreamController<String?>.broadcast();
  Stream<String?> get onNotificationClick => _onNotificationClick.stream;

  final StreamController<Map<String, String>> _onNotificationReply =
      StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get onNotificationReply =>
      _onNotificationReply.stream;

  Future<void> handleReplyAction({
    required String peerId,
    required String text,
    int? notificationId,
  }) async {
    if (text.trim().isEmpty) return;
    final target = NotificationTarget.decode(peerId);
    if (target.peerId.trim().isEmpty) return;
    await _replyInbox.save(
        peerId: target.peerId,
        text: text.trim(),
        nonce: target.nonce,
        notificationId: notificationId);
    _onNotificationReply.add({
      'peerId': target.peerId,
      'text': text.trim(),
    });
  }

  Future<void> cancelNotification(int id) async {
    try {
      await _notifications.cancel(id);
    } catch (_) {}
  }

  Future<void> init() {
    if (_initialized) return Future<void>.value();
    return _initializing ??=
        _initialize().whenComplete(() => _initializing = null);
  }

  Future<void> _initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) async {
        if (details.notificationResponseType ==
                NotificationResponseType.selectedNotificationAction &&
            details.actionId == 'reply_action' &&
            details.input != null &&
            details.input!.trim().isNotEmpty &&
            details.payload != null) {
          try {
            await handleReplyAction(
              peerId: details.payload!,
              text: details.input!.trim(),
              notificationId: details.id,
            );
          } catch (error) {
            debugPrint('[Reply] Could not save notification reply: $error');
          }
        } else if (details.payload != null) {
          _onNotificationClick
              .add(NotificationTarget.decode(details.payload!).peerId);
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // Create Notification Channel for Android 8.0+
    const channel = AndroidNotificationChannel(
      'farmitra_nearby_messages',
      'NearMitra Messages & Files',
      description:
          'Notifications for incoming chat messages and file transfers',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(channel);
      // Permission prompts belong to main's foreground UI. A service-only
      // restart has no Activity; requesting here would abort delivery.
    }

    _initialized = true;
  }

  Future<void> showIncomingMessageNotification({
    required String peerId,
    required String senderName,
    required String message,
  }) async {
    await init();

    final nonce = const Uuid().v4();
    final payload = NotificationTarget(peerId, nonce: nonce).encode();
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _replyInbox.registerNotification(peerId.hashCode, nonce);
      } catch (error) {
        // A reply-inbox/storage failure must not hide incoming chat alerts.
        // Without a registered slot, the native reply path will retain the alert.
        debugPrint('[Reply] Notification slot could not be saved: $error');
      }
    }

    final androidDetails = AndroidNotificationDetails(
      'farmitra_nearby_messages',
      'NearMitra Messages & Files',
      channelDescription:
          'Notifications for incoming chat messages and file transfers',
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
          cancelNotification: false,
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
      payload: payload,
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
      channelDescription:
          'Notifications for incoming chat messages and file transfers',
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
