// lib/widgets/prayer_calendar_widget.dart

import 'package:flutter/material.dart';
import '../services/prayer_service.dart';

/// Prayer Calendar Widget - View prayer times for any date up to 1 year
class PrayerCalendarWidget extends StatefulWidget {
  final bool isDay;
  final double? latitude;
  final double? longitude;
  final String? cityName;

  const PrayerCalendarWidget({
    super.key,
    required this.isDay,
    this.latitude,
    this.longitude,
    this.cityName,
  });

  @override
  State<PrayerCalendarWidget> createState() => _PrayerCalendarWidgetState();
}

class _PrayerCalendarWidgetState extends State<PrayerCalendarWidget> {
  DateTime _selectedDate = DateTime.now();
  DailyPrayerTimes? _prayerTimes;
  bool _loading = false;
  String? _error;
  AsrMadhab _currentMadhab = AsrMadhab.hanafi;
  PrayerMethod _currentMethod = PrayerMethod.karachi;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void didUpdateWidget(PrayerCalendarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      _loadPrayerTimes();
    }
  }

  Future<void> _loadPreferences() async {
    _currentMadhab = await PrayerService.getSavedMadhab();
    _currentMethod = await PrayerService.getSavedMethod();
    await _loadPrayerTimes();
  }

  Future<void> _loadPrayerTimes() async {
    if (widget.latitude == null || widget.longitude == null) {
      setState(() => _error = 'Location not available');
      return;
    }

    setState(() => _loading = true);

    try {
      final prayers = await PrayerService.calculatePrayerTimes(
        latitude: widget.latitude!,
        longitude: widget.longitude!,
        date: _selectedDate,
        method: _currentMethod,
        madhab: _currentMadhab,
      );
      if (mounted) {
        setState(() {
          _prayerTimes = prayers;
          _loading = false;
          _error = null;
        });
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

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: widget.isDay
              ? ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: Colors.green,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black87,
                  ),
                )
              : ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: Colors.green,
                    onPrimary: Colors.white,
                    surface: Color(0xFF2C2C2E),
                    onSurface: Colors.white,
                  ),
                ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      await _loadPrayerTimes();
    }
  }

  void _goToPreviousDay() {
    final now = DateTime.now();
    final previousDay = _selectedDate.subtract(const Duration(days: 1));
    // Don't go before today
    if (previousDay.isAfter(now.subtract(const Duration(days: 1)))) {
      setState(() => _selectedDate = previousDay);
      _loadPrayerTimes();
    }
  }

  void _goToNextDay() {
    final now = DateTime.now();
    final nextDay = _selectedDate.add(const Duration(days: 1));
    // Don't go beyond 1 year
    if (nextDay.isBefore(now.add(const Duration(days: 366)))) {
      setState(() => _selectedDate = nextDay);
      _loadPrayerTimes();
    }
  }

  void _goToToday() {
    setState(() => _selectedDate = DateTime.now());
    _loadPrayerTimes();
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.isDay ? Colors.black87 : Colors.white;
    final tint = widget.isDay
        ? Colors.white.withValues(alpha: 0.3)
        : Colors.white.withValues(alpha: 0.1);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header with date selector
          _buildDateSelector(fg, tint),
          const SizedBox(height: 20),

          // Quick date buttons
          _buildQuickDateButtons(fg, tint),
          const SizedBox(height: 20),

          // Prayer times list
          if (_loading)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: fg),
                    const SizedBox(height: 16),
                    Text('Loading...', style: TextStyle(color: fg)),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(Icons.error_outline, color: fg, size: 48),
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: fg)),
                  ],
                ),
              ),
            )
          else if (_prayerTimes != null)
            _buildPrayerTimesList(fg, tint),

          const SizedBox(height: 16),

          // Location info
          if (widget.cityName != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: fg.withValues(alpha: 0.1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_on,
                      color: fg.withValues(alpha: 0.7), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    widget.cityName!,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDateSelector(Color fg, Color tint) {
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    final isTomorrow = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day + 1;

    String dateLabel;
    if (isToday) {
      dateLabel = 'Today';
    } else if (isTomorrow) {
      dateLabel = 'Tomorrow';
    } else {
      final dayName = _getDayName(_selectedDate.weekday);
      dateLabel = dayName;
    }

    final dateStr =
        '${_selectedDate.day} ${_getMonthName(_selectedDate.month)} ${_selectedDate.year}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.calendar_month, color: fg, size: 24),
              const SizedBox(width: 12),
              Text(
                'Prayer Calendar',
                style: TextStyle(
                  color: fg,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _selectedDate.isAfter(now) ? _goToPreviousDay : null,
                icon: Icon(
                  Icons.chevron_left,
                  color: _selectedDate.isAfter(now)
                      ? fg
                      : fg.withValues(alpha: 0.3),
                  size: 32,
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _selectDate,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: isToday
                              ? Colors.green.withValues(alpha: 0.2)
                              : tint,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isToday
                                ? Colors.green
                                : fg.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              dateLabel,
                              style: TextStyle(
                                color: isToday ? Colors.green : fg,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              dateStr,
                              style: TextStyle(
                                color: fg.withValues(alpha: 0.7),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap to select date',
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: _goToNextDay,
                icon: Icon(
                  Icons.chevron_right,
                  color: fg,
                  size: 32,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickDateButtons(Color fg, Color tint) {
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;

    return Row(
      children: [
        if (!isToday)
          Expanded(
            child: _buildQuickButton(
              'Today',
              Icons.today,
              fg,
              tint,
              _goToToday,
            ),
          ),
        if (!isToday) const SizedBox(width: 12),
        Expanded(
          child: _buildQuickButton(
            '+7 Days',
            Icons.calendar_view_week,
            fg,
            tint,
            () {
              setState(() => _selectedDate = now.add(const Duration(days: 7)));
              _loadPrayerTimes();
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickButton(
            '+30 Days',
            Icons.calendar_view_month,
            fg,
            tint,
            () {
              setState(() => _selectedDate = now.add(const Duration(days: 30)));
              _loadPrayerTimes();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildQuickButton(
      String label, IconData icon, Color fg, Color tint, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: fg.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fg.withValues(alpha: 0.7), size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrayerTimesList(Color fg, Color tint) {
    if (_prayerTimes == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: _prayerTimes!.prayers.map((prayer) {
          final isLast = _prayerTimes!.prayers.indexOf(prayer) ==
              _prayerTimes!.prayers.length - 1;

          return Column(
            children: [
              _buildPrayerRow(prayer, fg, tint),
              if (!isLast)
                Divider(
                  color: fg.withValues(alpha: 0.1),
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPrayerRow(PrayerTimeData prayer, Color fg, Color tint) {
    // Sunrise is not a prayer
    final isSunrise = prayer.name == 'Sunrise';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isSunrise
                  ? Colors.orange.withValues(alpha: 0.2)
                  : Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              prayer.icon,
              color: isSunrise ? Colors.orange : Colors.green,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          // Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prayer.name,
                  style: TextStyle(
                    color: fg,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  prayer.nameArabic,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Time
          Text(
            prayer.formattedTime,
            style: TextStyle(
              color: fg,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _getDayName(int weekday) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    return days[weekday - 1];
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return months[month - 1];
  }
}
