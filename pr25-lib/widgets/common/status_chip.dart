import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/theme.dart';

class StatusChip extends StatelessWidget {
  final String label;
  final Color? color;

  const StatusChip({super.key, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    final pill = _pill(colors);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: pill.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: pill.foreground,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }

  ({Color background, Color foreground}) _pill(ElevoColors colors) {
    final key = label.toLowerCase();
    const positive = {
      'occupied',
      'signed',
      'resolved',
      'approved',
      'active',
      'complete',
      'paid',
    };
    final urgent = key.contains('due') ||
        {
          'vacant',
          'emergency',
          'high',
          'overdue',
          'declined',
          'open',
        }.contains(key);
    if (positive.contains(key)) {
      return (
        background: colors.isLight ? const Color(0xFFE4EFDA) : const Color(0xFF1C3328),
        foreground: colors.isLight ? const Color(0xFF1F7A4D) : colors.successGreen,
      );
    }
    if (urgent) {
      return (
        background: colors.isLight ? const Color(0xFFF8E2D6) : colors.peachTint,
        foreground: colors.isLight ? const Color(0xFF7A321C) : colors.urgentRed,
      );
    }
    final foreground = color ?? colors.linkOlive;
    return (
      background: colors.isLight ? colors.oliveTint : colors.card,
      foreground: foreground,
    );
  }

}
