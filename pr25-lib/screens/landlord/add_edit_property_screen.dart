import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/elevo_logic.dart';
import '../../core/billing_rules.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/landlord_plan_gate.dart';
import '../../theme/theme.dart';

class AddEditPropertyScreen extends StatefulWidget {
  /// Pass an existing property id to edit; null = add new property.
  final String? propertyId;

  const AddEditPropertyScreen({super.key, this.propertyId});

  @override
  State<AddEditPropertyScreen> createState() => _AddEditPropertyScreenState();
}

class _AddEditPropertyScreenState extends State<AddEditPropertyScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _nameCtrl      = TextEditingController();
  final _addressCtrl   = TextEditingController();
  final _address2Ctrl  = TextEditingController();
  final _zipCtrl       = TextEditingController();
  final _cityCtrl      = TextEditingController(text: 'Phoenix');
  final _rentCtrl      = TextEditingController();
  final _unitCtrl      = TextEditingController();

  final _db = Supabase.instance.client;
  bool _isSaving = false;
  bool _hasPhoto = false;
  String _state = 'AZ';
  String _propertyType = '';
  String? _existingImageUrl;
  Uint8List? _photoBytes;
  String? _photoName;
  bool _removePhoto = false;

  bool get _isEditing => widget.propertyId != null;

  List<String> get _propertyTypeChoices {
    final choices = <String>['', ...propertyTypeOptions];
    if (_propertyType.isNotEmpty && !choices.contains(_propertyType)) {
      choices.add(_propertyType);
    }
    return choices;
  }

  @override
  void initState() {
    super.initState();
    // Auto-populate the hidden name field from address so the DB name column
    // always has a useful value without surfacing a redundant field to the user.
    _addressCtrl.addListener(() {
      _nameCtrl.text = _buildAutoName();
    });
    _address2Ctrl.addListener(() {
      _nameCtrl.text = _buildAutoName();
    });
    if (_isEditing) {
      _loadExistingProperty();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) landlordCreateAllowed(context, LandlordCreateKind.property);
      });
    }
  }

  /// Combines street + address2 into a human-readable property name.
  String _buildAutoName() {
    final street = _addressCtrl.text.trim();
    final unit   = _address2Ctrl.text.trim();
    if (street.isEmpty) return '';
    return unit.isEmpty ? street : '$street $unit';
  }

  Future<void> _loadExistingProperty() async {
    try {
      final row = await _db
          .from('properties')
          .select()
          .eq('id', widget.propertyId!)
          .single();
      if (!mounted) return;
      final storedState = (row['state'] as String?)?.trim() ?? '';
      final imageUrl = row['image_url']?.toString();
      setState(() {
        _addressCtrl.text   = row['address'] as String? ?? '';
        _address2Ctrl.text  = row['address2'] as String? ?? '';
        _cityCtrl.text      = row['city'] as String? ?? 'Phoenix';
        _zipCtrl.text       = row['zip'] as String? ?? '';
        _nameCtrl.text      = row['name'] as String? ?? '';
        _state = storedState.isEmpty ? 'AZ' : storedState.toUpperCase();
        _propertyType = normalizePropertyType(row['property_type']?.toString()) ?? '';
        _existingImageUrl = (imageUrl == null || imageUrl.isEmpty) ? null : imageUrl;
        _hasPhoto = _existingImageUrl != null;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _address2Ctrl.dispose();
    _zipCtrl.dispose();
    _cityCtrl.dispose();
    _rentCtrl.dispose();
    _unitCtrl.dispose();
    super.dispose();
  }

  Future<void> _uploadPhoto({
    required String propertyId,
    required String landlordId,
  }) async {
    final bytes = _photoBytes;
    if (bytes == null) return;
    final path = propertyPhotoStoragePath(
      landlordId: landlordId,
      propertyId: propertyId,
      fileName: _photoName ?? 'photo.jpg',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.storage.from('documents').uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(upsert: false),
    );
    final updated = await _db
        .from('properties')
        .update({'image_url': 'documents/$path'})
        .eq('id', propertyId)
        .select('id');
    if (List<dynamic>.from(updated as List).isEmpty) {
      throw Exception('Photo was uploaded but not linked to the property.');
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.lightImpact();
    setState(() => _isSaving = true);

    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) throw Exception('Not signed in');

      final address  = _addressCtrl.text.trim();
      final address2 = _address2Ctrl.text.trim();

      final payload = propertyWritePayload(
        address: address,
        address2: address2,
        city: _cityCtrl.text,
        zip: _zipCtrl.text,
        state: _state,
        landlordId: _isEditing ? null : uid,
        propertyType: _propertyType,
      );
      if (_removePhoto && _photoBytes == null) {
        payload['image_url'] = null;
      }

      late final String propertyId;
      if (_isEditing) {
        final updated = await _db
            .from('properties')
            .update(payload)
            .eq('id', widget.propertyId!)
            .select('id');
        if (List<dynamic>.from(updated as List).isEmpty) {
          throw Exception('Nothing was saved.');
        }
        propertyId = widget.propertyId!;
      } else {
        // Insert property and get back the new row so we can create its unit.
        final inserted = await _db
            .from('properties')
            .insert(payload)
            .select()
            .single();
        propertyId = inserted['id'] as String;

        final rent = parseMoneyAmount(_rentCtrl.text);
        if (rent == null || rent <= 0) {
          throw Exception('Enter the monthly rent for the first unit.');
        }
        final unitNumber = _unitCtrl.text.trim().isNotEmpty
            ? _unitCtrl.text.trim()
            : (address2.isNotEmpty ? address2 : '1');
        await _db.from('units').insert({
          'property_id' : propertyId,
          'landlord_id' : uid,
          'unit_number' : unitNumber,
          'status'      : 'vacant',
          'rent_amount' : rent,
          'deposit_amount': 0,
          'additional_deposit': 0,
        }).select();
      }

      var photoWarning = '';
      if (_photoBytes != null) {
        try {
          await _uploadPhoto(propertyId: propertyId, landlordId: uid);
        } catch (_) {
          photoWarning = ' The address was saved, but the photo was not.';
        }
      }

      if (mounted) context.read<DashboardProvider>().loadData();
      if (mounted) setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing
                  ? 'Property updated.$photoWarning'
                  : 'Property added!$photoWarning',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _isSaving = false);
      if (!mounted) return;
      if (openSubscriptionForPlanError(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Property' : 'Add Property'),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_isEditing)
            IconButton(
              icon: Icon(LucideIcons.trash2, color: colors.urgentRed),
              onPressed: _confirmDelete,
              tooltip: 'Delete property',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo upload area — ElevatedButton required for web FilePicker trust
              if (_hasPhoto)
                Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      height: 160,
                      decoration: BoxDecoration(
                        color: colors.gold.withAlpha(30),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                        border: Border.all(color: colors.gold, width: 2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _photoBytes != null
                          ? Image.memory(_photoBytes!, fit: BoxFit.cover)
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(LucideIcons.image, size: 40, color: colors.gold),
                                  const SizedBox(height: AppTheme.spacingSm),
                                  Text(
                                    'Photo on file',
                                    style: theme.textTheme.bodySmall?.copyWith(color: colors.goldInk),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    Positioned(
                      top: 8, right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _hasPhoto = false;
                          _photoBytes = null;
                          _photoName = null;
                          _removePhoto = true;
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: colors.midnight.withAlpha(180),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(LucideIcons.x, size: 16, color: colors.ivory),
                        ),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 160,
                  child: ElevatedButton(
                    onPressed: _pickPhoto,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.charcoal,
                      foregroundColor: colors.gold,
                      elevation: 0,
                      side: BorderSide(color: colors.taupe.withAlpha(80)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.upload, size: 32, color: colors.gold),
                        const SizedBox(height: AppTheme.spacingSm),
                        Text('Tap to add property photo',
                            style: theme.textTheme.bodySmall?.copyWith(color: colors.gold)),
                        const SizedBox(height: 4),
                        Text('JPG, PNG supported',
                            style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: AppTheme.spacingLg),

              Text('Property Details', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppTheme.spacingMd),

              // Street address
              TextFormField(
                controller: _addressCtrl,
                decoration: InputDecoration(
                  labelText: 'Address *',
                  hintText: 'Street address',
                  prefixIcon: Icon(LucideIcons.mapPin, color: colors.taupe, size: 18),
                ),
                textCapitalization: TextCapitalization.words,
                validator: validatePropertyAddress,
              ),
              const SizedBox(height: AppTheme.spacingMd),

              // Address 2 — unit number, apt, suite, etc.
              TextFormField(
                controller: _address2Ctrl,
                decoration: InputDecoration(
                  labelText: 'Address 2 (Unit No., Apt, Suite…)',
                  hintText: 'e.g. Apt 4B or Unit 101',
                  prefixIcon: Icon(LucideIcons.building2, color: colors.taupe, size: 18),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              if (!_isEditing) ...[
                const SizedBox(height: AppTheme.spacingMd),
                TextFormField(
                  controller: _unitCtrl,
                  decoration: const InputDecoration(
                    labelText: 'First unit number (optional)',
                    hintText: '1',
                  ),
                ),
                const SizedBox(height: AppTheme.spacingMd),
                TextFormField(
                  controller: _rentCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Monthly rent *',
                    hintText: '1,500.00',
                    prefixText: '\$ ',
                    helperText: 'Required. Saved on the first unit. You can edit it later.',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) => validateMoneyField(value, requiredField: true),
                ),
              ],
              const SizedBox(height: AppTheme.spacingMd),

              // ZIP + City row — ZIP first per user request
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _zipCtrl,
                      decoration: const InputDecoration(
                        labelText: 'ZIP *',
                        hintText: '85018',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      validator: (v) => validatePropertyZip(v, state: _state),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingMd),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _cityCtrl,
                      decoration: InputDecoration(
                        labelText: 'City *',
                        hintText: 'Phoenix',
                        prefixIcon: Icon(LucideIcons.mapPin, color: colors.taupe, size: 18),
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: validatePropertyCity,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingMd),

              // State — always AZ, shown as read-only
              Container(
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                decoration: BoxDecoration(
                  color: colors.charcoal,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(color: colors.taupe.withAlpha(40)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.flag, color: colors.taupe, size: 18),
                    const SizedBox(width: AppTheme.spacingMd),
                    Text('State', style: theme.textTheme.bodySmall),
                    const Spacer(),
                    Text(
                      _state == 'AZ' ? 'AZ — Arizona' : _state,
                      style: theme.textTheme.bodyMedium?.copyWith(color: colors.goldInk),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),

              DropdownButtonFormField<String>(
                value: _propertyTypeChoices.contains(_propertyType) ? _propertyType : '',
                decoration: InputDecoration(
                  labelText: 'Property type',
                  prefixIcon: Icon(LucideIcons.home, color: colors.taupe, size: 18),
                ),
                items: [
                  for (final type in _propertyTypeChoices)
                    DropdownMenuItem(
                      value: type,
                      child: Text(type.isEmpty ? 'Not set' : type),
                    ),
                ],
                onChanged: (value) => setState(() => _propertyType = value ?? ''),
              ),
              const SizedBox(height: AppTheme.spacingMd),

              const SizedBox(height: AppTheme.spacingXl),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(LucideIcons.save, size: 18, color: Colors.white),
                  label: Text(_isSaving
                      ? 'Saving…'
                      : _isEditing ? 'Update Property' : 'Add Property'),
                ),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    if (!kIsWeb) {
      try { HapticFeedback.lightImpact(); } catch (_) {}
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true, // Required on web; safe on mobile too
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (file.bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read that photo. Please try again.')),
          );
        }
        return;
      }
      if (mounted) {
        setState(() {
          _photoBytes = file.bytes;
          _photoName = file.name;
          _hasPhoto = true;
          _removePhoto = false;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open photo picker. Please try again.')),
        );
      }
    }
  }

  Future<void> _confirmDelete() async {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Property'),
        content: const Text(
          'This removes the property from your account. Units that belong to it '
          'are removed with it. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: colors.urgentRed)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = widget.propertyId;
    final uid = _db.auth.currentUser?.id;
    if (id == null || uid == null) return;
    try {
      final units = await _db
          .from('units')
          .select('id, status, tenant_id')
          .eq('property_id', id);
      final blocked = List<dynamic>.from(units as List).any((row) {
        final unit = Map<String, dynamic>.from(row as Map);
        return unitStillHasTenant(
          status: unit['status']?.toString(),
          tenantId: unit['tenant_id']?.toString(),
        );
      });
      if (blocked) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(propertyDeleteBlockedMessage)),
        );
        return;
      }
      final unitIds = List<dynamic>.from(units as List)
          .map((row) => Map<String, dynamic>.from(row as Map)['id']?.toString())
          .whereType<String>()
          .where((unitId) => unitId.isNotEmpty)
          .toList();
      Future<int> count(String table) async {
        if (unitIds.isEmpty) return 0;
        final rows = await _db.from(table).select('id').inFilter('unit_id', unitIds);
        return List<dynamic>.from(rows as List).length;
      }
      final history = historyBlocksDeleteMessage(
        subject: 'property',
        documents: await count('documents'),
        photoLogs: await count('photo_logs'),
        calendarEvents: await count('calendar_events'),
        screenings: await count('tenant_screenings'),
      );
      if (history != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(history)),
        );
        return;
      }
      final removed = await _db
          .from('properties')
          .delete()
          .eq('id', id)
          .eq('landlord_id', uid)
          .select('id');
      if (List<dynamic>.from(removed as List).isEmpty) {
        throw Exception('Nothing was removed.');
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      await context.read<DashboardProvider>().loadData();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Property deleted.')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final text = e.toString().toLowerCase();
      final blocked = text.contains('tenant') || text.contains('42501');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blocked ? propertyDeleteBlockedMessage : 'Could not delete this property.',
          ),
        ),
      );
    }
  }
}
