import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/partner_model.dart';
import '../../providers/partner_provider.dart';
import '../../theme/theme.dart';

class PartnerApplicationsScreen extends StatefulWidget {
  const PartnerApplicationsScreen({super.key});

  @override
  State<PartnerApplicationsScreen> createState() => _PartnerApplicationsScreenState();
}

class _PartnerApplicationsScreenState extends State<PartnerApplicationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PartnerProvider>().loadApplications();
    });
  }

  Color _statusColor(PartnerStatus status, ElevoColors colors) {
    return switch (status) {
      PartnerStatus.pending  => colors.warningAmber,
      PartnerStatus.active   => colors.successGreen,
      PartnerStatus.declined => colors.urgentRed,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final colors   = theme.extension<ElevoColors>()!;
    final provider = context.watch<PartnerProvider>();

    final filters = ['All', 'Pending', 'Active', 'Declined'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Partner Applications'),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // ── Filter chips ─────────────────────────────────────────────
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm),
              itemCount: filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppTheme.spacingXs),
              itemBuilder: (ctx, i) {
                final f = filters[i];
                final selected = provider.adminFilter == f;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    provider.setAdminFilter(f);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? colors.olive : colors.card,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      border: Border.all(
                          color: selected ? colors.olive : colors.stone),
                    ),
                    child: Text(
                      f,
                      style: TextStyle(
                        color: selected ? colors.onOlive : colors.ink,
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Applications list ────────────────────────────────────────
          Expanded(
            child: provider.isLoading
                ? Center(child: CircularProgressIndicator(color: colors.gold))
                : provider.filteredApplications.isEmpty
                    ? Center(
                        child: Text('No applications found.',
                            style: theme.textTheme.bodyMedium))
                    : ListView.separated(
                        padding: const EdgeInsets.all(AppTheme.spacingMd),
                        itemCount: provider.filteredApplications.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppTheme.spacingMd),
                        itemBuilder: (ctx, i) {
                          final app = provider.filteredApplications[i];
                          return _ApplicationCard(
                            application: app,
                            statusColor: _statusColor(app.status, colors),
                            onApprove: app.status == PartnerStatus.pending
                                ? () => _confirmApprove(ctx, app)
                                : null,
                            onDecline: app.status == PartnerStatus.pending
                                ? () => _confirmDecline(ctx, app)
                                : null,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _confirmApprove(BuildContext context, PartnerApplication app) {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Application'),
        content: Text(
          'Approve ${app.businessName} as an ELEVO ${app.tier.label} Partner? '
          'Their listing will go live immediately and they will receive a confirmation email.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: AppTheme.goldFillButton(colors, Theme.of(context).textTheme),
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<PartnerProvider>().approveApplication(app.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${app.businessName} approved and listing is now live.')),
                );
              }
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  void _confirmDecline(BuildContext context, PartnerApplication app) {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Application'),
        content: Text(
          'Decline the application from ${app.businessName}? '
          'They will receive a decline email automatically.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.urgentRed,
              backgroundColor: Colors.transparent,
              side: BorderSide(color: colors.urgentRed),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<PartnerProvider>().declineApplication(app.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${app.businessName} application declined.')),
                );
              }
            },
            child: const Text('Decline'),
          ),
        ],
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  final PartnerApplication application;
  final Color statusColor;
  final VoidCallback? onApprove;
  final VoidCallback? onDecline;

  const _ApplicationCard({
    required this.application,
    required this.statusColor,
    this.onApprove,
    this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final fmt    = DateFormat('MMM d, y');

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.stone.withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ─────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      application.businessName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(application.ownerName, style: theme.textTheme.bodySmall),
                    Text(application.category,
                        style: theme.textTheme.labelSmall?.copyWith(color: colors.sage)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: statusColor.withAlpha(80)),
                    ),
                    child: Text(
                      application.status.label,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Tier + price
                  Text(
                    '${application.tier.label} — \$${formatVendorPrice(application.monthlyPrice)}/mo',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.gold, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: AppTheme.spacingSm),
          Divider(height: 1, color: colors.stone.withAlpha(80)),
          const SizedBox(height: AppTheme.spacingSm),

          // ── Info row ───────────────────────────────────────────────
          Row(
            children: [
              Icon(LucideIcons.calendar, color: colors.sage, size: 13),
              const SizedBox(width: 4),
              Text(
                'Submitted ${fmt.format(application.submittedAt.toLocal())}',
                style: theme.textTheme.labelSmall,
              ),
              const Spacer(),
              Icon(LucideIcons.mail, color: colors.sage, size: 13),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  application.email,
                  style: theme.textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          // ── Action buttons (pending only) ──────────────────────────
          if (onApprove != null || onDecline != null) ...[
            const SizedBox(height: AppTheme.spacingMd),
            Row(
              children: [
                if (onApprove != null)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onApprove,
                      style: AppTheme.goldFillButton(colors, theme.textTheme).copyWith(
                        minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
                      ),
                      child: const Text('Approve',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                if (onApprove != null && onDecline != null)
                  const SizedBox(width: AppTheme.spacingSm),
                if (onDecline != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDecline,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        foregroundColor: colors.urgentRed,
                        backgroundColor: Colors.transparent,
                        side: BorderSide(color: colors.urgentRed),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
                      ),
                      child: const Text('Decline',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
