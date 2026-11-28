import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/theme.dart';

/// Landlord referral code, how the 20% discount works, and referral status.
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  String _code = '';
  int _count = 0;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _db.rpc('ensure_landlord_referral_code');
      final data = await _db.rpc('my_referral_dashboard');
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final list = map['referrals'];
      if (!mounted) return;
      setState(() {
        _code = map['code']?.toString() ?? '';
        _count = (map['count'] as num?)?.toInt() ?? 0;
        _rows = list is List
            ? list.map((row) => Map<String, dynamic>.from(row as Map)).toList()
            : const [];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your referral code.';
      });
    }
  }

  Future<void> _copy() async {
    if (_code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Referral code copied')),
    );
  }

  Future<void> _share() async {
    if (_code.isEmpty) return;
    await Share.share(
      'Use my Elevo code $_code when you start a landlord account. '
      'We both get 20% off for 3 months. https://getelevo.app/app/',
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'rewarded':
        return '20% off applied';
      case 'reward_pending':
        return 'Waiting for your plan';
      default:
        return 'Signed up';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    const navy = Color(0xFF1F3A5F);
    const gold = Color(0xFFC9A227);
    const darkGold = Color(0xFF7A5E28);

    return Scaffold(
      appBar: AppBar(title: const Text('Referral Program')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              children: [
                if (_error != null)
                  Text(_error!, style: TextStyle(color: colors.urgentRed)),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppTheme.spacingLg),
                  decoration: BoxDecoration(
                    color: navy,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your code',
                        style: theme.textTheme.bodySmall?.copyWith(color: gold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _code.isEmpty ? '—' : _code,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingMd),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _code.isEmpty ? null : _copy,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: gold,
                                side: const BorderSide(color: gold),
                              ),
                              child: const Text('Copy'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _code.isEmpty ? null : _share,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: gold,
                                foregroundColor: navy,
                              ),
                              child: const Text('Share'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTheme.spacingLg),
                Text(
                  'How it works',
                  style: theme.textTheme.titleMedium?.copyWith(color: navy),
                ),
                const SizedBox(height: 6),
                Text(
                  'Give 20% off for 3 months, get 20% off for 3 months.',
                  style: theme.textTheme.bodyLarge?.copyWith(color: darkGold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Share your code with another landlord. They enter it when they create an account or choose a plan. '
                  'They still add a card for the 7-day trial. When their plan is active, you both get 20% off for 3 months.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink),
                ),
                const SizedBox(height: AppTheme.spacingLg),
                Text(
                  _count == 1 ? '1 referral' : '$_count referrals',
                  style: theme.textTheme.titleMedium?.copyWith(color: navy),
                ),
                const SizedBox(height: AppTheme.spacingSm),
                if (_rows.isEmpty)
                  Text(
                    'No referrals yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.sage),
                  )
                else
                  for (final row in _rows)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        (row['first_name']?.toString().trim().isNotEmpty ?? false)
                            ? row['first_name'].toString()
                            : 'Landlord',
                      ),
                      trailing: Text(
                        _statusLabel(row['status']?.toString() ?? ''),
                        style: theme.textTheme.labelMedium?.copyWith(color: darkGold),
                      ),
                    ),
              ],
            ),
    );
  }
}
