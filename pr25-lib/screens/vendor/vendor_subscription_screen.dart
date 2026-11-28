import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/billing_rules.dart';
import '../../models/partner_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/stripe_checkout.dart';
import '../../widgets/account/change_password_sheet.dart';
import '../../widgets/account/delete_account_dialog.dart';
import '../../providers/partner_provider.dart' show kPlatinumMaxSpots, kPreferredMaxSpotsPerCategory;
import '../../services/partner_service.dart';
import '../../theme/theme.dart';
import '../../widgets/settings/appearance_setting.dart';

// ─── Tier data model ──────────────────────────────────────────────────────────

enum _VendorTier { basic, featured, preferred, platinum }

class _TierInfo {
  final _VendorTier tier;
  final String name;
  final double monthlyPrice;
  final String badge;
  final bool isMostPopular;
  final List<String> features;
  const _TierInfo({
    required this.tier,
    required this.name,
    required this.monthlyPrice,
    required this.badge,
    required this.features,
    this.isMostPopular = false,
  });
}

const _tiers = [
  _TierInfo(
    tier: _VendorTier.basic,
    name: 'Basic',
    monthlyPrice: 39.99,
    badge: 'Basic',
    features: [
      'Listed in your trade category',
      'Name and phone visible to all users',
      'Access to tenant and landlord contacts',
      'No setup fee',
    ],
  ),
  _TierInfo(
    tier: _VendorTier.featured,
    name: 'Featured',
    monthlyPrice: 89.99,
    badge: 'Featured',
    features: [
      'Everything in Basic',
      'Company logo displayed',
      'Business description up to 60 characters',
      'Star rating and reviews displayed',
      'Featured badge on your listing',
    ],
  ),
  _TierInfo(
    tier: _VendorTier.preferred,
    name: 'Preferred',
    monthlyPrice: 149,
    badge: 'ELEVO Preferred',
    isMostPopular: true,
    features: [
      'Everything in Featured',
      'Top placement above Featured & Basic',
      'Extended description up to 80 characters',
      'Direct in-app message button',
      'ELEVO Preferred gold badge',
    ],
  ),
  _TierInfo(
    tier: _VendorTier.platinum,
    name: 'Platinum',
    monthlyPrice: 199,
    badge: 'ELEVO Platinum',
    features: [
      'Everything in Preferred',
      'Guaranteed first position in category',
      'Premium dark navy card with gold border',
      'ELEVO Platinum gold badge',
      'Priority application review within 24 hours',
    ],
  ),
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class VendorSubscriptionScreen extends StatefulWidget {
  const VendorSubscriptionScreen({super.key});

  @override
  State<VendorSubscriptionScreen> createState() => _VendorSubscriptionScreenState();
}

class _VendorSubscriptionScreenState extends State<VendorSubscriptionScreen> {
  /// Trade from signup metadata. Blank means we cannot tell if Preferred
  /// is full for this vendor, so that check is skipped.
  String _vendorCategory = '';

  // ── Verified Stripe live links for vendor tiers (confirmed June 2026) ───────
  static const _stripeBasic     = 'https://buy.stripe.com/dRmcMYdTy1WeahC3dd67S0h';
  static const _stripeFeatured  = 'https://buy.stripe.com/4gMfZacPu0SafBWeVV67S0g';
  static const _stripePreferred = 'https://buy.stripe.com/3cI14gbLq9oG9dyaFF67S0f';
  static const _stripePlatinum  = 'https://buy.stripe.com/8x214g6r630iblGfZZ67S0e';

  final _partnerService = PartnerService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<AuthProvider>().refreshProfile();
      final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
      final category = meta?['service_type']?.toString().trim() ?? '';
      if (mounted) setState(() => _vendorCategory = category);
    });
  }

  Future<void> _openStripeCheckout(String url) async {
    final user = context.read<AuthProvider>().currentUser;
    final opened = await openStripePaymentLink(
      link: url,
      userId: user?.id,
      email: user?.email,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the payment page.')),
      );
    }
  }

  Future<void> _manage() async {
    final error = await openBillingPortal();
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// Returns true when the requested tier has no open spots.
  bool _isTierFull(_TierInfo tier) {
    if (tier.tier == _VendorTier.platinum) {
      return _partnerService.isPlatinumFull;
    }
    if (tier.tier == _VendorTier.preferred) {
      if (_vendorCategory.isEmpty) return false;
      return _partnerService.isPreferredFullForCategory(_vendorCategory);
    }
    return false;
  }

  void _handleSelectTier(_TierInfo tier, _VendorTier? current) {
    if (current != null && tier.tier == current) return;
    HapticFeedback.mediumImpact();

    // If tier is at capacity → show waitlist dialog, no charge
    if (_isTierFull(tier)) {
      _showWaitlistDialog(tier);
      return;
    }

    final currentPrice = current == null
        ? 0.0
        : _tiers.firstWhere((t) => t.tier == current).monthlyPrice;
    final isUpgrade = current == null || tier.monthlyPrice > currentPrice;

    if (isUpgrade) {
      // All upgrades open Stripe checkout
      final stripeUrl = switch (tier.tier) {
        _VendorTier.basic     => _stripeBasic,
        _VendorTier.featured  => _stripeFeatured,
        _VendorTier.preferred => _stripePreferred,
        _VendorTier.platinum  => _stripePlatinum,
      };
      _openStripeCheckout(stripeUrl);
    } else {
      // Downgrade still requires checkbox confirmation
      showDialog<bool>(
        context: context,
        builder: (ctx) => _PlanChangeDialog(tier: tier, isUpgrade: false),
      ).then((confirmed) {
        if (confirmed == true && mounted) _manage();
      });
    }
  }

  void _showWaitlistDialog(_TierInfo tier) {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        title: Row(
          children: [
            Icon(LucideIcons.bellRing, size: 20, color: colors.linkOlive),
            const SizedBox(width: 8),
            Text(
              '${tier.name} Is Full',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.midnight,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tier.tier == _VendorTier.platinum
                  ? 'Platinum is limited to $kPlatinumMaxSpots spots across the entire directory and is currently full.'
                  : '${tier.name} in the ${_vendorCategory} category is limited to $kPreferredMaxSpotsPerCategory spots and is currently full.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.ink,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppTheme.spacingMd),
            Container(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              decoration: BoxDecoration(
                color: colors.oliveTint,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: colors.linkOlive.withAlpha(120)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.info, size: 15, color: colors.linkOlive),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Join the waitlist and we\'ll notify you as soon as a spot opens up. You will not be charged until a spot is confirmed.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.ink,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Not Now',
              style: TextStyle(color: colors.sage, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'You\'re on the ${tier.name} waitlist. We\'ll notify you when a spot opens.',
                  ),
                  backgroundColor: colors.charcoal,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.olive,
              foregroundColor: colors.onOlive,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
            ),
            child: const Text(
              'Join Waitlist',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  void _handleCancel() {
    HapticFeedback.mediumImpact();
    _manage();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    final tierName = vendorTierForPlan(user?.subscriptionPlan);
    final currentTier = tierName == null
        ? null
        : _VendorTier.values.firstWhere((tier) => tier.name == tierName);
    final currentTierInfo = currentTier == null
        ? null
        : _tiers.firstWhere((t) => t.tier == currentTier);
    final billingLine = user?.currentPeriodEnd == null
        ? 'No billing date yet'
        : 'Next billing: ${user!.currentPeriodEnd!.toLocal().month}/${user.currentPeriodEnd!.toLocal().day}/${user.currentPeriodEnd!.toLocal().year}';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'My Subscription',
          style: theme.textTheme.titleMedium?.copyWith(
            color: colors.midnight,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        children: [
          // ── Current plan summary ──────────────────────────────────────────
          _CurrentPlanCard(
            user: user,
            tier: currentTierInfo,
            statusLabel: vendorPlanStatusLabel(
              user?.subscriptionStatus,
              hasPaidPlan: currentTierInfo != null,
            ),
            billingLine: billingLine,
            colors: colors,
            theme: theme,
            onCancel: _handleCancel,
          ),
          const SizedBox(height: AppTheme.spacingLg),

          Text(
            'Available Plans',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.midnight,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Text(
            'All plans are billed monthly. Cancel anytime.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.sage),
          ),
          const SizedBox(height: AppTheme.spacingMd),

          // ── Tier cards ────────────────────────────────────────────────────
          ..._tiers.map((tier) => _TierCard(
                tier: tier,
                isCurrent: vendorTierIsCurrent(
                  plan: user?.subscriptionPlan,
                  status: user?.subscriptionStatus,
                  tier: tier.name.toLowerCase(),
                ),
                isFull: _isTierFull(tier),
                colors: colors,
                theme: theme,
                onSelect: () => _handleSelectTier(tier, currentTier),
              )),

          const SizedBox(height: AppTheme.spacingLg),

          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Profile'),
            subtitle: const Text('Name, phone, and email'),
            onTap: () => context.push('/account/profile'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Change Password'),
            onTap: () => showChangePasswordSheet(context),
          ),
          const AppearanceSetting(),
          const SizedBox(height: AppTheme.spacingLg),

          // ── Billing note ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            decoration: BoxDecoration(
              color: colors.stone.withAlpha(40),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: colors.stone),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.info, size: 16, color: colors.sage),
                const SizedBox(width: AppTheme.spacingSm),
                Expanded(
                  child: Text(
                    'Upgrades take effect immediately and your card is charged the new rate right away. '
                    'Downgrades take effect at the end of your current billing period — no refunds for unused time. '
                    'For full tiers, join the waitlist — you will not be charged until a spot is confirmed. '
                    'Questions? hello@getelevo.app.',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.sage, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingMd),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: () => context.push('/terms'),
                child: const Text('Terms of Service'),
              ),
              TextButton(
                onPressed: () => context.push('/privacy'),
                child: const Text('Privacy Policy'),
              ),
            ],
          ),
          TextButton(
            onPressed: () => confirmAndDeleteAccount(context),
            child: const Text('Delete account'),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ─── Current plan card ────────────────────────────────────────────────────────

class _CurrentPlanCard extends StatelessWidget {
  final dynamic user;
  final _TierInfo? tier;
  final String statusLabel;
  final String billingLine;
  final ElevoColors colors;
  final ThemeData theme;
  final VoidCallback onCancel;

  const _CurrentPlanCard({
    required this.user,
    required this.tier,
    required this.statusLabel,
    required this.billingLine,
    required this.colors,
    required this.theme,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isPlatinum = tier?.tier == _VendorTier.platinum;

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.charcoal,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: isPlatinum
            ? Border.all(color: colors.gold, width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: colors.midnight.withAlpha(20),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Plan',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.ivory.withAlpha(140),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tier?.name ?? 'No plan yet',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: colors.gold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      tier == null
                          ? 'Choose a plan below'
                          : '\$${formatVendorPrice(tier!.monthlyPrice)}/month',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.ivory.withAlpha(200),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: colors.olive,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Text(
                  statusLabel.toUpperCase(),
                  style: TextStyle(
                    color: colors.onOlive,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMd),
          Row(
            children: [
              Icon(LucideIcons.calendarClock, size: 14, color: colors.ivory.withAlpha(120)),
              const SizedBox(width: 6),
              Text(
                billingLine,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.ivory.withAlpha(160),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMd),
          OutlinedButton(
            onPressed: onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.ivory.withAlpha(180),
              side: BorderSide(color: colors.ivory.withAlpha(60)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              minimumSize: const Size(double.infinity, 40),
            ),
            child: const Text('Manage Subscription', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ─── Plan change dialog (stateful — checkbox required) ────────────────────────

class _PlanChangeDialog extends StatefulWidget {
  final _TierInfo tier;
  final bool isUpgrade;

  const _PlanChangeDialog({required this.tier, required this.isUpgrade});

  @override
  State<_PlanChangeDialog> createState() => _PlanChangeDialogState();
}

class _PlanChangeDialogState extends State<_PlanChangeDialog> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final price =
        '\$${formatVendorPrice(widget.tier.monthlyPrice)}/month';

    return AlertDialog(
      backgroundColor: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      title: Text(
        widget.isUpgrade
            ? 'Upgrade to ${widget.tier.name}'
            : 'Downgrade to ${widget.tier.name}',
        style: theme.textTheme.titleMedium?.copyWith(
          color: colors.midnight,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isUpgrade
                ? 'Your plan will change to ${widget.tier.name} at $price. '
                    'Your card will be charged immediately and the upgrade takes effect right away.'
                : 'Your plan will change to ${widget.tier.name} at $price. '
                    'Your current plan stays active until the end of this billing period. No refunds for unused time.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colors.ink, height: 1.5),
          ),
          const SizedBox(height: AppTheme.spacingMd),
          // ── Agreement checkbox ──────────────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _agreed = !_agreed),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _agreed,
                    onChanged: (v) => setState(() => _agreed = v ?? false),
                    activeColor: colors.midnight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: AppTheme.spacingSm),
                Expanded(
                  child: Text(
                    widget.isUpgrade
                        ? 'I understand my card will be charged $price immediately upon confirming this upgrade.'
                        : 'I agree to downgrade to ${widget.tier.name} at $price. My current plan stays active until end of billing period.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.ink,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Not now', style: TextStyle(color: colors.sage)),
        ),
        ElevatedButton(
          onPressed: _agreed ? () => Navigator.of(context).pop(true) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                widget.isUpgrade ? colors.olive : colors.urgentRed,
            disabledBackgroundColor: colors.stone,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
          ),
          child: Text(
            widget.isUpgrade ? 'Confirm Upgrade' : 'Confirm Downgrade',
            style: TextStyle(
              color: _agreed ? colors.onOlive : colors.sage,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Individual tier card ─────────────────────────────────────────────────────

class _TierCard extends StatelessWidget {
  final _TierInfo tier;
  final bool isCurrent;
  final bool isFull;
  final ElevoColors colors;
  final ThemeData theme;
  final VoidCallback onSelect;

  const _TierCard({
    required this.tier,
    required this.isCurrent,
    required this.isFull,
    required this.colors,
    required this.theme,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isPlatinum = tier.tier == _VendorTier.platinum;

    final cardBg = isPlatinum ? colors.charcoal : colors.card;
    final textColor = isPlatinum ? colors.ivory : colors.ink;
    final headlineColor = isPlatinum ? colors.gold : colors.midnight;
    final borderColor = isCurrent
        ? colors.gold
        : isPlatinum
            ? colors.gold.withAlpha(100)
            : colors.stone;
    final borderWidth = isCurrent || isPlatinum ? 1.5 : 1.0;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: isCurrent || isPlatinum
            ? [
                BoxShadow(
                  color: colors.gold.withAlpha(isPlatinum ? 30 : 20),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          // ── Header ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tier.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: headlineColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '\$${formatVendorPrice(tier.monthlyPrice)}',
                                  style: TextStyle(
                                    color: headlineColor,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'Sora',
                                  ),
                                ),
                                TextSpan(
                                  text: '/month',
                                  style: TextStyle(
                                    color: isPlatinum ? colors.ivory.withAlpha(160) : colors.sage,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (tier.isMostPopular)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: colors.olive,
                              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                            ),
                            child: Text(
                              'MOST POPULAR',
                              style: TextStyle(
                                color: colors.onOlive,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        if (isCurrent) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: colors.successGreen.withAlpha(25),
                              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                              border: Border.all(color: colors.successGreen.withAlpha(80)),
                            ),
                            child: Text(
                              'CURRENT',
                              style: TextStyle(
                                color: colors.successGreen,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: AppTheme.spacingMd),

                // ── Features ─────────────────────────────────────────
                ...tier.features.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            LucideIcons.check,
                            size: 14,
                            color: isPlatinum ? colors.gold : colors.midnight,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              f,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: textColor,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),

          // ── CTA ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacingMd,
              0,
              AppTheme.spacingMd,
              AppTheme.spacingMd,
            ),
            child: isCurrent
                // ── Current plan indicator ─────────────────────────────
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: colors.successGreen.withAlpha(20),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      border: Border.all(color: colors.successGreen.withAlpha(60)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.checkCircle, size: 16, color: colors.successGreen),
                        const SizedBox(width: 8),
                        Text(
                          'Your current plan',
                          style: TextStyle(
                            color: colors.successGreen,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : isFull
                    // ── Tier full — join waitlist ──────────────────────
                    ? OutlinedButton.icon(
                        onPressed: onSelect,
                        icon: Icon(LucideIcons.bellRing, size: 16, color: colors.linkOlive),
                        label: Text(
                          'Tier Full — Join Waitlist',
                          style: TextStyle(
                            color: colors.linkOlive,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44),
                          side: BorderSide(color: colors.linkOlive, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                          ),
                          backgroundColor: colors.oliveTint,
                        ),
                      )
                    // ── Available — select plan ────────────────────────
                    : ElevatedButton(
                        onPressed: onSelect,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.olive,
                          foregroundColor: colors.onOlive,
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Select ${tier.name}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
