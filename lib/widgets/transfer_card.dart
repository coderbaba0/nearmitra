import 'package:flutter/material.dart';

import '../models/transfer_state.dart';

class TransferCard extends StatelessWidget {
  const TransferCard({super.key, required this.state});

  final TransferState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(state.active ? Icons.swap_horiz_rounded : Icons.check_circle_outline_rounded, size: 19, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(state.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('${(state.progress * 100).clamp(0, 100).toStringAsFixed(0)}%', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: state.active || state.progress > 0 ? state.progress.clamp(0, 1) : 0, minHeight: 7),
          ),
          if (state.active) ...[
            const SizedBox(height: 8),
            Text('${_speed(state.speedBytesPerSec)}${state.etaSeconds == null ? '' : '  •  ETA ${_eta(state.etaSeconds!)}'}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
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
