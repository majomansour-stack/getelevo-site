import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../../models/property_model.dart';
import '../../theme/theme.dart';
import '../common/section_header.dart';
import '../common/status_chip.dart';

class PropertyCarousel extends StatelessWidget {
  final List<Property> properties;

  const PropertyCarousel({super.key, required this.properties});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Properties',
          actionLabel: 'View All',
          onAction: () => context.go('/landlord/properties'),
        ),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: properties.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppTheme.spacingSm),
            itemBuilder: (context, i) => _PropertyCard(property: properties[i]),
          ),
        ),
      ],
    );
  }
}

class _PropertyCard extends StatelessWidget {
  final Property property;

  const _PropertyCard({required this.property});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    final badgeColor = property.occupancyRate >= 1.0
        ? colors.successGreen
        : property.occupancyRate >= 0.5
            ? colors.warningAmber
            : colors.urgentRed;

    return GestureDetector(
      onTap: () => context.go('/landlord/properties/${property.id}'),
      child: Container(
        width: 260,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          color: colors.charcoal,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (property.photoUrl != null)
              CachedNetworkImage(
                imageUrl: property.photoUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(color: colors.charcoal),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.45, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withAlpha(80),
                    Colors.black.withAlpha(210),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: AppTheme.spacingSm,
              left: AppTheme.spacingSm,
              right: AppTheme.spacingSm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    property.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(
                          color: Colors.black.withAlpha(160),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    property.address,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withAlpha(230),
                      shadows: [
                        Shadow(
                          color: Colors.black.withAlpha(160),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppTheme.spacingSm),
                  Row(
                    children: [
                      StatusChip(
                        label: property.occupiedUnits > 0 ? 'Occupied' : 'Vacant',
                        color: property.occupiedUnits > 0
                            ? colors.successGreen
                            : colors.urgentRed,
                      ),
                      const SizedBox(width: AppTheme.spacingXs),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
