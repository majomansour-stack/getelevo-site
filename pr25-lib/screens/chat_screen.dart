import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/elevo_logic.dart';
import '../providers/auth_provider.dart';
import '../providers/messages_provider.dart';
import '../services/push_notification_service.dart';
import '../theme/theme.dart';

class ChatScreen extends StatefulWidget {
  final String unitId;
  final String otherPartyName;
  final String unitAddress;

  /// When set, this screen is one pair (for example the tenant and the
  /// vendor on a job). When empty, the unit landlord sees every message
  /// on the unit.
  final String? counterpartyId;

  /// Repair-job group thread. Null for the existing 1:1 unit chat.
  final String? maintenanceRequestId;
  final bool jobClosed;

  const ChatScreen({
    super.key,
    required this.unitId,
    required this.otherPartyName,
    required this.unitAddress,
    this.counterpartyId,
    this.maintenanceRequestId,
    this.jobClosed = false,
  });

  bool get isJobChat =>
      maintenanceRequestId != null && maintenanceRequestId!.isNotEmpty;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textC = TextEditingController();
  final _scrollC = ScrollController();
  MessagesProvider? _messages;
  String? _landlordId;
  String? _tenantId;
  List<JobChatParticipant> _participants = [];

  /// Offset 0 is the bottom of a reversed list. Stay there unless the
  /// reader has scrolled up into older messages.
  bool _pinnedToLatest = true;
  bool _movingToLatest = false;

  bool get _jobMode => widget.isJobChat;

  @override
  void initState() {
    super.initState();
    _scrollC.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openThread());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final messages = context.read<MessagesProvider>();
    if (!identical(messages, _messages)) {
      _messages?.removeListener(_onMessagesChanged);
      _messages = messages;
      _messages!.addListener(_onMessagesChanged);
    }
  }

  void _onScroll() {
    if (!_scrollC.hasClients || _movingToLatest) return;
    _pinnedToLatest = _scrollC.offset <= 72;
  }

  void _onMessagesChanged() {
    if (_pinnedToLatest) _revealLatest();
  }

  void _revealLatest() {
    _pinnedToLatest = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_scrollC.hasClients || _scrollC.offset <= 1) return;
      _movingToLatest = true;
      try {
        await _scrollC.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } catch (_) {
        // The list can detach if the thread reloads mid-animation.
      } finally {
        _movingToLatest = false;
      }
    });
  }

  String _heading = '';

  Future<void> _fillHeading() async {
    final current = widget.otherPartyName.trim();
    if (current.isNotEmpty && current != 'Job chat') {
      if (mounted) setState(() => _heading = current);
      return;
    }
    if (_jobMode) {
      if (mounted) setState(() => _heading = 'Job chat');
      return;
    }
    final me = Supabase.instance.client.auth.currentUser?.id;
    final other = me != null && me == _landlordId ? _tenantId : _landlordId;
    if (other == null || other.isEmpty) return;
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('full_name')
          .eq('id', other)
          .maybeSingle();
      final name = (row?['full_name'] as String?)?.trim() ?? '';
      if (mounted && name.isNotEmpty) setState(() => _heading = name);
    } catch (_) {
      try {
        final contact = await Supabase.instance.client.rpc(
          'landlord_contact_for_tenant',
          params: {'p_landlord': other},
        );
        String name = '';
        if (contact is List && contact.isNotEmpty && contact.first is Map) {
          name = (contact.first['full_name'] as String?)?.trim() ?? '';
        }
        if (mounted && name.isNotEmpty) setState(() => _heading = name);
      } catch (_) {}
    }
  }

  Future<void> _openThread() async {
    if (!mounted) return;
    if (_jobMode) {
      await context.read<MessagesProvider>().loadJobChat(widget.maintenanceRequestId!);
      await _loadParticipants();
      return;
    }
    final party = widget.counterpartyId?.trim() ?? '';
    await context.read<MessagesProvider>().loadChatMessages(
      widget.unitId,
      fromSenderId: party.isEmpty ? null : party,
    );
    try {
      final row = await Supabase.instance.client
          .from('units')
          .select('tenant_id, landlord_id')
          .eq('id', widget.unitId)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() {
        _tenantId = row['tenant_id'] as String?;
        _landlordId = row['landlord_id'] as String?;
      });
      await _fillHeading();
    } catch (_) {}
  }

  Future<void> _loadParticipants() async {
    try {
      final rows = await Supabase.instance.client.rpc(
        'job_chat_directory',
        params: {'p_request': widget.maintenanceRequestId},
      );
      if (!mounted || rows is! List) return;
      setState(() {
        _participants = [
          for (final row in rows)
            if (row is Map)
              JobChatParticipant(
                userId: row['user_id']?.toString() ?? '',
                name: (row['full_name']?.toString() ?? '').trim(),
                role: row['participant_role']?.toString() ?? '',
                active: row['active'] != false,
              ),
        ].where((person) => person.userId.isNotEmpty).toList();
      });
    } catch (_) {}
  }

  String? _replyReceiver() {
    final me = context.read<AuthProvider>().currentUser?.id;
    if (me == null) return null;
    final messages = context.read<MessagesProvider>().chatMessages;
    return chatReplyReceiver(
      me: me,
      landlordId: _landlordId,
      tenantId: _tenantId,
      counterpartyId: widget.counterpartyId,
      // The provider keeps the newest message first.
      senderIdsOldestFirst:
          messages.reversed.map((message) => message.senderId).toList(),
    );
  }

  @override
  void dispose() {
    _messages?.removeListener(_onMessagesChanged);
    _textC.dispose();
    _scrollC.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'docx'],
        withData: true,
        allowCompression: false,
      );
      if (result != null && result.files.isNotEmpty && mounted) {
        final file = result.files.first;
        final bytes = file.bytes;
        final me = context.read<AuthProvider>().currentUser;
        if (bytes == null || me == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read that file.')),
          );
          return;
        }
        final db = Supabase.instance.client;
        final safeName = storageSafeFileName(file.name);
        final stamp = DateTime.now().millisecondsSinceEpoch;
        final path = _jobMode
            ? jobChatAttachmentPath(
                uploaderId: me.id,
                requestId: widget.maintenanceRequestId!,
                fileName: safeName,
                timestamp: stamp,
              )
            : '${me.id}/chat/${widget.unitId}/${stamp}_$safeName';
        await db.storage.from('documents').uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(upsert: false),
            );
        final note = chatFileMessage(file.name, path);
        final sent = _jobMode
            ? await context.read<MessagesProvider>().sendJobMessage(
                requestId: widget.maintenanceRequestId!,
                unitId: widget.unitId,
                senderId: me.id,
                text: note,
              )
            : await context.read<MessagesProvider>().sendMessage(
                unitId: widget.unitId,
                senderId: me.id,
                receiverId: _replyReceiver() ?? '',
                text: note,
              );
        if (sent && _jobMode) {
          _notifyJobParticipants(me.fullName, 'Shared a file: ${file.name}');
        }
        if (!mounted) return;
        if (!sent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not send that file.')),
          );
          return;
        }
        if (!mounted) return;
        _revealLatest();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sent ${file.name}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _textC.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    final me = context.read<AuthProvider>().currentUser;
    if (me == null) return;
    if (_jobMode) {
      if (widget.jobClosed) return;
      final sent = await context.read<MessagesProvider>().sendJobMessage(
        requestId: widget.maintenanceRequestId!,
        unitId: widget.unitId,
        senderId: me.id,
        text: text,
      );
      if (!mounted) return;
      if (!sent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message was not sent. Please try again.')),
        );
        return;
      }
      _notifyJobParticipants(me.fullName, text);
      _textC.clear();
      _revealLatest();
      return;
    }
    final receiverId = _replyReceiver() ?? '';
    if (receiverId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not tell who this message is for.')),
      );
      return;
    }
    final sent = await context.read<MessagesProvider>().sendMessage(
      unitId: widget.unitId,
      senderId: me.id,
      receiverId: receiverId,
      text: text,
    );
    if (!mounted) return;
    if (!sent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message was not sent. Please try again.')),
      );
      return;
    }
    PushNotificationService.notifyNewMessage(
      recipientId: receiverId,
      senderName: me.fullName.isEmpty ? 'Elevo' : me.fullName,
      preview: text,
      unitId: widget.unitId,
    );
    _textC.clear();
    _revealLatest();
  }

  void _notifyJobParticipants(String senderName, String preview) {
    final me = context.read<AuthProvider>().currentUser?.id ?? '';
    for (final recipientId in jobChatNotifyIds(
      senderId: me,
      activeParticipantIds: _participants.map((person) => person.userId),
    )) {
      PushNotificationService.notifyNewMessage(
        recipientId: recipientId,
        senderName: senderName.isEmpty ? 'Elevo' : senderName,
        preview: preview,
        unitId: widget.unitId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<MessagesProvider>();
    final myId = auth.currentUser?.id;
    if (myId == null) {
      return const Scaffold(body: Center(child: Text('Sign in to view messages.')));
    }
    final visible = _jobMode
        ? provider.chatMessages
        : provider.chatMessages.where((message) => chatMessageVisible(
            me: myId,
            landlordId: _landlordId,
            counterpartyId: widget.counterpartyId,
            senderId: message.senderId,
            receiverId: message.receiverId,
          )).toList();
    final names = {
      for (final person in _participants)
        if (person.name.isNotEmpty) person.userId: person.name,
    };

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _heading.isNotEmpty
                  ? _heading
                  : (widget.otherPartyName.trim().isEmpty
                      ? 'Messages'
                      : widget.otherPartyName),
              style: theme.textTheme.titleSmall?.copyWith(color: colors.midnight),
            ),
            Text(widget.unitAddress, style: theme.textTheme.labelSmall?.copyWith(fontSize: 11)),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_jobMode)
            _JobParticipantHeader(participants: _participants, colors: colors),
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollC,
                    reverse: true,
                    padding: const EdgeInsets.all(AppTheme.spacingMd),
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final msg = visible[i];
                      final isSystem = msg.senderId == 'system';
                      final isMine = !isSystem && msg.senderId == myId;
                      return _MessageBubble(
                        text: msg.messageText,
                        isMine: isMine,
                        isSystem: isSystem,
                        time: formatChatTimestamp(msg.createdAt),
                        isRead: msg.isRead,
                        senderLabel: _jobMode && !isMine
                            ? (names[msg.senderId] ?? 'Participant')
                            : null,
                      );
                    },
                  ),
          ),
          if (_jobMode && widget.jobClosed)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              color: theme.colorScheme.surface,
              child: SafeArea(
                top: false,
                child: Text(
                  'This job chat is closed. You can still read it.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.sage),
                ),
              ),
            )
          else
          MessageComposerBar(
            controller: _textC,
            onSend: _send,
            onAttach: _pickAttachment,
          ),
        ],
      ),
    );
  }

}

/// Shared by landlord, tenant, and vendor chats. The field fill and the
/// typed text both come from the color scheme so they stay readable in
/// light and dark mode.
class MessageComposerBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  const MessageComposerBar({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAttach,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingSm,
        vertical: AppTheme.spacingSm,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: colors.stone)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            ElevatedButton(
              onPressed: onAttach,
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.surfaceContainerHighest,
                foregroundColor: scheme.onSurface,
                elevation: 0,
                padding: EdgeInsets.zero,
                minimumSize: Size(AppTheme.touchTarget, AppTheme.touchTarget),
                shape: const CircleBorder(),
                side: BorderSide.none,
              ),
              child: Icon(LucideIcons.paperclip, color: scheme.onSurface, size: 20),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                cursorColor: scheme.onSurface,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(color: colors.sage),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                    borderSide: BorderSide(color: colors.stone),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                    borderSide: BorderSide(color: colors.stone),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                    borderSide: BorderSide(color: colors.linkOlive, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: AppTheme.spacingSm),
            SizedBox(
              width: AppTheme.touchTarget,
              height: AppTheme.touchTarget,
              child: IconButton(
                icon: Icon(LucideIcons.send, color: colors.goldInk, size: 20),
                onPressed: onSend,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobParticipantHeader extends StatelessWidget {
  final List<JobChatParticipant> participants;
  final ElevoColors colors;

  const _JobParticipantHeader({
    required this.participants,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = participants.where((person) => person.active).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingMd,
        AppTheme.spacingSm,
        AppTheme.spacingMd,
        AppTheme.spacingSm,
      ),
      color: Theme.of(context).colorScheme.surface,
      child: people.isEmpty
          ? Text(
              'Landlord, tenant, and vendor',
              style: theme.textTheme.labelSmall?.copyWith(color: colors.sage),
            )
          : Wrap(
              spacing: AppTheme.spacingSm,
              runSpacing: 4,
              children: [
                for (final person in people)
                  Text(
                    '${person.name.isEmpty ? person.roleLabel : person.name} · ${person.roleLabel}',
                    style: theme.textTheme.labelSmall?.copyWith(color: colors.midnight),
                  ),
              ],
            ),
    );
  }
}

Future<void> openJobChat(BuildContext context, {
  required String requestId,
  required String unitId,
  required String unitAddress,
  required String status,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider(
        create: (_) => MessagesProvider(),
        child: ChatScreen(
          unitId: unitId,
          otherPartyName: 'Job chat',
          unitAddress: unitAddress,
          maintenanceRequestId: requestId,
          jobClosed: maintenanceThreadIsClosed(status),
        ),
      ),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  final String text;
  final bool isMine;
  final bool isSystem;
  final String time;
  final bool isRead;
  final String? senderLabel;

  const _MessageBubble({
    required this.text,
    required this.isMine,
    required this.time,
    required this.isRead,
    this.isSystem = false,
    this.senderLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    final theme = Theme.of(context);

    // System messages use a special gold-bordered card spanning the full width.
    if (isSystem) {
      return Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        decoration: BoxDecoration(
          color: colors.olive,
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.gold.withAlpha(40),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'ELEVO',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onOlive,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      fontSize: 10,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.spacingXs),
                Text(
                  'Automated Welcome Message',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.taupe,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingSm),
            Text(
              text,
              style: TextStyle(color: colors.ivory, fontSize: 13, height: 1.55),
            ),
            const SizedBox(height: AppTheme.spacingXs),
            Text(
              time,
              style: TextStyle(color: colors.taupe, fontSize: 10),
            ),
          ],
        ),
      );
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacingSm),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMine ? colors.card : colors.olive,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMine ? 20 : 6),
            bottomRight: Radius.circular(isMine ? 6 : 20),
          ),
          border: isMine ? Border.all(color: colors.stone) : null,
          boxShadow: isMine ? AppTheme.cardShadow(colors) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (senderLabel != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    senderLabel!,
                    style: TextStyle(
                      color: isMine ? colors.goldInk : colors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            _ChatFileOrText(
              text: text,
              color: isMine ? colors.ink : colors.onOlive,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    color: isMine ? colors.sage : colors.onOlive.withAlpha(170),
                    fontSize: 10,
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    LucideIcons.checkCheck,
                    size: 12,
                    color: isRead ? colors.linkOlive : colors.sage,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatFileOrText extends StatelessWidget {
  final String text;
  final Color color;

  const _ChatFileOrText({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final file = storedChatFile(text);
    if (file == null) {
      return Text(text, style: TextStyle(color: color, fontSize: 14));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(file.label, style: TextStyle(color: color, fontSize: 14)),
        TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: color,
          ),
          onPressed: () async {
            try {
              final signed = await Supabase.instance.client.storage
                  .from('documents')
                  .createSignedUrl(file.path, 3600);
              final opened = await launchUrl(
                Uri.parse(signed),
                mode: LaunchMode.externalApplication,
              );
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not open that file.')),
                );
              }
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not open that file.')),
                );
              }
            }
          },
          child: const Text('Open file'),
        ),
      ],
    );
  }
}
