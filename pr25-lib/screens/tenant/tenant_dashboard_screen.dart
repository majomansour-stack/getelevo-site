import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/elevo_logic.dart';
import '../../models/property_model.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/payments/rent_payment_instructions.dart';
import '../../providers/messages_provider.dart';
import '../../services/landlord_contact.dart';
import '../../services/notification_service.dart';
import '../../services/push_notification_service.dart';
import '../../theme/theme.dart';

class TenantDashboardScreen extends StatefulWidget {
  const TenantDashboardScreen({super.key});

  @override
  State<TenantDashboardScreen> createState() => _TenantDashboardScreenState();
}

class _TenantDashboardScreenState extends State<TenantDashboardScreen> {
  final _db = Supabase.instance.client;
  Unit? _unit;
  String _propertyName = '';
  String _propertyAddress = '';
  String _landlordName = 'Your Landlord';
  String? _landlordId;
  List<LandlordPaymentMethod> _paymentMethods = [];
  bool _loadingPayments = false;
  bool _savingRent = false;
  bool _hasPendingRent = false;
  bool _rentConfirmed = false;
  DateTime? _noticeMonth;
  bool _hasLeaseDocument = false;
  int _historyRevision = 0;
  bool _loadingUnit = true;
  String? _loadError;
  // Prevents _maybeInjectWelcome from firing more than once within a single
  // screen session. The authoritative cross-login gate lives in
  // MessagesProvider.injectWelcomeMessage which re-reads welcome_message_sent
  // directly from Supabase before inserting.
  bool _welcomeInjected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadTenantUnit();
      _maybeInjectWelcome();
      // If unit is still null, keep the spinner showing and silently retry
      // up to 5 times (one every 2 seconds = 10 seconds total). This handles
      // the race where _linkTenantToUnit at login hasn't finished writing
      // tenant_id before initState fires, without showing any "pending" banner.
      if (_unit == null && mounted) {
        setState(() => _loadingUnit = true);
        for (int i = 0; i < 5; i++) {
          await Future.delayed(const Duration(seconds: 2));
          if (!mounted) return;
          await _loadTenantUnit();
          if (_unit != null) {
            _maybeInjectWelcome();
            return;
          }
        }
        // All retries exhausted — stop spinner so the tenant can see the app.
        if (mounted) setState(() => _loadingUnit = false);
      }
    });
  }

  Future<void> _loadTenantUnit() async {
    try {
      final uid   = _db.auth.currentUser?.id;
      final email = _db.auth.currentUser?.email?.toLowerCase().trim();
      if (uid == null) { setState(() => _loadingUnit = false); return; }

      // ── Fallback 1: unit already linked to this tenant by auth ID ─────────
      var rows = await _db
          .from('units')
          .select('*, properties(name, address, landlord_id)')
          .eq('tenant_id', uid)
          .limit(1);

      // ── Fallback 2: unit linked via invitation email ──────────────────────
      // Handles tenants whose tenant_id was never written (invited before the
      // auto-link flow existed, or the login-time link failed silently).
      if (rows.isEmpty && email != null) {
        final emailRows = await _db
            .from('units')
            .select('*, properties(name, address, landlord_id)')
            .eq('invited_email', email)
            .limit(1);

        if (emailRows.isNotEmpty) {
          final unitId = emailRows.first['id'] as String?;
          if (unitId != null) {
            // Self-heal: write tenant_id and mark occupied so future loads
            // always use Fallback 1 and the landlord sees the unit as taken.
            try {
              await _db.from('units').update({
                'tenant_id': uid,
                'status':    'occupied',
              }).eq('id', unitId);
            } catch (_) {}
          }
          // Use the rows returned from the email lookup (already fully joined).
          rows = emailRows;
        }
      }

      // ── Fallback 3: no unit found — show pending welcome state ────────────
      if (rows.isEmpty) {
        if (mounted) setState(() => _loadingUnit = false);
        return;
      }

      final r = rows.first;
      final propData = r['properties'] as Map<String, dynamic>?;

      // Ensure status is always occupied when we have a linked unit.
      final currentStatus = r['status'] as String?;
      if (currentStatus != 'occupied') {
        try {
          await _db.from('units').update({'status': 'occupied'})
              .eq('id', r['id'] as String);
        } catch (_) {}
      }

      // The unit's landlord is who the tenant pays. The property landlord
      // is only used when the unit row itself has no landlord id.
      String landlordName = 'Your Landlord';
      final landlordId = landlordIdForTenantPaymentMethods(
        unitLandlordId: r['landlord_id'] as String?,
        propertyLandlordId: propData?['landlord_id'] as String?,
      );
      if (landlordId != null) {
        final contact = await fetchLandlordContact(_db, landlordId);
        final name = contact?['full_name'] as String?;
        if (name != null && name.trim().isNotEmpty) landlordName = name;
      }

      final unit = Unit(
        id: r['id'] as String,
        propertyId: r['property_id'] as String,
        landlordId: landlordId ?? '',
        unitNumber: r['unit_number'] as String,
        tenantId: uid,
        rentAmount: ((r['rent_amount'] as num?) ?? 0).toDouble(),
        bedrooms: parseBedrooms(r['bedrooms']),
        bathrooms: parseBathrooms(r['bathrooms']),
        leaseStart: r['lease_start'] != null
            ? DateTime.parse(r['lease_start'] as String)
            : null,
        leaseEnd: r['lease_end'] != null
            ? DateTime.parse(r['lease_end'] as String)
            : null,
        status: 'occupied',
        createdAt: DateTime.parse(r['created_at'] as String),
        rentDueDay: parseRentDueDay(r['rent_due_day']),
      );

      if (mounted) {
        setState(() {
          _unit = unit;
          _propertyName = (propData?['name'] as String?) ?? '';
          _propertyAddress = (propData?['address'] as String?) ?? '';
          _landlordName = landlordName;
          _landlordId = landlordId;
          _loadingUnit = false;
        });
        await _loadPaymentMethods(landlordId);
        await _loadPendingRent(unit.id);
        await _loadLeaseDocument(unit.id);
      }
    } catch (e) {
      if (mounted) setState(() {
        _loadingUnit = false;
        _loadError = e.toString();
      });
    }
  }

  void _maybeInjectWelcome() {
    if (!mounted) return;
    // Local session guard — prevents multiple calls within the same screen
    // lifecycle (e.g. from the retry loop) from triggering a second injection.
    if (_welcomeInjected) return;
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    // In-memory fast-path: if the auth user already knows the message was sent,
    // skip without touching the DB.
    if (user == null || !user.isTenant || user.welcomeMessageSent) return;
    if (_unit == null) return;

    // Mark the local guard immediately (synchronous) so concurrent retry calls
    // cannot pass this point a second time.
    _welcomeInjected = true;

    final address = '$_propertyAddress #${_unit!.unitNumber}';
    final msgsProvider = context.read<MessagesProvider>();

    // injectWelcomeMessage re-reads welcome_message_sent from Supabase as the
    // authoritative gate before inserting, so a stale in-memory flag cannot
    // cause a duplicate message across logins.
    msgsProvider.loadChatMessages(_unit!.id).then((_) {
      msgsProvider.injectWelcomeMessage(
        unitId: _unit!.id,
        propertyAddress: address,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser!;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final dateFmt = DateFormat('MMMM d, y');

    if (_loadingUnit) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final unit = _unit;

    final now = DateTime.now();
    final dueDay = unit?.rentDueDay;
    final shownDue = _noticeMonth == null
        ? nextRentDueDate(now, dueDay: dueDay)
        : dueDateInMonth(_noticeMonth!, dueDay: dueDay);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Text(
                    'Elevo',
                    style: AppTheme.serif(
                      theme.textTheme.titleLarge,
                      color: colors.ink,
                      fontSize: 28,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => context.push('/tenant/more/notifications'),
                    child: Icon(LucideIcons.bell, color: colors.ink, size: 22),
                  ),
                  const SizedBox(width: AppTheme.spacingXs),
                  GestureDetector(
                    onTap: () => context.push('/tenant/more'),
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.oliveTint,
                        border: Border.all(color: colors.linkOlive),
                      ),
                      child: Center(
                        child: Text(
                          user.fullName.isNotEmpty ? user.fullName[0] : 'T',
                          style: TextStyle(
                            color: colors.linkOlive,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingLg),

              // Hero unit card — or minimal notice when unit not yet linked
              if (unit == null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppTheme.spacingLg),
                  decoration: AppTheme.surfaceCard(colors),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome to ELEVO',
                        style: theme.textTheme.headlineSmall?.copyWith(color: colors.ink),
                      ),
                      const SizedBox(height: 4),
                      if (_loadError != null) ...[
                        Text(
                          'Error loading unit: $_loadError',
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.urgentRed),
                        ),
                        const SizedBox(height: 8),
                      ] else ...[
                        Text(
                          'Your account is being linked to your unit automatically. This usually takes just a moment.',
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.sage),
                        ),
                        const SizedBox(height: 8),
                      ],
                      GestureDetector(
                        onTap: () async {
                          setState(() { _loadingUnit = true; _loadError = null; });
                          await _loadTenantUnit();
                          if (_unit != null) _maybeInjectWelcome();
                        },
                        child: Text(
                          'Tap to retry',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.linkOlive,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppTheme.spacingLg),
                decoration: AppTheme.surfaceCard(colors),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_propertyAddress #${unit.unitNumber}',
                      style: theme.textTheme.headlineSmall?.copyWith(color: colors.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _propertyName,
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.sage),
                    ),
                    if (unitSizeLabel(
                          bedrooms: unit.bedrooms,
                          bathrooms: unit.bathrooms,
                        ) !=
                        null) ...[
                      const SizedBox(height: 4),
                      Text(
                        unitSizeLabel(
                          bedrooms: unit.bedrooms,
                          bathrooms: unit.bathrooms,
                        )!,
                        style: theme.textTheme.bodySmall?.copyWith(color: colors.linkOlive),
                      ),
                    ],
                    const SizedBox(height: AppTheme.spacingSm),
                    Row(
                      children: [
                        Container(
                          width: 24, height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.oliveTint,
                          ),
                          child: Center(
                            child: Text(
                              _landlordName.isNotEmpty ? _landlordName[0].toUpperCase() : 'L',
                              style: TextStyle(color: colors.linkOlive, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacingSm),
                        Text(
                          _landlordName,
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.sage),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppTheme.spacingMd),

              // Rent card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppTheme.spacingLg),
                decoration: BoxDecoration(
                  color: colors.olive,
                  borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                  boxShadow: AppTheme.cardShadow(colors),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rent',
                      style: theme.textTheme.titleSmall?.copyWith(color: colors.onOlive.withAlpha(190)),
                    ),
                    const SizedBox(height: AppTheme.spacingSm),
                    Text(
                      fmt.format(unit.rentAmount),
                      style: AppTheme.serif(
                        theme.textTheme.headlineMedium,
                        color: colors.onOlive,
                        fontSize: 40,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingXs),
                    Row(
                      children: [
                        Text(
                          dateOnly(shownDue) == dateOnly(now)
                              ? 'Due today'
                              : 'Due ${dateFmt.format(shownDue)}',
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.onOlive.withAlpha(190)),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colors.onOlive.withAlpha(28),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            rentCountdownUntil(now, shownDue),
                            style: TextStyle(color: colors.onOlive, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacingMd),
                    RentPaymentInstructions(
                      methods: _paymentMethods,
                      loading: _loadingPayments,
                      onMarkPaid: (_savingRent || _hasPendingRent) ? null : _markRentPaid,
                      saving: _savingRent,
                      alreadyPending: _hasPendingRent,
                      alreadyConfirmed: _rentConfirmed,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppTheme.spacingMd),

              if (leaseDatesAreSet(unit.leaseStart, unit.leaseEnd))
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                decoration: AppTheme.surfaceCard(colors),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: unit.leaseProgress,
                            strokeWidth: 4,
                            backgroundColor: colors.taupe.withAlpha(40),
                            valueColor: AlwaysStoppedAnimation(colors.linkOlive),
                          ),
                          Text(
                            '${(unit.leaseProgress * 100).toInt()}%',
                            style: TextStyle(color: colors.linkOlive, fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lease Progress',
                            style: theme.textTheme.titleSmall?.copyWith(color: colors.ink),
                          ),
                          const SizedBox(height: 4),
                          if (unit.leaseEnd != null)
                            Text(
                              'Ends ${dateFmt.format(unit.leaseEnd!)}',
                              style: theme.textTheme.bodySmall?.copyWith(color: colors.sage),
                            ),
                          Text(
                            unit.daysRemaining < 0
                                ? 'Lease ended'
                                : '${unit.daysRemaining} days remaining',
                            style: TextStyle(color: colors.linkOlive, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  decoration: AppTheme.surfaceCard(colors),
                  child: Text(
                    'Lease dates not set',
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink),
                  ),
                ),

              const SizedBox(height: AppTheme.spacingLg),

              // Quick actions
              Text('Quick Actions', style: theme.textTheme.titleLarge?.copyWith(fontSize: 22)),
              const SizedBox(height: AppTheme.spacingSm),
              Row(
                children: [
                  _QuickAction(
                    icon: LucideIcons.messageCircle,
                    label: 'Message',
                    onTap: () => context.go('/tenant/messages'),
                  ),
                  _QuickAction(
                    icon: LucideIcons.wrench,
                    label: 'Request',
                    onTap: () => context.go('/tenant/maintenance'),
                  ),
                  _QuickAction(
                    icon: LucideIcons.fileText,
                    label: 'Documents',
                    onTap: () => context.go('/tenant/more/documents'),
                  ),
                  _QuickAction(
                    icon: LucideIcons.camera,
                    label: 'Photos',
                    onTap: () => context.go('/tenant/more/photos'),
                  ),
                ],
              ),

              const SizedBox(height: AppTheme.spacingLg),

              // ── View My Lease shortcut ──────────────────────────────────
              GestureDetector(
                onTap: () => context.push('/tenant/more/documents'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  decoration: AppTheme.surfaceCard(colors),
                  child: Row(
                    children: [
                      Icon(LucideIcons.fileText, color: colors.linkOlive, size: 28),
                      const SizedBox(width: AppTheme.spacingMd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Active Lease',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: colors.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (unit.leaseEnd != null)
                              Text(
                                'Ends ${DateFormat('MMMM d, y').format(unit.leaseEnd!)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.sage,
                                ),
                              )
                            else if (_hasLeaseDocument)
                              Text(
                                'Lease on file',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.sage,
                                ),
                              )
                            else
                              Text(
                                'No lease document uploaded yet. Contact your landlord.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.sage,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(LucideIcons.chevronRight, color: colors.taupe, size: 16),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppTheme.spacingLg),

              // ── Payment History ─────────────────────────────────────────
              Row(
                children: [
                  Text('Payment History', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => context.push('/tenant/payments'),
                    child: Text(
                      'View All',
                      style: TextStyle(
                        color: colors.linkOlive,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingSm),
              _PaymentHistoryList(
                unitId: unit.id,
                db: _db,
                colors: colors,
                theme: theme,
                revision: _historyRevision,
              ),
              ], // end unit != null else branch

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadPaymentMethods(String? landlordId) async {
    if (landlordId == null || landlordId.isEmpty) {
      if (mounted) {
        setState(() {
          _paymentMethods = [];
          _loadingPayments = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _loadingPayments = true);
    try {
      final rows = await _db
          .from('payment_methods')
          .select()
          .eq('landlord_id', landlordId);
      final list = List<dynamic>.from(rows as List);
      var methods = landlordPaymentMethodsFromRows(list);
      // Older accounts stored the same instructions on the landlord profile
      // instead of the payment_methods table. Use that only when no row exists.
      if (list.isEmpty) {
        final contact = await fetchLandlordContact(_db, landlordId);
        methods = userPaymentMethodsFromJson(contact?['payment_instructions']);
      }
      if (mounted) {
        setState(() {
          _paymentMethods = methods;
          _loadingPayments = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _paymentMethods = [];
          _loadingPayments = false;
        });
      }
    }
  }

  Future<void> _loadLeaseDocument(String unitId) async {
    try {
      final rows = await _db.from('documents').select().eq('unit_id', unitId);
      final found = List<Map<String, dynamic>>.from(rows as List).any((row) {
        final type = documentDocType(row).toLowerCase();
        final name = documentFileName(row).toLowerCase();
        return type.contains('lease') || name.contains('lease');
      });
      if (mounted) setState(() => _hasLeaseDocument = found);
    } catch (_) {}
  }

  Future<void> _loadPendingRent(String unitId) async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return;
      List<Map<String, dynamic>> list;
      try {
        final rows = await _db
            .from('payments')
            .select('status, submitted_at, rent_period')
            .eq('unit_id', unitId)
            .eq('tenant_id', uid);
        list = List<Map<String, dynamic>>.from(rows as List);
      } catch (_) {
        final rows = await _db
            .from('payments')
            .select('status, submitted_at')
            .eq('unit_id', unitId)
            .eq('tenant_id', uid);
        list = List<Map<String, dynamic>>.from(rows as List);
      }
      final now = DateTime.now();
      DateTime? monthOf(Map<String, dynamic> row) => confirmedRentMonth(
            period: DateTime.tryParse((row['rent_period'] ?? '').toString()),
            submittedAt: DateTime.tryParse((row['submitted_at'] as String?) ?? ''),
            dueDay: _unit?.rentDueDay,
          );
      bool sent(Map<String, dynamic> row) {
        final s = ((row['status'] as String?) ?? '').trim().toLowerCase();
        return s == 'confirmed' || isPendingRentStatus(s);
      }
      final sentMonths = <String>{
        for (final row in list.where(sent))
          if (monthOf(row) != null) '${monthOf(row)!.year}-${monthOf(row)!.month}',
      };
      // The notice is for the month on the card: the next due date when
      // paying early, or this month when it is late and not yet sent.
      final target = rentNoticeTargetMonth(
        now,
        dueDay: _unit?.rentDueDay,
        sentMonths: sentMonths,
      );
      bool covers(Map<String, dynamic> row) {
        final month = monthOf(row);
        return month != null && month.year == target.year && month.month == target.month;
      }
      final pending = list.any((row) =>
          isPendingRentStatus(row['status'] as String?) && covers(row));
      // A confirmed payment for this period also closes the button, so the
      // tenant cannot send a second notice for rent the landlord accepted.
      final confirmed = list.any((row) =>
          ((row['status'] as String?) ?? '').trim().toLowerCase() == 'confirmed' &&
          covers(row));
      if (mounted) {
        setState(() {
          _noticeMonth = target;
          _hasPendingRent = pending || confirmed;
          _rentConfirmed = confirmed;
        });
      }
    } catch (_) {}
  }

  Future<void> _markRentPaid() async {
    if (_savingRent || _hasPendingRent) return;
    final colors = Theme.of(context).extension<ElevoColors>()!;
    var saved = false;
    setState(() => _savingRent = true);
    try {
      final uid = _db.auth.currentUser?.id;
      final unitId = _unit?.id;
      if (uid == null || unitId == null) {
        throw Exception('No unit is linked to this account.');
      }
      await _loadPendingRent(unitId);
      if (_hasPendingRent) {
        saved = true;
      } else {
      final submittedAt = DateTime.now().toUtc();
      final period = _noticeMonth ??
          rentNoticeTargetMonth(DateTime.now(), dueDay: _unit!.rentDueDay);
      final row = <String, dynamic>{
        'tenant_id': uid,
        'unit_id': unitId,
        'amount': _unit!.rentAmount,
        'status': 'pending_confirmation',
        'submitted_at': submittedAt.toIso8601String(),
        'rent_period':
            '${period.year.toString().padLeft(4, '0')}-${period.month.toString().padLeft(2, '0')}-01',
      };
      dynamic inserted;
      try {
        inserted = await _db.from('payments').insert(row).select();
      } catch (_) {
        row.remove('rent_period');
        inserted = await _db.from('payments').insert(row).select();
      }
      if (List<dynamic>.from(inserted as List).isEmpty) {
        throw Exception('Nothing was recorded.');
      }
      saved = true;

      try {
        final landlordRow = await _db
            .from('units')
            .select('landlord_id')
            .eq('id', unitId)
            .maybeSingle();
        final landlordId = landlordIdForTenantPaymentMethods(
          unitLandlordId: landlordRow?['landlord_id'] as String?,
          propertyLandlordId: _landlordId,
        );
        if (landlordId != null) {
          final tenantName = context.read<AuthProvider>().currentUser?.fullName ?? 'Your tenant';
          final amount = '\$${_unit!.rentAmount.toStringAsFixed(0)}';
          final monthLabel = rentMonthLabel(period);
          await PushNotificationService.notifyRentPaid(
            landlordId: landlordId,
            tenantName: tenantName,
            unitAddress: '$_propertyAddress #${_unit!.unitNumber}',
            amount: amount,
            monthLabel: monthLabel,
            unitId: unitId,
          );
          final contact = await fetchLandlordContact(_db, landlordId);
          final landlordEmail = (contact?['email'] as String?)?.trim() ?? '';
          if (landlordEmail.isNotEmpty) {
            await NotificationService.sendRentPaid(
              toEmail: landlordEmail,
              tenantName: tenantName,
              amount: amount,
              monthLabel: monthLabel,
              unitId: unitId,
            );
          }
        }
      } catch (_) {
        // The payment row is already saved. A missed alert should not
        // tell the tenant that the notice failed.
      }
      }
    } catch (_) {
      saved = false;
    }
    if (mounted) {
      setState(() {
        _savingRent = false;
        if (saved) {
          _hasPendingRent = true;
          _historyRevision += 1;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(saved
              ? 'Payment notification sent to landlord'
              : 'Could not record the payment. Please try again.'),
          backgroundColor: saved ? colors.successGreen : colors.urgentRed,
        ),
      );
    }
  }
}

// ── Payment History List ──────────────────────────────────────────────────────

class _PaymentHistoryList extends StatefulWidget {
  final String unitId;
  final SupabaseClient db;
  final ElevoColors colors;
  final ThemeData theme;
  final int revision;

  const _PaymentHistoryList({
    required this.unitId,
    required this.db,
    required this.colors,
    required this.theme,
    required this.revision,
  });

  @override
  State<_PaymentHistoryList> createState() => _PaymentHistoryListState();
}

class _PaymentHistoryListState extends State<_PaymentHistoryList> {
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_PaymentHistoryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.db
          .from('payments')
          .select()
          .eq('unit_id', widget.unitId)
          .order('created_at', ascending: false)
          .limit(6);
      if (mounted) setState(() { _payments = List<Map<String, dynamic>>.from(rows); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final dateFmt = DateFormat('MMMM d, y');

    if (_loading) {
      return Container(
        height: 60,
        decoration: BoxDecoration(
          color: widget.colors.card,
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_payments.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        decoration: BoxDecoration(
          color: widget.colors.card,
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        ),
        child: Text(
          'No payment history yet.',
          style: widget.theme.textTheme.bodySmall?.copyWith(color: widget.colors.sage),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: widget.colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _payments.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: widget.colors.taupe.withAlpha(30)),
        itemBuilder: (_, i) {
          final p = _payments[i];
          final status = (p['status'] as String?) ?? 'pending_confirmation';
          final submitted = p['submitted_at'] != null
              ? DateTime.tryParse(p['submitted_at'] as String)
              : null;
          final amount = ((p['amount'] as num?) ?? 0).toDouble();

          Color statusColor;
          String statusLabel;
          if (status == 'confirmed') {
            statusColor = widget.colors.successGreen;
            statusLabel = 'Confirmed';
          } else if (status == 'declined') {
            statusColor = widget.colors.urgentRed;
            statusLabel = 'Declined';
          } else if (status == 'late') {
            statusColor = widget.colors.urgentRed;
            statusLabel = 'Late';
          } else {
            statusColor = widget.colors.warningAmber;
            statusLabel = 'Pending';
          }

          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingMd,
              vertical: AppTheme.spacingSm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    submitted != null ? dateFmt.format(submitted.toLocal()) : 'Unknown date',
                    style: widget.theme.textTheme.bodySmall?.copyWith(
                      color: widget.colors.ink,
                    ),
                  ),
                ),
                Text(
                  fmt.format(amount),
                  style: TextStyle(
                    color: widget.colors.olive,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: AppTheme.spacingSm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ElevoColors>()!;

    return Expanded(
      child: GestureDetector(
        onTap: () { HapticFeedback.lightImpact(); onTap(); },
        child: Column(
          children: [
            Container(
              width: AppTheme.touchTarget,
              height: AppTheme.touchTarget,
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                border: Border.all(color: colors.stone),
              ),
              child: Icon(icon, color: colors.linkOlive, size: 22),
            ),
            const SizedBox(height: AppTheme.spacingXs),
            Text(
              label,
              style: TextStyle(color: colors.ink, fontSize: 11, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
