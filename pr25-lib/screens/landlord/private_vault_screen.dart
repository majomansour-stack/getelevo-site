import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/elevo_logic.dart';
import '../../providers/dashboard_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/common/empty_state.dart';
import 'package:provider/provider.dart';

// ── Data models (local to this screen until Supabase is wired) ────────────────

enum VaultItemType { note, document, photo, backgroundCheck }

class VaultItem {
  final String id;
  final VaultItemType type;
  final String title;          // maps to vault_items.name column
  final String? note;          // maps to vault_items.note column
  final String? fileUrl;       // docs / photos
  final String? unitId;
  final String? unitLabel;
  final DateTime createdAt;

  const VaultItem({
    required this.id,
    required this.type,
    required this.title,
    this.note,
    this.fileUrl,
    this.unitId,
    this.unitLabel,
    required this.createdAt,
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class PrivateVaultScreen extends StatefulWidget {
  const PrivateVaultScreen({super.key});

  @override
  State<PrivateVaultScreen> createState() => _PrivateVaultScreenState();
}

class _PrivateVaultScreenState extends State<PrivateVaultScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final List<VaultItem> _items = [];
  bool _loadingItems = true;
  VaultItemType _filter = VaultItemType.note;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        setState(() {
          _filter = VaultItemType.values[_tabs.index];
        });
      }
    });
    _loadVaultItems();
  }

  Future<void> _loadVaultItems() async {
    try {
      final db  = Supabase.instance.client;
      final uid = db.auth.currentUser?.id;
      if (uid == null) { if (mounted) setState(() => _loadingItems = false); return; }
      final rows = await db
          .from('vault_items')
          .select()
          .eq('landlord_id', uid)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(rows.map<VaultItem>((r) => VaultItem(
                id: r['id'] as String,
                type: VaultItemType.values.firstWhere(
                  (t) => t.name == (r['type'] as String? ?? 'note'),
                  orElse: () => VaultItemType.note,
                ),
                title: (r['title'] as String?) ?? '',
                note: (r['content'] as String?) ?? (r['note'] as String?),
                fileUrl: r['file_url'] as String?,
                createdAt: DateTime.parse(r['created_at'] as String),
              )));
        _loadingItems = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<VaultItem> get _filtered =>
      _items.where((i) => i.type == _filter).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  void _showAddSheet() {
    HapticFeedback.lightImpact();
    final properties = context.read<DashboardProvider>().properties;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddVaultItemSheet(
        type: _filter,
        properties: properties,
        onSave: (_) => _loadVaultItems(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            Icon(LucideIcons.lock, color: colors.gold, size: 18),
            const SizedBox(width: 8),
            const Text('Private Vault'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppTheme.spacingSm),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colors.gold.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.gold.withAlpha(60)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.eyeOff, color: colors.gold, size: 12),
                  const SizedBox(width: 4),
                  Text('Landlord Only', style: TextStyle(color: colors.goldInk, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Notes'),
            Tab(text: 'Documents'),
            Tab(text: 'Photos'),
            Tab(text: 'Screening'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        child: const Icon(LucideIcons.plus),
      ),
      body: _loadingItems
          ? const Center(child: CircularProgressIndicator())
          : _filtered.isEmpty
          ? EmptyState(
              icon: _typeIcon(_filter),
              message: _emptyMessage(_filter),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spacingSm),
              itemBuilder: (context, i) => _VaultCard(
                item: _filtered[i],
                onDelete: () async {
                  final item = _filtered[i];
                  setState(() => _items.remove(item));
                  try {
                    await Supabase.instance.client
                        .from('vault_items')
                        .delete()
                        .eq('id', item.id);
                  } catch (_) { /* best-effort */ }
                },
              ),
            ),
    );
  }

  IconData _typeIcon(VaultItemType t) {
    switch (t) {
      case VaultItemType.note:            return LucideIcons.stickyNote;
      case VaultItemType.document:        return LucideIcons.fileText;
      case VaultItemType.photo:           return LucideIcons.image;
      case VaultItemType.backgroundCheck: return LucideIcons.shieldCheck;
    }
  }

  String _emptyMessage(VaultItemType t) {
    switch (t) {
      case VaultItemType.note:            return 'No private notes yet.\nTap + to add a note.';
      case VaultItemType.document:        return 'No private documents yet.\nTap + to upload a document.';
      case VaultItemType.photo:           return 'No private photos yet.\nTap + to upload a photo.';
      case VaultItemType.backgroundCheck: return 'No screening records yet.\nTap + to add a background check result.';
    }
  }
}

// ── Vault Card ────────────────────────────────────────────────────────────────

class _VaultCard extends StatelessWidget {
  final VaultItem item;
  final Future<void> Function() onDelete;

  const _VaultCard({required this.item, required this.onDelete});

  void _openDetail(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    showModalBottomSheet(
      context: context,
      useRootNavigator: false,
      isScrollControlled: true,
      backgroundColor: colors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
      ),
      builder: (_) {
        final typeColor = _typeColor(item.type, colors);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingMd, AppTheme.spacingSm,
                AppTheme.spacingMd, AppTheme.spacingLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
                    decoration: BoxDecoration(
                      color: colors.stone,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Type chip + title (navy bold)
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: typeColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(_typeIcon(item.type), color: typeColor, size: 18),
                    ),
                    const SizedBox(width: AppTheme.spacingSm),
                    Expanded(
                      child: Text(
                        item.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.midnight,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.unitLabel != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(LucideIcons.mapPin, color: colors.sage, size: 13),
                      const SizedBox(width: 4),
                      Text(item.unitLabel!,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: colors.sage)),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                // Date in taupe/sage
                Text(
                  _formatDate(item.createdAt),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: colors.taupe),
                ),
                // Note text — charcoal, scrollable
                if (item.note != null && item.note!.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.spacingMd),
                  Divider(color: colors.stone),
                  const SizedBox(height: AppTheme.spacingMd),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      child: Text(
                        item.note!,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: colors.ink, height: 1.6),
                      ),
                    ),
                  ),
                ],
                // Open File — gold button for any item with a fileUrl
                if (item.fileUrl != null && item.fileUrl!.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.spacingMd),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: Icon(LucideIcons.externalLink, size: 16,
                          color: colors.shade),
                      label: Text('Open File',
                          style: TextStyle(color: colors.shade)),
                      style: AppTheme.goldFillButton(colors, theme.textTheme),
                      onPressed: () async {
                        try {
                          final db = Supabase.instance.client;
                          final path = storageObjectPath(item.fileUrl, 'private-vault');
                          if (path == null) {
                            throw Exception('No file path');
                          }
                          final signedUrl = await db.storage
                              .from('private-vault')
                              .createSignedUrl(path, 3600);
                          final uri = Uri.parse(signedUrl);
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Could not open file: $e')),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ],
                const SizedBox(height: AppTheme.spacingLg),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    final isPhoto = item.type == VaultItemType.photo && item.fileUrl != null && item.fileUrl!.isNotEmpty;
    final hasContent = item.note != null && item.note!.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDetail(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: Container(
          decoration: BoxDecoration(
            color: colors.charcoal,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border(
              left: BorderSide(color: _typeColor(item.type, colors), width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo preview
              if (isPhoto)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusMedium)),
                  child: FutureBuilder<String>(
                    future: () async {
                      final path = storageObjectPath(item.fileUrl, 'private-vault');
                      if (path == null) return '';
                      return Supabase.instance.client.storage
                          .from('private-vault')
                          .createSignedUrl(path, 3600);
                    }(),
                    builder: (context, snapshot) {
                      final url = snapshot.data ?? '';
                      if (url.isEmpty) {
                        return Container(
                          height: 100,
                          color: colors.midnight,
                          child: Center(child: Icon(LucideIcons.image, color: colors.taupe)),
                        );
                      }
                      return Image.network(
                        url,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 100,
                          color: colors.midnight,
                          child: Center(child: Icon(LucideIcons.image, color: colors.taupe)),
                        ),
                      );
                    },
                  ),
                ),

              Padding(
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: _typeColor(item.type, colors).withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(_typeIcon(item.type), color: _typeColor(item.type, colors), size: 16),
                        ),
                        const SizedBox(width: AppTheme.spacingSm),
                        Expanded(
                          child: Text(item.title, style: theme.textTheme.titleSmall?.copyWith(color: colors.ivory)),
                        ),
                        // "Tap to read" hint for notes/screening
                        if (hasContent)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(LucideIcons.chevronRight, color: colors.taupe, size: 14),
                          ),
                        PopupMenuButton<String>(
                          color: colors.card,
                          icon: Icon(LucideIcons.moreVertical, color: colors.taupe, size: 18),
                          onSelected: (v) {
                            if (v == 'delete') {
                              HapticFeedback.lightImpact();
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Item'),
                                  content: const Text('This will permanently remove this vault item.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                    TextButton(
                                      onPressed: () { Navigator.pop(ctx); onDelete(); },
                                      child: Text('Delete', style: TextStyle(color: colors.urgentRed)),
                                    ),
                                  ],
                                ),
                              );
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ],
                    ),

                    // Unit label
                    if (item.unitLabel != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(LucideIcons.mapPin, color: colors.taupe, size: 12),
                          const SizedBox(width: 4),
                          Text(item.unitLabel!, style: theme.textTheme.labelSmall),
                        ],
                      ),
                    ],

                    // Note preview (truncated — tap to read full)
                    if (hasContent) ...[
                      const SizedBox(height: AppTheme.spacingSm),
                      Text(
                        item.note!,
                        style: theme.textTheme.bodySmall?.copyWith(color: colors.ivory.withAlpha(180)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    const SizedBox(height: AppTheme.spacingSm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDate(item.createdAt),
                          style: theme.textTheme.labelSmall,
                        ),
                        if (hasContent)
                          Text(
                            'Tap to read',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: colors.goldInk),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _typeColor(VaultItemType t, ElevoColors c) {
    switch (t) {
      case VaultItemType.note:            return c.gold;
      case VaultItemType.document:        return c.warningAmber;
      case VaultItemType.photo:           return c.taupe;
      case VaultItemType.backgroundCheck: return c.successGreen;
    }
  }

  IconData _typeIcon(VaultItemType t) {
    switch (t) {
      case VaultItemType.note:            return LucideIcons.stickyNote;
      case VaultItemType.document:        return LucideIcons.fileText;
      case VaultItemType.photo:           return LucideIcons.image;
      case VaultItemType.backgroundCheck: return LucideIcons.shieldCheck;
    }
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }
}

// ── Add Vault Item Sheet ──────────────────────────────────────────────────────

class _AddVaultItemSheet extends StatefulWidget {
  final VaultItemType type;
  final List<dynamic> properties;
  final ValueChanged<VaultItem> onSave;

  const _AddVaultItemSheet({required this.type, required this.properties, required this.onSave});

  @override
  State<_AddVaultItemSheet> createState() => _AddVaultItemSheetState();
}

class _AddVaultItemSheetState extends State<_AddVaultItemSheet> {
  final _titleCtrl   = TextEditingController();
  final _contentCtrl = TextEditingController();
  String? _selectedUnitId;
  bool _isSaving = false;
  PlatformFile? _pickedFile;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final isPhoto = widget.type == VaultItemType.photo;
    final result = await FilePicker.platform.pickFiles(
      type: isPhoto ? FileType.image : FileType.custom,
      allowedExtensions: isPhoto ? null : ['pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty && mounted) {
      setState(() => _pickedFile = result.files.first);
    }
  }

  String get _typeLabel {
    switch (widget.type) {
      case VaultItemType.note:            return 'Note';
      case VaultItemType.document:        return 'Document';
      case VaultItemType.photo:           return 'Photo';
      case VaultItemType.backgroundCheck: return 'Screening Record';
    }
  }

  List<DropdownMenuItem<String>> get _unitItems {
    final items = <DropdownMenuItem<String>>[];
    for (final p in widget.properties) {
      for (final u in p.units) {
        items.add(DropdownMenuItem(
          value: u.id as String,
          child: Text(
            '${p.name} #${u.unitNumber}',
            style: const TextStyle(color: Color(0xFFF7F4EE), fontSize: 15),
          ),
        ));
      }
    }
    return items;
  }

  String? _unitLabel(String? unitId) {
    if (unitId == null) return null;
    for (final p in widget.properties) {
      for (final u in p.units) {
        if (u.id == unitId) return '#${u.unitNumber} ${p.name}';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppTheme.spacingMd,
          right: AppTheme.spacingMd,
          top: AppTheme.spacingLg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppTheme.spacingLg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
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
                  Icon(LucideIcons.lock, color: colors.gold, size: 18),
                  const SizedBox(width: 8),
                  Text('Add Private $_typeLabel', style: theme.textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Visible to you only — never shared with tenants.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppTheme.spacingLg),

              TextFormField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  labelText: 'Title *',
                  prefixIcon: Icon(LucideIcons.pencil, color: colors.taupe, size: 18),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),

              DropdownButtonFormField<String>(
                value: _selectedUnitId,
                decoration: InputDecoration(
                  labelText: 'Link to Unit (optional)',
                  prefixIcon: Icon(LucideIcons.home, color: colors.taupe, size: 18),
                ),
                dropdownColor: colors.card,
                items: _unitItems,
                onChanged: (v) => setState(() => _selectedUnitId = v),
              ),
              const SizedBox(height: AppTheme.spacingMd),

              if (widget.type == VaultItemType.note ||
                  widget.type == VaultItemType.backgroundCheck) ...[
                TextFormField(
                  controller: _contentCtrl,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: widget.type == VaultItemType.backgroundCheck
                        ? 'Screening notes / results'
                        : 'Note content',
                    alignLabelWithHint: true,
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(bottom: 60),
                      child: Icon(LucideIcons.fileText, color: colors.taupe, size: 18),
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingMd),
                // Optional document attachment for notes — real FilePicker
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _pickFile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.charcoal,
                      foregroundColor: colors.gold,
                      elevation: 0,
                      side: BorderSide(
                        color: _pickedFile != null
                            ? colors.gold
                            : colors.gold.withAlpha(80),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _pickedFile != null
                              ? LucideIcons.checkCircle
                              : LucideIcons.paperclip,
                          color: colors.gold,
                          size: 18,
                        ),
                        const SizedBox(width: AppTheme.spacingSm),
                        Flexible(
                          child: Text(
                            _pickedFile != null
                                ? _pickedFile!.name
                                : 'Attach Document (optional)',
                            style: TextStyle(color: colors.gold, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingMd),
              ],

              if (widget.type == VaultItemType.document ||
                  widget.type == VaultItemType.photo) ...[
                SizedBox(
                  width: double.infinity,
                  height: 80,
                  child: ElevatedButton(
                    onPressed: _pickFile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.charcoal,
                      foregroundColor: colors.gold,
                      elevation: 0,
                      side: BorderSide(
                        color: _pickedFile != null
                            ? colors.gold
                            : colors.gold.withAlpha(80),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusMedium),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _pickedFile != null
                              ? LucideIcons.checkCircle
                              : (widget.type == VaultItemType.photo
                                  ? LucideIcons.camera
                                  : LucideIcons.upload),
                          color: colors.gold,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _pickedFile != null
                              ? _pickedFile!.name
                              : (widget.type == VaultItemType.photo
                                  ? 'Tap to select photo'
                                  : 'Tap to upload document'),
                          style: TextStyle(color: colors.taupe, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingMd),
              ],

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          if (_titleCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Please enter a title')),
                            );
                            return;
                          }
                          final needsFile =
                              widget.type == VaultItemType.document ||
                                  widget.type == VaultItemType.photo;
                          if (needsFile && _pickedFile == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Please select a file to upload.')),
                            );
                            return;
                          }
                          HapticFeedback.lightImpact();
                          setState(() => _isSaving = true);
                          try {
                            final db = Supabase.instance.client;
                            final uid = db.auth.currentUser?.id;
                            if (uid == null) throw Exception('Not signed in');

                            String? fileUrl;
                            if (_pickedFile != null) {
                              final bytes = _pickedFile!.bytes;
                              if (bytes == null) {
                                throw Exception('Could not read file bytes');
                              }
                              final path =
                                  '$uid/${DateTime.now().millisecondsSinceEpoch}_${storageSafeFileName(_pickedFile!.name)}';
                              await db.storage
                                  .from('private-vault')
                                  .uploadBinary(
                                    path,
                                    bytes,
                                    fileOptions:
                                        const FileOptions(upsert: false),
                                  );
                              fileUrl = path;
                            }

                            final row = await db
                                .from('vault_items')
                                .insert({
                                  'landlord_id': uid,
                                  'type': widget.type.name,
                                  'title': _titleCtrl.text.trim(),
                                  // Live column is `note`. `content` is not on this table.
                                  'note': _contentCtrl.text.trim().isEmpty
                                      ? null
                                      : _contentCtrl.text.trim(),
                                  'file_url': fileUrl,
                                })
                                .select()
                                .single();

                            final item = VaultItem(
                              id: row['id'] as String,
                              type: widget.type,
                              title: _titleCtrl.text.trim(),
                              note: _contentCtrl.text.trim().isEmpty
                                      ? null
                                      : _contentCtrl.text.trim(),
                              fileUrl: fileUrl,
                              unitId: _selectedUnitId,
                              unitLabel: _unitLabel(_selectedUnitId),
                              createdAt: DateTime.now(),
                            );
                            if (mounted) {
                              widget.onSave(item);
                              Navigator.of(context).pop();
                            }
                          } catch (e) {
                            if (mounted) {
                              setState(() => _isSaving = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Save failed: ${e.toString()}')),
                              );
                            }
                          }
                        },
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(LucideIcons.save,
                          size: 18, color: Colors.white),
                  label: Text(_isSaving ? 'Saving\u2026' : 'Save to Vault'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
