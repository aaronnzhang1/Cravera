import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_colors.dart';

class CraveraLogo extends StatefulWidget {
  final double size;
  final Duration duration;
  final IconData icon;

  const CraveraLogo({
    super.key,
    this.size = 104,
    this.duration = const Duration(milliseconds: 2200),
    this.icon = Icons.auto_awesome_rounded,
  });

  @override
  State<CraveraLogo> createState() => _CraveraLogoState();
}

class _CraveraLogoState extends State<CraveraLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pulse = (math.sin(_controller.value * math.pi * 2) + 1) / 2;
        final scale = 0.965 + (pulse * 0.04);
        final blur = 18 + (pulse * 18);
        final spread = 1 + (pulse * 3);
        final alpha = 0.18 + (pulse * 0.18);

        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF2895F), AppColors.accent, AppColors.accentPressed],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: alpha),
                  blurRadius: blur,
                  spreadRadius: spread,
                ),
              ],
            ),
            child: Center(
              child: Icon(
                widget.icon,
                size: widget.size * 0.42,
                color: AppColors.onAccent,
              ),
            ),
          ),
        );
      },
    );
  }
}
