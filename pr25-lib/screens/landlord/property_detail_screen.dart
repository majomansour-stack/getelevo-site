import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/billing_rules.dart';
import '../../models/property_model.dart';
import '../../core/elevo_logic.dart';
import '../../services/landlord_plan_gate.dart';
import '../../providers/dashboard_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/common/status_chip.dart';
import '../../widgets/payments/pending_rent_notices.dart';
import 'package:provider/provider.dart';

class PropertyDetailScreen extends StatelessWidget {
  final String propertyId;

  const PropertyDetailScreen({super.key, required this.propertyId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final dashboard = context.watch<DashboardProvider>();
    final property = dashboard.properties.cast<Property?>().firstWhere(
      (p) => p?.id == propertyId,
      orElse: () => null,
    );
    if (property == null) {
      if (dashboard.isLoading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Text(dashboard.loadError ?? 'This property could not be found.'),
        ),
      );
    }
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: colors.charcoal,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colors.shade.withAlpha(150),
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.arrowLeft, color: colors.ivory, size: 20),
              ),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colors.shade.withAlpha(150),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.pencil, color: colors.ivory, size: 18),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  context.go('/landlord/properties/${property.id}/edit');
                },
                tooltip: 'Edit property',
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (property.photoUrl != null)
                    CachedNetworkImage(
                      imageUrl: property.photoUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(color: colors.charcoal),
                    ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                        stops: [0.35, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: AppTheme.spacingMd,
                    left: AppTheme.spacingMd,
                    right: 60,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          property.name,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            shadows: [const Shadow(blurRadius: 8, color: Colors.black54)],
                          ),
                        ),
                        Text(
                          property.fullAddress,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withAlpha(210),
                            shadows: [const Shadow(blurRadius: 4, color: Colors.black54)],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tenancy', style: theme.textTheme.titleLarge?.copyWith(fontSize: 22)),
                  const SizedBox(height: AppTheme.spacingSm),
                  ...property.units.map((unit) => _UnitCard(
                        unit: unit,
                        fmt: fmt,
                        propertyId: property.id,
                        showUnitNumber: property.units.length > 1,
                      )),
                  PendingRentNotices(
                    unitIds: property.units.map((unit) => unit.id).toList(),
                    unitLabels: {
                      for (final unit in property.units)
                        unit.id: '${property.address} #${unit.unitNumber}',
                    },
                    unitDueDays: {
                      for (final unit in property.units) unit.id: unit.rentDueDay,
                    },
                    onChanged: () => context.read<DashboardProvider>().loadData(),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          HapticFeedback.lightImpact();
          if (landlordCreateAllowed(context, LandlordCreateKind.unit)) {
            context.go('/landlord/properties/${property.id}/add-unit');
          }
        },
        tooltip: 'Add Unit',
        child: const Icon(LucideIcons.plus, size: 22),
      ),
    );
  }
}

class _UnitCard extends StatelessWidget {
  final Unit unit;
  final NumberFormat fmt;
  final String propertyId;
  final bool showUnitNumber;

  const _UnitCard({
    required this.unit,
    required this.fmt,
    required this.propertyId,
    this.showUnitNumber = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final colors  = theme.extension<ElevoColors>()!;
    final dateFmt = DateFormat('MMMM d, y');

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (unit.isOccupied) {
          _showTenantDetailSheet(context, unit, fmt, propertyId);
        } else {
          context.go('/landlord/properties/$propertyId/unit/${unit.id}/edit');
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacingSm),
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        decoration: AppTheme.surfaceCard(colors),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  showUnitNumber
                      ? unit.unitNumber
                      : (unit.tenantName ?? (unit.isOccupied ? 'Occupied' : 'Vacant')),
                  style: theme.textTheme.titleMedium?.copyWith(color: colors.ink),
                ),
                const Spacer(),
                StatusChip(label: unit.status.toUpperCase()),
                const SizedBox(width: AppTheme.spacingSm),
                Icon(LucideIcons.chevronRight, size: 16, color: colors.taupe),
              ],
            ),
            if (unitSizeLabel(bedrooms: unit.bedrooms, bathrooms: unit.bathrooms) !=
                null) ...[
              const SizedBox(height: AppTheme.spacingXs),
              Text(
                unitSizeLabel(bedrooms: unit.bedrooms, bathrooms: unit.bathrooms)!,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.goldInk),
              ),
            ],
            const SizedBox(height: AppTheme.spacingSm),
            Row(
              children: [
                Icon(LucideIcons.user, size: 14, color: colors.taupe),
                const SizedBox(width: AppTheme.spacingXs),
                Expanded(
                  child: Text(
                    unit.tenantName ?? 'Vacant — tap to invite tenant',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: unit.tenantName == null ? colors.gold : null,
                    ),
                  ),
                ),
                Text(
                  fmt.format(unit.rentAmount),
                  style: TextStyle(color: colors.goldInk, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            if (unit.leaseEnd != null) ...[
              const SizedBox(height: AppTheme.spacingXs),
              Text(
                'Lease ends ${dateFmt.format(unit.leaseEnd!)}',
                style: theme.textTheme.labelSmall,
              ),
            ],
            if (unit.openTickets > 0) ...[
              const SizedBox(height: AppTheme.spacingXs),
              Row(
                children: [
                  Icon(LucideIcons.wrench, size: 12, color: colors.warningAmber),
                  const SizedBox(width: AppTheme.spacingXs),
                  Text(
                    '${unit.openTickets} open ticket${unit.openTickets > 1 ? 's' : ''}',
                    style: TextStyle(color: colors.warningAmber, fontSize: 11),
                  ),
                ],
              ),
            ],
            if (!unit.isOccupied) ...[
              const SizedBox(height: AppTheme.spacingSm),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.gold,
                    foregroundColor: colors.midnight,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                  ),
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    // Get property info from the DashboardProvider via context
                    final dash = context.read<DashboardProvider>();
                    final prop = dash.properties.cast<Property?>().firstWhere(
                      (p) => p?.id == propertyId,
                      orElse: () => null,
                    );
                    final address = prop?.fullAddress ?? 'a property';
                    final rentStr = fmt.format(unit.rentAmount);
                    final unitLabel = 'Unit ${unit.unitNumber}';
                    final shareText =
                        'Available rental at $address $unitLabel — $rentStr per month. '
                        'Managed through ELEVO Property Management. '
                        'Contact your landlord or visit getelevo.app to apply.';
                    try {
                      await Share.share(shareText, subject: 'Available Rental — $address $unitLabel');
                    } catch (_) {
                      await Clipboard.setData(ClipboardData(text: shareText));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Listing copied to clipboard')),
                        );
                      }
                    }
                  },
                  icon: Icon(LucideIcons.share2, size: 16, color: colors.midnight),
                  label: Text(
                    'Share Listing',
                    style: TextStyle(
                      color: colors.midnight,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Tenant detail sheet shown when landlord taps an occupied unit ───────────

Future<void> _showTenantDetailSheet(
    BuildContext context, Unit unit, NumberFormat fmt, String propertyId) async {
  final db = Supabase.instance.client;
  final theme = Theme.of(context);
  final colors = theme.extension<ElevoColors>()!;
  final dateFmt = DateFormat('MMMM d, y');

  String tenantEmail = '';
  String tenantPhone = '';
  bool loading = unit.tenantId != null;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.canvas,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        if (loading) {
          db.from('users')
              .select('email, phone')
              .eq('id', unit.tenantId!)
              .maybeSingle()
              .then((row) {
            tenantEmail = (row?['email'] as String?) ?? '';
            tenantPhone = (row?['phone'] as String?) ?? '';
            setSheet(() => loading = false);
          }).catchError((dynamic _) { setSheet(() => loading = false); return null; });
        }
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
                    decoration: BoxDecoration(
                        color: colors.stone, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(children: [
                  Icon(LucideIcons.user, color: colors.gold, size: 20),
                  const SizedBox(width: AppTheme.spacingSm),
                  Text(unit.tenantName ?? 'Tenant',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: colors.midnight)),
                ]),
                const SizedBox(height: AppTheme.spacingMd),
                if (loading)
                  const Center(child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: CircularProgressIndicator(),
                  ))
                else ...[
                  _DetailRow(label: 'Name', value: unit.tenantName ?? '—',
                      colors: colors, theme: theme),
                  if (tenantEmail.isNotEmpty)
                    _DetailRow(
                        label: 'Email',
                        value: tenantEmail,
                        colors: colors,
                        theme: theme,
                        onCopy: () {
                          Clipboard.setData(ClipboardData(text: tenantEmail));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Email copied')));
                        }),
                  if (tenantPhone.isNotEmpty)
                    _DetailRow(
                        label: 'Phone',
                        value: tenantPhone,
                        colors: colors,
                        theme: theme,
                        onCopy: () {
                          Clipboard.setData(ClipboardData(text: tenantPhone));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Phone copied')));
                        }),
                  if (unitSizeLabel(
                        bedrooms: unit.bedrooms,
                        bathrooms: unit.bathrooms,
                      ) !=
                      null)
                    _DetailRow(
                        label: 'Size',
                        value: unitSizeLabel(
                          bedrooms: unit.bedrooms,
                          bathrooms: unit.bathrooms,
                        )!,
                        colors: colors,
                        theme: theme),
                  _DetailRow(
                      label: 'Monthly Rent',
                      value: fmt.format(unit.rentAmount),
                      colors: colors,
                      theme: theme),
                  if (unit.leaseStart != null)
                    _DetailRow(
                        label: 'Lease Start',
                        value: dateFmt.format(unit.leaseStart!),
                        colors: colors,
                        theme: theme),
                  if (unit.leaseEnd != null)
                    _DetailRow(
                        label: 'Lease End',
                        value: dateFmt.format(unit.leaseEnd!),
                        colors: colors,
                        theme: theme),
                ],
                const SizedBox(height: AppTheme.spacingMd),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingSm),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.go(
                            '/landlord/properties/$propertyId/unit/${unit.id}/edit');
                      },
                      child: const Text('Edit Unit'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final ElevoColors colors;
  final ThemeData theme;
  final VoidCallback? onCopy;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.colors,
    required this.theme,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: colors.sage, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.ink)),
          ),
          if (onCopy != null)
            GestureDetector(
              onTap: onCopy,
              child: Icon(LucideIcons.copy, size: 14, color: colors.gold),
            ),
        ],
      ),
    );
  }
}

