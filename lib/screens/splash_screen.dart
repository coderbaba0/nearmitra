import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

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
  late AnimationController _orbitController;
  late AnimationController _progressController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  String _loadingStatusText = 'Initializing Direct P2P Radar & Sockets…';

  @override
  void initState() {
    super.initState();

    // 1. Concentric Pulse Waves (Continuous)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    // 2. Orbiting P2P Share Nodes (Continuous 360 Rotation)
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat();

    // 3. Progress Bar Fill Animation (0.0 to 1.0)
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _scaleAnimation = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: const Interval(0.0, 0.4, curve: Curves.easeIn)),
    );

    _progressController.forward();

    // Dynamic loading status text update steps
    Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() => _loadingStatusText = 'Setting up UDP 43888 & TCP 43889 Transports…');
      }
    });

    Timer(const Duration(milliseconds: 1700), () {
      if (mounted) {
        setState(() => _loadingStatusText = 'Ready for Offline Chat & High-Speed Sharing!');
      }
    });

    // Navigate to HomeScreen after splash completes
    Timer(const Duration(milliseconds: 2600), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => HomeScreen(service: widget.service),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 450),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _orbitController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF070E12) : const Color(0xFF0B141A),
      body: Stack(
        children: [
          // Background Emerald Radial Aura
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.0, -0.2),
                  radius: 0.85,
                  colors: [
                    Color(0x2610B981),
                    Color(0x00070E12),
                  ],
                ),
              ),
            ),
          ),

          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(),

                      // Central Animated Logo with Nearby P2P Pulse Waves & Orbiting Nodes
                      SizedBox(
                        width: 220,
                        height: 220,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // 1. Concentric Expanding Radar Waves
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                return CustomPaint(
                                  size: const Size(220, 220),
                                  painter: _NearbyPulsePainter(progress: _pulseController.value),
                                );
                              },
                            ),

                            // 2. Orbiting P2P Share Nodes around Logo
                            AnimatedBuilder(
                              animation: _orbitController,
                              builder: (context, child) {
                                return CustomPaint(
                                  size: const Size(220, 220),
                                  painter: _P2pOrbitNodesPainter(progress: _orbitController.value),
                                );
                              },
                            ),

                            // 3. Main App Logo Container
                            Container(
                              width: 105,
                              height: 105,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF0F1E25),
                                border: Border.all(color: const Color(0xFF10B981), width: 2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.45),
                                    blurRadius: 24,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(16),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(50),
                                child: Image.asset(
                                  'assets/images/app_logo.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.wifi_tethering_rounded,
                                    size: 50,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Title & Subtitle Branding
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Farmitra ',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: -0.4,
                            ),
                          ),
                          Text(
                            'Nearby',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF10B981),
                              letterSpacing: -0.4,
                              shadows: [
                                Shadow(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.6),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                        ),
                        child: const Text(
                          '⚡ FAST • PRIVATE • OFFLINE P2P & LAN',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF10B981),
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),

                      const Spacer(),

                      // Unique Custom Progress Bar / Loader
                      AnimatedBuilder(
                        animation: _progressController,
                        builder: (context, child) {
                          return Column(
                            children: [
                              CustomPaint(
                                size: const Size(240, 6),
                                painter: _UniqueGlowLoaderPainter(progress: _progressController.value),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _loadingStatusText,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white70,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 36),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Painter 1: Concentric Expanding Radar Waves
class _NearbyPulsePainter extends CustomPainter {
  _NearbyPulsePainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final waveProgress = (progress + (i * 0.333)) % 1.0;
      final radius = 55.0 + (waveProgress * (maxRadius - 55.0));
      final opacity = (1.0 - waveProgress).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: opacity * 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NearbyPulsePainter oldDelegate) => oldDelegate.progress != progress;
}

// Painter 2: Orbiting P2P Wireless Share Nodes
class _P2pOrbitNodesPainter extends CustomPainter {
  _P2pOrbitNodesPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final orbitRadius = size.width * 0.40;
    final angleStep = (2 * math.pi) / 3;
    final baseAngle = progress * 2 * math.pi;

    final nodePaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Draw orbital ring path
    canvas.drawCircle(center, orbitRadius, linePaint);

    for (int i = 0; i < 3; i++) {
      final angle = baseAngle + (i * angleStep);
      final nodeX = center.dx + (math.cos(angle) * orbitRadius);
      final nodeY = center.dy + (math.sin(angle) * orbitRadius);
      final nodePos = Offset(nodeX, nodeY);

      // Connecting beam from center to orbiting node
      canvas.drawLine(center, nodePos, linePaint);

      // Glowing Node dot
      canvas.drawCircle(nodePos, 6, nodePaint);
      canvas.drawCircle(
        nodePos,
        10,
        Paint()
          ..color = const Color(0xFF10B981).withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _P2pOrbitNodesPainter oldDelegate) => oldDelegate.progress != progress;
}

// Painter 3: Unique Futuristic Glow Loader Bar
class _UniqueGlowLoaderPainter extends CustomPainter {
  _UniqueGlowLoaderPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(4),
    );

    // Track Background
    final bgPaint = Paint()..color = Colors.white.withValues(alpha: 0.12);
    canvas.drawRRect(rect, bgPaint);

    if (progress <= 0) return;

    final filledWidth = size.width * progress.clamp(0.0, 1.0);
    final fillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, filledWidth, size.height),
      const Radius.circular(4),
    );

    // Fill Gradient
    final fillGradient = LinearGradient(
      colors: const [
        Color(0xFF059669),
        Color(0xFF10B981),
        Color(0xFF34D399),
      ],
    );

    final fillPaint = Paint()
      ..shader = fillGradient.createShader(Rect.fromLTWH(0, 0, filledWidth, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawRRect(fillRect, fillPaint);

    // Leading Glowing Particle Spark
    final sparkX = filledWidth;
    final sparkPaint = Paint()
      ..color = Colors.white
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    canvas.drawCircle(Offset(sparkX, size.height / 2), 4.5, sparkPaint);
  }

  @override
  bool shouldRepaint(covariant _UniqueGlowLoaderPainter oldDelegate) => oldDelegate.progress != progress;
}
