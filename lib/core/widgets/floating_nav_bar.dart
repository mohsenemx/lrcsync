import 'package:flutter/material.dart';

class FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const FloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1.0,
          child: Material(
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.25),
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(100),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _NavIconItem(
                    icon: Icons.music_note_outlined,
                    selectedIcon: Icons.music_note_rounded,
                    tooltip: 'Now Playing',
                    isSelected: currentIndex == 0,
                    onTap: () => onTap(0),
                  ),
                  const SizedBox(width: 6),
                  _NavIconItem(
                    icon: Icons.library_music_outlined,
                    selectedIcon: Icons.library_music_rounded,
                    tooltip: 'Local Library',
                    isSelected: currentIndex == 1,
                    onTap: () => onTap(1),
                  ),
                  const SizedBox(width: 6),
                  _NavIconItem(
                    icon: Icons.settings_outlined,
                    selectedIcon: Icons.settings_rounded,
                    tooltip: 'Settings & About',
                    isSelected: currentIndex == 2,
                    onTap: () => onTap(2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavIconItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavIconItem({
    required this.icon,
    required this.selectedIcon,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 22),
          decoration: BoxDecoration(
            color: isSelected ? scheme.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Icon(
            isSelected ? selectedIcon : icon,
            size: 24,
            color: isSelected
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
