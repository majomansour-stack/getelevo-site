import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/elevo_logic.dart';
import '../../models/maintenance_model.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/notification_service.dart';
import '../../services/push_notification_service.dart';
import '../../theme/theme.dart';
import '../../widgets/common/repair_timeline.dart';
import '../../widgets/common/status_chip.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/maintenance/repair_photo_strip.dart';
import '../chat_screen.dart';
import 'package:provider/provider.dart';

class MaintenanceLandlordScreen extends StatefulWidget {
  const MaintenanceLandlordScreen({super.key});

  @override
  State<MaintenanceLandlordScreen> createState() => _MaintenanceLandlordScreenState();
}

class _MaintenanceLandlordScreenState extends State<MaintenanceLandlordScreen> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final all = context.watch<DashboardProvider>().requests;
    final filtered = _filter == 'All'
        ? all
        : all.where((r) => r.status == _filter).toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => context.pop(),
        ),
        title: const Text('Maintenance'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
              children: ['All', ...MaintenanceRequest.statuses].map((s) {
                final selected = s == _filter;
                return Padding(
                  padding: const EdgeInsets.only(right: AppTheme.spacingSm),
                  child: ChoiceChip(
                    label: Text(s),
                    selected: selected,
                    selectedColor: colors.olive,
                    backgroundColor: colors.card,
                    side: BorderSide(color: selected ? colors.olive : colors.stone),
                    labelStyle: TextStyle(
                      color: selected ? colors.onOlive : colors.sage,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => setState(() => _filter = s),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const EmptyState(
                    icon: LucideIcons.wrench,
                    message: 'No maintenance requests',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppTheme.spacingMd),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spacingSm),
                    itemBuilder: (context, i) => _RequestCard(request: filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final MaintenanceRequest request;

  const _RequestCard({required this.request});

  Future<void> _showUpdateSheet(BuildContext context) async {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final db     = Supabase.instance.client;

    String? selectedStatus = request.status;
    final noteCtrl = TextEditingController();
    String? _invoiceFileName;
    final vendorRows = <Map<String, dynamic>>[];
    try {
      final uid = db.auth.currentUser?.id;
      if (uid != null) {
        final loaded = await db
            .from('vendors')
            .select('id, name, email')
            .eq('landlord_id', uid);
        for (final row in loaded) {
          vendorRows.add(Map<String, dynamic>.from(row));
        }
      }
    } catch (_) {}
    String? selectedVendorId;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.charcoal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left:   AppTheme.spacingMd,
            right:  AppTheme.spacingMd,
            top:    AppTheme.spacingMd,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + AppTheme.spacingLg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: colors.stone,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),
              Text('Update Status', style: theme.textTheme.titleMedium?.copyWith(color: colors.ivory)),
              if (request.photos.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spacingSm),
                RepairPhotoStrip(groupId: request.id, paths: request.photos),
              ],
              const SizedBox(height: AppTheme.spacingSm),
              Text(
                request.description,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.taupe),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppTheme.spacingMd),
              ...MaintenanceRequest.statuses.map((s) {
                final selected = s == selectedStatus;
                return GestureDetector(
                  onTap: () => setSheetState(() => selectedStatus = s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.only(bottom: AppTheme.spacingXs),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingMd,
                      vertical: AppTheme.spacingSm,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? colors.gold.withAlpha(25) : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                      border: Border.all(
                        color: selected ? colors.gold : colors.stone.withAlpha(60),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected ? LucideIcons.checkCircle : LucideIcons.circle,
                          size: 16,
                          color: selected ? colors.gold : colors.taupe,
                        ),
                        const SizedBox(width: AppTheme.spacingSm),
                        Text(
                          s,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: selected ? colors.gold : colors.ivory,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              if (selectedStatus == 'Assigned' && vendorRows.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spacingSm),
                DropdownButtonFormField<String>(
                  value: selectedVendorId,
                  dropdownColor: colors.card,
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink),
                  decoration: InputDecoration(
                    labelText: 'Assign vendor',
                    filled: true,
                    fillColor: colors.card,
                  ),
                  items: [
                    for (final v in vendorRows)
                      DropdownMenuItem(
                        value: v['id']?.toString(),
                        child: Text(
                          v['name']?.toString() ?? 'Vendor',
                          style: TextStyle(color: colors.ink),
                        ),
                      ),
                  ],
                  onChanged: (value) => setSheetState(() => selectedVendorId = value),
                ),
              ],
              const SizedBox(height: AppTheme.spacingMd),
              TextField(
                controller: noteCtrl,
                style: TextStyle(color: colors.ink),
                decoration: InputDecoration(
                  hintText: 'Note for tenant (optional)',
                  hintStyle: TextStyle(color: colors.sage),
                  filled: true,
                  fillColor: colors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    borderSide: BorderSide(color: colors.stone.withAlpha(60)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    borderSide: BorderSide(color: colors.stone.withAlpha(60)),
                  ),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: AppTheme.spacingMd),
              // Show Attach Invoice button when status is Resolved
              if (selectedStatus == 'Resolved') ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.gold.withAlpha(30),
                    foregroundColor: colors.goldInk,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                      side: BorderSide(color: colors.gold.withAlpha(80)),
                    ),
                  ),
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                    );
                    if (result != null && result.files.isNotEmpty) {
                      setSheetState(() => _invoiceFileName = result.files.first.name);
                      try {
                        final bytes = result.files.first.bytes;
                        final fname = result.files.first.name;
                        if (bytes != null) {
                          final uid = db.auth.currentUser?.id;
                          if (uid == null) throw Exception('Not signed in');
                          final safeName = storageSafeFileName(fname);
                          final path = '$uid/maintenance/${request.id}/$safeName';
                          await db.storage.from('documents').uploadBinary(
                            path,
                            bytes,
                            fileOptions: const FileOptions(upsert: true),
                          );
                          await db
                              .from('maintenance_requests')
                              .update({'invoice_url': path})
                              .eq('id', request.id);
                          await db.from('documents').insert(documentInsertPayload(
                            uid: uid,
                            isLandlord: true,
                            fileName: fname,
                            fileUrl: path,
                            docType: 'Receipt',
                            fileSizeBytes: bytes.length,
                            unitId: request.unitId,
                            counterpartyId: request.submittedBy,
                          )).select();
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Invoice uploaded & saved to vault.'),
                                backgroundColor: colors.successGreen,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      } catch (_) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Invoice upload failed. Please try again.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    }
                  },
                  icon: Icon(LucideIcons.paperclip, size: 16, color: colors.gold),
                  label: Text(
                    _invoiceFileName != null
                        ? 'Invoice: $_invoiceFileName'
                        : 'Attach Invoice (PDF/Image)',
                    style: TextStyle(color: colors.goldInk, fontSize: 13),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingSm),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (selectedStatus == null) return;
                    Navigator.of(ctx).pop();

                    final dbStatus = maintenanceStatusToDb(selectedStatus!);
                    String? vendorName;
                    String? vendorEmail;
                    if (selectedStatus == 'Assigned' && selectedVendorId != null) {
                      for (final vendor in vendorRows) {
                        if (vendor['id']?.toString() == selectedVendorId) {
                          vendorName = vendor['name']?.toString();
                          vendorEmail = vendor['email']?.toString();
                        }
                      }
                    }

                    String? vendorUserId;
                    String? vendorLinkNote;
                    final trimmedVendorEmail = vendorEmail?.trim() ?? '';
                    if (selectedStatus == 'Assigned' && trimmedVendorEmail.isNotEmpty) {
                      try {
                        final matches = await db
                            .from('vendor_login_for_landlord')
                            .select('id')
                            .ilike('email', ilikeLiteral(trimmedVendorEmail))
                            .limit(1);
                        if (matches.isNotEmpty) {
                          final found = matches.first['id']?.toString() ?? '';
                          if (found.isNotEmpty) vendorUserId = found;
                        }
                        if (vendorUserId == null) {
                          vendorLinkNote =
                              'No Elevo login matched this vendor\'s email, so the tenant will not see Message vendor.';
                          debugPrint(
                            '[maintenance] no Elevo login for vendor email $trimmedVendorEmail',
                          );
                        }
                      } catch (e) {
                        vendorLinkNote =
                            'The vendor was saved, but their Elevo login could not be linked, so the tenant will not see Message vendor.';
                        debugPrint('[maintenance] vendor login lookup failed: $e');
                      }
                    }

                    final updatePayload = <String, dynamic>{
                      'status': dbStatus,
                      if (noteCtrl.text.trim().isNotEmpty)
                        'landlord_notes': noteCtrl.text.trim(),
                      if (selectedStatus == 'Resolved')
                        ...maintenanceCloseTimestamps(DateTime.now()),
                      if (selectedVendorId != null) 'vendor_id': selectedVendorId,
                      if (vendorName != null && vendorName.isNotEmpty)
                        'vendor_name': vendorName,
                      if (vendorUserId != null) 'vendor_user_id': vendorUserId,
                    };

                    try {
                      try {
                        await db
                            .from('maintenance_requests')
                            .update(updatePayload)
                            .eq('id', request.id);
                      } catch (e) {
                        if (!updatePayload.containsKey('vendor_user_id')) rethrow;
                        debugPrint('[maintenance] saving vendor_user_id failed: $e');
                        updatePayload.remove('vendor_user_id');
                        vendorUserId = null;
                        vendorLinkNote =
                            'The job was assigned, but the vendor login could not be stored, so the tenant will not see Message vendor.';
                        await db
                            .from('maintenance_requests')
                            .update(updatePayload)
                            .eq('id', request.id);
                      }

                      if (vendorUserId != null) {
                        await PushNotificationService.sendToUser(
                          userId: vendorUserId,
                          title: 'New maintenance job',
                          body: request.description,
                          data: {
                            'type': 'maintenance',
                            'request_id': request.id,
                          },
                        );
                      }

                      // Refresh dashboard
                      if (context.mounted) {
                        context.read<DashboardProvider>().loadData();
                      }

                      // Send email notification to tenant
                      // Look up tenant email from the submittedBy user id
                      if (request.submittedBy.isNotEmpty) {
                        try {
                          final userRow = await db
                              .from('users')
                              .select('email, full_name')
                              .eq('id', request.submittedBy)
                              .maybeSingle();
                          if (userRow != null) {
                            // Email via Resend
                            await NotificationService.sendMaintenanceUpdate(
                              toEmail:     userRow['email'] as String,
                              tenantName:  (userRow['full_name'] as String?) ?? 'Tenant',
                              newStatus:   selectedStatus!,
                              description: request.description,
                              requestId:   request.id,
                              unitLabel:   request.unitAddress,
                              vendorName:  request.assignedVendorName,
                              landlordNote: noteCtrl.text.trim().isNotEmpty
                                  ? noteCtrl.text.trim()
                                  : null,
                            );
                            // Push notification
                            await PushNotificationService.notifyMaintenanceUpdate(
                              tenantId:    request.submittedBy,
                              newStatus:   selectedStatus!,
                              description: request.description,
                              requestId:   request.id,
                            );
                          }
                        } catch (_) {
                          // Tenant email lookup failure is non-fatal
                        }
                      }

                      if (context.mounted) {
                        final note = vendorLinkNote;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(note == null
                                ? 'Status updated to $selectedStatus'
                                : 'Status updated to $selectedStatus. $note'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: note == null ? 4 : 8),
                          ),
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to update status. Please try again.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Save & Notify Tenant'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    noteCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return GestureDetector(
      onTap: () => _showUpdateSheet(context),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        decoration: AppTheme.surfaceCard(
          colors,
          border: request.isEmergency
              ? Border.all(color: colors.urgentRed.withAlpha(120))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.unitAddress ?? '',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                StatusChip(label: request.priority),
                if (request.photos.isNotEmpty) ...[
                  const SizedBox(width: AppTheme.spacingSm),
                  RepairPhotoIndicator(count: request.photos.length, color: colors.sage),
                ],
              ],
            ),
            const SizedBox(height: AppTheme.spacingSm),
            Row(
              children: [
                StatusChip(label: request.category),
                const SizedBox(width: AppTheme.spacingSm),
                StatusChip(label: request.status),
              ],
            ),
            const SizedBox(height: AppTheme.spacingSm),
            Text(
              request.description,
              style: theme.textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppTheme.spacingSm),
            Row(
              children: [
                Text('${request.daysOpen}d open', style: theme.textTheme.labelSmall),
                if (request.assignedVendorName != null) ...[
                  const SizedBox(width: AppTheme.spacingSm),
                  Icon(LucideIcons.hardHat, size: 12, color: colors.taupe),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      request.assignedVendorName!,
                      style: theme.textTheme.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const Spacer(),
                Icon(LucideIcons.chevronRight, size: 14, color: colors.taupe),
              ],
            ),
            if ((request.assignedVendorId ?? '').isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => openJobChat(
                    context,
                    requestId: request.id,
                    unitId: request.unitId,
                    unitAddress: request.unitAddress ?? request.description,
                    status: request.status,
                  ),
                  icon: Icon(LucideIcons.users, size: 16, color: colors.gold),
                  label: Text('Job chat', style: TextStyle(color: colors.goldInk)),
                ),
              ),
            ],
            const SizedBox(height: AppTheme.spacingSm),
            RepairStatusTimeline(currentIndex: request.statusIndex),
          ],
        ),
      ),
    );
  }
}

