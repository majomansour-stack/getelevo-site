import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/elevo_logic.dart';
import '../../models/property_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/notification_service.dart';
import '../../theme/theme.dart';
import 'package:provider/provider.dart';

class InviteTenantScreen extends StatefulWidget {
  /// Pre-select a unit when navigating from UnitDetailScreen.
  final String? preselectedUnitId;

  const InviteTenantScreen({super.key, this.preselectedUnitId});

  @override
  State<InviteTenantScreen> createState() => _InviteTenantScreenState();
}

class _InviteTenantScreenState extends State<InviteTenantScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _rentCtrl     = TextEditingController();

  String? _selectedUnitId;
  bool _isSending    = false;
  bool _sent         = false;
  bool _didAutoSelect = false;

  /// All vacant units across all properties — computed from the watched provider
  /// inside build() and passed in; do NOT call context.read here.
  List<Unit> _vacantUnitsFrom(DashboardProvider dash) =>
      dash.properties.expand((p) => p.units).where((u) => u.isVacant).toList();

  @override
  void initState() {
    super.initState();
    // Pre-selected unit from caller (e.g. UnitDetailScreen).
    _selectedUnitId = widget.preselectedUnitId;
  }

  /// Called every time DashboardProvider notifies. Once the first batch of
  /// properties arrives we auto-select the first vacant unit if nothing is
  /// already selected.
  void _maybeAutoSelect(List<Unit> vacantUnits) {
    if (_didAutoSelect) return;
    if (vacantUnits.isEmpty) return;
    final target = widget.preselectedUnitId ?? vacantUnits.first.id;
    final exists = vacantUnits.any((u) => u.id == target);
    if (!mounted) return;
    final id = exists ? target : vacantUnits.first.id;
    setState(() {
      _selectedUnitId = id;
      _didAutoSelect = true;
      _fillRent(vacantUnits, id);
    });
  }

  void _fillRent(List<Unit> units, String? id) {
    Unit? unit;
    for (final candidate in units) {
      if (candidate.id == id) unit = candidate;
    }
    _rentCtrl.text = unit != null && unit.rentAmount > 0
        ? unit.rentAmount.toStringAsFixed(2)
        : '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _rentCtrl.dispose();
    super.dispose();
  }

  String _unitLabel(Unit u) {
    final properties = context.read<DashboardProvider>().properties;
    final property = properties.cast<dynamic>().firstWhere(
      (p) => p.id == u.propertyId,
      orElse: () => null,
    );
    if (property == null) return 'Unit ${u.unitNumber}';
    return '${property.name} — Unit ${u.unitNumber}';
  }

  Future<void> _sendInvitation(List<Unit> vacantUnits) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedUnitId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a unit.')),
      );
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _isSending = true);

    final unit = vacantUnits.firstWhere((u) => u.id == _selectedUnitId);
    final unitLabel = _unitLabel(unit);

    final landlordName = context.read<AuthProvider>().currentUser?.fullName ?? 'Your Landlord';

    // Save the invited email first. The email function only sends to the
    // address stored on a unit this landlord owns.
    var savedOnUnit = false;
    try {
      final rent = parseMoneyAmount(_rentCtrl.text);
      await Supabase.instance.client
          .from('units')
          .update({
            'invited_email': _emailCtrl.text.toLowerCase().trim(),
            // The landlord's New Message list and chat headers read the
            // name from the unit. Without it the tenant shows as "Tenant"
            // and cannot be picked for a new conversation.
            if (_nameCtrl.text.trim().isNotEmpty)
              'tenant_name': _nameCtrl.text.trim(),
            if (rent != null) 'rent_amount': rent,
          })
          .eq('id', _selectedUnitId!);
      savedOnUnit = true;
    } catch (_) {}

    final emailed = savedOnUnit
        ? await NotificationService.sendTenantInvite(
            toEmail:      _emailCtrl.text.trim(),
            tenantName:   _nameCtrl.text.trim(),
            landlordName: landlordName,
            unitLabel:    unitLabel,
            unitId:       _selectedUnitId!,
          )
        : false;

    if (!mounted) return;
    if (!savedOnUnit) {
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save this invitation. Please try again.'),
        ),
      );
      return;
    }
    if (!emailed) {
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The unit is marked as invited, but the email could not be sent. '
            'Ask the tenant to create an account with this email address.',
          ),
        ),
      );
      return;
    }

    if (mounted) await context.read<DashboardProvider>().loadData();
    if (!mounted) return;
    setState(() { _isSending = false; _sent = true; });
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    // Watch the provider so the screen rebuilds automatically when data loads.
    final dash        = context.watch<DashboardProvider>();
    final vacantUnits = _vacantUnitsFrom(dash);

    // Auto-select the first unit once data arrives (runs during build, safe).
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoSelect(vacantUnits));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invite Tenant'),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => context.pop(),
        ),
      ),
      body: _sent
          ? _SuccessView(name: _nameCtrl.text)
          : _buildForm(theme, colors, dash, vacantUnits),
    );
  }

  Widget _buildForm(
    ThemeData theme,
    ElevoColors colors,
    DashboardProvider dash,
    List<Unit> vacantUnits,
  ) {
    // Ensure the currently selected unit still exists in the list
    // (guards against stale ID after a reload).
    final validSelection = vacantUnits.any((u) => u.id == _selectedUnitId)
        ? _selectedUnitId
        : (vacantUnits.isNotEmpty ? vacantUnits.first.id : null);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Explainer card
            Container(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              decoration: BoxDecoration(
                color: colors.gold.withAlpha(15),
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(color: colors.gold.withAlpha(60)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.info, color: colors.gold, size: 20),
                  const SizedBox(width: AppTheme.spacingMd),
                  Expanded(
                    child: Text(
                      'Your tenant will receive an email with a link to create their '
                      'Elevo account and connect to their unit. The tenant will be '
                      'automatically linked to the selected unit once they sign up.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.spacingLg),

            // Unit selector
            Text('Select Unit', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppTheme.spacingSm),

            if (dash.isLoading)
              // Show a loading indicator while properties are being fetched.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMd),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.gold,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingMd),
                    Text('Loading properties…', style: theme.textTheme.bodySmall),
                  ],
                ),
              )
            else if (vacantUnits.isEmpty)
              Container(
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                decoration: BoxDecoration(
                  color: colors.gold.withAlpha(12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(color: colors.gold.withAlpha(80)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.alertTriangle, color: colors.gold, size: 18),
                        const SizedBox(width: AppTheme.spacingSm),
                        Expanded(
                          child: Text(
                            'No vacant property is available.',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colors.midnight,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacingSm),
                    Text(
                      'You need to add a property and at least one vacant unit before '
                      'you can invite a tenant. Tap the button below to go to Properties.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingMd),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => context.go('/landlord/properties'),
                        icon: const Icon(LucideIcons.building2,
                            size: 16, color: Colors.white),
                        label: const Text('Go to Properties'),
                      ),
                    ),
                  ],
                ),
              )
            else
              DropdownButtonFormField<String>(
                value: validSelection,
                decoration: InputDecoration(
                  hintText: 'Choose a vacant unit',
                  prefixIcon: Icon(LucideIcons.home, color: colors.taupe, size: 18),
                ),
                items: vacantUnits.map((u) => DropdownMenuItem(
                  value: u.id,
                  child: Text(_unitLabel(u), style: theme.textTheme.bodyMedium),
                )).toList(),
                onChanged: (v) => setState(() {
                  _selectedUnitId = v;
                  _fillRent(vacantUnits, v);
                }),
              ),

            const SizedBox(height: AppTheme.spacingLg),
            Text('Tenant Information', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppTheme.spacingSm),

            // Full name
            TextFormField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'Full Name',
                hintText: 'Tenant\'s full name',
                prefixIcon: Icon(LucideIcons.user, color: colors.taupe, size: 18),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: AppTheme.spacingMd),

            // Email
            TextFormField(
              controller: _emailCtrl,
              decoration: InputDecoration(
                labelText: 'Email Address',
                hintText: 'tenant@email.com',
                prefixIcon: Icon(LucideIcons.mail, color: colors.taupe, size: 18),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Email is required';
                if (!v.contains('@')) return 'Enter a valid email address';
                return null;
              },
            ),
            const SizedBox(height: AppTheme.spacingMd),

            TextFormField(
              controller: _rentCtrl,
              decoration: const InputDecoration(
                labelText: 'Monthly rent *',
                hintText: '1,500.00',
                prefixText: '\$ ',
                helperText: 'Saved on this unit. You can change it later.',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) => validateMoneyField(value, requiredField: true),
            ),
            const SizedBox(height: AppTheme.spacingMd),

            // Phone (optional)
            TextFormField(
              controller: _phoneCtrl,
              decoration: InputDecoration(
                labelText: 'Phone (optional)',
                hintText: 'Phone number',
                prefixIcon: Icon(LucideIcons.phone, color: colors.taupe, size: 18),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: AppTheme.spacingXl),

            // Send button — enabled only when a unit is selected and not loading.
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (vacantUnits.isEmpty || validSelection == null || _isSending)
                    ? null
                    : () => _sendInvitation(vacantUnits),
                icon: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.send, size: 18, color: Colors.white),
                label: Text(_isSending ? 'Sending…' : 'Send Invitation'),
              ),
            ),
            const SizedBox(height: AppTheme.spacingMd),
            Center(
              child: Text(
                'An invitation email will be sent.\n'
                'The tenant pays no Elevo fee — only the landlord subscribes.',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall,
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  final String name;

  const _SuccessView({required this.name});

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.successGreen.withAlpha(30),
                border: Border.all(color: colors.successGreen, width: 2),
              ),
              child: Icon(LucideIcons.checkCircle, color: colors.successGreen, size: 40),
            ),
            const SizedBox(height: AppTheme.spacingLg),
            Text(
              'Invitation Sent!',
              style: theme.textTheme.headlineSmall?.copyWith(color: colors.successGreen),
            ),
            const SizedBox(height: AppTheme.spacingSm),
            Text(
              '$name will receive an email with a link to create their Elevo account '
              'and connect to their assigned unit.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.taupe),
            ),
            const SizedBox(height: AppTheme.spacingXl),
            ElevatedButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(LucideIcons.arrowLeft, size: 18, color: Colors.white),
              label: const Text('Back to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
