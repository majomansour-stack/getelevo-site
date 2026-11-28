import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/elevo_logic.dart';
import '../../theme/theme.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  final _db = Supabase.instance.client;

  List<LandlordPaymentMethod> _methods = [];
  List<String> _existingIds = [];
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) {
        setState(() {
          _loading = false;
          _loadError = 'Sign in again to edit payment instructions.';
        });
        return;
      }
      final rows = await _db
          .from('payment_methods')
          .select()
          .eq('landlord_id', uid);
      final list = List<Map<String, dynamic>>.from(rows as List);
      if (!mounted) return;
      setState(() {
        _existingIds = [
          for (final row in list)
            if (row['id'] != null) row['id'].toString(),
        ];
        _methods = landlordPaymentMethodsFromRows(list);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load payment instructions.';
      });
    }
  }

  Future<void> _persist(List<LandlordPaymentMethod> next) async {
    final previous = _methods;
    setState(() {
      _methods = next;
      _saving = true;
    });
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) throw Exception('Not signed in');
      final payload = paymentMethodsWritePayload(
        landlordId: uid,
        methods: next,
        updatedAt: DateTime.now(),
      );
      List<dynamic> saved;
      if (_existingIds.isEmpty) {
        final inserted = await _db.from('payment_methods').insert(payload).select();
        saved = List<dynamic>.from(inserted as List);
      } else {
        final update = Map<String, dynamic>.from(payload)..remove('landlord_id');
        final updated = await _db
            .from('payment_methods')
            .update(update)
            .inFilter('id', _existingIds)
            .select();
        saved = List<dynamic>.from(updated as List);
      }
      if (!paymentMethodWriteReturnedRows(saved)) {
        throw Exception('Nothing was saved.');
      }
      if (!mounted) return;
      setState(() {
        _existingIds = [
          for (final row in saved)
            if (row is Map && row['id'] != null) row['id'].toString(),
        ];
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment instructions saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _methods = previous;
        _saving = false;
      });
      final message = e is PostgrestException
          ? 'Save failed (${e.code}): ${e.message}'
          : 'Could not save payment instructions.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _edit({LandlordPaymentMethod? existing}) async {
    final draft = await showDialog<LandlordPaymentMethod>(
      context: context,
      builder: (context) => _MethodDialog(existing: existing),
    );
    if (draft == null) return;
    await _persist(upsertPaymentMethod(_methods, draft));
  }

  Future<void> _delete(LandlordPaymentMethod method) async {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this method?'),
        content: Text(
          '${method.title} will no longer be shown to your tenants.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove', style: TextStyle(color: colors.urgentRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _persist(withoutPaymentMethod(_methods, method.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Methods'),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.spacingLg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: AppTheme.spacingMd),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(AppTheme.spacingLg),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppTheme.spacingMd),
                      decoration: BoxDecoration(
                        color: colors.midnight.withAlpha(12),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                        border: Border.all(color: colors.gold.withAlpha(60)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(LucideIcons.info, color: colors.gold, size: 18),
                          const SizedBox(width: AppTheme.spacingSm),
                          Expanded(
                            child: Text(
                              'Only your own tenants see these instructions on their rent screen. '
                              'Elevo does not collect or process rent.',
                              style: theme.textTheme.bodySmall?.copyWith(color: colors.sage),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingLg),
                    if (_methods.isEmpty)
                      Text(
                        'No payment methods yet. Add Zelle, Venmo, a check, a bank transfer, or anything else you accept.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: colors.sage),
                      ),
                    for (var i = 0; i < _methods.length; i++)
                      _MethodTile(
                        method: _methods[i],
                        canMoveUp: i > 0 && !_saving,
                        canMoveDown: i < _methods.length - 1 && !_saving,
                        onEdit: _saving ? null : () => _edit(existing: _methods[i]),
                        onDelete: _saving ? null : () => _delete(_methods[i]),
                        onUp: _saving
                            ? null
                            : () => _persist(movePaymentMethod(_methods, i, -1)),
                        onDown: _saving
                            ? null
                            : () => _persist(movePaymentMethod(_methods, i, 1)),
                      ),
                    const SizedBox(height: AppTheme.spacingLg),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : () => _edit(),
                        icon: const Icon(LucideIcons.plus, size: 18),
                        label: const Text('Add payment method'),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingLg),
                  ],
                ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final LandlordPaymentMethod method;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  const _MethodTile({
    required this.method,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onEdit,
    required this.onDelete,
    required this.onUp,
    required this.onDown,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingSm),
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.stone.withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(method.title, style: theme.textTheme.titleSmall),
          if (method.detail.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(method.detail, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: AppTheme.spacingSm),
          Row(
            children: [
              IconButton(
                tooltip: 'Move up',
                onPressed: canMoveUp ? onUp : null,
                icon: const Icon(LucideIcons.chevronUp, size: 18),
              ),
              IconButton(
                tooltip: 'Move down',
                onPressed: canMoveDown ? onDown : null,
                icon: const Icon(LucideIcons.chevronDown, size: 18),
              ),
              const Spacer(),
              TextButton(onPressed: onEdit, child: const Text('Edit')),
              TextButton(
                onPressed: onDelete,
                child: Text('Remove', style: TextStyle(color: colors.urgentRed)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MethodDialog extends StatefulWidget {
  final LandlordPaymentMethod? existing;

  const _MethodDialog({this.existing});

  @override
  State<_MethodDialog> createState() => _MethodDialogState();
}

class _MethodDialogState extends State<_MethodDialog> {
  late String _kind;
  late final TextEditingController _handleCtrl;
  late final TextEditingController _instructionsCtrl;
  late final TextEditingController _routingCtrl;
  late final TextEditingController _accountCtrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _kind = existing == null ? 'zelle' : normalizePaymentMethodKind(existing.kind);
    _handleCtrl = TextEditingController(text: existing?.handle ?? '');
    _instructionsCtrl = TextEditingController(text: existing?.instructions ?? '');
    _routingCtrl = TextEditingController(text: existing?.bankRouting ?? '');
    _accountCtrl = TextEditingController(text: existing?.bankAccount ?? '');
  }

  @override
  void dispose() {
    _handleCtrl.dispose();
    _instructionsCtrl.dispose();
    _routingCtrl.dispose();
    _accountCtrl.dispose();
    super.dispose();
  }

  String get _handleLabel {
    switch (_kind) {
      case 'zelle':
        return 'Phone or email';
      case 'venmo':
        return 'Venmo username';
      case 'cash_app':
        return 'Cashtag';
      case 'paypal':
        return 'PayPal email or username';
      case 'bank_transfer':
        return 'Bank name';
      case 'check':
        return 'Payable to';
      case 'cash':
        return 'Where to bring cash';
      default:
        return 'Method name';
    }
  }

  void _save() {
    final error = validatePaymentMethodDraft(
      kind: _kind,
      handle: _handleCtrl.text,
      instructions: _instructionsCtrl.text,
      bankRouting: _kind == 'bank_transfer' ? _routingCtrl.text : null,
      bankAccount: _kind == 'bank_transfer' ? _accountCtrl.text : null,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final existing = widget.existing;
    Navigator.pop(
      context,
      LandlordPaymentMethod(
        id: existing?.id ?? 'pm-${DateTime.now().microsecondsSinceEpoch}',
        kind: _kind,
        handle: _handleCtrl.text.trim(),
        instructions: _instructionsCtrl.text.trim(),
        sortOrder: existing?.sortOrder ?? 0,
        bankRouting: _kind == 'bank_transfer' ? _routingCtrl.text.trim() : null,
        bankAccount: _kind == 'bank_transfer' ? _accountCtrl.text.trim() : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add payment method' : 'Edit payment method'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _kind,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final kind in paymentMethodKinds)
                  DropdownMenuItem(
                    value: kind,
                    child: Text(paymentMethodKindLabel(kind)),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _kind = value);
              },
            ),
            const SizedBox(height: AppTheme.spacingSm),
            TextField(
              controller: _handleCtrl,
              decoration: InputDecoration(labelText: _handleLabel),
            ),
            if (_kind == 'bank_transfer') ...[
              const SizedBox(height: AppTheme.spacingSm),
              TextField(
                controller: _routingCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Routing number'),
              ),
              const SizedBox(height: AppTheme.spacingSm),
              TextField(
                controller: _accountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Account number'),
              ),
            ],
            const SizedBox(height: AppTheme.spacingSm),
            TextField(
              controller: _instructionsCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Instructions',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppTheme.spacingSm),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).extension<ElevoColors>()!.urgentRed,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
