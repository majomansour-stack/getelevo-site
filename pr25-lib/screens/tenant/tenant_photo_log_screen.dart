import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/elevo_logic.dart';
import '../../theme/theme.dart';

/// Signs a photo-log object. Uses the stored path, or the path inside an
/// older public or signed URL.
Future<String> signedPhotoLogUrl(
  SupabaseClient db, {
  String? storagePath,
  String? publicUrl,
}) async {
  final path = photoLogObjectPath(storagePath) ?? photoLogObjectPath(publicUrl);
  if (path == null) return '';
  try {
    return await db.storage.from('photo-logs').createSignedUrl(path, 60 * 60 * 24 * 7);
  } catch (_) {
    return '';
  }
}

class TenantPhotoLogScreen extends StatefulWidget {
  const TenantPhotoLogScreen({super.key});

  @override
  State<TenantPhotoLogScreen> createState() => _TenantPhotoLogScreenState();
}

class _TenantPhotoLogScreenState extends State<TenantPhotoLogScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _db = Supabase.instance.client;

  String? _unitId;
  bool _loadingPhotos = true;
  List<_PhotoEntry> _moveIn = [];
  String _inspectionDate = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUnitAndPhotos();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUnitAndPhotos() async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) setState(() => _loadingPhotos = false);
        return;
      }
      // Fetch the tenant's linked unit.
      final unitRows = await _db
          .from('units')
          .select('id')
          .eq('tenant_id', uid)
          .limit(1);
      if (unitRows.isEmpty) {
        if (mounted) setState(() => _loadingPhotos = false);
        return;
      }
      final unitId = unitRows.first['id'] as String;
      _unitId = unitId;
      await _fetchPhotos(unitId);
    } catch (_) {
      if (mounted) setState(() => _loadingPhotos = false);
    }
  }

  Future<void> _fetchPhotos(String unitId) async {
    try {
      final rows = await _db
          .from('photo_logs')
          .select()
          .eq('unit_id', unitId)
          .order('created_at', ascending: false);

      // Group by room name, keeping the most-recent created_at per room.
      final Map<String, _PhotoEntry> byRoom = {};
      DateTime? earliest;
      for (final r in rows) {
        final room = (r['room'] as String?) ?? 'General';
        final createdAt = r['created_at'] as String? ?? '';
        final parsed = DateTime.tryParse(createdAt);
        if (parsed != null && (earliest == null || parsed.isBefore(earliest))) {
          earliest = parsed;
        }
        final signedUrl = await signedPhotoLogUrl(
          _db,
          storagePath: r['storage_path'] as String?,
          publicUrl: r['public_url'] as String?,
        );
        if (!byRoom.containsKey(room)) {
          byRoom[room] = _PhotoEntry(
            room: room,
            date: _formatDate(createdAt),
            count: 1,
            latestUrl: signedUrl,
          );
        } else {
          byRoom[room] = _PhotoEntry(
            room: room,
            date: byRoom[room]!.date,
            count: byRoom[room]!.count + 1,
            latestUrl: byRoom[room]!.latestUrl,
          );
        }
      }

      if (mounted) {
        setState(() {
          _moveIn = byRoom.values.toList();
          _inspectionDate = earliest == null ? '' : _formatDate(earliest.toIso8601String());
          _loadingPhotos = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPhotos = false);
    }
  }

  String _formatDate(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = [
        'Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return '';
    }
  }

  void _showRoomDetail(BuildContext ctx, _PhotoEntry entry) {
    final colors = Theme.of(ctx).extension<ElevoColors>()!;
    final theme  = Theme.of(ctx);
    final messenger = ScaffoldMessenger.of(ctx);

    showModalBottomSheet(
      context: ctx,
      useRootNavigator: false,
      backgroundColor: colors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RoomDetailSheet(
        entry: entry,
        unitId: _unitId,
        colors: colors,
        theme: theme,
        messenger: messenger,
        onUploaded: () {
          if (_unitId != null) _fetchPhotos(_unitId!);
        },
      ),
    );
  }

  void _showAddPhotoSheet(BuildContext ctx) {
    final colors = Theme.of(ctx).extension<ElevoColors>()!;
    final theme  = Theme.of(ctx);
    final messenger = ScaffoldMessenger.of(ctx);

    showModalBottomSheet(
      context: ctx,
      useRootNavigator: false,
      backgroundColor: colors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddPhotoSheet(
        unitId: _unitId,
        colors: colors,
        theme: theme,
        messenger: messenger,
        onUploaded: () {
          if (_unitId != null) _fetchPhotos(_unitId!);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Log'),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Move-In'),
            Tab(text: 'Move-Out'),
          ],
        ),
      ),
      body: _loadingPhotos
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _MoveInTab(
                  entries: _moveIn,
                  inspectionDate: _inspectionDate,
                  colors: colors,
                  theme: theme,
                  onRoomTap: (e) => _showRoomDetail(context, e),
                  onAddTap: () => _showAddPhotoSheet(context),
                ),
                _EmptyMoveOutTab(colors: colors, theme: theme),
              ],
            ),
    );
  }
}

// ── Move-In tab ────────────────────────────────────────────────────────────────

class _MoveInTab extends StatelessWidget {
  final List<_PhotoEntry> entries;
  final String inspectionDate;
  final ElevoColors colors;
  final ThemeData theme;
  final ValueChanged<_PhotoEntry> onRoomTap;
  final VoidCallback onAddTap;

  const _MoveInTab({
    required this.entries,
    required this.inspectionDate,
    required this.colors,
    required this.theme,
    required this.onRoomTap,
    required this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          children: [
            // Header banner
            Container(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              decoration: BoxDecoration(
                color: colors.gold.withAlpha(15),
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(color: colors.gold.withAlpha(40)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.shieldCheck, color: colors.gold, size: 20),
                  const SizedBox(width: AppTheme.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Move-In Inspection',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(color: colors.goldInk),
                        ),
                        if (inspectionDate.isNotEmpty)
                          Text(inspectionDate,
                              style: theme.textTheme.labelSmall),
                        Text(
                          'These photos protect your security deposit.',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppTheme.spacingMd),
            Text(
              entries.isEmpty
                  ? 'No rooms yet. Tap the camera to add the first photo.'
                  : 'Tap a room to view or add photos',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppTheme.spacingSm),

            ...entries.map(
              (e) => _RoomCard(
                entry: e,
                colors: colors,
                theme: theme,
                onTap: () => onRoomTap(e),
              ),
            ),

            const SizedBox(height: 100),
          ],
        ),

        // FAB — ElevatedButton styled as FAB so the tap is trusted on web.
        Positioned(
          bottom: AppTheme.spacingLg,
          right: AppTheme.spacingMd,
          child: FloatingActionButton(
            heroTag: 'photo_log_fab',
            onPressed: onAddTap,
            child: const Icon(LucideIcons.camera),
          ),
        ),
      ],
    );
  }
}

// ── Room card — tappable ───────────────────────────────────────────────────────

class _RoomCard extends StatelessWidget {
  final _PhotoEntry entry;
  final ElevoColors colors;
  final ThemeData theme;
  final VoidCallback onTap;

  const _RoomCard({
    required this.entry,
    required this.colors,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingSm),
      child: Material(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: Container(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: colors.stone),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.gold.withAlpha(20),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Icon(LucideIcons.image, color: colors.gold, size: 20),
                ),
                const SizedBox(width: AppTheme.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.room,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: colors.ink)),
                      Text(
                        '${countPhrase(entry.count, 'photo', 'photos')} · ${entry.date}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.sage),
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, color: colors.sage, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Move-out empty state ───────────────────────────────────────────────────────

class _EmptyMoveOutTab extends StatelessWidget {
  final ElevoColors colors;
  final ThemeData theme;

  const _EmptyMoveOutTab({required this.colors, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.gold.withAlpha(15),
              ),
              child: Icon(LucideIcons.camera, color: colors.gold, size: 32),
            ),
            const SizedBox(height: AppTheme.spacingMd),
            Text(
              'No Move-Out Photos Yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingXs),
            Text(
              'Move-out photos will be captured here when you begin '
              'the move-out process with your landlord.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Room detail sheet ──────────────────────────────────────────────────────────
// Self-contained StatefulWidget so ElevatedButton.onPressed can call FilePicker
// directly without any Navigator.pop() beforehand — keeping the browser's
// trusted-event chain fully intact.

class _RoomDetailSheet extends StatefulWidget {
  final _PhotoEntry entry;
  final String? unitId;
  final ElevoColors colors;
  final ThemeData theme;
  final ScaffoldMessengerState messenger;
  final VoidCallback onUploaded;

  const _RoomDetailSheet({
    required this.entry,
    required this.unitId,
    required this.colors,
    required this.theme,
    required this.messenger,
    required this.onUploaded,
  });

  @override
  State<_RoomDetailSheet> createState() => _RoomDetailSheetState();
}

class _RoomDetailSheetState extends State<_RoomDetailSheet> {
  final _db = Supabase.instance.client;
  bool _uploading = false;

  Future<void> _pick() async {
    if (!kIsWeb) {
      try { HapticFeedback.lightImpact(); } catch (_) {}
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
        allowCompression: false,
      );
      if (result == null || result.files.isEmpty) return;
      if (widget.unitId == null) {
        widget.messenger.showSnackBar(const SnackBar(
            content: Text('No unit linked — contact your landlord.')));
        return;
      }
      setState(() => _uploading = true);
      int uploaded = 0;
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null) continue;
        final ts = DateTime.now().millisecondsSinceEpoch;
        final safeName = storageSafeFileName(file.name);
        final uid = _db.auth.currentUser?.id;
        if (uid == null) continue;
        final path = '$uid/${widget.unitId}/${ts}_$safeName';
        await _db.storage.from('photo-logs').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
        await _db.from('photo_logs').insert({
          'unit_id': widget.unitId,
          'room': widget.entry.room,
          'storage_path': path,
          'public_url': path,
        }).select();
        uploaded++;
      }
      setState(() => _uploading = false);
      widget.messenger.showSnackBar(SnackBar(
        content: Text(uploaded == 1
            ? '1 photo saved to your log.'
            : '${countPhrase(uploaded, 'photo', 'photos')} saved to your log.'),
        behavior: SnackBarBehavior.floating,
      ));
      widget.onUploaded();
    } on PlatformException catch (e) {
      setState(() => _uploading = false);
      widget.messenger.showSnackBar(
          SnackBar(content: Text('Could not open photos: ${e.message}')));
    } catch (e) {
      setState(() => _uploading = false);
      widget.messenger.showSnackBar(
          SnackBar(content: Text('Upload failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final theme  = widget.theme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
                decoration: BoxDecoration(
                  color: colors.stone,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(widget.entry.room, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppTheme.spacingXs),
            Text(
              '${countPhrase(widget.entry.count, 'photo', 'photos')} · ${widget.entry.date}',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.sage),
            ),
            const SizedBox(height: AppTheme.spacingLg),
            // Show the latest uploaded photo if available, otherwise placeholder.
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: colors.stone.withAlpha(40),
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(color: colors.stone),
              ),
              clipBehavior: Clip.antiAlias,
              child: widget.entry.latestUrl.isNotEmpty
                  ? Image.network(
                      widget.entry.latestUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => Center(
                        child: Icon(LucideIcons.image,
                            color: colors.sage, size: 32),
                      ),
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.image, color: colors.sage, size: 32),
                          const SizedBox(height: AppTheme.spacingXs),
                          Text('${countPhrase(widget.entry.count, 'photo', 'photos')} on file',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: colors.sage)),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: AppTheme.spacingLg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _uploading ? null : _pick,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.olive,
                  foregroundColor: colors.onOlive,
                  padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMd),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                ),
                icon: _uploading
                    ? SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: colors.onOlive))
                    : Icon(LucideIcons.imagePlus,
                        size: 18, color: colors.onOlive),
                label: Text(_uploading ? 'Uploading…' : 'Add More Photos',
                    style: TextStyle(color: colors.onOlive)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add photo sheet ────────────────────────────────────────────────────────────

class _AddPhotoSheet extends StatefulWidget {
  final String? unitId;
  final ElevoColors colors;
  final ThemeData theme;
  final ScaffoldMessengerState messenger;
  final VoidCallback onUploaded;

  const _AddPhotoSheet({
    required this.unitId,
    required this.colors,
    required this.theme,
    required this.messenger,
    required this.onUploaded,
  });

  @override
  State<_AddPhotoSheet> createState() => _AddPhotoSheetState();
}

class _AddPhotoSheetState extends State<_AddPhotoSheet> {
  final _db = Supabase.instance.client;
  bool _uploading = false;
  String _selectedRoom = 'Living Room';

  static const _rooms = [
    'Living Room', 'Kitchen', 'Master Bedroom', 'Bedroom',
    'Bathroom', 'Patio / Exterior', 'Garage', 'Other',
  ];

  Future<void> _pick() async {
    if (!kIsWeb) {
      try { HapticFeedback.lightImpact(); } catch (_) {}
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
        allowCompression: false,
      );
      if (result == null || result.files.isEmpty) return;
      if (widget.unitId == null) {
        widget.messenger.showSnackBar(const SnackBar(
            content: Text('No unit linked — contact your landlord.')));
        return;
      }
      setState(() => _uploading = true);
      int uploaded = 0;
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null) continue;
        final ts = DateTime.now().millisecondsSinceEpoch;
        final safeName = storageSafeFileName(file.name);
        final uid = _db.auth.currentUser?.id;
        if (uid == null) continue;
        final path = '$uid/${widget.unitId}/${ts}_$safeName';
        await _db.storage.from('photo-logs').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
        await _db.from('photo_logs').insert({
          'unit_id': widget.unitId,
          'room': _selectedRoom,
          'storage_path': path,
          'public_url': path,
        }).select();
        uploaded++;
      }
      setState(() => _uploading = false);
      widget.messenger.showSnackBar(SnackBar(
        content: Text(uploaded == 1
            ? '1 photo saved to your log.'
            : '${countPhrase(uploaded, 'photo', 'photos')} saved to your log.'),
        behavior: SnackBarBehavior.floating,
      ));
      widget.onUploaded();
    } on PlatformException catch (e) {
      setState(() => _uploading = false);
      widget.messenger.showSnackBar(
          SnackBar(content: Text('Could not open photos: ${e.message}')));
    } catch (e) {
      setState(() => _uploading = false);
      widget.messenger.showSnackBar(
          SnackBar(content: Text('Upload failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final theme  = widget.theme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
                decoration: BoxDecoration(
                  color: colors.stone,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Add Photos', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppTheme.spacingXs),
            Text(
              'Photos become part of your official move record and are visible to your landlord.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppTheme.spacingMd),
            DropdownButtonFormField<String>(
              value: _selectedRoom,
              decoration: const InputDecoration(labelText: 'Room'),
              items: _rooms
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedRoom = v);
              },
            ),
            const SizedBox(height: AppTheme.spacingMd),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _uploading ? null : _pick,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.olive,
                  foregroundColor: colors.onOlive,
                  padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMd),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                ),
                icon: _uploading
                    ? SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: colors.onOlive))
                    : Icon(LucideIcons.image,
                        size: 18, color: colors.onOlive),
                label: Text(_uploading ? 'Uploading…' : 'Choose from Photo Library',
                    style: TextStyle(color: colors.onOlive)),
              ),
            ),
            const SizedBox(height: AppTheme.spacingLg),
          ],
        ),
      ),
    );
  }
}

// ── Data model ─────────────────────────────────────────────────────────────────

class _PhotoEntry {
  final String room;
  final String date;
  final int count;
  final String latestUrl;

  const _PhotoEntry({
    required this.room,
    required this.date,
    required this.count,
    this.latestUrl = '',
  });
}
