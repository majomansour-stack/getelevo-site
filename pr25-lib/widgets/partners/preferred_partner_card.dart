import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/partner_model.dart';
import '../../theme/theme.dart';

class PreferredPartnerCard extends StatelessWidget {
  final PartnerListing listing;
  final VoidCallback? onMessage;
  final VoidCallback? onCallTap;
  final VoidCallback? onEmailTap;

  const PreferredPartnerCard({
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
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: colors.stone, width: 1),
        boxShadow: [
          BoxShadow(
            color: colors.midnight.withAlpha(12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colors.midnight.withAlpha(10),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(color: colors.stone),
                ),
                child: listing.logoUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                        child: Image.network(listing.logoUrl!, fit: BoxFit.cover))
                    : Icon(LucideIcons.building2, color: colors.midnight, size: 22),
              ),
              const SizedBox(width: AppTheme.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            listing.businessName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        // Preferred badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: colors.stone.withAlpha(80),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: colors.stone),
                          ),
                          child: Text(
                            'ELEVO Preferred',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      listing.category,
                      style: theme.textTheme.bodySmall,
                    ),
                    if (listing.reviewCount > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          ...List.generate(5, (i) => Icon(
                            LucideIcons.star,
                            color: i < listing.rating.floor()
                                ? colors.gold
                                : colors.stone,
                            size: 12,
                          )),
                          const SizedBox(width: 4),
                          Text(
                            '${listing.rating.toStringAsFixed(1)} (${listing.reviewCount})',
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          if (listing.description != null) ...[
            const SizedBox(height: AppTheme.spacingSm),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                listing.description!.length > 80
                    ? '${listing.description!.substring(0, 80)}…'
                    : listing.description!,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.ink),
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
                    foregroundColor: colors.midnight,
                    backgroundColor: Colors.transparent,
                    side: BorderSide(color: colors.midnight, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                  ),
                  icon: Icon(LucideIcons.phone, size: 14, color: colors.midnight),
                  label: Text(
                    'Call',
                    style: TextStyle(color: colors.midnight, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spacingSm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _email,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    foregroundColor: colors.midnight,
                    backgroundColor: Colors.transparent,
                    side: BorderSide(color: colors.midnight, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                  ),
                  icon: Icon(LucideIcons.mail, size: 14, color: colors.midnight),
                  label: Text(
                    'Email',
                    style: TextStyle(color: colors.midnight, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spacingSm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onMessage,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    foregroundColor: colors.midnight,
                    backgroundColor: Colors.transparent,
                    side: BorderSide(color: colors.midnight, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                  ),
                  icon: Icon(LucideIcons.messageSquare, size: 14, color: colors.midnight),
                  label: Text(
                    'Message',
                    style: TextStyle(color: colors.midnight, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
