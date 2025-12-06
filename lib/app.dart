// lib/app.dart

import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

class WeatherAlertApp extends StatelessWidget {
  const WeatherAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Weather Alert Pakistan',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFF),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      // FIX: const keyword removed from HomeScreen
      home: HomeScreen(),
    );
  }
}
