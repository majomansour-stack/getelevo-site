import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/billing_rules.dart';
import '../providers/auth_provider.dart';
import '../services/stripe_checkout.dart';
import '../theme/theme.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  // Monthly, same default as Choose your plan.
  bool _isAnnual = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AuthProvider>().refreshProfile();
    });
  }

  Future<void> _launchPayment(String link) async {
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

  String _planDetail({
    required LandlordPlanSnapshot snap,
    required String trialWhen,
    required String? periodWhen,
    required bool needsCard,
  }) {
    final card = needsCard
        ? 'Add a card now. It is charged after the 7-day trial, not today. '
        : '';
    if (snap.trialActive) return '$card$trialWhen';
    if (periodWhen != null) return '$card$periodWhen';
    if (snap.createsBlocked) {
      return '${card}Subscribe to add properties. What you already added is still here.';
    }
    return '${card}This is the plan on your account.';
  }

  Future<void> _manage() async {
    final error = await openBillingPortal();
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final user = context.watch<AuthProvider>().currentUser;
    final snap = landlordPlanSnapshot(
      role: user?.role ?? 'landlord',
      plan: user?.subscriptionPlan,
      status: user?.subscriptionStatus,
      trialEndsAt: user?.trialEndsAt,
      extraProperties: user?.extraPropertyCount ?? 0,
      now: DateTime.now(),
    );
    final currentPlan = snap.planKey == 'essential' || snap.planKey == 'unlimited'
        ? snap.planKey
        : 'trial';
    final legacyTrial = snap.trialActive &&
        currentPlan != 'essential' &&
        currentPlan != 'unlimited';
    final trialWhen = legacyTrial
        ? (user?.trialEndsAt == null
            ? 'Your trial is active. Choose a plan before it ends.'
            : 'Your trial is active until ${DateFormat.yMMMd().format(user!.trialEndsAt!.toLocal())}. '
                'Choose a plan before it ends.')
        : (user?.trialEndsAt == null
            ? 'Your 7-day trial is active.'
            : 'Trial until ${DateFormat.yMMMd().format(user!.trialEndsAt!.toLocal())}. '
                'The card is charged then unless you cancel.');
    final periodWhen = user?.currentPeriodEnd == null
        ? null
        : 'Renews ${DateFormat.yMMMd().format(user!.currentPeriodEnd!.toLocal())}.';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription & Pricing'),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        children: [
          // ── Real plan, status, and trial end ────────────────────────────
          _AccountPlanBanner(
            colors: colors,
            theme: theme,
            title: '${landlordPlanTitle(currentPlan)} · ${subscriptionStatusLabel(snap.status)}',
            detail: _planDetail(
              snap: snap,
              trialWhen: trialWhen,
              periodWhen: periodWhen,
              needsCard: !legacyTrial &&
                  snap.status != 'trialing' &&
                  (user?.stripeCustomerId == null ||
                      user!.stripeCustomerId!.trim().isEmpty),
            ),
            onManage: _manage,
          ),
          const SizedBox(height: AppTheme.spacingMd),
          if (snap.trialActive && !legacyTrial) ...[
            _TrialBadge(colors: colors, theme: theme, detail: trialWhen),
            const SizedBox(height: AppTheme.spacingMd),
          ],

          // ── Annual savings callout — shown first, no word "switch" ───────
          _AnnualValueBanner(
            colors: colors,
            theme: theme,
            isAnnual: _isAnnual,
            onToggle: (v) => setState(() => _isAnnual = v),
          ),
          const SizedBox(height: AppTheme.spacingMd),

          // ── Billing toggle ───────────────────────────────────────────────
          _BillingToggle(
            isAnnual: _isAnnual,
            onChanged: (v) => setState(() => _isAnnual = v),
          ),
          const SizedBox(height: AppTheme.spacingLg),

          // ── Essential plan ───────────────────────────────────────────────
          _PlanCard(
            name: 'Essential',
            planLabel: 'Get Started',
            tagline: '1 property — core features',
            monthlyPrice: 39.99,
            annualMonthlyEquiv: 24.92,
            annualTotalPrice: 299.00,
            isAnnual: _isAnnual,
            isCurrent: currentPlan == 'essential' && snap.paidActive,
            isOnTrial: snap.trialActive,
            isHighlighted: false,
            isMostPopular: false,
            savingsBadge: _isAnnual ? 'Save \$180.88/yr' : null,
            trialBadge: null,
            features: const [
              _Feature('1 property included', true),
              _Feature('Additional properties at \$12.99/mo each', true),
              _Feature('Tenant messaging & broadcast', true),
              _Feature('Maintenance requests + vendor management', true),
              _Feature('Document storage (10 GB)', true),
              _Feature('Tenant screening via RentSpree', true),
              _Feature('Calendar, alerts & reminders', true),
              _Feature('Financial P&L reports (PDF)', true),
              _Feature('Mon–Fri email support', true),
              _Feature('Unlimited properties', false),
            ],
            ctaCopy: 'Start 7-Day Trial',
            showTrialDisclaimer: true,
            onUpgrade: () => _openStripeCheckout('Essential'),
            onManage: _manage,
          ),
          const SizedBox(height: AppTheme.spacingMd),

          // ── Per-property pricing breakdown (Essential) ───────────────────
          _PerPropertyNote(colors: colors, theme: theme),
          const SizedBox(height: AppTheme.spacingLg),

          // ── Unlimited plan ───────────────────────────────────────────────
          _PlanCard(
            name: 'Unlimited',
            planLabel: 'Most Popular',
            tagline: 'Unlimited properties',
            monthlyPrice: 79.00,
            annualMonthlyEquiv: 58.25,
            annualTotalPrice: 699.00,
            isAnnual: _isAnnual,
            isCurrent: currentPlan == 'unlimited' && snap.paidActive,
            isOnTrial: snap.trialActive,
            isHighlighted: true,
            isMostPopular: true,
            savingsBadge: _isAnnual ? 'Save \$249/yr' : null,
            trialBadge: null,
            features: const [
              _Feature('Unlimited properties', true),
              _Feature('Tenant messaging & broadcast', true),
              _Feature('Maintenance + vendor management', true),
              _Feature('Document storage (unlimited)', true),
              _Feature('Tenant screening via RentSpree', true),
              _Feature('Financial P&L + tax-ready reports (PDF)', true),
              _Feature('Calendar, alerts & reminders', true),
              _Feature('Priority Mon–Fri email support', true),
              _Feature('Done-for-You setup add-on available', true),
            ],
            ctaCopy: 'Start 7-Day Trial',
            showTrialDisclaimer: true,
            onUpgrade: () => _openStripeCheckout('Unlimited'),
            onManage: _manage,
          ),
          const SizedBox(height: AppTheme.spacingMd),

          // ── Per-property add-on (for Essential subscribers) ──────────────
          _PropertyAddOnCard(
            onTap: () => _launchPayment(_stripePropertyAddOn),
          ),
          const SizedBox(height: AppTheme.spacingLg),

          // ── Done for You add-on ──────────────────────────────────────────
          _AddOnCard(onTap: () => _showSetupDialog(context)),
          const SizedBox(height: AppTheme.spacingLg),

          // ── Support callout ──────────────────────────────────────────────
          _SupportCallout(colors: colors, theme: theme),
          const SizedBox(height: AppTheme.spacingLg),

          // ── Comparison table ─────────────────────────────────────────────
          _ComparisonTable(colors: colors, theme: theme),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  // Landlord plan links live in billing_rules.dart. These two are unchanged.
  static const _stripeEssentialMonthly = stripeEssentialMonthlyLink;
  static const _stripeEssentialAnnual = stripeEssentialAnnualLink;
  static const _stripeUnlimitedMonthly = stripeUnlimitedMonthlyLink;
  static const _stripeUnlimitedAnnual = stripeUnlimitedAnnualLink;
  static const _stripeDoneForYou = 'https://buy.stripe.com/3cI3cocPufN4dtO7tt67S0j';
  static const _stripePropertyAddOn = 'https://buy.stripe.com/4gMcMY8ze0Sa1L629967S0i';

  Future<void> _openStripeCheckout(String plan) async {
    final String url;
    if (plan == 'Essential') {
      url = _isAnnual ? _stripeEssentialAnnual : _stripeEssentialMonthly;
    } else {
      url = _isAnnual ? _stripeUnlimitedAnnual : _stripeUnlimitedMonthly;
    }
    await _launchPayment(url);
  }

  void _showSetupDialog(BuildContext context) {
    HapticFeedback.lightImpact();
    final colors = Theme.of(context).extension<ElevoColors>()!;
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(LucideIcons.sparkles, color: colors.gold, size: 20),
            const SizedBox(width: AppTheme.spacingSm),
            const Text('Done for You Setup'),
          ],
        ),
        content: Text(
          'The Elevo team will configure all your properties, upload your documents, '
          'send tenant invitations, and run a 1-hour onboarding call — all for a one-time '
          'fee of \$249.\n\nWe\'ll reach out within one business day to get started.',
          style: theme.textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _launchPayment(_stripeDoneForYou);
            },
            child: const Text('Get Set Up for Me — \$249'),
          ),
        ],
      ),
    );
  }

}

// ── Trial badge ───────────────────────────────────────────────────────────────

class _AccountPlanBanner extends StatelessWidget {
  final ElevoColors colors;
  final ThemeData theme;
  final String title;
  final String detail;
  final VoidCallback onManage;

  const _AccountPlanBanner({
    required this.colors,
    required this.theme,
    required this.title,
    required this.detail,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.charcoal,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.gold.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall?.copyWith(color: colors.goldInk)),
          const SizedBox(height: 4),
          Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: colors.ivory)),
          const SizedBox(height: AppTheme.spacingSm),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.ivory,
              side: BorderSide(color: colors.ivory.withAlpha(160)),
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              onManage();
            },
            child: const Text('Manage Subscription'),
          ),
        ],
      ),
    );
  }
}

class _TrialBadge extends StatelessWidget {
  final ElevoColors colors;
  final ThemeData theme;
  final String detail;

  const _TrialBadge({
    required this.colors,
    required this.theme,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.olive, colors.shade],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.gold.withAlpha(120)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.gold.withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.clock, color: colors.gold, size: 20),
          ),
          const SizedBox(width: AppTheme.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Trial active',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: colors.goldInk)),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onOlive),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Annual value banner (shown before toggle — no word "switch") ──────────────

class _AnnualValueBanner extends StatelessWidget {
  final ElevoColors colors;
  final ThemeData theme;
  final bool isAnnual;
  final ValueChanged<bool> onToggle;

  const _AnnualValueBanner({
    required this.colors,
    required this.theme,
    required this.isAnnual,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (isAnnual) {
      // Annual is active — confirm the value they're getting
      return Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMd, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colors.gold.withAlpha(40), colors.gold.withAlpha(15)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: colors.gold.withAlpha(100)),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.badgeCheck, color: colors.gold, size: 16),
            const SizedBox(width: AppTheme.spacingSm),
            Expanded(
              child: Text(
                'Annual plan selected — save up to \$249/yr.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.ink, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    // Monthly is active — show savings opportunity without saying "switch"
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onToggle(true);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMd, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colors.gold.withAlpha(30), colors.gold.withAlpha(10)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: colors.gold.withAlpha(80)),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.tag, color: colors.gold, size: 16),
            const SizedBox(width: AppTheme.spacingSm),
            Expanded(
              child: Text(
                'Save up to \$249/yr on an annual plan. Essential saves \$180.88/yr.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.gold, fontWeight: FontWeight.w600),
              ),
            ),
            Icon(LucideIcons.chevronRight, color: colors.gold, size: 16),
          ],
        ),
      ),
    );
  }
}

// ── Billing toggle ────────────────────────────────────────────────────────────

class _BillingToggle extends StatelessWidget {
  final bool isAnnual;
  final ValueChanged<bool> onChanged;

  const _BillingToggle({required this.isAnnual, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: colors.stone),
      ),
      child: Row(
        children: [
          _ToggleOption(
            label: 'Annual',
            selected: isAnnual,
            badge: 'Best Value',
            onTap: () {
              HapticFeedback.lightImpact();
              onChanged(true);
            },
          ),
          _ToggleOption(
            label: 'Monthly',
            selected: !isAnnual,
            onTap: () {
              HapticFeedback.lightImpact();
              onChanged(false);
            },
          ),
        ],
      ),
    );
  }
}

class _ToggleOption extends StatelessWidget {
  final String label;
  final bool selected;
  final String? badge;
  final VoidCallback onTap;

  const _ToggleOption({
    required this.label,
    required this.selected,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ElevoColors>()!;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? colors.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? colors.midnight : colors.taupe,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w400,
                  fontSize: 14,
                ),
              ),
              if (badge != null && selected) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.midnight.withAlpha(60),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                        color: colors.midnight,
                        fontSize: 9,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Support callout ───────────────────────────────────────────────────────────

class _SupportCallout extends StatelessWidget {
  final ElevoColors colors;
  final ThemeData theme;

  const _SupportCallout({required this.colors, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.gold.withAlpha(15),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.gold.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.headphones, color: colors.gold, size: 22),
          const SizedBox(width: AppTheme.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('5-Day-a-Week Support Included on All Plans',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: colors.goldInk)),
                const SizedBox(height: 2),
                Text(
                  'Customer support is available Monday–Friday by email '
                  'for technical issues and account questions.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () {
                    launchUrl(Uri(scheme: 'mailto', path: 'hello@getelevo.app'));
                  },
                  child: Text(
                    'hello@getelevo.app',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.goldInk,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Feature model ─────────────────────────────────────────────────────────────

class _Feature {
  final String label;
  final bool included;

  const _Feature(this.label, this.included);
}

// ── Plan card ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final String name;
  final String planLabel;
  final String tagline;
  final double monthlyPrice;
  final double annualMonthlyEquiv;
  final double annualTotalPrice;
  final bool isAnnual;
  final bool isCurrent;
  final bool isOnTrial;
  final bool isHighlighted;
  final bool isMostPopular;
  final String? savingsBadge;
  final String? trialBadge;
  final List<_Feature> features;
  final String ctaCopy;
  final bool showTrialDisclaimer;
  final VoidCallback? onUpgrade;
  final VoidCallback? onManage;

  const _PlanCard({
    required this.name,
    required this.planLabel,
    required this.tagline,
    required this.monthlyPrice,
    required this.annualMonthlyEquiv,
    required this.annualTotalPrice,
    required this.isAnnual,
    required this.isCurrent,
    required this.isOnTrial,
    this.isHighlighted = false,
    this.isMostPopular = false,
    this.savingsBadge,
    this.trialBadge,
    required this.features,
    required this.ctaCopy,
    this.showTrialDisclaimer = false,
    required this.onUpgrade,
    this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    final effectiveMonthly =
        isAnnual ? annualMonthlyEquiv : monthlyPrice;

    final onPlan = isHighlighted ? colors.onOlive : colors.ink;
    return Container(
      decoration: BoxDecoration(
        color: isHighlighted ? colors.olive : colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(
          color: isCurrent || isOnTrial
              ? colors.gold
              : isHighlighted
                  ? colors.olive
                  : colors.stone,
          width: isCurrent || isOnTrial || isHighlighted ? 2 : 1,
        ),
        boxShadow: AppTheme.cardShadow(colors),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label bar
          if (isMostPopular || (!isHighlighted))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isMostPopular
                    ? colors.gold
                    : colors.taupe.withAlpha(30),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppTheme.radiusXl),
                  topRight: Radius.circular(AppTheme.radiusXl),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isMostPopular) ...[
                    Icon(LucideIcons.crown,
                        size: 13, color: colors.midnight),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    planLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isMostPopular ? colors.midnight : colors.taupe,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                name,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: isHighlighted
                                      ? colors.onOlive
                                      : colors.ink,
                                ),
                              ),
                              if (isCurrent) ...[
                                const SizedBox(width: AppTheme.spacingSm),
                                _Badge(
                                    label: 'Current Plan',
                                    bg: colors.gold,
                                    fg: colors.midnight),
                              ],
                              if (isOnTrial) ...[
                                const SizedBox(width: AppTheme.spacingSm),
                                _Badge(
                                    label: '7-Day Trial',
                                    bg: colors.warningAmber,
                                    fg: colors.midnight),
                              ],
                            ],
                          ),
                          Text(tagline, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    if (savingsBadge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.successGreen.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: colors.successGreen.withAlpha(80)),
                        ),
                        child: Text(
                          savingsBadge!,
                          style: TextStyle(
                              color: colors.successGreen,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingMd),

                // Price display
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: fmt.format(effectiveMonthly),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: isHighlighted
                                  ? colors.onOlive
                                  : colors.ink,
                              fontSize: 34,
                            ),
                          ),
                          TextSpan(
                            text: '/mo',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (isAnnual) ...[
                      const SizedBox(width: AppTheme.spacingSm),
                      Expanded(
                        child: Text(
                          'billed ${fmt.format(annualTotalPrice)}/yr',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colors.taupe),
                        ),
                      ),
                    ],
                  ],
                ),

                if (trialBadge != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    trialBadge!,
                    style: TextStyle(
                        color: colors.warningAmber,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
                ],

                const SizedBox(height: AppTheme.spacingMd),
                Divider(color: colors.taupe.withAlpha(30), height: 1),
                const SizedBox(height: AppTheme.spacingMd),

                // Features list
                ...features.map((f) => Padding(
                      padding:
                          const EdgeInsets.only(bottom: AppTheme.spacingSm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(
                              f.included
                                  ? LucideIcons.check
                                  : LucideIcons.x,
                              size: 14,
                              color: f.included
                                  ? colors.successGreen
                                  : colors.taupe.withAlpha(80),
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacingSm),
                          Expanded(
                            child: Text(
                              f.label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: f.included
                                    ? onPlan
                                    : colors.sage.withAlpha(isHighlighted ? 180 : 140),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),

                const SizedBox(height: AppTheme.spacingMd),

                if (!isCurrent && onUpgrade != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        onUpgrade!();
                      },
                      style: ElevatedButton.styleFrom(
                              backgroundColor: isHighlighted
                                  ? colors.olive
                                  : colors.card,
                              foregroundColor: isHighlighted
                                  ? colors.onOlive
                                  : colors.ink,
                              side: isHighlighted
                                  ? BorderSide.none
                                  : BorderSide(color: colors.stone),
                            ),
                      child: Text(ctaCopy),
                    ),
                  ),
                  if (showTrialDisclaimer) ...[
                    const SizedBox(height: 6),
                    Text(
                      'A card is collected when you start. It is charged when the 7-day trial ends. Cancel anytime before it ends.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.sage,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ] else if (isCurrent)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        onManage?.call();
                      },
                      child: const Text('Manage Subscription'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _Badge({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

// ── Per-property pricing note ─────────────────────────────────────────────────

class _PerPropertyNote extends StatelessWidget {
  final ElevoColors colors;
  final ThemeData theme;

  const _PerPropertyNote({required this.colors, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.charcoal,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.taupe.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.building2, size: 16, color: colors.gold),
              const SizedBox(width: AppTheme.spacingSm),
              Text('Essential — How Pricing Works',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: colors.ivory)),
            ],
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Text(
            'Essential is 1 property. '
            'Each extra property is \$12.99/mo.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.ivory),
          ),
          const SizedBox(height: AppTheme.spacingMd),

          _PricingRow('1 property', '\$39.99/mo', colors, theme,
              highlight: false),
          _PricingRow('2 properties (+1 property)', '\$52.98/mo', colors, theme,
              highlight: false),
          _PricingRow('3 properties (+2 properties)', '\$65.97/mo', colors, theme,
              highlight: false),
          _PricingRow('Unlimited properties', 'Upgrade to Unlimited ↓', colors, theme,
              highlight: true),

          const SizedBox(height: AppTheme.spacingMd),

          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMd, vertical: 10),
            decoration: BoxDecoration(
              color: colors.gold.withAlpha(15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.gold.withAlpha(50)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(LucideIcons.trendingUp,
                      size: 14, color: colors.gold),
                ),
                const SizedBox(width: AppTheme.spacingSm),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.ivory),
                      children: [
                        const TextSpan(
                            text: 'Need unlimited properties? Unlimited plan is only '),
                        TextSpan(
                          text: '\$79/mo',
                          style: TextStyle(
                              color: colors.gold,
                              fontWeight: FontWeight.w700),
                        ),
                        const TextSpan(
                            text:
                                ' — covers unlimited properties with no extra fees.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PricingRow extends StatelessWidget {
  final String label;
  final String price;
  final ElevoColors colors;
  final ThemeData theme;
  final bool highlight;

  const _PricingRow(this.label, this.price, this.colors, this.theme,
      {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: highlight
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
          : EdgeInsets.zero,
      decoration: highlight
          ? BoxDecoration(
              color: colors.gold.withAlpha(15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.gold.withAlpha(60)),
            )
          : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: highlight ? colors.ivory : null,
                  fontWeight:
                      highlight ? FontWeight.w600 : FontWeight.normal,
                )),
          ),
          const SizedBox(width: AppTheme.spacingSm),
          Text(price,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.gold, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Property add-on card (below Unlimited) ────────────────────────────────────

class _PropertyAddOnCard extends StatelessWidget {
  final VoidCallback onTap;

  const _PropertyAddOnCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.charcoal,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.taupe.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.plusCircle, size: 18, color: colors.gold),
              const SizedBox(width: AppTheme.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add one property — Essential add-on',
                      style: theme.textTheme.titleSmall?.copyWith(color: colors.ivory),
                    ),
                    Text(
                      r'$12.99/mo',
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.taupe),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMd),
          Text(
            'Essential includes one property. Each checkout adds one more property at \$12.99 per month. '
            'Tap again to add another. This add-on is monthly only.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.ivory),
          ),
          const SizedBox(height: AppTheme.spacingMd),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                onTap();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.olive,
                foregroundColor: colors.onOlive,
              ),
              child: const Text(r'Add one property — $12.99/mo'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddOnCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddOnCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.olive, colors.shade],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.gold.withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.sparkles, color: colors.gold, size: 22),
              const SizedBox(width: AppTheme.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Done for You — We Handle Everything',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: colors.goldInk)),
                    Text(
                      'One-time add-on. Works with any plan.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.ivory),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.gold,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('\$249',
                    style: TextStyle(
                        color: colors.midnight,
                        fontWeight: FontWeight.w800,
                        fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMd),
          Text(
            'The Elevo team configures all your properties, uploads your '
            'existing documents, sends tenant invitation emails, and runs a 1-hour '
            'onboarding call — so you\'re managing from day one, not day ten.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.ivory),
          ),
          const SizedBox(height: AppTheme.spacingMd),
          ...const [
            'All properties configured',
            'All documents uploaded & organized',
            'Tenant invitation emails sent',
            '1-hour onboarding call with Elevo team',
            'Mon–Fri ongoing support included',
          ].map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(LucideIcons.check, size: 14, color: colors.gold),
                    const SizedBox(width: AppTheme.spacingSm),
                    Text(item,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.ivory)),
                  ],
                ),
              )),
          const SizedBox(height: AppTheme.spacingMd),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                onTap();
              },
              icon:
                  Icon(LucideIcons.sparkles, size: 18, color: colors.onOlive),
              label: const Text('Get Set Up for Me — \$249'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Comparison table ──────────────────────────────────────────────────────────

class _ComparisonTable extends StatelessWidget {
  final ElevoColors colors;
  final ThemeData theme;

  const _ComparisonTable({required this.colors, required this.theme});

  @override
  Widget build(BuildContext context) {
    final rows = _tableRows();
    return Container(
      decoration: AppTheme.surfaceCard(colors),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMd, vertical: 14),
            decoration: BoxDecoration(
              color: colors.olive,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppTheme.radiusXl),
                topRight: Radius.circular(AppTheme.radiusXl),
              ),
            ),
            child: Row(
              children: [
                const Expanded(flex: 4, child: SizedBox()),
                Expanded(
                  flex: 2,
                  child: Text('Essential',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: colors.ivory, fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Unlimited',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: colors.gold, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),

          // Feature rows
          ...rows.asMap().entries.map((entry) {
            final i   = entry.key;
            final row = entry.value;
            final isLast = i == rows.length - 1;

            return Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingMd, vertical: 11),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: colors.taupe.withAlpha(25)),
                  bottom: isLast
                      ? BorderSide.none
                      : BorderSide(color: colors.taupe.withAlpha(10)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(row[0],
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.ink)),
                  ),
                  Expanded(
                    flex: 2,
                    child: _TableCell(value: row[1], colors: colors, theme: theme),
                  ),
                  Expanded(
                    flex: 2,
                    child: _TableCell(
                        value: row[2], colors: colors, theme: theme,
                        isHighlighted: true),
                  ),
                ],
              ),
            );
          }),

          // Footer
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            decoration: BoxDecoration(
              color: colors.midnight.withAlpha(40),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(AppTheme.radiusMedium),
                bottomRight: Radius.circular(AppTheme.radiusMedium),
              ),
              border: Border(
                top: BorderSide(color: colors.taupe.withAlpha(30)),
              ),
            ),
            child: Text(
              '7-day trial · Card collected now, charged after the trial · Cancel anytime',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.taupe),
            ),
          ),
        ],
      ),
    );
  }

  List<List<String>> _tableRows() => [
        ['Properties included', '1', 'No limit'],
        ['Extra property', '\$12.99/mo each', 'Included'],
        ['Tenant messaging', '✓', '✓'],
        ['Maintenance + vendors', '✓', '✓'],
        ['Document storage', '10 GB', 'Unlimited'],
        ['Tenant screening', '✓', '✓'],
        ['P&L reports (PDF)', '✓', '✓'],
        ['Calendar & alerts', '✓', '✓'],
        ['Support', 'Mon–Fri', 'Priority'],
        ['Done-for-You setup', 'Add-on', 'Add-on'],
      ];
}

class _TableCell extends StatelessWidget {
  final String value;
  final ElevoColors colors;
  final ThemeData theme;
  final bool isHighlighted;

  const _TableCell({
    required this.value,
    required this.colors,
    required this.theme,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final isCheck = value == '✓';
    final isDash = value == '–';

    return Center(
      child: isCheck
          ? Icon(LucideIcons.check,
              size: 15,
              color: isHighlighted ? colors.gold : colors.successGreen)
          : isDash
              ? Icon(LucideIcons.minus,
                  size: 15, color: colors.taupe.withAlpha(80))
              : Text(
                  value,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isHighlighted ? colors.gold : colors.ink,
                    fontWeight: isHighlighted
                        ? FontWeight.w600
                        : FontWeight.normal,
                    fontSize: 11,
                  ),
                ),
    );
  }
}
