import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/app_colors.dart';

/// Decorative restaurant-style cards that drift upward behind the home
/// screen, at different depths (far ones are smaller, fainter and blurred).
///
/// They show only a cuisine and an emoji, never a restaurant name: every
/// name the app shows must come from Google Places (see AGENTS.md), so fake
/// names here could be mistaken for real results.
///
/// Screen readers skip them, taps pass through them, and they hold still
/// when the phone's "reduce motion" setting is on.
class FloatingCards extends StatefulWidget {
  const FloatingCards({super.key});

  @override
  State<FloatingCards> createState() => _FloatingCardsState();
}

class _Spec {
  final String emoji;
  final String cuisine;
  final double x; // 0..1 across the screen
  final double startY; // 0..1 down the screen at time 0
  final double depth; // 0 = far, 1 = near
  final double sway; // phase of the side-to-side drift
  const _Spec(this.emoji, this.cuisine, this.x, this.startY, this.depth, this.sway);
}

class _FloatingCardsState extends State<FloatingCards> with SingleTickerProviderStateMixin {
  static const _cards = [
    _Spec('🍜', 'Ramen', 0.05, 0.05, 0.9, 0.0),
    _Spec('🌮', 'Tacos', 0.62, 0.18, 0.5, 1.3),
    _Spec('🍣', 'Sushi', 0.30, 0.42, 0.2, 2.6),
    _Spec('🍕', 'Pizza', 0.72, 0.60, 0.85, 3.9),
    _Spec('🥗', 'Salad', 0.02, 0.72, 0.35, 5.2),
    _Spec('🍔', 'Burgers', 0.45, 0.88, 0.6, 0.7),
    _Spec('🥟', 'Dumplings', 0.80, 0.95, 0.25, 2.0),
  ];

  late final AnimationController _time = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _time.stop();
    } else if (!_time.isAnimating) {
      _time.repeat();
    }
  }

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: LayoutBuilder(
            builder: (context, box) {
              // Children are built once; only their positions change per frame.
              final cards = [for (final s in _cards) _MiniCard(spec: s)];
              return AnimatedBuilder(
                animation: _time,
                builder: (context, _) {
                  final t = _time.value;
                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      for (var i = 0; i < _cards.length; i++) _place(_cards[i], cards[i], t, box.biggest),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _place(_Spec s, Widget card, double t, Size area) {
    // Near cards rise faster than far ones, which gives a sense of depth.
    final speed = 0.6 + 0.8 * s.depth;
    final y = ((s.startY - t * speed) % 1.3) - 0.2; // wraps from top back to bottom
    final angle = t * 2 * math.pi * 3 + s.sway;
    return Positioned(
      left: area.width * s.x + 14 * math.sin(angle),
      top: area.height * y,
      child: Transform.rotate(angle: 0.08 * math.sin(angle * 0.7), child: card),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final _Spec spec;
  const _MiniCard({required this.spec});

  @override
  Widget build(BuildContext context) {
    final scale = 0.65 + 0.35 * spec.depth;
    final card = Opacity(
      opacity: 0.18 + 0.30 * spec.depth,
      child: Container(
        width: 118 * scale,
        padding: EdgeInsets.all(12 * scale),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22 * scale),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withValues(alpha: 0.14), Colors.white.withValues(alpha: 0.04)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 54 * scale,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14 * scale),
                color: AppColors.accent.withValues(alpha: 0.22),
              ),
              alignment: Alignment.center,
              child: Text(spec.emoji, style: TextStyle(fontSize: 26 * scale)),
            ),
            SizedBox(height: 8 * scale),
            Text(
              spec.cuisine,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13 * scale, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6 * scale),
            Row(
              children: [
                Icon(Icons.star_rounded, size: 12 * scale, color: AppColors.gold),
                SizedBox(width: 4 * scale),
                Expanded(
                  child: Container(
                    height: 5 * scale,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    // Far cards are slightly out of focus.
    if (spec.depth >= 0.5) return card;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
      child: card,
    );
  }
}
