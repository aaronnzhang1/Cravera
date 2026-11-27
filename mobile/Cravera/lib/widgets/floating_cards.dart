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
  final double depth; // 0 = far, 1 = near
  const _Spec(this.emoji, this.cuisine, this.depth);
}

class _FloatingCardsState extends State<FloatingCards> with SingleTickerProviderStateMixin {
  // Cards alternate between a left and a right lane at the screen edges, so
  // the headline in the middle stays clear. They start evenly spaced down the
  // screen and all move at one speed, so the gaps never change and no two
  // cards overlap.
  static const _cards = [
    _Spec('🍜', 'Ramen', 0.9),
    _Spec('🌮', 'Tacos', 0.4),
    _Spec('🍣', 'Sushi', 0.7),
    _Spec('🍕', 'Pizza', 0.3),
    _Spec('🥗', 'Salad', 0.8),
    _Spec('🍔', 'Burgers', 0.5),
  ];
  static const _cardWidth = 118.0; // a near card's width; far cards are smaller

  /// The loop length as a share of screen height. A card leaves at the top
  /// and comes back in at the bottom, with room to be fully off screen.
  static const _loop = 1.4;

  late final AnimationController _time = AnimationController(vsync: this, duration: const Duration(seconds: 42));

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
              final cards = [for (final spec in _cards) _MiniCard(spec: spec)];
              return AnimatedBuilder(
                animation: _time,
                builder: (context, _) {
                  final t = _time.value;
                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [for (var i = 0; i < _cards.length; i++) _place(i, cards[i], t, box.biggest)],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _place(int i, Widget card, double t, Size area) {
    final spec = _cards[i];
    final width = _cardWidth * _MiniCard.scaleFor(spec.depth);
    // Lane centers sit near the edges, so each card peeks in from the side.
    final centerX = i.isEven ? area.width * 0.13 : area.width * 0.87;
    final startY = i * _loop / _cards.length;
    // One controller cycle moves every card exactly one loop, so the last frame
    // matches the first and nothing jumps when the animation repeats.
    final y = ((startY - t * _loop) % _loop) - 0.25; // wraps from top back to bottom
    final sway = math.sin(t * 2 * math.pi * 3 + i);
    return Positioned(
      left: centerX - width / 2 + 8 * sway,
      top: area.height * y,
      child: Transform.rotate(angle: 0.05 * sway, child: card),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final _Spec spec;
  const _MiniCard({required this.spec});

  /// Far cards are drawn smaller, which reads as distance.
  static double scaleFor(double depth) => 0.65 + 0.35 * depth;

  @override
  Widget build(BuildContext context) {
    final scale = scaleFor(spec.depth);
    // On cream, cards need more presence than on the old dark theme to read
    // as "alive", while staying behind the question and the input.
    final card = Opacity(
      opacity: 0.35 + 0.40 * spec.depth,
      child: Container(
        width: 118 * scale,
        padding: EdgeInsets.all(12 * scale),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22 * scale),
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 54 * scale,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14 * scale),
                color: AppColors.accentSoft,
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
                      color: AppColors.surface3,
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
    return ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5), child: card);
  }
}
