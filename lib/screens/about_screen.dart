import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About Farmitra Nearby', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
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
                        color: const Color(0xFF10B981).withValues(alpha: 0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF10B981),
                        child: const Icon(Icons.wifi_tethering_rounded, size: 50, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Farmitra Nearby',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4),
              ),
              const SizedBox(height: 4),
              const Text(
                'Fast. Private. Offline P2P & LAN Communication',
                style: TextStyle(fontSize: 13, color: Color(0xFF10B981), fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'v1.0.0 (v7.1 Direct P2P & Nearby AI)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 24),

              // Section 1: What is Farmitra Nearby?
              _buildInfoCard(
                context,
                icon: Icons.grass_rounded,
                iconColor: const Color(0xFF10B981),
                title: 'What is Farmitra Nearby?',
                description:
                    'Farmitra Nearby is a high-speed, local communication and file-sharing app built specifically for farmers, rural communities, and field teams. It allows instant text chat, high-speed file transfers, and remote AI processing without needing cellular data, internet, or a central router.',
              ),

              const SizedBox(height: 14),

              // Section 2: How does it work?
              _buildInfoCard(
                context,
                icon: Icons.alt_route_rounded,
                iconColor: const Color(0xFF3B82F6),
                title: 'How does it work?',
                description:
                    '• Direct P2P Mode: Connects devices directly using Wi-Fi Direct (v7.1 Radar flow) without any Wi-Fi router.\n'
                    '• Nearby LAN Mode: Auto-discovers devices on the same local Wi-Fi router via UDP discovery (Port 43888).\n'
                    '• Nearby AI: Sends AI prompts to a nearby Windows PC host over TCP (Port 43889) to run local Ollama AI models securely without cloud API keys.',
              ),

              const SizedBox(height: 14),

              // Section 3: Who can use it?
              _buildInfoCard(
                context,
                icon: Icons.groups_rounded,
                iconColor: const Color(0xFF8B5CF6),
                title: 'Who can use it?',
                description:
                    'Designed for farmers, agricultural advisors, field survey teams, students, and remote workers who need fast, reliable, and private local communication in areas with low or no internet connectivity.',
              ),

              const SizedBox(height: 28),

              // Professional Footer Branding
              Divider(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.security_rounded, size: 14, color: Color(0xFF10B981)),
                  const SizedBox(width: 6),
                  Text(
                    'Local Peer-to-Peer Encrypted Socket Transport',
                    style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.black54),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '© 2026 Farmitra Ecosystem • All Rights Reserved',
                style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38, fontWeight: FontWeight.w500),
              ),
            ],
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 6,
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
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}
