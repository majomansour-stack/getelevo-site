import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme/theme.dart';

class MetricCardsGrid extends StatelessWidget {
  final double monthlyIncome;
  final double occupancyRate;
  final double outstandingBalance;
  final int openTickets;
  final int urgentTickets;

  const MetricCardsGrid({
    super.key,
    required this.monthlyIncome,
    required this.occupancyRate,
    required this.outstandingBalance,
    required this.openTickets,
    required this.urgentTickets,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Column(
      children: [
        _MetricCard(
          label: 'Monthly Income',
          value: fmt.format(monthlyIncome),
          icon: LucideIcons.trendingUp,
          olive: true,
          onTap: () => context.push('/landlord/more/reports'),
        ),
        const SizedBox(height: AppTheme.spacingSm),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'Occupancy Rate',
                  value: '${(occupancyRate * 100).toInt()}%',
                  icon: LucideIcons.home,
                  onTap: () => context.push('/landlord/properties'),
                ),
              ),
              const SizedBox(width: AppTheme.spacingSm),
              Expanded(
                child: _MetricCard(
                  label: 'Outstanding',
                  value: fmt.format(outstandingBalance),
                  icon: LucideIcons.alertCircle,
                  emphasize: outstandingBalance > 0,
                  onTap: () => context.push('/landlord/more/maintenance'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spacingSm),
        _MetricCard(
          label: 'Open Tickets',
          value: '$openTickets',
          icon: LucideIcons.wrench,
          subtitle: urgentTickets > 0 ? '$urgentTickets urgent' : null,
          subtitleRed: urgentTickets > 0,
          onTap: () => context.push('/landlord/more/maintenance'),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool olive;
  final bool emphasize;
  final String? subtitle;
  final bool subtitleRed;
  final VoidCallback? onTap;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.olive = false,
    this.emphasize = false,
    this.subtitle,
    this.subtitleRed = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final muted = olive ? colors.onOlive.withAlpha(180) : colors.sage;
    final valueColor = olive
        ? colors.onOlive
        : emphasize
            ? colors.terracotta
            : colors.ink;

    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              onTap!();
            },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTheme.spacingMd + 2),
        decoration: olive
            ? BoxDecoration(
                color: colors.olive,
                borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                boxShadow: AppTheme.cardShadow(colors),
              )
            : AppTheme.surfaceCard(colors),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(icon, size: 16, color: olive ? colors.onOlive : colors.linkOlive),
              ],
            ),
            const SizedBox(height: AppTheme.spacingSm),
            Text(
              value,
              style: AppTheme.serif(
                theme.textTheme.headlineSmall,
                color: valueColor,
                fontSize: olive ? 36 : 26,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppTheme.spacingXs),
              Text(
                subtitle!,
                style: TextStyle(
                  color: subtitleRed ? colors.urgentRed : muted,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
