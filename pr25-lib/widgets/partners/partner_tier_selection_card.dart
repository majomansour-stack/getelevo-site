import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/partner_model.dart';
import '../../theme/theme.dart';

class PartnerTierSelectionCard extends StatelessWidget {
  final PartnerTier tier;
  final bool isSelected;
  final bool mostPopular;
  final VoidCallback onTap;

  const PartnerTierSelectionCard({
    super.key,
    required this.tier,
    required this.isSelected,
    required this.onTap,
    this.mostPopular = false,
  });

  List<String> _benefits() {
    switch (tier) {
      case PartnerTier.basic:
        return [
          'Listed in your trade category',
          'ELEVO verified badge',
          'Name and phone visible to all ELEVO users',
          'Access to tenant and landlord contacts',
          'No setup fee',
        ];
      case PartnerTier.featured:
        return [
          'Everything in Basic',
          'Company logo displayed on your card',
          'Business description shown to users',
          'Star rating and customer reviews displayed',
          'Featured badge on your listing',
        ];
      case PartnerTier.preferred:
        return [
          'Everything in Featured',
          'Top placement above Featured and Basic vendors',
          'Extended description visible to users',
          'Direct message button — contact in-app',
          'ELEVO Preferred gold badge on your listing',
        ];
      case PartnerTier.platinum:
        return [
          'Everything in Preferred',
          'Guaranteed first position in your category',
          'Premium dark navy card with gold border',
          'ELEVO Platinum gold badge',
          'Priority application review within 24 hours',
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        decoration: BoxDecoration(
          color: isSelected ? colors.gold.withAlpha(28) : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(
            color: isSelected ? colors.gold : colors.stone,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (mostPopular)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colors.gold,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'MOST POPULAR',
                            style: TextStyle(
                              color: colors.shade,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      Text(
                        '${tier.label} Partner',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 2),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '\$${formatVendorPrice(tier.monthlyPrice)}',
                              style: TextStyle(
                                color: colors.goldInk,
                                fontWeight: FontWeight.w800,
                                fontSize: 22,
                              ),
                            ),
                            TextSpan(
                              text: ' / month',
                              style: TextStyle(
                                color: colors.sage,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: colors.gold,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(LucideIcons.check, color: colors.shade, size: 16),
                  )
                else
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.stone, width: 1.5),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingMd),
            Divider(height: 1, color: colors.stone.withAlpha(120)),
            const SizedBox(height: AppTheme.spacingMd),
            ..._benefits().map((benefit) => Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacingXs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.check, color: colors.goldInk, size: 14),
                  const SizedBox(width: AppTheme.spacingSm),
                  Expanded(
                    child: Text(
                      benefit,
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.ink),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}
