// lib/services/notification_service.dart

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:flutter/material.dart' show Color, GlobalKey, NavigatorState;
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:device_info_plus/device_info_plus.dart';
import '../models/weather_alert.dart';
import 'alert_storage_service.dart';
import 'prayer_service.dart'; // For PrayerNotificationMode enum

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
  // IMPORTANT: Channel sound is set at channel creation time and cached by Android.
  // If you change the sound, you must change the channel ID or uninstall the app.
  static const AndroidNotificationChannel _prayerChannel =
      AndroidNotificationChannel(
    'prayer_azan_v4', // Changed channel ID to force new channel with azan sound
    'Prayer Time Azan',
    description: 'Prayer time notifications with azan sound',
    importance: Importance.max, // Max importance for prayer notifications
    playSound: true,
    enableVibration: true,
    enableLights: true,
    ledColor: Color(0xFF4CAF50),
    sound: RawResourceAndroidNotificationSound(
        'azan'), // Set sound at channel level
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

    // Check and request exact alarm permission on Android 12+ (non-blocking)
    try {
      await _checkExactAlarmPermission();
    } catch (e) {
      print('⚠️ Exact alarm permission check failed: $e');
      // Continue initialization even if this fails
    }

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
    // NOTE: Do NOT subscribe to weather_alerts_pk topic
    // That topic is only used as fallback and would bypass polygon/radius targeting
    // Only subscribe to city-specific topics based on user preference

    // Unsubscribe from general topic if previously subscribed
    await _messaging.unsubscribeFromTopic('weather_alerts_pk');

    // Subscribe to city-specific topics (can be dynamic based on user preference)
    await _messaging.subscribeToTopic('alerts_islamabad');
    await _messaging.subscribeToTopic('alerts_lahore');
    await _messaging.subscribeToTopic('alerts_karachi');

    print('Subscribed to weather alert topics (city-specific only)');
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
    PrayerNotificationMode mode = PrayerNotificationMode.azan,
  }) async {
    // Skip if mode is off
    if (mode == PrayerNotificationMode.off) {
      print('Prayer notification skipped (mode off): $prayerName');
      return;
    }

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

    // Vibration pattern based on mode
    final bool useVibration = mode == PrayerNotificationMode.vibrationOnly ||
        mode == PrayerNotificationMode.azan;
    final vibrationPattern = isReminder
        ? Int64List.fromList([0, 250, 250, 250]) // Short pattern for reminder
        : Int64List.fromList(
            [0, 500, 200, 500, 200, 500, 200, 500]); // Long pattern for azan

    // Sound based on mode - use azan.mp3 only for azan mode
    final bool useSound = mode == PrayerNotificationMode.azan;
    final AndroidNotificationSound? sound = (useSound && !isReminder)
        ? const RawResourceAndroidNotificationSound('azan')
        : null;

    // Check if we can use exact alarms, otherwise use inexact
    final canScheduleExact = await canScheduleExactAlarms();
    final scheduleMode = canScheduleExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

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
            enableVibration: useVibration,
            vibrationPattern: useVibration ? vibrationPattern : null,
            playSound: useSound,
            sound: sound,
            fullScreenIntent: !isReminder, // Full screen for prayer time
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            ticker: title,
          ),
        ),
        androidScheduleMode: scheduleMode,
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

  /// Check and request exact alarm permission on Android 12+
  Future<bool> _checkExactAlarmPermission() async {
    if (!Platform.isAndroid) return true;

    try {
      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin == null) return false;

      // Check Android version
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      print('📱 Android SDK: $sdkInt');

      // Android 12 (API 31) and above requires explicit exact alarm permission
      if (sdkInt >= 31) {
        final canSchedule = await androidPlugin.canScheduleExactNotifications();
        print('🔔 Can schedule exact alarms: $canSchedule');

        if (canSchedule != true) {
          // Request exact alarm permission
          print('⚠️ Requesting exact alarm permission...');
          final granted = await androidPlugin.requestExactAlarmsPermission();
          print('🔔 Exact alarm permission granted: $granted');
          return granted ?? false;
        }
        return true;
      }
      return true;
    } catch (e) {
      print('Error checking exact alarm permission: $e');
      return false;
    }
  }

  /// Check if exact alarms can be scheduled
  Future<bool> canScheduleExactAlarms() async {
    if (!Platform.isAndroid) return true;
    try {
      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin == null) return false;
      return await androidPlugin.canScheduleExactNotifications() ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Open exact alarm settings (Android 12+)
  Future<void> openExactAlarmSettings() async {
    if (!Platform.isAndroid) return;
    try {
      const platform = MethodChannel('com.mashhood.weatheralert/settings');
      await platform.invokeMethod('openExactAlarmSettings');
    } catch (e) {
      print('Error opening exact alarm settings: $e');
      // Fallback: try to open app settings
      try {
        const platform = MethodChannel('com.mashhood.weatheralert/settings');
        await platform.invokeMethod('openAppSettings');
      } catch (_) {}
    }
  }

  /// Open battery optimization settings (for OnePlus/Oppo/Xiaomi phones)
  Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      const platform = MethodChannel('com.mashhood.weatheralert/settings');
      await platform.invokeMethod('openBatteryOptimizationSettings');
    } catch (e) {
      print('Error opening battery optimization settings: $e');
      // Fallback: try to open app settings
      try {
        const platform = MethodChannel('com.mashhood.weatheralert/settings');
        await platform.invokeMethod('openAppSettings');
      } catch (_) {}
    }
  }

  /// Get list of pending notifications (for debugging)
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _localNotifications.pendingNotificationRequests();
  }

  /// Cancel all prayer notifications
  Future<void> cancelAllPrayerNotifications() async {
    // Prayer notification IDs:
    // Today: 1000-1009 (prayers), 1005-1014 (reminders)
    // Tomorrow: 1020-1029 (prayers), 1030-1039 (reminders)
    for (int i = 1000; i < 1040; i++) {
      await _localNotifications.cancel(i);
    }
    print('All prayer notifications cancelled');
  }

  /// Schedule all prayer notifications for today
  Future<void> scheduleAllPrayerNotifications({
    required Map<String, DateTime> prayerTimes,
    required Map<String, PrayerNotificationMode> prayerModes,
    int minutesBefore = 5,
  }) async {
    print('Scheduling prayer notifications...');
    print('Prayer times: $prayerTimes');
    print('Prayer modes: $prayerModes');

    // Cancel existing prayer notifications first
    await cancelAllPrayerNotifications();

    int id = 1000;
    int scheduledCount = 0;

    for (final entry in prayerTimes.entries) {
      final prayerName = entry.key;
      final prayerTime = entry.value;
      final mode = prayerModes[prayerName] ?? PrayerNotificationMode.azan;

      // Skip if this prayer notification is off
      if (mode == PrayerNotificationMode.off) {
        print('Skipping $prayerName - notifications off');
        id++;
        continue;
      }

      // Schedule notification at prayer time
      await schedulePrayerNotification(
        id: id,
        prayerName: prayerName,
        scheduledTime: prayerTime,
        minutesBefore: 0,
        mode: mode,
      );
      scheduledCount++;

      // Also schedule a reminder before prayer time (always vibration only)
      if (minutesBefore > 0) {
        await schedulePrayerNotification(
          id: id + 5, // Offset ID for reminder
          prayerName: prayerName,
          scheduledTime: prayerTime,
          minutesBefore: minutesBefore,
          mode: PrayerNotificationMode
              .vibrationOnly, // Reminders always vibration only
        );
        scheduledCount++;
      }

      id++;
    }

    print('Scheduled $scheduledCount prayer notifications for today');
  }

  /// Schedule tomorrow's prayer notifications (with offset IDs to avoid conflicts)
  Future<void> scheduleTomorrowPrayerNotifications({
    required Map<String, DateTime> prayerTimes,
    required Map<String, PrayerNotificationMode> prayerModes,
    int minutesBefore = 5,
  }) async {
    print('Scheduling tomorrow\'s prayer notifications...');

    int id =
        1020; // Start from 1020 for tomorrow's prayers (today uses 1000-1019)
    int scheduledCount = 0;

    for (final entry in prayerTimes.entries) {
      // Prayer name has "_tomorrow" suffix, remove it for mode lookup
      final fullName = entry.key;
      final prayerName = fullName.replaceAll('_tomorrow', '');
      final prayerTime = entry.value;
      final mode = prayerModes[prayerName] ?? PrayerNotificationMode.azan;

      // Skip if this prayer notification is off
      if (mode == PrayerNotificationMode.off) {
        print('Skipping tomorrow $prayerName - notifications off');
        id++;
        continue;
      }

      // Schedule notification at prayer time
      await schedulePrayerNotification(
        id: id,
        prayerName: prayerName,
        scheduledTime: prayerTime,
        minutesBefore: 0,
        mode: mode,
      );
      scheduledCount++;

      // Also schedule a reminder before prayer time
      if (minutesBefore > 0) {
        await schedulePrayerNotification(
          id: id + 10, // Offset ID for tomorrow's reminder
          prayerName: prayerName,
          scheduledTime: prayerTime,
          minutesBefore: minutesBefore,
          mode: PrayerNotificationMode.vibrationOnly,
        );
        scheduledCount++;
      }

      id++;
    }

    print('Scheduled $scheduledCount prayer notifications for tomorrow');
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
          sound: const RawResourceAndroidNotificationSound('azan'),
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
        ),
      ),
      payload: 'prayer_$prayerName',
    );
    print('Immediate prayer notification shown for $prayerName');
  }

  /// Schedule a test prayer notification for 30 seconds from now (for testing)
  Future<void> scheduleTestPrayerNotification() async {
    _ensureTimezoneInitialized();

    // First check exact alarm permission
    final canScheduleExact = await canScheduleExactAlarms();
    print('📱 Can schedule exact alarms: $canScheduleExact');

    final scheduledTime = DateTime.now().add(const Duration(seconds: 30));
    final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

    final vibrationPattern =
        Int64List.fromList([0, 500, 200, 500, 200, 500, 200, 500]);

    // Use inexact if exact alarms not available
    final scheduleMode = canScheduleExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    print('📅 Using schedule mode: $scheduleMode');
    print('📅 Current time: ${DateTime.now()}');
    print('📅 Target time: $tzScheduledTime');
    print('📅 Timezone: ${tz.local.name}');

    try {
      await _localNotifications.zonedSchedule(
        998, // Test scheduled notification ID
        '🕌 Test Prayer Time',
        'Allahu Akbar - This is a scheduled test notification',
        tzScheduledTime,
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
            sound: const RawResourceAndroidNotificationSound('azan'),
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
          ),
        ),
        androidScheduleMode: scheduleMode,
        matchDateTimeComponents: null,
        payload: 'prayer_test',
      );
      print(
          '✅ Test prayer notification scheduled for $tzScheduledTime (30 seconds from now)');

      // Check pending notifications
      final pending = await getPendingNotifications();
      print('📋 Pending notifications count: ${pending.length}');
      final testNotification = pending.where((n) => n.id == 998).toList();
      if (testNotification.isNotEmpty) {
        print('✅ Test notification (ID 998) is in pending list');
        for (final n in testNotification) {
          print('   - Title: ${n.title}');
          print('   - Body: ${n.body}');
          print('   - Payload: ${n.payload}');
        }
      } else {
        print('❌ Test notification (ID 998) NOT FOUND in pending list!');
      }
    } catch (e) {
      print('❌ Error scheduling test prayer notification: $e');
    }
  }

  /// Schedule a test notification using show() with a delay (works around alarm issues)
  Future<void> scheduleTestWithDelay() async {
    print('📅 Starting delayed notification test...');
    print('📅 Notification will show in 10 seconds...');

    // Delay 10 seconds then show immediately
    await Future.delayed(const Duration(seconds: 10));

    await showImmediatePrayerNotification('Delayed Test');
  }

  /// Test BOTH methods simultaneously to diagnose which one works
  /// This helps identify if the issue is with AlarmManager or the app
  Future<void> testBothSchedulingMethods() async {
    print('🧪 ========== DUAL SCHEDULING TEST ==========');
    print('🧪 Testing both zonedSchedule AND Future.delayed simultaneously');
    print('🧪 Current time: ${DateTime.now()}');

    _ensureTimezoneInitialized();

    // Check permissions
    final canScheduleExact = await canScheduleExactAlarms();
    print('🧪 Can schedule exact alarms: $canScheduleExact');

    // === Method 1: zonedSchedule (AlarmManager) ===
    final scheduledTime = DateTime.now().add(const Duration(seconds: 15));
    final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

    try {
      await _localNotifications.zonedSchedule(
        997, // Different ID for this test
        '⏰ AlarmManager Test',
        'This notification used zonedSchedule (ID 997)',
        tzScheduledTime,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _prayerChannel.id,
            _prayerChannel.name,
            channelDescription: _prayerChannel.description,
            importance: Importance.max,
            priority: Priority.max,
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFF4CAF50),
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
          ),
        ),
        androidScheduleMode: canScheduleExact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'test_alarmmanager',
      );
      print('🧪 ✅ zonedSchedule registered for: $tzScheduledTime');

      // Verify it's in pending
      final pending = await getPendingNotifications();
      final found = pending.any((n) => n.id == 997);
      print('🧪 Notification 997 in pending list: $found');
    } catch (e) {
      print('🧪 ❌ zonedSchedule error: $e');
    }

    // === Method 2: Dart Timer (in-memory) ===
    print('🧪 Starting Dart Timer for 15 seconds...');
    Future.delayed(const Duration(seconds: 15), () async {
      print('🧪 ⏰ Dart Timer fired! Showing notification...');
      await _localNotifications.show(
        996, // Different ID
        '⏱️ Dart Timer Test',
        'This notification used Future.delayed (ID 996)',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _prayerChannel.id,
            _prayerChannel.name,
            channelDescription: _prayerChannel.description,
            importance: Importance.max,
            priority: Priority.max,
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFFFF9800),
          ),
        ),
        payload: 'test_timer',
      );
    });

    print('🧪 ========================================');
    print('🧪 Both methods scheduled. Watch for:');
    print(
        '🧪   - ID 996: Dart Timer (orange) - should always work if app open');
    print('🧪   - ID 997: AlarmManager (green) - tests system scheduling');
    print('🧪 If only 996 appears, AlarmManager is being blocked');
    print('🧪 ========================================');
  }

  /// Cancel test notifications
  Future<void> cancelTestNotifications() async {
    await _localNotifications.cancel(996);
    await _localNotifications.cancel(997);
    await _localNotifications.cancel(998);
    await _localNotifications.cancel(999);
    print('🧹 Test notifications cancelled (IDs 996-999)');
  }
}
