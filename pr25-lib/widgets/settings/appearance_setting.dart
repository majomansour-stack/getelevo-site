import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../services/theme_mode_store.dart';
import '../../theme/theme.dart';

/// System / Light / Dark control. Persists through [ThemeModeController].
class AppearanceSetting extends StatelessWidget {
  const AppearanceSetting({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = theme.extension<ElevoColors>();
    final controller = context.watch<ThemeModeController>();
    final border = colors?.stone ?? scheme.outline;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: border.withAlpha(160)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Appearance',
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'System follows this device. Light and Dark stay fixed.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors?.sage ?? scheme.onSurface.withAlpha(180),
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Row(
            children: [
              _AppearanceChoice(
                mode: ThemeMode.system,
                label: 'System',
                icon: LucideIcons.monitor,
                selected: controller.mode == ThemeMode.system,
                onTap: () => controller.setMode(ThemeMode.system),
              ),
              const SizedBox(width: AppTheme.spacingSm),
              _AppearanceChoice(
                mode: ThemeMode.light,
                label: 'Light',
                icon: LucideIcons.sun,
                selected: controller.mode == ThemeMode.light,
                onTap: () => controller.setMode(ThemeMode.light),
              ),
              const SizedBox(width: AppTheme.spacingSm),
              _AppearanceChoice(
                mode: ThemeMode.dark,
                label: 'Dark',
                icon: LucideIcons.moon,
                selected: controller.mode == ThemeMode.dark,
                onTap: () => controller.setMode(ThemeMode.dark),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppearanceChoice extends StatelessWidget {
  final ThemeMode mode;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AppearanceChoice({
    required this.mode,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = theme.extension<ElevoColors>();
    final fill = selected
        ? (colors?.olive ?? scheme.primary)
        : (colors?.canvas ?? scheme.surfaceContainerHighest);
    final foreground = selected
        ? (colors?.onOlive ?? scheme.onPrimary)
        : scheme.onSurface;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label appearance',
        child: Material(
          color: fill,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          child: InkWell(
            key: Key('appearance-${mode.name}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(
                  color: selected
                      ? (colors?.olive ?? scheme.primary)
                      : (colors?.stone ?? scheme.outline),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: foreground),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
