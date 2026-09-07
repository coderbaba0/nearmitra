import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WalkthroughStepItem {
  const WalkthroughStepItem({
    required this.key,
    required this.title,
    required this.description,
    required this.howToUse,
    required this.icon,
    this.onEnter,
  });

  final GlobalKey key;
  final String title;
  final String description;
  final String howToUse;
  final IconData icon;
  final VoidCallback? onEnter;
}

class HomeWalkthroughGuide extends StatefulWidget {
  const HomeWalkthroughGuide({
    super.key,
    required this.steps,
    required this.onFinish,
    required this.onSkip,
  });

  final List<WalkthroughStepItem> steps;
  final VoidCallback onFinish;
  final VoidCallback onSkip;

  static const String prefKey = 'homeWalkthroughCompleted';

  /// Check if the walkthrough has been completed before
  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefKey) ?? false;
  }

  /// Mark the walkthrough as completed
  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, true);
  }

  /// Reset completion state (for manual replay)
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, false);
  }

  @override
  State<HomeWalkthroughGuide> createState() => _HomeWalkthroughGuideState();
}

class _HomeWalkthroughGuideState extends State<HomeWalkthroughGuide>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  Rect? _targetRect;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showStep(_currentIndex, isInitial: true);
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _showStep(int index, {bool isInitial = false}) {
    if (index < 0 || index >= widget.steps.length) return;

    final step = widget.steps[index];
    step.onEnter?.call();

    // Small delay to allow layout to settle if step triggered a state change
    Future.delayed(Duration(milliseconds: isInitial ? 100 : 180), () {
      if (!mounted) return;
      _updateTargetRect(step.key);
      _animController.forward(from: 0.0);
    });
  }

  void _updateTargetRect(GlobalKey key) {
    final context = key.currentContext;
    if (context != null) {
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final position = renderBox.localToGlobal(Offset.zero);
        final size = renderBox.size;
        setState(() {
          // Add 4px padding around target
          _targetRect = Rect.fromLTWH(
            position.dx - 4,
            position.dy - 4,
            size.width + 8,
            size.height + 8,
          );
        });
        return;
      }
    }
    // Fallback if target render box not found
    setState(() {
      _targetRect = null;
    });
  }

  void _nextStep() {
    if (_currentIndex < widget.steps.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _showStep(_currentIndex);
    } else {
      _finish();
    }
  }

  void _prevStep() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _showStep(_currentIndex);
    }
  }

  Future<void> _skip() async {
    await HomeWalkthroughGuide.markCompleted();
    widget.onSkip();
  }

  Future<void> _finish() async {
    await HomeWalkthroughGuide.markCompleted();
    widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final step = widget.steps[_currentIndex];
    final isLast = _currentIndex == widget.steps.length - 1;
    final isFirst = _currentIndex == 0;

    return Stack(
      children: [
        // 1. Fullscreen Dimmed Backdrop with Spotlight Cutout
        CustomPaint(
          size: screenSize,
          painter: _SpotlightPainter(
            targetRect: _targetRect,
            overlayColor: Colors.black.withValues(alpha: isDark ? 0.78 : 0.68),
          ),
        ),

        // 2. Animated Tooltip Card
        AnimatedBuilder(
          animation: _animController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: child,
              ),
            );
          },
          child: _buildTooltipCard(
            context,
            step: step,
            isFirst: isFirst,
            isLast: isLast,
            screenSize: screenSize,
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  Widget _buildTooltipCard(
    BuildContext context, {
    required WalkthroughStepItem step,
    required bool isFirst,
    required bool isLast,
    required Size screenSize,
    required bool isDark,
  }) {
    // Calculate card position (place below target if space permits, else above)
    double topPosition = 120.0;
    if (_targetRect != null) {
      final targetBottom = _targetRect!.bottom;
      final targetTop = _targetRect!.top;

      if (targetBottom + 300 < screenSize.height - 40) {
        // Enough room below target
        topPosition = targetBottom + 14;
      } else if (targetTop - 300 > 60) {
        // Place above target
        topPosition = math.max(60, targetTop - 290);
      } else {
        // Default center-safe placement
        topPosition = math.max(80, (screenSize.height - 280) / 2);
      }
    }

    final double cardWidth = math.min(screenSize.width - 32, 420.0);

    return Positioned(
      top: topPosition,
      left: (screenSize.width - cardWidth) / 2,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: cardWidth,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
                blurRadius: 24,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Badge + Step Title + Skip button
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(step.icon, size: 14, color: const Color(0xFF10B981)),
                        const SizedBox(width: 5),
                        Text(
                          'STEP ${_currentIndex + 1} OF ${widget.steps.length}',
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Skip button
                  TextButton(
                    onPressed: _skip,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: isDark ? Colors.white60 : Colors.black54,
                    ),
                    child: const Text(
                      'Skip',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Step Title
              Text(
                step.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),

              // Description
              Text(
                step.description,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 10),

              // How to Use Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A).withValues(alpha: 0.7)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 15,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        step.howToUse,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Bottom Actions: Dots Indicator & Navigation Buttons
              Row(
                children: [
                  // Step Indicator Dots
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(widget.steps.length, (i) {
                      final active = i == _currentIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 5),
                        width: active ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFF10B981)
                              : (isDark ? Colors.white24 : Colors.black26),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                  const Spacer(),

                  // Back Button (if not first)
                  if (!isFirst) ...[
                    OutlinedButton(
                      onPressed: _prevStep,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        'Back',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Next / Done Button
                  FilledButton(
                    onPressed: _nextStep,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isLast ? 'Done' : 'Next',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({
    required this.targetRect,
    required this.overlayColor,
  });

  final Rect? targetRect;
  final Color overlayColor;

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()..color = overlayColor;

    if (targetRect == null) {
      canvas.drawRect(fullRect, paint);
      return;
    }

    final path = Path()
      ..addRect(fullRect)
      ..addRRect(
        RRect.fromRectAndRadius(
          targetRect!,
          const Radius.circular(14),
        ),
      )
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // Draw glowing border around target cutout
    final borderPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        targetRect!,
        const Radius.circular(14),
      ),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.overlayColor != overlayColor;
  }
}
