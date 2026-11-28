import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/elevo_logic.dart';
import '../../models/maintenance_model.dart';
import '../../theme/theme.dart';
import '../../widgets/common/repair_timeline.dart';
import '../../widgets/common/status_chip.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/maintenance/repair_photo_strip.dart';
import '../chat_screen.dart';

class TenantMaintenanceScreen extends StatefulWidget {
  const TenantMaintenanceScreen({super.key});

  @override
  State<TenantMaintenanceScreen> createState() => _TenantMaintenanceScreenState();
}

class _TenantMaintenanceScreenState extends State<TenantMaintenanceScreen> {
  final _db = Supabase.instance.client;
  List<MaintenanceRequest> _requests = [];
  bool _loading = true;
  bool _tabVisible = false;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadRequests();
    final uid = _db.auth.currentUser?.id;
    if (uid != null) {
      _channel = _db
          .channel('tenant-repairs-$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'maintenance_requests',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: uid,
            ),
            callback: (_) => _loadRequests(),
          )
          .subscribe();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.of(context);
    if (visible && !_tabVisible) _loadRequests();
    _tabVisible = visible;
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) _db.removeChannel(channel);
    super.dispose();
  }

  Future<void> _loadRequests() async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) { setState(() => _loading = false); return; }
      final rows = await _db
          .from('maintenance_requests')
          .select()
          .eq('tenant_id', uid)
          .order('created_at', ascending: false);
      setState(() {
        _requests = rows.map<MaintenanceRequest>(_mapMaintenance).toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  MaintenanceRequest _mapMaintenance(Map<String, dynamic> r) => MaintenanceRequest(
        id: r['id'] as String,
        unitId: r['unit_id'] as String,
        propertyId: '',
        landlordId: r['landlord_id'] as String,
        submittedBy: (r['tenant_id'] as String?) ?? '',
        description: r['description'] as String,
        category: (r['category'] as String?) ?? 'Other',
        assignedVendorId: r['vendor_user_id'] as String?,
        assignedVendorName: r['vendor_name'] as String?,
        priority: _capitalize((r['priority'] as String?) ?? 'medium'),
        status: _mapStatus((r['status'] as String?) ?? 'open'),
        unitAddress: r['unit_address'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
        photos: repairPhotoPaths(r['photo_paths']),
      );

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _mapStatus(String s) => mapMaintenanceStatus(s);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final requests = _requests;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Maintenance')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () { HapticFeedback.lightImpact(); _showSubmitSheet(context); },
                icon: const Icon(LucideIcons.plus, size: 18),
                label: const Text('Submit New Request'),
              ),
            ),
          ),
          Expanded(
            child: requests.isEmpty
                ? const EmptyState(
                    icon: LucideIcons.wrench,
                    message: 'No maintenance requests yet',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
                    itemCount: requests.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spacingSm),
                    itemBuilder: (context, i) {
                      final r = requests[i];
                      return Container(
                        padding: const EdgeInsets.all(AppTheme.spacingMd),
                        decoration: AppTheme.surfaceCard(colors),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                StatusChip(label: r.category),
                                const SizedBox(width: AppTheme.spacingSm),
                                StatusChip(label: r.status),
                                const Spacer(),
                                StatusChip(label: r.priority),
                              ],
                            ),
                            const SizedBox(height: AppTheme.spacingSm),
                            Text(r.description, style: theme.textTheme.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                            if (r.photos.isNotEmpty) ...[
                              const SizedBox(height: AppTheme.spacingSm),
                              RepairPhotoIndicator(count: r.photos.length, color: colors.sage),
                              const SizedBox(height: AppTheme.spacingSm),
                              RepairPhotoStrip(groupId: r.id, paths: r.photos),
                            ],
                            const SizedBox(height: AppTheme.spacingSm),
                            RepairStatusTimeline(currentIndex: r.statusIndex),
                            if (r.assignedVendorId != null && r.assignedVendorId!.isNotEmpty) ...[
                              const SizedBox(height: AppTheme.spacingSm),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () => openJobChat(
                                    context,
                                    requestId: r.id,
                                    unitId: r.unitId,
                                    unitAddress: r.unitAddress ?? r.description,
                                    status: r.status,
                                  ),
                                  icon: Icon(LucideIcons.users, size: 16, color: colors.midnight),
                                  label: Text(
                                    'Job chat',
                                    style: TextStyle(color: colors.midnight),
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () {
                                    final vendorName = (r.assignedVendorName ?? '').trim();
                                    context.push(
                                      '/tenant/maintenance/chat/${r.unitId}'
                                      '?with=${Uri.encodeComponent(r.assignedVendorId!)}'
                                      '&name=${Uri.encodeComponent(vendorName.isEmpty ? 'Vendor' : vendorName)}'
                                      '&addr=${Uri.encodeComponent(r.unitAddress ?? '')}',
                                    );
                                  },
                                  icon: Icon(LucideIcons.messageSquare, size: 16, color: colors.midnight),
                                  label: Text(
                                    'Message ${((r.assignedVendorName ?? '').trim().isEmpty) ? 'vendor' : r.assignedVendorName}',
                                    style: TextStyle(color: colors.midnight),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showSubmitSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _NewRepairSheet(
        db: _db,
        onSubmitted: _loadRequests,
      ),
    );
  }
}

String _repairPhotoSaveMessage(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('42501') ||
      text.contains('only add photos') ||
      text.contains('up to 5 files')) {
    return 'Your request was saved. Photos must be up to 5 files for this repair only.';
  }
  return 'Your request was saved, but the photos could not be attached.';
}

class _PendingRepairPhoto {
  final String name;
  final Uint8List bytes;

  const _PendingRepairPhoto({required this.name, required this.bytes});
}

class _NewRepairSheet extends StatefulWidget {
  final SupabaseClient db;
  final VoidCallback onSubmitted;

  const _NewRepairSheet({required this.db, required this.onSubmitted});

  @override
  State<_NewRepairSheet> createState() => _NewRepairSheetState();
}

class _NewRepairSheetState extends State<_NewRepairSheet> {
  final _descCtrl = TextEditingController();
  final _unitCtrl = TextEditingController();
  final _photos = <_PendingRepairPhoto>[];
  String _category = 'Plumbing';
  String _priority = 'Medium';
  bool _submitting = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    _unitCtrl.dispose();
    super.dispose();
  }

  _PendingRepairPhoto _prepare(String name, Uint8List bytes) {
    final shrunk = shrinkRepairPhoto(bytes);
    final isJpeg = shrunk.length >= 3 &&
        shrunk[0] == 0xFF &&
        shrunk[1] == 0xD8 &&
        shrunk[2] == 0xFF;
    return _PendingRepairPhoto(
      name: isJpeg ? repairPhotoJpegName(name) : name,
      bytes: shrunk,
    );
  }

  void _addPhotos(List<_PendingRepairPhoto> incoming) {
    if (incoming.isEmpty) return;
    final room = repairPhotoLimit - _photos.length;
    if (room <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can attach up to 5 photos.')),
      );
      return;
    }
    setState(() => _photos.addAll(incoming.take(room)));
    if (incoming.length > room && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can attach up to 5 photos.')),
      );
    }
  }

  Future<void> _pickWeb() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;
    _addPhotos([
      for (final file in result.files)
        if (file.bytes != null) _prepare(file.name, file.bytes!),
    ]);
  }

  Future<void> _pickMobile(ImageSource source) async {
    final picker = ImagePicker();
    if (source == ImageSource.camera) {
      final shot = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: repairPhotoMaxSide.toDouble(),
        maxHeight: repairPhotoMaxSide.toDouble(),
        imageQuality: repairPhotoJpegQuality,
      );
      if (shot == null) return;
      _addPhotos([_prepare(shot.name, await shot.readAsBytes())]);
      return;
    }
    final files = await picker.pickMultiImage(
      maxWidth: repairPhotoMaxSide.toDouble(),
      maxHeight: repairPhotoMaxSide.toDouble(),
      imageQuality: repairPhotoJpegQuality,
    );
    if (files.isEmpty) return;
    final pending = <_PendingRepairPhoto>[];
    for (final file in files) {
      pending.add(_prepare(file.name, await file.readAsBytes()));
    }
    _addPhotos(pending);
  }

  Future<void> _submit() async {
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final colors = Theme.of(context).extension<ElevoColors>()!;
    final unitNum = _unitCtrl.text.trim();
    final category = _category;
    final priority = _priority;
    final photos = List<_PendingRepairPhoto>.from(_photos);
    Navigator.pop(context);
    try {
      final uid = widget.db.auth.currentUser?.id;
      if (uid == null) throw Exception('Not signed in');
      List<dynamic> unitRows = await widget.db
          .from('units')
          .select('id, landlord_id')
          .eq('tenant_id', uid)
          .limit(1);
      if (unitRows.isEmpty && unitNum.isNotEmpty) {
        unitRows = await widget.db
            .from('units')
            .select('id, landlord_id')
            .eq('unit_number', unitNum)
            .limit(1);
      }
      final requestId = const Uuid().v4();
      final payload = <String, dynamic>{
        'id': requestId,
        'tenant_id': uid,
        'description': desc,
        'category': category,
        'priority': priority.toLowerCase(),
        'status': 'open',
      };
      if (unitRows.isNotEmpty) {
        final row = unitRows.first as Map<String, dynamic>;
        final unitId = row['id'] as String?;
        final landlordId = row['landlord_id'] as String?;
        if (unitId != null) payload['unit_id'] = unitId;
        if (landlordId != null) payload['landlord_id'] = landlordId;
      }
      await widget.db.from('maintenance_requests').insert(payload).select();
      final paths = <String>[];
      for (final photo in photos) {
        try {
          final path = repairPhotoStoragePath(
            tenantId: uid,
            requestId: requestId,
            fileName: photo.name,
            timestamp: DateTime.now().microsecondsSinceEpoch,
          );
          await widget.db.storage.from(repairPhotoBucket).uploadBinary(
                path,
                photo.bytes,
                fileOptions: const FileOptions(upsert: false),
              );
          paths.add(path);
        } catch (_) {}
      }
      if (paths.isNotEmpty) {
        try {
          await widget.db
              .from('maintenance_requests')
              .update({'photo_paths': paths})
              .eq('id', requestId);
        } catch (e) {
          widget.onSubmitted();
          messenger.showSnackBar(
            SnackBar(content: Text(_repairPhotoSaveMessage(e))),
          );
          return;
        }
      }
      widget.onSubmitted();
      messenger.showSnackBar(
        SnackBar(
          content: Text(photos.isEmpty || paths.length == photos.length
              ? 'Request submitted'
              : 'Request submitted. Some photos could not be saved.'),
          backgroundColor: colors.successGreen,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to submit: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppTheme.spacingLg,
        AppTheme.spacingLg,
        AppTheme.spacingLg,
        MediaQuery.of(context).viewInsets.bottom + AppTheme.spacingLg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Submit Request', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppTheme.spacingMd),
            TextField(
              controller: _unitCtrl,
              style: TextStyle(color: colors.ink),
              decoration: const InputDecoration(
                labelText: 'Unit Number (optional)',
                hintText: 'e.g. 2B',
              ),
            ),
            const SizedBox(height: AppTheme.spacingSm),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              style: TextStyle(color: colors.ink),
              decoration: const InputDecoration(
                labelText: 'Description *',
                hintText: 'Describe the issue...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppTheme.spacingSm),
            DropdownButtonFormField<String>(
              value: _category,
              dropdownColor: colors.card,
              style: TextStyle(color: colors.ink),
              decoration: const InputDecoration(labelText: 'Category'),
              items: MaintenanceRequest.categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: AppTheme.spacingSm),
            DropdownButtonFormField<String>(
              value: _priority,
              dropdownColor: colors.card,
              style: TextStyle(color: colors.ink),
              decoration: const InputDecoration(labelText: 'Priority'),
              items: MaintenanceRequest.priorities
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) => setState(() => _priority = v ?? _priority),
            ),
            const SizedBox(height: AppTheme.spacingMd),
            Text('Photos (up to 5)', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppTheme.spacingSm),
            if (_photos.isNotEmpty)
              SizedBox(
                height: 76,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final photo = _photos[index];
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                          child: Image.memory(
                            photo.bytes,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: () => setState(() => _photos.removeAt(index)),
                            icon: Icon(LucideIcons.x, size: 16, color: colors.ivory),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            const SizedBox(height: AppTheme.spacingSm),
            if (kIsWeb)
              OutlinedButton.icon(
                onPressed: _photos.length >= repairPhotoLimit ? null : _pickWeb,
                icon: const Icon(LucideIcons.paperclip, size: 16),
                label: const Text('Add photos'),
              )
            else
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _photos.length >= repairPhotoLimit
                        ? null
                        : () => _pickMobile(ImageSource.camera),
                    icon: const Icon(LucideIcons.camera, size: 16),
                    label: const Text('Camera'),
                  ),
                  const SizedBox(width: AppTheme.spacingSm),
                  OutlinedButton.icon(
                    onPressed: _photos.length >= repairPhotoLimit
                        ? null
                        : () => _pickMobile(ImageSource.gallery),
                    icon: const Icon(LucideIcons.image, size: 16),
                    label: const Text('Gallery'),
                  ),
                ],
              ),
            const SizedBox(height: AppTheme.spacingLg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? 'Submitting...' : 'Submit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

