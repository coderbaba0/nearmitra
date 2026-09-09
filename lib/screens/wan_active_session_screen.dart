import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat_item.dart';
import '../models/wan_models.dart';
import '../services/wan_service.dart';
import '../services/wan_webrtc_manager.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/forward_message_dialog.dart';

class WanActiveSessionScreen extends StatefulWidget {
  final WanDevice peer;
  static bool isScreenOpen = false;

  const WanActiveSessionScreen({super.key, required this.peer});

  @override
  State<WanActiveSessionScreen> createState() => _WanActiveSessionScreenState();
}

class _WanActiveSessionScreenState extends State<WanActiveSessionScreen> {
  final WanWebRtcManager _rtcManager = WanWebRtcManager();
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  int _chatDisplayCount = 20;
  bool _isLoadingMore = false;
  Timer? _typingDebounceTimer;
  ChatItem? _replyingToItem;

  @override
  void initState() {
    super.initState();
    WanActiveSessionScreen.isScreenOpen = true;
    WanService().activeChatPeerId = widget.peer.id;
    WanService().clearUnreadCount(widget.peer.id);
    _rtcManager.addListener(_onRtcChanged);
    _scrollController.addListener(_onScroll);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    await _rtcManager.loadChatHistory(widget.peer.id);
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _onTextChanged(String text) {
    if (text.trim().isNotEmpty) {
      _rtcManager.sendTypingIndicator(true);
      _typingDebounceTimer?.cancel();
      _typingDebounceTimer = Timer(const Duration(seconds: 2), () {
        _rtcManager.sendTypingIndicator(false);
      });
    } else {
      _typingDebounceTimer?.cancel();
      _rtcManager.sendTypingIndicator(false);
    }
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      if (_scrollController.position.pixels <= 40 && !_isLoadingMore) {
        final total = _rtcManager.directChatItems.length;
        if (_chatDisplayCount < total) {
          setState(() {
            _isLoadingMore = true;
            _chatDisplayCount = (_chatDisplayCount + 20).clamp(0, total);
          });
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) {
              setState(() {
                _isLoadingMore = false;
              });
            }
          });
        }
      }
    }
  }

  @override
  void dispose() {
    WanActiveSessionScreen.isScreenOpen = false;
    if (WanService().activeChatPeerId == widget.peer.id) {
      WanService().activeChatPeerId = null;
    }
    _typingDebounceTimer?.cancel();
    _rtcManager.sendTypingIndicator(false);
    _rtcManager.removeListener(_onRtcChanged);
    _scrollController.removeListener(_onScroll);
    _msgController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onRtcChanged() {
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _pickAndSendFiles({FileType fileType = FileType.any}) async {
    HapticFeedback.lightImpact();
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: fileType,
        withData: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final filesToSend = result.files.where((f) => f.path != null).toList();
        if (filesToSend.isEmpty) return;

        for (final picked in filesToSend) {
          final file = File(picked.path!);
          if (await file.exists()) {
            await _rtcManager.sendDirectFile(file);
          }
        }
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File send error: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pickAndSendFolder() async {
    HapticFeedback.lightImpact();
    try {
      final String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null) {
        final dir = Directory(selectedDirectory);
        final entities = dir.listSync(recursive: true).whereType<File>().toList();
        if (entities.isEmpty) return;

        for (final file in entities) {
          if (await file.exists()) {
            await _rtcManager.sendDirectFile(file);
          }
        }
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Folder send error: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showAttachmentOptions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2C34) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -2)),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag bar and close button
              Row(
                children: [
                  const SizedBox(width: 30),
                  const Spacer(),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: _attachmentOption(
                      icon: Icons.insert_drive_file_rounded,
                      color: const Color(0xFF10B981),
                      label: 'Files (Multi)',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendFiles(fileType: FileType.any);
                      },
                    ),
                  ),
                  Expanded(
                    child: _attachmentOption(
                      icon: Icons.folder_copy_rounded,
                      color: const Color(0xFFEC4899),
                      label: 'Folder',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendFolder();
                      },
                    ),
                  ),
                  Expanded(
                    child: _attachmentOption(
                      icon: Icons.photo_library_rounded,
                      color: const Color(0xFF6366F1),
                      label: 'Photos/Media',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendFiles(fileType: FileType.media);
                      },
                    ),
                  ),
                  Expanded(
                    child: _attachmentOption(
                      icon: Icons.audiotrack_rounded,
                      color: const Color(0xFFF59E0B),
                      label: 'Audio',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendFiles(fileType: FileType.audio);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachmentOption({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearChat() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 10),
            Text('Clear Chat?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete all messages and media history with ${widget.peer.name}? This cannot be undone.',
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _rtcManager.clearChatHistory(widget.peer.id);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat history cleared'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _typingDebounceTimer?.cancel();
    _rtcManager.sendTypingIndicator(false);
    _msgController.clear();
    HapticFeedback.lightImpact();

    final replyingTo = _replyingToItem;
    if (mounted) {
      setState(() {
        _replyingToItem = null;
      });
    }

    try {
      final wasConnected = _rtcManager.isConnected;
      await _rtcManager.sendDirectMessage(
        text,
        null,
        replyingTo?.id,
        replyingTo?.sender,
        replyingTo?.text ?? replyingTo?.fileName,
      );
      _scrollToBottom();
      if (!wasConnected && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Peer is offline · Message saved to Outbox (will auto-send on connect)'),
            backgroundColor: Color(0xFF005C4B),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Send message error: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Color _getStatusColor(WanConnectionState state) {
    switch (state) {
      case WanConnectionState.connected:
        return const Color(0xFF10B981);
      case WanConnectionState.connecting:
      case WanConnectionState.signaling:
      case WanConnectionState.negotiating:
        return const Color(0xFF00A884);
      case WanConnectionState.failed:
      case WanConnectionState.disconnected:
        return Colors.grey.shade400;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(WanConnectionState state) {
    switch (state) {
      case WanConnectionState.connected:
        return 'Connected';
      case WanConnectionState.connecting:
      case WanConnectionState.signaling:
      case WanConnectionState.negotiating:
        return 'Connecting...';
      case WanConnectionState.failed:
      case WanConnectionState.disconnected:
        return 'Offline';
      default:
        return 'Offline';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final state = _rtcManager.state;
    final isConnected = _rtcManager.isConnected;
    final chatItems = _rtcManager.directChatItems;

    // WhatsApp-like theme colors
    final chatBg = isDark ? const Color(0xFF0B141A) : const Color(0xFFEFEAE2);
    const primaryGreen = Color(0xFF005C4B);
    const accentGreen = Color(0xFF10B981);

    // Active ongoing file transfers
    final ongoingTransfers = _rtcManager.activeTransfers
        .where((t) => !t.isCompleted && !t.isCancelled)
        .toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
      backgroundColor: chatBg,
      appBar: AppBar(
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        backgroundColor: isDark ? const Color(0xFF1F2C34) : primaryGreen,
        foregroundColor: Colors.white,
        elevation: 1.5,
        titleSpacing: 0,
        title: Row(
          children: [
            // Peer Avatar with status indicator ring
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  child: (widget.peer.avatarEmoji != null && widget.peer.avatarEmoji!.trim().isNotEmpty)
                      ? Center(
                          child: Text(
                            widget.peer.avatarEmoji!.trim(),
                            style: const TextStyle(fontSize: 19),
                          ),
                        )
                      : Icon(
                          widget.peer.platform == 'windows'
                              ? Icons.laptop_windows_rounded
                              : Icons.smartphone_rounded,
                          color: Colors.white,
                          size: 21,
                        ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _getStatusColor(state),
                      border: Border.all(
                        color: isDark ? const Color(0xFF1F2C34) : primaryGreen,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.peer.name,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          widget.peer.platform == 'windows' ? 'PC' : 'Mobile',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _rtcManager.peerIsTyping ? 'typing…' : _getStatusText(state),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: _rtcManager.peerIsTyping ? const Color(0xFF6EE7B7) : (isConnected ? const Color(0xFF6EE7B7) : Colors.white70),
                      fontWeight: FontWeight.w500,
                      fontStyle: _rtcManager.peerIsTyping ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Voice Call Icon (Grey, Display Only)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 7),
            child: Icon(Icons.call_rounded, size: 21, color: Colors.white54),
          ),

          // Video Call Icon (Grey, Display Only)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 7),
            child: Icon(Icons.videocam_rounded, size: 23, color: Colors.white54),
          ),

          // More Options Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            tooltip: 'More Options',
            color: isDark ? const Color(0xFF1F2C34) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (value) {
              if (value == 'clear') {
                _confirmClearChat();
              } else if (value == 'end') {
                _rtcManager.disconnect();
                if (context.mounted) Navigator.pop(context);
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: const [
                    Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 20),
                    SizedBox(width: 10),
                    Text('Clear Chat History', style: TextStyle(fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'end',
                child: Row(
                  children: const [
                    Icon(Icons.call_end_rounded, color: Colors.redAccent, size: 20),
                    SizedBox(width: 10),
                    Text('End Session', style: TextStyle(fontWeight: FontWeight.w500, color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Active ongoing file transfers progress bar (WhatsApp Style)
          if (ongoingTransfers.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: isDark ? const Color(0xFF182229) : const Color(0xFFE2E8F0),
              child: Column(
                children: ongoingTransfers.map((t) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3.0),
                    child: Row(
                      children: [
                        Icon(
                          t.isSender ? Icons.upload_rounded : Icons.download_rounded,
                          size: 16,
                          color: accentGreen,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${t.fileName} (${(t.progressPercentage * 100).toInt()}%)',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              LinearProgressIndicator(
                                value: t.progressPercentage,
                                minHeight: 3,
                                backgroundColor: Colors.grey.withValues(alpha: 0.25),
                                valueColor: const AlwaysStoppedAnimation<Color>(accentGreen),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${t.speedMBps.toStringAsFixed(1)} MB/s',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accentGreen),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16, color: Colors.redAccent),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _rtcManager.cancelFileTransfer(t.fileId),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

          // Message List Area with Pagination (Full ChatBubble experience)
          Expanded(
            child: chatItems.isEmpty
                ? Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF182229).withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_rounded, size: 24, color: accentGreen),
                          const SizedBox(height: 6),
                          Text(
                            'End-to-End Direct Session',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Messages and files are transferred directly between devices with zero cloud storage.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Builder(
                    builder: (context) {
                      final totalCount = chatItems.length;
                      final hasMore = totalCount > _chatDisplayCount;
                      final visibleItems = hasMore
                          ? chatItems.sublist(totalCount - _chatDisplayCount)
                          : chatItems;

                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(10, 12, 10, 16),
                        itemCount: visibleItems.length + (hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (hasMore && index == 0) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                    backgroundColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _chatDisplayCount = (_chatDisplayCount + 20).clamp(0, totalCount);
                                    });
                                  },
                                  icon: const Icon(Icons.history_rounded, size: 16, color: accentGreen),
                                  label: Text(
                                    'Load earlier messages (${totalCount - _chatDisplayCount} more)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white70 : Colors.black87,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }

                          final itemIndex = hasMore ? index - 1 : index;
                          final item = visibleItems[itemIndex];
                          return ChatBubble(
                            item: item,
                            onReact: (emoji) => _rtcManager.sendReaction(item.id, emoji),
                            onCancel: item.status == 'Queued'
                                ? () => _rtcManager.cancelQueuedItem(item.id)
                                : (item.kind == ChatKind.file && (item.status == 'sending' || item.status == 'downloading'))
                                    ? () => _rtcManager.cancelFileTransfer(item.id)
                                    : null,
                            onReply: (replyItem) {
                              setState(() {
                                _replyingToItem = replyItem;
                              });
                            },
                            onForward: (fwdItem) {
                              ForwardMessageDialog.show(
                                context,
                                item: fwdItem,
                                onForwardComplete: (targetName) async {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Forwarded to $targetName'),
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                  await _loadHistory();
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
          ),

          // Pinned Floating WhatsApp Typing Indicator (Always visible right above input bar)
          if (_rtcManager.peerIsTyping)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
              child: _WhatsAppTypingIndicator(
                isDark: isDark,
                peerName: widget.peer.name,
              ),
            ),

          // WhatsApp Quoted Reply Preview Bar
          if (_replyingToItem != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2C34) : const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(12),
                border: Border(
                  left: BorderSide(
                    color: isDark ? const Color(0xFF25D366) : const Color(0xFF00A884),
                    width: 4,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _replyingToItem!.mine ? 'You' : _replyingToItem!.sender,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFF25D366) : const Color(0xFF00A884),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _replyingToItem!.kind == ChatKind.text
                              ? (_replyingToItem!.text ?? '')
                              : '📁 ${_replyingToItem!.fileName ?? "Attachment"}',
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
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: isDark ? Colors.white60 : Colors.black54,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    splashRadius: 16,
                    onPressed: () {
                      setState(() {
                        _replyingToItem = null;
                      });
                    },
                    tooltip: 'Cancel reply',
                  ),
                ],
              ),
            ),

          // Professional Floating Chat Input Bar (WhatsApp / Telegram style)
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
              color: Colors.transparent,
              child: Row(
                children: [
                  // Text input container with attachment icon
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF202C33) : Colors.white,
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: _showAttachmentOptions,
                            icon: const Icon(Icons.attach_file_rounded),
                            color: isDark ? Colors.grey[400] : const Color(0xFF54656F),
                            tooltip: 'Attach File / Media',
                          ),
                          Expanded(
                            child: TextField(
                              controller: _msgController,
                              focusNode: _focusNode,
                              minLines: 1,
                              maxLines: 3,
                              keyboardType: TextInputType.multiline,
                              textCapitalization: TextCapitalization.sentences,
                              onChanged: _onTextChanged,
                              style: TextStyle(
                                fontSize: 15,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              decoration: InputDecoration(
                                hintText: isConnected
                                    ? 'Message…'
                                    : 'Peer offline • Queued in Outbox',
                                hintStyle: TextStyle(
                                  fontSize: 14.5,
                                  color: isDark ? Colors.grey[500] : const Color(0xFF8696A0),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Floating Circular Send Button
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF169B62),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF169B62).withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 22,
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
    ),
    );
  }
}

class _WhatsAppTypingIndicator extends StatefulWidget {
  final bool isDark;
  final String peerName;

  const _WhatsAppTypingIndicator({
    required this.isDark,
    required this.peerName,
  });

  @override
  State<_WhatsAppTypingIndicator> createState() => _WhatsAppTypingIndicatorState();
}

class _WhatsAppTypingIndicatorState extends State<_WhatsAppTypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bubbleBg = widget.isDark ? const Color(0xFF1F2C34) : Colors.white;
    const accentGreen = Color(0xFF25D366);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bubbleBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isDark ? Colors.white12 : Colors.black12,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: widget.isDark ? 0.25 : 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (index) {
                    final delay = index * 0.2;
                    final progress = (_controller.value - delay) % 1.0;
                    final scale = 0.6 + (0.4 * (1.0 - (progress - 0.5).abs() * 2).clamp(0.0, 1.0));
                    final opacity = 0.4 + (0.6 * (1.0 - (progress - 0.5).abs() * 2).clamp(0.0, 1.0));

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: 7 * scale,
                      height: 7 * scale,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentGreen.withValues(alpha: opacity),
                      ),
                    );
                  }),
                );
              },
            ),
            const SizedBox(width: 8),
            Text(
              '${widget.peerName} is typing…',
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF25D366),
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
