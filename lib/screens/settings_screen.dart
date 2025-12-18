// lib/screens/settings_screen.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../utils/background_utils.dart';

class SettingsScreen extends StatefulWidget {
  final bool isDay;

  const SettingsScreen({super.key, required this.isDay});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService();

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final fg = foregroundForCard(widget.isDay);
    final tint = cardTint(widget.isDay);
    final bgGradient = widget.isDay
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF87CEEB), Color(0xFF4A90D9)],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
          );

    return Container(
      decoration: BoxDecoration(gradient: bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        extendBody: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios, color: fg),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Settings',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Units Section
                _buildSectionHeader('Units', Icons.straighten, fg),
                const SizedBox(height: 12),
                _buildUnitsCard(fg, tint),
                const SizedBox(height: 24),

                // Appearance Section
                _buildSectionHeader('Appearance', Icons.palette, fg),
                const SizedBox(height: 12),
                _buildThemeCard(fg, tint),
                const SizedBox(height: 24),

                // Location Section
                _buildSectionHeader('Location', Icons.location_on, fg),
                const SizedBox(height: 12),
                _buildTravelingCard(fg, tint),
                const SizedBox(height: 24),

                // About Section
                _buildSectionHeader('About', Icons.info_outline, fg),
                const SizedBox(height: 12),
                _buildAboutCard(fg, tint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color fg) {
    return Row(
      children: [
        Icon(icon, color: fg.withValues(alpha: 0.8), size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: fg.withValues(alpha: 0.8),
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildGlassCard({
    required Widget child,
    required Color tint,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildUnitsCard(Color fg, Color tint) {
    return _buildGlassCard(
      tint: tint,
      child: Column(
        children: [
          // Temperature Unit
          _buildSettingTile(
            icon: Icons.thermostat,
            iconColor: Colors.orange,
            title: 'Temperature Unit',
            subtitle: SettingsService.getTemperatureUnitName(
                _settings.temperatureUnit),
            fg: fg,
            onTap: () => _showTemperatureUnitPicker(fg, tint),
          ),
          Divider(color: fg.withValues(alpha: 0.1), height: 1),
          // Wind Unit
          _buildSettingTile(
            icon: Icons.air,
            iconColor: Colors.lightBlue,
            title: 'Wind Speed Unit',
            subtitle: SettingsService.getWindUnitName(_settings.windUnit),
            fg: fg,
            onTap: () => _showWindUnitPicker(fg, tint),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeCard(Color fg, Color tint) {
    return _buildGlassCard(
      tint: tint,
      child: _buildSettingTile(
        icon: Icons.brightness_6,
        iconColor: Colors.amber,
        title: 'Theme Mode',
        subtitle: SettingsService.getThemeModeName(_settings.themeMode),
        fg: fg,
        onTap: () => _showThemeModePicker(fg, tint),
      ),
    );
  }

  Widget _buildTravelingCard(Color fg, Color tint) {
    return _buildGlassCard(
      tint: tint,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.flight, color: Colors.green, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Traveling Mode',
                    style: TextStyle(
                      color: fg,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Update location in background for accurate prayer times',
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _settings.travelingMode,
              onChanged: (value) => _settings.setTravelingMode(value),
              activeTrackColor: Colors.green.withValues(alpha: 0.5),
              activeThumbColor: Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutCard(Color fg, Color tint) {
    return _buildGlassCard(
      tint: tint,
      child: Column(
        children: [
          _buildSettingTile(
            icon: Icons.apps,
            iconColor: Colors.purple,
            title: 'App Version',
            subtitle: '1.1.6',
            fg: fg,
            showArrow: false,
          ),
          Divider(color: fg.withValues(alpha: 0.1), height: 1),
          _buildSettingTile(
            icon: Icons.code,
            iconColor: Colors.blue,
            title: 'Developer',
            subtitle: 'Mashhood',
            fg: fg,
            showArrow: false,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Color fg,
    VoidCallback? onTap,
    bool showArrow = true,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: fg,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (showArrow && onTap != null)
                Icon(
                  Icons.chevron_right,
                  color: fg.withValues(alpha: 0.4),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTemperatureUnitPicker(Color fg, Color tint) {
    _showOptionPicker(
      title: 'Temperature Unit',
      options: TemperatureUnit.values,
      currentValue: _settings.temperatureUnit,
      getName: SettingsService.getTemperatureUnitName,
      onSelect: (unit) => _settings.setTemperatureUnit(unit),
      fg: fg,
      tint: tint,
    );
  }

  void _showWindUnitPicker(Color fg, Color tint) {
    _showOptionPicker(
      title: 'Wind Speed Unit',
      options: WindUnit.values,
      currentValue: _settings.windUnit,
      getName: SettingsService.getWindUnitName,
      onSelect: (unit) => _settings.setWindUnit(unit),
      fg: fg,
      tint: tint,
    );
  }

  void _showThemeModePicker(Color fg, Color tint) {
    _showOptionPicker(
      title: 'Theme Mode',
      options: AppThemeMode.values,
      currentValue: _settings.themeMode,
      getName: SettingsService.getThemeModeName,
      onSelect: (mode) => _settings.setThemeMode(mode),
      fg: fg,
      tint: tint,
    );
  }

  void _showOptionPicker<T>({
    required String title,
    required List<T> options,
    required T currentValue,
    required String Function(T) getName,
    required void Function(T) onSelect,
    required Color fg,
    required Color tint,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.9),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: TextStyle(
                    color: fg,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ...options.map((option) => ListTile(
                      leading: Radio<T>(
                        value: option,
                        groupValue: currentValue,
                        onChanged: (value) {
                          if (value != null) {
                            onSelect(value);
                            Navigator.pop(context);
                          }
                        },
                        activeColor: Colors.blue,
                      ),
                      title: Text(
                        getName(option),
                        style: TextStyle(
                          color: fg,
                          fontWeight: option == currentValue
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      onTap: () {
                        onSelect(option);
                        Navigator.pop(context);
                      },
                    )),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
