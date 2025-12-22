// lib/app.dart

import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/user_service.dart';

class WeatherAlertApp extends StatefulWidget {
  const WeatherAlertApp({super.key});

  @override
  State<WeatherAlertApp> createState() => _WeatherAlertAppState();
}

class _WeatherAlertAppState extends State<WeatherAlertApp> {
  bool _showOnboarding = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final needsOnboarding = await UserService().needsOnboarding();
    setState(() {
      _showOnboarding = needsOnboarding;
      _isLoading = false;
    });
  }

  void _onOnboardingComplete() {
    setState(() {
      _showOnboarding = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Weather & Prayer Alert PK',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFF),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: _isLoading
          ? const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            )
          : _showOnboarding
              ? OnboardingScreen(onComplete: _onOnboardingComplete)
              : HomeScreen(),
    );
  }
}
