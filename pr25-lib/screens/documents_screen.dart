import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/elevo_logic.dart';
import '../models/document_model.dart';
import '../theme/theme.dart';
import '../widgets/common/status_chip.dart';
import '../widgets/common/empty_state.dart';
import '../widgets/documents/upload_document_sheet.dart';



class DocumentsScreen extends StatefulWidget {
  final bool isLandlord;

  const DocumentsScreen({super.key, required this.isLandlord});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  String _filter = 'All';
  final _db = Supabase.instance.client;
  List<Document> _docs = [];
  bool _loadingDocs = true;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) { setState(() => _loadingDocs = false); return; }

      // Tenants also need the landlord's files for their unit. Those rows
      // have an empty tenant_id, so the owner/landlord/tenant filter hid
      // them. Row level security already limits a tenant to their own files
      // and the landlord's files for their current tenancy.
      final query = _db.from('documents').select();
      final rows = await (widget.isLandlord
              ? query.or(documentsOrFilter(uid))
              : query)
          .order('created_at', ascending: false);

      final docs = rows.map<Document>((r) {
        final storageUrl = (r['file_url'] as String?) ?? '';
        final ownerCol = (r['owner_id'] as String?) ??
            (r['landlord_id'] as String?) ??
            (r['tenant_id'] as String?) ??
            '';
        return Document(
          id: r['id'] as String,
          unitId: (r['unit_id'] as String?) ?? '',
          propertyId: '',
          landlordId: ownerCol,
          uploadedBy: ownerCol,
          fileName: documentFileName(r),
          docType: documentDocType(r),
          fileUrl: storageUrl,
          fileSize: documentFileSize(r),
          createdAt: DateTime.parse(r['created_at'] as String),
        );
      }).toList();

      setState(() {
        _docs = docs;
        _loadingDocs = false;
      });
    } catch (_) {
      setState(() => _loadingDocs = false);
    }
  }

  Future<void> _deleteDocument(Document d) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete document'),
        content: Text('Delete ${d.fileName}? The tenant will no longer see this file.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final path = storageObjectPath(d.fileUrl, 'documents');
      if (path != null && path.isNotEmpty) {
        await _db.storage.from('documents').remove([path]);
      }
      await _db.from('documents').delete().eq('id', d.id);
      if (!mounted) return;
      setState(() => _docs.removeWhere((doc) => doc.id == d.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Download logic
  // ---------------------------------------------------------------------------

  /// Generates a fresh 1-hour signed URL from Supabase Storage and opens it
  /// in the browser / device viewer using url_launcher.
  Future<void> _downloadDocument(Document d) async {
    if (d.fileUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file available for this document.')),
      );
      return;
    }

    try {
      // New rows store the path. Older rows stored a public or signed URL.
      final path = storageObjectPath(d.fileUrl, 'documents');
      if (path == null) {
        throw Exception('No file path');
      }

      final signedUrl = await _db.storage
          .from('documents')
          .createSignedUrl(path, 3600); // 1-hour expiry

      final launchUri = Uri.parse(signedUrl);
      if (!await launchUrl(launchUri, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open file.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Open failed: $e')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    if (_loadingDocs) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final docs   = _filter == 'All'
        ? _docs
        : _docs.where((d) => d.docType == _filter).toList();
    final fmt = DateFormat('MMM d, y');

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => context.pop(),
        ),
        title: const Text('Documents'),
      ),

      // ── Clean circle FAB: navy bg, white + icon ──
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await showUploadDocumentSheet(
            context,
            isLandlord: widget.isLandlord,
          );
          _loadDocuments();
        },
        child: const Icon(Icons.add, size: 28),
      ),

      body: Column(
        children: [
          // ── Filter chips row ──
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMd,
                vertical: AppTheme.spacingSm,
              ),
              children: ['All', ...Document.docTypes].map((t) {
                final selected = t == _filter;
                return Padding(
                  padding: const EdgeInsets.only(right: AppTheme.spacingSm),
                  child: ChoiceChip(
                    label: Text(t),
                    selected: selected,
                    selectedColor: colors.olive,
                    backgroundColor: colors.card,
                    side: BorderSide(
                      color: selected ? colors.olive : colors.stone,
                    ),
                    labelStyle: theme.textTheme.labelMedium?.copyWith(
                      color: selected ? colors.onOlive : colors.ink,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    onSelected: (_) => setState(() => _filter = t),
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Document list ──
          Expanded(
            child: docs.isEmpty
                ? const EmptyState(
                    icon: LucideIcons.fileText,
                    message: 'No documents found',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppTheme.spacingMd),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppTheme.spacingSm),
                    itemBuilder: (context, i) {
                      final d = docs[i];
                      return Container(
                        padding: const EdgeInsets.all(AppTheme.spacingMd),
                        decoration: BoxDecoration(
                          color: colors.card,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusMedium),
                          border: Border.all(color: colors.stone),
                          boxShadow: [
                            BoxShadow(
                              color: colors.midnight.withAlpha(10),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // File icon badge
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: colors.gold.withAlpha(25),
                                borderRadius: BorderRadius.circular(
                                    AppTheme.radiusSmall),
                              ),
                              child: Icon(
                                LucideIcons.fileText,
                                color: colors.gold,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: AppTheme.spacingMd),

                            // File name + meta
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d.fileName,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colors.ink,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      StatusChip(label: d.docType),
                                      const SizedBox(width: AppTheme.spacingSm),
                                      Text(
                                        d.fileSizeFormatted,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(color: colors.sage),
                                      ),
                                      const SizedBox(width: AppTheme.spacingSm),
                                      Flexible(
                                        child: Text(
                                          fmt.format(d.createdAt.toLocal()),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(color: colors.sage),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Optional signature status chip
                            if (d.signatureStatus != null) ...[
                              const SizedBox(width: AppTheme.spacingSm),
                              StatusChip(label: d.signatureStatus!),
                            ],

                            // ── Download button ──
                            IconButton(
                              tooltip: 'Download',
                              icon: Icon(
                                LucideIcons.download,
                                color: colors.midnight,
                                size: 20,
                              ),
                              onPressed: () => _downloadDocument(d),
                            ),
                            if (widget.isLandlord)
                              IconButton(
                                tooltip: 'Delete',
                                icon: Icon(
                                  LucideIcons.trash2,
                                  color: colors.midnight,
                                  size: 20,
                                ),
                                onPressed: () => _deleteDocument(d),
                              ),
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
}
