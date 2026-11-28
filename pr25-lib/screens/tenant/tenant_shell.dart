import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/common/elevo_bottom_nav.dart';
import '../../widgets/common/elevo_readable_width.dart';

class TenantShell extends StatefulWidget {
  final StatefulNavigationShell child;

  const TenantShell({super.key, required this.child});

  @override
  State<TenantShell> createState() => _TenantShellState();
}

class _TenantShellState extends State<TenantShell> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _loadUnread();
  }

  @override
  void didUpdateWidget(TenantShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child.currentIndex != widget.child.currentIndex) {
      _loadUnread();
    }
  }

  Future<void> _loadUnread() async {
    try {
      final db = Supabase.instance.client;
      final uid = db.auth.currentUser?.id;
      if (uid == null) return;
      final rows = await db
          .from('messages')
          .select('id')
          .eq('receiver_id', uid)
          .eq('is_read', false)
          .limit(1);
      final unread = (rows as List).isNotEmpty ? 1 : 0;
      if (mounted && unread != _unread) setState(() => _unread = unread);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ElevoReadableWidth(child: widget.child),
      bottomNavigationBar: ElevoReadableWidth(
        child: ElevoBottomNav(
          currentIndex: widget.child.currentIndex,
          onTap: (index) {
            HapticFeedback.lightImpact();
            widget.child.goBranch(index);
          },
          destinations: [
            const ElevoNavDestination(icon: LucideIcons.home, label: 'Home'),
            ElevoNavDestination(
              icon: LucideIcons.messageCircle,
              label: 'Messages',
              badge: _unread,
            ),
            const ElevoNavDestination(icon: LucideIcons.wrench, label: 'Repairs'),
            const ElevoNavDestination(icon: LucideIcons.moreHorizontal, label: 'More'),
          ],
        ),
      ),
    );
  }
}
