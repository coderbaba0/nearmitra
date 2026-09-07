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
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  Rect? _targetRect;
  Rect? _prevRect;

  late AnimationController _morphController;
  late Animation<double> _morphAnimation;

  late AnimationController _cardController;
  late Animation<double> _cardFadeAnimation;
  late Animation<Offset> _cardSlideAnimation;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Morph animation for spotlight gliding smoothly between targets
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _morphAnimation = CurvedAnimation(
      parent: _morphController,
      curve: Curves.easeInOutCubic,
    );

    // Card entry/transition animation
    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _cardFadeAnimation = CurvedAnimation(
      parent: _cardController,
      curve: Curves.easeOut,
    );
    _cardSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _cardController,
      curve: Curves.easeOutBack,
    ));

    // Continuous subtle glowing pulse around active spotlight
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.5, end: 4.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showStep(_currentIndex, isInitial: true);
    });
  }

  @override
  void dispose() {
    _morphController.dispose();
    _cardController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _showStep(int index, {bool isInitial = false}) {
    if (index < 0 || index >= widget.steps.length) return;

    final step = widget.steps[index];
    step.onEnter?.call();

    _scheduleTargetUpdate(step.key, isInitial: isInitial);
  }

  void _scheduleTargetUpdate(GlobalKey key, {bool isInitial = false, int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(Duration(milliseconds: isInitial ? 150 : 80), () {
        if (!mounted) return;
        final newRect = _calculateTargetRect(key);

        if (newRect == null && attempt < 3) {
          _scheduleTargetUpdate(key, isInitial: false, attempt: attempt + 1);
          return;
        }

        setState(() {
          _prevRect = _targetRect ?? newRect;
          _targetRect = newRect;
        });

        _morphController.forward(from: 0.0);
        _cardController.forward(from: 0.0);
      });
    });
  }

  Rect? _calculateTargetRect(GlobalKey key) {
    final targetContext = key.currentContext;
    if (targetContext != null && targetContext.mounted) {
      final targetBox = targetContext.findRenderObject() as RenderBox?;
      if (targetBox != null && targetBox.hasSize && targetBox.attached) {
        final position = targetBox.localToGlobal(Offset.zero);
        final size = targetBox.size;
        return Rect.fromLTWH(
          position.dx - 4,
          position.dy - 3,
          size.width + 8,
          size.height + 6,
        );
      }
    }
    return null;
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
    final screenSize = MediaQuery.sizeOf(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final step = widget.steps[_currentIndex];
    final isLast = _currentIndex == widget.steps.length - 1;
    final isFirst = _currentIndex == 0;

    // Compute Card Geometry
    final double cardWidth = math.min(screenSize.width - 32, 400.0);
    double topPosition = 140.0;
    bool isBelowTarget = true;
    double arrowLeft = cardWidth / 2;

    if (_targetRect != null) {
      final targetBottom = _targetRect!.bottom;
      final targetTop = _targetRect!.top;
      final targetCenterX = _targetRect!.center.dx;

      if (targetBottom + 320 < screenSize.height - 30) {
        topPosition = targetBottom + 12;
        isBelowTarget = true;
      } else if (targetTop - 320 > 50) {
        topPosition = targetTop - 310;
        isBelowTarget = false;
      } else {
        topPosition = math.max(80, (screenSize.height - 300) / 2);
      }

      final cardLeft = (screenSize.width - cardWidth) / 2;
      arrowLeft = (targetCenterX - cardLeft).clamp(24.0, cardWidth - 24.0);
    }

    return Stack(
      children: [
        // 1. Fullscreen Dimmed Backdrop with Animated Morphing Spotlight Cutout
        Positioned.fill(
          child: AnimatedBuilder(
            animation: Listenable.merge([_morphAnimation, _pulseAnimation]),
            builder: (context, _) {
              Rect? animatedRect;
              if (_prevRect != null && _targetRect != null) {
                animatedRect = Rect.lerp(_prevRect, _targetRect, _morphAnimation.value);
              } else {
                animatedRect = _targetRect;
              }

              return CustomPaint(
                size: screenSize,
                painter: _SpotlightPainter(
                  targetRect: animatedRect,
                  overlayColor: Colors.black.withValues(alpha: isDark ? 0.78 : 0.70),
                  pulseSpread: _pulseAnimation.value,
                ),
              );
            },
          ),
        ),

        // 2. Global Top-Right "Skip Tour" Floating Button (Direct child of Stack)
        Positioned(
          top: MediaQuery.paddingOf(context).top + 10,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _skip,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'Skip Tour',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.close_rounded, size: 14, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 3. Animated Spotlight Tooltip Card (Direct child of Stack)
        Positioned(
          top: topPosition,
          left: (screenSize.width - cardWidth) / 2,
          child: AnimatedBuilder(
            animation: _cardController,
            builder: (context, child) {
              return FadeTransition(
                opacity: _cardFadeAnimation,
                child: SlideTransition(
                  position: _cardSlideAnimation,
                  child: child,
                ),
              );
            },
            child: _buildTooltipCardContent(
              context,
              step: step,
              isFirst: isFirst,
              isLast: isLast,
              cardWidth: cardWidth,
              arrowLeft: arrowLeft,
              isBelowTarget: isBelowTarget,
              isDark: isDark,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTooltipCardContent(
    BuildContext context, {
    required WalkthroughStepItem step,
    required bool isFirst,
    required bool isLast,
    required double cardWidth,
    required double arrowLeft,
    required bool isBelowTarget,
    required bool isDark,
  }) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Tooltip Card Body
          Container(
            width: cardWidth,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.45),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.22),
                  blurRadius: 28,
                  spreadRadius: 2,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Step Badge + Step Counter + Header Skip
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF005C4B), Color(0xFF10B981)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: 0.35),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(step.icon, size: 14, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            'STEP ${_currentIndex + 1} OF ${widget.steps.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Skip Action
                    InkWell(
                      onTap: _skip,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Step Title
                Text(
                  step.title,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),

                // Description
                Text(
                  step.description,
                  style: TextStyle(
                    fontSize: 13.2,
                    height: 1.42,
                    color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 12),

                // How to Use Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0F172A).withValues(alpha: 0.75)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.white12 : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.lightbulb_rounded,
                          size: 16,
                          color: Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          step.howToUse,
                          style: TextStyle(
                            fontSize: 11.8,
                            height: 1.38,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Bottom Bar: Progress Dots & Action Buttons
                Row(
                  children: [
                    // Animated Progress Dots
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(widget.steps.length, (i) {
                        final active = i == _currentIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.only(right: 6),
                          width: active ? 22 : 6,
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

                    // Back Button
                    if (!isFirst) ...[
                      OutlinedButton(
                        onPressed: _prevStep,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: BorderSide(
                            color: isDark ? Colors.white24 : Colors.black26,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Back',
                          style: TextStyle(
                            fontSize: 12.5,
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
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isLast ? 'Done' : 'Next',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            isLast ? Icons.check_circle_rounded : Icons.arrow_forward_rounded,
                            size: 15,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Triangle Pointer Arrow pointing directly to highlighted button
          if (_targetRect != null)
            Positioned(
              top: isBelowTarget ? -8 : null,
              bottom: isBelowTarget ? null : -8,
              left: arrowLeft - 8,
              child: CustomPaint(
                size: const Size(16, 8),
                painter: _ArrowPainter(
                  isBelow: isBelowTarget,
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderColor: const Color(0xFF10B981),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({
    required this.isBelow,
    required this.color,
    required this.borderColor,
  });

  final bool isBelow;
  final Color color;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (isBelow) {
      // Pointing UP
      path.moveTo(0, size.height);
      path.lineTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
    } else {
      // Pointing DOWN
      path.moveTo(0, 0);
      path.lineTo(size.width / 2, size.height);
      path.lineTo(size.width, 0);
    }
    path.close();

    final fillPaint = Paint()..color = color;
    canvas.drawPath(path, fillPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) =>
      oldDelegate.isBelow != isBelow ||
      oldDelegate.color != color ||
      oldDelegate.borderColor != borderColor;
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({
    required this.targetRect,
    required this.overlayColor,
    required this.pulseSpread,
  });

  final Rect? targetRect;
  final Color overlayColor;
  final double pulseSpread;

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()..color = overlayColor;

    if (targetRect == null) {
      canvas.drawRect(fullRect, paint);
      return;
    }

    final rrect = RRect.fromRectAndRadius(
      targetRect!,
      const Radius.circular(14),
    );

    final path = Path()
      ..addRect(fullRect)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // Glowing animated border around target cutout
    final glowPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = pulseSpread;

    canvas.drawRRect(rrect, glowPaint);

    // Crisp inner emerald border
    final borderPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.overlayColor != overlayColor ||
        oldDelegate.pulseSpread != pulseSpread;
  }
}
