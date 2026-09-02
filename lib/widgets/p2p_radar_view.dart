import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/p2p_peer.dart';
import '../services/wifi_direct_service.dart';

class P2pRadarView extends StatefulWidget {
  const P2pRadarView({
    super.key,
    required this.p2pService,
    required this.onPeerConnectedTap,
    required this.onManualPairingTap,
  });

  final WifiDirectService p2pService;
  final ValueChanged<String> onPeerConnectedTap;
  final VoidCallback onManualPairingTap;

  @override
  State<P2pRadarView> createState() => _P2pRadarViewState();
}

class _P2pRadarViewState extends State<P2pRadarView> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _sweepController;
  Timer? _realtimeStatusTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();

    widget.p2pService.addListener(_onP2pChanged);
    widget.p2pService.ensureP2pPermissionsAndWifi();
    widget.p2pService.startAutoDiscovery();

    // Instant real-time status check every 1 second
    _realtimeStatusTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (mounted) {
        widget.p2pService.checkNativeWifiEnabled();
        widget.p2pService.checkNativeLocationEnabled();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      widget.p2pService.checkNativeWifiEnabled();
      widget.p2pService.checkNativeLocationEnabled();
    }
  }

  void _onP2pChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeStatusTimer?.cancel();
    widget.p2pService.removeListener(_onP2pChanged);
    widget.p2pService.stopAutoDiscovery();
    _sweepController.dispose();
    super.dispose();
  }

  Offset _getNodeOffset(int index, int total, double radius) {
    if (total == 0) return Offset.zero;
    final angle = (index * (2 * math.pi / math.max(total, 4))) - (math.pi / 2);
    final distance = radius * 0.68;
    return Offset(
      math.cos(angle) * distance,
      math.sin(angle) * distance,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final wifiDirectPeers = widget.p2pService.peers;
    final totalPeerCount = wifiDirectPeers.length;
    final isScanning = widget.p2pService.isScanning;
    final isConnected = widget.p2pService.isConnected;

    final isWifiOn = widget.p2pService.isP2pEnabled;
    final isLocationOn = widget.p2pService.isLocationEnabled;
    final hasWarning = !isWifiOn || !isLocationOn;

    return Column(
      children: [
        // UNIFIED SINGLE TOP HEADER CARD
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          decoration: BoxDecoration(
            color: hasWarning
                ? Colors.amber.withValues(alpha: 0.12)
                : (isConnected
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9))),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasWarning
                  ? Colors.amber.withValues(alpha: 0.45)
                  : (isConnected
                      ? const Color(0xFF10B981).withValues(alpha: 0.4)
                      : (isDark ? Colors.white12 : Colors.black12)),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    hasWarning
                        ? Icons.warning_amber_rounded
                        : (isConnected ? Icons.wifi_tethering_rounded : Icons.radar_rounded),
                    color: hasWarning
                        ? Colors.amber
                        : (isConnected ? const Color(0xFF10B981) : (isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5))),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          !isWifiOn
                              ? 'Wi-Fi Turned OFF'
                              : (!isLocationOn
                                  ? 'Location (GPS) Turned OFF'
                                  : (isConnected
                                      ? 'Direct P2P Connected'
                                      : (isScanning ? 'Radar Scanning for Devices…' : 'Wi‑Fi Direct Radar Ready'))),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: hasWarning
                                ? Colors.amber[800]
                                : (isConnected ? const Color(0xFF10B981) : (isDark ? Colors.white : Colors.black87)),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          !isWifiOn
                              ? 'Turn ON Wi-Fi to scan & connect P2P peers'
                              : (!isLocationOn
                                  ? 'Android OS requires GPS to scan P2P peers'
                                  : (isConnected
                                      ? (widget.p2pService.isGroupOwner ? 'Host (Group Owner) • High Speed Link' : 'Connected to Host • High Speed Link')
                                      : (totalPeerCount == 0
                                          ? 'Searching nearby P2P devices…'
                                          : '$totalPeerCount device(s) found'))),
                          style: TextStyle(
                            fontSize: 11,
                            color: hasWarning ? Colors.amber[900]?.withValues(alpha: 0.8) : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!hasWarning) ...[
                    if (isConnected)
                      TextButton(
                        onPressed: () => widget.p2pService.disconnectP2p(),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        ),
                        child: const Text('Disconnect', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      )
                    else if (isScanning)
                      RotationTransition(
                        turns: _sweepController,
                        child: IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 20, color: Color(0xFF10B981)),
                          onPressed: () {
                            widget.p2pService.discoverPeers();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Radar scanning for nearby P2P devices…'),
                                duration: Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          tooltip: 'Refresh Radar Scan',
                        ),
                      ),
                  ],
                ],
              ),
              if (hasWarning) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!isWifiOn)
                      FilledButton.icon(
                        onPressed: () => widget.p2pService.openWifiSettings(),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.wifi_rounded, size: 16),
                        label: const Text('Turn ON Wi-Fi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    if (!isWifiOn && !isLocationOn) const SizedBox(width: 8),
                    if (!isLocationOn)
                      FilledButton.icon(
                        onPressed: () => widget.p2pService.openLocationSettings(),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.amber[800],
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.location_on_rounded, size: 16),
                        label: const Text('Turn ON Location (GPS)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // Main 60 FPS Interactive Radar Circle
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = math.min(constraints.maxWidth, constraints.maxHeight) * 0.92;
              final centerOffset = Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
              final radarRadius = size / 2;

              return Stack(
                children: [
                  // 60 FPS Custom Painter Radar Sweeper & Rings
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _sweepController,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: _RadarSweepPainter(
                            progress: _sweepController.value,
                            isDark: isDark,
                            isScanning: isScanning,
                          ),
                        );
                      },
                    ),
                  ),

                  // Center Breathing Point (This Device)
                  Positioned(
                    left: centerOffset.dx - 26,
                    top: centerOffset.dy - 26,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark ? const Color(0xFF10B981) : const Color(0xFF059669),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF10B981).withValues(alpha: 0.4),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.phone_android_rounded, color: Colors.white, size: 22),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black87 : Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'This Device',
                                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                widget.p2pService.localP2pIp ?? 'IP: Ready',
                                style: const TextStyle(fontSize: 8.5, color: Color(0xFF10B981), fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Wi-Fi Direct Discovered Device Nodes placed around Radar
                  ...List.generate(wifiDirectPeers.length, (index) {
                    final p = wifiDirectPeers[index];
                    final totalNodes = totalPeerCount;
                    final nodeOffset = _getNodeOffset(index, totalNodes, radarRadius);
                    final posX = centerOffset.dx + nodeOffset.dx - 28;
                    final posY = centerOffset.dy + nodeOffset.dy - 28;

                    return Positioned(
                      left: posX,
                      top: posY,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutBack,
                        builder: (context, scale, child) {
                          return Transform.scale(scale: scale, child: child);
                        },
                        child: GestureDetector(
                          onTap: () {
                            if (p.isConnected) {
                              widget.onPeerConnectedTap(p.name);
                            } else {
                              widget.p2pService.connectP2p(p);
                            }
                          },
                          child: _buildWifiDirectNode(p, isDark),
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),

        // QR / Manual Pairing Fallback Button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: OutlinedButton.icon(
            onPressed: widget.onManualPairingTap,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
            label: const Text(
              "Can't find device? Scan QR / Manual Pairing",
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  IconData _getRadarDeviceIcon(String name, [String? id]) {
    final lowerName = name.toLowerCase();
    final lowerId = (id ?? '').toLowerCase();

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

    // 2. All other devices in NearMitra ecosystem -> Phone Icon
    return Icons.phone_android_rounded;
  }

  Widget _buildWifiDirectNode(P2pPeer p, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.isConnected
                ? const Color(0xFF10B981)
                : (p.isConnecting
                    ? const Color(0xFFF59E0B)
                    : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
            border: Border.all(
              color: p.isConnected
                  ? Colors.white
                  : (p.isConnecting
                      ? const Color(0xFFFBFB04)
                      : const Color(0xFF10B981).withValues(alpha: 0.6)),
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: (p.isConnected ? const Color(0xFF10B981) : Colors.black12).withValues(alpha: 0.3),
                blurRadius: 6,
                spreadRadius: 1.5,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                _getRadarDeviceIcon(p.name, p.deviceAddress),
                color: p.isConnected ? Colors.white : (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7)),
                size: 21,
              ),
              if (p.isConnecting)
                const SizedBox(
                  width: 40, height: 40,
                  child: CircularProgressIndicator(strokeWidth: 2.0, color: Color(0xFFF59E0B)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          child: Column(
            children: [
              Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              Text(
                p.statusLabel,
                style: TextStyle(
                  fontSize: 9.5,
                  color: p.isConnected
                      ? const Color(0xFF10B981)
                      : (p.isConnecting ? const Color(0xFFF59E0B) : Colors.grey),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RadarSweepPainter extends CustomPainter {
  _RadarSweepPainter({
    required this.progress,
    required this.isDark,
    required this.isScanning,
  });

  final double progress;
  final bool isDark;
  final bool isScanning;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) * 0.44;

    final linePaint = Paint()
      ..color = (isDark ? const Color(0xFF10B981) : const Color(0xFF059669)).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Concentric Guide Rings
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, maxRadius * (i / 3.0), linePaint);
    }

    // Crosshair Lines
    canvas.drawLine(Offset(center.dx - maxRadius, center.dy), Offset(center.dx + maxRadius, center.dy), linePaint);
    canvas.drawLine(Offset(center.dx, center.dy - maxRadius), Offset(center.dx, center.dy + maxRadius), linePaint);

    // Expanding Pulse Waves
    for (int i = 0; i < 3; i++) {
      final waveProgress = (progress + (i * 0.333)) % 1.0;
      final radius = waveProgress * maxRadius;
      final opacity = (1.0 - waveProgress).clamp(0.0, 1.0);

      final pulsePaint = Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: opacity * 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;

      canvas.drawCircle(center, radius, pulsePaint);
    }

    // 60 FPS Rotating Sweep Sector Arc
    final sweepAngle = progress * 2 * math.pi;
    final sweepRect = Rect.fromCircle(center: center, radius: maxRadius);

    final sweepGradient = SweepGradient(
      center: Alignment.center,
      startAngle: sweepAngle - 0.6,
      endAngle: sweepAngle,
      colors: [
        const Color(0xFF10B981).withValues(alpha: 0.0),
        const Color(0xFF10B981).withValues(alpha: 0.35),
      ],
      stops: const [0.0, 1.0],
    );

    final sweepPaint = Paint()
      ..shader = sweepGradient.createShader(sweepRect)
      ..style = PaintingStyle.fill;

    canvas.drawArc(sweepRect, sweepAngle - 0.6, 0.6, true, sweepPaint);

    // Leading Sweep Line
    final lineEndX = center.dx + math.cos(sweepAngle) * maxRadius;
    final lineEndY = center.dy + math.sin(sweepAngle) * maxRadius;

    final leadingLinePaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 2.2;

    canvas.drawLine(center, Offset(lineEndX, lineEndY), leadingLinePaint);
  }

  @override
  bool shouldRepaint(covariant _RadarSweepPainter oldDelegate) => true;
}
