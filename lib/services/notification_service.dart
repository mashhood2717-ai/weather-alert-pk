// lib/services/notification_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart' show Color, GlobalKey, NavigatorState;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/weather_alert.dart';
import 'alert_storage_service.dart';

// Global navigator key for navigation from notification
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase must be initialized in background isolate
  // Firebase is auto-initialized by FlutterFire, but we ensure it's ready
  print('Background message received: ${message.messageId}');
  print('Background notification title: ${message.notification?.title}');
  print('Background notification body: ${message.notification?.body}');

  // For data-only messages, we handle them here
  // For notification messages (with title/body), Android shows them automatically
  if (message.notification == null && message.data.isNotEmpty) {
    // This is a data-only message, save it
    await _saveAlertFromMessage(message);
  }
}

Future<void> _saveAlertFromMessage(RemoteMessage message) async {
  final alert = WeatherAlert(
    id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
    title: message.notification?.title ?? 'Weather Alert',
    body: message.notification?.body ?? '',
    city: message.data['city'],
    severity: message.data['severity'],
    receivedAt: DateTime.now(),
    data: message.data,
  );
  await AlertStorageService().saveAlert(alert);
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Notification channels for different severity levels
  static const AndroidNotificationChannel _channelHigh =
      AndroidNotificationChannel(
    'weather_alerts_high',
    'Severe Weather Alerts',
    description: 'Critical and severe weather alerts',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    enableLights: true,
    ledColor: Color(0xFFFF0000),
  );

  static const AndroidNotificationChannel _channelMedium =
      AndroidNotificationChannel(
    'weather_alerts_medium',
    'Weather Warnings',
    description: 'Medium priority weather warnings',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _channelLow =
      AndroidNotificationChannel(
    'weather_alerts_low',
    'Weather Updates',
    description: 'Low priority weather updates',
    importance: Importance.defaultImportance,
    playSound: true,
    enableVibration: false,
  );

  // Default channel for backward compatibility
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'weather_alerts_channel',
    'Weather Alerts',
    description: 'Severe weather alerts for Pakistan',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  // Prayer notification channel with azan sound
  // Note: For custom sound, place azan.mp3 in android/app/src/main/res/raw/
  static const AndroidNotificationChannel _prayerChannel =
      AndroidNotificationChannel(
    'prayer_notifications_v2', // Changed channel ID to force new channel creation
    'Prayer Time Azan',
    description: 'Prayer time notifications with azan sound',
    importance: Importance.max, // Max importance for prayer notifications
    playSound: true,
    enableVibration: true,
    enableLights: true,
    ledColor: Color(0xFF4CAF50),
    // Custom sound will be set in AndroidNotificationDetails
  );

  // Silent prayer reminder channel (for X minutes before)
  static const AndroidNotificationChannel _prayerReminderChannel =
      AndroidNotificationChannel(
    'prayer_reminders',
    'Prayer Reminders',
    description: 'Reminders before prayer time',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  Future<void> initialize() async {
    // Request permission
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    print('FCM Permission: ${settings.authorizationStatus}');

    // Initialize local notifications for Android
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create notification channel on Android
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(_channel);
      await androidPlugin.createNotificationChannel(_channelHigh);
      await androidPlugin.createNotificationChannel(_channelMedium);
      await androidPlugin.createNotificationChannel(_channelLow);
      await androidPlugin.createNotificationChannel(_prayerChannel);
      await androidPlugin.createNotificationChannel(_prayerReminderChannel);
    }

    // Initialize timezone for scheduled notifications
    tz_data.initializeTimeZones();
    // Set local timezone to Pakistan (Asia/Karachi) - required before using tz.local
    tz.setLocalLocation(tz.getLocation('Asia/Karachi'));

    // Get FCM token and save to Firestore
    String? token = await _messaging.getToken();
    print('FCM Token: $token');

    // Save FCM token to Firestore for push notifications when app is closed
    if (token != null) {
      await _saveFcmToken(token);
    }

    // Listen for token refresh
    _messaging.onTokenRefresh.listen((newToken) async {
      print('FCM Token refreshed: $newToken');
      await _saveFcmToken(newToken);
    });

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);

    // Check if app was opened from a notification
    RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationOpen(initialMessage);
    }

    // Subscribe to weather alert topics
    await subscribeToAlerts();

    _isInitialized = true;
  }

  /// Save FCM token to Firestore for push notifications when app is closed
  Future<void> _saveFcmToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString('device_id');

      if (deviceId == null) {
        // Generate device ID if not exists
        deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
        await prefs.setString('device_id', deviceId);
      }

      // Save token to user_locations collection (same doc used by ManualAlertService)
      await FirebaseFirestore.instance
          .collection('user_locations')
          .doc(deviceId)
          .set({
        'fcmToken': token,
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
        'platform': 'android',
      }, SetOptions(merge: true));

      print('FCM token saved to Firestore for device: $deviceId');
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }

  Future<void> subscribeToAlerts() async {
    // Subscribe to general weather alerts
    await _messaging.subscribeToTopic('weather_alerts_pk');

    // Subscribe to city-specific topics (can be dynamic based on user preference)
    await _messaging.subscribeToTopic('alerts_islamabad');
    await _messaging.subscribeToTopic('alerts_lahore');
    await _messaging.subscribeToTopic('alerts_karachi');

    print('Subscribed to weather alert topics');
  }

  Future<void> subscribeToCity(String city) async {
    final topic = 'alerts_${city.toLowerCase().replaceAll(' ', '_')}';
    await _messaging.subscribeToTopic(topic);
    print('Subscribed to $topic');
  }

  Future<void> unsubscribeFromCity(String city) async {
    final topic = 'alerts_${city.toLowerCase().replaceAll(' ', '_')}';
    await _messaging.unsubscribeFromTopic(topic);
    print('Unsubscribed from $topic');
  }

  void _handleForegroundMessage(RemoteMessage message) async {
    print('Foreground message: ${message.notification?.title}');

    // Save to local storage
    await _saveAlertFromMessage(message);

    RemoteNotification? notification = message.notification;
    if (notification != null) {
      final severity = message.data['severity'] ?? 'medium';
      _showLocalNotification(
        title: notification.title ?? 'Weather Alert',
        body: notification.body ?? 'Check weather conditions',
        payload: jsonEncode(message.data),
        severity: severity,
      );
    }
  }

  void _handleNotificationOpen(RemoteMessage message) {
    print('Notification opened: ${message.data}');
    // Navigate to alerts screen
    navigatorKey.currentState?.pushNamed('/alerts');
  }

  void _onNotificationTap(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
    // Navigate to alerts screen when notification is tapped
    navigatorKey.currentState?.pushNamed('/alerts');
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
    String severity = 'medium',
  }) async {
    // Select channel based on severity
    final AndroidNotificationChannel channel;
    final Priority priority;

    switch (severity.toLowerCase()) {
      case 'extreme':
      case 'high':
        channel = _channelHigh;
        priority = Priority.max;
        break;
      case 'medium':
        channel = _channelMedium;
        priority = Priority.high;
        break;
      case 'low':
      default:
        channel = _channelLow;
        priority = Priority.defaultPriority;
    }

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: priority,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFF2196F3),
          enableVibration: channel.enableVibration,
          playSound: channel.playSound,
        ),
      ),
      payload: payload,
    );
  }

  /// Public method to show weather alert notification (used by local monitor)
  Future<void> showWeatherAlert({
    required String title,
    required String body,
    String severity = 'medium',
    String? payload,
  }) async {
    await _showLocalNotification(
      title: title,
      body: body,
      severity: severity,
      payload: payload,
    );
  }

  // Get current FCM token
  Future<String?> getToken() async {
    return await _messaging.getToken();
  }

  // ==================== Prayer Notifications ====================

  /// Ensure timezone is initialized (can be called multiple times safely)
  void _ensureTimezoneInitialized() {
    try {
      // Try to access local - if it throws, timezone isn't set
      tz.local;
    } catch (e) {
      // Initialize timezone if not already done
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Karachi'));
    }
  }

  /// Schedule a prayer notification with sound and vibration
  Future<void> schedulePrayerNotification({
    required int id,
    required String prayerName,
    required DateTime scheduledTime,
    int minutesBefore = 0,
  }) async {
    // Ensure timezone is initialized
    _ensureTimezoneInitialized();

    // Calculate the actual notification time
    final notificationTime =
        scheduledTime.subtract(Duration(minutes: minutesBefore));

    // Don't schedule if the time has already passed
    if (notificationTime.isBefore(DateTime.now())) {
      print(
          'Prayer notification skipped (past time): $prayerName at $scheduledTime');
      return;
    }

    final tzNotificationTime = tz.TZDateTime.from(notificationTime, tz.local);

    // Different title/body for reminder vs actual prayer time
    final bool isReminder = minutesBefore > 0;
    final title = isReminder
        ? '$prayerName in $minutesBefore minutes'
        : '🕌 $prayerName Time';
    final body = isReminder
        ? 'Prepare for $prayerName prayer'
        : 'Allahu Akbar - It\'s time for $prayerName prayer';

    // Use different channels for prayer time vs reminder
    final channelId =
        isReminder ? _prayerReminderChannel.id : _prayerChannel.id;
    final channelName =
        isReminder ? _prayerReminderChannel.name : _prayerChannel.name;
    final channelDesc = isReminder
        ? _prayerReminderChannel.description
        : _prayerChannel.description;

    // Strong vibration pattern for prayer time: wait, vibrate, wait, vibrate...
    final vibrationPattern = isReminder
        ? Int64List.fromList([0, 250, 250, 250]) // Short pattern for reminder
        : Int64List.fromList(
            [0, 500, 200, 500, 200, 500, 200, 500]); // Long pattern for azan

    try {
      await _localNotifications.zonedSchedule(
        id,
        title,
        body,
        tzNotificationTime,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDesc,
            importance: isReminder ? Importance.high : Importance.max,
            priority: Priority.max,
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFF4CAF50),
            enableVibration: true,
            vibrationPattern: vibrationPattern,
            playSound: true,
            // Use custom sound if available (azan.mp3 in res/raw/)
            // sound: isReminder ? null : const RawResourceAndroidNotificationSound('azan'),
            fullScreenIntent: !isReminder, // Full screen for prayer time
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            ticker: title,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: null,
        payload: 'prayer_$prayerName',
      );
      print(
          'Prayer notification scheduled: $prayerName at $tzNotificationTime (ID: $id)');
    } catch (e) {
      print('Error scheduling prayer notification: $e');
    }
  }

  /// Cancel a specific prayer notification
  Future<void> cancelPrayerNotification(int id) async {
    await _localNotifications.cancel(id);
  }

  /// Cancel all prayer notifications
  Future<void> cancelAllPrayerNotifications() async {
    // Prayer notification IDs start from 1000
    for (int i = 1000; i < 1020; i++) {
      await _localNotifications.cancel(i);
    }
    print('All prayer notifications cancelled');
  }

  /// Schedule all prayer notifications for today
  Future<void> scheduleAllPrayerNotifications({
    required Map<String, DateTime> prayerTimes,
    required Map<String, bool> enabledPrayers,
    int minutesBefore = 5,
  }) async {
    print('Scheduling prayer notifications...');
    print('Prayer times: $prayerTimes');
    print('Enabled prayers: $enabledPrayers');

    // Cancel existing prayer notifications first
    await cancelAllPrayerNotifications();

    int id = 1000;
    int scheduledCount = 0;

    for (final entry in prayerTimes.entries) {
      final prayerName = entry.key;
      final prayerTime = entry.value;

      // Skip if this prayer notification is disabled
      if (enabledPrayers[prayerName] != true) {
        print('Skipping $prayerName - notifications disabled');
        continue;
      }

      // Schedule notification at prayer time
      await schedulePrayerNotification(
        id: id,
        prayerName: prayerName,
        scheduledTime: prayerTime,
        minutesBefore: 0,
      );
      scheduledCount++;

      // Also schedule a reminder before prayer time
      if (minutesBefore > 0) {
        await schedulePrayerNotification(
          id: id + 5, // Offset ID for reminder
          prayerName: prayerName,
          scheduledTime: prayerTime,
          minutesBefore: minutesBefore,
        );
        scheduledCount++;
      }

      id++;
    }

    print('Scheduled $scheduledCount prayer notifications');
  }

  /// Show an immediate prayer notification (for testing)
  Future<void> showImmediatePrayerNotification(String prayerName) async {
    final vibrationPattern =
        Int64List.fromList([0, 500, 200, 500, 200, 500, 200, 500]);

    await _localNotifications.show(
      999, // Test notification ID
      '🕌 $prayerName Time',
      'Allahu Akbar - It\'s time for $prayerName prayer',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _prayerChannel.id,
          _prayerChannel.name,
          channelDescription: _prayerChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFF4CAF50),
          enableVibration: true,
          vibrationPattern: vibrationPattern,
          playSound: true,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
        ),
      ),
      payload: 'prayer_$prayerName',
    );
    print('Immediate prayer notification shown for $prayerName');
  }
}
