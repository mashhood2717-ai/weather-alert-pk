// lib/widgets/tiles_area.dart - 3 TILES PER ROW

import 'package:flutter/material.dart';
import '../services/weather_controller.dart';
import 'param_tile.dart';

class TilesArea extends StatelessWidget {
  final WeatherController controller;

  const TilesArea({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = controller.getTilesForUI();
    final isDay = (controller.current.value?.isDay ?? 1) == 1;

    if (tiles.isEmpty) return const SizedBox.shrink();

    final List<Widget> rows = [];
    final entries = tiles.entries.toList();

    // 3 tiles per row
    for (int i = 0; i < entries.length; i += 3) {
      final first = entries[i];
      final second = (i + 1 < entries.length) ? entries[i + 1] : null;
      final third = (i + 2 < entries.length) ? entries[i + 2] : null;

      rows.add(
        Row(
          children: [
            Expanded(
              child: ParamTile(
                label: first.key,
                value: first.value,
                isDay: isDay,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: second == null
                  ? const SizedBox.shrink()
                  : ParamTile(
                      label: second.key,
                      value: second.value,
                      isDay: isDay,
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: third == null
                  ? const SizedBox.shrink()
                  : ParamTile(
                      label: third.key,
                      value: third.value,
                      isDay: isDay,
                    ),
            ),
          ],
        ),
      );

      rows.add(const SizedBox(height: 8));
    }

    return Column(children: rows.take(rows.length - 1).toList());
  }
}
