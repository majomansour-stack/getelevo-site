import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/elevo_logic.dart';
import '../../providers/messages_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/common/empty_state.dart';
import '../chat_screen.dart';

class VendorMessagesScreen extends StatefulWidget {
  const VendorMessagesScreen({super.key});

  @override
  State<VendorMessagesScreen> createState() => _VendorMessagesScreenState();
}

class _VendorMessagesScreenState extends State<VendorMessagesScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _threads = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadThreads();
  }

  Future<void> _loadThreads() async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) { setState(() => _loading = false); return; }

      // Fetch all units where this vendor has sent or received messages.
      // Messages are stored in the messages table with unit_id.
      // We fetch all unique unit_ids from messages where sender_id = uid,
      // then join with units and users to get landlord info.
      final rows = await _db
          .from('messages')
          .select('unit_id, created_at, content')
          .eq('sender_id', uid)
          .order('created_at', ascending: false);

      // Keep the latest message per unit, whether the vendor sent it or
      // received it. Both queries are newest-first, but an older outgoing
      // note must not hide a newer reply.
      final Map<String, Map<String, dynamic>> seen = {};
      for (final r in rows) {
        _keepLatestMessage(seen, r);
      }

      // Also fetch messages sent TO this vendor (by landlords in their units).
      final inbound = await _db
          .from('messages')
          .select('unit_id, created_at, content, sender_id')
          .eq('receiver_id', uid)
          .order('created_at', ascending: false);

      for (final r in inbound) {
        _keepLatestMessage(seen, r);
      }

      // Enrich with unit address info.
      final enriched = <Map<String, dynamic>>[];
      for (final entry in seen.entries) {
        try {
          final unitRow = await _db
              .from('vendor_job_units')
              .select('unit_number, address, property_name')
              .eq('id', entry.key)
              .maybeSingle();
          if (unitRow != null) {
            enriched.add({
              'unit_id': entry.key,
              'unit_number': unitRow['unit_number'] as String? ?? '',
              'property_name': unitRow['property_name'] as String? ?? '',
              'property_address': unitRow['address'] as String? ?? '',
              'last_message': entry.value['content'] as String? ?? '',
              'created_at': entry.value['created_at'],
            });
          }
        } catch (_) {}
      }

      final inbox = MessagesProvider();
      final jobs = await inbox.loadJobInboxThreads();
      inbox.dispose();
      for (final job in jobs) {
        enriched.add({
          'job_request_id': job.requestId,
          'unit_id': job.unitId,
          'unit_number': '',
          'property_name': 'Job chat',
          'property_address': job.address.isEmpty ? job.title : job.address,
          'last_message': job.preview,
          'created_at': job.at?.toUtc().toIso8601String(),
          'job_status': job.status,
        });
      }

      setState(() {
        _threads = enriched;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _keepLatestMessage(
    Map<String, Map<String, dynamic>> seen,
    Map<String, dynamic> row,
  ) {
    final unitId = row['unit_id'] as String?;
    if (unitId == null || unitId.isEmpty) return;
    final current = seen[unitId];
    if (current == null) {
      seen[unitId] = row;
      return;
    }
    final nextAt = parseServerTimestamp(row['created_at']);
    final prevAt = parseServerTimestamp(current['created_at']);
    if (nextAt != null && (prevAt == null || nextAt.isAfter(prevAt))) {
      seen[unitId] = row;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Messages',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: colors.midnight, fontWeight: FontWeight.w700)),
      ),
      body: _threads.isEmpty
          ? const EmptyState(
              icon: LucideIcons.messageSquare,
              message: 'No message threads yet.\nLandlords will contact you here.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              itemCount: _threads.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spacingSm),
              itemBuilder: (context, i) {
                final t = _threads[i];
                final unitId = t['unit_id'] as String;
                final number = (t['unit_number'] as String?) ?? '';
                final place = (t['property_address'] as String?) ?? '';
                final address = number.isEmpty ? place : '$place #$number';
                final preview = t['last_message'] as String;
                final sentAt = parseServerTimestamp(t['created_at']);
                final timeLabel =
                    sentAt == null ? '' : formatChatTimestamp(sentAt);
                final jobId = t['job_request_id'] as String?;
                return GestureDetector(
                  onTap: () {
                    if (jobId != null && jobId.isNotEmpty) {
                      openJobChat(
                        context,
                        requestId: jobId,
                        unitId: unitId,
                        unitAddress: address,
                        status: t['job_status'] as String? ?? '',
                      ).then((_) {
                        if (context.mounted) _loadThreads();
                      });
                      return;
                    }
                    context.push(
                      '/vendor/messages/$unitId?name=${Uri.encodeComponent(t['property_name'] as String? ?? 'Landlord')}&addr=${Uri.encodeComponent(address)}',
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(AppTheme.spacingMd),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      border: Border.all(color: colors.stone),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colors.midnight.withAlpha(15),
                            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                          ),
                          child: Icon(LucideIcons.messageSquare,
                              color: colors.midnight, size: 20),
                        ),
                        const SizedBox(width: AppTheme.spacingMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(address,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                                color: colors.ink,
                                                fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  if (timeLabel.isNotEmpty) ...[
                                    const SizedBox(width: AppTheme.spacingSm),
                                    Text(timeLabel,
                                        style: theme.textTheme.labelSmall),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(preview,
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: colors.sage),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        Icon(LucideIcons.chevronRight, size: 16, color: colors.stone),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
