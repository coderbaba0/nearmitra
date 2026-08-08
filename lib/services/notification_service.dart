import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  factory NotificationService() => _instance;
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  final StreamController<String?> _onNotificationClick = StreamController<String?>.broadcast();
  Stream<String?> get onNotificationClick => _onNotificationClick.stream;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        if (details.payload != null) {
          _onNotificationClick.add(details.payload);
        }
      },
    );

    // Create Notification Channel for Android 8.0+
    const channel = AndroidNotificationChannel(
      'farmitra_nearby_messages',
      'Farmitra Nearby Messages & Files',
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
      'Farmitra Nearby Messages & Files',
      channelDescription: 'Notifications for incoming chat messages and file transfers',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'New message from $senderName',
      styleInformation: BigTextStyleInformation(
        message,
        contentTitle: '💬 $senderName',
        summaryText: 'Farmitra Nearby',
      ),
      icon: '@mipmap/ic_launcher',
    );

    final details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      peerId.hashCode,
      '💬 $senderName',
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
      'Farmitra Nearby Messages & Files',
      channelDescription: 'Notifications for incoming chat messages and file transfers',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'File received from $senderName',
      styleInformation: BigTextStyleInformation(
        'Received: $fileName ($fileSizeText)',
        contentTitle: '📁 File from $senderName',
        summaryText: 'Farmitra Nearby',
      ),
      icon: '@mipmap/ic_launcher',
    );

    final details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      (peerId + fileName).hashCode,
      '📁 File from $senderName',
      'Received $fileName ($fileSizeText)',
      details,
      payload: peerId,
    );
  }
}
