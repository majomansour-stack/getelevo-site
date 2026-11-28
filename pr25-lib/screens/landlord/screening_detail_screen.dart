import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/screening_model.dart';
import '../../providers/screening_provider.dart';
import '../../theme/theme.dart';

class ScreeningDetailScreen extends StatefulWidget {
  final String screeningId;

  const ScreeningDetailScreen({super.key, required this.screeningId});

  @override
  State<ScreeningDetailScreen> createState() => _ScreeningDetailScreenState();
}

class _ScreeningDetailScreenState extends State<ScreeningDetailScreen> {
  final _notesCtrl = TextEditingController();
  bool _notesDirty = false;
  bool _actionLoading = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Action helpers ────────────────────────────────────────────────────────

  Future<void> _markComplete(ScreeningProvider provider, TenantScreening s) async {
    final notesCtrl = TextEditingController(text: s.notes ?? '');
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add screening notes (optional):'),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'e.g. Credit score 720, no evictions…',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, notesCtrl.text),
            child: const Text('Save & Mark Complete'),
          ),
        ],
      ),
    );
    if (confirmed == null || !mounted) return;
    setState(() => _actionLoading = true);
    try {
      await provider.markComplete(s.id, confirmed);
      if (mounted) {
        _notesCtrl.text = confirmed;
        _showSuccess('Screening marked as complete.');
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _approve(ScreeningProvider provider, TenantScreening s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Applicant'),
        content: Text(
          'Send a congratulations email to ${s.applicantFirstName} '
          '${s.applicantLastName} and mark this application as approved?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve & Send Email'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _actionLoading = true);
    try {
      await provider.approveApplicant(s.id);
      if (mounted) _showSuccess('Applicant approved. Congratulations email sent.');
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _decline(ScreeningProvider provider, TenantScreening s) async {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Applicant'),
        content: const Text(
          'Federal law requires you to send an adverse action notice to '
          'applicants you decline based on screening results. Tap '
          '"Send Adverse Action Notice" to send the required notice automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFF7A321C),
              foregroundColor: colors.onOlive,
            ),
            onPressed: () => Navigator.pop(ctx, 'send'),
            child: const Text('Send Adverse Action Notice'),
          ),
        ],
      ),
    );
    if (action != 'send' || !mounted) return;
    setState(() => _actionLoading = true);
    try {
      await provider.declineApplicant(s.id);
      if (mounted) {
        _showSuccess(
          'Applicant declined. Adverse action notice sent as required by law.',
        );
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _resend(ScreeningProvider provider, TenantScreening s) async {
    setState(() => _actionLoading = true);
    try {
      await provider.resendInvitation(s);
      if (mounted) {
        _showSuccess(
          'Invitation email resent to ${s.applicantEmail}.',
        );
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _saveNotes(ScreeningProvider provider, TenantScreening s) async {
    await provider.updateNotes(s.id, _notesCtrl.text.trim());
    setState(() => _notesDirty = false);
    if (mounted) _showSuccess('Notes saved.');
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final colors   = theme.extension<ElevoColors>()!;
    final provider = context.watch<ScreeningProvider>();
    final s        = provider.findById(widget.screeningId);

    if (s == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Screening Detail'),
        ),
        body: const Center(child: Text('Record not found.')),
      );
    }

    // Sync notes controller on first build
    if (_notesCtrl.text.isEmpty && (s.notes?.isNotEmpty ?? false)) {
      _notesCtrl.text = s.notes!;
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(s.applicantFullName),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Applicant card ───────────────────────────────────────────
            _InfoCard(s: s, colors: colors, theme: theme),

            const SizedBox(height: AppTheme.spacingMd),

            // ── Actions ──────────────────────────────────────────────────
            Text(
              'Actions',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.midnight,
              ),
            ),
            const SizedBox(height: AppTheme.spacingSm),

            if (_actionLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppTheme.spacingMd),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              // Mark as Complete — gold
              OutlinedButton.icon(
                onPressed: s.status == ScreeningStatus.approved ||
                        s.status == ScreeningStatus.declined
                    ? null
                    : () => _markComplete(provider, s),
                icon: const Icon(LucideIcons.checkCircle),
                label: const Text('Mark as Complete'),
              ),
              const SizedBox(height: AppTheme.spacingSm),

              // Approve — green outlined
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: colors.successGreen.withAlpha(18),
                  foregroundColor: colors.successGreen,
                  side: BorderSide(color: colors.successGreen),
                  minimumSize: const Size(double.infinity, AppTheme.buttonHeight),
                ),
                onPressed: s.status == ScreeningStatus.approved ||
                        s.status == ScreeningStatus.declined
                    ? null
                    : () => _approve(provider, s),
                icon: const Icon(LucideIcons.thumbsUp),
                label: const Text('Approve Applicant'),
              ),
              const SizedBox(height: AppTheme.spacingSm),

              // Decline — red outlined
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: colors.urgentRed,
                  side: BorderSide(color: colors.urgentRed),
                  minimumSize: const Size(double.infinity, AppTheme.buttonHeight),
                ),
                onPressed: s.status == ScreeningStatus.approved ||
                        s.status == ScreeningStatus.declined
                    ? null
                    : () => _decline(provider, s),
                icon: const Icon(LucideIcons.thumbsDown),
                label: const Text('Decline Applicant'),
              ),
              const SizedBox(height: AppTheme.spacingSm),

              // Resend — taupe outlined
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: colors.sage,
                  side: BorderSide(color: colors.stone),
                  minimumSize: const Size(double.infinity, AppTheme.buttonHeight),
                ),
                onPressed: () => _resend(provider, s),
                icon: const Icon(LucideIcons.send),
                label: const Text('Resend Invitation'),
              ),
            ],

            const SizedBox(height: AppTheme.spacingLg),

            // ── Notes ────────────────────────────────────────────────────
            Text(
              'Screening Notes',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.midnight,
              ),
            ),
            const SizedBox(height: AppTheme.spacingSm),
            TextField(
              controller: _notesCtrl,
              maxLines: 5,
              onChanged: (_) => setState(() => _notesDirty = true),
              decoration: const InputDecoration(
                hintText:
                    'Record your notes here — credit score, concerns, recommendation…',
              ),
            ),
            if (_notesDirty) ...[
              const SizedBox(height: AppTheme.spacingSm),
              OutlinedButton(
                onPressed: () => _saveNotes(provider, s),
                child: const Text('Save Notes'),
              ),
            ],

            const SizedBox(height: AppTheme.spacingLg),

            // ── Legal disclaimer ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              decoration: BoxDecoration(
                color: colors.stone.withAlpha(30),
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
              child: Text(
                'Tenant screening is powered by RentSpree. ELEVO does not collect, '
                'store, or process screening fees or consumer report data. All '
                'screening fees are paid directly by the applicant to RentSpree. '
                'Landlords are responsible for compliance with the Fair Credit '
                'Reporting Act and all applicable state and local screening laws '
                'including Arizona Revised Statutes.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.sage,
                  height: 1.6,
                ),
              ),
            ),

            const SizedBox(height: AppTheme.spacingXxl),
          ],
        ),
      ),
    );
  }
}

// ── Applicant info card ────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final TenantScreening s;
  final ElevoColors colors;
  final ThemeData theme;

  const _InfoCard({required this.s, required this.colors, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.stone.withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.applicantFullName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StatusBadgeDetail(status: s.status, colors: colors, theme: theme),
            ],
          ),
          const SizedBox(height: AppTheme.spacingSm),
          _InfoRow(icon: LucideIcons.mail, label: s.applicantEmail, colors: colors, theme: theme),
          const SizedBox(height: 6),
          _InfoRow(icon: LucideIcons.home, label: s.propertyAndUnit, colors: colors, theme: theme),
          const SizedBox(height: 6),
          _InfoRow(
            icon: LucideIcons.shieldCheck,
            label: '${s.screeningTypeLabel} screening — \$${s.screeningFee.toStringAsFixed(0)} (applicant pays)',
            colors: colors,
            theme: theme,
          ),
          const SizedBox(height: 6),
          _InfoRow(
            icon: LucideIcons.calendar,
            label: 'Sent ${_formatDate(s.invitedAt)}',
            colors: colors,
            theme: theme,
          ),
          if (s.completedAt != null) ...[
            const SizedBox(height: 6),
            _InfoRow(
              icon: LucideIcons.checkCircle,
              label: 'Completed ${_formatDate(s.completedAt!)}',
              colors: colors,
              theme: theme,
            ),
          ],
          if (s.approvedAt != null) ...[
            const SizedBox(height: 6),
            _InfoRow(
              icon: LucideIcons.thumbsUp,
              label: 'Approved ${_formatDate(s.approvedAt!)}',
              colors: colors,
              theme: theme,
            ),
          ],
          if (s.declinedAt != null) ...[
            const SizedBox(height: 6),
            _InfoRow(
              icon: LucideIcons.thumbsDown,
              label: 'Declined ${_formatDate(s.declinedAt!)}',
              colors: colors,
              theme: theme,
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final ElevoColors colors;
  final ThemeData theme;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.colors,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: colors.sage),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.sage),
          ),
        ),
      ],
    );
  }
}

// ── Detail status badge ───────────────────────────────────────────────────────

class _StatusBadgeDetail extends StatelessWidget {
  final ScreeningStatus status;
  final ElevoColors colors;
  final ThemeData theme;

  const _StatusBadgeDetail(
      {required this.status, required this.colors, required this.theme});

  @override
  Widget build(BuildContext context) {
    Color bg;
    String label;
    switch (status) {
      case ScreeningStatus.invited:
        bg = colors.warningAmber;
        label = 'Invited';
      case ScreeningStatus.complete:
        bg = colors.successGreen;
        label = 'Complete';
      case ScreeningStatus.approved:
        bg = colors.gold;
        label = 'Approved';
      case ScreeningStatus.declined:
        bg = colors.urgentRed;
        label = 'Declined';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg.withAlpha(25),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: bg.withAlpha(100)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: bg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
