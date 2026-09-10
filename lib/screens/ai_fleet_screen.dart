import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/peer.dart';
import '../providers/ai_settings_providers.dart';
import '../services/ai_settings_service.dart';
import '../services/nearby_service.dart';
import 'ai_settings_screen.dart';
import 'stream_hub_screen.dart';

class AiFleetScreen extends ConsumerStatefulWidget {
  const AiFleetScreen({
    super.key,
    required this.service,
    required this.onOpenChatWithPeer,
    required this.onStartCall,
  });

  final NearbyService service;
  final void Function(Peer peer) onOpenChatWithPeer;
  final void Function(Peer peer, bool isVideo) onStartCall;

  @override
  ConsumerState<AiFleetScreen> createState() => _AiFleetScreenState();
}

class _AiFleetScreenState extends ConsumerState<AiFleetScreen> {
  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onServiceChanged);
    AiSettingsService().addListener(_onAiServiceChanged);
  }

  @override
  void dispose() {
    widget.service.removeListener(_onServiceChanged);
    AiSettingsService().removeListener(_onAiServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _onAiServiceChanged() {
    if (mounted) setState(() {});
  }

  bool _isWindowsDevice(Peer peer) {
    final lower = peer.name.toLowerCase();
    return lower.contains('windows') ||
        lower.contains('pc') ||
        lower.contains('desktop') ||
        lower.contains('laptop') ||
        lower.contains('win-') ||
        lower.contains('win1') ||
        lower.contains('win_');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        duration: const Duration(milliseconds: 1800),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final aiService = AiSettingsService();
    final aiConfig = ref.watch(aiConfigProvider);
    final isAiKeyConfigured = (aiConfig.provider == 'gemini' &&
            aiConfig.geminiApiKey.trim().isNotEmpty) ||
        (aiConfig.provider == 'openai' &&
            aiConfig.openaiApiKey.trim().isNotEmpty);

    final peers = widget.service.peers
        .where((p) => p.id != 'local_ai_assistant')
        .toList();

    final allowedCount = peers
        .where((p) => p.isAiHostAllowed || aiService.isPeerAllowed(p.id, p.ip))
        .length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'AI Fleet Devices',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'AI Model Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Network Scan',
            onPressed: () {
              widget.service.announce();
              widget.service.scanSubnet();
              _toast('Scanning local network for devices…');
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Host AI Status & API Key Validation Banner
              if (!isAiKeyConfigured)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Color(0xFFEF4444), size: 22),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Host AI API Key Setup Required',
                              style: TextStyle(
                                color: Color(0xFFEF4444),
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'To allow connected peer devices to use your AI in Nearby AI mode, configure your Google Gemini or OpenAI API key in AI Settings.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.key_rounded, size: 17),
                          label: const Text(
                            'Configure AI API Key Now',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const AiSettingsScreen()),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [
                              const Color(0xFF064E3B).withValues(alpha: 0.6),
                              const Color(0xFF0F172A),
                            ]
                          : [
                              const Color(0xFFECFDF5),
                              const Color(0xFFF1F5F9),
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.4),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xFF10B981),
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Host AI Engine Active',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15.5,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    aiConfig.provider.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${aiService.totalAiRequests} total requests processed • Ready to share with connected nodes',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // 2. Real-Time Analytics Cards Grid
              const Text(
                'FLEET ANALYTICS & METRICS',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      title: 'Connected Devices',
                      value: '${peers.length}',
                      icon: Icons.devices_rounded,
                      color: const Color(0xFF3B82F6),
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricCard(
                      title: 'AI Permitted Nodes',
                      value: '$allowedCount / ${peers.length}',
                      icon: Icons.verified_user_rounded,
                      color: const Color(0xFF10B981),
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      title: 'AI Requests Served',
                      value: '${aiService.totalAiRequests}',
                      icon: Icons.bolt_rounded,
                      color: const Color(0xFFF59E0B),
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricCard(
                      title: 'Mesh Relay',
                      value: widget.service.meshRelayEnabled ? 'Active' : 'Off',
                      icon: Icons.hub_rounded,
                      color: const Color(0xFF8B5CF6),
                      isDark: isDark,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // 3. Device Fleet & Batch Action Toolbar
              Row(
                children: [
                  const Text(
                    'CONNECTED NODES',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: Colors.grey,
                    ),
                  ),
                  const Spacer(),
                  if (peers.isNotEmpty) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        side: const BorderSide(
                            color: Color(0xFF10B981), width: 1.2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          size: 14, color: Color(0xFF10B981)),
                      label: const Text(
                        'Allow All',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                        ),
                      ),
                      onPressed: () {
                        final peerIds = peers.map((p) => p.id);
                        aiService.allowAllPeers(peerIds);
                        for (final p in peers) {
                          p.isAiHostAllowed = true;
                        }
                        setState(() {});
                        _toast(
                            'Nearby AI access allowed for all connected devices');
                      },
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        side: const BorderSide(
                            color: Color(0xFFEF4444), width: 1.2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.block_rounded,
                          size: 14, color: Color(0xFFEF4444)),
                      label: const Text(
                        'Revoke All',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                      onPressed: () {
                        aiService.revokeAllPeers();
                        for (final p in peers) {
                          p.isAiHostAllowed = false;
                        }
                        setState(() {});
                        _toast('Nearby AI access revoked for all devices');
                      },
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              // 4. Peer Cards List
              if (peers.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 40, horizontal: 20),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      Icon(
                        Icons.sensors_off_rounded,
                        size: 52,
                        color: Colors.grey.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'No nearby devices discovered yet',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Open NearMitra on other devices on the same Wi-Fi or Wi-Fi Direct network',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: Colors.grey),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: () {
                          widget.service.announce();
                          widget.service.scanSubnet();
                          _toast('Scanning local network…');
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text(
                          'Scan Local Network Now',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...peers.map((p) {
                  final isAllowed = p.isAiHostAllowed ||
                      aiService.isPeerAllowed(p.id, p.ip);
                  final requestCount = aiService.getPeerRequestCount(p.id);
                  final isWin = _isWindowsDevice(p);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isAllowed
                            ? const Color(0xFF10B981).withValues(alpha: 0.45)
                            : (isDark
                                ? Colors.white12
                                : const Color(0xFFE2E8F0)),
                        width: isAllowed ? 1.6 : 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: isDark ? 0.25 : 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Device Header
                        Row(
                          children: [
                            Stack(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: isAllowed
                                      ? const Color(0xFF10B981)
                                      : (isDark
                                          ? Colors.white24
                                          : Colors.black26),
                                  child: Text(
                                    p.name.isNotEmpty
                                        ? p.name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 11,
                                    height: 11,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF22C55E),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isDark
                                            ? const Color(0xFF1E293B)
                                            : Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          p.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: isWin
                                              ? const Color(0xFF3B82F6)
                                                  .withValues(alpha: 0.15)
                                              : const Color(0xFF10B981)
                                                  .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          isWin ? 'WINDOWS' : 'ANDROID',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: isWin
                                                ? const Color(0xFF3B82F6)
                                                : const Color(0xFF10B981),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'IP: ${p.ip} • $requestCount AI requests served',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 10),

                        // Nearby AI Permission Toggle Switch
                        Row(
                          children: [
                            Icon(
                              isAllowed
                                  ? Icons.check_circle_rounded
                                  : Icons.lock_outline_rounded,
                              size: 18,
                              color: isAllowed
                                  ? const Color(0xFF10B981)
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isAllowed
                                        ? 'Nearby AI Access Granted'
                                        : 'Nearby AI Access Restricted',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isAllowed
                                          ? const Color(0xFF10B981)
                                          : (isDark
                                              ? Colors.white70
                                              : Colors.black87),
                                    ),
                                  ),
                                  Text(
                                    isAllowed
                                        ? 'Can query your host AI model over LAN'
                                        : 'Cannot access your AI model',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              activeThumbColor: const Color(0xFF10B981),
                              activeTrackColor: const Color(0xFF10B981)
                                  .withValues(alpha: 0.35),
                              value: isAllowed,
                              onChanged: (val) {
                                p.isAiHostAllowed = val;
                                aiService.setPeerAllowed(p.id, val);
                                setState(() {});
                                _toast(val
                                    ? 'Nearby AI allowed for ${p.name}'
                                    : 'Nearby AI revoked for ${p.name}');
                              },
                            ),
                          ],
                        ),

                        // Functional Remote Action Shortcuts
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _buildActionButton(
                              icon: Icons.videocam_rounded,
                              label: 'CCTV Stream',
                              color: const Color(0xFF3B82F6),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StreamHubScreen(
                                      service: widget.service,
                                      targetPeer: p,
                                      initialStreamType: 'camera',
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            _buildActionButton(
                              icon: Icons.mic_rounded,
                              label: 'Live Audio',
                              color: const Color(0xFF8B5CF6),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StreamHubScreen(
                                      service: widget.service,
                                      targetPeer: p,
                                      initialStreamType: 'audio',
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            if (!isWin) ...[
                              _buildActionButton(
                                icon: Icons.call_rounded,
                                label: 'Voice Call',
                                color: const Color(0xFF10B981),
                                onTap: () {
                                  Navigator.pop(context);
                                  widget.onStartCall(p, false);
                                },
                              ),
                              const SizedBox(width: 8),
                            ],
                            _buildActionButton(
                              icon: Icons.chat_bubble_rounded,
                              label: 'P2P Chat',
                              color: const Color(0xFFF59E0B),
                              onTap: () {
                                Navigator.pop(context);
                                widget.onOpenChatWithPeer(p);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),

              const SizedBox(height: 28),

              // 5. Creative Small Footer
              Center(
                child: Column(
                  children: [
                    Divider(
                      color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.mail_outline_rounded,
                          size: 13,
                          color: Color(0xFF10B981),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'For support or suggestions: theflutterfever@gmail.com',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Built with ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey,
                          ),
                        ),
                        const Icon(
                          Icons.favorite_rounded,
                          size: 14,
                          color: Color(0xFFEF4444),
                        ),
                        const Text(
                          ' Flutter and Kotlin',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '© 2026 NearMitra Ecosystem • 100% Local P2P Security',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark ? Colors.white38 : Colors.black38,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withValues(alpha: 0.22),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.8,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
