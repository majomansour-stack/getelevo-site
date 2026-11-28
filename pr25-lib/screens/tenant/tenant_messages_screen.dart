import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/message_model.dart';
import '../../providers/messages_provider.dart';
import '../../services/landlord_contact.dart';
import '../chat_screen.dart';

class TenantMessagesScreen extends StatefulWidget {
  const TenantMessagesScreen({super.key});

  @override
  State<TenantMessagesScreen> createState() => _TenantMessagesScreenState();
}

class _TenantMessagesScreenState extends State<TenantMessagesScreen> {
  final _db = Supabase.instance.client;
  String? _unitId;
  String? _landlordId;
  String _landlordName = 'Your Landlord';
  String _unitAddress = '';
  bool _loading = true;
  List<JobInboxThread> _jobs = const [];

  @override
  void initState() {
    super.initState();
    _loadUnit();
  }

  Future<void> _loadUnit() async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) { setState(() => _loading = false); return; }

      // Primary lookup: units where tenant_id matches this user
      List<dynamic> rows = await _db
          .from('units')
          .select('id, unit_number, properties(name, address, landlord_id)')
          .eq('tenant_id', uid)
          .limit(1);

      final email = _db.auth.currentUser?.email?.toLowerCase().trim();
      if (rows.isEmpty && email != null && email.isNotEmpty) {
        try {
          final emailRows = await _db
              .from('units')
              .select('id, unit_number, properties(name, address, landlord_id)')
              .eq('invited_email', email)
              .limit(1);
          if (emailRows.isNotEmpty) {
            final invitedId = emailRows.first['id'] as String?;
            if (invitedId != null) {
              try {
                await _db.from('units').update({
                  'tenant_id': uid,
                  'status': 'occupied',
                }).eq('id', invitedId);
              } catch (_) {}
            }
            rows = emailRows;
          }
        } catch (_) {}
      }

      // Fallback: look up unit_id from the users table (covers manually-created accounts)
      if (rows.isEmpty) {
        try {
          final userRow = await _db
              .from('users')
              .select('unit_id')
              .eq('id', uid)
              .maybeSingle();
          final unitId = userRow?['unit_id'] as String?;
          if (unitId != null) {
            rows = await _db
                .from('units')
                .select('id, unit_number, properties(name, address, landlord_id)')
                .eq('id', unitId)
                .limit(1);
          }
        } catch (_) {}
      }

      if (rows.isEmpty) { setState(() => _loading = false); return; }

      final r = rows.first;
      final propData = r['properties'] as Map<String, dynamic>?;
      final landlordId = propData?['landlord_id'] as String?;
      String landlordName = 'Your Landlord';
      if (landlordId != null) {
        try {
          final uRow = await fetchLandlordContact(_db, landlordId);
          final name = uRow?['full_name'] as String?;
          if (name != null && name.trim().isNotEmpty) landlordName = name;
        } catch (_) {}
      }

      final inbox = MessagesProvider();
      final jobs = await inbox.loadJobInboxThreads();
      inbox.dispose();

      if (mounted) {
        setState(() {
          _unitId = r['id'] as String;
          _landlordId = landlordId;
          _unitAddress = propData != null
              ? '${propData['address']} #${r['unit_number']}'
              : '#${r['unit_number']}';
          _landlordName = landlordName;
          _jobs = jobs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_unitId == null) {
      return const Scaffold(
        body: Center(child: Text('No unit assigned yet. Contact your landlord.')),
      );
    }
    return Column(
      children: [
        if (_jobs.isNotEmpty)
          Material(
            child: Column(
              children: [
                for (final job in _jobs)
                  ListTile(
                    title: Text(job.address.isEmpty ? 'Job chat' : job.address),
                    subtitle: Text(job.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openJobChat(
                      context,
                      requestId: job.requestId,
                      unitId: job.unitId,
                      unitAddress: job.address,
                      status: job.status,
                    ),
                  ),
                const Divider(height: 1),
              ],
            ),
          ),
        Expanded(
          child: ChatScreen(
            unitId: _unitId!,
            otherPartyName: _landlordName,
            unitAddress: _unitAddress,
            counterpartyId: _landlordId,
          ),
        ),
      ],
    );
  }
}
