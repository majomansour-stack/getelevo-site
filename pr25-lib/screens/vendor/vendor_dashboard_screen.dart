import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/elevo_logic.dart';
import '../../models/maintenance_model.dart';
import '../../services/vendor_maintenance_query.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/maintenance/repair_photo_strip.dart';
import '../elevo_auth_screens.dart' hide ElevoColors;

class VendorDashboardScreen extends StatefulWidget {
  const VendorDashboardScreen({super.key});

  @override
  State<VendorDashboardScreen> createState() => _VendorDashboardScreenState();
}

class _VendorDashboardScreenState extends State<VendorDashboardScreen> {
  final _db = Supabase.instance.client;
  List<MaintenanceRequest> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    vendorJobsRevision.addListener(_loadJobs);
    _loadJobs();
  }

  @override
  void dispose() {
    vendorJobsRevision.removeListener(_loadJobs);
    super.dispose();
  }

  Future<void> _loadJobs() async {
    if (!mounted) return;
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final rows = await VendorMaintenanceQuery(_db).loadForCurrentUser();
      if (!mounted) return;
      setState(() {
        _requests = rows.map<MaintenanceRequest>(_mapMR).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  MaintenanceRequest _mapMR(Map<String, dynamic> r) => MaintenanceRequest(
        id: r['id'] as String,
        unitId: r['unit_id'] as String,
        propertyId: '',
        landlordId: r['landlord_id'] as String,
        submittedBy: (r['tenant_id'] as String?) ?? '',
        description: r['description'] as String,
        category: (r['category'] as String?) ?? 'Other',
        priority: _cap((r['priority'] as String?) ?? 'medium'),
        status: _mapStatus((r['status'] as String?) ?? 'open'),
        assignedVendorName: r['vendor_name'] as String?,
        estimatedCost: r['estimated_cost'] != null ? (r['estimated_cost'] as num).toDouble() : null,
        unitAddress: r['unit_address'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
        photos: repairPhotoPaths(r['photo_paths']),
      );

  String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
  String _mapStatus(String s) => mapMaintenanceStatus(s);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final requests = _requests;
    final company = vendorCompanyFromMetadata(
      _db.auth.currentUser?.userMetadata,
      user?.fullName,
    );
    final active = requests.where((r) => r.status != 'Resolved').length;
    final completed = requests.where((r) => r.status == 'Resolved').length;

    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const ElevoLogo(height: 28, showWordmark: false),
            const SizedBox(width: AppTheme.spacingSm),
            Text(
              'Vendor Portal',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.midnight,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.logOut, color: colors.midnight, size: 22),
            tooltip: 'Sign Out',
            onPressed: () async {
              await auth.logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        children: [
          // ── Welcome card ───────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            decoration: BoxDecoration(
              color: colors.olive,
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: colors.onOlive.withAlpha(40),
                  child: Text(
                    user?.initials ?? '?',
                    style: TextStyle(
                      color: colors.onOlive,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome back,',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.ivory.withAlpha(160)),
                      ),
                      Text(
                        user?.fullName ?? 'Vendor',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.ivory,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (company.isNotEmpty)
                        Text(
                          company,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colors.onOlive, fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingMd),

          // ── Summary tiles ──────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Active Jobs',
                  value: '$active',
                  icon: LucideIcons.wrench,
                  iconColor: colors.goldInk,
                  colors: colors,
                  theme: theme,
                ),
              ),
              const SizedBox(width: AppTheme.spacingSm),
              Expanded(
                child: _StatCard(
                  label: 'Completed',
                  value: '$completed',
                  icon: LucideIcons.checkCircle,
                  iconColor: colors.successGreen,
                  colors: colors,
                  theme: theme,
                ),
              ),
              const SizedBox(width: AppTheme.spacingSm),
              Expanded(
                child: _StatCard(
                  label: 'This Month',
                  value: '\$${_monthlyEarnings(requests).toStringAsFixed(0)}',
                  icon: LucideIcons.dollarSign,
                  iconColor: colors.midnight,
                  colors: colors,
                  theme: theme,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingLg),

          // ── Active work orders ─────────────────────────────────────────────
          Text(
            'Active Work Orders',
            style: theme.textTheme.titleSmall?.copyWith(
                color: colors.midnight, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppTheme.spacingSm),

          if (requests.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              decoration: AppTheme.surfaceCard(colors),
              child: Column(
                children: [
                  Icon(LucideIcons.checkCircle,
                      color: colors.successGreen, size: 36),
                  const SizedBox(height: AppTheme.spacingSm),
                  Text('No active jobs — all clear!',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: colors.sage)),
                ],
              ),
            )
          else
            ...requests
                .where((r) => r.status != 'Resolved')
                .map((r) => _WorkOrderCard(request: r, colors: colors, theme: theme)),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  double _monthlyEarnings(List<dynamic> requests) {
    return requests
        .where((r) => r.status == 'Resolved')
        .fold(0.0, (sum, r) => sum + (r.estimatedCost ?? 0.0));
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final ElevoColors colors;
  final ThemeData theme;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.colors,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: AppTheme.surfaceCard(colors),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: AppTheme.spacingXs),
          Text(value,
              style: AppTheme.serif(
                theme.textTheme.headlineSmall,
                color: colors.ink,
                fontSize: 26,
              )),
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: colors.sage)),
        ],
      ),
    );
  }
}

class _WorkOrderCard extends StatelessWidget {
  final dynamic request;
  final ElevoColors colors;
  final ThemeData theme;

  const _WorkOrderCard({
    required this.request,
    required this.colors,
    required this.theme,
  });

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'High':
        return colors.urgentRed;
      case 'Medium':
        return colors.goldInk;
      default:
        return colors.sage;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingSm),
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: AppTheme.surfaceCard(colors),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.ink, fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    RepairPhotoIndicator(count: request.photos.length, color: colors.sage),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spacingSm),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _priorityColor(request.priority).withAlpha(20),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(
                      color: _priorityColor(request.priority).withAlpha(80)),
                ),
                child: Text(
                  request.priority,
                  style: TextStyle(
                    color: _priorityColor(request.priority),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingXs),
          Row(
            children: [
              Icon(LucideIcons.mapPin, size: 13, color: colors.sage),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  request.unitAddress,
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.sage),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingXs),
          Row(
            children: [
              _StatusChip(status: request.status, colors: colors),
              const Spacer(),
              if (request.estimatedCost != null)
                Text(
                  '\$${request.estimatedCost!.toStringAsFixed(0)} est.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.midnight, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final ElevoColors colors;

  const _StatusChip({required this.status, required this.colors});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (status) {
      case 'Assigned':
        bg = colors.goldInk.withAlpha(28);
        fg = colors.goldInk;
        break;
      case 'In Progress':
        bg = colors.midnight.withAlpha(20);
        fg = colors.midnight;
        break;
      case 'Resolved':
        bg = colors.successGreen.withAlpha(25);
        fg = colors.successGreen;
        break;
      default:
        bg = colors.stone.withAlpha(60);
        fg = colors.sage;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Text(status,
          style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
