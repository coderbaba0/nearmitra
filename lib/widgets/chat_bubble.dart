import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';

import '../models/chat_item.dart';
import '../services/file_opener_service.dart';

class ChatBubble extends StatefulWidget {
  const ChatBubble({
    super.key,
    required this.item,
    this.onCancel,
    this.onReact,
    this.onReply,
    this.onForward,
  });

  final ChatItem item;
  final VoidCallback? onCancel;
  final ValueChanged<String>? onReact;
  final ValueChanged<ChatItem>? onReply;
  final ValueChanged<ChatItem>? onForward;

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> with SingleTickerProviderStateMixin {
  double _dragOffset = 0.0;
  static const double _replyThreshold = 48.0;
  static const double _maxDragOffset = 70.0;
  late AnimationController _springController;
  late Animation<double> _springAnimation;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        if (mounted) {
          setState(() {
            _dragOffset = _springAnimation.value;
          });
        }
      });
    _springAnimation = const AlwaysStoppedAnimation<double>(0.0);
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (widget.onReply == null) return;
    if (details.primaryDelta == null) return;

    // Only allow swiping to the right (WhatsApp standard)
    final newOffset = (_dragOffset + details.primaryDelta!).clamp(0.0, _maxDragOffset);
    if (newOffset != _dragOffset) {
      if (_dragOffset < _replyThreshold && newOffset >= _replyThreshold) {
        HapticFeedback.lightImpact();
      }
      setState(() {
        _dragOffset = newOffset;
      });
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_dragOffset >= _replyThreshold) {
      HapticFeedback.mediumImpact();
      widget.onReply?.call(widget.item);
    }

    _springAnimation = Tween<double>(
      begin: _dragOffset,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _springController,
      curve: Curves.easeOutBack,
    ));

    _springController.forward(from: 0.0);
  }

  void _showContextMenu(BuildContext context) {
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final item = widget.item;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle & Header with Close Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 12, 6),
                  child: Row(
                    children: [
                      const Spacer(),
                      Container(
                        width: 42,
                        height: 4.5,
                        margin: const EdgeInsets.only(left: 28),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 22),
                        color: isDark ? Colors.white70 : Colors.black54,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        splashRadius: 20,
                        onPressed: () => Navigator.pop(ctx),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),

                // Floating Reactions Row
                if (widget.onReact != null)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF111B21) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(28),
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

                const Divider(height: 18),

                // Reply Option
                if (widget.onReply != null)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 2),
                    leading: const Icon(Icons.reply_rounded, color: Color(0xFF25D366), size: 24),
                    title: const Text('Reply', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onReply?.call(item);
                    },
                  ),

                // Forward Option
                if (widget.onForward != null)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 2),
                    leading: const Icon(Icons.shortcut_rounded, color: Color(0xFF3B82F6), size: 24),
                    title: const Text('Forward', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onForward?.call(item);
                    },
                  ),

                // Copy Option (Text or File Name/Path)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 2),
                  leading: Icon(Icons.copy_rounded, color: isDark ? Colors.white70 : Colors.black87, size: 24),
                  title: Text(
                    item.kind == ChatKind.text ? 'Copy Text' : 'Copy File Name',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    final textToCopy = item.kind == ChatKind.text
                        ? (item.text ?? '')
                        : (item.filePath ?? item.fileName ?? '');
                    if (textToCopy.isNotEmpty) {
                      Clipboard.setData(ClipboardData(text: textToCopy));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(item.kind == ChatKind.text ? 'Message copied to clipboard' : 'File info copied'),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),

                // Share Option (Text or File)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 2),
                  leading: Icon(Icons.share_rounded, color: isDark ? Colors.white70 : Colors.black87, size: 24),
                  title: const Text('Share…', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      if (item.kind == ChatKind.text && item.text != null && item.text!.isNotEmpty) {
                        await Share.share(item.text!);
                      } else if (item.filePath != null) {
                        final file = File(item.filePath!);
                        if (await file.exists()) {
                          await Share.shareXFiles([XFile(item.filePath!)]);
                        } else if (item.fileName != null) {
                          await Share.share(item.fileName!);
                        }
                      }
                    } catch (_) {}
                  },
                ),

                // Cancel Queued Option
                if (widget.onCancel != null)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 2),
                    leading: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 24),
                    title: const Text('Cancel message', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 16)),
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onCancel?.call();
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _emojiButton(BuildContext ctx, String emoji) {
    final isCurrent = widget.item.reaction == emoji;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Navigator.pop(ctx);
        widget.onReact?.call(isCurrent ? '' : emoji);
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

  Widget _buildQuotedReplyBox(BuildContext context, bool isDark, bool mine) {
    final item = widget.item;
    if (item.replyToText == null && item.replyToSender == null) {
      return const SizedBox.shrink();
    }

    final accentColor = mine
        ? (isDark ? const Color(0xFF25D366) : const Color(0xFF005C4B))
        : (isDark ? const Color(0xFF53BDEB) : const Color(0xFF0284C7));

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 3.5,
            height: 28,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.replyToSender ?? 'Quoted message',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  item.replyToText ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final item = widget.item;
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

    final swipeProgress = (_dragOffset / _replyThreshold).clamp(0.0, 1.0);

    return GestureDetector(
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      onLongPress: () => _showContextMenu(context),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // Animated Swipe-to-Reply Icon on the left
          if (_dragOffset > 0)
            Positioned(
              left: 12,
              child: Opacity(
                opacity: swipeProgress,
                child: Transform.scale(
                  scale: 0.5 + (0.5 * swipeProgress),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withValues(alpha: 0.2 + (0.8 * (swipeProgress == 1.0 ? 1 : 0))),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.reply_rounded,
                      color: swipeProgress >= 1.0 ? Colors.white : const Color(0xFF25D366),
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),

          // Main Chat Bubble with horizontal translation offset
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
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
                        // Forwarded message label
                        if (item.isForwarded) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.shortcut_rounded,
                                size: 13,
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Forwarded',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: isDark ? Colors.white54 : Colors.black45,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                        ],

                        // Sender Name (if incoming)
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

                        // Quoted Reply Box Preview
                        _buildQuotedReplyBox(context, isDark, mine),

                        // Message Text Body
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

                        // Footer (Time, Copy, Share, Mesh, Status)
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
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.hub_rounded, size: 11, color: Color(0xFF10B981)),
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
                                      if (widget.onCancel != null) ...[
                                        const SizedBox(width: 4),
                                        InkWell(
                                          onTap: widget.onCancel,
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

                  // Emoji Reaction Badge
                  if (item.reaction != null && item.reaction!.isNotEmpty)
                    Positioned(
                      bottom: 0,
                      right: mine ? null : 16,
                      left: mine ? 16 : null,
                      child: GestureDetector(
                        onTap: () => _showContextMenu(context),
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
        ],
      ),
    );
  }

  Future<void> _openFileOrCopyPath(BuildContext context, String filePath) async {
    await FileOpenerService.openOrInstallFile(context, filePath);
  }

  Widget _buildFileCard(BuildContext context, bool isDark, Color textColor) {
    final item = widget.item;
    final isFolder = item.kind == ChatKind.folder;
    final fileName = item.fileName ?? item.filePath?.split(RegExp(r'[/\\]')).last ?? 'Attachment';
    final isApk = FileOpenerService.isApkFile(fileName);
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';

    IconData fileIcon = Icons.insert_drive_file_rounded;
    Color iconBgColor = item.mine ? const Color(0xFF169B62) : const Color(0xFF075E54);

    if (isApk) {
      fileIcon = Icons.android_rounded;
      iconBgColor = const Color(0xFF10B981);
    } else if (isFolder || ext == 'zip' || ext == 'rar' || ext == '7z' || ext == 'tar' || ext == 'gz') {
      fileIcon = isFolder ? Icons.folder_rounded : Icons.folder_zip_rounded;
      iconBgColor = const Color(0xFFF59E0B);
    } else if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'].contains(ext)) {
      fileIcon = Icons.image_rounded;
      iconBgColor = const Color(0xFF3B82F6);
    } else if (['mp4', 'mkv', 'mov', 'avi', 'webm', '3gp'].contains(ext)) {
      fileIcon = Icons.video_file_rounded;
      iconBgColor = const Color(0xFF8B5CF6);
    } else if (['mp3', 'm4a', 'wav', 'aac', 'flac', 'ogg', 'opus'].contains(ext)) {
      fileIcon = Icons.audiotrack_rounded;
      iconBgColor = const Color(0xFFEC4899);
    } else if (ext == 'pdf') {
      fileIcon = Icons.picture_as_pdf_rounded;
      iconBgColor = const Color(0xFFEF4444);
    } else if (['doc', 'docx', 'txt', 'rtf', 'pdf', 'csv', 'xls', 'xlsx', 'ppt', 'pptx'].contains(ext)) {
      fileIcon = Icons.description_rounded;
      iconBgColor = const Color(0xFF0EA5E9);
    }

    return InkWell(
      onTap: item.filePath == null ? null : () => _openFileOrCopyPath(context, item.filePath!),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.black.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: iconBgColor.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                fileIcon,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _size(item.fileSize ?? 0),
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        ' • ',
                        style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 11),
                      ),
                      Text(
                        isApk
                            ? (item.mine ? 'APK Sent' : 'Tap to Install')
                            : (item.status ?? 'Received'),
                        style: TextStyle(
                          color: isApk && !item.mine
                              ? const Color(0xFF10B981)
                              : textColor.withValues(alpha: 0.7),
                          fontSize: 11,
                          fontWeight: isApk && !item.mine ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isApk ? Icons.install_mobile_rounded : (item.mine ? Icons.file_present_rounded : Icons.open_in_new_rounded),
                size: 16,
                color: isApk ? const Color(0xFF10B981) : textColor.withValues(alpha: 0.7),
              ),
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
