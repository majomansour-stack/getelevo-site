import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/auth_provider.dart';
import '../../services/landlord_contact.dart';
import '../../theme/theme.dart';
import '../../widgets/settings/appearance_setting.dart';

class TenantMoreScreen extends StatefulWidget {
  const TenantMoreScreen({super.key});

  @override
  State<TenantMoreScreen> createState() => _TenantMoreScreenState();
}

class _TenantMoreScreenState extends State<TenantMoreScreen> {
  String? _landlordName;
  String? _landlordPhone;
  bool _loadingContacts = true;

  List<Map<String, dynamic>> _myContacts = [];
  bool _loadingMyContacts = true;

  @override
  void initState() {
    super.initState();
    _loadEmergencyContacts();
    _loadMyContacts();
  }

  Future<void> _loadEmergencyContacts() async {
    try {
      final db  = Supabase.instance.client;
      final uid = db.auth.currentUser?.id;
      if (uid == null) { setState(() => _loadingContacts = false); return; }

      final unitRows = await db
          .from('units')
          .select('landlord_id')
          .eq('tenant_id', uid)
          .limit(1);

      if (unitRows.isNotEmpty) {
        final landlordId = unitRows.first['landlord_id'] as String?;
        if (landlordId != null) {
          final landlordRow = await fetchLandlordContact(db, landlordId);
          if (landlordRow != null && mounted) {
            setState(() {
              _landlordName  = landlordRow['full_name'] as String?;
              _landlordPhone = landlordRow['phone'] as String?;
            });
          }
        }
      }
    } catch (_) {}
    finally {
      if (mounted) setState(() => _loadingContacts = false);
    }
  }

  Future<void> _loadMyContacts() async {
    try {
      final db  = Supabase.instance.client;
      final uid = db.auth.currentUser?.id;
      if (uid == null) { setState(() => _loadingMyContacts = false); return; }
      final rows = await db
          .from('tenant_emergency_contacts')
          .select()
          .eq('tenant_id', uid)
          .order('created_at');
      if (mounted) setState(() => _myContacts = List<Map<String, dynamic>>.from(rows));
    } catch (_) {}
    finally {
      if (mounted) setState(() => _loadingMyContacts = false);
    }
  }

  Future<void> _addContact() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final relCtrl = TextEditingController();
    final theme = Theme.of(context);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: AppTheme.spacingLg,
          right: AppTheme.spacingLg,
          top: AppTheme.spacingLg,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + AppTheme.spacingLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add Emergency Contact', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppTheme.spacingMd),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: AppTheme.spacingSm),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(labelText: 'Phone Number'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: AppTheme.spacingSm),
            TextField(
              controller: relCtrl,
              decoration: const InputDecoration(labelText: 'Relationship (optional)'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: AppTheme.spacingLg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final name  = nameCtrl.text.trim();
                  final phone = phoneCtrl.text.trim();
                  if (name.isEmpty || phone.isEmpty) return;
                  Navigator.pop(ctx);
                  try {
                    final db  = Supabase.instance.client;
                    final uid = db.auth.currentUser?.id;
                    if (uid == null) return;
                    await db.from('tenant_emergency_contacts').insert({
                      'tenant_id':    uid,
                      'name':         name,
                      'phone':        phone,
                      'relationship': relCtrl.text.trim().isEmpty ? null : relCtrl.text.trim(),
                    }).select();
                    await _loadMyContacts();
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to save contact.')),
                      );
                    }
                  }
                },
                child: const Text('Save Contact'),
              ),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();
    relCtrl.dispose();
  }

  Future<void> _deleteContact(String id) async {
    try {
      final db = Supabase.instance.client;
      await db.from('tenant_emergency_contacts').delete().eq('id', id);
      await _loadMyContacts();
    } catch (_) {}
  }

  Future<void> _callNumber(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        children: [
          // ── Profile card ──────────────────────────────────────────────────
          Container(
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
                      user?.initials ?? 'T',
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
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    context.push('/tenant/more/settings');
                  },
                  child: Icon(LucideIcons.pencil, color: colors.taupe, size: 18),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacingMd),

          // ── Emergency Contacts ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            decoration: AppTheme.surfaceCard(
              colors,
              border: Border.all(color: colors.urgentRed.withAlpha(90)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.phone, color: colors.urgentRed, size: 18),
                    const SizedBox(width: AppTheme.spacingSm),
                    Expanded(
                      child: Text(
                        'Emergency Contacts',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _addContact,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.spacingSm, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.gold.withAlpha(20),
                          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                          border: Border.all(color: colors.gold.withAlpha(80)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.plus, color: colors.gold, size: 14),
                            const SizedBox(width: 4),
                            Text('Add', style: theme.textTheme.labelSmall?.copyWith(color: colors.goldInk)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingMd),
                if (_loadingContacts)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  // Landlord contact — always shown first
                  _ContactRow(
                    name: _landlordName ?? 'Your Landlord',
                    subtitle: _landlordPhone ?? 'Phone not on file',
                    badge: 'LANDLORD',
                    onTap: _landlordPhone != null && _landlordPhone!.isNotEmpty
                        ? () => _callNumber(_landlordPhone!)
                        : null,
                    colors: colors,
                    theme: theme,
                  ),
                ],
                if (_loadingMyContacts)
                  const Padding(
                    padding: EdgeInsets.only(top: AppTheme.spacingSm),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_myContacts.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.spacingSm),
                  ..._myContacts.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.spacingSm),
                    child: _ContactRow(
                      name: c['name'] as String? ?? '',
                      subtitle: c['phone'] as String? ?? '',
                      badge: c['relationship'] as String?,
                      onTap: () => _callNumber(c['phone'] as String? ?? ''),
                      onDelete: () => _deleteContact(c['id'] as String),
                      colors: colors,
                      theme: theme,
                    ),
                  )),
                ] else ...[
                  const SizedBox(height: AppTheme.spacingSm),
                  Text(
                    'Tap + Add to save personal emergency contacts (family, friends, doctor).',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.sage),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacingLg),

          // ── Section label ─────────────────────────────────────────────────
          Text(
            'MY UNIT',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.taupe,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),

          Container(
            decoration: AppTheme.surfaceCard(colors),
            child: Column(
              children: [
                _Tile(
                  icon: LucideIcons.fileText,
                  label: 'Documents',
                  subtitle: 'Lease, notices & shared files',
                  onTap: () => context.push('/tenant/more/documents'),
                ),
                Divider(height: 1, color: colors.taupe.withAlpha(20)),
                _Tile(
                  icon: LucideIcons.camera,
                  label: 'Photo Log',
                  subtitle: 'Move-in & move-out photos',
                  onTap: () => context.push('/tenant/more/photos'),
                ),
                Divider(height: 1, color: colors.taupe.withAlpha(20)),
                _Tile(
                  icon: LucideIcons.star,
                  label: 'Preferred Partners',
                  subtitle: 'Reviewed local service providers',
                  onTap: () => context.push('/partners'),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacingMd),

          Text(
            'ACCOUNT',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.taupe,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),

          const AppearanceSetting(),
          const SizedBox(height: AppTheme.spacingSm),

          Container(
            decoration: AppTheme.surfaceCard(colors),
            child: Column(
              children: [
                _Tile(
                  icon: LucideIcons.bell,
                  label: 'Notification Preferences',
                  subtitle: 'Push and email settings',
                  onTap: () => context.push('/tenant/more/notifications'),
                ),
                Divider(height: 1, color: colors.taupe.withAlpha(20)),
                _Tile(
                  icon: LucideIcons.settings,
                  label: 'Settings',
                  subtitle: 'Profile, password & account',
                  onTap: () => context.push('/tenant/more/settings'),
                ),
                Divider(height: 1, color: colors.taupe.withAlpha(20)),
                _Tile(
                  icon: LucideIcons.helpCircle,
                  label: 'Help & FAQ',
                  subtitle: 'Arizona landlord-tenant law & support',
                  onTap: () => context.push('/tenant/more/qanda'),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacingLg),

          // ── Sign out ──────────────────────────────────────────────────────
          Center(
            child: TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sign Out'),
                    content:
                        const Text('Are you sure you want to sign out?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel')),
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

          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

// ── Tile widget ────────────────────────────────────────────────────────────────

class _ContactRow extends StatelessWidget {
  final String name;
  final String subtitle;
  final String? badge;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final ElevoColors colors;
  final ThemeData theme;

  const _ContactRow({
    required this.name,
    required this.subtitle,
    this.badge,
    this.onTap,
    this.onDelete,
    required this.colors,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd,
          vertical: AppTheme.spacingSm,
        ),
        decoration: AppTheme.surfaceCard(colors, shadow: false),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: AppTheme.spacingXs),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.gold.withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge!.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.gold,
                              fontSize: 9,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.goldInk),
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              GestureDetector(
                onTap: onDelete,
                child: Icon(LucideIcons.trash2, color: colors.urgentRed.withAlpha(180), size: 16),
              )
            else if (onTap != null)
              Icon(LucideIcons.phone, color: colors.gold, size: 18),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

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
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.gold.withAlpha(18),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Icon(icon, color: colors.gold, size: 18),
            ),
            const SizedBox(width: AppTheme.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink)),
                  Text(subtitle, style: theme.textTheme.labelSmall),
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
