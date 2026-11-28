import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/billing_rules.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/account/change_password_sheet.dart';
import '../../widgets/account/delete_account_dialog.dart';
import '../../widgets/settings/appearance_setting.dart';

// Support contact details
const _supportEmail = 'hello@getelevo.app';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  Future<void> _launchEmail(BuildContext context) async {
    // Use Uri() constructor — Uri.parse() with percent-encoded mailto strings
    // fails on Safari/iOS. The constructor lets url_launcher encode correctly.
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {
        'subject': 'ELEVO Support Request',
        'body': 'Hi, I need help with my ELEVO account.',
      },
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Email: $_supportEmail')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final auth   = context.watch<AuthProvider>();
    final user   = auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        children: [
          // ── Profile card ────────────────────────────────────────────────
          GestureDetector(
            onTap: () => context.push('/landlord/more/subscription'),
            child: Container(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            decoration: AppTheme.surfaceCard(colors),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.gold.withAlpha(30),
                    border: Border.all(color: colors.gold.withAlpha(60)),
                  ),
                  child: Center(
                    child: Text(
                      user?.initials ?? 'A',
                      style: TextStyle(
                          color: colors.gold,
                          fontWeight: FontWeight.w700,
                          fontSize: 20),
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.fullName ?? '',
                          style: theme.textTheme.titleMedium?.copyWith(color: colors.ink)),
                      Text(user?.email ?? '',
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.sage)),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight,
                    color: colors.taupe, size: 18),
              ],
            ),
          ),
          ),

          const SizedBox(height: AppTheme.spacingLg),

          // ── Subscription ─────────────────────────────────────────────────
          _MoreTile(
            icon: LucideIcons.crown,
            label: 'Subscription & Pricing',
            subtitle: '${landlordPlanTitle(user?.subscriptionPlan)} — Manage billing',
            onTap: () => context.push('/landlord/more/subscription'),
          ),

          const SizedBox(height: AppTheme.spacingSm),

          // ── Invite Tenant (highlighted) ──────────────────────────────────
          _MoreTile(
            icon: LucideIcons.userPlus,
            label: 'Invite Tenant',
            subtitle: 'Send an invitation to a new tenant',
            onTap: () => context.push('/landlord/more/invite-tenant'),
            highlight: true,
          ),

          const SizedBox(height: AppTheme.spacingSm),

          // ── Features ─────────────────────────────────────────────────────
          _MoreTile(icon: LucideIcons.wrench,    label: 'Maintenance',          onTap: () => context.push('/landlord/more/maintenance')),
          _MoreTile(icon: LucideIcons.hardHat,   label: 'Vendors',             onTap: () => context.push('/landlord/more/vendors')),
          _MoreTile(icon: LucideIcons.star,      label: 'Preferred Partners',  subtitle: 'Reviewed local service providers', onTap: () => context.push('/partners')),
          _MoreTile(icon: LucideIcons.fileText,  label: 'Documents',           onTap: () => context.push('/landlord/more/documents')),
          _MoreTile(icon: LucideIcons.calendar,  label: 'Calendar',          onTap: () => context.push('/landlord/more/calendar')),
          _MoreTile(icon: LucideIcons.userCheck, label: 'Tenant Screening',  subtitle: 'Powered by RentSpree — applicant pays directly', onTap: () => context.push('/landlord/more/screening')),
          _MoreTile(
            icon: LucideIcons.link,
            label: 'RentSpree link',
            subtitle: 'Your screening link for applicants',
            onTap: () => context.push('/landlord/more/rentspree'),
          ),
          _MoreTile(icon: LucideIcons.lock,      label: 'Private Vault',     subtitle: 'Notes, docs & screening — landlord only',     onTap: () => context.push('/landlord/more/vault')),
          _MoreTile(icon: LucideIcons.barChart2, label: 'Financial Reports', subtitle: 'Monthly & annual P&L — downloadable PDF',     onTap: () => context.push('/landlord/more/reports')),
          _MoreTile(icon: LucideIcons.helpCircle,label: 'Help & FAQ',        subtitle: 'Answers, Arizona law, how-tos',               onTap: () => context.push('/landlord/more/qanda')),

          const SizedBox(height: AppTheme.spacingSm),
          Divider(height: 1, color: colors.taupe.withAlpha(25)),
          const SizedBox(height: AppTheme.spacingSm),

          // ── Account ───────────────────────────────────────────────────────
          const AppearanceSetting(),
          const SizedBox(height: AppTheme.spacingSm),
          _MoreTile(
            icon: LucideIcons.user,
            label: 'Profile',
            subtitle: 'Name, phone, and email',
            onTap: () => context.push('/account/profile'),
          ),
          _MoreTile(
            icon: LucideIcons.lock,
            label: 'Change Password',
            onTap: () => showChangePasswordSheet(context),
          ),
          _MoreTile(
            icon: LucideIcons.creditCard,
            label: 'Payment Methods',
            subtitle: 'Zelle, Venmo & bank info shown to tenants',
            onTap: () => context.push('/landlord/more/payment-methods'),
          ),
          _MoreTile(
            icon: LucideIcons.bell,
            label: 'Notification Preferences',
            subtitle: 'Push and email settings',
            onTap: () => context.push('/landlord/more/notifications'),
          ),
          _MoreTile(
            icon: LucideIcons.gift,
            label: 'Referral Program',
            subtitle: 'Give 20% off for 3 months, get 20% off for 3 months',
            onTap: () => context.push('/landlord/more/referral'),
          ),

          // ── Admin section (visible to admin role only) ─────────────────────
          if (user?.isAdmin == true) ...[
            const SizedBox(height: AppTheme.spacingSm),
            Divider(height: 1, color: colors.taupe.withAlpha(25)),
            const SizedBox(height: AppTheme.spacingSm),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: AppTheme.spacingXs),
              child: Text(
                'ADMIN',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.gold,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            _MoreTile(
              icon: LucideIcons.clipboardList,
              label: 'Partner Applications',
              subtitle: 'Review and approve vendor applications',
              onTap: () => context.push('/admin/partner-applications'),
            ),
          ],

          _MoreTile(
            icon: LucideIcons.fileText,
            label: 'Terms of Service',
            onTap: () => context.push('/terms'),
          ),
          _MoreTile(
            icon: LucideIcons.shield,
            label: 'Privacy Policy',
            onTap: () => context.push('/privacy'),
          ),

          const SizedBox(height: AppTheme.spacingSm),
          Divider(height: 1, color: colors.taupe.withAlpha(25)),
          const SizedBox(height: AppTheme.spacingSm),

          // ── Support — email only ─────────────────────────────────────────
          _SupportTile(
            onEmailTap: () { HapticFeedback.lightImpact(); _launchEmail(context); },

            colors: colors,
            theme: theme,
          ),

          const SizedBox(height: AppTheme.spacingLg),

          // ── Sign out ─────────────────────────────────────────────────────
          Center(
            child: TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sign Out'),
                    content: const Text('Are you sure you want to sign out?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          auth.logout();
                          context.go('/login');
                        },
                        child: Text('Sign Out',
                            style: TextStyle(color: colors.urgentRed)),
                      ),
                    ],
                  ),
                );
              },
              child: Text('Sign Out',
                  style: TextStyle(color: colors.urgentRed)),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                confirmAndDeleteAccount(context);
              },
              child: Text('Delete account',
                  style: TextStyle(color: colors.urgentRed)),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

// ── Support tile with a tappable email ────────────────────────────────────────

class _SupportTile extends StatelessWidget {
  final VoidCallback onEmailTap;
  final ElevoColors colors;
  final ThemeData theme;

  const _SupportTile({
    required this.onEmailTap,
    required this.colors,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.gold.withAlpha(12),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.gold.withAlpha(45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.headphones, color: colors.gold, size: 18),
              const SizedBox(width: AppTheme.spacingSm),
              Text('Customer Support',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colors.gold, fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.successGreen.withAlpha(25),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('Mon–Fri',
                    style: TextStyle(
                        color: colors.successGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMd),
          // Email button
          GestureDetector(
            onTap: onEmailTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm + 2),
              decoration: BoxDecoration(
                color: colors.charcoal,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: colors.taupe.withAlpha(50)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.mail, color: colors.gold, size: 16),
                  const SizedBox(width: AppTheme.spacingSm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Email Support',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: colors.ivory)),
                        Text(_supportEmail,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: colors.gold)),
                      ],
                    ),
                  ),
                  Icon(LucideIcons.externalLink,
                      color: colors.taupe, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Menu tile ─────────────────────────────────────────────────────────────────

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool highlight;

  const _MoreTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd,
          vertical: AppTheme.spacingSm + 4,
        ),
        decoration: highlight
            ? BoxDecoration(
                color: colors.gold.withAlpha(12),
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(color: colors.gold.withAlpha(50)),
              )
            : null,
        child: Row(
          children: [
            Icon(icon, color: highlight ? colors.linkOlive : colors.ink, size: 20),
            const SizedBox(width: AppTheme.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyMedium),
                  if (subtitle != null)
                    Text(subtitle!, style: theme.textTheme.labelSmall),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: colors.taupe, size: 16),
          ],
        ),
      ),
    );
  }
}
