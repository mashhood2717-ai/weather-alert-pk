import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/alerts_screen.dart';
import 'screens/admin_portal_screen.dart';
import 'services/notification_service.dart';
import 'services/weather_monitor_service.dart';
import 'services/manual_alert_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase first (required)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Set up background message handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Request notification permission IMMEDIATELY on first launch
  // This is critical for prayer alarms to work
  await _requestNotificationPermission();

  // Run the app immediately - don't wait for non-critical services
  runApp(const WeatherAlertApp());

  // Initialize non-critical services AFTER app is running (deferred)
  _initializeBackgroundServices();
}

/// Request notification permission immediately on app start
Future<void> _requestNotificationPermission() async {
  final status = await Permission.notification.status;
  if (!status.isGranted) {
    await Permission.notification.request();
    debugPrint('🔔 Notification permission requested on app start');
  }
}

/// Initialize background services after app is visible
/// This improves perceived startup time significantly
Future<void> _initializeBackgroundServices() async {
  // Wait 3 seconds to allow location permission dialog to complete first
  // This prevents "Can request only one set of permissions at a time" error
  await Future.delayed(const Duration(seconds: 3));

  // Initialize notification service (this sets up channels, FCM, etc.)
  final notificationService = NotificationService();
  await notificationService.initialize();

  // Start local weather monitoring (checks every 30 min)
  await WeatherMonitorService().startMonitoring();

  // Initialize manual alert service (listens for admin portal alerts)
  ManualAlertService().initialize().catchError((e) {
    debugPrint('ManualAlertService init error: $e');
  });
}

class WeatherAlertApp extends StatelessWidget {
  const WeatherAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Weather & Prayer Alert PK',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFF),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const HomeScreen(),
      routes: {
        '/alerts': (context) => const AlertsScreen(),
        '/admin': (context) => const AdminPortalScreen(),
      },
    );
  }
}
