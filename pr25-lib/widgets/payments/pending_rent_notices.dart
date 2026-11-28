import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/elevo_logic.dart';
import '../../theme/theme.dart';

/// Landlord review of tenant "I Have Paid" notices.
class PendingRentNotices extends StatefulWidget {
  final List<String> unitIds;
  final Map<String, String> unitLabels;
  final Map<String, int?> unitDueDays;
  final VoidCallback? onChanged;

  const PendingRentNotices({
    super.key,
    required this.unitIds,
    this.unitLabels = const {},
    this.unitDueDays = const {},
    this.onChanged,
  });

  @override
  State<PendingRentNotices> createState() => _PendingRentNoticesState();
}

class _PendingRentNoticesState extends State<PendingRentNotices> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  Map<String, String> _names = {};
  bool _loading = true;
  String? _savingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PendingRentNotices oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unitIds.join() != widget.unitIds.join()) _load();
  }

  Future<void> _load() async {
    if (widget.unitIds.isEmpty) {
      if (mounted) setState(() { _rows = []; _loading = false; });
      return;
    }
    try {
      List<dynamic> raw;
      try {
        raw = await _db
            .from('payments')
            .select('id, amount, status, submitted_at, unit_id, tenant_id, rent_period')
            .inFilter('unit_id', widget.unitIds)
            .eq('status', 'pending_confirmation')
            .order('submitted_at', ascending: false) as List;
      } catch (_) {
        raw = await _db
            .from('payments')
            .select('id, amount, status, submitted_at, unit_id, tenant_id')
            .inFilter('unit_id', widget.unitIds)
            .eq('status', 'pending_confirmation')
            .order('submitted_at', ascending: false) as List;
      }
      final rows = List<Map<String, dynamic>>.from(raw);
      final tenantIds = rows
          .map((row) => row['tenant_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final names = <String, String>{};
      if (tenantIds.isNotEmpty) {
        try {
          final people = await _db
              .from('users')
              .select('id, full_name')
              .inFilter('id', tenantIds);
          for (final person in people as List) {
            final id = person['id']?.toString() ?? '';
            final name = (person['full_name'] as String?)?.trim() ?? '';
            if (id.isNotEmpty && name.isNotEmpty) names[id] = name;
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _rows = rows;
          _names = names;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(String id, String status) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null || _savingId != null) return;
    setState(() => _savingId = id);
    try {
      await _db.from('payments').update({
        'status': status,
        'confirmed_by': uid,
        'confirmed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      await _load();
      widget.onChanged?.call();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update that payment.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          _rows.length == 1 ? '1 rent notice' : '${_rows.length} rent notices',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (final row in _rows)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: AppTheme.surfaceCard(colors),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(builder: (context) {
                  final amount = ((row['amount'] as num?) ?? 0).toDouble();
                  final submitted = DateTime.tryParse((row['submitted_at'] ?? '').toString());
                  final dueDay = widget.unitDueDays[row['unit_id']?.toString() ?? ''];
                  final stored = DateTime.tryParse((row['rent_period'] ?? '').toString());
                  final month = stored != null
                      ? rentMonthLabel(stored)
                      : submitted == null
                          ? 'this month'
                          : rentPeriodLabel(submitted, dueDay: dueDay);
                  final name = _names[row['tenant_id']?.toString() ?? ''] ?? 'Your tenant';
                  final place = widget.unitLabels[row['unit_id']?.toString() ?? ''] ?? '';
                  return Text(
                    '$name says they paid ${fmt.format(amount)} for $month'
                    '${place.isEmpty ? '' : ' · $place'}',
                    style: theme.textTheme.titleSmall?.copyWith(color: colors.ink),
                  );
                }),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _savingId == null
                            ? () => _setStatus(row['id'] as String, 'confirmed')
                            : null,
                        child: const Text('Confirm'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _savingId == null
                            ? () => _setStatus(row['id'] as String, 'declined')
                            : null,
                        child: const Text('Decline'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
