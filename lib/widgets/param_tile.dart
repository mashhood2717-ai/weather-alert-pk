// lib/widgets/param_tile.dart - Premium glass tile design

import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class ParamTile extends StatelessWidget {
  final String label;
  final String value;
  final bool isDay;
  final IconData? icon;

  const ParamTile({
    super.key,
    required this.label,
    required this.value,
    required this.isDay,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme(isDay: isDay);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDay
              ? [
                  Colors.white.withValues(alpha: 0.35),
                  Colors.white.withValues(alpha: 0.2),
                ]
              : [
                  Colors.white.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.05),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDay ? 0.4 : 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDay ? 0.06 : 0.2),
            blurRadius: 12,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon with subtle background
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.textPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 16,
                color: theme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Label
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: theme.textTertiary,
              letterSpacing: 0.8,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          // Value
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: theme.textPrimary,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
