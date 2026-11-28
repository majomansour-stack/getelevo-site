import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Elevo visual tokens. Legacy names (`midnight`, `charcoal`, `ivory`, `olive`)
/// stay so existing screens keep compiling. [olive] is the navy primary.
/// `canvas`, `card`, and `terracotta` follow light or dark mode.
@immutable
class ElevoColors extends ThemeExtension<ElevoColors> {
  /// Primary text and icons. Charcoal in light mode, cream in dark mode.
  final Color midnight;

  /// Legacy dark surface. Stays dark in both modes so older cards that put
  /// cream or white type on it remain readable.
  final Color charcoal;

  /// Cream. Text on navy, shade, and photos.
  final Color ivory;

  /// Hairline borders.
  final Color stone;

  /// Secondary text.
  final Color sage;

  /// Bright gold (#C9A227). Marks on navy and other dark surfaces.
  /// Do not use this as text or a link on cream; use [goldInk].
  final Color gold;

  /// Gold used as text or an icon on cream. #7A5E28 is 5.9:1 on the cream card.
  final Color goldInk;

  final Color urgentRed;
  final Color warningAmber;
  final Color successGreen;

  /// Page background.
  final Color canvas;

  /// Raised card. Cream in light mode, a slightly lighter warm charcoal in dark.
  final Color card;

  /// Navy primary (#1F3A5F). The field keeps the name [olive].
  final Color olive;

  /// Cream type on [olive].
  final Color onOlive;

  /// Terracotta used for primary buttons and highlights.
  final Color terracotta;

  final Color onTerracotta;

  /// Bottom navigation surface.
  final Color nav;

  /// Dark warm surface that does not flip. Calendar chrome and photo scrims.
  final Color shade;

  Color get taupe => sage;
  Color get sand => stone;
  Color get ink => midnight;
  Color get muted => sage;
  Color get hairline => stone;

  bool get isLight => canvas.computeLuminance() > 0.5;

  /// Dark header band. Near-black in both modes.
  Color get header => isLight ? const Color(0xFF1F3A5F) : const Color(0xFF0E0D0C);

  Color get onHeader => const Color(0xFFFFFBF6);

  Color get headerMuted => const Color(0xFFC9BFAF);

  Color get oliveTint => isLight ? const Color(0xFFE6EEF6) : const Color(0xFF24344E);

  Color get peachTint => isLight ? const Color(0xFFFCE9DE) : const Color(0xFF3A2C26);

  /// Warm sand wash. Kept distinct from the navy tint and from success green.
  Color get sageTint => isLight ? const Color(0xFFF3E6D4) : const Color(0xFF3A3228);

  /// Gold accent on the navy header.
  Color get oliveBar => const Color(0xFFC9A227);

  /// Navy text and icons on the page. #1F3A5F on cream is 11:1.
  Color get linkOlive => isLight ? olive : const Color(0xFFE4C98A);

  const ElevoColors({
    required this.midnight,
    required this.charcoal,
    required this.ivory,
    required this.stone,
    required this.sage,
    required this.gold,
    required this.goldInk,
    required this.urgentRed,
    required this.warningAmber,
    required this.successGreen,
    required this.canvas,
    required this.card,
    required this.olive,
    required this.onOlive,
    required this.terracotta,
    required this.onTerracotta,
    required this.nav,
    required this.shade,
  });

  static const light = ElevoColors(
    midnight: Color(0xFF2F2A24),
    charcoal: Color(0xFF201E1A),
    ivory: Color(0xFFFFFBF6),
    stone: Color(0xFFE4D8C8),
    sage: Color(0xFF534C43),
    gold: Color(0xFFC9A227),
    goldInk: Color(0xFF7A5E28),
    urgentRed: Color(0xFF7A321C),
    warningAmber: Color(0xFF7A5A28),
    successGreen: Color(0xFF1F7A4D),
    canvas: Color(0xFFF6EFE2),
    card: Color(0xFFFFFBF6),
    olive: Color(0xFF1F3A5F),
    onOlive: Color(0xFFFFFBF6),
    terracotta: Color(0xFF7A5E28),
    onTerracotta: Color(0xFFFFFBF6),
    nav: Color(0xFF1F3A5F),
    shade: Color(0xFF1F3A5F),
  );

  static const dark = ElevoColors(
    midnight: Color(0xFFFFFBF6),
    charcoal: Color(0xFF201E1A),
    ivory: Color(0xFFFFFBF6),
    stone: Color(0xFF3A342C),
    sage: Color(0xFFD4CBBF),
    gold: Color(0xFFC9A227),
    goldInk: Color(0xFFE4C98A),
    urgentRed: Color(0xFFF0B8A4),
    warningAmber: Color(0xFFE4C98A),
    successGreen: Color(0xFF7DCEA0),
    canvas: Color(0xFF141311),
    card: Color(0xFF24211C),
    olive: Color(0xFF1F3A5F),
    onOlive: Color(0xFFFFFBF6),
    terracotta: Color(0xFFC9A227),
    onTerracotta: Color(0xFFFFFBF6),
    nav: Color(0xFF0E0D0C),
    shade: Color(0xFF0E0D0C),
  );

  @override
  ElevoColors copyWith({
    Color? midnight,
    Color? charcoal,
    Color? ivory,
    Color? stone,
    Color? sage,
    Color? gold,
    Color? goldInk,
    Color? urgentRed,
    Color? warningAmber,
    Color? successGreen,
    Color? canvas,
    Color? card,
    Color? olive,
    Color? onOlive,
    Color? terracotta,
    Color? onTerracotta,
    Color? nav,
    Color? shade,
  }) =>
      ElevoColors(
        midnight: midnight ?? this.midnight,
        charcoal: charcoal ?? this.charcoal,
        ivory: ivory ?? this.ivory,
        stone: stone ?? this.stone,
        sage: sage ?? this.sage,
        gold: gold ?? this.gold,
        goldInk: goldInk ?? this.goldInk,
        urgentRed: urgentRed ?? this.urgentRed,
        warningAmber: warningAmber ?? this.warningAmber,
        successGreen: successGreen ?? this.successGreen,
        canvas: canvas ?? this.canvas,
        card: card ?? this.card,
        olive: olive ?? this.olive,
        onOlive: onOlive ?? this.onOlive,
        terracotta: terracotta ?? this.terracotta,
        onTerracotta: onTerracotta ?? this.onTerracotta,
        nav: nav ?? this.nav,
        shade: shade ?? this.shade,
      );

  @override
  ElevoColors lerp(covariant ThemeExtension<ElevoColors>? other, double t) {
    if (other is! ElevoColors) return this;
    return ElevoColors(
      midnight: Color.lerp(midnight, other.midnight, t)!,
      charcoal: Color.lerp(charcoal, other.charcoal, t)!,
      ivory: Color.lerp(ivory, other.ivory, t)!,
      stone: Color.lerp(stone, other.stone, t)!,
      sage: Color.lerp(sage, other.sage, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      goldInk: Color.lerp(goldInk, other.goldInk, t)!,
      urgentRed: Color.lerp(urgentRed, other.urgentRed, t)!,
      warningAmber: Color.lerp(warningAmber, other.warningAmber, t)!,
      successGreen: Color.lerp(successGreen, other.successGreen, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      card: Color.lerp(card, other.card, t)!,
      olive: Color.lerp(olive, other.olive, t)!,
      onOlive: Color.lerp(onOlive, other.onOlive, t)!,
      terracotta: Color.lerp(terracotta, other.terracotta, t)!,
      onTerracotta: Color.lerp(onTerracotta, other.onTerracotta, t)!,
      nav: Color.lerp(nav, other.nav, t)!,
      shade: Color.lerp(shade, other.shade, t)!,
    );
  }
}

class AppTheme {
  AppTheme._();

  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;
  static const double spacingXxl = 48.0;

  static const double radiusSmall = 8.0;
  static const double radiusMedium = 14.0;
  static const double radiusLarge = 16.0;
  static const double radiusXl = 16.0;

  static const double buttonHeight = 52.0;
  static const double touchTarget = 48.0;

  /// Light palette. Kept for call sites that read colors without a [BuildContext].
  static const elevoColors = ElevoColors.light;

  static final ThemeData lightTheme = _buildTheme(ElevoColors.light);
  static final ThemeData darkTheme = _buildTheme(ElevoColors.dark);

  /// Gold fill with near-black label. [gold] is bright in both themes, so the
  /// label cannot follow [ElevoColors.ink] or it turns cream-on-gold in dark mode.
  static ButtonStyle goldFillButton(ElevoColors colors, TextTheme text) {
    final onGold = colors.shade;
    return ElevatedButton.styleFrom(
      backgroundColor: colors.gold,
      foregroundColor: onGold,
      disabledBackgroundColor: colors.gold.withAlpha(110),
      disabledForegroundColor: onGold.withAlpha(170),
      elevation: 0,
      textStyle: text.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: onGold,
      ),
    );
  }

  static List<BoxShadow> cardShadow(ElevoColors colors) => [
        BoxShadow(
          color: const Color(0xFF1C1A17).withAlpha(colors.isLight ? 15 : 46),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  static BoxDecoration surfaceCard(
    ElevoColors colors, {
    Color? color,
    bool shadow = true,
    Border? border,
  }) {
    return BoxDecoration(
      color: color ?? colors.card,
      borderRadius: BorderRadius.circular(radiusXl),
      border: border ?? Border.all(color: colors.stone.withAlpha(160)),
      boxShadow: shadow ? cardShadow(colors) : null,
    );
  }

  static TextStyle serif(
    TextStyle? base, {
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
  }) {
    return GoogleFonts.manrope(
      color: color ?? base?.color,
      fontSize: fontSize ?? base?.fontSize,
      fontWeight: fontWeight ?? base?.fontWeight ?? FontWeight.w800,
      height: base?.height,
      letterSpacing: -0.4,
    );
  }

  static ThemeData _buildTheme(ElevoColors c) {
    final isLight = c.canvas.computeLuminance() > 0.5;
    final textTheme = _textTheme(c);

    final scheme = ColorScheme(
      brightness: isLight ? Brightness.light : Brightness.dark,
      primary: c.olive,
      onPrimary: c.onOlive,
      secondary: c.olive,
      onSecondary: c.onOlive,
      tertiary: c.gold,
      onTertiary: c.shade,
      error: c.urgentRed,
      onError: const Color(0xFFFFFCF7),
      surface: c.card,
      onSurface: c.ink,
      outline: c.stone,
      outlineVariant: c.stone.withAlpha(140),
      shadow: c.shade.withAlpha(30),
      surfaceContainerHighest: isLight ? const Color(0xFFF3EDE3) : const Color(0xFF2E2A26),
    );

    final radius = BorderRadius.circular(radiusLarge);

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      scaffoldBackgroundColor: c.canvas,
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(color: c.ink, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: c.canvas,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: c.ink),
      ),
      cardTheme: CardThemeData(
        color: c.card,
        elevation: 0,
        shadowColor: c.shade.withAlpha(20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: BorderSide(color: c.stone.withAlpha(140)),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, buttonHeight),
          backgroundColor: c.olive,
          foregroundColor: c.onOlive,
          disabledBackgroundColor: c.olive.withAlpha(90),
          disabledForegroundColor: c.onOlive.withAlpha(180),
          elevation: 0,
          side: isLight ? null : const BorderSide(color: Color(0xFFC9A227), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: c.onOlive,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, buttonHeight),
          backgroundColor: c.olive,
          foregroundColor: c.onOlive,
          disabledBackgroundColor: c.olive.withAlpha(90),
          disabledForegroundColor: c.onOlive.withAlpha(180),
          elevation: 0,
          side: isLight ? null : const BorderSide(color: Color(0xFFC9A227), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: c.onOlive,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, buttonHeight),
          backgroundColor: Colors.transparent,
          foregroundColor: c.ink,
          side: BorderSide(color: c.stone),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.linkOlive),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.card,
        hintStyle: TextStyle(color: c.sage),
        labelStyle: TextStyle(color: c.sage),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: c.stone),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: c.stone),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: c.linkOlive, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: isLight ? c.olive : c.linkOlive,
        foregroundColor: isLight ? c.onOlive : const Color(0xFF141311),
        elevation: 2,
        shape: const CircleBorder(),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.nav,
        selectedItemColor: c.ink,
        unselectedItemColor: c.sage,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 11),
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.nav,
        indicatorColor: c.olive.withAlpha(28),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.inter(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? c.ink : c.sage,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? c.ink : c.sage, size: 22);
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.ink,
        unselectedLabelColor: c.sage,
        indicatorColor: c.linkOlive,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.gold.withAlpha(28),
        selectedColor: c.olive,
        labelStyle: GoogleFonts.inter(color: c.ink, fontSize: 12, fontWeight: FontWeight.w600),
        secondaryLabelStyle: GoogleFonts.inter(color: c.onOlive, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        shape: const StadiumBorder(),
        side: BorderSide.none,
      ),
      dividerTheme: DividerThemeData(color: c.stone.withAlpha(180), thickness: 0.5, space: 1),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onOlive : c.sage,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.linkOlive : c.stone,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.linkOlive),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.shade,
        contentTextStyle: GoogleFonts.inter(color: c.ivory),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXl)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.canvas,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.linkOlive,
        textColor: c.ink,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodySmall,
      ),
      extensions: [c],
    );
  }

  static TextTheme _textTheme(ElevoColors c) {
    TextStyle serifStyle({
      required double fontSize,
      FontWeight weight = FontWeight.w500,
      Color? color,
      double letterSpacing = -0.4,
    }) {
      return GoogleFonts.manrope(
        fontWeight: weight,
        color: color ?? c.ink,
        fontSize: fontSize,
        letterSpacing: letterSpacing,
        height: 1.15,
      );
    }

    TextStyle sans({
      required double fontSize,
      FontWeight weight = FontWeight.w400,
      Color? color,
    }) {
      return GoogleFonts.inter(
        fontWeight: weight,
        color: color ?? c.ink,
        fontSize: fontSize,
        height: 1.4,
      );
    }

    return TextTheme(
      displayLarge: serifStyle(fontSize: 48, weight: FontWeight.w500),
      displayMedium: serifStyle(fontSize: 40, weight: FontWeight.w500),
      displaySmall: serifStyle(fontSize: 34, weight: FontWeight.w500),
      headlineLarge: serifStyle(fontSize: 36, weight: FontWeight.w800),
      headlineMedium: serifStyle(fontSize: 30, weight: FontWeight.w800),
      headlineSmall: serifStyle(fontSize: 24, weight: FontWeight.w800),
      titleLarge: serifStyle(fontSize: 22, weight: FontWeight.w800),
      titleMedium: sans(fontSize: 16, weight: FontWeight.w600),
      titleSmall: sans(fontSize: 14, weight: FontWeight.w600, color: c.sage),
      bodyLarge: sans(fontSize: 16),
      bodyMedium: sans(fontSize: 15),
      bodySmall: sans(fontSize: 13, color: c.sage),
      labelLarge: sans(fontSize: 15, weight: FontWeight.w600),
      labelMedium: sans(fontSize: 13, weight: FontWeight.w500, color: c.sage),
      labelSmall: sans(fontSize: 11, weight: FontWeight.w500, color: c.sage),
    );
  }
}
