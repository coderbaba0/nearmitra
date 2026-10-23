import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Displays measured WebRTC audio energy; silence stays still.
class WirelessAudioMeter extends StatelessWidget {
  const WirelessAudioMeter(
      {super.key, required this.level, required this.active});
  final double level;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final energy = active ? math.sqrt(level.clamp(0, 1)) : 0.0;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Semantics(
      label: active
          ? 'Live audio level ${(level * 100).round()} percent'
          : 'Audio idle',
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(15, (index) {
            final weight = 0.3 + 0.7 * (1 - (index - 7).abs() / 8);
            return Expanded(
                child: Center(
                    child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              height: 4 + 40 * energy * weight,
              decoration: BoxDecoration(
                color: active && energy > 0.02
                    ? colors.primary
                    : colors.outlineVariant,
                borderRadius: BorderRadius.circular(6),
              ),
            )));
          }),
        ),
      ),
    );
  }
}
