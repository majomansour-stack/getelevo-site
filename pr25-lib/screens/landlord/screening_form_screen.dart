import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/property_model.dart';
import '../../models/screening_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/rentspree_links.dart';
import '../../theme/theme.dart';
import '../../widgets/screening/rentspree_how_it_works.dart';
import '../../widgets/screening/screening_type_card.dart';

class ScreeningFormScreen extends StatefulWidget {
  const ScreeningFormScreen({super.key});

  @override
  State<ScreeningFormScreen> createState() => _ScreeningFormScreenState();
}

class _ScreeningFormScreenState extends State<ScreeningFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstCtrl = TextEditingController();
  final _lastCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();

  Property?        _selectedProperty;
  Unit?            _selectedUnit;
  bool             _isSubmitting = false;

  // Properties belonging to the current landlord
  List<Property> get _landlordProperties =>
      context.read<DashboardProvider>().properties;

  List<Unit> get _unitsForProperty =>
      _selectedProperty?.units ?? [];

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  // Saved landlord link, then RENTSPREE_INVITE_LINK, then the homepage.
  String? _resolvedRentspreeUrl;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final db  = Supabase.instance.client;
      final uid = db.auth.currentUser?.id;

      // ── 1. Insert screening record ──────────────────────────────────────────
      await db.from('tenant_screenings').insert({
        'landlord_id':     uid,
        'applicant_name':  '${_firstCtrl.text.trim()} ${_lastCtrl.text.trim()}',
        'applicant_first_name': _firstCtrl.text.trim(),
        'applicant_last_name': _lastCtrl.text.trim(),
        'applicant_email': _emailCtrl.text.trim(),
        if (_selectedProperty != null) 'property_id': _selectedProperty!.id,
        if (_selectedProperty != null) 'property_address': _selectedProperty!.address,
        if (_selectedUnit != null) 'unit_id': _selectedUnit!.id,
        if (_selectedUnit != null) 'unit_number': _selectedUnit!.unitNumber,
        'status':          'invited',
        'created_at':      DateTime.now().toIso8601String(),
      });

      final rentspreeUrl = await loadRentspreeLink(uid);

      // ── 3. Fetch landlord display name ─────────────────────────────────────
      String landlordName = 'Your landlord';
      try {
        final profileRow = await db
            .from('users')
            .select('full_name')
            .eq('id', uid!)
            .maybeSingle();
        final name = profileRow?['full_name'] as String?;
        if (name != null && name.trim().isNotEmpty) landlordName = name.trim();
      } catch (_) {}

      // ── 4. Show copy-link card ─────────────────────────────────────────────
      if (mounted) {
        setState(() => _resolvedRentspreeUrl = rentspreeUrl);
      }

      // ── 5. Send email via Edge Function ────────────────────────────────────
      bool emailOk = false;
      try {
        final response = await db.functions.invoke(
          'send-email',
          body: {
            'to':   _emailCtrl.text.trim(),
            'type': 'screening_invite',
            'data': {
              'tenantName':    '${_firstCtrl.text.trim()} ${_lastCtrl.text.trim()}',
              'landlordName':  landlordName,
              'unitLabel':     _selectedUnit?.unitNumber ??
                               _selectedProperty?.name ??
                               'the property',
              'rentspreeLink': rentspreeUrl,
            },
          },
        );

        final hasError = response.data is Map &&
            (response.data as Map).containsKey('error');
        emailOk = response.status < 300 && !hasError;
      } catch (emailErr) {
        emailOk = false;
      }

      if (mounted) {
        if (emailOk) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Screening request saved. Invitation email sent to applicant.'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 6),
              content: const Text(
                'Screening record saved, but the invitation email failed to send. '
                'Please copy the link below and send it to the applicant manually.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final properties = _landlordProperties;
    final savedLink = context.watch<AuthProvider>().currentUser?.rentspreeInviteLink;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_resolvedRentspreeUrl != null);
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => Navigator.of(context).pop(_resolvedRentspreeUrl != null),
        ),
        title: const Text('Request Screening'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RentSpreeHowItWorks(
                needsLink: savedLink == null || savedLink.trim().isEmpty,
              ),
              const SizedBox(height: AppTheme.spacingMd),

              // ── Applicant name ─────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'First Name *'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingMd),
                  Expanded(
                    child: TextFormField(
                      controller: _lastCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Last Name *'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppTheme.spacingMd),

              // ── Email ──────────────────────────────────────────────────
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Applicant Email Address *',
                  prefixIcon: Icon(LucideIcons.mail, size: 18, color: colors.sage),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                  if (!emailRegex.hasMatch(v.trim())) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),

              const SizedBox(height: AppTheme.spacingMd),

              // ── Property ───────────────────────────────────────────────
              DropdownButtonFormField<Property>(
                value: _selectedProperty,
                decoration: const InputDecoration(labelText: 'Property *'),
                items: properties
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p.name),
                        ))
                    .toList(),
                onChanged: (p) {
                  setState(() {
                    _selectedProperty = p;
                    _selectedUnit     = null;
                  });
                },
                validator: (v) => v == null ? 'Please select a property' : null,
              ),

              const SizedBox(height: AppTheme.spacingMd),

              // ── Unit ───────────────────────────────────────────────────
              DropdownButtonFormField<Unit>(
                value: _selectedUnit,
                decoration: const InputDecoration(labelText: 'Unit (optional)'),
                items: _unitsForProperty
                    .map((u) => DropdownMenuItem(
                          value: u,
                          child: Text('Unit ${u.unitNumber}'),
                        ))
                    .toList(),
                onChanged: _selectedProperty == null
                    ? null
                    : (u) => setState(() => _selectedUnit = u),
                hint: Text(
                  _selectedProperty == null
                      ? 'Select a property first'
                      : 'Select a unit (optional)',
                ),
              ),

              const SizedBox(height: AppTheme.spacingLg),

              // ── Screening type (Full Credit Report — only option) ───────
              Text(
                'Screening Package',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.midnight,
                ),
              ),
              const SizedBox(height: AppTheme.spacingSm),

              ScreeningTypeCard(
                type: ScreeningType.full,
                isSelected: true,
                onTap: () {},
              ),

              const SizedBox(height: AppTheme.spacingMd),

              // ── Note ───────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                decoration: BoxDecoration(
                  color: colors.gold.withAlpha(12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(color: colors.gold.withAlpha(45)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.info, size: 16, color: colors.gold),
                    const SizedBox(width: AppTheme.spacingSm),
                    Expanded(
                      child: Text(
                        'An invitation will be sent to the applicant with a secure '
                        'link to begin their RentSpree application.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.sage,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppTheme.spacingLg),

              // ── Send button ────────────────────────────────────────────
              OutlinedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send Screening Request'),
              ),

              const SizedBox(height: AppTheme.spacingLg),

              // ── Copy-link card — shown after submit as backup ──────────
              if (_resolvedRentspreeUrl != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  decoration: BoxDecoration(
                    color: colors.gold.withAlpha(18),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: colors.gold),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RentSpree Screening Link',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.midnight,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingXs),
                      Text(
                        'This link will be emailed to the applicant automatically. '
                        'Use the Copy button as a backup if needed.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.sage),
                      ),
                      const SizedBox(height: AppTheme.spacingSm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacingSm,
                          vertical: AppTheme.spacingXs,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusSmall),
                          border: Border.all(color: colors.stone),
                        ),
                        child: SelectableText(
                          _resolvedRentspreeUrl!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingSm),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: AppTheme.goldFillButton(colors, theme.textTheme),
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: _resolvedRentspreeUrl!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Link copied to clipboard.')),
                            );
                          },
                          icon: const Icon(LucideIcons.copy, size: 16),
                          label: const Text('Copy Link'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTheme.spacingMd),
              ],

              const SizedBox(height: AppTheme.spacingXl),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
