import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../widgets/common/elevo_bottom_nav.dart';
import '../../widgets/common/elevo_readable_width.dart';

class VendorShell extends StatelessWidget {
  final StatefulNavigationShell child;

  const VendorShell({super.key, required this.child});

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
          ElevoNavDestination(icon: LucideIcons.layoutDashboard, label: 'Dashboard'),
          ElevoNavDestination(icon: LucideIcons.clipboardList, label: 'Jobs'),
          ElevoNavDestination(icon: LucideIcons.messageSquare, label: 'Messages'),
          ElevoNavDestination(icon: LucideIcons.barChart2, label: 'Reports'),
          ElevoNavDestination(icon: LucideIcons.creditCard, label: 'Plan'),
        ],
        ),
      ),
    );
  }
}
