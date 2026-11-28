import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/theme.dart';

class ElevoWordmark extends StatelessWidget {
  /// Controls the rendered height of the logo image.
  /// The original lockup is ~3:2 landscape so width scales automatically.
  final double fontSize;
  final bool showTagline;

  const ElevoWordmark({super.key, this.fontSize = 40, this.showTagline = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    // Logo height derived from fontSize for proportional scaling.
    // The full lockup (house mark + wordmark) is used; height ≈ 2.4× font size.
    final logoHeight = fontSize * 2.4;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/elevo_logo.png',
          height: logoHeight,
          fit: BoxFit.contain,
        ),
        if (showTagline) ...[
          const SizedBox(height: AppTheme.spacingSm),
          Text(
            'Property management, elevated.',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              letterSpacing: 1.5,
              color: colors.midnight,
            ),
          ),
        ],
      ],
    );
  }
}
