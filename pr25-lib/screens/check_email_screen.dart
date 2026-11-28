import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'elevo_auth_screens.dart';

/// Shown when sign-up does not return a session because email
/// confirmation is turned on.
class CheckEmailScreen extends StatefulWidget {
  final String email;

  const CheckEmailScreen({super.key, required this.email});

  @override
  State<CheckEmailScreen> createState() => _CheckEmailScreenState();
}

class _CheckEmailScreenState extends State<CheckEmailScreen> {
  bool _sending = false;

  Future<void> _resend() async {
    if (_sending) return;
    setState(() => _sending = true);
    final auth = context.read<AuthProvider>();
    final error = await auth.resendSignupConfirmation(widget.email);
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Confirmation email sent again.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = dark ? ElevoColors.oliveLinkDark : ElevoColors.olive;

    return ElevoAuthLayout(
      onBack: () => context.go('/login'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(LucideIcons.mail, color: accent, size: 36),
          const SizedBox(height: 16),
          ElevoAuthHeading(
            title: 'Check your email',
            subtitle:
                'We sent a confirmation link to ${widget.email}. '
                'Open it on this phone to finish creating your account, then log in.',
          ),
          const SizedBox(height: 28),
          ElevoPrimaryButton(
            label: _sending ? 'Sending…' : 'Resend email',
            onPressed:
                _sending
                    ? null
                    : () {
                      HapticFeedback.lightImpact();
                      _resend();
                    },
          ),
          const SizedBox(height: 8),
          Center(
            child: ElevoAuthLink(
              label: 'Back to log in',
              onPressed: () => context.go('/login'),
            ),
          ),
        ],
      ),
    );
  }
}
