import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_colors.dart';
import 'glass.dart';

/// A floating frosted-glass tab bar with one glowing "lens" that slides to
/// the tab you tap. While it travels, the lens stretches and then springs
/// back, so the movement feels fluid rather than jumping.
class GlassNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const GlassNav({super.key, required this.currentIndex, required this.onTap});

  static const _items = [
    (Icons.home_rounded, 'Home'),
    (Icons.bookmark_rounded, 'Saved'),
    (Icons.group_rounded, 'Friends'),
    (Icons.person_rounded, 'Profile'),
  ];

  @override
  State<GlassNav> createState() => _GlassNavState();
}

class _GlassNavState extends State<GlassNav> with SingleTickerProviderStateMixin {
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late double _from = widget.currentIndex.toDouble();
  late double _to = widget.currentIndex.toDouble();

  @override
  void didUpdateWidget(GlassNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _from = _position;
      _to = widget.currentIndex.toDouble();
      if (MediaQuery.disableAnimationsOf(context)) {
        _move.value = 1;
      } else {
        _move.forward(from: 0);
      }
    }
  }

  /// Where the lens is now, measured in tabs (0 = first tab).
  double get _position {
    final eased = Curves.easeOutBack.transform(_move.value);
    return _from + (_to - _from) * eased;
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 10 + bottom),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(999)),
          boxShadow: [BoxShadow(color: Color(0x73000000), blurRadius: 30, offset: Offset(0, 12))],
        ),
        child: Glass(
          blur: true,
          radius: 999,
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            height: 60,
            child: LayoutBuilder(
              builder: (context, box) {
                final slot = box.maxWidth / GlassNav._items.length;
                return AnimatedBuilder(
                  animation: _move,
                  builder: (context, _) {
                    // Stretch most in the middle of the trip, none at either end.
                    final stretch = math.sin(_move.value * math.pi) * (_to - _from).abs().clamp(0, 1);
                    final width = slot * (1 + 0.35 * stretch);
                    final left = _position * slot - (width - slot) / 2;
                    return Stack(
                      children: [
                        Positioned(
                          left: left,
                          width: width,
                          top: 0,
                          bottom: 0,
                          child: const _Lens(),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < GlassNav._items.length; i++)
                              Expanded(
                                child: _NavItem(
                                  icon: GlassNav._items[i].$1,
                                  label: GlassNav._items[i].$2,
                                  // Light up as the lens arrives, not after it lands.
                                  glow: (1 - (_position - i).abs()).clamp(0.0, 1.0),
                                  selected: widget.currentIndex == i,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    widget.onTap(i);
                                  },
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The glowing glass bubble behind the selected tab.
class _Lens extends StatelessWidget {
  const _Lens();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.accent.withValues(alpha: 0.38),
            AppColors.accent.withValues(alpha: 0.16),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.35), blurRadius: 18)],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final double glow; // 0 = idle, 1 = fully lit
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.glow,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(AppColors.textMuted, AppColors.textPrimary, glow)!;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.scale(scale: 1 + 0.08 * glow, child: Icon(icon, size: 24, color: color)),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color, letterSpacing: 0.2),
            ),
          ],
        ),
      ),
    );
  }
}
