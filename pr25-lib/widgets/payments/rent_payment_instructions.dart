import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/elevo_logic.dart';
import '../../theme/theme.dart';

/// How a tenant pays rent: the landlord's own instructions, plus the
/// existing "I have paid" notice. Elevo does not collect the money.
class RentPaymentInstructions extends StatelessWidget {
  final List<LandlordPaymentMethod> methods;
  final bool loading;
  final VoidCallback? onMarkPaid;
  final bool saving;
  final bool alreadyPending;
  final bool alreadyConfirmed;

  const RentPaymentInstructions({
    super.key,
    required this.methods,
    this.loading = false,
    this.onMarkPaid,
    this.saving = false,
    this.alreadyPending = false,
    this.alreadyConfirmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How to pay',
          style: theme.textTheme.titleSmall?.copyWith(
            color: Colors.white.withAlpha(200),
          ),
        ),
        const SizedBox(height: AppTheme.spacingXs),
        Text(
          methods.isEmpty
              ? 'Your landlord has not added payment instructions yet. Contact them to arrange rent. Elevo does not collect rent.'
              : 'Pay your landlord directly with one of these methods. Elevo does not collect or process this payment. When you have paid, tap I Have Paid.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white.withAlpha(170),
          ),
        ),
        const SizedBox(height: AppTheme.spacingSm),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppTheme.spacingSm),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          for (final method in methods)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: AppTheme.spacingSm),
              padding: const EdgeInsets.all(AppTheme.spacingSm + 4),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(16),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: colors.gold.withAlpha(70)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          method.title,
                          style: TextStyle(
                            color: colors.gold,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (method.detail.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            method.detail,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withAlpha(200),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (method.copyText.trim().isNotEmpty)
                    IconButton(
                      tooltip: 'Copy ${method.title}',
                      icon: Icon(LucideIcons.copy, color: colors.gold, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: method.copyText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${method.title} copied')),
                        );
                      },
                    ),
                ],
              ),
            ),
        const SizedBox(height: AppTheme.spacingSm),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1F3A5F),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF1F3A5F).withAlpha(120),
              disabledForegroundColor: Colors.white,
            ),
            onPressed: saving || alreadyPending || alreadyConfirmed ? null : onMarkPaid,
            child: Text(
              saving
                  ? 'Saving…'
                  : alreadyConfirmed
                      ? 'Landlord confirmed'
                      : alreadyPending
                      ? 'Waiting for landlord'
                      : 'I Have Paid',
            ),
          ),
        ),
      ],
    );
  }
}
