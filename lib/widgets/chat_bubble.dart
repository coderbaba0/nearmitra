import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';

import '../models/chat_item.dart';
import '../services/file_opener_service.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.item,
    this.onCancel,
    this.onReact,
  });

  final ChatItem item;
  final VoidCallback? onCancel;
  final ValueChanged<String>? onReact;

  void _showReactionPicker(BuildContext context) {
    if (onReact == null) return;
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? Size.zero;
    final position = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final screenSize = MediaQuery.sizeOf(context);
    final topPadding = MediaQuery.paddingOf(context).top;

    const popupWidth = 260.0;
    const popupHeight = 52.0;

    // Position directly above the message bubble (or below if too close to top bar)
    double targetTop = position.dy - popupHeight - 8;
    if (targetTop < topPadding + 56) {
      targetTop = position.dy + size.height + 8;
    }

    // Horizontal positioning aligned with bubble
    double targetLeft;
    if (item.mine) {
      targetLeft = (position.dx + size.width - popupWidth)
          .clamp(16.0, screenSize.width - popupWidth - 16.0);
    } else {
      targetLeft =
          position.dx.clamp(16.0, screenSize.width - popupWidth - 16.0);
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss reaction',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim1, anim2) {
        return Stack(
          children: [
            Positioned(
              left: targetLeft,
              top: targetTop,
              child: Material(
                color: Colors.transparent,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      alignment: item.mine
                          ? Alignment.bottomRight
                          : Alignment.bottomLeft,
                      child: child,
                    );
                  },
                  child: Container(
                    width: popupWidth,
                    height: popupHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.black12,
                        width: 1,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 18,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _emojiButton(ctx, '👍'),
                        _emojiButton(ctx, '❤️'),
                        _emojiButton(ctx, '👎'),
                        _emojiButton(ctx, '🤔'),
                        _emojiButton(ctx, '😂'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _emojiButton(BuildContext ctx, String emoji) {
    final isCurrent = item.reaction == emoji;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Navigator.pop(ctx);
        onReact?.call(isCurrent ? '' : emoji);
      },
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: isCurrent
              ? const Color(0xFF10B981).withValues(alpha: 0.25)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Text(
          emoji,
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mine = item.mine;

    final isAiWarning = item.text == 'Nearby AI is not enabled on this device.';

    // WhatsApp-style Color Palette + AI Mode Colors
    final bg = mine
        ? (isDark ? const Color(0xFF005C4B) : const Color(0xFFDCF8C6))
        : (item.isAi
            ? (isAiWarning
                ? (isDark ? const Color(0xFF3F2A1D) : const Color(0xFFFFF3E0))
                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF0FDF4)))
            : (isDark ? const Color(0xFF202C33) : const Color(0xFFFFFFFF)));

    final textColor = mine
        ? (isDark ? const Color(0xFFE9EDEF) : const Color(0xFF111B21))
        : (isAiWarning
            ? (isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100))
            : (isDark ? const Color(0xFFE9EDEF) : const Color(0xFF111B21)));

    final timeColor = mine
        ? (isDark ? Colors.white60 : Colors.black45)
        : (isDark ? Colors.white54 : Colors.black45);

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(mine ? 16 : 4),
      bottomRight: Radius.circular(mine ? 4 : 16),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset((mine ? 1 : -1) * (1 - value) * 16, (1 - value) * 8),
          child: Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: onReact != null ? () => _showReactionPicker(context) : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.84,
                ),
                margin: EdgeInsets.only(
                  top: 4,
                  bottom: (item.reaction != null && item.reaction!.isNotEmpty)
                      ? 12
                      : 4,
                  left: 8,
                  right: 8,
                ),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: radius,
                  border: item.isAi && !mine
                      ? Border.all(
                          color: isAiWarning
                              ? const Color(0xFFFFA726).withValues(alpha: 0.5)
                              : const Color(0xFF10B981).withValues(alpha: 0.4),
                        )
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                      blurRadius: 3,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!mine) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.isAi) ...[
                      Icon(
                        isAiWarning ? Icons.info_outline_rounded : Icons.auto_awesome_rounded,
                        size: 14,
                        color: isAiWarning ? const Color(0xFFFB8C00) : const Color(0xFF10B981),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Builder(
                      builder: (_) {
                        String senderName = item.sender;
                        if (item.isAi) {
                          if (isAiWarning) {
                            senderName = 'System Notice';
                          } else {
                            senderName = senderName.replaceAll(
                              RegExp(r'\b(AI|Ai)\s+(AI|Ai)\b', caseSensitive: false),
                              'AI',
                            );
                          }
                        }
                        return Text(
                          senderName,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: item.isAi
                                ? (isAiWarning ? const Color(0xFFFB8C00) : const Color(0xFF10B981))
                                : (isDark ? const Color(0xFF53BDEB) : const Color(0xFF075E54)),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 3),
              ],
              if (item.kind == ChatKind.text)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: item.isAi && !isAiWarning
                      ? MarkdownBody(
                          data: item.text ?? '',
                          selectable: true,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(color: textColor, fontSize: 14.5, height: 1.38),
                            strong: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                            code: TextStyle(
                              color: isDark ? const Color(0xFF818CF8) : const Color(0xFF3730A3),
                              backgroundColor: isDark ? Colors.black38 : const Color(0xFFEEF2FF),
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        )
                      : Text(
                          item.text ?? '',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 15,
                            height: 1.35,
                          ),
                        ),
                )
              else
                _buildFileCard(context, isDark, textColor),

              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (item.isAi && !mine && !isAiWarning) ...[
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        if (item.text != null && item.text!.isNotEmpty) {
                          Clipboard.setData(ClipboardData(text: item.text!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('AI response copied to clipboard'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.copy_rounded, size: 13, color: timeColor),
                            const SizedBox(width: 3),
                            Text('Copy', style: TextStyle(fontSize: 10.5, color: timeColor, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () async {
                        if (item.text != null && item.text!.isNotEmpty) {
                          try {
                            await Share.share(
                              item.text!,
                              subject: 'NearMitra AI Response',
                            );
                          } catch (_) {
                            Clipboard.setData(ClipboardData(text: item.text!));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('AI response copied to clipboard'),
                                  duration: Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.share_rounded, size: 13, color: timeColor),
                            const SizedBox(width: 3),
                            Text('Share', style: TextStyle(fontSize: 10.5, color: timeColor, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (item.isMeshRelay) ...[
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.hub_rounded,
                              size: 11, color: Color(0xFF10B981)),
                          const SizedBox(width: 3),
                          Text(
                            item.relayHops != null && item.relayHops!.length > 1
                                ? 'Mesh (${item.relayHops!.length - 1} hops)'
                                : 'Mesh',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  const Spacer(),
                  Text(
                    item.formattedTime,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: timeColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    if (item.status == 'Queued') ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.schedule_rounded, size: 11, color: Color(0xFFF59E0B)),
                            const SizedBox(width: 3),
                            const Text(
                              'Queued',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFF59E0B),
                              ),
                            ),
                            if (onCancel != null) ...[
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: onCancel,
                                borderRadius: BorderRadius.circular(4),
                                child: const Icon(Icons.close_rounded, size: 12, color: Color(0xFFEF4444)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ] else if (item.status == 'Cancelled') ...[
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.block_rounded, size: 13, color: Color(0xFFEF4444)),
                          SizedBox(width: 3),
                          Text('Cancelled',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFFEF4444),
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ] else if (item.status == 'Sending…') ...[
                      const SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Colors.white70),
                      ),
                    ] else ...[
                      const Icon(
                        Icons.done_all_rounded,
                        size: 16,
                        color: Color(0xFF53BDEB),
                      ),
                    ],
                  ],
                ],
              ),
            ],
          ),
        ),
        if (item.reaction != null && item.reaction!.isNotEmpty)
          Positioned(
            bottom: 0,
            right: mine ? null : 16,
            left: mine ? 16 : null,
            child: GestureDetector(
              onTap: () => _showReactionPicker(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white24 : Colors.black12,
                    width: 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(0, 1.5),
                    ),
                  ],
                ),
                child: Text(
                  item.reaction!,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ),
      ],
    ),
  ),
),
);
}

  Future<void> _openFileOrCopyPath(BuildContext context, String filePath) async {
    await FileOpenerService.openOrInstallFile(context, filePath);
  }

  Widget _buildFileCard(BuildContext context, bool isDark, Color textColor) {
    final isFolder = item.kind == ChatKind.folder;
    final isApk = FileOpenerService.isApkFile(item.fileName ?? item.filePath);

    return InkWell(
      onTap: item.filePath == null ? null : () => _openFileOrCopyPath(context, item.filePath!),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: isApk
              ? Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.35),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isApk
                    ? const Color(0xFF10B981)
                    : (item.mine ? const Color(0xFF169B62) : const Color(0xFF075E54)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isApk
                    ? Icons.android_rounded
                    : (isFolder ? Icons.folder_rounded : Icons.insert_drive_file_rounded),
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.fileName ?? (isApk ? 'Application Package' : 'Attachment'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_size(item.fileSize ?? 0)} • ${isApk ? (item.mine ? "APK Sent" : "Tap to Install") : (item.status ?? 'Received')}',
                    style: TextStyle(
                      color: isApk && !item.mine
                          ? const Color(0xFF10B981)
                          : textColor.withValues(alpha: 0.7),
                      fontSize: 11.5,
                      fontWeight: isApk && !item.mine ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isApk ? Icons.install_mobile_rounded : Icons.open_in_new_rounded,
              size: 19,
              color: isApk ? const Color(0xFF10B981) : textColor.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
}
