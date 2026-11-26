import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_theme.dart';

/// A frosted-glass panel: a see-through fill, a thin light edge and,
/// when [blur] is on, a blur of whatever moves behind it.
///
/// Blur is expensive for the phone's graphics chip, so it is off by default.
/// Turn it on only for a few large pieces (nav bar, composer, sheets),
/// never for every row of a long list.
class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool blur;

  /// Optional color mixed into the glass, such as the accent for a selected item.
  final Color? tint;

  const Glass({
    super.key,
    required this.child,
    this.radius = AppRadius.large,
    this.padding,
    this.blur = false,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend((tint ?? Colors.white).withValues(alpha: tint == null ? 0.10 : 0.22), AppColors.glassBase),
            Color.alphaBlend((tint ?? Colors.white).withValues(alpha: tint == null ? 0.04 : 0.10), AppColors.glassBase),
          ],
        ),
        border: Border.all(color: AppColors.glassEdge),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    return ClipRRect(
      borderRadius: shape,
      child: blur
          ? BackdropFilter(filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22), child: panel)
          : panel,
    );
  }
}

/// The same title block at the top of every tab, so tabs feel like one app.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const PageHeader({super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.headlineMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A round glass icon button.
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color color;
  final double size;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = AppColors.textSecondary,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Glass(
        radius: size / 2,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          icon: Icon(icon, color: color, size: size * 0.48),
        ),
      ),
    );
  }
}
