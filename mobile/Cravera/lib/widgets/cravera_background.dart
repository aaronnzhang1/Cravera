import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_colors.dart';

/// The app background: cream with three soft color glows (olive,
/// sage, light violet) that drift slowly. The glows give the glass panels something
/// to show through, which is what makes glass read as glass.
///
/// Everything is drawn by one painter in one layer, which keeps it cheap.
/// It holds still when the phone's "reduce motion" setting is on.
class CraveraBackground extends StatefulWidget {
  final Widget child;
  const CraveraBackground({super.key, required this.child});

  @override
  State<CraveraBackground> createState() => _CraveraBackgroundState();
}

class _CraveraBackgroundState extends State<CraveraBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(painter: _GlowPainter(_drift)),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  final Animation<double> t;
  _GlowPainter(this.t) : super(repaint: t);

  // (color, strength, start x, start y, radius as a share of width, phase)
  static const _glows = [
    (AppColors.accent, 0.10, 0.15, 0.05, 0.95, 0.0),
    (AppColors.tomato, 0.06, 0.95, 0.35, 0.75, 2.1),
    (AppColors.accentLight, 0.07, 0.10, 0.85, 0.85, 4.2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final angle = t.value * 2 * math.pi;
    for (final (color, strength, x, y, r, phase) in _glows) {
      final center = Offset(
        size.width * (x + 0.08 * math.sin(angle + phase)),
        size.height * (y + 0.05 * math.cos(angle + phase)),
      );
      final radius = size.width * r;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: strength), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) => false;
}
