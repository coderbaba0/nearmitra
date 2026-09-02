import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../services/call_service.dart';
import '../services/nearby_service.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.service});

  final NearbyService service;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  bool _navigated = false;
  Timer? _navTimer;

  void _navigateToHome() {
    if (_navigated || !mounted) return;
    _navigated = true;
    _navTimer?.cancel();
    _pulseController.stop();
    _rotationController.stop();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => HomeScreen(service: widget.service),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    // If a call was already accepted from background / killed mode, immediately jump to HomeScreen
    CallService().registerCallAcceptedCallback((peer, isVideo, isIncoming) {
      _navigateToHome();
    });

    if (CallService().hasPendingAcceptedCall) {
      _navigateToHome();
      return;
    }

    // 1. Concentric Signal Waves Animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // 2. Node Rotation
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..repeat();

    // Navigate to HomeScreen after clean splash animation
    _navTimer = Timer(const Duration(milliseconds: 2400), () {
      _navigateToHome();
    });
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070E12),
      body: Stack(
        children: [
          // Background Ambient Radial Glow
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.0, 0.0),
                  radius: 1.0,
                  colors: [
                    Color(0x3510B981),
                    Color(0x12059669),
                    Color(0xFF070E12),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),

          // Pure Centered Smooth P2P Connection Animation
          Center(
            child: SizedBox(
              width: 260,
              height: 260,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Vector Animation Painter
                  AnimatedBuilder(
                    animation: Listenable.merge([_pulseController, _rotationController]),
                    builder: (context, child) {
                      return CustomPaint(
                        size: const Size(260, 260),
                        painter: _SmoothConnectionPainter(
                          pulseProgress: _pulseController.value,
                          rotationProgress: _rotationController.value,
                        ),
                      );
                    },
                  ),

                  // Center Hub Icon Badge
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0D1D24),
                      border: Border.all(
                        color: const Color(0xFF10B981),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.55),
                          blurRadius: 32,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.wifi_tethering_rounded,
                      size: 52,
                      color: Color(0xFF10B981),
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
}

// Pure Creative Smooth Connection Network Painter
class _SmoothConnectionPainter extends CustomPainter {
  _SmoothConnectionPainter({
    required this.pulseProgress,
    required this.rotationProgress,
  });

  final double pulseProgress;
  final double rotationProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Concentric Pulsing Signal Rings
    for (int i = 0; i < 3; i++) {
      final waveProgress = (pulseProgress + (i * 0.333)) % 1.0;
      final waveRadius = 50.0 + (waveProgress * (radius * 0.95 - 50.0));
      final opacity = (1.0 - waveProgress).clamp(0.0, 1.0);

      final wavePaint = Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: opacity * 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;

      canvas.drawCircle(center, waveRadius, wavePaint);
    }

    // 2. Subtle Geometry Orbit Lines
    final orbitPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius * 0.72, orbitPaint);

    // 3. Rotating Smooth Connection Nodes (Devices)
    const nodeCount = 4;
    final orbitAngle = rotationProgress * 2 * math.pi;
    final nodes = <Offset>[];

    for (int i = 0; i < nodeCount; i++) {
      final a = orbitAngle + (i * (2 * math.pi / nodeCount));
      final r = radius * 0.72;
      final nx = center.dx + (math.cos(a) * r);
      final ny = center.dy + (math.sin(a) * r);
      nodes.add(Offset(nx, ny));
    }

    // Connect Nodes to Center Hub & Between Adjacent Nodes
    final beamPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    for (int i = 0; i < nodes.length; i++) {
      final n1 = nodes[i];
      final n2 = nodes[(i + 1) % nodes.length];
      canvas.drawLine(center, n1, beamPaint);
      canvas.drawLine(n1, n2, Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0);

      // Node Outer Glow Halo
      canvas.drawCircle(
        n1,
        8.0,
        Paint()
          ..color = const Color(0xFF10B981).withValues(alpha: 0.28)
          ..style = PaintingStyle.fill,
      );

      // Node Solid Core
      canvas.drawCircle(
        n1,
        4.0,
        Paint()..color = const Color(0xFF34D399),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SmoothConnectionPainter oldDelegate) => true;
}
