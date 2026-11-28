import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/elevo_logic.dart';
import '../core/web_location.dart';
import '../providers/auth_provider.dart';
import '../theme/theme.dart';

/// Shown after a password-recovery link. The person chooses a new password
/// and is then signed in on their home screen.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final next = _password.text;
    final confirm = _confirm.text;
    if (next.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (next != confirm) {
      setState(() => _error = 'The new passwords do not match.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    try {
      await auth.updatePassword(next);
      if (!mounted) return;
      final home = homeRouteForRole(auth.currentUser?.role);
      replaceBrowserHash(home);
      context.go(home);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not update the password. Open the reset link again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final auth = context.watch<AuthProvider>();
    final ready = auth.passwordRecovery || auth.isLoggedIn;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              children: [
                Text(
                  'Set a new password',
                  style: theme.textTheme.headlineSmall?.copyWith(color: colors.ink),
                ),
                const SizedBox(height: AppTheme.spacingSm),
                Text(
                  auth.expiredAuthLink
                      ? 'This reset link is invalid or has expired. Request a new one from the sign-in screen.'
                      : ready
                          ? 'Choose a new password for your Elevo account.'
                          : 'Open the reset link from your email on this device, then choose a new password.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: auth.expiredAuthLink ? colors.urgentRed : colors.sage,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingLg),
                if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: colors.urgentRed)),
                  const SizedBox(height: AppTheme.spacingSm),
                ],
                TextField(
                  controller: _password,
                  obscureText: true,
                  enabled: ready && !_saving,
                  decoration: const InputDecoration(labelText: 'New password'),
                ),
                const SizedBox(height: AppTheme.spacingMd),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  enabled: ready && !_saving,
                  decoration: const InputDecoration(labelText: 'Confirm new password'),
                  onSubmitted: ready ? (_) => _save() : null,
                ),
                const SizedBox(height: AppTheme.spacingLg),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: ready && !_saving ? _save : null,
                    child: Text(_saving ? 'Saving…' : 'Save password'),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingSm),
                TextButton(
                  onPressed: _saving ? null : () => context.go('/login'),
                  child: const Text('Back to sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
