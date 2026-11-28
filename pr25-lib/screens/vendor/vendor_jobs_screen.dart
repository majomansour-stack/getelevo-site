import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/elevo_logic.dart';
import '../../models/maintenance_model.dart';
import '../../services/vendor_maintenance_query.dart';
import '../../theme/theme.dart';
import '../chat_screen.dart';
import '../../widgets/maintenance/repair_photo_strip.dart';

class VendorJobsScreen extends StatefulWidget {
  const VendorJobsScreen({super.key});

  @override
  State<VendorJobsScreen> createState() => _VendorJobsScreenState();
}

class _VendorJobsScreenState extends State<VendorJobsScreen> {
  final _db = Supabase.instance.client;
  String _filter = 'All';
  final _filters = ['All', 'Submitted', 'Assigned', 'In Progress', 'Resolved'];
  List<MaintenanceRequest> _allJobs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) { setState(() => _loading = false); return; }
      final rows = await VendorMaintenanceQuery(_db).loadForCurrentUser();
      setState(() {
        _allJobs = rows.map<MaintenanceRequest>(_mapMR).toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
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
        assignedVendorId: r['vendor_user_id']?.toString(),
        assignedVendorName: r['vendor_name'] as String?,
        estimatedCost: r['estimated_cost'] != null ? (r['estimated_cost'] as num).toDouble() : null,
        unitAddress: r['unit_address'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
        photos: repairPhotoPaths(r['photo_paths']),
      );

  String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
  String _mapStatus(String s) => mapMaintenanceStatus(s);

  void _applySavedStatus(String id, String dbStatus) {
    final display = mapMaintenanceStatus(dbStatus);
    setState(() {
      _allJobs = [
        for (final job in _allJobs)
          if (job.id == id) _copyJobStatus(job, display) else job,
      ];
    });
    notifyVendorJobsChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final all = _allJobs;

    final filtered =
        _filter == 'All' ? all : all.where((r) => r.status == _filter).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('My Jobs',
            style: theme.textTheme.titleMedium?.copyWith(
                color: colors.midnight, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          // Filter chips
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppTheme.spacingXs),
              itemBuilder: (_, i) {
                final f = _filters[i];
                final selected = _filter == f;
                return GestureDetector(
                  onTap: () => setState(() => _filter = f),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? colors.olive : colors.card,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      border: Border.all(
                          color: selected ? colors.olive : colors.stone),
                    ),
                    child: Text(
                      f,
                      style: TextStyle(
                        color: selected ? colors.onOlive : colors.ink,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.clipboardList,
                            size: 48, color: colors.stone),
                        const SizedBox(height: AppTheme.spacingSm),
                        Text('No jobs found',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: colors.sage)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppTheme.spacingMd),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppTheme.spacingSm),
                    itemBuilder: (_, i) {
                      final job = filtered[i];
                      return _JobCard(
                        request: job,
                        colors: colors,
                        theme: theme,
                        onStatusSaved: (dbStatus) => _applySavedStatus(job.id, dbStatus),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

MaintenanceRequest _copyJobStatus(MaintenanceRequest job, String status) {
  return MaintenanceRequest(
    id: job.id,
    unitId: job.unitId,
    propertyId: job.propertyId,
    landlordId: job.landlordId,
    submittedBy: job.submittedBy,
    description: job.description,
    category: job.category,
    priority: job.priority,
    status: status,
    photos: job.photos,
    assignedVendorId: job.assignedVendorId,
    assignedVendorName: job.assignedVendorName,
    estimatedCost: job.estimatedCost,
    actualCost: job.actualCost,
    landlordNotes: job.landlordNotes,
    createdAt: job.createdAt,
    resolvedAt: job.resolvedAt,
    unitAddress: job.unitAddress,
  );
}

class _JobCard extends StatelessWidget {
  final MaintenanceRequest request;
  final ElevoColors colors;
  final ThemeData theme;
  final ValueChanged<String> onStatusSaved;

  const _JobCard({
    required this.request,
    required this.colors,
    required this.theme,
    required this.onStatusSaved,
  });

  Color _priorityColor(String p) {
    switch (p) {
      case 'High':
        return colors.urgentRed;
      case 'Medium':
        return colors.goldInk;
      default:
        return colors.sage;
    }
  }

  Color _statusBg(String s) {
    switch (s) {
      case 'Assigned':
        return colors.gold.withAlpha(30);
      case 'In Progress':
        return colors.midnight.withAlpha(20);
      case 'Resolved':
        return colors.successGreen.withAlpha(25);
      default:
        return colors.stone.withAlpha(60);
    }
  }

  Color _statusFg(String s) {
    switch (s) {
      case 'Assigned':
        return colors.goldInk;
      case 'In Progress':
        return colors.midnight;
      case 'Resolved':
        return colors.successGreen;
      default:
        return colors.sage;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.stone),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.midnight.withAlpha(15),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Icon(LucideIcons.wrench,
                    size: 16, color: colors.midnight),
              ),
              const SizedBox(width: AppTheme.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.category,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: colors.sage),
                    ),
                    RepairPhotoIndicator(count: request.photos.length, color: colors.sage),
                    Text(
                      request.description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.ink, fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spacingSm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
          if (request.photos.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacingSm),
            RepairPhotoStrip(groupId: request.id, paths: request.photos),
          ],
          const SizedBox(height: AppTheme.spacingSm),
          Row(
            children: [
              Icon(LucideIcons.mapPin, size: 13, color: colors.sage),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  request.unitAddress ?? '',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.sage),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingXs),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusBg(request.status),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Text(
                  request.status,
                  style: TextStyle(
                      color: _statusFg(request.status),
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              if (request.estimatedCost != null)
                Text(
                  '\$${request.estimatedCost!.toStringAsFixed(0)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.midnight, fontWeight: FontWeight.w700),
                ),
            ],
          ),
          if ((request.assignedVendorId ?? '').isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacingSm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: Icon(LucideIcons.users, size: 14, color: colors.midnight),
                label: const Text('Job chat', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.stone),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
                ),
                onPressed: () => openJobChat(
                  context,
                  requestId: request.id,
                  unitId: request.unitId,
                  unitAddress: request.unitAddress ?? request.description,
                  status: request.status,
                ),
              ),
            ),
          ],
          if (request.submittedBy.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacingSm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: Icon(LucideIcons.messageSquare, size: 14, color: colors.midnight),
                label: const Text('Message tenant', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.stone),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
                ),
                onPressed: () {
                  context.push(
                    '/vendor/messages/${request.unitId}'
                    '?with=${Uri.encodeComponent(request.submittedBy)}'
                    '&name=${Uri.encodeComponent('Tenant')}'
                    '&addr=${Uri.encodeComponent(request.unitAddress ?? '')}',
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: AppTheme.spacingSm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: Icon(LucideIcons.refreshCw, size: 14, color: colors.midnight),
              label: Text('Update Status',
                  style: TextStyle(color: colors.midnight, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.stone),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
              ),
              onPressed: () => _showUpdateSheet(context),
            ),
          ),
        ],
      ),
    );
  }

  void _showUpdateSheet(BuildContext context) {
    final db = Supabase.instance.client;
    final theme = Theme.of(context);
    final colors = Theme.of(context).extension<ElevoColors>()!;
    final statuses = vendorJobStatusOptions(request.status);
    String selectedStatus = vendorJobStatusInitial(request.status);
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              AppTheme.spacingLg,
              AppTheme.spacingMd,
              AppTheme.spacingLg,
              AppTheme.spacingLg + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
                    decoration: BoxDecoration(color: colors.stone, borderRadius: BorderRadius.circular(2))),
              ),
              Text('Update Job Status', style: theme.textTheme.titleMedium?.copyWith(color: colors.midnight)),
              const SizedBox(height: AppTheme.spacingMd),
              DropdownButtonFormField<String>(
                value: selectedStatus,
                decoration: InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
                ),
                items: [
                  for (final s in statuses)
                    DropdownMenuItem(
                      value: s,
                      child: Text(vendorJobStatusLabels[s] ?? s),
                    ),
                ],
                onChanged: (v) { if (v != null) setSheet(() => selectedStatus = v); },
              ),
              const SizedBox(height: AppTheme.spacingMd),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: saving ? null : () async {
                    setSheet(() => saving = true);
                    try {
                      final update = <String, dynamic>{'status': selectedStatus};
                      if (selectedStatus == 'resolved') {
                        update.addAll(maintenanceCloseTimestamps(DateTime.now()));
                      }
                      await db.from('maintenance_requests')
                          .update(update)
                          .eq('id', request.id);
                      onStatusSaved(selectedStatus);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Job status updated.')),
                        );
                      }
                    } catch (e) {
                      setSheet(() => saving = false);
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Update failed: $e')),
                        );
                      }
                    }
                  },
                  child: saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save Update'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
