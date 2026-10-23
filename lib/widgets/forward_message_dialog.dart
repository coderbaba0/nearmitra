import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/conversation_providers.dart';
import '../models/chat_item.dart';
import '../models/peer.dart';
import '../models/wan_models.dart';
import '../services/nearby_service.dart';
import '../services/wan_service.dart';

class ForwardMessageDialog extends ConsumerStatefulWidget {
  const ForwardMessageDialog({
    super.key,
    required this.item,
    required this.onForwardComplete,
  });

  final ChatItem item;
  final Function(String targetName) onForwardComplete;

  static Future<void> show(
    BuildContext context, {
    required ChatItem item,
    required Function(String targetName) onForwardComplete,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ForwardMessageDialog(
        item: item,
        onForwardComplete: onForwardComplete,
      ),
    );
  }

  @override
  ConsumerState<ForwardMessageDialog> createState() =>
      _ForwardMessageDialogState();
}

class _ForwardMessageDialogState extends ConsumerState<ForwardMessageDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _resolveNearbyAvatar(Peer peer) {
    if (peer.avatarEmoji != null && peer.avatarEmoji!.trim().isNotEmpty) {
      return peer.avatarEmoji!.trim();
    }
    final lower = peer.name.toLowerCase();
    if (lower.contains('windows') ||
        lower.contains('pc') ||
        lower.contains('desktop') ||
        lower.contains('laptop') ||
        lower.contains('win')) {
      return '💻';
    }
    return '📱';
  }

  String _resolveWanAvatar(WanDevice dev) {
    if (dev.avatarEmoji != null && dev.avatarEmoji!.trim().isNotEmpty) {
      return dev.avatarEmoji!.trim();
    }
    final lower = dev.name.toLowerCase();
    if (lower.contains('windows') ||
        lower.contains('pc') ||
        lower.contains('desktop') ||
        lower.contains('laptop') ||
        lower.contains('win')) {
      return '💻';
    }
    return '📱';
  }

  Future<void> _forwardToNearbyPeer(Peer peer) async {
    final controller = ref.read(conversationControllerProvider);
    Navigator.pop(context);
    final item = widget.item;
    if (item.kind == ChatKind.text && item.text != null) {
      await controller.sendText(peer, item.text!, forwarded: true);
    } else if (item.kind == ChatKind.folder && item.filePath != null) {
      await controller.sendFolder(peer, item.filePath!);
    } else if (item.filePath != null && await File(item.filePath!).exists()) {
      await controller.sendFile(peer, File(item.filePath!), forwarded: true);
    }
    widget.onForwardComplete(peer.name);
  }

  Future<void> _forwardToWanPeer(WanDevice device) => _forwardToNearbyPeer(
      ref.read(conversationControllerProvider).peerForWan(device));

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationControllerProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;

    final nearbyPeers = NearbyService.instance.peers.where((p) {
      if (_filter.isEmpty) return true;
      return p.name.toLowerCase().contains(_filter.toLowerCase());
    }).toList();

    final nearbyIds = nearbyPeers
        .map((p) => conversations.canonicalId(p.internetDeviceId ?? p.id))
        .toSet();
    final wanDevices = WanService.instance.trustedDevicesList.where((d) {
      if (nearbyIds.contains(d.id)) return false;
      if (_filter.isEmpty) return true;
      return d.name.toLowerCase().contains(_filter.toLowerCase());
    }).toList();

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2C34) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 42,
                height: 4.5,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),

            // Header Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.shortcut_rounded,
                      color: Color(0xFF25D366), size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Forward Message',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Forwarded Message Content Preview
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF111B21) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF25D366).withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.mine ? 'You' : widget.item.sender,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF25D366),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.item.kind == ChatKind.text
                              ? (widget.item.text ?? '')
                              : '📁 ${widget.item.fileName ?? 'File attachment'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 15),
                onChanged: (val) => setState(() => _filter = val.trim()),
                decoration: InputDecoration(
                  hintText: 'Search contact or device…',
                  hintStyle: const TextStyle(fontSize: 15),
                  prefixIcon: const Icon(Icons.search_rounded, size: 22),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF111B21)
                      : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // List of Contacts / Peers
            Flexible(
              child: (nearbyPeers.isEmpty && wanDevices.isEmpty)
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          'No available peers found to forward',
                          style: TextStyle(color: Colors.grey, fontSize: 14.5),
                        ),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      children: [
                        if (nearbyPeers.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            child: Text(
                              'NEARBY NETWORK',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: scheme.primary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          ...nearbyPeers.map((p) {
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 4),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              leading: CircleAvatar(
                                radius: 22,
                                backgroundColor:
                                    scheme.primary.withValues(alpha: 0.15),
                                child: Text(_resolveNearbyAvatar(p),
                                    style: const TextStyle(fontSize: 20)),
                              ),
                              title: Text(
                                p.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15.5),
                              ),
                              subtitle: Text(
                                p.isMeshPeer ? 'Mesh Relay' : p.ip,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant),
                              ),
                              trailing: const Icon(Icons.send_rounded,
                                  size: 22, color: Color(0xFF25D366)),
                              onTap: () => _forwardToNearbyPeer(p),
                            );
                          }),
                        ],
                        if (wanDevices.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            child: Text(
                              'INTERNET (WAN) CONTACTS',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF005C4B),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          ...wanDevices.map((d) {
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 4),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              leading: CircleAvatar(
                                radius: 22,
                                backgroundColor: const Color(0xFF005C4B)
                                    .withValues(alpha: 0.15),
                                child: Text(_resolveWanAvatar(d),
                                    style: const TextStyle(fontSize: 20)),
                              ),
                              title: Text(
                                d.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15.5),
                              ),
                              subtitle: Text(
                                d.isOnline ? 'Online' : 'Offline (Outbox)',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: d.isOnline
                                      ? const Color(0xFF22C55E)
                                      : Colors.grey,
                                ),
                              ),
                              trailing: const Icon(Icons.send_rounded,
                                  size: 22, color: Color(0xFF25D366)),
                              onTap: () => _forwardToWanPeer(d),
                            );
                          }),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
