import 'package:flutter/material.dart';

import '../core/app_colors.dart';

/// The app background: warm charcoal with one soft ember glow at the top.
///
/// One gradient layer only. The old version stacked three see-through
/// gradients, which rendered with blotches on the Android emulator.
class CravioBackground extends StatelessWidget {
  final Widget child;
  const CravioBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        gradient: RadialGradient(
          center: const Alignment(0, -1.1),
          radius: 1.0,
          colors: [
            Color.alphaBlend(AppColors.accent.withValues(alpha: 0.14), AppColors.background),
            AppColors.background,
          ],
        ),
      ),
      child: SizedBox.expand(child: child),
    );
  }
}
