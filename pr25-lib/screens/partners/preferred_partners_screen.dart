import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/partner_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/partner_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/partners/basic_partner_card.dart';
import '../../widgets/partners/featured_partner_card.dart';
import '../../widgets/partners/partner_message_sheet.dart';
import '../../widgets/partners/platinum_partner_card.dart';
import '../../widgets/partners/preferred_partner_card.dart';

class PreferredPartnersScreen extends StatefulWidget {
  const PreferredPartnersScreen({super.key});

  @override
  State<PreferredPartnersScreen> createState() => _PreferredPartnersScreenState();
}

class _PreferredPartnersScreenState extends State<PreferredPartnersScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PartnerProvider>().loadListings();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showMessageSheet(PartnerListing listing) {
    PartnerMessageSheet.show(context, listing);
  }

  Future<void> _launchVendorEmail() async {
    final uri = Uri.parse('mailto:vendors@getelevo.app?subject=Vendor%20Concern%20Report');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  Future<void> _launchJoinEmail() async {
    const subject = 'Preferred%20Vendor%20Inquiry';
    const body =
        'Thank%20you%20for%20your%20interest%20in%20joining.%20'
        'We%20will%20be%20in%20contact%20soon%20with%20details%20'
        'on%20our%20preferred%20vendor%20tiers%20and%20options.';
    final uri = Uri.parse('mailto:vendors@getelevo.app?subject=$subject&body=$body');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  Future<void> _launchWaitlistEmail({String? category, bool isPlatinum = false}) async {
    final subject = isPlatinum
        ? 'Platinum%20Vendor%20Waitlist'
        : 'Preferred%20Vendor%20Waitlist${category != null ? '%20%E2%80%94%20$category' : ''}';
    final body = isPlatinum
        ? 'I%20would%20like%20to%20be%20added%20to%20the%20Platinum%20vendor%20waitlist.%20'
          'Please%20notify%20me%20as%20soon%20as%20a%20spot%20becomes%20available.'
        : 'I%20would%20like%20to%20be%20added%20to%20the%20Preferred%20vendor%20waitlist'
          '${category != null ? '%20for%20the%20$category%20category' : ''}.%20'
          'Please%20notify%20me%20as%20soon%20as%20a%20spot%20becomes%20available.';
    final uri = Uri.parse('mailto:vendors@getelevo.app?subject=$subject&body=$body');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final provider = context.watch<PartnerProvider>();
    final auth = context.watch<AuthProvider>();
    final userId = auth.currentUser?.id ?? '';
    final isVendor = auth.currentUser?.isVendor ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preferred Partners'),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => context.pop(),
        ),
      ),
      body: provider.isLoading
          ? Center(child: CircularProgressIndicator(color: colors.gold))
          : CustomScrollView(
              slivers: [
                // ── Search bar ─────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppTheme.spacingMd, AppTheme.spacingMd, AppTheme.spacingMd, 0),
                    child: TextField(
                      controller: _searchCtrl,
                      style: TextStyle(color: colors.ink),
                      decoration: InputDecoration(
                        hintText: 'Search vendors…',
                        prefixIcon: Icon(LucideIcons.search, color: colors.sage, size: 18),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(LucideIcons.x, color: colors.sage, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  provider.setSearch('');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      ),
                      onChanged: provider.setSearch,
                    ),
                  ),
                ),

                // ── Category filter chips ──────────────────────────────────
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 52,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm),
                      itemCount: kPartnerCategories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: AppTheme.spacingXs),
                      itemBuilder: (ctx, i) {
                        final cat = kPartnerCategories[i];
                        final selected = provider.selectedCategory == cat;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            provider.setCategory(cat);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: selected ? colors.olive : colors.card,
                              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                              border: Border.all(
                                color: selected ? colors.olive : colors.stone,
                              ),
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                color: selected ? colors.onOlive : colors.ink,
                                fontSize: 13,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // ── Vendor list ────────────────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  sliver: _buildListings(
                    context,
                    provider,
                    colors,
                    theme,
                    userId,
                    platinumFull: provider.isPlatinumFull,
                    preferredFullCategories: provider.preferredFullCategories,
                    isVendor: isVendor,
                  ),
                ),

                // ── Disclaimer ─────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingMd),
                    child: Column(
                      children: [
                        Divider(color: colors.stone.withAlpha(80)),
                        const SizedBox(height: AppTheme.spacingSm),
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: TextStyle(color: colors.sage, fontSize: 11, height: 1.5),
                            children: [
                              const TextSpan(
                                text:
                                    'Preferred vendors are independent businesses. Elevo may review a listing before it is shown. '
                                    'That review is not a background check, and Elevo does not guarantee the vendor\'s work or licensing. '
                                    'Elevo is not affiliated with, employed by, or financially responsible for any listed vendor. '
                                    'Vendor tiers are paid arrangements. Payment does not influence reviews or ratings. '
                                    'To report a vendor concern contact ',
                              ),
                              WidgetSpan(
                                child: GestureDetector(
                                  onTap: _launchVendorEmail,
                                  child: Text(
                                    'vendors@getelevo.app',
                                    style: TextStyle(
                                      color: colors.gold,
                                      fontSize: 11,
                                      decoration: TextDecoration.underline,
                                      decorationColor: colors.gold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacingXs),
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: TextStyle(color: colors.sage, fontSize: 11, height: 1.5),
                            children: [
                              const TextSpan(
                                text: 'Interested in becoming a preferred vendor? Email us at ',
                              ),
                              WidgetSpan(
                                child: GestureDetector(
                                  onTap: _launchJoinEmail,
                                  child: Text(
                                    'vendors@getelevo.app',
                                    style: TextStyle(
                                      color: colors.gold,
                                      fontSize: 11,
                                      decoration: TextDecoration.underline,
                                      decorationColor: colors.gold,
                                    ),
                                  ),
                                ),
                              ),
                              const TextSpan(text: '.'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildListings(
    BuildContext context,
    PartnerProvider provider,
    ElevoColors colors,
    ThemeData theme,
    String userId, {
    required bool platinumFull,
    required Set<String> preferredFullCategories,
    required bool isVendor,
  }) {
    final listings = provider.filteredListings;

    if (listings.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.building2, color: colors.stone, size: 40),
              const SizedBox(height: AppTheme.spacingMd),
              Text('No vendors found', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    // When "All" selected — group by category
    if (provider.selectedCategory == 'All') {
      final grouped = provider.listingsByCategory;
      final categories = grouped.keys.toList()..sort();

      // Check if a platinum section exists in the grouped results
      final hasPlatinumListings =
          listings.any((l) => l.tier == PartnerTier.platinum);

      final widgets = <Widget>[];

      // Global Platinum waitlist banner — vendors only
      if (isVendor && platinumFull && hasPlatinumListings) {
        widgets.add(_WaitlistBanner(
          message: 'Platinum is currently full — only 2 spots available.',
          onNotify: () => _launchWaitlistEmail(isPlatinum: true),
          colors: colors,
        ));
        widgets.add(const SizedBox(height: AppTheme.spacingMd));
      }

      for (final cat in categories) {
        final catListings = grouped[cat]!;
        final catHasPreferred =
            catListings.any((l) => l.tier == PartnerTier.preferred);
        final catPreferredFull =
            catHasPreferred && preferredFullCategories.contains(cat);

        // Category header
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spacingSm),
          child: Text(
            cat.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.midnight,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              fontSize: 11,
            ),
          ),
        ));

        // Per-category Preferred waitlist banner — vendors only
        if (isVendor && catPreferredFull) {
          widgets.add(_WaitlistBanner(
            message: 'Preferred spots in $cat are full — 2 of 2 taken.',
            onNotify: () =>
                _launchWaitlistEmail(category: cat, isPlatinum: false),
            colors: colors,
          ));
          widgets.add(const SizedBox(height: AppTheme.spacingSm));
        }

        for (final listing in catListings) {
          widgets.add(_buildCard(context, listing, userId));
        }
        widgets.add(const SizedBox(height: AppTheme.spacingMd));
      }

      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => widgets[i],
          childCount: widgets.length,
        ),
      );
    }

    // Single category filter
    final cat = provider.selectedCategory;
    final catPreferredFull = preferredFullCategories.contains(cat);
    final filterHasPreferred =
        listings.any((l) => l.tier == PartnerTier.preferred);

    final widgets = <Widget>[];

    // Platinum banner — vendors only
    if (isVendor && platinumFull && listings.any((l) => l.tier == PartnerTier.platinum)) {
      widgets.add(_WaitlistBanner(
        message: 'Platinum is currently full — only 2 spots available.',
        onNotify: () => _launchWaitlistEmail(isPlatinum: true),
        colors: colors,
      ));
      widgets.add(const SizedBox(height: AppTheme.spacingSm));
    }

    // Preferred banner for this specific category — vendors only
    if (isVendor && catPreferredFull && filterHasPreferred) {
      widgets.add(_WaitlistBanner(
        message: 'Preferred spots in $cat are full — 2 of 2 taken.',
        onNotify: () =>
            _launchWaitlistEmail(category: cat, isPlatinum: false),
        colors: colors,
      ));
      widgets.add(const SizedBox(height: AppTheme.spacingSm));
    }

    for (final listing in listings) {
      widgets.add(_buildCard(context, listing, userId));
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, i) => widgets[i],
        childCount: widgets.length,
      ),
    );
  }

  Widget _buildCard(BuildContext context, PartnerListing listing, String userId) {
    final provider = context.read<PartnerProvider>();
    switch (listing.tier) {
      case PartnerTier.platinum:
        return PlatinumPartnerCard(
          listing: listing,
          onMessage: () => _showMessageSheet(listing),
          onCallTap: () =>
              provider.logContact(vendorId: listing.id, userId: userId, type: 'call'),
          onEmailTap: () =>
              provider.logContact(vendorId: listing.id, userId: userId, type: 'email'),
        );
      case PartnerTier.preferred:
        return PreferredPartnerCard(
          listing: listing,
          onMessage: () => _showMessageSheet(listing),
          onCallTap: () =>
              provider.logContact(vendorId: listing.id, userId: userId, type: 'call'),
          onEmailTap: () =>
              provider.logContact(vendorId: listing.id, userId: userId, type: 'email'),
        );
      case PartnerTier.featured:
        return FeaturedPartnerCard(
          listing: listing,
          onCallTap: () =>
              provider.logContact(vendorId: listing.id, userId: userId, type: 'call'),
        );
      case PartnerTier.basic:
        return BasicPartnerCard(
          listing: listing,
          onCallTap: () =>
              provider.logContact(vendorId: listing.id, userId: userId, type: 'call'),
        );
    }
  }
}

// ── Waitlist banner widget ────────────────────────────────────────────────────

class _WaitlistBanner extends StatelessWidget {
  const _WaitlistBanner({
    required this.message,
    required this.onNotify,
    required this.colors,
  });

  final String message;
  final VoidCallback onNotify;
  final ElevoColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm + 2),
      decoration: BoxDecoration(
        color: colors.gold.withAlpha(20),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.gold.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(LucideIcons.bell, size: 16, color: colors.gold),
          const SizedBox(width: AppTheme.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Get notified as soon as a spot opens up.',
                  style: TextStyle(color: colors.sage, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacingSm),
          OutlinedButton(
            onPressed: onNotify,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.midnight,
              side: BorderSide(color: colors.midnight.withAlpha(160)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              textStyle: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600),
            ),
            child: const Text('Join Waitlist'),
          ),
        ],
      ),
    );
  }
}
