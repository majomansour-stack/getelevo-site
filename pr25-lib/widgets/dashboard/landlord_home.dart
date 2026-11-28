import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/elevo_logic.dart';
import '../../models/maintenance_model.dart';
import '../../models/property_model.dart';
import '../../theme/theme.dart';
import '../payments/pending_rent_notices.dart';

/// Landlord home in the A3-P2 layout. Figures come from data already loaded.
class LandlordHome extends StatelessWidget {
  final String fullName;
  final double occupancyRate;
  final int propertyCount;
  final double monthlyRent;
  final double confirmedThisMonth;
  final int pendingRentCount;
  final VoidCallback? onRentChanged;
  final int openRepairs;
  final int urgentRepairs;
  final List<Property> properties;
  final MaintenanceRequest? recentRepair;
  final String? loadError;

  const LandlordHome({
    super.key,
    required this.fullName,
    required this.occupancyRate,
    required this.propertyCount,
    required this.monthlyRent,
    this.confirmedThisMonth = 0,
    this.pendingRentCount = 0,
    this.onRentChanged,
    required this.openRepairs,
    required this.urgentRepairs,
    required this.properties,
    required this.recentRepair,
    this.loadError,
  });

  String get _firstName {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? 'there' : parts.first;
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    final money = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final showOccupancy = propertyCount > 0;
    final recent = recentRepair;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _Header(
          colors: colors,
          greeting: _greeting,
          name: _firstName,
          initial: _firstName.isNotEmpty ? _firstName[0].toUpperCase() : 'E',
          subtitle: propertyCount > 0 && urgentRepairs == 0
              ? 'Your properties are in good shape.'
              : null,
          occupancy: showOccupancy ? occupancyRate : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Transform.translate(
            offset: const Offset(0, -14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        tint: colors.oliveTint,
                        icon: LucideIcons.home,
                        iconBg: colors.isLight ? const Color(0xFFD5E0EE) : colors.olive,
                        iconColor: colors.isLight ? colors.olive : colors.onOlive,
                        label: 'Properties',
                        value: '$propertyCount',
                        onTap: () => context.go('/landlord/properties'),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _StatCard(
                        tint: colors.card,
                        icon: LucideIcons.wallet,
                        iconBg: colors.oliveTint,
                        iconColor: colors.isLight ? colors.olive : colors.onOlive,
                        label: 'Collected',
                        value: money.format(confirmedThisMonth),
                        hint: pendingRentCount > 0
                            ? '$pendingRentCount pending · of ${money.format(monthlyRent)} expected'
                            : 'of ${money.format(monthlyRent)} expected',
                        onTap: () => context.push('/landlord/more/reports'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        tint: colors.peachTint,
                        icon: LucideIcons.wrench,
                        iconBg: colors.isLight ? const Color(0xFFF5D5C4) : colors.terracotta,
                        iconColor: colors.isLight ? colors.terracotta : colors.onTerracotta,
                        label: 'Open repairs',
                        value: '$openRepairs',
                        hint: urgentRepairs > 0 ? '$urgentRepairs urgent' : null,
                        hintColor: colors.urgentRed,
                        onTap: () => context.push('/landlord/more/maintenance'),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _StatCard(
                        tint: colors.sageTint,
                        icon: LucideIcons.messageCircle,
                        iconBg: colors.isLight ? const Color(0xFFE8D7B8) : const Color(0xFF3A3228),
                        iconColor: colors.isLight ? colors.goldInk : colors.gold,
                        label: 'Messages',
                        value: null,
                        onTap: () => context.go('/landlord/messages'),
                      ),
                    ),
                  ],
                ),
                PendingRentNotices(
                  unitIds: properties.expand((property) => property.units).map((unit) => unit.id).toList(),
                  unitLabels: {
                    for (final property in properties)
                      for (final unit in property.units)
                        unit.id: '${property.address} #${unit.unitNumber}',
                  },
                  unitDueDays: {
                    for (final property in properties)
                      for (final unit in property.units)
                        unit.id: unit.rentDueDay,
                  },
                  onChanged: onRentChanged,
                ),
              ],
            ),
          ),
        ),
        if (loadError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(loadError!, style: TextStyle(color: colors.urgentRed, fontWeight: FontWeight.w600)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Row(
            children: [
              Text('Your properties', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 17)),
              const Spacer(),
              TextButton(
                onPressed: () => context.go('/landlord/properties'),
                child: const Text('See all'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              for (final property in properties.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _PropertyRow(property: property),
                ),
            ],
          ),
        ),
        if (recent != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text('Recent repair', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 17)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _RepairRow(request: recent),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final ElevoColors colors;
  final String greeting;
  final String name;
  final String initial;
  final String? subtitle;
  final double? occupancy;

  const _Header({
    required this.colors,
    required this.greeting,
    required this.name,
    required this.initial,
    required this.subtitle,
    required this.occupancy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.header,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: colors.shade.withAlpha(40), blurRadius: 28, offset: const Offset(0, 12)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    // The full lockup is navy ink on a transparent
                    // background, so it disappeared on the navy header.
                    // The app icon is the gold-and-ivory mark on navy.
                    // The mark fills about 40% of the icon, so at 28px
                    // it was a speck. Scale it up inside the clip.
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: Transform.scale(
                        scale: 2.2,
                        child: Image.asset(
                          'assets/icons/app_icon.png',
                          width: 28,
                          height: 28,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Elevo',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w800,
                      fontSize: 21,
                      color: colors.onHeader,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  Material(
                    color: colors.onHeader.withAlpha(20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: colors.onHeader.withAlpha(36)),
                    ),
                    child: InkWell(
                      onTap: () => context.push('/landlord/more/notifications'),
                      borderRadius: BorderRadius.circular(10),
                      child: const SizedBox(
                        width: 38,
                        height: 38,
                        child: Icon(LucideIcons.bell, color: Color(0xFFFFFBF6), size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => context.push('/landlord/more'),
                    child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.gold,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.onHeader.withAlpha(220), width: 1.5),
                    ),
                    child: Text(
                      initial,
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: const Color(0xFF1F3A5F),
                      ),
                    ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(greeting, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: colors.headerMuted)),
              Text(
                name,
                style: GoogleFonts.manrope(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                  letterSpacing: -0.9,
                  color: colors.onHeader,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(subtitle!, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: colors.headerMuted)),
              ],
              if (occupancy != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Occupancy', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: colors.headerMuted)),
                    const Spacer(),
                    Text(
                      '${(occupancy! * 100).round()}%',
                      style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w800, color: colors.onHeader),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: occupancy!.clamp(0, 1),
                    minHeight: 5,
                    backgroundColor: colors.onHeader.withAlpha(36),
                    color: colors.oliveBar,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final Color tint;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String? value;
  final String? hint;
  final Color? hintColor;
  final VoidCallback onTap;

  const _StatCard({
    required this.tint,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.onTap,
    this.hint,
    this.hintColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.ink.withAlpha(10)),
          boxShadow: [
            BoxShadow(color: colors.shade.withAlpha(16), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 15, color: iconColor),
            ),
            const SizedBox(height: 6),
            Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: colors.sage)),
            if (value != null)
              Text(
                value!,
                style: GoogleFonts.manrope(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                  height: 1.15,
                  color: colors.ink,
                ),
              ),
            if (hint != null)
              Text(hint!, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: hintColor ?? colors.sage)),
          ],
        ),
      ),
    );
  }
}

class _PropertyRow extends StatelessWidget {
  final Property property;
  const _PropertyRow({required this.property});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    final label = propertyOccupancyLabel(
      occupied: property.occupiedUnits,
      total: property.totalUnits,
    );
    final occupied = label == 'Occupied';
    return GestureDetector(
      onTap: () => context.go('/landlord/properties/${property.id}'),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: AppTheme.surfaceCard(colors, shadow: true),
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
                        errorWidget: (_, __, ___) => _PhotoFallback(colors: colors),
                      )
                    : _PhotoFallback(colors: colors),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    property.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(fontSize: 14.5, fontWeight: FontWeight.w800, color: colors.ink, letterSpacing: -0.3),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    property.fullAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w500, color: colors.sage),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusLabel(ok: occupied, label: label),
          ],
        ),
      ),
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  final ElevoColors colors;
  const _PhotoFallback({required this.colors});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colors.olive,
      child: Icon(LucideIcons.home, color: colors.onOlive, size: 22),
    );
  }
}

class StatusLabel extends StatelessWidget {
  final bool ok;
  final String label;
  const StatusLabel({super.key, required this.ok, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    final bg = ok
        ? (colors.isLight ? const Color(0xFFE4EFDA) : const Color(0xFF1C3328))
        : colors.peachTint;
    final fg = ok
        ? (colors.isLight ? const Color(0xFF1F7A4D) : colors.successGreen)
        : colors.urgentRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

class _RepairRow extends StatelessWidget {
  final MaintenanceRequest request;
  const _RepairRow({required this.request});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    final when = DateTime.now().difference(request.createdAt).inDays == 0
        ? 'Today'
        : DateFormat('MMM d').format(request.createdAt.toLocal());
    final place = (request.unitAddress ?? '').trim();
    return GestureDetector(
      onTap: () => context.push('/landlord/more/maintenance'),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: AppTheme.surfaceCard(colors),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: colors.peachTint, borderRadius: BorderRadius.circular(10)),
              child: Icon(LucideIcons.wrench, color: colors.terracotta, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(fontSize: 14.5, fontWeight: FontWeight.w800, color: colors.ink),
                  ),
                  Text(
                    [if (place.isNotEmpty) place, when].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w500, color: colors.sage),
                  ),
                ],
              ),
            ),
            StatusLabel(ok: false, label: request.status),
          ],
        ),
      ),
    );
  }
}
