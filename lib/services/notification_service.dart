import 'dart:async';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  static bool _initializing = false;
  static final Set<String> _sentMatchNotifications = <String>{};
  static Timer? _matchCheckTimer;

  /// Initialize the notification service
  static Future<void> initialize() async {
    if (_initialized) return;
    if (_initializing) {
      _logger.w('⚠️ Notification service already initializing, skipping...');
      return;
    }

    _initializing = true;
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

    try {
      await _notifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      _logger.i('📱 Notification plugin initialized');

      // Request permissions (important for Android 13+)
      await _requestPermissions();

      // Check if notifications are enabled (without sending test)
      final bool? enabled = await areNotificationsEnabled();
      _logger.i('📊 Notifications enabled: $enabled');

      _initialized = true;
      _logger.i('✅ Notification service fully initialized');
    } catch (e) {
      _logger.e('❌ Failed to initialize notifications: $e');
      _initializing = false;
      rethrow;
    } finally {
      _initializing = false;
    }
  }



  /// Request notification permissions (iOS & Android)
  static Future<void> _requestPermissions() async {
    // Request Android permissions (Android 13+)
    final bool? androidResult = await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _logger.d('🤖 Android notification permission: $androidResult');

    // Request iOS permissions
    final bool? iosResult = await _notifications
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

    _logger.d('📱 iOS notification permission: $iosResult');
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
    String? matchId,
  }) async {
    // Create a unique key for this match to prevent duplicates
    final String matchKey = matchId ?? '$matchedUserName:${compatibilityScore.toStringAsFixed(2)}';
    
    if (_sentMatchNotifications.contains(matchKey)) {
      _logger.w('⚠️ Notification for $matchedUserName already sent, skipping duplicate');
      return;
    }

    _logger.i('🔔 Starting match notification process for $matchedUserName');

    if (!_initialized) {
      _logger.w('⚠️ Notification service not initialized, initializing now...');
      await initialize();
    }

    // Check if notifications are enabled
    final bool enabled = await areNotificationsEnabled();
    _logger.i('📊 Notifications enabled: $enabled');

    if (!enabled) {
      _logger.w('⚠️ Notifications are disabled by user or system');
      return;
    }

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
      autoCancel: true,
      ongoing: false,
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
    final String body = 'You matched with $matchedUserName';
    final int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    _logger.i('📤 Attempting to show notification - ID: $notificationId, Title: $title');

    try {
      await _notifications.show(
        notificationId,
        title,
        body,
        notificationDetails,
        payload: 'match:$matchedUserName:$compatibilityScore',
      );

      _logger.i('✅ Match notification sent successfully with ID: $notificationId');
      
      // Mark this match as notified to prevent duplicates
      _sentMatchNotifications.add(matchKey);
      
      // Keep cache size reasonable (max 100 notifications)
      if (_sentMatchNotifications.length > 100) {
        final List<String> toRemove = _sentMatchNotifications.take(50).toList();
        _sentMatchNotifications.removeAll(toRemove);
        _logger.d('🧹 Cleaned notification cache, removed ${toRemove.length} old entries');
      }
      
    } catch (e) {
      _logger.e('❌ Failed to send match notification: $e');
      _logger.e('Stack trace: ${StackTrace.current}');
      rethrow;
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

  /// Start periodic checking for new matches
  static void startPeriodicMatchChecking() {
    _logger.i('🔄 Starting periodic match checking...');
    
    // Cancel existing timer if any
    _matchCheckTimer?.cancel();
    
    // Check every 2 minutes
    _matchCheckTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      checkForNewMatches();
    });
    
    _logger.i('✅ Periodic match checking started (every 2 minutes)');
  }

  /// Stop periodic checking for new matches
  static void stopPeriodicMatchChecking() {
    _logger.i('🛑 Stopping periodic match checking...');
    _matchCheckTimer?.cancel();
    _matchCheckTimer = null;
  }

  /// Check for new matches and send notifications
  static Future<void> checkForNewMatches() async {
    try {
      _logger.i('🔍 Checking for new matches to notify...');
      
      // Import needed dependencies at top of file
      final supabase = Supabase.instance.client;
      final currentUser = supabase.auth.currentUser;
      
      if (currentUser == null) {
        _logger.w('⚠️ No authenticated user, skipping match check');
        return;
      }

      // Get all matches for current user
      final matchesResponse = await supabase.rpc('get_my_matches');
      
      if (matchesResponse == null || matchesResponse.isEmpty) {
        _logger.d('📭 No matches found');
        return;
      }

      final matches = List<Map<String, dynamic>>.from(matchesResponse);
      _logger.i('📬 Found ${matches.length} total matches, checking for new ones...');

      // Check each match to see if we've already notified about it
      for (final match in matches) {
        final matchId = match['id'] as String;
        final createdAt = DateTime.parse(match['matched_at'] as String);
        final now = DateTime.now();
        final timeDiff = now.difference(createdAt);

        // Only notify about matches created in the last 24 hours
        if (timeDiff.inHours > 24) {
          continue;
        }

        // Check if we've already sent a notification for this match
        if (_sentMatchNotifications.contains(matchId)) {
          continue;
        }

        // Get the other user's info
        final currentUserId = currentUser.id;
        final otherUserId = match['user_id_1'] == currentUserId 
            ? match['user_id_2'] 
            : match['user_id_1'];

        // Get other user's profile
        final otherUserResponse = await supabase.rpc('get_user_data', params: {
          'p_user_id': otherUserId,
        });

        if (otherUserResponse != null && otherUserResponse.isNotEmpty) {
          final otherUser = otherUserResponse[0];
          final otherUserName = otherUser['name'] ?? 'Someone';
          final compatibilityScore = (match['compatibility_score'] ?? 0.0).toDouble();
          final reasoning = match['ai_reasoning'] ?? 'You have a new match!';

          _logger.i('🔔 Sending notification for new match with $otherUserName');

          // Send notification with match ID to prevent duplicates
          await sendMatchNotification(
            matchedUserName: otherUserName,
            compatibilityScore: compatibilityScore,
            reasoning: reasoning,
            matchId: matchId,
          );
        }
      }

      _logger.i('✅ Finished checking for new matches');
    } catch (e) {
             _logger.e('❌ Error checking for new matches: $e');
     }
   }
 } 