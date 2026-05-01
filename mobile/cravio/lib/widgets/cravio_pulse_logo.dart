import 'dart:math' as math;

import 'package:flutter/material.dart';

class CravioPulseLogo extends StatefulWidget {
  final double size;
  final Duration duration;
  final IconData icon;

  const CravioPulseLogo({
    super.key,
    this.size = 104,
    this.duration = const Duration(milliseconds: 2200),
    this.icon = Icons.auto_awesome_rounded,
  });

  @override
  State<CravioPulseLogo> createState() => _CravioPulseLogoState();
}

class _CravioPulseLogoState extends State<CravioPulseLogo> with SingleTickerProviderStateMixin {
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
              color: const Color(0xFF2E5D45),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF56B36A).withValues(alpha: alpha),
                  blurRadius: blur,
                  spreadRadius: spread,
                ),
              ],
            ),
            child: Center(
              child: Icon(
                widget.icon,
                size: widget.size * 0.42,
                color: const Color(0xFFE8F2EC),
              ),
            ),
          ),
        );
      },
    );
  }
}
