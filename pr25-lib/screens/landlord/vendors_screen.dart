import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/vendor_model.dart';
import '../../theme/theme.dart';
import '../../widgets/common/status_chip.dart';

class VendorsScreen extends StatefulWidget {
  const VendorsScreen({super.key});

  @override
  State<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends State<VendorsScreen> {
  final _db = Supabase.instance.client;
  List<Vendor> _vendors = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadVendors();
  }

  Future<void> _loadVendors() async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) { setState(() => _loading = false); return; }
      final rows = await _db
          .from('vendors')
          .select()
          .eq('landlord_id', uid)
          .order('name');
      final mapped = <Vendor>[];
      for (final r in rows) {
        try { mapped.add(_mapVendor(r)); } catch (_) {}
      }
      setState(() {
        _vendors = mapped;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
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

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final colors  = theme.extension<ElevoColors>()!;
    final vendors = _vendors;
    final fmt     = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => context.pop(),
        ),
        title: const Text('Vendors'),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.plus, color: colors.gold),
            onPressed: () {
              HapticFeedback.lightImpact();
              _showAddVendorSheetWithCallback(context);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          HapticFeedback.lightImpact();
          _showAddVendorSheetWithCallback(context);
        },
        child: const Icon(LucideIcons.plus),
      ),
      body: vendors.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.hardHat, size: 56, color: colors.gold),
                  const SizedBox(height: AppTheme.spacingMd),
                  Text('No vendors yet', style: TextStyle(color: colors.taupe)),
                ],
              ),
            )
          : ListView.separated(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        itemCount: vendors.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spacingSm),
        itemBuilder: (context, i) {
          final v = vendors[i];
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              context.go('/landlord/more/vendors/${v.id}');
            },
            behavior: HitTestBehavior.opaque,
            child: Opacity(
              opacity: v.isActive ? 1.0 : 0.5,
              child: Container(
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F3A5F),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(color: const Color(0xFFC9A227).withAlpha(80)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            v.name.isNotEmpty ? v.name : '(Unnamed Vendor)',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        StatusChip(label: v.category, color: const Color(0xFF7A5E28)),
                        const SizedBox(width: 4),
                        Icon(LucideIcons.chevronRight, color: const Color(0xFFC9A227), size: 16),
                      ],
                    ),
                    if (v.company.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(v.company, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                    ],
                    if (v.phone.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(LucideIcons.phone, size: 12, color: Color(0xFFC9A227)),
                          const SizedBox(width: 4),
                          Text(v.phone, style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFC9A227))),
                        ],
                      ),
                    ],
                    if (v.email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(LucideIcons.mail, size: 12, color: Colors.white.withAlpha(180)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              v.email,
                              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppTheme.spacingSm),
                    Row(
                      children: [
                        StatusChip(
                          label: v.spendLimit <= 0
                              ? 'No limit set'
                              : 'Up to ${fmt.format(v.spendLimit)}',
                        ),
                        const SizedBox(width: 8),
                        StatusChip(label: v.isActive ? 'Active' : 'Inactive'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAddVendorSheetWithCallback(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddVendorSheet(onSaved: _loadVendors),
    );
  }
}

// ── Add Vendor Bottom Sheet ─────────────────────────────────────────────────

class _AddVendorSheet extends StatefulWidget {
  final VoidCallback? onSaved;
  const _AddVendorSheet({this.onSaved});

  @override
  State<_AddVendorSheet> createState() => _AddVendorSheetState();
}

class _AddVendorSheetState extends State<_AddVendorSheet> {
  final _nameCtrl    = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _limitCtrl   = TextEditingController();
  String _category   = Vendor.categories.first;
  bool _isSaving     = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _companyCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppTheme.spacingMd,
          right: AppTheme.spacingMd,
          top: AppTheme.spacingLg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppTheme.spacingLg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
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
              Text('Add Vendor', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppTheme.spacingMd),

              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Contact Name *',
                  prefixIcon: Icon(LucideIcons.user, color: colors.taupe, size: 18),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),

              TextFormField(
                controller: _companyCtrl,
                decoration: InputDecoration(
                  labelText: 'Company Name',
                  prefixIcon: Icon(LucideIcons.building2, color: colors.taupe, size: 18),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),

              DropdownButtonFormField<String>(
                value: _category,
                decoration: InputDecoration(
                  labelText: 'Trade Category',
                  prefixIcon: Icon(LucideIcons.tag, color: colors.taupe, size: 18),
                ),
                dropdownColor: colors.card,
                items: Vendor.categories
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, style: theme.textTheme.bodyMedium),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _category = v ?? Vendor.categories.first),
              ),
              const SizedBox(height: AppTheme.spacingMd),

              TextFormField(
                controller: _phoneCtrl,
                decoration: InputDecoration(
                  labelText: 'Phone',
                  hintText: 'Phone number',
                  prefixIcon: Icon(LucideIcons.phone, color: colors.taupe, size: 18),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppTheme.spacingMd),

              TextFormField(
                controller: _emailCtrl,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(LucideIcons.mail, color: colors.taupe, size: 18),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: AppTheme.spacingMd),

              TextFormField(
                controller: _limitCtrl,
                decoration: InputDecoration(
                  labelText: 'Spend Limit (per job)',
                  prefixText: '\$',
                  prefixIcon: Icon(LucideIcons.dollarSign, color: colors.taupe, size: 18),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppTheme.spacingLg),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          if (_nameCtrl.text.trim().isEmpty) return;
                          HapticFeedback.lightImpact();
                          setState(() => _isSaving = true);
                          try {
                            final uid = Supabase.instance.client.auth.currentUser?.id;
                            if (uid != null) {
                              await Supabase.instance.client
                                  .from('vendors')
                                  .insert({
                                    'landlord_id': uid,
                                    'name': _nameCtrl.text.trim(),
                                    'company_name': _companyCtrl.text.trim().isEmpty ? null : _companyCtrl.text.trim(),
                                    'category': _category,
                                    'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
                                    'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
                                    'spend_limit': double.tryParse(_limitCtrl.text.trim()) ?? 0.0,
                                    'is_active': true,
                                  })
                                  .select()
                                  .single();
                            }
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              widget.onSaved?.call();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Vendor added!')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to add vendor: ${e.toString()}')),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _isSaving = false);
                          }
                        },
                  icon: _isSaving
                      ? SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(LucideIcons.save, size: 18, color: Colors.white),
                  label: Text(_isSaving ? 'Saving…' : 'Add Vendor'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
