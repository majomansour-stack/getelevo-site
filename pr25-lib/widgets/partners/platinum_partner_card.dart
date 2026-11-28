import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/partner_model.dart';
import '../../theme/theme.dart';

class PlatinumPartnerCard extends StatelessWidget {
  final PartnerListing listing;
  final VoidCallback? onMessage;
  final VoidCallback? onCallTap;
  final VoidCallback? onEmailTap;

  const PlatinumPartnerCard({
    super.key,
    required this.listing,
    this.onMessage,
    this.onCallTap,
    this.onEmailTap,
  });

  Future<void> _call() async {
    final uri = Uri(scheme: 'tel', path: listing.phone.replaceAll(RegExp(r'\D'), ''));
    if (await canLaunchUrl(uri)) launchUrl(uri);
    onCallTap?.call();
  }

  Future<void> _email() async {
    final uri = Uri(scheme: 'mailto', path: listing.email);
    if (await canLaunchUrl(uri)) launchUrl(uri);
    onEmailTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.charcoal,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: colors.gold, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: colors.gold.withAlpha(30),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Card header ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            child: Column(
              children: [
                // Badge + logo row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo placeholder
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: colors.gold.withAlpha(20),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                        border: Border.all(color: colors.gold.withAlpha(60)),
                      ),
                      child: listing.logoUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                              child: Image.network(listing.logoUrl!, fit: BoxFit.cover))
                          : Icon(LucideIcons.building2, color: colors.gold, size: 24),
                    ),
                    const SizedBox(width: AppTheme.spacingMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            listing.businessName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colors.gold,
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            listing.category,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.headerMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Platinum badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.gold,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                      ),
                      child: Text(
                        'ELEVO Platinum',
                        style: TextStyle(
                          color: colors.shade,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppTheme.spacingMd),

                // Star rating
                if (listing.reviewCount > 0)
                  Row(
                    children: [
                      ...List.generate(5, (i) => Icon(
                        i < listing.rating.floor()
                            ? LucideIcons.star
                            : LucideIcons.star,
                        color: i < listing.rating.floor()
                            ? colors.gold
                            : colors.gold.withAlpha(40),
                        size: 14,
                      )),
                      const SizedBox(width: AppTheme.spacingXs),
                      Text(
                        '${listing.rating.toStringAsFixed(1)} (${listing.reviewCount})',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.headerMuted,
                        ),
                      ),
                    ],
                  ),

                if (listing.description != null) ...[
                  const SizedBox(height: AppTheme.spacingSm),
                  Text(
                    listing.description!.length > 100
                        ? '${listing.description!.substring(0, 100)}…'
                        : listing.description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.ivory.withAlpha(200),
                    ),
                  ),
                ],

                const SizedBox(height: AppTheme.spacingMd),

                // Contact buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _call,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          foregroundColor: colors.gold,
                          backgroundColor: Colors.transparent,
                          side: BorderSide(color: colors.gold, width: 1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                          ),
                        ),
                        icon: Icon(LucideIcons.phone, size: 14, color: colors.gold),
                        label: Text(
                          listing.phone,
                          style: TextStyle(color: colors.gold, fontSize: 12, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingSm),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _email,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          foregroundColor: colors.gold,
                          backgroundColor: Colors.transparent,
                          side: BorderSide(color: colors.gold, width: 1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                          ),
                        ),
                        icon: Icon(LucideIcons.mail, size: 14, color: colors.gold),
                        label: Text(
                          'Email',
                          style: TextStyle(color: colors.gold, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Divider ─────────────────────────────────────────────────
          Divider(height: 1, color: colors.gold.withAlpha(60)),

          // ── Message button ───────────────────────────────────────────
          InkWell(
            onTap: onMessage,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(AppTheme.radiusLarge),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMd,
                vertical: AppTheme.spacingSm + 2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.messageSquare, color: colors.gold, size: 16),
                  const SizedBox(width: AppTheme.spacingSm),
                  Text(
                    'Send Message',
                    style: TextStyle(
                      color: colors.gold,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
