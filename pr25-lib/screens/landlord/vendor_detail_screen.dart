import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/elevo_logic.dart';
import '../../models/vendor_model.dart';
import '../../theme/theme.dart';

// ── Job record from maintenance_requests ─────────────────────────────────────

class _JobRecord {
  final String id;
  final String unitLabel;
  final String description;
  final double cost;
  final String status;
  final DateTime date;

  const _JobRecord({
    required this.id,
    required this.unitLabel,
    required this.description,
    required this.cost,
    required this.status,
    required this.date,
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class VendorDetailScreen extends StatefulWidget {
  final String vendorId;

  const VendorDetailScreen({super.key, required this.vendorId});

  @override
  State<VendorDetailScreen> createState() => _VendorDetailScreenState();
}

class _VendorDetailScreenState extends State<VendorDetailScreen> {
  final _db = Supabase.instance.client;
  Vendor? _vendor;
  List<_JobRecord> _jobs = [];
  bool _loadingVendor = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final vRow = await _db
          .from('vendors')
          .select()
          .eq('id', widget.vendorId)
          .maybeSingle();
      if (vRow == null) {
        if (mounted) setState(() { _loadingVendor = false; _error = 'Vendor not found.'; });
        return;
      }
      final vendor = _mapVendor(vRow);

      // Load maintenance requests assigned to this vendor
      final mrRows = await _db
          .from('maintenance_requests')
          .select()
          .eq('vendor_id', widget.vendorId)
          .order('created_at', ascending: false);

      final jobs = mrRows.map<_JobRecord>((r) => _JobRecord(
            id: r['id'] as String,
            unitLabel: (r['unit_address'] as String?) ?? 'Unknown unit',
            description: r['description'] as String,
            cost: ((r['estimated_cost'] as num?) ?? 0).toDouble(),
            status: _mapStatus((r['status'] as String?) ?? 'open'),
            date: DateTime.parse(r['created_at'] as String),
          )).toList();

      setState(() {
        _vendor = vendor;
        _jobs = jobs;
        _loadingVendor = false;
      });
    } catch (e) {
      debugPrint('VendorDetail error: $e');
      setState(() {
        _loadingVendor = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _deleteVendor() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Vendor'),
        content: Text(
            'Remove ${_vendor?.name ?? 'this vendor'}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.from('vendors').delete().eq('id', widget.vendorId);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete vendor: $e')),
        );
      }
    }
  }

  Vendor _mapVendor(Map<String, dynamic> r) => Vendor(
        id: r['id'] as String,
        landlordId: r['landlord_id'] as String,
        name: (r['name'] as String?) ?? '',
        company: (r['company_name'] as String?) ?? '',
        category: (r['category'] as String?) ?? 'Other',
        phone: (r['phone'] as String?) ?? '',
        email: (r['email'] as String?) ?? '',
        spendLimit: ((r['spend_limit'] as num?) ?? 0).toDouble(),
        isActive: (r['is_active'] as bool?) ?? true,
        createdAt: r['created_at'] != null
            ? DateTime.parse(r['created_at'] as String)
            : DateTime.now(),
      );

  String _mapStatus(String s) => mapMaintenanceStatus(s);

  void _openEditSheet() {
    if (_vendor == null) return;
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditVendorSheet(
        vendor: _vendor!,
        onSave: (updated) {
          setState(() => _vendor = updated);
          _saveVendorUpdate(updated, showFeedback: true);
        },
      ),
    );
  }

  Future<void> _saveVendorUpdate(Vendor v, {bool showFeedback = false}) async {
    try {
      await _db.from('vendors').update({
        'name': v.name,
        'company_name': v.company,
        'category': v.category,
        'phone': v.phone,
        'email': v.email,
        'spend_limit': v.spendLimit,
        'is_active': v.isActive,
      }).eq('id', v.id).select();
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(v.isActive ? 'Vendor set to Active' : 'Vendor set to Inactive'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save vendor: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingVendor) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_vendor == null) {
      final theme  = Theme.of(context);
      final colors = theme.extension<ElevoColors>()!;
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
            onPressed: () => context.pop(),
          ),
          title: const Text('Vendor'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.alertCircle, color: colors.gold, size: 40),
                const SizedBox(height: AppTheme.spacingMd),
                Text('Could not load vendor.',
                    style: theme.textTheme.titleMedium),
                if (_error != null) ...[
                  const SizedBox(height: AppTheme.spacingSm),
                  Text(_error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.sage),
                      textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final theme   = Theme.of(context);
    final colors  = theme.extension<ElevoColors>()!;
    final fmt     = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final vendor  = _vendor!;
    final jobs    = _jobs;
    final totalSpend = jobs.where((j) => j.status == 'Resolved').fold(0.0, (s, j) => s + j.cost);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => context.pop(),
        ),
        title: Text(vendor.name),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.pencil, color: colors.gold, size: 20),
            onPressed: _openEditSheet,
            tooltip: 'Edit Vendor',
          ),
          IconButton(
            icon: const Icon(LucideIcons.trash2, color: Colors.red, size: 20),
            onPressed: _deleteVendor,
            tooltip: 'Delete Vendor',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        children: [

          // ── Profile Card ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            decoration: BoxDecoration(
              color: colors.charcoal,
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              border: Border.all(color: colors.gold.withAlpha(40)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Avatar circle
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.gold.withAlpha(20),
                        border: Border.all(color: colors.gold.withAlpha(80)),
                      ),
                      child: Center(
                        child: Text(
                          vendor.name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase(),
                          style: TextStyle(color: colors.goldInk, fontWeight: FontWeight.w700, fontSize: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(vendor.name, style: theme.textTheme.titleLarge?.copyWith(color: colors.ivory)),
                          Text(vendor.company, style: theme.textTheme.bodySmall?.copyWith(color: colors.sage)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _StatusBadge(label: vendor.category, color: colors.gold),
                              const SizedBox(width: 8),
                              _StatusBadge(
                                label: vendor.isActive ? 'Active' : 'Inactive',
                                color: vendor.isActive ? colors.successGreen : colors.taupe,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppTheme.spacingMd),
                Divider(color: colors.taupe.withAlpha(30)),
                const SizedBox(height: AppTheme.spacingMd),

                // Contact rows
                _ContactRow(icon: LucideIcons.phone, value: vendor.phone, label: 'Phone', colors: colors, theme: theme),
                const SizedBox(height: AppTheme.spacingSm),
                _ContactRow(icon: LucideIcons.mail, value: vendor.email, label: 'Email', colors: colors, theme: theme),
                const SizedBox(height: AppTheme.spacingSm),
                _InfoRow(
                  icon: LucideIcons.shield,
                  label: 'Spend Limit',
                  value: vendor.spendLimit <= 0
                      ? 'No limit set'
                      : 'Up to ${fmt.format(vendor.spendLimit)} per job',
                  colors: colors,
                  theme: theme,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacingMd),

          // ── Stats row ────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(child: _StatCard(label: 'Jobs Completed', value: '${jobs.where((j) => j.status == 'Resolved').length}', icon: LucideIcons.checkCircle, color: colors.successGreen, theme: theme, colors: colors)),
              const SizedBox(width: AppTheme.spacingSm),
              Expanded(child: _StatCard(label: 'Active', value: '${jobs.where((j) => j.status == 'In Progress' || j.status == 'Assigned').length}', icon: LucideIcons.clock, color: colors.warningAmber, theme: theme, colors: colors)),
              const SizedBox(width: AppTheme.spacingSm),
              Expanded(child: _StatCard(label: 'Total Spend', value: fmt.format(totalSpend), icon: LucideIcons.dollarSign, color: colors.gold, theme: theme, colors: colors)),
            ],
          ),

          const SizedBox(height: AppTheme.spacingLg),

          // ── Job History ──────────────────────────────────────────────────
          Row(
            children: [
              Icon(LucideIcons.clipboardList, color: colors.gold, size: 16),
              const SizedBox(width: 8),
              Text('Job History', style: theme.textTheme.titleSmall?.copyWith(color: colors.goldInk)),
            ],
          ),
          const SizedBox(height: AppTheme.spacingSm),

          if (jobs.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              decoration: BoxDecoration(
                color: colors.charcoal,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
              child: Text('No jobs recorded yet.', style: theme.textTheme.bodySmall),
            )
          else
            ...jobs.map((j) => _JobRow(job: j, fmt: fmt, theme: theme, colors: colors)),

          const SizedBox(height: AppTheme.spacingLg),

          // ── Quick Actions ─────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Calling ${vendor.phone}…')),
                    );
                  },
                  icon: Icon(LucideIcons.phone, size: 16, color: colors.gold),
                  label: const Text('Call'),
                ),
              ),
              const SizedBox(width: AppTheme.spacingSm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Emailing ${vendor.email}…')),
                    );
                  },
                  icon: Icon(LucideIcons.mail, size: 16, color: colors.gold),
                  label: const Text('Email'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMd),

          // Toggle active status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm),
            decoration: BoxDecoration(
              color: colors.charcoal,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.toggleLeft, color: colors.taupe, size: 18),
                const SizedBox(width: AppTheme.spacingSm),
                Expanded(child: Text('Vendor Active', style: theme.textTheme.bodyMedium?.copyWith(color: colors.ivory))),
                Switch(
                  value: vendor.isActive,
                  onChanged: (v) {
                    HapticFeedback.lightImpact();
                    final updated = Vendor(
                      id: vendor.id, landlordId: vendor.landlordId,
                      name: vendor.name, company: vendor.company,
                      category: vendor.category, phone: vendor.phone,
                      email: vendor.email, spendLimit: vendor.spendLimit,
                      isActive: v, createdAt: vendor.createdAt,
                    );
                    setState(() => _vendor = updated);
                    _saveVendorUpdate(updated, showFeedback: true);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

// ── Supporting Widgets ────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final ElevoColors colors;
  final ThemeData theme;

  const _ContactRow({required this.icon, required this.value, required this.label, required this.colors, required this.theme});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label: $value')));
      },
      child: Row(
        children: [
          Icon(icon, color: colors.gold, size: 16),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall?.copyWith(color: colors.sage)),
              Text(value, style: theme.textTheme.bodyMedium?.copyWith(color: colors.ivory)),
            ],
          )),
          Icon(LucideIcons.copy, color: colors.taupe, size: 14),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ElevoColors colors;
  final ThemeData theme;

  const _InfoRow({required this.icon, required this.label, required this.value, required this.colors, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: colors.taupe, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: colors.sage)),
            Text(value, style: theme.textTheme.bodyMedium?.copyWith(color: colors.ivory)),
          ],
        )),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final ThemeData theme;
  final ElevoColors colors;

  const _StatCard({required this.label, required this.value, required this.icon, required this.color, required this.theme, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.charcoal,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 6),
          Text(value, style: theme.textTheme.titleMedium?.copyWith(color: color)),
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: colors.sage)),
        ],
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  final _JobRecord job;
  final NumberFormat fmt;
  final ThemeData theme;
  final ElevoColors colors;

  const _JobRow({required this.job, required this.fmt, required this.theme, required this.colors});

  @override
  Widget build(BuildContext context) {
    final statusColor = job.status == 'Resolved' ? colors.successGreen
        : job.status == 'In Progress' ? colors.warningAmber
        : colors.taupe;
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingXs),
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.charcoal,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border(left: BorderSide(color: statusColor, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(job.description, style: theme.textTheme.bodyMedium?.copyWith(color: colors.ivory), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(LucideIcons.home, color: colors.taupe, size: 11),
                    const SizedBox(width: 4),
                    Text(job.unitLabel, style: theme.textTheme.labelSmall),
                    const SizedBox(width: 8),
                    Icon(LucideIcons.calendar, color: colors.taupe, size: 11),
                    const SizedBox(width: 4),
                    Text('${months[job.date.toLocal().month - 1]} ${job.date.toLocal().day}', style: theme.textTheme.labelSmall),
                    const SizedBox(width: 8),
                    Text('·', style: theme.textTheme.labelSmall),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacingSm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fmt.format(job.cost), style: theme.textTheme.titleSmall?.copyWith(color: colors.goldInk)),
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(job.status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Edit Vendor Sheet ─────────────────────────────────────────────────────────

class _EditVendorSheet extends StatefulWidget {
  final Vendor vendor;
  final ValueChanged<Vendor> onSave;

  const _EditVendorSheet({required this.vendor, required this.onSave});

  @override
  State<_EditVendorSheet> createState() => _EditVendorSheetState();
}

class _EditVendorSheetState extends State<_EditVendorSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _companyCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _limitCtrl;
  late String _category;
  late bool _isActive;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl    = TextEditingController(text: widget.vendor.name);
    _companyCtrl = TextEditingController(text: widget.vendor.company);
    _phoneCtrl   = TextEditingController(text: widget.vendor.phone);
    _emailCtrl   = TextEditingController(text: widget.vendor.email);
    _limitCtrl   = TextEditingController(text: widget.vendor.spendLimit.toStringAsFixed(0));
    _category    = widget.vendor.category;
    _isActive    = widget.vendor.isActive;
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _companyCtrl.dispose(); _phoneCtrl.dispose();
    _emailCtrl.dispose(); _limitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppTheme.spacingMd, right: AppTheme.spacingMd,
          top: AppTheme.spacingLg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppTheme.spacingLg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: AppTheme.spacingLg),
                  decoration: BoxDecoration(
                    color: colors.taupe.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Edit Vendor', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppTheme.spacingMd),

              TextFormField(controller: _nameCtrl, decoration: InputDecoration(
                labelText: 'Contact Name *',
                prefixIcon: Icon(LucideIcons.user, color: colors.taupe, size: 18),
              )),
              const SizedBox(height: AppTheme.spacingMd),

              TextFormField(controller: _companyCtrl, decoration: InputDecoration(
                labelText: 'Company Name',
                prefixIcon: Icon(LucideIcons.building2, color: colors.taupe, size: 18),
              )),
              const SizedBox(height: AppTheme.spacingMd),

              DropdownButtonFormField<String>(
                value: _category,
                decoration: InputDecoration(
                  labelText: 'Trade Category',
                  prefixIcon: Icon(LucideIcons.tag, color: colors.taupe, size: 18),
                ),
                dropdownColor: colors.card,
                items: Vendor.categories.map((c) => DropdownMenuItem(
                  value: c,
                  child: Text(c, style: theme.textTheme.bodyMedium),
                )).toList(),
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: AppTheme.spacingMd),

              TextFormField(controller: _phoneCtrl, keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(LucideIcons.phone, color: colors.taupe, size: 18),
                )),
              const SizedBox(height: AppTheme.spacingMd),

              TextFormField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(LucideIcons.mail, color: colors.taupe, size: 18),
                )),
              const SizedBox(height: AppTheme.spacingMd),

              TextFormField(controller: _limitCtrl, keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Spend Limit (per job)',
                  prefixText: '\$',
                  prefixIcon: Icon(LucideIcons.dollarSign, color: colors.taupe, size: 18),
                )),
              const SizedBox(height: AppTheme.spacingMd),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm),
                decoration: BoxDecoration(
                  color: colors.midnight,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(color: colors.taupe.withAlpha(80)),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text('Vendor Active', style: theme.textTheme.bodyMedium)),
                    Switch(value: _isActive, onChanged: (v) => setState(() => _isActive = v)),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacingLg),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          if (_nameCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Vendor name is required')),
                            );
                            return;
                          }
                          HapticFeedback.lightImpact();
                          setState(() => _isSaving = true);
                          await Future.delayed(const Duration(milliseconds: 800));
                          final updated = Vendor(
                            id: widget.vendor.id,
                            landlordId: widget.vendor.landlordId,
                            name: _nameCtrl.text.trim(),
                            company: _companyCtrl.text.trim(),
                            category: _category,
                            phone: _phoneCtrl.text.trim(),
                            email: _emailCtrl.text.trim(),
                            spendLimit: double.tryParse(_limitCtrl.text.trim()) ?? widget.vendor.spendLimit,
                            isActive: _isActive,
                            createdAt: widget.vendor.createdAt,
                          );
                          if (mounted) {
                            widget.onSave(updated);
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Vendor updated successfully')),
                            );
                          }
                        },
                  icon: _isSaving
                      ? SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(LucideIcons.save, size: 18, color: Colors.white),
                  label: Text(_isSaving ? 'Saving…' : 'Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
