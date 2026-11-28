import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme/theme.dart';

/// Cream-or-dark card shown until the landlord dismisses the RentSpree note.
class RentSpreeBeforeYouBegin extends StatelessWidget {
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  const RentSpreeBeforeYouBegin({
    super.key,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final onSurface = theme.colorScheme.onSurface;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.gold, width: 1.5),
      ),
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Before You Begin',
            style: theme.textTheme.titleSmall?.copyWith(
              color: onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Text(
            'You will need a free RentSpree account to screen tenants.\n\n'
            'Step 1: Create your free account at rentspree.com.\n'
            'Step 2: Add each rental property to your RentSpree dashboard.\n'
            'Step 3: Copy the screening link for each property and paste it into your ELEVO property settings.',
            style: theme.textTheme.bodySmall?.copyWith(color: onSurface),
          ),
          const SizedBox(height: AppTheme.spacingMd),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: AppTheme.goldFillButton(colors, theme.textTheme),
              onPressed: onOpen,
              child: const Text('Open RentSpree'),
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Center(
            child: GestureDetector(
              onTap: onDismiss,
              child: Text(
                'I already have an account — dismiss',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onSurface,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Short explanation that the landlord uses their own free RentSpree
/// account. Expanded when they have not saved a link yet.
class RentSpreeHowItWorks extends StatelessWidget {
  final bool needsLink;

  const RentSpreeHowItWorks({super.key, required this.needsLink});

  static const steps = <String>[
    'Create a free landlord account at rentspree.com.',
    'Add your property in RentSpree.',
    'Copy your RentSpree apply/screening link and paste it in Elevo (More > RentSpree link).',
    'Send the screening invite from Elevo. The applicant opens your link and pays RentSpree directly.',
    'Review the report in RentSpree, then mark the applicant approved or declined in Elevo.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    final onSurface = theme.colorScheme.onSurface;
    return Material(
      color: needsLink ? colors.gold.withAlpha(28) : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        side: BorderSide(
          color: needsLink ? colors.gold : colors.stone,
          width: needsLink ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey(needsLink),
          initiallyExpanded: needsLink,
          iconColor: onSurface,
          collapsedIconColor: onSurface,
          tilePadding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppTheme.spacingMd,
            0,
            AppTheme.spacingMd,
            AppTheme.spacingMd,
          ),
          leading: Icon(LucideIcons.info, size: 18, color: colors.goldInk),
          title: Text(
            'How screening with RentSpree works',
            style: theme.textTheme.titleSmall?.copyWith(
              color: onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: needsLink
              ? Text(
                  'Add your link so applicants use your RentSpree account.',
                  style: theme.textTheme.bodySmall?.copyWith(color: onSurface),
                )
              : null,
          children: [
            ...steps.asMap().entries.map((entry) {
              final number = entry.key + 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$number. ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: onSurface,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
            Text(
              "Elevo isn't affiliated with RentSpree and doesn't see or store credit reports.",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: onSurface,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
