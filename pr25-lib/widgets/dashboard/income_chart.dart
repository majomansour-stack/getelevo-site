import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../theme/theme.dart';
import '../common/section_header.dart';

class IncomeChart extends StatelessWidget {
  final List<double> monthlyData;

  const IncomeChart({super.key, required this.monthlyData});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final currentMonth = DateTime.now().month - 1;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    // Filter only the months with data (up to and including current month)
    final maxValue = monthlyData.where((v) => v > 0).isEmpty
        ? 1.0
        : monthlyData.where((v) => v > 0).reduce((a, b) => a > b ? a : b);
    final chartMax = maxValue * 1.25;

    // Y-axis label formatter — shows abbreviated dollar amounts
    String _yLabel(double v) {
      if (v >= 1000) return '\$${(v / 1000).toStringAsFixed(0)}k';
      return '\$${v.toStringAsFixed(0)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Monthly Income'),
        const SizedBox(height: AppTheme.spacingSm),
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacingXs,
            AppTheme.spacingMd,
            AppTheme.spacingMd,
            AppTheme.spacingSm,
          ),
          decoration: AppTheme.surfaceCard(colors),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary row
              Padding(
                padding: const EdgeInsets.only(left: AppTheme.spacingSm, bottom: AppTheme.spacingMd),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors.olive,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingXs),
                    Text(
                      'Current month',
                      style: theme.textTheme.labelSmall?.copyWith(color: colors.sage),
                    ),
                    const SizedBox(width: AppTheme.spacingMd),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors.midnight.withAlpha(30),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingXs),
                    Text(
                      'Prior months',
                      style: theme.textTheme.labelSmall?.copyWith(color: colors.sage),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: chartMax,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => colors.midnight,
                        tooltipRoundedRadius: AppTheme.radiusSmall,
                        tooltipPadding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacingSm,
                          vertical: AppTheme.spacingXs,
                        ),
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          return BarTooltipItem(
                            '${months[group.x]}\n${fmt.format(rod.toY)}',
                            TextStyle(
                              color: colors.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.6,
                            ),
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 44,
                          interval: chartMax / 4,
                          getTitlesWidget: (val, _) {
                            if (val == 0) return const SizedBox.shrink();
                            return Text(
                              _yLabel(val),
                              style: TextStyle(
                                color: colors.sage,
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          getTitlesWidget: (val, _) {
                            final idx = val.toInt();
                            if (idx < 0 || idx >= months.length) return const SizedBox.shrink();
                            // Only label every other month to avoid crowding
                            if (idx % 2 != 0) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                months[idx].substring(0, 3),
                                style: TextStyle(
                                  color: idx == currentMonth ? colors.gold : colors.sage,
                                  fontSize: 9,
                                  fontWeight: idx == currentMonth
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: chartMax / 4,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: colors.stone.withAlpha(60),
                        strokeWidth: 1,
                        dashArray: [4, 4],
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: List.generate(12, (i) {
                      final isCurrentMonth = i == currentMonth;
                      final hasData = monthlyData[i] > 0;
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: hasData ? monthlyData[i] : 0,
                            gradient: isCurrentMonth
                                ? LinearGradient(
                                    colors: [
                                      colors.olive,
                                      colors.olive.withAlpha(200),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  )
                                : LinearGradient(
                                    colors: [
                                      colors.midnight.withAlpha(60),
                                      colors.midnight.withAlpha(30),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                            width: 16,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
