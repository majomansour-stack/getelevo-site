import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../widgets/common/elevo_bottom_nav.dart';
import '../../widgets/common/elevo_readable_width.dart';

class LandlordShell extends StatelessWidget {
  final StatefulNavigationShell child;

  const LandlordShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ElevoReadableWidth(child: child),
      bottomNavigationBar: ElevoReadableWidth(
        child: ElevoBottomNav(
        currentIndex: child.currentIndex,
        onTap: (index) {
          HapticFeedback.lightImpact();
          child.goBranch(index);
        },
        destinations: const [
          ElevoNavDestination(icon: LucideIcons.home, label: 'Home'),
          ElevoNavDestination(icon: LucideIcons.building2, label: 'Properties'),
          ElevoNavDestination(icon: LucideIcons.messageCircle, label: 'Messages'),
          ElevoNavDestination(icon: LucideIcons.moreHorizontal, label: 'More'),
        ],
        ),
      ),
    );
  }
}
