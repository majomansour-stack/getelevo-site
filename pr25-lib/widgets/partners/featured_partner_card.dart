import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/partner_model.dart';
import '../../theme/theme.dart';

class FeaturedPartnerCard extends StatelessWidget {
  final PartnerListing listing;
  final VoidCallback? onCallTap;

  const FeaturedPartnerCard({
    super.key,
    required this.listing,
    this.onCallTap,
  });

  Future<void> _call() async {
    final uri = Uri(scheme: 'tel', path: listing.phone.replaceAll(RegExp(r'\D'), ''));
    if (await canLaunchUrl(uri)) launchUrl(uri);
    onCallTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingSm),
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.stone.withAlpha(120)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        listing.businessName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    // Featured badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.oliveTint,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: colors.stone),
                      ),
                      child: Text(
                        'Featured',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(listing.category, style: theme.textTheme.labelSmall),
                if (listing.reviewCount > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      ...List.generate(5, (i) => Icon(
                        LucideIcons.star,
                        color: i < listing.rating.floor() ? colors.gold : colors.stone,
                        size: 11,
                      )),
                      const SizedBox(width: 4),
                      Text(
                        listing.rating.toStringAsFixed(1),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
                if (listing.description != null) ...[
                  const SizedBox(height: AppTheme.spacingXs),
                  Text(
                    listing.description!.length > 60
                        ? '${listing.description!.substring(0, 60)}…'
                        : listing.description!,
                    style: theme.textTheme.labelSmall?.copyWith(color: colors.ink),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacingMd),
          // Call button
          OutlinedButton.icon(
            onPressed: _call,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              foregroundColor: colors.midnight,
              backgroundColor: Colors.transparent,
              side: BorderSide(color: colors.midnight.withAlpha(80)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
            ),
            icon: Icon(LucideIcons.phone, size: 13, color: colors.midnight),
            label: Text(
              'Call',
              style: TextStyle(color: colors.midnight, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
