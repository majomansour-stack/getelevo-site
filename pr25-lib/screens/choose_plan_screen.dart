import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/billing_rules.dart';
import '../providers/auth_provider.dart';
import '../services/stripe_checkout.dart';
import '../theme/theme.dart';
import '../widgets/account/delete_account_dialog.dart';

/// Shown after a new landlord confirms email. The landlord app stays
/// closed until Stripe marks the subscription trialing or active.
class ChoosePlanScreen extends StatefulWidget {
  const ChoosePlanScreen({super.key});

  @override
  State<ChoosePlanScreen> createState() => _ChoosePlanScreenState();
}

class _ChoosePlanScreenState extends State<ChoosePlanScreen> {
  bool _annual = false;
  bool _checking = false;
  final _referral = TextEditingController();
  bool _hasReferral = false;

  @override
  void initState() {
    super.initState();
    final saved = Supabase.instance.client.auth.currentUser
        ?.userMetadata?['referral_code']
        ?.toString();
    if (saved != null && saved.trim().isNotEmpty) {
      _referral.text = saved.trim();
    }
    _lookupReferral();
  }

  @override
  void dispose() {
    _referral.dispose();
    super.dispose();
  }

  Future<void> _lookupReferral() async {
    try {
      final data = await Supabase.instance.client.rpc('my_referral_dashboard');
      final used = data is Map ? data['used_code']?.toString() ?? '' : '';
      if (!mounted) return;
      setState(() => _hasReferral = used.isNotEmpty);
    } catch (_) {}
  }

  Future<bool> _claimIfEntered() async {
    final code = _referral.text.trim();
    if (code.isEmpty || _hasReferral) return true;
    try {
      await Supabase.instance.client.rpc(
        'claim_referral_code',
        params: {'p_code': code},
      );
      if (mounted) setState(() => _hasReferral = true);
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
      }
      return false;
    }
  }

  Future<void> _open(String link, String plan) async {
    if (!await _claimIfEntered()) return;
    if (_hasReferral || _referral.text.trim().isNotEmpty) {
      final error = await openReferralCheckout(plan: plan, annual: _annual);
      if (error == null) return;
      if (mounted && !error.contains('not ready')) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
        return;
      }
    }
    final user = context.read<AuthProvider>().currentUser;
    final opened = await openStripePaymentLink(
      link: link,
      userId: user?.id,
      email: user?.email,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the payment page.')),
      );
    }
  }

  Future<void> _refresh() async {
    setState(() => _checking = true);
    try {
      await context.read<AuthProvider>().refreshProfile();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not check the account. Try again in a moment.',
            ),
          ),
        );
      }
    }
    if (!mounted) return;
    final user = context.read<AuthProvider>().currentUser;
    final waiting = landlordMustChoosePlan(
      role: user?.role,
      plan: user?.subscriptionPlan,
      status: user?.subscriptionStatus,
      trialEndsAt: user?.trialEndsAt,
      planChoiceRequired: user?.planChoiceRequired ?? false,
    );
    setState(() => _checking = false);
    if (!waiting) {
      context.go('/landlord');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Finish adding a card in Stripe, then tap this again.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final essential = _annual ? '\$299/yr' : '\$39.99/mo';
    final unlimited = _annual ? '\$699/yr' : '\$79/mo';
    final essentialLink =
        _annual ? stripeEssentialAnnualLink : stripeEssentialMonthlyLink;
    final unlimitedLink =
        _annual ? stripeUnlimitedAnnualLink : stripeUnlimitedMonthlyLink;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Choose your plan'),
        actions: [
          TextButton(
            onPressed: () => confirmAndDeleteAccount(context),
            child: const Text('Delete account'),
          ),
          TextButton(
            onPressed: () => context.read<AuthProvider>().logout(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        children: [
          Text('Add a card to start.', style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppTheme.spacingSm),
          Text(
            'You will not be charged today. The card is charged after the 7-day trial unless you cancel.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: AppTheme.spacingMd),
          TextField(
            controller: _referral,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Referral code (optional)',
              hintText: 'ELEVO-XXXX',
            ),
          ),
          const SizedBox(height: AppTheme.spacingMd),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Monthly')),
              ButtonSegment(value: true, label: Text('Annual')),
            ],
            selected: {_annual},
            onSelectionChanged: (next) => setState(() => _annual = next.first),
          ),
          const SizedBox(height: AppTheme.spacingMd),
          _PlanChoice(
            name: 'Essential',
            price: essential,
            detail: '1 property included. Add more later at \$12.99/mo each.',
            button: 'Continue with Essential',
            onPressed: () {
              HapticFeedback.lightImpact();
              _open(essentialLink, 'essential');
            },
          ),
          const SizedBox(height: AppTheme.spacingMd),
          _PlanChoice(
            name: 'Unlimited',
            price: unlimited,
            detail: 'No property limit while the subscription is active.',
            button: 'Continue with Unlimited',
            onPressed: () {
              HapticFeedback.lightImpact();
              _open(unlimitedLink, 'unlimited');
            },
          ),
          const SizedBox(height: AppTheme.spacingLg),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _checking ? null : _refresh,
              child: Text(_checking ? 'Checking…' : "I've added my card"),
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Text(
            'Stripe collects the card. Elevo never sees the card number. Come back here after checkout and tap the button above.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.taupe),
          ),
        ],
      ),
    );
  }
}

class _PlanChoice extends StatelessWidget {
  final String name;
  final String price;
  final String detail;
  final String button;
  final VoidCallback onPressed;

  const _PlanChoice({
    required this.name,
    required this.price,
    required this.detail,
    required this.button,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.charcoal,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.gold.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.ivory,
                  ),
                ),
              ),
              Text(
                price,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.gold,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.ivory),
          ),
          const SizedBox(height: AppTheme.spacingMd),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.olive,
                foregroundColor: colors.onOlive,
              ),
              child: Text(button),
            ),
          ),
        ],
      ),
    );
  }
}
