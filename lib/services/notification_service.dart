import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';

class NotificationService {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  static final FlutterLocalNotificationsPlugin _notifications = 
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Initialize the notification service
  static Future<void> initialize() async {
    if (_initialized) return;

    _logger.i('🔔 Initializing notification service...');

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
      macOS: initializationSettingsIOS,
    );

    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Request permissions for iOS
    await _requestPermissions();

    _initialized = true;
    _logger.i('✅ Notification service initialized');
  }

  /// Request notification permissions (iOS)
  static Future<void> _requestPermissions() async {
    final bool? result = await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

    final bool? macResult = await _notifications
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

    _logger.d('📱 iOS notification permission: $result');
    _logger.d('💻 macOS notification permission: $macResult');
  }

  /// Handle notification tap
  static void _onNotificationTapped(NotificationResponse details) {
    _logger.i('🔔 Notification tapped: ${details.payload}');
    // You can add navigation logic here if needed
  }

  /// Send a match notification
  static Future<void> sendMatchNotification({
    required String matchedUserName,
    required double compatibilityScore,
    required String reasoning,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    _logger.i('🔔 Sending match notification for $matchedUserName');

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'matches_channel',
      'Match Notifications',
      channelDescription: 'Notifications for new matches found nearby',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'New Match Found!',
      icon: '@mipmap/ic_launcher',
      color: Color(0xFF6750A4), // Material 3 primary color
      showWhen: true,
      when: null,
      enableVibration: true,
      enableLights: true,
      ledColor: Color(0xFF6750A4),
      ledOnMs: 1000,
      ledOffMs: 500,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
      badgeNumber: 1,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    final String title = '🎉 New Match Found!';
    final String body = 'You matched with $matchedUserName (${(compatibilityScore * 100).toStringAsFixed(0)}% compatible)';

    try {
      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000, // Unique ID
        title,
        body,
        notificationDetails,
        payload: 'match:$matchedUserName:$compatibilityScore',
      );

      _logger.i('✅ Match notification sent successfully');
    } catch (e) {
      _logger.e('❌ Failed to send match notification: $e');
    }
  }

  /// Send a general notification
  static Future<void> sendNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'general_channel',
      'General Notifications',
      channelDescription: 'General app notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    try {
      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000, // Unique ID
        title,
        body,
        notificationDetails,
        payload: payload,
      );

      _logger.i('✅ Notification sent: $title');
    } catch (e) {
      _logger.e('❌ Failed to send notification: $e');
    }
  }

  /// Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
    _logger.i('🔕 All notifications cancelled');
  }

  /// Check if notifications are enabled
  static Future<bool> areNotificationsEnabled() async {
    if (!_initialized) return false;

    final bool? result = await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.areNotificationsEnabled();

    return result ?? false;
  }
} 