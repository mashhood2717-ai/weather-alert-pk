import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/background_utils.dart'; // CORRECTED PATH

class ParamTile extends StatelessWidget {
  final String label;
  final String value;
  final bool isDay;

  const ParamTile({
    super.key,
    required this.label,
    required this.value,
    required this.isDay,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foregroundForCard(isDay);
    final tint = cardTint(isDay);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          width: MediaQuery.of(context).size.width / 2 - 26,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: fg.withValues(alpha: isDay ? 0.06 : 0.10),
            ),
            boxShadow: [
              BoxShadow(
                color: isDay
                    ? Colors.black.withValues(alpha: 0.07)
                    : Colors.black.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
