import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/theme.dart';

class ElevoNavDestination {
  final IconData icon;
  final String label;
  final int badge;

  const ElevoNavDestination({
    required this.icon,
    required this.label,
    this.badge = 0,
  });
}

/// Dark charcoal bar with a navy pill behind the active icon.
class ElevoBottomNav extends StatelessWidget {
  final List<ElevoNavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const ElevoBottomNav({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    return Container(
      color: colors.header,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _Tab(
                    icon: destinations[i].icon,
                    label: destinations[i].label,
                    badge: destinations[i].badge,
                    selected: i == currentIndex,
                    onTap: () => onTap(i),
                    colors: colors,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final IconData icon;
  final String label;
  final int badge;
  final bool selected;
  final VoidCallback onTap;
  final ElevoColors colors;

  const _Tab({
    required this.icon,
    required this.label,
    required this.badge,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final idle = colors.headerMuted;
    const active = Color(0xFFC9A227);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? active : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 20, color: selected ? const Color(0xFF1F3A5F) : idle),
                if (badge > 0)
                  Positioned(
                    right: 4,
                    top: 2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFB42318),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: selected ? active : idle,
            ),
          ),
        ],
      ),
    );
  }
}
