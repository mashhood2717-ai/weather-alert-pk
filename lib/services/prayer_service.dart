// lib/services/prayer_service.dart

import 'package:adhan/adhan.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

/// Prayer calculation method
enum PrayerMethod {
  karachi,
  muslimWorldLeague,
  egyptian,
  ummAlQura,
  dubai,
  qatar,
  kuwait,
  moonsightingCommittee,
  singapore,
  turkey,
  tehran,
  northAmerica,
}

/// Madhab for Asr calculation
enum AsrMadhab {
  shafi, // Standard (Shafi, Maliki, Hanbali)
  hanafi, // Hanafi
}

/// Prayer notification mode
enum PrayerNotificationMode {
  off, // No notification
  vibrationOnly, // Vibration only, no sound
  azan, // Full azan sound with vibration
}

/// Single prayer time data
class PrayerTimeData {
  final String name;
  final String nameArabic;
  final DateTime time;
  final IconData icon;

  PrayerTimeData({
    required this.name,
    required this.nameArabic,
    required this.time,
    required this.icon,
  });

  String get formattedTime {
    final hour =
        time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final amPm = time.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} $amPm';
  }
}

/// Complete prayer times for a day
class DailyPrayerTimes {
  final DateTime date;
  final List<PrayerTimeData> prayers;
  final PrayerTimeData? currentPrayer;
  final PrayerTimeData? nextPrayer;
  final Duration? timeUntilNext;

  DailyPrayerTimes({
    required this.date,
    required this.prayers,
    this.currentPrayer,
    this.nextPrayer,
    this.timeUntilNext,
  });
}

class PrayerService {
  static const String _madhabKey = 'prayer_madhab';
  static const String _methodKey = 'prayer_method';
  static const String _notificationsKey = 'prayer_notifications';

  /// Get saved madhab preference (default is Hanafi for Pakistan)
  static Future<AsrMadhab> getSavedMadhab() async {
    final prefs = await SharedPreferences.getInstance();
    final value =
        prefs.getString(_madhabKey) ?? 'hanafi'; // Default Hanafi for Pakistan
    return value == 'hanafi' ? AsrMadhab.hanafi : AsrMadhab.shafi;
  }

  /// Save madhab preference
  static Future<void> saveMadhab(AsrMadhab madhab) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _madhabKey, madhab == AsrMadhab.hanafi ? 'hanafi' : 'shafi');
  }

  /// Get saved calculation method
  static Future<PrayerMethod> getSavedMethod() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_methodKey) ?? 'karachi';
    return PrayerMethod.values.firstWhere(
      (m) => m.name == value,
      orElse: () => PrayerMethod.karachi,
    );
  }

  /// Save calculation method
  static Future<void> saveMethod(PrayerMethod method) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_methodKey, method.name);
  }

  /// Get notification preferences for each prayer (now returns mode)
  static Future<Map<String, PrayerNotificationMode>>
      getNotificationPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final prayers = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
    final Map<String, PrayerNotificationMode> result = {};
    for (final prayer in prayers) {
      final value =
          prefs.getString('${_notificationsKey}_${prayer}_mode') ?? 'azan';
      result[prayer] = PrayerNotificationMode.values.firstWhere(
        (m) => m.name == value,
        orElse: () => PrayerNotificationMode.azan,
      );
    }
    return result;
  }

  /// Save notification mode for a prayer
  static Future<void> saveNotificationMode(
      String prayer, PrayerNotificationMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_notificationsKey}_${prayer}_mode', mode.name);
  }

  /// Cycle to next notification mode: off -> vibration -> azan -> off
  static PrayerNotificationMode cycleNotificationMode(
      PrayerNotificationMode current) {
    switch (current) {
      case PrayerNotificationMode.off:
        return PrayerNotificationMode.vibrationOnly;
      case PrayerNotificationMode.vibrationOnly:
        return PrayerNotificationMode.azan;
      case PrayerNotificationMode.azan:
        return PrayerNotificationMode.off;
    }
  }

  /// Get icon for notification mode
  static IconData getNotificationModeIcon(PrayerNotificationMode mode) {
    switch (mode) {
      case PrayerNotificationMode.off:
        return Icons.notifications_off_outlined;
      case PrayerNotificationMode.vibrationOnly:
        return Icons.vibration;
      case PrayerNotificationMode.azan:
        return Icons.volume_up_rounded;
    }
  }

  /// Get color for notification mode
  static Color getNotificationModeColor(PrayerNotificationMode mode) {
    switch (mode) {
      case PrayerNotificationMode.off:
        return Colors.grey;
      case PrayerNotificationMode.vibrationOnly:
        return Colors.orange;
      case PrayerNotificationMode.azan:
        return Colors.green;
    }
  }

  /// Get label for notification mode
  static String getNotificationModeLabel(PrayerNotificationMode mode) {
    switch (mode) {
      case PrayerNotificationMode.off:
        return 'Off';
      case PrayerNotificationMode.vibrationOnly:
        return 'Vibrate';
      case PrayerNotificationMode.azan:
        return 'Azan';
    }
  }

  /// Convert our method enum to adhan package CalculationMethod
  static CalculationMethod _getCalculationMethod(PrayerMethod method) {
    switch (method) {
      case PrayerMethod.karachi:
        return CalculationMethod.karachi;
      case PrayerMethod.muslimWorldLeague:
        return CalculationMethod.muslim_world_league;
      case PrayerMethod.egyptian:
        return CalculationMethod.egyptian;
      case PrayerMethod.ummAlQura:
        return CalculationMethod.umm_al_qura;
      case PrayerMethod.dubai:
        return CalculationMethod.dubai;
      case PrayerMethod.qatar:
        return CalculationMethod.qatar;
      case PrayerMethod.kuwait:
        return CalculationMethod.kuwait;
      case PrayerMethod.moonsightingCommittee:
        return CalculationMethod.moon_sighting_committee;
      case PrayerMethod.singapore:
        return CalculationMethod.singapore;
      case PrayerMethod.turkey:
        return CalculationMethod.turkey;
      case PrayerMethod.tehran:
        return CalculationMethod.tehran;
      case PrayerMethod.northAmerica:
        return CalculationMethod.north_america;
    }
  }

  /// Get prayer method display name
  static String getMethodDisplayName(PrayerMethod method) {
    switch (method) {
      case PrayerMethod.karachi:
        return 'Karachi (Pakistan)';
      case PrayerMethod.muslimWorldLeague:
        return 'Muslim World League';
      case PrayerMethod.egyptian:
        return 'Egyptian General Authority';
      case PrayerMethod.ummAlQura:
        return 'Umm Al-Qura (Makkah)';
      case PrayerMethod.dubai:
        return 'Dubai';
      case PrayerMethod.qatar:
        return 'Qatar';
      case PrayerMethod.kuwait:
        return 'Kuwait';
      case PrayerMethod.moonsightingCommittee:
        return 'Moonsighting Committee';
      case PrayerMethod.singapore:
        return 'Singapore';
      case PrayerMethod.turkey:
        return 'Turkey (Diyanet)';
      case PrayerMethod.tehran:
        return 'Tehran';
      case PrayerMethod.northAmerica:
        return 'ISNA (North America)';
    }
  }

  /// Calculate prayer times for a specific date and location
  static Future<DailyPrayerTimes> calculatePrayerTimes({
    required double latitude,
    required double longitude,
    DateTime? date,
    PrayerMethod? method,
    AsrMadhab? madhab,
  }) async {
    // Use saved preferences if not provided
    final usedMethod = method ?? await getSavedMethod();
    final usedMadhab = madhab ?? await getSavedMadhab();
    final usedDate = date ?? DateTime.now();

    // Create coordinates
    final coordinates = Coordinates(latitude, longitude);

    // Get calculation parameters
    final params = _getCalculationMethod(usedMethod).getParameters();
    params.madhab =
        usedMadhab == AsrMadhab.hanafi ? Madhab.hanafi : Madhab.shafi;

    // Calculate prayer times
    final dateComponents = DateComponents.from(usedDate);
    final prayerTimes = PrayerTimes(coordinates, dateComponents, params);

    // Build prayer list
    final prayers = [
      PrayerTimeData(
        name: 'Fajr',
        nameArabic: 'الفجر',
        time: prayerTimes.fajr,
        icon: Icons.nightlight_round,
      ),
      PrayerTimeData(
        name: 'Sunrise',
        nameArabic: 'الشروق',
        time: prayerTimes.sunrise,
        icon: Icons.wb_twilight,
      ),
      PrayerTimeData(
        name: 'Dhuhr',
        nameArabic: 'الظهر',
        time: prayerTimes.dhuhr,
        icon: Icons.wb_sunny,
      ),
      PrayerTimeData(
        name: 'Asr',
        nameArabic: 'العصر',
        time: prayerTimes.asr,
        icon: Icons.sunny_snowing,
      ),
      PrayerTimeData(
        name: 'Maghrib',
        nameArabic: 'المغرب',
        time: prayerTimes.maghrib,
        icon: Icons.wb_twilight,
      ),
      PrayerTimeData(
        name: 'Isha',
        nameArabic: 'العشاء',
        time: prayerTimes.isha,
        icon: Icons.nights_stay,
      ),
    ];

    // Determine current and next prayer
    final now = DateTime.now();
    PrayerTimeData? currentPrayer;
    PrayerTimeData? nextPrayer;
    Duration? timeUntilNext;

    // Include all prayers including Sunrise for next prayer calculation
    // But current prayer should only be main prayers (not sunrise)
    final allPrayers = prayers; // includes Sunrise
    final mainPrayers = prayers.where((p) => p.name != 'Sunrise').toList();

    // Find the next prayer (including Sunrise)
    for (int i = 0; i < allPrayers.length; i++) {
      final prayer = allPrayers[i];
      if (now.isBefore(prayer.time)) {
        nextPrayer = prayer;
        timeUntilNext = prayer.time.difference(now);
        break;
      }
    }

    // Find current prayer (excluding Sunrise)
    for (int i = mainPrayers.length - 1; i >= 0; i--) {
      final prayer = mainPrayers[i];
      if (now.isAfter(prayer.time) || now.isAtSameMomentAs(prayer.time)) {
        currentPrayer = prayer;
        break;
      }
    }

    // If no next prayer found today, next is tomorrow's Fajr
    if (nextPrayer == null) {
      final tomorrow = usedDate.add(const Duration(days: 1));
      final tomorrowComponents = DateComponents.from(tomorrow);
      final tomorrowPrayers =
          PrayerTimes(coordinates, tomorrowComponents, params);
      nextPrayer = PrayerTimeData(
        name: 'Fajr',
        nameArabic: 'الفجر',
        time: tomorrowPrayers.fajr,
        icon: Icons.nightlight_round,
      );
      timeUntilNext = nextPrayer.time.difference(now);
      // Current prayer is Isha if we're past all prayers
      if (currentPrayer == null) {
        currentPrayer = mainPrayers.last; // Isha
      }
    }

    // If no current prayer found, we're before Fajr
    if (currentPrayer == null && nextPrayer.name == 'Fajr') {
      // Before Fajr, no current prayer (or previous day's Isha)
      currentPrayer = null;
    }

    return DailyPrayerTimes(
      date: usedDate,
      prayers: prayers,
      currentPrayer: currentPrayer,
      nextPrayer: nextPrayer,
      timeUntilNext: timeUntilNext,
    );
  }

  /// Schedule prayer notifications based on current preferences
  static Future<void> scheduleNotifications({
    required double latitude,
    required double longitude,
    PrayerMethod? method,
    AsrMadhab? madhab,
  }) async {
    try {
      // Get prayer times
      final prayerTimesData = await calculatePrayerTimes(
        latitude: latitude,
        longitude: longitude,
        method: method,
        madhab: madhab,
      );

      // Get notification preferences
      final notificationPrefs = await getNotificationPrefs();

      // Build prayer times map (only main prayers, not sunrise)
      final prayerTimes = <String, DateTime>{};
      for (final prayer in prayerTimesData.prayers) {
        if (prayer.name != 'Sunrise') {
          prayerTimes[prayer.name] = prayer.time;
        }
      }

      // Schedule notifications
      await NotificationService().scheduleAllPrayerNotifications(
        prayerTimes: prayerTimes,
        prayerModes: notificationPrefs,
        minutesBefore: 5,
      );
    } catch (e) {
      debugPrint('Error scheduling prayer notifications: $e');
    }
  }

  /// Format duration as "Xh Ym"
  static String formatDuration(Duration? duration) {
    if (duration == null) return '--';
    if (duration.isNegative) return 'Now';

    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}
