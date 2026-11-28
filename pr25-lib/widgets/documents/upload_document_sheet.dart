import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/elevo_logic.dart';
import '../../models/document_model.dart';
import '../../models/property_model.dart';
import '../../theme/theme.dart';

/// Shows the upload document bottom sheet and returns a Future that resolves
/// when the sheet is dismissed — allowing callers to await and then reload.
Future<void> showUploadDocumentSheet(
  BuildContext context, {
  required bool isLandlord,
  String? preselectedUnitId,
}) async {
  // Capture scaffold messenger before the sheet discards context.
  final messenger = ScaffoldMessenger.of(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: false, // MUST be false — true breaks FilePicker on web
    backgroundColor: Theme.of(context).extension<ElevoColors>()?.canvas,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => UploadDocumentSheet(
      isLandlord: isLandlord,
      preselectedUnitId: preselectedUnitId,
      messenger: messenger,
    ),
  );
}

class UploadDocumentSheet extends StatefulWidget {
  final bool isLandlord;
  final String? preselectedUnitId;
  final ScaffoldMessengerState? messenger;

  const UploadDocumentSheet({
    super.key,
    required this.isLandlord,
    this.preselectedUnitId,
    this.messenger,
  });

  @override
  State<UploadDocumentSheet> createState() => _UploadDocumentSheetState();
}

class _UploadDocumentSheetState extends State<UploadDocumentSheet> {
  final _db = Supabase.instance.client;

  String  _docType          = 'Lease';
  String? _unitId;
  String? _counterpartyId;
  bool    _isUploading      = false;
  double  _uploadProgress   = 0;
  bool    _fileSelected     = false;
  String  _selectedFileName = '';
  int     _selectedFileSize = 0;
  List<Unit> _units = [];
  List<dynamic> _properties = [];
  PlatformFile? _pickedFile;

  @override
  void initState() {
    super.initState();
    _unitId = widget.preselectedUnitId;
    if (widget.isLandlord) {
      _loadUnits();
    } else {
      _loadTenantUnit();
    }
  }

  Future<void> _loadTenantUnit() async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return;

      // Primary lookup: units where tenant_id matches this user
      final unitRows = await _db
          .from('units')
          .select('id, landlord_id')
          .eq('tenant_id', uid)
          .limit(1);

      if (unitRows.isNotEmpty) {
        final unitId = unitRows.first['id'] as String?;
        final landlordId = unitRows.first['landlord_id'] as String?;
        if (unitId != null && mounted) {
          setState(() {
            _unitId = unitId;
            _counterpartyId = landlordId;
          });
          return;
        }
      }

      // Fallback: look up unit_id from the users table (covers manually-created accounts)
      final userRow = await _db
          .from('users')
          .select('unit_id')
          .eq('id', uid)
          .maybeSingle();
      final unitId = userRow?['unit_id'] as String?;
      if (unitId != null && mounted) {
        setState(() => _unitId = unitId);
      }
    } catch (e) {
      debugPrint('[UploadSheet] _loadTenantUnit error: $e');
    }
  }

  Future<void> _loadUnits() async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return;
      final propRows = await _db
          .from('properties')
          .select('id, name, address, units(id, unit_number, property_id, landlord_id, status, rent_amount, created_at)')
          .eq('landlord_id', uid);

      final props = <dynamic>[];
      final units = <Unit>[];
      for (final p in propRows) {
        props.add(p);
        final uRows = (p['units'] as List<dynamic>?) ?? [];
        for (final u in uRows) {
          units.add(Unit(
            id: u['id'] as String,
            propertyId: u['property_id'] as String,
            landlordId: (u['landlord_id'] as String?) ?? uid,
            unitNumber: u['unit_number'] as String,
            rentAmount: ((u['rent_amount'] as num?) ?? 0).toDouble(),
            status: (u['status'] as String?) ?? 'vacant',
            createdAt: DateTime.parse(u['created_at'] as String),
          ));
        }
      }
      if (mounted) {
        setState(() {
          _properties = props;
          _units = units;
          if (_unitId == null && units.isNotEmpty) _unitId = units.first.id;
        });
      }
    } catch (e) {
      debugPrint('[UploadSheet] _loadUnits error: $e');
    }
  }

  String _unitLabel(Unit u) {
    final prop = _properties.cast<dynamic>().firstWhere(
      (p) => p['id'] == u.propertyId,
      orElse: () => null,
    );
    if (prop == null) return 'Unit ${u.unitNumber}';
    return '${prop['name']} \u2014 Unit ${u.unitNumber}';
  }

  // ---------------------------------------------------------------------------
  // File picker
  // Core fix: call FilePicker.platform.pickFiles() directly from an
  // ElevatedButton.onPressed callback. This keeps it in a genuine user-gesture
  // event frame — the only way the browser allows opening a file input.
  // Never wrap in GestureDetector or InkWell inside a ModalBottomSheet;
  // those intercept the gesture and sever the event-from-user-interaction
  // chain that browsers require to trigger <input type="file">.
  // ---------------------------------------------------------------------------
  Future<void> _pickFile() async {
    if (!kIsWeb) {
      try {
        HapticFeedback.lightImpact();
      } catch (_) {}
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg'],
        allowMultiple: false,
        // withData: true is required on web so FilePicker can hand back bytes.
        // On mobile the path is sufficient, but true is safe cross-platform.
        withData: true,
        allowCompression: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final nameLower = file.name.toLowerCase();
      if (nameLower.startsWith('http://') || nameLower.startsWith('https://')) {
        (widget.messenger ?? ScaffoldMessenger.of(context)).showSnackBar(
          const SnackBar(
            content: Text('Please select a file from your device, not a URL.'),
          ),
        );
        return;
      }

      if (mounted) {
        setState(() {
          _pickedFile       = file;
          _fileSelected     = true;
          _selectedFileName = file.name;
          _selectedFileSize = file.size;
        });
      }
    } on PlatformException catch (e) {
      (widget.messenger ?? ScaffoldMessenger.of(context)).showSnackBar(
        SnackBar(content: Text('File picker error: ${e.message}')),
      );
    } catch (_) {
      (widget.messenger ?? ScaffoldMessenger.of(context)).showSnackBar(
        const SnackBar(
          content: Text('Could not open file browser. Please try again.'),
        ),
      );
    }
  }

  void _clearFile() => setState(() {
        _fileSelected     = false;
        _selectedFileName = '';
        _selectedFileSize = 0;
      });

  // ---------------------------------------------------------------------------
  // Upload — real Supabase Storage upload + documents table insert
  // ---------------------------------------------------------------------------
  Future<void> _upload() async {
    if (!_fileSelected || _pickedFile == null) {
      (widget.messenger ?? ScaffoldMessenger.of(context)).showSnackBar(
        const SnackBar(content: Text('Please choose a file first.')),
      );
      return;
    }
    if (!kIsWeb) {
      try { HapticFeedback.lightImpact(); } catch (_) {}
    }
    setState(() { _isUploading = true; _uploadProgress = 0; });

    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) throw Exception('Not signed in');

      // Show fake progress while uploading
      final file = _pickedFile!;
      final bytes = file.bytes;
      if (bytes == null) throw Exception('Could not read file bytes');

      // Animate to 50% while waiting for upload
      setState(() => _uploadProgress = 0.3);

      final unitSegment = _unitId ?? 'unassigned';
      final path = '$uid/$unitSegment/${DateTime.now().millisecondsSinceEpoch}_${storageSafeFileName(file.name)}';
      await _db.storage.from('documents').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(upsert: false),
      );

      setState(() => _uploadProgress = 0.8);

      // Store the path. The documents screen signs it when the file is opened.
      await _db.from('documents').insert(documentInsertPayload(
        uid: uid,
        isLandlord: widget.isLandlord,
        fileName: file.name,
        fileUrl: path,
        docType: _docType,
        fileSizeBytes: bytes.length,
        unitId: _unitId,
        counterpartyId: _counterpartyId,
      ));

      setState(() => _uploadProgress = 1.0);

      if (mounted) {
        final name = _selectedFileName;
        final messenger = widget.messenger ?? ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text('$name uploaded successfully.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('[UploadSheet] _upload error: $e');
      if (mounted) {
        setState(() { _isUploading = false; _uploadProgress = 0; });
        (widget.messenger ?? ScaffoldMessenger.of(context)).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            duration: const Duration(seconds: 10),
          ),
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

    final dropdownDecoration = InputDecoration(
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest,
      labelStyle: theme.textTheme.bodySmall?.copyWith(color: colors.sage),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        borderSide: BorderSide(color: colors.stone),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        borderSide: BorderSide(color: colors.stone),
      ),
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left:   AppTheme.spacingMd,
          right:  AppTheme.spacingMd,
          top:    AppTheme.spacingLg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppTheme.spacingLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
                decoration: BoxDecoration(
                  color: colors.stone,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Text('Upload Document', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppTheme.spacingMd),

            // ── Document type dropdown ──
            DropdownButtonFormField<String>(
              value: _docType,
              dropdownColor: theme.colorScheme.surface,
              decoration: dropdownDecoration.copyWith(
                labelText: 'Document Type',
                prefixIcon: Icon(LucideIcons.tag, color: colors.sage, size: 18),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
              items: Document.docTypes
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(
                          t,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurface),
                        ),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _docType = v ?? 'Lease'),
            ),
            const SizedBox(height: AppTheme.spacingMd),

            // ── Unit selector (landlord only) ──
            if (widget.isLandlord) ...[
              DropdownButtonFormField<String>(
                value: _unitId,
                dropdownColor: theme.colorScheme.surface,
                decoration: dropdownDecoration.copyWith(
                  labelText: 'Unit',
                  prefixIcon:
                      Icon(LucideIcons.home, color: colors.sage, size: 18),
                ),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurface),
                items: _units
                    .map((u) => DropdownMenuItem(
                          value: u.id,
                          child: Text(
                            _unitLabel(u),
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: theme.colorScheme.onSurface),
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _unitId = v),
              ),
              const SizedBox(height: AppTheme.spacingMd),
            ],

            // ── Selected file display (shown after picking) ──
            if (_fileSelected) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                decoration: BoxDecoration(
                  color: colors.gold.withAlpha(15),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(color: colors.gold, width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.fileCheck, color: colors.gold, size: 22),
                    const SizedBox(width: AppTheme.spacingSm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedFileName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_selectedFileSize > 0)
                            Text(
                              _formatSize(_selectedFileSize),
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: colors.sage),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(LucideIcons.x, size: 18, color: colors.sage),
                      onPressed: _clearFile,
                      tooltip: 'Remove file',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),
            ],

            // ── Choose File button — only visible when no file selected ──
            // This is the ONLY tap target for the picker. Using ElevatedButton
            // (not GestureDetector / InkWell) is critical: the browser requires
            // the file-input trigger to originate from a direct button press
            // event. Any gesture wrapper severs that chain.
            if (!_fileSelected) ...[
              SizedBox(
                width: double.infinity,
                height: 100,
                child: ElevatedButton(
                  onPressed: _pickFile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    foregroundColor: theme.colorScheme.onSurface,
                    elevation: 0,
                    side: BorderSide(color: colors.stone),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.uploadCloud,
                          color: colors.gold, size: 32),
                      const SizedBox(height: AppTheme.spacingSm),
                      Text(
                        'Tap to choose a file',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'PDF, Word, JPG or PNG',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: colors.sage),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),
            ],

            // ── Storage note ──
            Row(
              children: [
                Icon(LucideIcons.shieldCheck, size: 14, color: colors.sage),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Files are stored securely. Download links expire after '
                    '1 hour for security.',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: colors.sage),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingMd),

            // ── Upload progress bar ──
            if (_isUploading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _uploadProgress,
                  backgroundColor: colors.stone,
                  valueColor: AlwaysStoppedAnimation(colors.gold),
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: AppTheme.spacingSm),
              Center(
                child: Text(
                  '${(_uploadProgress * 100).toInt()}% uploaded',
                  style:
                      theme.textTheme.labelSmall?.copyWith(color: colors.goldInk),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),
            ],

            // ── Upload button ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isUploading ? null : _upload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.olive,
                  foregroundColor: colors.onOlive,
                  disabledBackgroundColor: colors.olive.withAlpha(80),
                  padding: const EdgeInsets.symmetric(
                      vertical: AppTheme.spacingMd),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                ),
                icon: _isUploading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onOlive,
                        ),
                      )
                    : Icon(Icons.upload_rounded,
                        size: 18, color: colors.onOlive),
                label: Text(
                  _isUploading ? 'Uploading\u2026' : 'Upload Document',
                  style: TextStyle(color: colors.onOlive),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }
}
