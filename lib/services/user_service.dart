// lib/services/user_service.dart

import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Service to manage unique user identification with Firebase sync
class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  static const String _userIdKey = 'user_unique_id';
  static const String _userNameKey = 'user_display_name';
  static const String _isGuestKey = 'user_is_guest';
  static const String _onboardingCompleteKey = 'user_onboarding_complete';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _userId;
  String? _userName;
  bool _isGuest = true;
  bool _onboardingComplete = false;
  String? _deviceInfo;

  /// Get the current user ID
  String get userId => _userId ?? '';
  
  /// Get the current user name
  String get userName => _userName ?? 'Guest';
  
  /// Check if user is a guest
  bool get isGuest => _isGuest;
  
  /// Check if onboarding is complete
  bool get onboardingComplete => _onboardingComplete;

  /// Get device info string
  String get deviceInfo => _deviceInfo ?? 'Unknown';

  /// Initialize the user service
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    
    _userId = prefs.getString(_userIdKey);
    _userName = prefs.getString(_userNameKey);
    _isGuest = prefs.getBool(_isGuestKey) ?? true;
    _onboardingComplete = prefs.getBool(_onboardingCompleteKey) ?? false;
    
    // Get device info
    await _getDeviceInfo();
    
    // Generate user ID if not exists
    if (_userId == null || _userId!.isEmpty) {
      _userId = _generateUserId();
      await prefs.setString(_userIdKey, _userId!);
      debugPrint('🆔 Generated new user ID: $_userId');
    } else {
      debugPrint('🆔 Loaded existing user ID: $_userId');
    }
    
    // Update last active in Firestore (fire and forget)
    _updateLastActive();
  }

  /// Get device information
  Future<void> _getDeviceInfo() async {
    try {
      final deviceInfoPlugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        _deviceInfo = 'Android ${androidInfo.version.release} - ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        _deviceInfo = 'iOS ${iosInfo.systemVersion} - ${iosInfo.model}';
      } else {
        _deviceInfo = 'Unknown Platform';
      }
    } catch (e) {
      _deviceInfo = 'Unknown';
      debugPrint('🆔 Error getting device info: $e');
    }
  }

  /// Generate a unique user ID
  String _generateUserId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = timestamp.hashCode.abs() % 100000;
    return 'user_${timestamp}_$random';
  }

  /// Set user name and mark as non-guest
  Future<void> setUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    _userName = name.trim();
    _isGuest = false;
    
    await prefs.setString(_userNameKey, _userName!);
    await prefs.setBool(_isGuestKey, false);
    
    // Sync to Firestore
    await _syncUserToFirestore();
    
    debugPrint('🆔 User name set: $_userName');
  }

  /// Continue as guest
  Future<void> continueAsGuest() async {
    final prefs = await SharedPreferences.getInstance();
    _userName = 'Guest';
    _isGuest = true;
    
    await prefs.setString(_userNameKey, 'Guest');
    await prefs.setBool(_isGuestKey, true);
    
    // Sync to Firestore
    await _syncUserToFirestore();
    
    debugPrint('🆔 Continuing as guest');
  }

  /// Sync user data to Firestore
  Future<void> _syncUserToFirestore() async {
    if (_userId == null || _userId!.isEmpty) return;
    
    try {
      await _firestore.collection('users').doc(_userId).set({
        'userId': _userId,
        'name': _userName ?? 'Guest',
        'isGuest': _isGuest,
        'deviceInfo': _deviceInfo ?? 'Unknown',
        'createdAt': FieldValue.serverTimestamp(),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      debugPrint('🆔 User synced to Firestore: $_userId');
    } catch (e) {
      debugPrint('🆔 Error syncing user to Firestore: $e');
    }
  }

  /// Update last active timestamp
  Future<void> _updateLastActive() async {
    if (_userId == null || _userId!.isEmpty) return;
    if (!_onboardingComplete) return; // Only update if onboarding is done
    
    try {
      await _firestore.collection('users').doc(_userId).update({
        'lastActive': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Document might not exist yet, that's okay
      debugPrint('🆔 Could not update lastActive: $e');
    }
  }

  /// Mark onboarding as complete
  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    _onboardingComplete = true;
    await prefs.setBool(_onboardingCompleteKey, true);
  }

  /// Check if user needs onboarding (first launch)
  Future<bool> needsOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_onboardingCompleteKey) ?? false);
  }

  /// Record that user received an alert
  Future<void> recordAlertReceived({
    required String alertId,
    required String alertTitle,
    required String alertType,
  }) async {
    if (_userId == null || _userId!.isEmpty) return;
    
    try {
      await _firestore.collection('alert_receipts').add({
        'userId': _userId,
        'userName': _userName ?? 'Guest',
        'alertId': alertId,
        'alertTitle': alertTitle,
        'alertType': alertType,
        'receivedAt': FieldValue.serverTimestamp(),
        'acknowledged': false,
      });
      debugPrint('🆔 Alert receipt recorded: $alertId for $_userId');
    } catch (e) {
      debugPrint('🆔 Error recording alert receipt: $e');
    }
  }

  /// Mark alert as acknowledged
  Future<void> acknowledgeAlert(String receiptId) async {
    try {
      await _firestore.collection('alert_receipts').doc(receiptId).update({
        'acknowledged': true,
        'acknowledgedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('🆔 Error acknowledging alert: $e');
    }
  }

  /// Clear user data (for testing)
  Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_isGuestKey);
    await prefs.remove(_onboardingCompleteKey);
    _userId = null;
    _userName = null;
    _isGuest = true;
    _onboardingComplete = false;
  }
}
