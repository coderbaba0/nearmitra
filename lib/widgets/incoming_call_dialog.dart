import 'package:flutter/material.dart';

/// Presentation only; the existing call route owns accepting and declining.
class IncomingCallDialog extends StatelessWidget {
  const IncomingCallDialog({
    super.key,
    required this.callerName,
    required this.isVideo,
    this.avatar,
  });

  final String callerName;
  final bool isVideo;
  final String? avatar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final name = callerName.trim().isEmpty ? 'Nearby device' : callerName;
    final callIcon = isVideo ? Icons.videocam_rounded : Icons.call_rounded;

    return Dialog(
      backgroundColor: colors.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(callIcon, size: 18, color: colors.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      isVideo ? 'Incoming video call' : 'Incoming voice call',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: colors.primary.withValues(alpha: .14)),
                ),
                child: CircleAvatar(
                  radius: 42,
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.onPrimaryContainer,
                  child: avatar?.isNotEmpty == true
                      ? Text(avatar!, style: const TextStyle(fontSize: 34))
                      : const Icon(Icons.person_rounded, size: 42),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isVideo
                    ? 'Would like to video call you'
                    : 'Would like to talk to you',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_rounded, size: 14, color: colors.primary),
                    const SizedBox(width: 6),
                    Text('Nearby call',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              LayoutBuilder(builder: (context, constraints) {
                final decline = FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.errorContainer,
                    foregroundColor: colors.onErrorContainer,
                    minimumSize: const Size(0, 52),
                  ),
                  icon: const Icon(Icons.call_end_rounded, size: 22),
                  label: const Text('Decline'),
                );
                final answer = FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                  icon: Icon(callIcon, size: 22),
                  label: const Text('Answer'),
                );
                if (constraints.maxWidth < 280 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [answer, const SizedBox(height: 12), decline],
                  );
                }
                return Row(children: [
                  Expanded(child: decline),
                  const SizedBox(width: 12),
                  Expanded(child: answer),
                ]);
              }),
            ],
          ),
        ),
      ),
    );
  }
}
