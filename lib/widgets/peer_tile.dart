import 'package:flutter/material.dart';

import '../models/peer.dart';
import '../services/wan_service.dart';

class PeerTile extends StatelessWidget {
  const PeerTile({
    super.key,
    required this.peer,
    required this.selected,
    required this.onTap,
    this.isPinned = false,
    this.onLongPress,
  });

  final Peer peer;
  final bool selected;
  final VoidCallback onTap;
  final bool isPinned;
  final VoidCallback? onLongPress;

  IconData _getDeviceIcon(Peer peer) {
    if (peer.id == 'local_ai_assistant') {
      return Icons.auto_awesome_rounded;
    }

    final lowerName = peer.name.toLowerCase();
    final lowerId = peer.id.toLowerCase();

    // 1. Windows PC / Laptop -> Computer Icon
    if (lowerName.contains('windows') ||
        lowerName.contains('win-') ||
        lowerName.contains('win_') ||
        lowerName.contains('win1') ||
        lowerName.contains('win') ||
        lowerName.contains('desktop') ||
        lowerName.contains('laptop') ||
        lowerName.contains('pc') ||
        lowerId.contains('win')) {
      return Icons.computer_rounded;
    }

    // 2. All other connected devices in NearMitra ecosystem -> Phone Icon
    return Icons.phone_android_rounded;
  }

  bool _isEmoji(String char) {
    if (char.isEmpty) return false;
    return char.runes.any((r) =>
        (r >= 0x1F300 && r <= 0x1F9FF) ||
        (r >= 0x2600 && r <= 0x27BF) ||
        (r >= 0x1FA70 && r <= 0x1FAFF) ||
        (r >= 0xFE00 && r <= 0xFE0F) ||
        (r >= 0x1F000 && r <= 0x1F2FF));
  }

  String? _resolveAvatarEmoji(Peer peer) {
    // 1. Direct peer.avatarEmoji
    if (peer.avatarEmoji != null && peer.avatarEmoji!.trim().isNotEmpty) {
      return peer.avatarEmoji!.trim();
    }

    // 2. Check if peer.name starts with emoji
    final trimmed = peer.name.trim();
    if (trimmed.isNotEmpty) {
      final firstChar = trimmed.characters.first;
      if (_isEmoji(firstChar)) {
        return firstChar;
      }
    }

    // 3. Match against WanService trusted devices list (by ID or name)
    try {
      final wanDevices = WanService.instance.trustedDevicesList;
      final peerNameClean = peer.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      for (final wd in wanDevices) {
        if (wd.avatarEmoji != null && wd.avatarEmoji!.trim().isNotEmpty) {
          final wdNameClean = wd.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (wd.id == peer.id ||
              wd.name.toLowerCase() == peer.name.toLowerCase() ||
              (peerNameClean.isNotEmpty && wdNameClean.isNotEmpty &&
                  (wdNameClean.contains(peerNameClean) || peerNameClean.contains(wdNameClean)))) {
            return wd.avatarEmoji!.trim();
          }
        }
      }

      final publicDevices = WanService.instance.publicDevices;
      for (final pd in publicDevices) {
        if (pd.avatarEmoji != null && pd.avatarEmoji!.trim().isNotEmpty) {
          final pdNameClean = pd.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (pd.id == peer.id ||
              pd.name.toLowerCase() == peer.name.toLowerCase() ||
              (peerNameClean.isNotEmpty && pdNameClean.isNotEmpty &&
                  (pdNameClean.contains(peerNameClean) || peerNameClean.contains(pdNameClean)))) {
            return pd.avatarEmoji!.trim();
          }
        }
      }
    } catch (_) {}

    return null;
  }

  Widget _buildLeadingAvatar(BuildContext context, ColorScheme scheme) {
    if (peer.id == 'local_ai_assistant') {
      return CircleAvatar(
        radius: 21,
        backgroundColor: scheme.primary.withValues(alpha: .13),
        child: Icon(Icons.auto_awesome_rounded, color: scheme.primary),
      );
    }

    final emoji = _resolveAvatarEmoji(peer);

    if (emoji != null && emoji.isNotEmpty) {
      return CircleAvatar(
        radius: 21,
        backgroundColor: scheme.primary.withValues(alpha: .13),
        child: Text(
          emoji,
          style: const TextStyle(fontSize: 20),
        ),
      );
    }

    return CircleAvatar(
      radius: 21,
      backgroundColor: scheme.primary.withValues(alpha: .13),
      child: Icon(_getDeviceIcon(peer), color: scheme.primary),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected ? scheme.primaryContainer.withValues(alpha: .75) : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? scheme.primary.withValues(alpha: .28) : scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            _buildLeadingAvatar(context, scheme),
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: peer.isOnline ? const Color(0xFF22C55E) : scheme.outline,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                peer.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (peer.isAiHost) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 10, color: Color(0xFF10B981)),
                    SizedBox(width: 3),
                    Text(
                      'Nearby AI',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                    ),
                  ],
                ),
              ),
            ],
            if (peer.isMeshPeer) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hub_rounded, size: 10, color: Color(0xFF3B82F6)),
                    SizedBox(width: 3),
                    Text(
                      'Mesh Relay',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF3B82F6)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        subtitle: peer.isTyping
            ? const Text(
                'typing…',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF22C55E),
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                ),
              )
            : Text(
                peer.isMeshPeer
                    ? 'Mesh Relay • via ${peer.relayViaName ?? 'Intermediate'}'
                    : peer.ip,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPinned) ...[
              Transform.rotate(
                angle: 0.45,
                child: Icon(
                  Icons.push_pin_rounded,
                  size: 16,
                  color: scheme.primary.withValues(alpha: 0.85),
                ),
              ),
              if (peer.unreadCount > 0) const SizedBox(width: 8),
            ],
            if (peer.unreadCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x4025D366),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '${peer.unreadCount > 99 ? '99+' : peer.unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
