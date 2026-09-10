import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text(
          'About NearMitra',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Logo & App Name Branding
              Center(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.35),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset(
                      'assets/images/nearmitra.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF10B981),
                        child: const Icon(
                          Icons.wifi_tethering_rounded,
                          size: 50,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Near',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        letterSpacing: -0.6,
                      ),
                    ),
                    const TextSpan(
                      text: 'Mitra',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF10B981),
                        letterSpacing: -0.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Offline P2P Mesh • Global Internet (WAN) P2P • HD Calling • CCTV Streaming • Dual-Tier AI',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF10B981),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white12 : const Color(0xFFCBD5E1),
                  ),
                ),
                child: const Text(
                  'v2.1.0 • P2P WebRTC DataChannel • Global WAN • Riverpod Reactive',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 24),

              // Section 1: What is NearMitra?
              _buildInfoCard(
                context,
                icon: Icons.connect_without_contact_rounded,
                iconColor: const Color(0xFF10B981),
                title: 'What is NearMitra?',
                description:
                    'NearMitra is an enterprise-grade peer-to-peer communication, live media streaming, global internet sync, and AI ecosystem built for everyone — individuals, teams, families, field professionals, and off-grid communities. It operates 100% peer-to-peer over local Wi-Fi, Wi-Fi Direct, and global Internet (WAN) without storing private data on third-party cloud servers.',
              ),

              const SizedBox(height: 14),

              // Section 2: Global Internet (WAN) P2P Mode
              _buildInfoCard(
                context,
                icon: Icons.public_rounded,
                iconColor: const Color(0xFF10B981),
                title: 'Global Internet (WAN) P2P Connection',
                description:
                    '• Worldwide Direct Connection: Chat and transfer files directly with paired devices across any network, city, or country over the Internet.\n'
                    '• Zero Cloud Storage: All messages and files travel directly device-to-device via encrypted WebRTC DataChannels — zero private data is ever stored on Firebase or cloud databases.\n'
                    '• 6-Digit Pair Code & QR: 1-tap secure pairing with mutual authentication and trusted device management.\n'
                    '• Interactive Radar Scan: Visual live presence radar showing online status and real-time WebRTC connection indicators.\n'
                    '• Offline Outbox Auto-Sync: Queue messages and files offline; they automatically deliver the moment your peer comes online.',
              ),

              const SizedBox(height: 14),

              // Section 3: Core Feature Highlights
              _buildInfoCard(
                context,
                icon: Icons.videocam_rounded,
                iconColor: const Color(0xFF3B82F6),
                title: 'Remote CCTV & Live Audio Streaming Hub',
                description:
                    '• Remote CCTV Camera: Transform any nearby phone into an off-grid security camera with real-time 1080P HD 30fps video.\n'
                    '• Remote Hardware Control: Remotely toggle torch/flashlight, flip camera lenses, and mute host microphones.\n'
                    '• Live Audio Relay & Walkie-Talkie: Real-time room acoustic monitoring (Baby Monitor mode) and 1-tap voice broadcast to remote phone speakers.\n'
                    '• 1-Tap Reset Action: Instant stream session reset and clean state recovery.',
              ),

              const SizedBox(height: 14),

              // Section 4: WebRTC HD Calling & Screen Sharing
              _buildInfoCard(
                context,
                icon: Icons.phone_in_talk_rounded,
                iconColor: const Color(0xFF06B6D4),
                title: 'WebRTC HD Calling & Live Screen Casting',
                description:
                    '• Zero-Latency Voice & Video: Full-duplex HD audio and 720p video calls over local sockets.\n'
                    '• Real-Time Screen Sharing: Cast mobile screens live to the caller device with seamless audio-video switching.\n'
                    '• Android 14+ CallKit Engine: Native full-screen heads-up incoming call alerts with speakerphone and background service.',
              ),

              const SizedBox(height: 14),

              // Section 5: Dual-Tier AI System
              _buildInfoCard(
                context,
                icon: Icons.auto_awesome_rounded,
                iconColor: const Color(0xFFF59E0B),
                title: 'Dual-Tier AI Assistant (My AI vs Nearby AI)',
                description:
                    '• Floating "My AI": Personal private AI assistant powered directly by local Gemini 2.0 Flash / OpenAI keys.\n'
                    '• Peer "Nearby AI": Query connected peer/host AI engines over LAN without personal API keys.\n'
                    '• Host Access Control: Host devices can grant or revoke AI permissions per device directly via the chat header 3-dots menu.',
              ),

              const SizedBox(height: 14),

              // Section 6: Mesh Relay & High-Speed File Transfer
              _buildInfoCard(
                context,
                icon: Icons.hub_rounded,
                iconColor: const Color(0xFF8B5CF6),
                title: 'Multi-Hop Mesh Network & Blazing File Transfers',
                description:
                    '• Auto Multi-Hop Mesh Relay: Messages automatically hop through intermediary phones to reach distant devices beyond direct range.\n'
                    '• High-Speed Sockets: Share multiple gigabytes of photos, videos, documents, and APKs at maximum local Wi-Fi speeds with chunked verification and zero compression.',
              ),
              const SizedBox(height: 28),

              // Professional Footer Branding
              Divider(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
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
                '© 2026 NearMitra Ecosystem • All Rights Reserved',
                style: TextStyle(
                  fontSize: 10.5,
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2C34) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: TextStyle(
              fontSize: 12.8,
              height: 1.48,
              color:
                  isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}
