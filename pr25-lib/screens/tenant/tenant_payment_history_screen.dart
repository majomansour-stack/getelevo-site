import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/theme.dart';

class TenantPaymentHistoryScreen extends StatefulWidget {
  const TenantPaymentHistoryScreen({super.key});

  @override
  State<TenantPaymentHistoryScreen> createState() =>
      _TenantPaymentHistoryScreenState();
}

class _TenantPaymentHistoryScreenState extends State<TenantPaymentHistoryScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final rows = await _db
          .from('payments')
          .select()
          .eq('tenant_id', uid)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _payments = List<Map<String, dynamic>>.from(rows as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final dateFmt = DateFormat('MMMM d, y');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment History'),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _payments.isEmpty
              ? Center(
                  child: Text(
                    'No payment history yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.sage),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  itemCount: _payments.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: colors.taupe.withAlpha(30)),
                  itemBuilder: (_, i) {
                    final p = _payments[i];
                    final status = (p['status'] as String?) ?? 'pending_confirmation';
                    final submitted = p['submitted_at'] != null
                        ? DateTime.tryParse(p['submitted_at'] as String)
                        : null;
                    final amount = ((p['amount'] as num?) ?? 0).toDouble();
                    final confirmed = status == 'confirmed';
                    final declined = status == 'declined';
                    final late = status == 'late';
                    final statusColor = confirmed
                        ? colors.successGreen
                        : declined || late
                            ? colors.urgentRed
                            : colors.warningAmber;
                    final statusLabel = confirmed
                        ? 'Confirmed'
                        : declined
                            ? 'Declined'
                            : late
                                ? 'Late'
                                : 'Pending';
                    return ListTile(
                      title: Text(
                        submitted != null
                            ? dateFmt.format(submitted.toLocal())
                            : 'Unknown date',
                        style: TextStyle(color: colors.ink),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            fmt.format(amount),
                            style: TextStyle(
                              color: colors.olive,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(statusLabel, style: TextStyle(color: statusColor)),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
