import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/calendar_event_model.dart';
import '../../theme/theme.dart';
import '../common/section_header.dart';

class UpcomingAlerts extends StatelessWidget {
  final List<CalendarEvent> events;

  const UpcomingAlerts({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    final sorted = List<CalendarEvent>.from(events)
      ..sort((a, b) => a.eventDate.compareTo(b.eventDate));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Upcoming Alerts',
          actionLabel: 'View All',
          onAction: () => context.push('/landlord/more/calendar'),
        ),
        ...sorted.take(4).map((e) => _AlertTile(event: e)),
      ],
    );
  }
}

class _AlertTile extends StatelessWidget {
  final CalendarEvent event;

  const _AlertTile({required this.event});

  Color _urgencyColor(ElevoColors colors) {
    if (event.isCompleted) return colors.successGreen;
    final days = event.daysUntil;
    if (days < 0 || days <= 7) return colors.urgentRed;
    if (days <= 30) return colors.warningAmber;
    if (days <= 90) return colors.gold;
    return colors.successGreen;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final uc = _urgencyColor(colors);
    final fmt = DateFormat('MMMM d, y');

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingSm),
      padding: const EdgeInsets.all(AppTheme.spacingSm + 4),
      decoration: AppTheme.surfaceCard(colors),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: uc, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppTheme.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (event.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    event.subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.sage,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacingSm),
          Text(
            fmt.format(event.eventDate),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.sage,
            ),
          ),
        ],
      ),
    );
  }
}
