import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:open_filex/open_filex.dart';

import '../models/chat_item.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.item});

  final ChatItem item;

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
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.84,
          ),
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
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
                    Text(
                      item.isAi ? (isAiWarning ? 'System Notice' : item.sender) : item.sender,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: item.isAi
                            ? (isAiWarning ? const Color(0xFFFB8C00) : const Color(0xFF10B981))
                            : (isDark ? const Color(0xFF53BDEB) : const Color(0xFF075E54)),
                      ),
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
                      onTap: () {
                        if (item.text != null && item.text!.isNotEmpty) {
                          Clipboard.setData(ClipboardData(text: item.text!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('AI response copied for sharing'),
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
                    const Icon(
                      Icons.done_all_rounded,
                      size: 16,
                      color: Color(0xFF53BDEB),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openFileOrCopyPath(BuildContext context, String filePath) async {
    final file = File(filePath);
    final dir = Directory(filePath);

    if (!await file.exists() && !await dir.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File not found: $filePath'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final res = await OpenFilex.open(filePath);
    if (res.type != ResultType.done && context.mounted) {
      Clipboard.setData(ClipboardData(text: filePath));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File saved at: $filePath (Path copied to clipboard)'),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'COPY',
            onPressed: () => Clipboard.setData(ClipboardData(text: filePath)),
          ),
        ),
      );
    }
  }

  Widget _buildFileCard(BuildContext context, bool isDark, Color textColor) {
    final isFolder = item.kind == ChatKind.folder;
    return InkWell(
      onTap: item.filePath == null ? null : () => _openFileOrCopyPath(context, item.filePath!),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: item.mine ? const Color(0xFF169B62) : const Color(0xFF075E54),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isFolder ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
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
                    item.fileName ?? 'Attachment',
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
                    '${_size(item.fileSize ?? 0)} • ${item.status ?? 'Received'}',
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.7),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.open_in_new_rounded,
              size: 18,
              color: textColor.withValues(alpha: 0.7),
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
