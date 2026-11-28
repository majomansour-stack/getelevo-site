import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/account/delete_account_dialog.dart';
import '../../widgets/settings/appearance_setting.dart';

class TenantSettingsScreen extends StatefulWidget {
  const TenantSettingsScreen({super.key});

  @override
  State<TenantSettingsScreen> createState() => _TenantSettingsScreenState();
}

class _TenantSettingsScreenState extends State<TenantSettingsScreen> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser;
    _nameController  = TextEditingController(text: user?.fullName ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    HapticFeedback.lightImpact();
    setState(() => _isSaving = true);
    try {
      final db  = Supabase.instance.client;
      final uid = db.auth.currentUser?.id;
      if (uid != null) {
        final name = _nameController.text.trim();
        final phone = _phoneController.text.trim();
        await db.from('users').update({
          'full_name': name,
          'phone':     phone,
        }).eq('id', uid);
        try {
          await db.from('profiles').update({
            'full_name': name,
            'phone': phone,
          }).eq('id', uid);
        } catch (_) {}
        try {
          await db.auth.updateUser(UserAttributes(data: {
            'full_name': name,
            'phone': phone,
          }));
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(LucideIcons.checkCircle,
                  color: Theme.of(context).extension<ElevoColors>()!.successGreen,
                  size: 18),
              const SizedBox(width: AppTheme.spacingSm),
              const Text('Profile updated successfully.'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _changePassword() {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final currentCtrl = TextEditingController();
    final nextCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: AppTheme.spacingLg,
          right: AppTheme.spacingLg,
          top: AppTheme.spacingLg,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + AppTheme.spacingXl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Change Password', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppTheme.spacingMd),
            TextField(
              controller: currentCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current Password'),
            ),
            const SizedBox(height: AppTheme.spacingMd),
            TextField(
              controller: nextCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New Password'),
            ),
            const SizedBox(height: AppTheme.spacingMd),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm New Password'),
            ),
            const SizedBox(height: AppTheme.spacingLg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final current = currentCtrl.text;
                  final next = nextCtrl.text;
                  final confirm = confirmCtrl.text;
                  final messenger = ScaffoldMessenger.of(context);
                  if (next.length < 6) {
                    messenger.showSnackBar(const SnackBar(
                      content: Text('Password must be at least 6 characters.'),
                    ));
                    return;
                  }
                  if (next != confirm) {
                    messenger.showSnackBar(const SnackBar(
                      content: Text('The new passwords do not match.'),
                    ));
                    return;
                  }
                  final email = context.read<AuthProvider>().currentUser?.email;
                  if (email == null || email.isEmpty) return;
                  try {
                    await Supabase.instance.client.auth.signInWithPassword(
                      email: email,
                      password: current,
                    );
                    await Supabase.instance.client.auth.updateUser(
                      UserAttributes(password: next),
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            Icon(LucideIcons.checkCircle,
                                color: colors.successGreen, size: 18),
                            const SizedBox(width: AppTheme.spacingSm),
                            const Text('Password updated successfully.'),
                          ],
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  } catch (_) {
                    messenger.showSnackBar(const SnackBar(
                      content: Text('Could not update the password. Check the current password and try again.'),
                    ));
                  }
                },
                child: const Text('Update Password'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        children: [
          const AppearanceSetting(),
          const SizedBox(height: AppTheme.spacingLg),
          // ── Profile section ───────────────────────────────────────────────
          _SectionLabel(label: 'Profile', colors: colors, theme: theme),
          const SizedBox(height: AppTheme.spacingMd),

          Column(
            children: [
              TextField(
                controller: _nameController,
                style: TextStyle(color: colors.ink),
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(LucideIcons.user, size: 18, color: colors.sage),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: colors.ink),
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: Icon(LucideIcons.mail, size: 18, color: colors.sage),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: TextStyle(color: colors.ink),
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(LucideIcons.phone, size: 18, color: colors.sage),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppTheme.spacingLg),

          // ── Security section ──────────────────────────────────────────────
          _SectionLabel(label: 'Security', colors: colors, theme: theme),
          const SizedBox(height: AppTheme.spacingSm),

          Container(
            decoration: AppTheme.surfaceCard(colors),
            child: Column(
              children: [
                _SettingsTile(
                  icon: LucideIcons.lock,
                  label: 'Change Password',
                  onTap: _changePassword,
                  colors: colors,
                  theme: theme,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacingLg),

          // ── Danger zone ───────────────────────────────────────────────────
          _SectionLabel(label: 'Account', colors: colors, theme: theme),
          const SizedBox(height: AppTheme.spacingSm),

          Container(
            decoration: AppTheme.surfaceCard(colors),
            child: Column(
              children: [
                _SettingsTile(
                  icon: LucideIcons.fileText,
                  label: 'Terms of Service',
                  onTap: () => context.push('/terms'),
                  colors: colors,
                  theme: theme,
                ),
                Divider(height: 1, color: colors.taupe.withAlpha(25)),
                _SettingsTile(
                  icon: LucideIcons.shield,
                  label: 'Privacy Policy',
                  onTap: () => context.push('/privacy'),
                  colors: colors,
                  theme: theme,
                ),
                Divider(height: 1, color: colors.taupe.withAlpha(25)),
                _SettingsTile(
                  icon: LucideIcons.trash2,
                  label: 'Delete Account',
                  labelColor: colors.urgentRed,
                  iconColor: colors.urgentRed,
                  onTap: () => confirmAndDeleteAccount(context),
                  colors: colors,
                  theme: theme,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacingLg),

          // ── Save button ───────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Changes'),
            ),
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

// ── Helper widgets ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final ElevoColors colors;
  final ThemeData theme;

  const _SectionLabel(
      {required this.label, required this.colors, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: colors.taupe,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ElevoColors colors;
  final ThemeData theme;
  final Color? labelColor;
  final Color? iconColor;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.colors,
    required this.theme,
    this.labelColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMd,
            vertical: AppTheme.spacingSm + 4),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? colors.gold, size: 20),
            const SizedBox(width: AppTheme.spacingMd),
            Expanded(
              child: Text(label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: labelColor ?? colors.ink)),
            ),
            Icon(LucideIcons.chevronRight, color: colors.taupe, size: 16),
          ],
        ),
      ),
    );
  }
}
