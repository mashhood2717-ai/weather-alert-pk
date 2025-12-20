// lib/widgets/param_tile.dart - COMPACT FOR 3 PER ROW

import 'package:flutter/material.dart';
import '../utils/background_utils.dart';

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
    final fg = foregroundForCard(isDay);
    final tint = cardTint(isDay);

    // PERFORMANCE: Removed BackdropFilter - too expensive for 9+ tiles
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: fg.withValues(alpha: isDay ? 0.1 : 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: isDay
                ? Colors.black.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 18,
              color: fg.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 2),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: fg.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: fg,
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
