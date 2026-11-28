import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/partner_model.dart';
import '../../theme/theme.dart';

class BasicPartnerCard extends StatelessWidget {
  final PartnerListing listing;
  final VoidCallback? onCallTap;

  const BasicPartnerCard({
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
      margin: const EdgeInsets.only(bottom: AppTheme.spacingXs),
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm + 4),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.stone.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.building2, color: colors.sage, size: 20),
          const SizedBox(width: AppTheme.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.businessName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(listing.category, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          // ELEVO badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: colors.oliveTint,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              'ELEVO',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacingSm),
          // Phone button
          GestureDetector(
            onTap: _call,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(LucideIcons.phone, color: theme.colorScheme.onSurface, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
