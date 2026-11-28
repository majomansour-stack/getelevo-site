import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/elevo_logic.dart';
import '../../services/notification_preferences_store.dart';
import '../../theme/theme.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class _NotifPref {
  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  bool enabled;

  _NotifPref({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    this.enabled = true,
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  // Push notification master toggle
  bool _pushEnabled = true;
  bool _emailEnabled = true;

  // Per-event preferences
  final List<_NotifPref> _prefs = [
    _NotifPref(
      id: 'new_message',
      label: 'New Message',
      subtitle: 'When a tenant sends you a message',
      icon: LucideIcons.messageCircle,
      enabled: true,
    ),
    _NotifPref(
      id: 'maintenance_submitted',
      label: 'Maintenance Request Submitted',
      subtitle: 'When a tenant submits a new request',
      icon: LucideIcons.wrench,
      enabled: true,
    ),
    _NotifPref(
      id: 'maintenance_update',
      label: 'Maintenance Status Update',
      subtitle: 'When vendor or status changes on a request',
      icon: LucideIcons.refreshCw,
      enabled: true,
    ),
    _NotifPref(
      id: 'rent_paid',
      label: 'Tenant Marked Rent as Paid',
      subtitle: 'When a tenant taps "I Have Paid"',
      icon: LucideIcons.dollarSign,
      enabled: true,
    ),
    _NotifPref(
      id: 'lease_90',
      label: 'Lease Expiry — 90 Days',
      subtitle: 'Early warning for upcoming lease renewals',
      icon: LucideIcons.calendarClock,
      enabled: true,
    ),
    _NotifPref(
      id: 'lease_60',
      label: 'Lease Expiry — 60 Days',
      subtitle: 'Second reminder before lease ends',
      icon: LucideIcons.calendarClock,
      enabled: true,
    ),
    _NotifPref(
      id: 'lease_30',
      label: 'Lease Expiry — 30 Days',
      subtitle: 'Final reminder — action required soon',
      icon: LucideIcons.calendarClock,
      enabled: true,
    ),
    _NotifPref(
      id: 'vendor_approval',
      label: 'Vendor Spend Approval Needed',
      subtitle: 'When estimated cost exceeds vendor spend limit',
      icon: LucideIcons.hardHat,
      enabled: true,
    ),
    _NotifPref(
      id: 'screening_complete',
      label: 'Tenant Screening Complete',
      subtitle: 'When RentSpree results are ready for review',
      icon: LucideIcons.shieldCheck,
      enabled: true,
    ),
    _NotifPref(
      id: 'document_signed',
      label: 'Document Signed',
      subtitle: 'When a tenant signs a document',
      icon: LucideIcons.fileCheck,
      enabled: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final snapshot = await NotificationPreferencesStore(
      Supabase.instance.client,
    ).load();
    if (!mounted) return;
    setState(() {
      _pushEnabled = snapshot.pushEnabled;
      _emailEnabled = snapshot.emailEnabled;
      for (final pref in _prefs) {
        final stored = snapshot.events[pref.id];
        if (stored != null) pref.enabled = stored;
      }
    });
  }

  Future<void> _savePreferences() async {
    HapticFeedback.lightImpact();
    final snapshot = NotificationPreferenceSnapshot(
      pushEnabled: _pushEnabled,
      emailEnabled: _emailEnabled,
      smsEnabled: false,
      events: {for (final pref in _prefs) pref.id: pref.enabled},
    );
    final messenger = ScaffoldMessenger.of(context);
    final colors = Theme.of(context).extension<ElevoColors>()!;
    try {
      final full = await NotificationPreferencesStore(
        Supabase.instance.client,
      ).save(snapshot);
      messenger.showSnackBar(
        SnackBar(
          content: Text(full
              ? 'Notification preferences saved.'
              : 'Push setting saved. The other switches need a database update before they can be stored.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (mounted && full) Navigator.of(context).pop();
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not save notification preferences.',
              style: TextStyle(color: colors.ivory)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Preferences'),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _savePreferences,
            child: Text('Save',
                style: TextStyle(
                    color: colors.linkOlive, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        children: [
          // ── Delivery channels ───────────────────────────────────────────
          _SectionLabel(label: 'Delivery Channels', colors: colors, theme: theme),
          const SizedBox(height: AppTheme.spacingSm),

          Container(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Column(
              children: [
                _ChannelTile(
                  icon: LucideIcons.bell,
                  label: 'Push Notifications',
                  subtitle: 'Alerts on your device — recommended',
                  value: _pushEnabled,
                  onChanged: (v) => setState(() => _pushEnabled = v),
                  colors: colors,
                  theme: theme,
                  isFirst: true,
                ),
                Divider(height: 1, color: colors.taupe.withAlpha(25)),
                _ChannelTile(
                  icon: LucideIcons.mail,
                  label: 'Email Notifications',
                  subtitle: 'Sent to your account email address',
                  value: _emailEnabled,
                  onChanged: (v) => setState(() => _emailEnabled = v),
                  colors: colors,
                  theme: theme,
                  isLast: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacingLg),

          // ── Per-event toggles ───────────────────────────────────────────
          _SectionLabel(label: 'Event Notifications', colors: colors, theme: theme),
          const SizedBox(height: AppTheme.spacingXs),
          Text(
            'Choose which events trigger notifications.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppTheme.spacingMd),

          Container(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Column(
              children: List.generate(_prefs.length, (i) {
                final pref = _prefs[i];
                return Column(
                  children: [
                    if (i > 0)
                      Divider(height: 1, color: colors.taupe.withAlpha(20)),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingMd,
                        vertical: AppTheme.spacingSm + 2,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: pref.enabled
                                  ? colors.oliveTint
                                  : colors.stone.withAlpha(80),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              pref.icon,
                              color:
                                  pref.enabled ? colors.linkOlive : colors.sage,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacingMd),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(pref.label,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: pref.enabled
                                          ? colors.ink
                                          : colors.sage,
                                    )),
                                Text(pref.subtitle,
                                    style: theme.textTheme.labelSmall),
                              ],
                            ),
                          ),
                          Switch(
                            value: pref.enabled,
                            onChanged: (v) {
                              HapticFeedback.lightImpact();
                              setState(() => pref.enabled = v);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),

          const SizedBox(height: AppTheme.spacingLg),

          // ── Save button ─────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _savePreferences,
              child: const Text('Save Preferences'),
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

class _ChannelTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final ElevoColors colors;
  final ThemeData theme;
  final bool isFirst;
  final bool isLast;

  const _ChannelTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.colors,
    required this.theme,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMd,
        vertical: AppTheme.spacingSm + 2,
      ),
      child: Row(
        children: [
          Icon(icon, color: value ? colors.linkOlive : colors.sage, size: 20),
          const SizedBox(width: AppTheme.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: value ? colors.ink : colors.sage,
                    )),
                Text(subtitle, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: (v) {
              HapticFeedback.lightImpact();
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}
