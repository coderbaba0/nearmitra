import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Decorative flowing waves whose intensity follows measured audio energy.
/// Phase advances between audio samples; silence and hidden tabs stop the ticker.
class WirelessAudioMeter extends StatefulWidget {
  const WirelessAudioMeter({
    super.key,
    required this.level,
    required this.active,
    this.color,
    this.idleColor,
    this.height = 96,
  });

  final double level;
  final bool active;
  final Color? color, idleColor;
  final double height;

  @override
  State<WirelessAudioMeter> createState() => _WirelessAudioMeterState();
}

class _WirelessAudioMeterState extends State<WirelessAudioMeter>
    with TickerProviderStateMixin {
  late final AnimationController _flow, _energy;
  bool _reduceMotion = false, _visible = true;

  double get _level =>
      widget.active && widget.level.isFinite ? widget.level.clamp(0, 1) : 0;

  @override
  void initState() {
    super.initState();
    _flow =
        AnimationController(vsync: this, duration: const Duration(seconds: 12));
    _energy = AnimationController(vsync: this, value: _level)
      ..addListener(_settleSilence);
  }

  void _settleSilence() {
    if (_energy.value <= 0.001 && _level <= 0.001) _flow.stop();
  }

  void _syncMotion() {
    final moving =
        !_reduceMotion && _visible && (_level > 0.001 || _energy.value > 0.001);
    if (moving && !_flow.isAnimating) {
      _flow.repeat();
    } else if (!moving) {
      _flow.stop();
    }
  }

  void _retarget() {
    if (_reduceMotion || !_visible) {
      _energy.value = _level;
    } else if (_energy.value != _level) {
      _energy.animateTo(_level,
          duration: Duration(milliseconds: _level > _energy.value ? 85 : 220),
          curve: Curves.easeOutCubic);
    }
    _syncMotion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _visible = TickerMode.valuesOf(context).enabled;
    _retarget();
  }

  @override
  void didUpdateWidget(covariant WirelessAudioMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level || oldWidget.active != widget.active) {
      _retarget();
    }
  }

  @override
  void dispose() {
    _energy.removeListener(_settleSilence);
    _energy.dispose();
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: widget.active
          ? 'Live audio level ${(_level * 100).round()} percent'
          : 'Audio idle',
      child: RepaintBoundary(
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: AudioWavePainter(
              phase: _flow,
              energy: _energy,
              colors: [
                widget.color ?? const Color(0xFF69F5D3),
                const Color(0xFF51CFFF),
                const Color(0xFFA58AFF),
                const Color(0xFFFF72CE),
                const Color(0xFFFFC76B),
              ],
              idleColor: widget.idleColor ?? colors.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class AudioWavePainter extends CustomPainter {
  AudioWavePainter({
    required this.phase,
    required this.energy,
    required this.colors,
    required this.idleColor,
  }) : super(repaint: Listenable.merge([phase, energy]));

  final Animation<double> phase, energy;
  final List<Color> colors;
  final Color idleColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = size.height / 2;
    final amplitude = math.sqrt(energy.value.clamp(0, 1));
    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (amplitude <= 0.032) {
      paint
        ..color = idleColor
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(0, center), Offset(size.width, center), paint);
      return;
    }

    // Integer phase multipliers keep the 12-second loop seamless.
    final angle = phase.value * 2 * math.pi;
    const points = 96;
    for (var layer = 0; layer < colors.length; layer++) {
      final offset = layer * 1.1;
      final strength = 0.75 + 0.18 * math.sin(angle * 2 + offset);
      final path = Path()..moveTo(0, center);
      for (var step = 1; step <= points; step++) {
        final x = step / points;
        final envelope = math.pow(math.sin(math.pi * x).abs(), 0.85);
        final wave = math.sin(x * math.pi * 3 - angle * 9 + offset) +
            0.38 * math.sin(x * math.pi * 5 + angle * 13 + offset * 1.7) +
            0.18 * math.sin(x * math.pi * 7 - angle * 7 + offset * 0.6);
        final y = center +
            wave / 1.56 * envelope * size.height * 0.42 * amplitude * strength;
        path.lineTo(x * size.width, y);
      }

      // Colours drift into their neighbours, with no frame-by-frame randomness.
      final blend = (math.sin(angle + offset) + 1) / 2;
      final tint = Color.lerp(
          colors[layer], colors[(layer + 1) % colors.length], blend)!;
      paint
        ..shader = null
        ..color = tint.withValues(alpha: 0.10)
        ..strokeWidth = 6;
      canvas.drawPath(path, paint);
      paint
        ..color = Colors.white
        ..shader = LinearGradient(
          colors: [
            tint.withValues(alpha: 0.25),
            tint,
            colors[(layer + 2) % colors.length].withValues(alpha: 0.9),
            tint.withValues(alpha: 0.25),
          ],
          stops: const [0, 0.35, 0.7, 1],
        ).createShader(Offset.zero & size)
        ..strokeWidth = 1.7;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant AudioWavePainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.energy != energy ||
      oldDelegate.idleColor != idleColor ||
      !_sameColors(oldDelegate.colors);

  bool _sameColors(List<Color> other) {
    if (other.length != colors.length) return false;
    for (var index = 0; index < colors.length; index++) {
      if (other[index] != colors[index]) return false;
    }
    return true;
  }
}
