import 'package:flutter/material.dart';

import '../core/app_colors.dart';

class ExpandingBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const ExpandingBottomNav({super.key, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(18, 10, 18, 12 + bottomPadding),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: AppColors.border.withValues(alpha: 0.50))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(selected: currentIndex == 0, label: 'Home', icon: Icons.home_outlined, onTap: () => onTap(0)),
          _NavItem(selected: currentIndex == 1, label: 'Bookmarks', icon: Icons.bookmark_border_rounded, onTap: () => onTap(1)),
          _NavItem(selected: currentIndex == 2, label: 'Friends', icon: Icons.group_outlined, onTap: () => onTap(2)),
          _NavItem(selected: currentIndex == 3, label: 'Profile', icon: Icons.person_outline_rounded, onTap: () => onTap(3)),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _NavItem({required this.selected, required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8EAED) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? const Color(0xFF56B36A) : AppColors.textMuted),
            if (selected) ...[
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Color(0xFF56B36A), fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }
}
