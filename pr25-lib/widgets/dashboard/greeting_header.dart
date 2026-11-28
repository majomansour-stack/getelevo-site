import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme/theme.dart';

class GreetingHeader extends StatelessWidget {
  final String userName;

  const GreetingHeader({super.key, required this.userName});

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _firstName => userName.split(' ').first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Elevo',
                style: AppTheme.serif(
                  theme.textTheme.titleLarge,
                  color: colors.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppTheme.spacingXs),
              Text(
                '$_greeting, $_firstName',
                style: theme.textTheme.headlineSmall,
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => context.push('/landlord/more/notifications'),
          child: Container(
            width: AppTheme.touchTarget,
            height: AppTheme.touchTarget,
            alignment: Alignment.center,
            child: Stack(
              children: [
                Icon(LucideIcons.bell, color: colors.ink, size: 22),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors.urgentRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppTheme.spacingXs),
        GestureDetector(
          onTap: () => context.push('/landlord/more'),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.oliveTint,
              border: Border.all(color: colors.olive),
            ),
            child: Center(
              child: Text(
                _firstName.isNotEmpty ? _firstName[0] : 'A',
                style: TextStyle(
                  color: colors.linkOlive,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
