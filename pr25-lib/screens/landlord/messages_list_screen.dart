import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/elevo_logic.dart';
import '../../models/message_model.dart';
import '../../providers/messages_provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/common/empty_state.dart';
import '../chat_screen.dart';

// ── Messages List Screen ──────────────────────────────────────────────────────

class MessagesListScreen extends StatelessWidget {
  const MessagesListScreen({super.key});

  void _showNewMessageSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    final landlordId = context.read<AuthProvider>().currentUser?.id ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewMessageSheet(
        landlordId: landlordId,
        onStartConversation: (unitId, tenantName, unitAddress) {
          context.go(
            '/landlord/messages/chat/$unitId'
            '?name=${Uri.encodeComponent(tenantName)}'
            '&addr=${Uri.encodeComponent(unitAddress)}',
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final provider = context.watch<MessagesProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.pencil, color: colors.gold, size: 20),
            tooltip: 'New Message',
            onPressed: () => _showNewMessageSheet(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewMessageSheet(context),
        child: const Icon(LucideIcons.pencil),
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : provider.conversations.isEmpty
              ? const EmptyState(
                  icon: LucideIcons.messageCircle,
                  message: 'No messages yet',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  itemCount: provider.conversations.length,
                  separatorBuilder: (_, __) => Divider(
                    color: colors.taupe.withAlpha(30),
                    height: 1,
                  ),
                  itemBuilder: (context, i) => _ConversationTile(
                    conversation: provider.conversations[i],
                  ),
                ),
    );
  }
}

// ── Conversation Tile ─────────────────────────────────────────────────────────

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;

  const _ConversationTile({required this.conversation});

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    final name     = conversation.tenantName;
    final initials = name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();

    final lastAt = conversation.lastMessage?.createdAt;
    final timeLabel = lastAt == null ? '' : formatChatTimestamp(lastAt);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (conversation.isJobChat) {
          openJobChat(
            context,
            requestId: conversation.jobRequestId!,
            unitId: conversation.unitId,
            unitAddress: conversation.unitAddress,
            status: conversation.jobStatus,
          ).then((_) {
            if (context.mounted) {
              context.read<MessagesProvider>().loadConversations();
            }
          });
          return;
        }
        context.push(
          '/landlord/messages/chat/${conversation.unitId}'
          '?name=${Uri.encodeComponent(name)}'
          '&addr=${Uri.encodeComponent(conversation.unitAddress)}',
        ).then((_) {
          if (context.mounted) {
            context.read<MessagesProvider>().loadConversations();
          }
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSm + 4),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.gold.withAlpha(30),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: TextStyle(color: colors.goldInk, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacingSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name, style: theme.textTheme.titleSmall?.copyWith(color: colors.midnight)),
                      ),
                      Text(timeLabel, style: theme.textTheme.labelSmall),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    conversation.unitAddress,
                    style: theme.textTheme.labelSmall?.copyWith(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    conversation.lastMessage?.messageText ?? '',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (conversation.unreadCount > 0) ...[
              const SizedBox(width: AppTheme.spacingSm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.gold,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${conversation.unreadCount}',
                  style: TextStyle(color: colors.midnight, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── New Message Sheet ─────────────────────────────────────────────────────────

class _TenantUnit {
  final String unitId;
  final String tenantName;
  final String unitAddress;
  final String propertyName;
  final String unitNumber;

  const _TenantUnit({
    required this.unitId,
    required this.tenantName,
    required this.unitAddress,
    required this.propertyName,
    required this.unitNumber,
  });
}

class _NewMessageSheet extends StatefulWidget {
  final String landlordId;
  final void Function(String unitId, String tenantName, String unitAddress) onStartConversation;

  const _NewMessageSheet({
    required this.landlordId,
    required this.onStartConversation,
  });

  @override
  State<_NewMessageSheet> createState() => _NewMessageSheetState();
}

class _NewMessageSheetState extends State<_NewMessageSheet> {
  String? _selectedUnitId;
  List<_TenantUnit> _units = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUnits();
  }

  Future<void> _loadUnits() async {
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('units')
          .select('id, unit_number, tenant_name, status, properties(name, address)')
          .eq('landlord_id', widget.landlordId)
          .eq('status', 'occupied');

      final result = <_TenantUnit>[];
      for (final row in rows as List) {
        final tenantName = row['tenant_name'] as String?;
        if (tenantName == null || tenantName.isEmpty) continue;
        final property = row['properties'] as Map<String, dynamic>?;
        final propertyName = property?['name'] as String? ?? '';
        final address = property?['address'] as String? ?? '';
        final unitNumber = row['unit_number'] as String? ?? '';
        result.add(_TenantUnit(
          unitId: row['id'] as String,
          tenantName: tenantName,
          unitAddress: '$address #$unitNumber',
          propertyName: propertyName,
          unitNumber: unitNumber,
        ));
      }
      if (mounted) setState(() { _units = result; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final units  = _units;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppTheme.spacingMd,
          right: AppTheme.spacingMd,
          top: AppTheme.spacingLg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppTheme.spacingLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: AppTheme.spacingLg),
                decoration: BoxDecoration(
                  color: colors.taupe.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Row(
              children: [
                Icon(LucideIcons.pencil, color: colors.gold, size: 20),
                const SizedBox(width: 8),
                Text('New Message', style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 6),
            Text('Select a tenant to start a conversation.', style: theme.textTheme.bodySmall),
            const SizedBox(height: AppTheme.spacingLg),

            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: AppTheme.spacingLg),
                child: CircularProgressIndicator(),
              ))
            else if (units.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingLg),
                  child: Column(
                    children: [
                      Icon(LucideIcons.users, color: colors.taupe, size: 36),
                      const SizedBox(height: AppTheme.spacingSm),
                      Text('No tenants yet', style: theme.textTheme.bodyMedium),
                      Text('Invite a tenant to a unit first.', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              )
            else
              ...units.map((u) {
                final initials = u.tenantName
                    .split(' ')
                    .map((w) => w.isNotEmpty ? w[0] : '')
                    .take(2)
                    .join()
                    .toUpperCase();
                final isSelected = _selectedUnitId == u.unitId;

                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedUnitId = u.unitId);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(bottom: AppTheme.spacingXs),
                    padding: const EdgeInsets.all(AppTheme.spacingMd),
                    decoration: BoxDecoration(
                      color: isSelected ? colors.gold.withAlpha(28) : colors.card,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      border: Border.all(
                        color: isSelected ? colors.gold : colors.taupe.withAlpha(40),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.gold.withAlpha(isSelected ? 40 : 20),
                          ),
                          child: Center(
                            child: Text(
                              initials,
                              style: TextStyle(
                                color: colors.gold,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacingSm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                u.tenantName,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: isSelected ? colors.goldInk : colors.ink,
                                ),
                              ),
                              Text(
                                '${u.propertyName} · Unit ${u.unitNumber}',
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(LucideIcons.checkCircle, color: colors.gold, size: 18),
                      ],
                    ),
                  ),
                );
              }),

            if (units.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spacingLg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _selectedUnitId == null
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          final unit = units.firstWhere((u) => u.unitId == _selectedUnitId);
                          Navigator.of(context).pop();
                          widget.onStartConversation(
                            unit.unitId,
                            unit.tenantName,
                            unit.unitAddress,
                          );
                        },
                  icon: const Icon(LucideIcons.send, size: 18, color: Colors.white),
                  label: const Text('Open Conversation'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
