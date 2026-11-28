import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/theme.dart';

/// Vertical repair-status timeline. Labels are the app's existing statuses.
class RepairStatusTimeline extends StatelessWidget {
  final int currentIndex;
  final List<String> labels;

  const RepairStatusTimeline({
    super.key,
    required this.currentIndex,
    this.labels = const ['Submitted', 'Assigned', 'In Progress', 'Resolved'],
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ElevoColors>()!;

    return Column(
      children: [
        for (var i = 0; i < labels.length; i++)
          _Step(
            label: labels[i],
            active: i <= currentIndex,
            current: i == currentIndex,
            last: i == labels.length - 1,
            colors: colors,
          ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final String label;
  final bool active;
  final bool current;
  final bool last;
  final ElevoColors colors;

  const _Step({
    required this.label,
    required this.active,
    required this.current,
    required this.last,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final dot = active ? colors.olive : colors.stone;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                  width: current ? 14 : 10,
                  height: current ? 14 : 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? dot : Colors.transparent,
                    border: Border.all(color: dot, width: 1.5),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: active ? colors.olive.withAlpha(160) : colors.stone,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: current ? FontWeight.w600 : FontWeight.w500,
                  color: active ? colors.ink : colors.sage,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
