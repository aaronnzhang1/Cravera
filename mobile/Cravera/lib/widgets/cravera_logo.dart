import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/app_colors.dart';

/// Cravera's "presence": a glowing orb whose colors slowly swirl and whose
/// glow breathes. It stands for the AI concierge, and doubles as the logo.
///
/// [thinking] makes it swirl faster, for while a search runs.
class CraveraLogo extends StatefulWidget {
  final double size;
  final bool thinking;

  const CraveraLogo({super.key, this.size = 104, this.thinking = false});

  @override
  State<CraveraLogo> createState() => _CraveraLogoState();
}

class _CraveraLogoState extends State<CraveraLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  Duration get _period => widget.thinking ? const Duration(milliseconds: 1600) : const Duration(seconds: 6);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(CraveraLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thinking != widget.thinking) _sync();
  }

  void _sync() {
    _controller.duration = _period;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          final breath = (math.sin(t * 2 * math.pi) + 1) / 2;
          // Align keeps the orb round when a parent (such as a ListView)
          // forces its children to full width.
          return Align(
            widthFactor: 1,
            heightFactor: 1,
            child: SizedBox.square(
            dimension: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.30 + 0.20 * breath),
                    blurRadius: size * (0.35 + 0.15 * breath),
                  ),
                ],
              ),
              child: ClipOval(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Swirling color body.
                    // Blurred so the colors melt together instead of meeting at a point.
                    ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: size * 0.12, sigmaY: size * 0.12),
                      child: Transform.rotate(
                      angle: t * 2 * math.pi,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: SweepGradient(
                            colors: [
                              AppColors.accent,
                              AppColors.accentLight,
                              AppColors.sage,
                              AppColors.accentLight,
                              AppColors.accent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    ),
                    // Soft light from the top left, so it reads as a sphere.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(-0.4, -0.5),
                          radius: 0.9,
                          colors: [Color(0x59FFFFFF), Color(0x00FFFFFF)],
                        ),
                      ),
                    ),
                    // Darker rim at the bottom for depth.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0, -0.2),
                          radius: 0.75,
                          colors: [Color(0x00000000), Color(0x55000000)],
                          stops: [0.6, 1.0],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
          );
        },
      ),
    );
  }
}
