import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/billing_rules.dart';
import '../../core/elevo_logic.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/landlord_plan_gate.dart';
import '../../services/notification_service.dart';
import '../../services/push_notification_service.dart';
import '../../theme/theme.dart';

class AddEditUnitScreen extends StatefulWidget {
  final String propertyId;
  final String? unitId; // null = add new unit

  const AddEditUnitScreen({
    super.key,
    required this.propertyId,
    this.unitId,
  });

  @override
  State<AddEditUnitScreen> createState() => _AddEditUnitScreenState();
}

class _AddEditUnitScreenState extends State<AddEditUnitScreen> {
  final _formKey              = GlobalKey<FormState>();
  final _unitNumCtrl          = TextEditingController();
  final _rentCtrl             = TextEditingController();
  final _depositCtrl          = TextEditingController();
  final _additionalDepositCtrl = TextEditingController();

  DateTime? _leaseStart;
  DateTime? _leaseEnd;
  String _status = 'vacant';
  String _bedrooms = '';
  String _bathrooms = '';
  String? _tenantId;
  String _tenantName = '';
  bool _isSaving = false;
  bool _loadingExisting = false;
  String? _loadError;

  final _db = Supabase.instance.client;
  bool get _isEditing => widget.unitId != null;
  final _dateFmt = DateFormat('MMMM d, y');

  static const _statusOptions = unitStatusOptions;

  List<String> get _bedroomChoices {
    final choices = <String>['', for (var n = 0; n <= 20; n++) '$n'];
    if (_bedrooms.isNotEmpty && !choices.contains(_bedrooms)) {
      choices.add(_bedrooms);
    }
    return choices;
  }

  List<String> get _bathroomChoices {
    final choices = <String>[
      '',
      for (var halves = 0; halves <= 40; halves++) formatBathrooms(halves / 2),
    ];
    if (_bathrooms.isNotEmpty && !choices.contains(_bathrooms)) {
      choices.add(_bathrooms);
    }
    return choices;
  }

  String _moneyText(double amount) {
    if (amount == amount.roundToDouble()) return amount.toStringAsFixed(0);
    return amount.toStringAsFixed(2);
  }

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _loadExisting();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) landlordCreateAllowed(context, LandlordCreateKind.unit);
      });
    }
  }

  Future<void> _loadExisting() async {
    setState(() {
      _loadingExisting = true;
      _loadError = null;
    });
    try {
      final row = await _db
          .from('units')
          .select()
          .eq('id', widget.unitId!)
          .maybeSingle();
      if (row == null) throw Exception('Unit not found');
      _unitNumCtrl.text = row['unit_number']?.toString() ?? '';
      final rent = parseMoneyAmount(row['rent_amount']);
      if (rent != null && rent > 0) _rentCtrl.text = _moneyText(rent);
      final deposit = parseMoneyAmount(row['deposit_amount']);
      if (deposit != null) _depositCtrl.text = _moneyText(deposit);
      final extra = parseMoneyAmount(row['additional_deposit']);
      if (extra != null) _additionalDepositCtrl.text = _moneyText(extra);
      final status = (row['status'] as String?) ?? 'vacant';
      _status = isKnownUnitStatus(status) ? status : 'vacant';
      final bedrooms = parseBedrooms(row['bedrooms']);
      _bedrooms = bedrooms == null ? '' : '$bedrooms';
      final bathrooms = parseBathrooms(row['bathrooms']);
      _bathrooms = bathrooms == null ? '' : formatBathrooms(bathrooms);
      _leaseStart = parseDateColumn(row['lease_start']);
      _leaseEnd = parseDateColumn(row['lease_end']);
      final tenant = row['tenant_id']?.toString().trim() ?? '';
      _tenantId = tenant.isEmpty ? null : tenant;
      _tenantName = row['tenant_name']?.toString().trim() ?? '';
    } catch (_) {
      _loadError = 'Could not load this unit. Nothing was changed.';
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  @override
  void dispose() {
    _unitNumCtrl.dispose();
    _rentCtrl.dispose();
    _depositCtrl.dispose();
    _additionalDepositCtrl.dispose();
    super.dispose();
  }

  Future<void> _notifyRentChange({
    required String unitId,
    required double previousRent,
    required double newRent,
    required String landlordId,
  }) async {
    try {
      final mFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

      // Look up the tenant assigned to this unit
      final unitRow = await _db
          .from('units')
          .select('tenant_id, unit_number, properties(address)')
          .eq('id', unitId)
          .maybeSingle();
      if (unitRow == null) return;

      final tenantId = unitRow['tenant_id'] as String?;
      if (tenantId == null) return;

      final unitNum  = unitRow['unit_number'] as String? ?? '';
      final prop     = unitRow['properties'];
      final address  = (prop is Map ? prop['address'] as String? : null) ?? 'your unit';
      final unitLabel = '$address Unit $unitNum'.trim();

      final tenantRow = await _db
          .from('users')
          .select('email, full_name')
          .eq('id', tenantId)
          .maybeSingle();
      if (tenantRow == null) return;

      final tenantEmail = tenantRow['email'] as String?;
      final tenantName  = (tenantRow['full_name'] as String?) ?? 'Tenant';

      final prevStr = mFmt.format(previousRent);
      final newStr  = mFmt.format(newRent);

      // Record in rent_history
      try {
        await _db.from('rent_history').insert({
          'unit_id':         unitId,
          'previous_amount': previousRent,
          'new_amount':      newRent,
          'changed_by':      landlordId,
          'changed_at':      DateTime.now().toIso8601String(),
        }).select();
      } catch (_) {}

      // Push notification to tenant
      await PushNotificationService.sendToUser(
        userId: tenantId,
        title: 'Rent Update',
        body:  'Rent Update for $unitLabel \u2014 Your rent has been updated from $prevStr to $newStr effective on your next payment date.',
        data:  {'type': 'rent_increase'},
      );

      // Email via Resend
      if (tenantEmail != null) {
        await NotificationService.sendRentIncrease(
          toEmail:        tenantEmail,
          tenantName:     tenantName,
          unitLabel:      unitLabel,
          previousAmount: prevStr,
          newAmount:      newStr,
          unitId:         unitId,
        );
      }
    } catch (_) {
      // Non-fatal — notification failure should not block save
    }
  }

  Future<void> _pickDate(bool isStart) async {
    HapticFeedback.lightImpact();
    final initial = isStart ? (_leaseStart ?? DateTime.now()) : (_leaseEnd ?? DateTime.now().add(const Duration(days: 365)));
    final first   = isStart ? DateTime(1990) : (_leaseStart ?? DateTime(1990));
    final last    = DateTime(2100);
    var initialDate = initial;
    if (initialDate.isBefore(first)) initialDate = first;
    if (initialDate.isAfter(last)) initialDate = last;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: first,
      lastDate: last,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _leaseStart = picked;
          // Auto-push end date if it's before start
          if (_leaseEnd != null && _leaseEnd!.isBefore(picked)) _leaseEnd = null;
        } else {
          _leaseEnd = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_isEditing && _loadError != null) return;
    if (!_formKey.currentState!.validate()) return;
    final leaseError = validateLeaseDates(_leaseStart, _leaseEnd);
    if (leaseError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(leaseError)));
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _isSaving = true);

    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) throw Exception('Not signed in');

      final rent = parseMoneyAmount(_rentCtrl.text) ?? 0;
      final deposit = parseMoneyAmount(_depositCtrl.text) ?? 0;
      final additional = parseMoneyAmount(_additionalDepositCtrl.text) ?? 0;

      final payload = unitWritePayload(
        propertyId: widget.propertyId,
        landlordId: uid,
        unitNumber: _unitNumCtrl.text,
        status: _status,
        rentAmount: rent,
        depositAmount: deposit,
        additionalDeposit: additional,
        leaseStart: _leaseStart,
        leaseEnd: _leaseEnd,
        bedrooms: parseBedrooms(_bedrooms),
        bathrooms: parseBathrooms(_bathrooms),
      );

      if (_isEditing) {
        // Detect rent change before saving
        double? previousRent;
        try {
          final existing = await _db
              .from('units')
              .select('rent_amount, tenant_id, unit_number')
              .eq('id', widget.unitId!)
              .maybeSingle();
          if (existing != null) {
            previousRent = ((existing['rent_amount'] as num?) ?? 0).toDouble();
          }
        } catch (_) {}

        final updated = await _db
            .from('units')
            .update(payload)
            .eq('id', widget.unitId!)
            .select('id');
        if (List<dynamic>.from(updated as List).isEmpty) {
          throw Exception('Nothing was saved.');
        }

        // Fire rent increase notification if rent changed
        if (previousRent != null && rent != previousRent) {
          _notifyRentChange(
            unitId: widget.unitId!,
            previousRent: previousRent,
            newRent: rent,
            landlordId: uid,
          );
        }
      } else {
        final inserted = await _db.from('units').insert(payload).select('id');
        if (List<dynamic>.from(inserted as List).isEmpty) {
          throw Exception('Nothing was saved.');
        }
      }

      if (mounted) {
        await context.read<DashboardProvider>().loadData();
      }
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEditing ? 'Unit updated.' : 'Unit added!')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _isSaving = false);
      if (!mounted) return;
      if (!_isEditing && openSubscriptionForPlanError(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save unit. Please try again.'),
        ),
      );
    }
  }

  Future<void> _confirmMoveOut() async {
    final unitId = widget.unitId;
    final tenantId = _tenantId;
    if (unitId == null || tenantId == null || tenantId.isEmpty) return;
    final who = _tenantName.isEmpty ? 'this tenant' : _tenantName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move tenant out?'),
        content: Text(
          'Move $who out of this unit? Their tenancy ends. They can still '
          'read messages from before they left, and they can no longer post '
          'in open job chats.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Move out')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isSaving = true);
    try {
      final removed = await _db
          .from('units')
          .update(unitMoveOutUpdate())
          .eq('id', unitId)
          .eq('tenant_id', tenantId)
          .select('id');
      if (List<dynamic>.from(removed as List).isEmpty) {
        throw Exception('Nothing was changed.');
      }
      if (!mounted) return;
      setState(() {
        _tenantId = null;
        _tenantName = '';
        _status = 'vacant';
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tenant moved out.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not move this tenant out.')),
      );
    }
  }

  Future<bool> _tableHasUnitRow(String table, String unitId) async {
    final rows = await _db.from(table).select('id').eq('unit_id', unitId).limit(1);
    return List<dynamic>.from(rows as List).isNotEmpty;
  }

  Future<int> _unitRowCount(String table, String unitId) async {
    final rows = await _db.from(table).select('id').eq('unit_id', unitId);
    return List<dynamic>.from(rows as List).length;
  }

  /// Other records are only a warning. A missing table must not block delete.
  Future<bool> _optionalUnitRow(String table, String unitId) async {
    try {
      return await _tableHasUnitRow(table, unitId);
    } catch (_) {
      return false;
    }
  }

  Future<void> _confirmDelete() async {
    final unitId = widget.unitId;
    final uid = _db.auth.currentUser?.id;
    if (unitId == null || uid == null) return;
    final colors = Theme.of(context).extension<ElevoColors>()!;

    late UnitDeleteDecision decision;
    try {
      final row = await _db
          .from('units')
          .select('status, tenant_id, unit_number')
          .eq('id', unitId)
          .maybeSingle();
      if (row == null) {
        throw Exception('This unit could not be found.');
      }
      final hasMessages = await _tableHasUnitRow('messages', unitId);
      final hasPayments = await _tableHasUnitRow('payments', unitId);
      final hasMaintenance = await _optionalUnitRow('maintenance_requests', unitId);
      final hasRentHistory = await _optionalUnitRow('rent_history', unitId);
      final documents = await _unitRowCount('documents', unitId);
      final photoLogs = await _unitRowCount('photo_logs', unitId);
      final calendarEvents = await _unitRowCount('calendar_events', unitId);
      final screenings = await _unitRowCount('tenant_screenings', unitId);
      decision = decideUnitDelete(
        status: (row['status'] as String?) ?? _status,
        tenantId: row['tenant_id']?.toString(),
        hasMessages: hasMessages,
        hasPayments: hasPayments,
        hasMaintenance: hasMaintenance,
        hasRentHistory: hasRentHistory,
      );
      final history = historyBlocksDeleteMessage(
        subject: 'unit',
        documents: documents,
        photoLogs: photoLogs,
        calendarEvents: calendarEvents,
        screenings: screenings,
      );
      if (history != null && decision.allowed) {
        decision = UnitDeleteDecision(allowed: false, blockReason: history);
      }
    } catch (_) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unit not deleted'),
          content: const Text(
            'The messages and payment records on this unit could not be checked, so the unit was left in place.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    if (!decision.allowed) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unit not deleted'),
          content: Text(decision.blockReason ?? 'This unit cannot be deleted.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete unit'),
        content: Text(unitDeleteConfirmation(
          unitNumber: _unitNumCtrl.text,
          warnings: decision.warnings,
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: colors.urgentRed)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final removed = await _db
          .from('units')
          .delete()
          .eq('id', unitId)
          .eq('landlord_id', uid)
          .select('id');
      if (List<dynamic>.from(removed as List).isEmpty) {
        throw Exception('Nothing was removed.');
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      await context.read<DashboardProvider>().loadData();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Unit deleted.')));
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This unit is still linked to other records, so it was not removed.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    if (_loadingExisting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Unit')),
        body: Center(child: Text(_loadError!)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Unit' : 'Add Unit'),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Delete unit',
              icon: Icon(LucideIcons.trash2, color: colors.urgentRed),
              onPressed: _isSaving ? null : _confirmDelete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Unit Details', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppTheme.spacingMd),

              // Unit number — optional (single-family homes may not have one)
              TextFormField(
                controller: _unitNumCtrl,
                decoration: InputDecoration(
                  labelText: 'Unit Number — Optional',
                  hintText: '101 or A or 2B',
                  prefixIcon: Icon(LucideIcons.hash, color: colors.taupe, size: 18),
                  helperText: 'Leave blank for single-family homes',
                  helperStyle: TextStyle(color: colors.taupe, fontSize: 11),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),

              DropdownButtonFormField<String>(
                value: _bedroomChoices.contains(_bedrooms) ? _bedrooms : '',
                decoration: InputDecoration(
                  labelText: 'Bedrooms',
                  prefixIcon: Icon(LucideIcons.bedDouble, color: colors.taupe, size: 18),
                  helperText: 'Optional. 0 is a studio.',
                ),
                items: [
                  for (final choice in _bedroomChoices)
                    DropdownMenuItem(
                      value: choice,
                      child: Text(choice.isEmpty
                          ? 'Not set'
                          : choice == '0'
                              ? '0 (Studio)'
                              : choice),
                    ),
                ],
                onChanged: (value) => setState(() => _bedrooms = value ?? ''),
              ),
              const SizedBox(height: AppTheme.spacingMd),

              DropdownButtonFormField<String>(
                value: _bathroomChoices.contains(_bathrooms) ? _bathrooms : '',
                decoration: InputDecoration(
                  labelText: 'Bathrooms',
                  prefixIcon: Icon(LucideIcons.bath, color: colors.taupe, size: 18),
                  helperText: 'Optional. Half baths are allowed, such as 1.5.',
                ),
                items: [
                  for (final choice in _bathroomChoices)
                    DropdownMenuItem(
                      value: choice,
                      child: Text(choice.isEmpty ? 'Not set' : choice),
                    ),
                ],
                onChanged: (value) => setState(() => _bathrooms = value ?? ''),
              ),
              const SizedBox(height: AppTheme.spacingMd),

              // Status dropdown
              DropdownButtonFormField<String>(
                value: _status,
                decoration: InputDecoration(
                  labelText: 'Status',
                  prefixIcon: Icon(LucideIcons.tag, color: colors.taupe, size: 18),
                ),
                dropdownColor: colors.card,
                items: _statusOptions.map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(
                    s[0].toUpperCase() + s.substring(1),
                    style: theme.textTheme.bodyMedium,
                  ),
                )).toList(),
                onChanged: (v) => setState(() => _status = v ?? 'vacant'),
              ),
              if (_tenantId != null) ...[
                const SizedBox(height: AppTheme.spacingMd),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isSaving ? null : _confirmMoveOut,
                    icon: Icon(LucideIcons.userMinus, color: colors.urgentRed, size: 18),
                    label: Text(
                      _tenantName.isEmpty ? 'Move tenant out' : 'Move $_tenantName out',
                      style: TextStyle(color: colors.urgentRed),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppTheme.spacingLg),

              Text('Financial Details', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppTheme.spacingMd),

              // Rent amount
              TextFormField(
                controller: _rentCtrl,
                decoration: InputDecoration(
                  labelText: 'Monthly Rent *',
                  hintText: '1,500.00',
                  prefixIcon: Icon(LucideIcons.dollarSign, color: colors.taupe, size: 18),
                  prefixText: '\$',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                validator: (v) => validateMoneyField(v, requiredField: true),
              ),
              const SizedBox(height: AppTheme.spacingMd),

              // Security deposit
              TextFormField(
                controller: _depositCtrl,
                decoration: InputDecoration(
                  labelText: 'Security Deposit',
                  hintText: '1,500.00',
                  prefixIcon: Icon(LucideIcons.shield, color: colors.taupe, size: 18),
                  prefixText: '\$',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                validator: (v) => validateMoneyField(v, requiredField: false),
              ),
              const SizedBox(height: AppTheme.spacingMd),

              // Additional deposit (pet deposit, key deposit, etc.)
              TextFormField(
                controller: _additionalDepositCtrl,
                decoration: InputDecoration(
                  labelText: 'Additional Deposit',
                  hintText: 'e.g. pet deposit, key deposit',
                  helperText: 'Optional — enter any deposit collected beyond the security deposit',
                  helperMaxLines: 2,
                  prefixIcon: Icon(LucideIcons.badgeDollarSign, color: colors.taupe, size: 18),
                  prefixText: '\$',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                validator: (v) => validateMoneyField(v, requiredField: false),
              ),
              const SizedBox(height: AppTheme.spacingLg),

              Text('Lease Dates', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppTheme.spacingMd),

              // Lease start
              _DatePickerTile(
                label: 'Lease Start Date',
                date: _leaseStart,
                icon: LucideIcons.calendarPlus,
                dateFmt: _dateFmt,
                onTap: () => _pickDate(true),
                onClear: _leaseStart == null
                    ? null
                    : () => setState(() => _leaseStart = null),
              ),
              const SizedBox(height: AppTheme.spacingMd),

              // Lease end
              _DatePickerTile(
                label: 'Lease End Date',
                date: _leaseEnd,
                icon: LucideIcons.calendarX,
                dateFmt: _dateFmt,
                onTap: () => _pickDate(false),
                onClear: _leaseEnd == null
                    ? null
                    : () => setState(() => _leaseEnd = null),
              ),

              // Lease duration hint
              if (_leaseStart != null && _leaseEnd != null) ...[
                const SizedBox(height: AppTheme.spacingSm),
                Center(
                  child: Text(
                    '${_leaseEnd!.difference(_leaseStart!).inDays} days '
                    '(${(_leaseEnd!.difference(_leaseStart!).inDays / 30.44).toStringAsFixed(1)} months)',
                    style: theme.textTheme.labelSmall?.copyWith(color: colors.goldInk),
                  ),
                ),
              ],

              const SizedBox(height: AppTheme.spacingXl),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(LucideIcons.save, size: 18, color: Colors.white),
                  label: Text(_isSaving
                      ? 'Saving…'
                      : _isEditing ? 'Update Unit' : 'Add Unit'),
                ),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final IconData icon;
  final DateFormat dateFmt;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DatePickerTile({
    required this.label,
    required this.date,
    required this.icon,
    required this.dateFmt,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(
            color: date != null ? colors.gold.withAlpha(80) : colors.taupe.withAlpha(60),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: date != null ? colors.gold : colors.taupe, size: 18),
            const SizedBox(width: AppTheme.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  if (date != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      dateFmt.format(date!),
                      style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink),
                    ),
                  ],
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                tooltip: 'Clear date',
                onPressed: onClear,
                icon: Icon(LucideIcons.x, color: colors.taupe, size: 16),
              )
            else
              Icon(
                LucideIcons.chevronRight,
                color: colors.taupe,
                size: 16,
              ),
          ],
        ),
      ),
    );
  }
}
