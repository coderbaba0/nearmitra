import 'package:flutter/material.dart';
import '../models/transfer_state.dart';

class TransferCard extends StatelessWidget {
  const TransferCard({super.key, required this.state});

  final TransferState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const accentGreen = Color(0xFF25D366);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2C34) : const Color(0xFFF0F2F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentGreen.withValues(alpha: 0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: accentGreen.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  state.active ? Icons.swap_horiz_rounded : Icons.check_circle_rounded,
                  size: 18,
                  color: accentGreen,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${(state.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: accentGreen,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: state.active || state.progress > 0 ? state.progress.clamp(0, 1) : 0,
              minHeight: 5,
              backgroundColor: isDark ? Colors.white12 : Colors.black12,
              valueColor: const AlwaysStoppedAnimation<Color>(accentGreen),
            ),
          ),
          if (state.active) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _speed(state.speedBytesPerSec),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: accentGreen,
                  ),
                ),
                if (state.etaSeconds != null)
                  Text(
                    'ETA ${_eta(state.etaSeconds!)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _speed(double bytes) {
    if (bytes <= 0) return 'Starting…';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB/s';
  }

  static String _eta(int sec) => sec < 60 ? '${sec}s' : '${sec ~/ 60}m ${sec % 60}s';
}
