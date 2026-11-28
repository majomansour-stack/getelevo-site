// =============================================================================
// ELEVO — Auth screens (Login, Sign up, Terms)
// -----------------------------------------------------------------------------
// Self-contained, pure Flutter Material. Null-safe, Dart 3, no packages,
// no network images, no asset files required.
//
// Public widgets:
//   ElevoLoginScreen    -> route '/login'
//   ElevoSignUpScreen   -> route '/signup'
//   ElevoTermsScreen    -> route '/terms'
//   ElevoPrivacyScreen  -> route '/privacy'
//
// Every action is a constructor callback. If a callback is not supplied, a
// safe default runs (a SnackBar, or a simple navigation) so this file compiles
// and runs on its own. Throw ElevoAuthException('message') from any callback
// to show that message inline on the form.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../legal/elevo_legal_copy.dart';

// -----------------------------------------------------------------------------
// Brand tokens
// -----------------------------------------------------------------------------

class ElevoColors {
  ElevoColors._();

  static const Color navy = Color(0xFF1F3A5F);
  static const Color olive = Color(0xFF1F3A5F);
  /// Interactive navy on dark surfaces. #5B7FB0 is 3.9:1 on the dark card;
  static const Color oliveLinkDark = Color(0xFFC9A227);
  static const Color gold = Color(0xFFC9A227); // bright gold on navy
  static const Color goldFocus = Color(0xFF1F3A5F); // focused controls are navy
  static const Color goldDeep = Color(0xFF7A5E28); // gold text on cream, 5.9:1
  static const Color goldTint = Color(0xFFFBF6EC);
  static const Color beige = Color(0xFFF6F1E8);
  static const Color ink = Color(0xFF2C2825);
  static const Color muted = Color(0xFF5E5852);
  static const Color border = Color(0xFFE4DCD0);
  static const Color cardBorder = Color(0xFFE8E0D4);
  static const Color canvasDark = Color(0xFF141210);
  static const Color cardDark = Color(0xFF24211C);
  static const Color inkDark = Color(0xFFF3EEE4);
  static const Color mutedDark = Color(0xFFC8BBAE);
  static const Color borderDark = Color(0xFF3A342C);
  static const Color error = Color(0xFFB4372F);
  static const Color errorTint = Color(0xFFFBECEA);
  static const Color success = Color(0xFF2F7D5B);
  static const Color warning = Color(0xFFA35A12);
}

/// Throw this from any callback to show [message] inline on the form.
class ElevoAuthException implements Exception {
  const ElevoAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum ElevoRole { landlord, tenant, vendor }

/// Google and Apple buttons (and the "or" divider) stay hidden until real
/// Google/Apple sign-in is set up. Set to true to show them again.
const bool _kShowSocialSignIn = false;

/// Everything the sign-up form collects.
class ElevoSignUpData {
  const ElevoSignUpData({
    required this.role,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.password,
    this.vendorDetails = const {},
    this.referralCode = '',
  });

  final ElevoRole role;
  final String fullName;
  final String email;
  final String phone;
  final String password;

  /// Only filled for vendors: company_name, service_type, service_area and
  /// (when given) license_number.
  final Map<String, String> vendorDetails;
  final String referralCode;
}

typedef ElevoAction = FutureOr<void> Function(BuildContext context);
typedef ElevoSignInAction = FutureOr<void> Function(
  BuildContext context,
  String email,
  String password,
);
typedef ElevoEmailAction = FutureOr<void> Function(BuildContext context, String email);
typedef ElevoSignUpAction = FutureOr<void> Function(BuildContext context, ElevoSignUpData data);

void _showStub(BuildContext context, String name) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('$name is not connected yet. Wire it to your auth logic.'),
    ),
  );
}

ThemeData _elevoAuthTheme(BuildContext context) {
  final base = Theme.of(context);
  final dark = base.brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: ElevoColors.olive,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: ElevoColors.olive,
    onPrimary: const Color(0xFFFFFCF7),
    secondary: ElevoColors.gold,
    onSecondary: dark ? ElevoColors.inkDark : ElevoColors.ink,
    error: ElevoColors.error,
    surface: dark ? ElevoColors.cardDark : Colors.white,
    onSurface: dark ? ElevoColors.inkDark : ElevoColors.ink,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? ElevoColors.canvasDark : ElevoColors.beige,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: ElevoColors.navy,
      selectionColor: ElevoColors.gold.withAlpha(90),
      selectionHandleColor: ElevoColors.goldFocus,
    ),
  );
}

final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

String? _validateEmail(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return 'Enter your email address';
  if (!_emailPattern.hasMatch(v)) return 'Enter a valid email, like name@example.com';
  return null;
}

String _friendlyError(Object error, String fallback) {
  if (error is ElevoAuthException) return error.message;
  return fallback;
}

// -----------------------------------------------------------------------------
// Logo — house-E mark + ELEVO wordmark. One Text widget inside a FittedBox,
// so it scales to any size without dropping or repeating letters.
// -----------------------------------------------------------------------------

class ElevoLogo extends StatelessWidget {
  const ElevoLogo({super.key, this.height = 40, this.onDark = false, this.showWordmark = true});

  final double height;
  final bool onDark;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Elevo',
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(
                  size: const Size(48, 48),
                  painter: _HouseEMarkPainter(onDark: onDark),
                ),
                if (showWordmark) ...[
                  const SizedBox(width: 12),
                  Text(
                    'Elevo',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    textScaler: TextScaler.noScaling,
                    style: GoogleFonts.manrope(
                      fontSize: 32,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: onDark ? Colors.white : ElevoColors.ink,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HouseEMarkPainter extends CustomPainter {
  const _HouseEMarkPainter({required this.onDark});

  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);

    final roof = Paint()
      ..color = ElevoColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final roofPath = Path()
      ..moveTo(5, 22)
      ..lineTo(24, 6)
      ..lineTo(43, 22);
    canvas.drawPath(roofPath, roof);

    final e = Paint()..color = onDark ? Colors.white : ElevoColors.navy;
    const r = Radius.circular(1.5);
    canvas.drawRRect(RRect.fromLTRBR(12, 24, 17, 43, r), e); // spine
    canvas.drawRRect(RRect.fromLTRBR(12, 24, 36, 28.5, r), e); // top
    canvas.drawRRect(RRect.fromLTRBR(12, 31.5, 32, 35.5, r), e); // middle
    canvas.drawRRect(RRect.fromLTRBR(12, 38.5, 36, 43, r), e); // bottom
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HouseEMarkPainter oldDelegate) => oldDelegate.onDark != onDark;
}

// -----------------------------------------------------------------------------
// Hero — flat navy. No gradient and no skyline.
// -----------------------------------------------------------------------------

class _Benefit {
  const _Benefit(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

const List<_Benefit> _benefits = [
  _Benefit(
    Icons.account_balance_wallet_outlined,
    'Rent records',
    'Landlords keep the record. Tenants track rent. Elevo does not collect it.',
  ),
  _Benefit(
    Icons.build_outlined,
    'Maintenance requests',
    'Tenants report issues with photos. You track every fix.',
  ),
  _Benefit(
    Icons.forum_outlined,
    'Tenant & vendor messaging',
    'Every conversation stays tied to the right property.',
  ),
];

class ElevoHeroPanel extends StatelessWidget {
  const ElevoHeroPanel({super.key, this.compact = false, this.backgroundImage, this.leading});

  final bool compact;

  /// Accepted so existing callers keep compiling. It is not painted, so the
  /// panel stays a flat navy on every width.
  final ImageProvider? backgroundImage;

  /// Optional widget shown above the logo (e.g. a back button on mobile).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    // Phone and wide layouts share this widget. A gradient made the tall
    // laptop panel a different color than the short phone strip. A flat navy
    // fill keeps them identical, and a supplied photo is not painted.
    return Container(
      color: ElevoColors.navy,
      child: SafeArea(
        right: false,
        bottom: !compact,
        child: compact ? _buildCompact() : _buildFull(),
      ),
    );
  }

  Widget _buildCompact() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) leading! else const SizedBox(height: 12),
          const SizedBox(height: 8),
          const ElevoLogo(height: 30, onDark: true),
          const SizedBox(height: 20),
          Semantics(
            header: true,
            child: Text(
              'Run every property from one place.',
              style: GoogleFonts.manrope(
                color: Color(0xFFFFFBF6),
                fontSize: 28,
                height: 1.15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in _benefits)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withAlpha(36)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(b.icon, size: 15, color: ElevoColors.gold),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          b.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFull() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(56, 48, 56, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ElevoLogo(height: 36, onDark: true),
                    const Spacer(),
                    const SizedBox(height: 40),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 3,
                            decoration: BoxDecoration(
                              color: ElevoColors.gold,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Semantics(
                            header: true,
                            child: const Text(
                              'Run every property from one place.',
                              style: TextStyle(
                                color: Color(0xFFFFFBF6),
                                fontSize: 44,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Elevo brings landlords, tenants and vendors together, '
                            'so rent, repairs and conversations never slip through the cracks.',
                            style: TextStyle(
                              color: Color(0xFFFFFBF6),
                              fontSize: 16.5,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 36),
                          for (final b in _benefits) ...[
                            _BenefitRow(benefit: b),
                            const SizedBox(height: 20),
                          ],
                        ],
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Icon(Icons.lock_outline, size: 16, color: ElevoColors.gold),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Encrypted sign-in  ·  Built for independent landlords',
                            style: const TextStyle(
                              color: Color(0xFFFFFBF6),
                              fontSize: 13,
                              letterSpacing: 0.2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.benefit});
  final _Benefit benefit;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: ElevoColors.gold.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ElevoColors.gold.withAlpha(90)),
            ),
            child: Icon(benefit.icon, color: ElevoColors.gold, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  benefit.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  benefit.body,
                  style: const TextStyle(
                    color: Color(0xFFFFFBF6),
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Layout shell — split at >= 900px, stacked below.
// -----------------------------------------------------------------------------

class ElevoAuthLayout extends StatelessWidget {
  const ElevoAuthLayout({
    super.key,
    required this.child,
    this.heroImage,
    this.onBack,
    this.barHeroOnNarrow = false,
  });

  static const double breakpoint = 900;

  final Widget child;
  final ImageProvider? heroImage;
  final VoidCallback? onBack;

  /// On a phone, use a short navy bar instead of the marketing hero so a long
  /// form can scroll its primary button fully into view.
  final bool barHeroOnNarrow;

  Widget _backButton(Color color) => IconButton(
    tooltip: 'Back',
    onPressed: onBack,
    iconSize: 24,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    icon: Icon(Icons.arrow_back_rounded, color: color),
  );

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _elevoAuthTheme(context),
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= breakpoint;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 5, child: ElevoHeroPanel(backgroundImage: heroImage)),
                  Expanded(
                    flex: 6,
                    child: SafeArea(
                      left: false,
                      child: Stack(
                        children: [
                          Center(
                            child: SingleChildScrollView(
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(32, 48, 32, 64),
                              child: _AuthCard(child: child),
                            ),
                          ),
                          if (onBack != null)
                            Positioned(top: 12, left: 12, child: _backButton(ElevoColors.navy)),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (barHeroOnNarrow)
                    _NarrowAuthBar(onBack: onBack)
                  else
                    ElevoHeroPanel(
                      compact: true,
                      backgroundImage: heroImage,
                      leading: onBack == null ? null : _backButton(Colors.white),
                    ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 48),
                      child: Center(child: _AuthCard(compact: true, child: child)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Short navy strip used when a phone form is too tall for the marketing hero.
class _NarrowAuthBar extends StatelessWidget {
  const _NarrowAuthBar({required this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ElevoColors.navy,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 12),
          child: Row(
            children: [
              if (onBack != null)
                IconButton(
                  tooltip: 'Back',
                  onPressed: onBack,
                  iconSize: 24,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                )
              else
                const SizedBox(width: 12),
              const ElevoLogo(height: 28, onDark: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({required this.child, this.compact = false});
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 32, vertical: compact ? 28 : 36),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? ElevoColors.borderDark
                : ElevoColors.cardBorder,
          ),
          boxShadow: [
            BoxShadow(
              color: ElevoColors.navy.withAlpha(18),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Shared form parts
// -----------------------------------------------------------------------------

class ElevoAuthHeading extends StatelessWidget {
  const ElevoAuthHeading({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: GoogleFonts.manrope(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 32,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? ElevoColors.mutedDark
                : ElevoColors.muted,
            fontSize: 15,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class ElevoTextField extends StatefulWidget {
  const ElevoTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.autofillHints,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.obscure = false,
    this.enabled = true,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? hint;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool obscure;
  final bool enabled;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<ElevoTextField> createState() => _ElevoTextFieldState();
}

class _ElevoTextFieldState extends State<ElevoTextField> {
  bool _hidden = true;

  OutlineInputBorder _border(Color color, [double width = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color, width: width),
  );

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? ElevoColors.mutedDark
        : ElevoColors.muted;
    final Widget? suffix = widget.obscure
        ? IconButton(
            tooltip: _hidden ? 'Show password' : 'Hide password',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => setState(() => _hidden = !_hidden),
            icon: Icon(
              _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: muted,
              size: 20,
            ),
          )
        : null;

    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofillHints: widget.enabled ? widget.autofillHints : null,
      obscureText: widget.obscure && _hidden,
      enableSuggestions: !widget.obscure,
      autocorrect: false,
      textCapitalization: widget.textCapitalization,
      inputFormatters: widget.inputFormatters,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        filled: true,
        fillColor: widget.enabled
            ? Theme.of(context).colorScheme.surface
            : (Theme.of(context).brightness == Brightness.dark
                ? ElevoColors.canvasDark
                : const Color(0xFFF3F1EC)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: TextStyle(color: muted, fontSize: 15),
        floatingLabelStyle: TextStyle(
          color: Theme.of(context).brightness == Brightness.dark
              ? ElevoColors.oliveLinkDark
              : ElevoColors.navy,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(color: muted, fontSize: 15),
        errorStyle: const TextStyle(color: ElevoColors.error, fontSize: 12.5),
        errorMaxLines: 2,
        prefixIcon: Icon(widget.icon, size: 20, color: muted),
        suffixIcon: suffix,
        border: _border(ElevoColors.border),
        enabledBorder: _border(ElevoColors.border),
        disabledBorder: _border(ElevoColors.cardBorder),
        focusedBorder: _border(
          Theme.of(context).brightness == Brightness.dark ? ElevoColors.oliveLinkDark : ElevoColors.navy,
          2,
        ),
        errorBorder: _border(ElevoColors.error),
        focusedErrorBorder: _border(ElevoColors.error, 2),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 20,
    height: 20,
    child: CircularProgressIndicator(strokeWidth: 2.2, color: color),
  );
}

class ElevoPrimaryButton extends StatelessWidget {
  const ElevoPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled && !loading,
      label: loading ? '$label, loading' : label,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: enabled ? (loading ? () {} : onPressed) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: ElevoColors.olive,
            foregroundColor: const Color(0xFFFFFBF6),
            disabledBackgroundColor: const Color(0xFFC5D0DE),
            disabledForegroundColor: const Color(0xFF6E625C),
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          child: loading ? const _Spinner(color: Colors.white) : Text(label),
        ),
      ),
    );
  }
}

class ElevoSecondaryButton extends StatelessWidget {
  const ElevoSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.leading,
    this.loading = false,
    this.borderColor = ElevoColors.navy,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? leading;
  final bool loading;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final border = dark && borderColor == ElevoColors.navy ? ElevoColors.oliveLinkDark : borderColor;
    final lead = leading ?? (icon == null ? null : Icon(icon, size: 20, color: dark ? ElevoColors.oliveLinkDark : ElevoColors.navy));
    return Semantics(
      button: true,
      enabled: onPressed != null && !loading,
      label: loading ? '$label, loading' : label,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton(
          onPressed: onPressed == null ? null : (loading ? () {} : onPressed),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            backgroundColor: Theme.of(context).colorScheme.surface,
            side: BorderSide(color: border, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
          ),
          child: loading
              ? const _Spinner(color: ElevoColors.navy)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (lead != null) ...[lead, const SizedBox(width: 10)],
                    Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                  ],
                ),
        ),
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ElevoColors.border),
      ),
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 13,
          height: 1,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1A73E8),
        ),
      ),
    );
  }
}

class ElevoAuthLink extends StatelessWidget {
  const ElevoAuthLink({
    required this.label,
    required this.onPressed,
    this.trailingIcon,
    this.onLightSurface = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? trailingIcon;

  /// The vendor row stays on a cream chip in both themes, so its link
  /// keeps the navy that passes on cream.
  final bool onLightSurface;

  @override
  Widget build(BuildContext context) {
    final darkPage = Theme.of(context).brightness == Brightness.dark;
    final link = darkPage && !onLightSurface
        ? ElevoColors.oliveLinkDark
        : ElevoColors.olive;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: link,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.padded,
        textStyle: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: link,
        ),
      ),
      child: trailingIcon == null
          ? Text(label)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(label)),
                const SizedBox(width: 4),
                Icon(trailingIcon, size: 18),
              ],
            ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: ElevoColors.cardBorder, thickness: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text('or', style: TextStyle(color: ElevoColors.muted, fontSize: 13.5)),
        ),
        Expanded(child: Divider(color: ElevoColors.cardBorder, thickness: 1)),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onClose});
  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        decoration: BoxDecoration(
          color: ElevoColors.errorTint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ElevoColors.error.withAlpha(70)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: ElevoColors.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: ElevoColors.error, fontSize: 14, height: 1.35),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onClose,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.close, size: 18, color: ElevoColors.error),
            ),
          ],
        ),
      ),
    );
  }
}

/// Runs [cb] (or the stub) and returns a friendly error string, or null.
Future<String?> _invoke(BuildContext context, ElevoAction? cb, String name, String fallback) async {
  try {
    if (cb == null) {
      _showStub(context, name);
    } else {
      await cb(context);
    }
    return null;
  } catch (e) {
    return _friendlyError(e, fallback);
  }
}

/// Default navigation: try the named route, fall back to pushing [fallback].
void _pushNamedOr(BuildContext context, String route, WidgetBuilder fallback) {
  final navigator = Navigator.of(context);
  try {
    navigator.pushNamed(route);
  } catch (_) {
    navigator.push(MaterialPageRoute<void>(builder: fallback));
  }
}

// -----------------------------------------------------------------------------
// LOGIN
// -----------------------------------------------------------------------------

enum _LoginBusy { none, signIn, google, apple }

class ElevoLoginScreen extends StatefulWidget {
  const ElevoLoginScreen({
    super.key,
    this.onSignIn,
    this.onSignUp,
    this.onForgotPassword,
    this.onResendConfirmation,
    this.onGoogle,
    this.onApple,
    this.onVendorPortal,
    this.heroImage,
    this.initialEmail,
    this.initialError,
  });

  /// Email + password sign-in. Throw ElevoAuthException to show a message.
  final ElevoSignInAction? onSignIn;

  /// "Create an account" link. Default: pushNamed('/signup'), falling back
  /// to pushing ElevoSignUpScreen if that route doesn't exist.
  final ElevoAction? onSignUp;

  /// Receives whatever is currently typed in the email field.
  final ElevoEmailAction? onForgotPassword;
  final ElevoEmailAction? onResendConfirmation;
  final ElevoAction? onGoogle;
  final ElevoAction? onApple;
  final ElevoAction? onVendorPortal;

  /// Accepted for existing callers. The hero does not paint it.
  final ImageProvider? heroImage;
  final String? initialEmail;
  final String? initialError;

  @override
  State<ElevoLoginScreen> createState() => _ElevoLoginScreenState();
}

class _ElevoLoginScreenState extends State<ElevoLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(text: widget.initialEmail ?? '');
  final _password = TextEditingController();
  _LoginBusy _busy = _LoginBusy.none;
  bool _submitted = false;
  late String? _error = widget.initialError;

  bool get _isBusy => _busy != _LoginBusy.none;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(_LoginBusy kind, Future<void> Function() task, String fallback) async {
    if (_isBusy) return;
    setState(() {
      _busy = kind;
      _error = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e, fallback));
    } finally {
      if (mounted) setState(() => _busy = _LoginBusy.none);
    }
  }

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();
    setState(() => _submitted = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await _run(_LoginBusy.signIn, () async {
      final cb = widget.onSignIn;
      if (cb == null) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (mounted) _showStub(context, 'onSignIn');
      } else {
        await cb(context, _email.text.trim(), _password.text);
      }
      TextInput.finishAutofillContext();
    }, "We couldn't sign you in. Check your connection and try again.");
  }

  Future<void> _social(_LoginBusy kind, ElevoAction? cb, String name) => _run(kind, () async {
    if (cb == null) {
      _showStub(context, 'on$name');
    } else {
      await cb(context);
    }
  }, "$name sign-in didn't finish. Please try again.");

  Future<void> _simple(ElevoAction? cb, String name, String fallback) async {
    final err = await _invoke(context, cb, name, fallback);
    if (err != null && mounted) setState(() => _error = err);
  }

  Future<void> _forgot() async {
    final cb = widget.onForgotPassword;
    if (cb == null) {
      _showStub(context, 'onForgotPassword');
      return;
    }
    try {
      await cb(context, _email.text.trim());
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = _friendlyError(e, "We couldn't send a reset link. Please try again."),
        );
      }
    }
  }

  void _openSignUp() {
    final cb = widget.onSignUp;
    if (cb != null) {
      _simple(cb, 'onSignUp', "Couldn't open sign up. Please try again.");
    } else {
      _pushNamedOr(context, '/signup', (_) => const ElevoSignUpScreen());
    }
  }

  VoidCallback? _guard(_LoginBusy kind, VoidCallback action) =>
      _isBusy && _busy != kind ? null : action;

  @override
  Widget build(BuildContext context) {
    return ElevoAuthLayout(
      heroImage: widget.heroImage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ElevoAuthHeading(
            title: 'Welcome back',
            subtitle: 'Sign in to manage your properties, tenants and requests.',
          ),
          const SizedBox(height: 28),
          if (_error != null)
            _ErrorBanner(message: _error!, onClose: () => setState(() => _error = null)),
          if (_error != null &&
              _error!.contains('Confirm your email') &&
              widget.onResendConfirmation != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _isBusy
                    ? null
                    : () => _simple(
                          (ctx) => widget.onResendConfirmation!(ctx, _email.text.trim()),
                          'onResendConfirmation',
                          "Couldn't resend the confirmation email. Please try again.",
                        ),
                child: const Text('Resend confirmation email'),
              ),
            ),
          ],
          AutofillGroup(
            child: Form(
              key: _formKey,
              autovalidateMode: _submitted
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevoTextField(
                    controller: _email,
                    label: 'Email',
                    hint: 'name@example.com',
                    icon: Icons.mail_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: _validateEmail,
                    enabled: !_isBusy,
                  ),
                  const SizedBox(height: 16),
                  ElevoTextField(
                    controller: _password,
                    label: 'Password',
                    hint: 'Your password',
                    icon: Icons.lock_outline_rounded,
                    obscure: true,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                    onSubmitted: (_) => _signIn(),
                    enabled: !_isBusy,
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: ElevoAuthLink(label: 'Forgot password?', onPressed: _isBusy ? null : _forgot),
          ),
          const SizedBox(height: 8),
          ElevoPrimaryButton(
            label: 'Sign in',
            loading: _busy == _LoginBusy.signIn,
            onPressed: _guard(_LoginBusy.signIn, _signIn),
          ),
          const SizedBox(height: 24),
          if (_kShowSocialSignIn) ...[
            const _OrDivider(),
            const SizedBox(height: 20),
            ElevoSecondaryButton(
              label: 'Continue with Google',
              leading: const _GoogleMark(),
              borderColor: ElevoColors.border,
              loading: _busy == _LoginBusy.google,
              onPressed: _guard(
                _LoginBusy.google,
                () => _social(_LoginBusy.google, widget.onGoogle, 'Google'),
              ),
            ),
            const SizedBox(height: 12),
            ElevoSecondaryButton(
              label: 'Continue with Apple',
              icon: Icons.apple,
              borderColor: ElevoColors.border,
              loading: _busy == _LoginBusy.apple,
              onPressed: _guard(
                _LoginBusy.apple,
                () => _social(_LoginBusy.apple, widget.onApple, 'Apple'),
              ),
            ),
            const SizedBox(height: 24),
          ],
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'New to Elevo?',
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? ElevoColors.mutedDark
                      : ElevoColors.muted,
                  fontSize: 14.5,
                ),
              ),
              ElevoAuthLink(label: 'Create an account', onPressed: _isBusy ? null : _openSignUp),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            decoration: BoxDecoration(
              color: ElevoColors.beige,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ElevoColors.cardBorder),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.briefcase, size: 18, color: ElevoColors.olive),
                    SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Are you a vendor?',
                        style: TextStyle(
                          color: ElevoColors.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                ElevoAuthLink(
                  onLightSurface: true,
                  label: 'Vendor / Partner Portal',
                  trailingIcon: Icons.arrow_forward_rounded,
                  onPressed: _isBusy
                      ? null
                      : () => _simple(
                          widget.onVendorPortal,
                          'onVendorPortal',
                          "Couldn't open the Vendor Portal. Please try again.",
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SIGN UP
// -----------------------------------------------------------------------------

class _RoleInfo {
  const _RoleInfo(this.role, this.icon, this.title, this.body);
  final ElevoRole role;
  final IconData icon;
  final String title;
  final String body;
}

const List<_RoleInfo> _roles = [
  _RoleInfo(
    ElevoRole.landlord,
    Icons.apartment_outlined,
    'Landlord',
    'I own or manage rental properties.',
  ),
  _RoleInfo(
    ElevoRole.tenant,
    Icons.home_outlined,
    'Tenant',
    'I rent a home. I can track rent, request repairs, and message my landlord.',
  ),
  _RoleInfo(
    ElevoRole.vendor,
    Icons.handyman_outlined,
    'Vendor',
    'I provide maintenance or property services.',
  ),
];

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.info, required this.selected, required this.onTap});

  final _RoleInfo info;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '${info.title}. ${info.body}',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFE6EEF6) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? ElevoColors.navy : ElevoColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFD5E0EE) : ElevoColors.beige,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    info.icon,
                    size: 22,
                    color: ElevoColors.navy,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.title,
                        style: const TextStyle(
                          color: ElevoColors.ink,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        info.body,
                        style: const TextStyle(color: ElevoColors.muted, fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: selected
                      ? const Icon(
                          Icons.check_circle_rounded,
                          key: ValueKey('on'),
                          color: ElevoColors.navy,
                          size: 24,
                        )
                      : const Icon(
                          Icons.radio_button_unchecked_rounded,
                          key: ValueKey('off'),
                          color: ElevoColors.border,
                          size: 24,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 0 = empty, 1 = weak, 2 = fair, 3 = good, 4 = strong.
int elevoPasswordStrength(String p) {
  if (p.isEmpty) return 0;
  if (p.length < 8) return 1;
  var score = 1;
  if (p.length >= 12) score++;
  if (RegExp(r'[a-z]').hasMatch(p) && RegExp(r'[A-Z]').hasMatch(p)) score++;
  if (RegExp(r'\d').hasMatch(p)) score++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) score++;
  if (score <= 2) return 2;
  if (score <= 4) return 3;
  return 4;
}

class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.level});
  final int level;

  static const List<String> _labels = ['', 'Weak', 'Fair', 'Good', 'Strong'];
  static const List<Color> _colors = [
    ElevoColors.border,
    ElevoColors.error,
    ElevoColors.warning,
    ElevoColors.goldDeep,
    ElevoColors.success,
  ];

  @override
  Widget build(BuildContext context) {
    final color = _colors[level];
    final text = level == 0
        ? 'Use 8+ characters with a mix of letters, numbers and symbols.'
        : 'Password strength: ${_labels[level]}';
    return Semantics(
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 10, left: 4, right: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 1; i <= 4; i++) ...[
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= level ? color : ElevoColors.cardBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (i < 4) const SizedBox(width: 6),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: level == 0 ? ElevoColors.muted : color,
                fontWeight: level == 0 ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrialBadge extends StatelessWidget {
  const _TrialBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFF7E6), Color(0xFFFBEFD3)]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ElevoColors.gold),
      ),
      child: const Row(
        children: [
          Icon(Icons.workspace_premium_outlined, color: ElevoColors.goldDeep, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '7-day trial · Card collected upfront · Cancel anytime before it ends',
              style: TextStyle(
                color: ElevoColors.goldDeep,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// VENDOR FIELDS — shown on sign-up only while the Vendor role is selected.
// -----------------------------------------------------------------------------

const List<String> _vendorServiceTypes = [
  'Plumbing',
  'Electrical',
  'HVAC',
  'Cleaning',
  'Landscaping',
  'Handyman',
  'Painting',
  'Pest Control',
  'Other',
];

class _VendorFields extends StatelessWidget {
  const _VendorFields({
    required this.company,
    required this.area,
    required this.license,
    required this.serviceType,
    required this.onServiceTypeChanged,
    required this.enabled,
  });

  final TextEditingController company;
  final TextEditingController area;
  final TextEditingController license;
  final String? serviceType;
  final ValueChanged<String?> onServiceTypeChanged;
  final bool enabled;

  OutlineInputBorder _border(Color color, [double width = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color, width: width),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        ElevoTextField(
          controller: company,
          label: 'Company name',
          hint: 'Your company name',
          icon: Icons.business_outlined,
          textCapitalization: TextCapitalization.words,
          enabled: enabled,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: serviceType,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: ElevoColors.muted),
          dropdownColor: Colors.white,
          style: const TextStyle(fontSize: 16, color: ElevoColors.ink),
          items: [
            for (final t in _vendorServiceTypes)
              DropdownMenuItem<String>(value: t, child: Text(t)),
          ],
          onChanged: enabled ? onServiceTypeChanged : null,
          validator: (v) => v == null ? 'Choose your service type' : null,
          decoration: InputDecoration(
            labelText: 'Service type',
            filled: true,
            fillColor: enabled ? Colors.white : const Color(0xFFF3F1EC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            labelStyle: const TextStyle(color: ElevoColors.muted, fontSize: 15),
            floatingLabelStyle: const TextStyle(
              color: ElevoColors.navy,
              fontWeight: FontWeight.w600,
            ),
            errorStyle: const TextStyle(color: ElevoColors.error, fontSize: 12.5),
            prefixIcon: const Icon(Icons.handyman_outlined, size: 20, color: ElevoColors.muted),
            border: _border(ElevoColors.border),
            enabledBorder: _border(ElevoColors.border),
            disabledBorder: _border(ElevoColors.cardBorder),
            focusedBorder: _border(ElevoColors.navy, 2),
            errorBorder: _border(ElevoColors.error),
            focusedErrorBorder: _border(ElevoColors.error, 2),
          ),
        ),
        const SizedBox(height: 16),
        ElevoTextField(
          controller: area,
          label: 'Service area / city',
          hint: 'Phoenix, AZ',
          icon: Icons.location_on_outlined,
          textCapitalization: TextCapitalization.words,
          enabled: enabled,
          validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your service area or city' : null,
        ),
        const SizedBox(height: 16),
        ElevoTextField(
          controller: license,
          label: 'License or insurance number (optional)',
          icon: Icons.verified_outlined,
          enabled: enabled,
        ),
      ],
    );
  }
}

class ElevoSignUpScreen extends StatefulWidget {
  const ElevoSignUpScreen({
    super.key,
    this.onSignUp,
    this.onSignIn,
    this.onBack,
    this.onOpenTerms,
    this.onOpenPrivacy,
    this.onGoogle,
    this.onApple,
    this.initialRole,
    this.initialEmail,
    this.heroImage,
  });

  /// Create the account. Throw ElevoAuthException to show a message.
  final ElevoSignUpAction? onSignUp;

  /// "Already have an account? Sign in". Default: Navigator.maybePop.
  final ElevoAction? onSignIn;

  /// Back arrow. Default: Navigator.maybePop.
  final ElevoAction? onBack;

  /// Terms link. Default: pushNamed('/terms'), falling back to ElevoTermsScreen.
  final ElevoAction? onOpenTerms;
  final ElevoAction? onOpenPrivacy;
  final ElevoAction? onGoogle;
  final ElevoAction? onApple;
  final ElevoRole? initialRole;
  final String? initialEmail;
  final ImageProvider? heroImage;

  @override
  State<ElevoSignUpScreen> createState() => _ElevoSignUpScreenState();
}

class _ElevoSignUpScreenState extends State<ElevoSignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final TextEditingController _email =
      TextEditingController(text: widget.initialEmail ?? '');
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _company = TextEditingController();
  final _area = TextEditingController();
  final _license = TextEditingController();
  final _referral = TextEditingController();

  String? _serviceType;
  late ElevoRole? _role = widget.initialRole;
  bool _agreed = false;
  bool _submitted = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    _company.dispose();
    _area.dispose();
    _license.dispose();
    _referral.dispose();
    super.dispose();
  }

  Future<void> _call(ElevoAction? cb, String name, String fallback) async {
    final err = await _invoke(context, cb, name, fallback);
    if (err != null && mounted) setState(() => _error = err);
  }

  void _back() {
    final cb = widget.onBack;
    if (cb == null) {
      Navigator.of(context).maybePop();
    } else {
      _call(cb, 'onBack', "Couldn't go back.");
    }
  }

  void _openTerms() {
    final cb = widget.onOpenTerms;
    if (cb != null) {
      _call(cb, 'onOpenTerms', "Couldn't open the Terms. Please try again.");
    } else {
      _pushNamedOr(context, '/terms', (_) => const ElevoTermsScreen());
    }
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitted = true;
      _error = null;
    });
    final formOk = _formKey.currentState?.validate() ?? false;
    final role = _role;
    if (role == null || !formOk || !_agreed) return;

    setState(() => _loading = true);
    try {
      final data = ElevoSignUpData(
        role: role,
        fullName: _name.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        password: _password.text,
        vendorDetails: role == ElevoRole.vendor
            ? {
                if (_company.text.trim().isNotEmpty) 'company_name': _company.text.trim(),
                'service_type': _serviceType ?? '',
                'service_area': _area.text.trim(),
                if (_license.text.trim().isNotEmpty) 'license_number': _license.text.trim(),
              }
            : const {},
        referralCode: role == ElevoRole.landlord ? _referral.text.trim() : '',
      );
      final cb = widget.onSignUp;
      if (cb == null) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (mounted) _showStub(context, 'onSignUp');
      } else {
        await cb(context, data);
      }
      TextInput.finishAutofillContext();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = _friendlyError(e, "We couldn't create your account. Please try again."),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strength = elevoPasswordStrength(_password.text);
    final confirmTyped = _confirm.text.isNotEmpty;
    final matches = confirmTyped && _confirm.text == _password.text;
    const bodyStyle = TextStyle(color: ElevoColors.ink, fontSize: 14.5);

    return ElevoAuthLayout(
      heroImage: widget.heroImage,
      onBack: _back,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ElevoAuthHeading(
            title: 'Create your account',
            subtitle: 'Set up Elevo in a couple of minutes.',
          ),
          const SizedBox(height: 20),
          if (_role == ElevoRole.landlord) ...[
            const _TrialBadge(),
            const SizedBox(height: 24),
          ],
          if (_error != null)
            _ErrorBanner(message: _error!, onClose: () => setState(() => _error = null)),
          Semantics(
            header: true,
            child: const Text(
              'I am a…',
              style: TextStyle(color: ElevoColors.ink, fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          for (final r in _roles) ...[
            _RoleCard(
              info: r,
              selected: _role == r.role,
              onTap: _loading ? null : () => setState(() => _role = r.role),
            ),
            const SizedBox(height: 10),
          ],
          if (_submitted && _role == null)
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                'Choose how you will use Elevo',
                style: TextStyle(color: ElevoColors.error, fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 14),
          AutofillGroup(
            child: Form(
              key: _formKey,
              autovalidateMode: _submitted
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevoTextField(
                    controller: _name,
                    label: 'Full name',
                    hint: 'Your full name',
                    icon: Icons.person_outline_rounded,
                    keyboardType: TextInputType.name,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    enabled: !_loading,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Enter your full name';
                      if (t.length < 2) return 'Name looks too short';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  ElevoTextField(
                    controller: _email,
                    label: 'Email',
                    hint: 'name@example.com',
                    icon: Icons.mail_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    enabled: !_loading,
                    validator: _validateEmail,
                  ),
                  const SizedBox(height: 16),
                  ElevoTextField(
                    controller: _phone,
                    label: 'Phone',
                    hint: 'Your phone number',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+()\-\s]'))],
                    enabled: !_loading,
                    validator: (v) {
                      final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                      if (digits.isEmpty) return 'Enter your phone number';
                      if (digits.length < 7) return 'Enter a valid phone number';
                      return null;
                    },
                  ),
                  if (_role == ElevoRole.landlord) ...[
                    const SizedBox(height: 16),
                    ElevoTextField(
                      controller: _referral,
                      label: 'Referral code (optional)',
                      hint: 'ELEVO-XXXX',
                      icon: Icons.card_giftcard_outlined,
                      enabled: !_loading,
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevoTextField(
                    controller: _password,
                    label: 'Password',
                    hint: 'At least 8 characters',
                    icon: Icons.lock_outline_rounded,
                    obscure: true,
                    autofillHints: const [AutofillHints.newPassword],
                    enabled: !_loading,
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final p = v ?? '';
                      if (p.isEmpty) return 'Create a password';
                      if (p.length < 8) return 'Use at least 8 characters';
                      if (!RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) {
                        return 'Include at least one letter and one number';
                      }
                      return null;
                    },
                  ),
                  _StrengthMeter(level: strength),
                  const SizedBox(height: 16),
                  ElevoTextField(
                    controller: _confirm,
                    label: 'Confirm password',
                    hint: 'Re-enter your password',
                    icon: Icons.lock_reset_rounded,
                    obscure: true,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    enabled: !_loading,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (_agreed) _submit();
                    },
                    validator: (v) {
                      if ((v ?? '').isEmpty) return 'Confirm your password';
                      if (v != _password.text) return "Passwords don't match";
                      return null;
                    },
                  ),
                  if (confirmTyped)
                    Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8, left: 4),
                        child: Row(
                          children: [
                            Icon(
                              matches ? Icons.check_circle_rounded : Icons.cancel_outlined,
                              size: 16,
                              color: matches ? ElevoColors.success : ElevoColors.error,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              matches ? 'Passwords match' : "Passwords don't match yet",
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: matches ? ElevoColors.success : ElevoColors.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_role == ElevoRole.vendor)
                    _VendorFields(
                      company: _company,
                      area: _area,
                      license: _license,
                      serviceType: _serviceType,
                      onServiceTypeChanged: (v) => setState(() => _serviceType = v),
                      enabled: !_loading,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Semantics(
                label: 'I agree to the Terms of Service and Privacy Policy',
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Checkbox(
                    value: _agreed,
                    activeColor: ElevoColors.navy,
                    checkColor: Colors.white,
                    side: const BorderSide(color: ElevoColors.muted, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    onChanged: _loading ? null : (v) => setState(() => _agreed = v ?? false),
                  ),
                ),
              ),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: _loading ? null : () => setState(() => _agreed = !_agreed),
                      child: const Text('I agree to the', style: bodyStyle),
                    ),
                    ElevoAuthLink(label: 'Terms', onPressed: _openTerms),
                    const Text('and', style: bodyStyle),
                    ElevoAuthLink(
                      label: 'Privacy Policy',
                      onPressed: () => _call(
                        widget.onOpenPrivacy,
                        'onOpenPrivacy',
                        "Couldn't open the Privacy Policy.",
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevoPrimaryButton(
            label: 'Create account',
            loading: _loading,
            onPressed: _agreed ? _submit : null,
          ),
          if (!_agreed)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Agree to the Terms to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(color: ElevoColors.muted, fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 24),
          if (_kShowSocialSignIn) ...[
            const _OrDivider(),
            const SizedBox(height: 20),
            ElevoSecondaryButton(
              label: 'Continue with Google',
              leading: const _GoogleMark(),
              borderColor: ElevoColors.border,
              onPressed: _loading
                  ? null
                  : () => _call(widget.onGoogle, 'onGoogle', "Google sign-up didn't finish."),
            ),
            const SizedBox(height: 12),
            ElevoSecondaryButton(
              label: 'Continue with Apple',
              icon: Icons.apple,
              borderColor: ElevoColors.border,
              onPressed: _loading
                  ? null
                  : () => _call(widget.onApple, 'onApple', "Apple sign-up didn't finish."),
            ),
            const SizedBox(height: 20),
          ],
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Already have an account?',
                style: TextStyle(color: ElevoColors.muted, fontSize: 14.5),
              ),
              ElevoAuthLink(
                label: 'Sign in',
                onPressed: () {
                  final cb = widget.onSignIn;
                  if (cb == null) {
                    Navigator.of(context).maybePop();
                  } else {
                    _call(cb, 'onSignIn', "Couldn't open sign in.");
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// TERMS AND PRIVACY
// Attorney review required. Do not show a draft banner. The text lives in
// lib/legal/elevo_legal_copy.dart and must match web/terms.html and
// web/privacy.html.
// -----------------------------------------------------------------------------

class ElevoTermsScreen extends StatelessWidget {
  const ElevoTermsScreen({
    super.key,
    this.onBack,
    this.lastUpdated = elevoLegalEffectiveDate,
  });

  final ElevoAction? onBack;
  final String lastUpdated;

  @override
  Widget build(BuildContext context) {
    return _ElevoLegalDocument(
      title: 'Terms of Service',
      heading: 'Elevo Terms of Service',
      lastUpdated: lastUpdated,
      sections: elevoTermsSections,
      otherLabel: 'Privacy Policy',
      otherPath: '/privacy',
      onBack: onBack,
    );
  }
}

class ElevoPrivacyScreen extends StatelessWidget {
  const ElevoPrivacyScreen({
    super.key,
    this.onBack,
    this.lastUpdated = elevoLegalEffectiveDate,
  });

  final ElevoAction? onBack;
  final String lastUpdated;

  @override
  Widget build(BuildContext context) {
    return _ElevoLegalDocument(
      title: 'Privacy Policy',
      heading: 'Elevo Privacy Policy',
      lastUpdated: lastUpdated,
      sections: elevoPrivacySections,
      otherLabel: 'Terms of Service',
      otherPath: '/terms',
      onBack: onBack,
    );
  }
}

class _ElevoLegalDocument extends StatelessWidget {
  const _ElevoLegalDocument({
    required this.title,
    required this.heading,
    required this.lastUpdated,
    required this.sections,
    required this.otherLabel,
    required this.otherPath,
    this.onBack,
  });

  final String title;
  final String heading;
  final String lastUpdated;
  final List<ElevoLegalSection> sections;
  final String otherLabel;
  final String otherPath;
  final ElevoAction? onBack;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _elevoAuthTheme(context),
      child: Scaffold(
        backgroundColor: ElevoColors.beige,
        appBar: AppBar(
          backgroundColor: ElevoColors.beige,
          foregroundColor: ElevoColors.navy,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () {
                final cb = onBack;
                if (cb == null) {
                  Navigator.of(ctx).maybePop();
                } else {
                  cb(ctx);
                }
              },
            ),
          ),
          title: Text(
            title,
            style: const TextStyle(color: ElevoColors.navy, fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: ElevoColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ElevoLogo(height: 26),
                        const SizedBox(height: 20),
                        Semantics(
                          header: true,
                          child: Text(
                            heading,
                            style: const TextStyle(
                              color: ElevoColors.navy,
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Effective $lastUpdated',
                          style: const TextStyle(color: ElevoColors.muted, fontSize: 13.5),
                        ),
                        const SizedBox(height: 20),
                        for (final s in sections) ...[
                          Semantics(
                            header: true,
                            child: Text(
                              s.title,
                              style: const TextStyle(
                                color: ElevoColors.navy,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            s.body,
                            style: const TextStyle(
                              color: ElevoColors.ink,
                              fontSize: 15,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 22),
                        ],
                        TextButton(
                          onPressed: () {
                            final router = GoRouter.maybeOf(context);
                            if (router != null) router.push(otherPath);
                          },
                          child: Text(otherLabel),
                        ),
                      ],
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
