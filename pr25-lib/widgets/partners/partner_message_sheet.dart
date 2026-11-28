import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/elevo_logic.dart';
import '../../models/partner_model.dart';
import '../../services/notification_service.dart';
import '../../services/partner_service.dart';
import '../../theme/theme.dart';

// ─── Sheet ────────────────────────────────────────────────────────────────────

class PartnerMessageSheet extends StatefulWidget {
  final PartnerListing listing;

  const PartnerMessageSheet({super.key, required this.listing});

  /// Convenience method — call this instead of showModalBottomSheet directly.
  static void show(BuildContext context, PartnerListing listing) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PartnerMessageSheet(listing: listing),
    );
  }

  @override
  State<PartnerMessageSheet> createState() => _PartnerMessageSheetState();
}

class _PartnerMessageSheetState extends State<PartnerMessageSheet> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  static const int _maxChars = 300;

  bool _sending = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    // Auto-focus after the sheet animation
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();

    if (text.isEmpty) {
      setState(() => _errorText = 'Please write a message before sending.');
      return;
    }

    if (containsBlockedLanguage(text)) {
      HapticFeedback.heavyImpact();
      setState(() =>
          _errorText = 'Your message contains inappropriate content and cannot be sent. '
              'Please revise and try again.');
      return;
    }

    if (text.length > _maxChars) {
      setState(() => _errorText = 'Message must be $_maxChars characters or fewer.');
      return;
    }

    setState(() {
      _sending = true;
      _errorText = null;
    });

    final sent = await NotificationService.sendPartnerMessage(
      toEmail: widget.listing.email,
      businessName: widget.listing.businessName,
      senderName: Supabase.instance.client.auth.currentUser?.email ?? 'An Elevo user',
      message: text,
      listingId: widget.listing.id,
    );
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (sent && uid != null) {
      try {
        await PartnerService().logContactTap(
          vendorId: widget.listing.id,
          contactedBy: uid,
          contactType: 'message',
          message: text,
        );
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _sending = false);
    if (!sent) {
      setState(() => _errorText = 'Could not send that message. Please try again.');
      return;
    }
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Message sent to ${widget.listing.businessName}'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final remaining = _maxChars - _ctrl.text.length;
    final overLimit = remaining < 0;

    return Container(
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppTheme.spacingMd,
        AppTheme.spacingMd,
        AppTheme.spacingMd,
        AppTheme.spacingMd + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Handle ─────────────────────────────────────────────────────
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.stone,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingMd),

          // ── Header ─────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.midnight.withAlpha(10),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(color: colors.stone),
                ),
                child: Icon(LucideIcons.building2, color: theme.colorScheme.onSurface, size: 18),
              ),
              const SizedBox(width: AppTheme.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.listing.businessName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.listing.category,
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.sage),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(LucideIcons.x, color: colors.sage, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMd),

          // ── Policy note ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingMd,
              vertical: AppTheme.spacingSm,
            ),
            decoration: BoxDecoration(
              color: colors.stone.withAlpha(40),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.shieldCheck, size: 14, color: colors.sage),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Messages are reviewed for policy compliance. Keep it professional.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.sage,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingMd),

          // ── Text input ─────────────────────────────────────────────────
          TextField(
            controller: _ctrl,
            focusNode: _focusNode,
            maxLines: 5,
            minLines: 3,
            style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Describe your inquiry or the work you need done…',
              hintStyle: TextStyle(color: colors.sage.withAlpha(160), fontSize: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                borderSide: BorderSide(color: colors.stone),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                borderSide: BorderSide(color: colors.linkOlive, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                borderSide: BorderSide(color: colors.urgentRed, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(AppTheme.spacingMd),
              errorText: _errorText,
              errorMaxLines: 2,
            ),
            onChanged: (_) => setState(() => _errorText = null),
          ),
          const SizedBox(height: AppTheme.spacingXs),

          // ── Character counter ──────────────────────────────────────────
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$remaining characters remaining',
              style: theme.textTheme.labelSmall?.copyWith(
                color: overLimit ? colors.urgentRed : colors.sage,
                fontWeight: overLimit ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingMd),

          // ── Send button ────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_sending || overLimit) ? null : _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.olive,
                foregroundColor: colors.onOlive,
                minimumSize: const Size(double.infinity, AppTheme.buttonHeight),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                ),
              ),
              icon: _sending
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onOlive,
                      ),
                    )
                  : Icon(LucideIcons.send, size: 16, color: colors.onOlive),
              label: Text(_sending ? 'Sending…' : 'Send Message'),
            ),
          ),
          const SizedBox(height: AppTheme.spacingXs),
        ],
      ),
    );
  }
}
