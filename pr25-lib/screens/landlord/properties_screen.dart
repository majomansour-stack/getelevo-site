import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/billing_rules.dart';
import '../../models/property_model.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/landlord_plan_gate.dart';
import '../../theme/theme.dart';
import '../../widgets/common/status_chip.dart';

class PropertiesScreen extends StatelessWidget {
  const PropertiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final properties = context.watch<DashboardProvider>().properties;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Properties'),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.megaphone, color: colors.gold),
            tooltip: 'Broadcast to tenants',
            onPressed: () {
              HapticFeedback.lightImpact();
              context.push('/landlord/properties/announce');
            },
          ),
          IconButton(
            icon: Icon(LucideIcons.plus, color: colors.gold),
            onPressed: () {
              HapticFeedback.lightImpact();
              if (landlordCreateAllowed(context, LandlordCreateKind.property)) {
                context.go('/landlord/properties/add');
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          HapticFeedback.lightImpact();
          if (landlordCreateAllowed(context, LandlordCreateKind.property)) {
            context.go('/landlord/properties/add');
          }
        },
        child: const Icon(LucideIcons.plus),
      ),
      body: properties.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.building2, size: 56, color: colors.gold),
                  const SizedBox(height: AppTheme.spacingMd),
                  Text('Add your first property\nto get started',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.taupe),
                  ),
                  const SizedBox(height: AppTheme.spacingLg),
                  ElevatedButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      if (landlordCreateAllowed(context, LandlordCreateKind.property)) {
                        context.go('/landlord/properties/add');
                      }
                    },
                    child: const Text('Add Property'),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              itemCount: properties.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spacingSm),
              itemBuilder: (context, i) {
                final p = properties[i];
                return _PropertyListCard(property: p, fmt: fmt);
              },
            ),
    );
  }
}

class _PropertyListCard extends StatelessWidget {
  final Property property;
  final NumberFormat fmt;

  const _PropertyListCard({required this.property, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    final occupied = property.occupiedUnits > 0;
    return GestureDetector(
      onTap: () => context.go('/landlord/properties/${property.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: AppTheme.surfaceCard(colors),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: property.photoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: property.photoUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => ColoredBox(
                          color: colors.olive,
                          child: Icon(LucideIcons.home, color: colors.onOlive),
                        ),
                      )
                    : ColoredBox(
                        color: colors.olive,
                        child: Icon(LucideIcons.home, color: colors.onOlive),
                      ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(property.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(color: colors.ink, fontWeight: FontWeight.w800)),
                  Text(property.fullAddress, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                  Text(fmt.format(property.enteredRent), style: theme.textTheme.labelMedium?.copyWith(color: colors.ink, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            StatusChip(
              label: occupied ? 'Occupied' : 'Vacant',
              color: occupied ? colors.successGreen : colors.urgentRed,
            ),
          ],
        ),
      ),
    );
  }
}
