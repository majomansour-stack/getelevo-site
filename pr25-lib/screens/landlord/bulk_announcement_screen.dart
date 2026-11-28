import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/property_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/notification_service.dart';
import '../../services/push_notification_service.dart';
import '../../theme/theme.dart';

class BulkAnnouncementScreen extends StatefulWidget {
  const BulkAnnouncementScreen({super.key});

  @override
  State<BulkAnnouncementScreen> createState() => _BulkAnnouncementScreenState();
}

class _BulkAnnouncementScreenState extends State<BulkAnnouncementScreen> {
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _db = Supabase.instance.client;

  // null = all tenants; non-null = specific property id
  String? _selectedPropertyId;
  bool _isSending = false;
  bool _sent = false;
  int _sentCount = 0;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  List<Property> _properties(DashboardProvider dash) => dash.properties;

  List<Map<String, dynamic>> _previewRecipients(
      DashboardProvider dash) {
    final recipients = <Map<String, dynamic>>[];
    for (final p in _properties(dash)) {
      if (_selectedPropertyId != null && p.id != _selectedPropertyId) continue;
      for (final u in p.units) {
        if (u.tenantId != null && u.tenantId!.isNotEmpty) {
          recipients.add({
            'unit_id': u.id,
            'tenant_id': u.tenantId,
            'label': '${p.name} #${u.unitNumber}',
          });
        }
      }
    }
    return recipients;
  }

  Future<void> _send(DashboardProvider dash) async {
    final subject = _subjectCtrl.text.trim();
    final message = _messageCtrl.text.trim();
    if (subject.isEmpty || message.isEmpty) return;
    HapticFeedback.mediumImpact();

    setState(() => _isSending = true);

    final auth = context.read<AuthProvider>();
    final landlordId = auth.currentUser?.id;
    final landlordName = auth.currentUser?.fullName ?? 'Your landlord';
    final recipients = _previewRecipients(dash);

    try {
      int count = 0;
      for (final r in recipients) {
        final tenantId = r['tenant_id'] as String?;
        if (tenantId == null) continue;

        // Insert message record
        try {
          await _db.from('messages').insert({
            'unit_id': r['unit_id'],
            'sender_id': landlordId,
            'receiver_id': tenantId,
            'content': '📢 $subject\n\n$message',
            'created_at': DateTime.now().toIso8601String(),
          }).select();
        } catch (_) {}

        // Push notification
        try {
          await PushNotificationService.notifyAnnouncement(
            tenantId: tenantId,
            subject: subject,
            preview: message,
          );
        } catch (_) {}

        // Email via Resend / Edge Function
        try {
          final userRow = await _db
              .from('users')
              .select('email, full_name')
              .eq('id', tenantId)
              .maybeSingle();
          if (userRow != null) {
            await NotificationService.sendAnnouncement(
              toEmail: userRow['email'] as String,
              tenantName: (userRow['full_name'] as String?) ?? 'Tenant',
              landlordName: landlordName,
              unitLabel: r['label'] as String,
              subject: subject,
              message: message,
              unitId: r['unit_id'] as String,
            );
          }
        } catch (_) {}

        count++;
      }

      // Store in announcements table
      try {
        await _db.from('announcements').insert({
          'landlord_id': landlordId,
          'subject': subject,
          'message': message,
          'recipient_count': count,
          'sent_at': DateTime.now().toIso8601String(),
          'recipient_scope': _selectedPropertyId ?? 'all',
        }).select();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _isSending = false;
          _sent = true;
          _sentCount = count;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send. Please try again.')),
        );
      }
    }
  }

  void _showPreview(DashboardProvider dash) {
    final recipients = _previewRecipients(dash);
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.charcoal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${recipients.length} recipient${recipients.length == 1 ? '' : 's'}',
                  style: theme.textTheme.titleMedium?.copyWith(color: colors.ivory)),
              const SizedBox(height: AppTheme.spacingMd),
              if (recipients.isEmpty)
                Text('No tenants are assigned yet.',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.sage))
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: recipients.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: colors.taupe.withAlpha(30)),
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(recipients[i]['label'] as String,
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.ivory)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final dash = context.watch<DashboardProvider>();
    final properties = _properties(dash);

    if (_sent) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Announcement Sent'),
          leading: IconButton(
            icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.megaphone, size: 64, color: colors.gold),
                const SizedBox(height: AppTheme.spacingMd),
                Text(
                  'Announcement sent!',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTheme.spacingSm),
                Text(
                  '$_sentCount tenant${_sentCount == 1 ? '' : 's'} notified via push notification and message.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.sage),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTheme.spacingXl),
                ElevatedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Broadcast to Tenants'),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Recipient selector
            Text('Send To', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppTheme.spacingSm),
            Wrap(
              spacing: AppTheme.spacingSm,
              children: [
                _RecipientChip(
                  label: 'All Tenants',
                  selected: _selectedPropertyId == null,
                  count: _previewRecipients(dash).length,
                  onTap: () => setState(() => _selectedPropertyId = null),
                  colors: colors,
                  theme: theme,
                ),
                ...properties.map((p) => _RecipientChip(
                  label: p.name,
                  selected: _selectedPropertyId == p.id,
                  count: p.units.where((u) => u.tenantId != null && u.tenantId!.isNotEmpty).length,
                  onTap: () => setState(() => _selectedPropertyId = p.id),
                  colors: colors,
                  theme: theme,
                )),
              ],
            ),

            const SizedBox(height: AppTheme.spacingMd),

            // Preview
            TextButton.icon(
              onPressed: () => _showPreview(dash),
              icon: Icon(LucideIcons.users, size: 16, color: colors.gold),
              label: Text(
                'Preview Recipients (${_previewRecipients(dash).length})',
                style: TextStyle(color: colors.goldInk),
              ),
            ),

            const SizedBox(height: AppTheme.spacingMd),

            // Subject
            Text('Subject', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppTheme.spacingSm),
            TextFormField(
              controller: _subjectCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. Building Notice — Water Shutoff',
                prefixIcon: Icon(LucideIcons.type, color: colors.taupe, size: 18),
              ),
            ),

            const SizedBox(height: AppTheme.spacingMd),

            // Message
            Text('Message', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppTheme.spacingSm),
            TextFormField(
              controller: _messageCtrl,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'Write your announcement here…',
                alignLabelWithHint: true,
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(bottom: 80),
                  child: Icon(LucideIcons.fileText, color: colors.taupe, size: 18),
                ),
              ),
            ),

            const SizedBox(height: AppTheme.spacingXl),

            // Send button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSending ? null : () => _send(dash),
                icon: _isSending
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(LucideIcons.send, size: 18, color: Colors.white),
                label: Text(_isSending ? 'Sending…' : 'Send Announcement'),
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}

class _RecipientChip extends StatelessWidget {
  final String label;
  final bool selected;
  final int count;
  final VoidCallback onTap;
  final ElevoColors colors;
  final ThemeData theme;

  const _RecipientChip({
    required this.label,
    required this.selected,
    required this.count,
    required this.onTap,
    required this.colors,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colors.gold.withAlpha(25) : colors.charcoal,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: selected ? colors.gold : colors.taupe.withAlpha(60),
          ),
        ),
        child: Text(
          '$label ($count)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: selected ? colors.gold : colors.ivory,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
