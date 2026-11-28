import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/elevo_logic.dart';
import '../models/message_model.dart';

class MessagesProvider extends ChangeNotifier {
  final _db = Supabase.instance.client;

  List<Conversation> _conversations = [];
  List<Conversation> get conversations => _conversations;

  /// Newest message first. The chat screen reverses the list so index 0
  /// is the bubble at the bottom.
  List<Message> _chatMessages = [];
  List<Message> get chatMessages => _chatMessages;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSub;

  int get totalUnread =>
      _conversations.fold(0, (sum, c) => sum + c.unreadCount);

  Future<void> loadConversations() async {
    _isLoading = true;
    notifyListeners();
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) { _isLoading = false; notifyListeners(); return; }

      // Fetch occupied units that belong to this landlord
      final unitRows = await _db
          .from('units')
          .select('id, unit_number, tenant_id, tenant_name, property_id, properties(name, address)')
          .eq('landlord_id', uid)
          .eq('status', 'occupied');

      final convs = <Conversation>[];
      for (final u in unitRows) {
        final unitId = u['id'] as String;
        // Get last message for this unit
        final msgRows = await _oneToOneMessages(
          unitId,
          newestFirst: true,
          limit: 1,
        );
        final lastMsg = msgRows.isNotEmpty ? _mapMessage(msgRows.first) : null;
        final unread = lastMsg != null &&
                lastMsg.receiverId == uid &&
                !lastMsg.isRead
            ? 1
            : 0;
        final propData = u['properties'] as Map<String, dynamic>?;
        final address = propData != null
            ? '${propData['address']} #${u['unit_number']}'
            : '#${u['unit_number']}';
        convs.add(Conversation(
          unitId: unitId,
          tenantId: (u['tenant_id'] as String?) ?? '',
          tenantName: (u['tenant_name'] as String?) ?? 'Tenant',
          unitAddress: address,
          lastMessage: lastMsg,
          unreadCount: unread,
        ));
      }
      convs.addAll(await _jobConversations(uid));
      // A unit thread and a job chat on that unit are different conversations.
      final seen = <String>{};
      _conversations = convs.where((c) {
        final key = c.isJobChat ? 'job:${c.jobRequestId}' : c.unitId;
        return seen.add(key);
      }).toList();
      _conversations.sort((a, b) {
        final aAt = a.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bAt = b.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bAt.compareTo(aAt);
      });
    } catch (_) {
      // silently fail — show empty state
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Job chats this person is still in, including a thread with no messages yet.
  Future<List<JobInboxThread>> loadJobInboxThreads() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      final parts = await _db
          .from('job_chat_participants')
          .select('maintenance_request_id')
          .eq('user_id', uid)
          .isFilter('left_at', null);
      final ids = <String>{
        for (final row in parts as List)
          if ((row['maintenance_request_id']?.toString() ?? '').isNotEmpty)
            row['maintenance_request_id'].toString(),
      };
      final threads = <JobInboxThread>[];
      for (final id in ids) {
        final req = await _db
            .from('maintenance_requests')
            .select('id, unit_id, status, description, unit_address')
            .eq('id', id)
            .maybeSingle();
        if (req == null) continue;
        final msgs = await _db
            .from('messages')
            .select('content, created_at')
            .eq('maintenance_request_id', id)
            .order('created_at', ascending: false)
            .limit(1);
        final last = (msgs as List).isEmpty ? null : msgs.first as Map;
        final content = last?['content']?.toString().trim() ?? '';
        threads.add(JobInboxThread(
          requestId: id,
          unitId: req['unit_id']?.toString() ?? '',
          address: (req['unit_address']?.toString() ?? '').trim(),
          title: (req['description']?.toString() ?? '').trim().isEmpty
              ? 'Job chat'
              : req['description'].toString().trim(),
          status: req['status']?.toString() ?? '',
          preview: content.isEmpty ? 'Job chat' : content.split('\n').first,
          at: parseServerTimestamp(last?['created_at']),
        ));
      }
      threads.sort((a, b) {
        final aAt = a.at ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bAt = b.at ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bAt.compareTo(aAt);
      });
      return threads;
    } catch (_) {
      return const [];
    }
  }

  Future<List<Conversation>> _jobConversations(String uid) async {
    final threads = await loadJobInboxThreads();
    return [
      for (final thread in threads)
        Conversation(
          unitId: thread.unitId,
          tenantId: uid,
          tenantName: 'Job chat',
          unitAddress: thread.address.isEmpty ? thread.title : thread.address,
          lastMessage: thread.at == null
              ? null
              : Message(
                  id: '',
                  unitId: thread.unitId,
                  senderId: '',
                  receiverId: '',
                  messageText: thread.preview,
                  createdAt: thread.at!,
                ),
          jobRequestId: thread.requestId,
          jobStatus: thread.status,
        ),
    ];
  }

  Future<void> loadChatMessages(String unitId, {String? fromSenderId}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final uid = _db.auth.currentUser?.id;
      final party = fromSenderId?.trim() ?? '';
      if (uid != null) {
        try {
          var markRead = _db
              .from('messages')
              .update({'is_read': true})
              .eq('unit_id', unitId)
              .eq('receiver_id', uid)
              .eq('is_read', false);
          if (party.isNotEmpty) {
            markRead = markRead.eq('sender_id', party);
          }
          await markRead;
        } catch (e) {
          debugPrint('[messages] could not mark read: $e');
        }
      }
      final rows = await _oneToOneMessages(unitId, newestFirst: true);
      _chatMessages = _newestFirst(rows.map<Message>(_mapMessage));
    } catch (_) {
      _chatMessages = [];
    }
    _isLoading = false;
    notifyListeners();
    _subscribeRealtime(unitId);
  }

  void _subscribeRealtime(String unitId) {
    _realtimeSub?.cancel();
    _realtimeSub = _db
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('unit_id', unitId)
        .order('created_at', ascending: false)
        .listen((rows) {
          _chatMessages = _newestFirst(
            rows
                .where((row) => !isJobChatMessage(row))
                .map<Message>(_mapMessage),
          );
          notifyListeners();
        });
  }

  /// 1:1 rows only. Job threads use [loadJobChat]. If the job column is
  /// not on this database yet, the plain unit query is used.
  Future<List<Map<String, dynamic>>> _oneToOneMessages(
    String unitId, {
    bool newestFirst = false,
    int? limit,
  }) async {
    try {
      var query = _db
          .from('messages')
          .select()
          .eq('unit_id', unitId)
          .isFilter('maintenance_request_id', null)
          .order('created_at', ascending: !newestFirst);
      if (limit != null) query = query.limit(limit);
      final rows = await query;
      return rows.map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (_) {
      var query = _db
          .from('messages')
          .select()
          .eq('unit_id', unitId)
          .order('created_at', ascending: !newestFirst);
      if (limit != null) query = query.limit(limit);
      final rows = await query;
      return rows
          .map((row) => Map<String, dynamic>.from(row))
          .where((row) => !isJobChatMessage(row))
          .toList();
    }
  }

  Future<void> loadJobChat(String requestId) async {
    _isLoading = true;
    notifyListeners();
    try {
      final uid = _db.auth.currentUser?.id;
      final rows = await _db
          .from('messages')
          .select()
          .eq('maintenance_request_id', requestId)
          .order('created_at', ascending: false);
      _chatMessages = _newestFirst(rows.map<Message>(_mapMessage));
      if (uid != null) {
        for (final message in _chatMessages) {
          if (message.senderId == uid || message.id.isEmpty) continue;
          try {
            await _db.from('job_chat_reads').upsert(
              {
                'message_id': message.id,
                'user_id': uid,
                'read_at': DateTime.now().toUtc().toIso8601String(),
              },
              onConflict: 'message_id,user_id',
            );
          } catch (e) {
            debugPrint('[job chat] could not mark read: $e');
          }
        }
      }
    } catch (_) {
      _chatMessages = [];
    }
    _isLoading = false;
    notifyListeners();
    _subscribeJobRealtime(requestId);
  }

  void _subscribeJobRealtime(String requestId) {
    _realtimeSub?.cancel();
    _realtimeSub = _db
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('maintenance_request_id', requestId)
        .order('created_at', ascending: false)
        .listen((rows) {
          _chatMessages = _newestFirst(
            rows
                .where((row) => isJobChatMessage(row))
                .map<Message>(_mapMessage),
          );
          notifyListeners();
        });
  }

  Future<bool> sendJobMessage({
    required String requestId,
    required String unitId,
    required String senderId,
    required String text,
  }) async {
    try {
      await _db.from('messages').insert({
        'unit_id': unitId,
        'maintenance_request_id': requestId,
        'sender_id': senderId,
        'receiver_id': null,
        'content': text,
        'is_read': false,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendMessage({
    required String unitId,
    required String senderId,
    required String receiverId,
    required String text,
  }) async {
    try {
      await _db.from('messages').insert({
        'unit_id': unitId,
        'sender_id': senderId,
        'receiver_id': receiverId,
        'content': text,
        'is_read': false,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Inserts the one-time automated welcome message into Supabase.
  ///
  /// Before inserting, re-reads `welcome_message_sent` directly from the
  /// `users` table so the guard works even if the in-memory flag is stale.
  /// If the flag is already `true` this method returns without doing anything.
  /// On success it immediately sets `welcome_message_sent = true` so a second
  /// concurrent call that passes the initial read will lose the race at the DB
  /// update level (non-fatal: the message would appear twice but this path is
  /// already protected by the local _welcomeInjected guard in the screen).
  Future<void> injectWelcomeMessage({
    required String unitId,
    required String propertyAddress,
  }) async {
    // ── Gate: re-check welcome_message_sent directly in Supabase ─────────────
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final row = await _db
          .from('users')
          .select('welcome_message_sent')
          .eq('id', uid)
          .single();
      final alreadySent = row['welcome_message_sent'] == true;
      if (alreadySent) return;
    } catch (_) {
      // If we cannot verify the flag, skip injection to err on the side of
      // not duplicating the message.
      return;
    }

    const welcomeText =
        'Welcome to ELEVO — we are so glad to have you here.\n\n'
        'You have been successfully added to ELEVO, your property management portal. '
        'Here is everything you need to know to get started:\n\n'
        'All communication with your landlord should go through this app for the fastest response. '
        'This includes maintenance requests, questions about your lease, and any general messages. '
        'Messages sent through ELEVO are tracked and responded to faster than phone calls or emails.\n\n'
        'Here is what we recommend you do right now to get set up:\n\n'
        'First, go to the Documents section and review your lease agreement and any move-in paperwork '
        'that has been shared with you.\n\n'
        'Second, upload your move-in photos. Go to the Photo Log section and upload photos of every room, '
        'every wall, every appliance, and any existing damage you notice before you move in. '
        'Label each photo clearly by room. These photos protect your security deposit when you move out '
        'so be thorough.\n\n'
        'Third, make sure your notification settings are turned on so you never miss a message from '
        'your landlord.\n\n'
        'If you have any questions your landlord is available through the Messages tab. Welcome home.';

    try {
      await _db.rpc('send_tenant_welcome', params: {'p_unit': unitId});
    } catch (_) {
      // If insert fails, show it locally so the tenant still sees the message.
      final welcomeMsg = Message(
        id: 'welcome_${DateTime.now().millisecondsSinceEpoch}',
        unitId: unitId,
        senderId: 'system',
        receiverId: '',
        messageText: welcomeText,
        isRead: true,
        createdAt: DateTime.now(),
      );
      _chatMessages = _newestFirst([..._chatMessages, welcomeMsg]);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  // ── Mapper ────────────────────────────────────────────────────────────────

  Message _mapMessage(Map<String, dynamic> row) {
    return Message(
      id: row['id']?.toString() ?? '',
      unitId: row['unit_id']?.toString() ?? '',
      senderId: row['sender_id']?.toString() ?? '',
      receiverId: row['receiver_id']?.toString() ?? '',
      messageText: row['content']?.toString() ?? '',
      isRead: row['is_read'] == true,
      createdAt: parseServerTimestamp(row['created_at']) ?? DateTime.now(),
    );
  }

  List<Message> _newestFirst(Iterable<Message> messages) {
    final ordered = messages.toList();
    ordered.sort((a, b) {
      final byTime = b.createdAt.compareTo(a.createdAt);
      if (byTime != 0) return byTime;
      return b.id.compareTo(a.id);
    });
    return ordered;
  }
}
