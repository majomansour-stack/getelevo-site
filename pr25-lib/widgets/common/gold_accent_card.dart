import 'package:flutter/material.dart';
import '../../theme/theme.dart';

class GoldAccentCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final bool showGoldBorder;

  const GoldAccentCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.showGoldBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ElevoColors>()!;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: padding ?? const EdgeInsets.all(AppTheme.spacingMd),
        decoration: AppTheme.surfaceCard(
          colors,
          border: showGoldBorder
              ? Border(
                  left: BorderSide(color: colors.gold, width: 3),
                  top: BorderSide(color: colors.stone.withAlpha(140)),
                  right: BorderSide(color: colors.stone.withAlpha(140)),
                  bottom: BorderSide(color: colors.stone.withAlpha(140)),
                )
              : null,
        ),
        child: child,
      ),
    );
  }
}
