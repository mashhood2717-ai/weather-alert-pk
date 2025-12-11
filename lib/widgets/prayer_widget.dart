// lib/widgets/prayer_widget.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/prayer_service.dart';
import '../services/notification_service.dart';
import '../utils/background_utils.dart';

class PrayerWidget extends StatefulWidget {
  final bool isDay;
  final double? latitude;
  final double? longitude;
  final String? cityName;

  const PrayerWidget({
    super.key,
    required this.isDay,
    this.latitude,
    this.longitude,
    this.cityName,
  });

  @override
  State<PrayerWidget> createState() => _PrayerWidgetState();
}

class _PrayerWidgetState extends State<PrayerWidget> {
  DailyPrayerTimes? _prayerTimes;
  bool _loading = true;
  String? _error;
  AsrMadhab _currentMadhab = AsrMadhab.hanafi; // Default Hanafi for Pakistan
  PrayerMethod _currentMethod = PrayerMethod.karachi;
  Map<String, PrayerNotificationMode> _notificationModes = {};
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    // Refresh every minute to update countdown
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) _calculatePrayers();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(PrayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      _calculatePrayers();
    }
  }

  Future<void> _loadPreferences() async {
    _currentMadhab = await PrayerService.getSavedMadhab();
    _currentMethod = await PrayerService.getSavedMethod();
    _notificationModes = await PrayerService.getNotificationPrefs();
    if (mounted) setState(() {});
    await _calculatePrayers();
  }

  Future<void> _calculatePrayers() async {
    if (widget.latitude == null || widget.longitude == null) {
      setState(() {
        _error = 'Location not available';
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);

    try {
      final prayers = await PrayerService.calculatePrayerTimes(
        latitude: widget.latitude!,
        longitude: widget.longitude!,
        method: _currentMethod,
        madhab: _currentMadhab,
      );
      if (mounted) {
        setState(() {
          _prayerTimes = prayers;
          _loading = false;
          _error = null;
        });
        // Schedule notifications after calculating prayer times
        await _scheduleNotifications();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to calculate prayer times';
          _loading = false;
        });
      }
    }
  }

  Future<void> _scheduleNotifications() async {
    if (widget.latitude == null || widget.longitude == null) return;
    await PrayerService.scheduleNotifications(
      latitude: widget.latitude!,
      longitude: widget.longitude!,
      method: _currentMethod,
      madhab: _currentMadhab,
    );
  }

  Future<void> _changeMadhab(AsrMadhab madhab) async {
    await PrayerService.saveMadhab(madhab);
    setState(() => _currentMadhab = madhab);
    await _calculatePrayers();
  }

  Future<void> _changeMethod(PrayerMethod method) async {
    await PrayerService.saveMethod(method);
    setState(() => _currentMethod = method);
    await _calculatePrayers();
  }

  /// Cycle notification mode for a prayer: Off -> Vibration -> Azan -> Off
  Future<void> _cycleNotificationMode(String prayer) async {
    final currentMode =
        _notificationModes[prayer] ?? PrayerNotificationMode.azan;
    final newMode = PrayerService.cycleNotificationMode(currentMode);
    await PrayerService.saveNotificationMode(prayer, newMode);
    setState(() => _notificationModes[prayer] = newMode);
    // Show feedback
    final label = PrayerService.getNotificationModeLabel(newMode);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$prayer notification: $label'),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
      ),
    );
    // Re-schedule notifications with updated preferences
    await _scheduleNotifications();
  }

  /// Test azan notification with sound and vibration
  Future<void> _testAzanNotification() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🕌 Sending test Azan notification...'),
        duration: Duration(seconds: 1),
      ),
    );
    await NotificationService().showImmediatePrayerNotification('Test');
  }

  @override
  Widget build(BuildContext context) {
    final fg = foregroundForCard(widget.isDay);
    final tint = cardTint(widget.isDay);

    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: fg),
            const SizedBox(height: 16),
            Text('Calculating Prayer Times...', style: TextStyle(color: fg)),
          ],
        ),
      );
    }

    if (_error != null || _prayerTimes == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mosque_outlined, color: fg, size: 64),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Unable to load prayer times',
              style: TextStyle(color: fg, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Next Prayer Card
          _buildNextPrayerCard(fg, tint),
          const SizedBox(height: 16),
          // Prayer Times List
          _buildPrayerTimesList(fg, tint),
          const SizedBox(height: 16),
          // Settings Card
          _buildSettingsCard(fg, tint),
        ],
      ),
    );
  }

  Widget _buildNextPrayerCard(Color fg, Color tint) {
    final next = _prayerTimes!.nextPrayer;
    final timeUntil = _prayerTimes!.timeUntilNext;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mosque, color: fg, size: 28),
              const SizedBox(width: 12),
              Text(
                'Prayer Times',
                style: TextStyle(
                  color: fg,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (widget.cityName != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.cityName!,
              style: TextStyle(
                color: fg.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (next != null) ...[
            Text(
              'Next Prayer',
              style: TextStyle(
                color: fg.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(next.icon, color: Colors.amber, size: 32),
                const SizedBox(width: 12),
                Text(
                  next.name,
                  style: TextStyle(
                    color: fg,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  next.nameArabic,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.7),
                    fontSize: 20,
                    fontFamily: 'Arial',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              next.formattedTime,
              style: TextStyle(
                color: fg,
                fontSize: 24,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'in ${PrayerService.formatDuration(timeUntil)}',
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrayerTimesList(Color fg, Color tint) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today\'s Prayer Times',
            style: TextStyle(
              color: fg,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          ...(_prayerTimes!.prayers.map((p) => _buildPrayerRow(p, fg, tint))),
        ],
      ),
    );
  }

  Widget _buildPrayerRow(PrayerTimeData prayer, Color fg, Color tint) {
    final isCurrent = _prayerTimes!.currentPrayer?.name == prayer.name;
    final isNext = _prayerTimes!.nextPrayer?.name == prayer.name;
    final isSunrise = prayer.name == 'Sunrise';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isNext
            ? Colors.green.withValues(alpha: 0.15)
            : isCurrent
                ? Colors.blue.withValues(alpha: 0.1)
                : tint.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: isNext
            ? Border.all(color: Colors.green, width: 2)
            : isCurrent
                ? Border.all(color: Colors.blue.withValues(alpha: 0.5))
                : null,
      ),
      child: Row(
        children: [
          Icon(
            prayer.icon,
            color: isNext ? Colors.green : fg.withValues(alpha: 0.7),
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      prayer.name,
                      style: TextStyle(
                        color: isNext ? Colors.green : fg,
                        fontSize: 16,
                        fontWeight: isNext ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      prayer.nameArabic,
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.6),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                if (isCurrent && !isSunrise)
                  Text(
                    'Current',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            prayer.formattedTime,
            style: TextStyle(
              color: isNext ? Colors.green : fg,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (!isSunrise) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _cycleNotificationMode(prayer.name),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: PrayerService.getNotificationModeColor(
                    _notificationModes[prayer.name] ??
                        PrayerNotificationMode.azan,
                  ).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: PrayerService.getNotificationModeColor(
                      _notificationModes[prayer.name] ??
                          PrayerNotificationMode.azan,
                    ).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PrayerService.getNotificationModeIcon(
                        _notificationModes[prayer.name] ??
                            PrayerNotificationMode.azan,
                      ),
                      color: PrayerService.getNotificationModeColor(
                        _notificationModes[prayer.name] ??
                            PrayerNotificationMode.azan,
                      ),
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      PrayerService.getNotificationModeLabel(
                        _notificationModes[prayer.name] ??
                            PrayerNotificationMode.azan,
                      ),
                      style: TextStyle(
                        color: PrayerService.getNotificationModeColor(
                          _notificationModes[prayer.name] ??
                              PrayerNotificationMode.azan,
                        ),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsCard(Color fg, Color tint) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: TextStyle(
              color: fg,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          // Madhab Selection
          Text(
            'Asr Calculation (Madhab)',
            style: TextStyle(
              color: fg.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMadhabButton(
                  'Shafi/Hanbali',
                  AsrMadhab.shafi,
                  fg,
                  tint,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMadhabButton(
                  'Hanafi',
                  AsrMadhab.hanafi,
                  fg,
                  tint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Calculation Method
          Text(
            'Calculation Method',
            style: TextStyle(
              color: fg.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: fg.withValues(alpha: 0.1)),
            ),
            child: DropdownButton<PrayerMethod>(
              value: _currentMethod,
              isExpanded: true,
              dropdownColor: widget.isDay ? Colors.white : Colors.grey[900],
              underline: const SizedBox(),
              icon: Icon(Icons.arrow_drop_down, color: fg),
              style: TextStyle(color: fg, fontSize: 14),
              items: PrayerMethod.values.map((method) {
                return DropdownMenuItem(
                  value: method,
                  child: Text(
                    PrayerService.getMethodDisplayName(method),
                    style: TextStyle(color: fg),
                  ),
                );
              }).toList(),
              onChanged: (method) {
                if (method != null) _changeMethod(method);
              },
            ),
          ),
          const SizedBox(height: 20),
          // Test Azan Button
          Text(
            'Test Notification',
            style: TextStyle(
              color: fg.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _testAzanNotification,
              icon: const Icon(Icons.notifications_active, size: 20),
              label: const Text('Test Azan Sound & Vibration'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMadhabButton(
    String label,
    AsrMadhab madhab,
    Color fg,
    Color tint,
  ) {
    final isSelected = _currentMadhab == madhab;
    return GestureDetector(
      onTap: () => _changeMadhab(madhab),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.green.withValues(alpha: 0.2)
              : tint.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.green : fg.withValues(alpha: 0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.green : fg,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
