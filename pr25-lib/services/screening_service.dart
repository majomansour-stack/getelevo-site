import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/screening_model.dart';
import 'notification_service.dart';
import 'rentspree_links.dart';

/// Handles all Supabase persistence and email dispatch for tenant
/// screenings. All data is persisted in the `tenant_screenings` table.
class ScreeningService {
  final _db = Supabase.instance.client;

  // ── Read ─────────────────────────────────────────────────────────────────────

  Future<List<TenantScreening>> fetchForLandlord(String landlordId) async {
    final rows = await _db
        .from('tenant_screenings')
        .select()
        .eq('landlord_id', landlordId)
        .order('created_at', ascending: false);
    return rows.map<TenantScreening>(_mapScreening).toList();
  }

  // ── Create ────────────────────────────────────────────────────────────────────

  Future<TenantScreening> createScreening({
    required TenantScreening screening,
    required String landlordFullName,
  }) async {
    final row = await _db.from('tenant_screenings').insert({
      'landlord_id': screening.landlordId,
      'applicant_name': '${screening.applicantFirstName} ${screening.applicantLastName}',
      'applicant_first_name': screening.applicantFirstName,
      'applicant_last_name': screening.applicantLastName,
      'applicant_email': screening.applicantEmail,
      'property_id': screening.propertyId,
      'property_address': screening.propertyAddress,
      'unit_id': screening.unitId,
      'unit_number': screening.unitNumber,
      'screening_type': screening.screeningType.name,
      'screening_fee': screening.screeningFee,
      'status': 'invited',
    }).select().single();

    final saved = _mapScreening(row);
    // Email failure must not roll back the successfully-created screening record.
    try { await _sendInvitationEmail(saved, landlordFullName); } catch (_) {}
    return saved;
  }

  /// Inserts the screening record with status 'invited' without sending any
  /// email. Used by the RentSpree redirect flow (P6).
  Future<TenantScreening> saveRecordOnly(TenantScreening screening) async {
    final row = await _db.from('tenant_screenings').insert({
      'landlord_id': screening.landlordId,
      'applicant_name': '${screening.applicantFirstName} ${screening.applicantLastName}',
      'applicant_first_name': screening.applicantFirstName,
      'applicant_last_name': screening.applicantLastName,
      'applicant_email': screening.applicantEmail,
      'property_id': screening.propertyId,
      'property_address': screening.propertyAddress,
      'unit_id': screening.unitId,
      'unit_number': screening.unitNumber,
      'screening_type': screening.screeningType.name,
      'screening_fee': screening.screeningFee,
      'status': 'invited',
    }).select().single();
    return _mapScreening(row);
  }

  // ── Update ────────────────────────────────────────────────────────────────────

  Future<TenantScreening> markComplete(String screeningId, String notes) async {
    final row = await _db.from('tenant_screenings').update({
      'status': 'complete',
      'completed_at': DateTime.now().toIso8601String(),
      'notes': notes,
    }).eq('id', screeningId).select().single();
    return _mapScreening(row);
  }

  Future<TenantScreening> approveApplicant(
      String screeningId, String landlordFullName) async {
    final row = await _db.from('tenant_screenings').update({
      'status': 'approved',
      'approved_at': DateTime.now().toIso8601String(),
    }).eq('id', screeningId).select().single();
    final updated = _mapScreening(row);
    await _sendApprovalEmail(updated, landlordFullName);
    return updated;
  }

  Future<TenantScreening> declineApplicant(
      String screeningId, String landlordFullName) async {
    final row = await _db.from('tenant_screenings').update({
      'status': 'declined',
      'declined_at': DateTime.now().toIso8601String(),
    }).eq('id', screeningId).select().single();
    final updated = _mapScreening(row);
    await _sendAdverseActionEmail(updated, landlordFullName);
    return updated;
  }

  Future<TenantScreening> updateNotes(String screeningId, String notes) async {
    final row = await _db.from('tenant_screenings').update({
      'notes': notes,
    }).eq('id', screeningId).select().single();
    return _mapScreening(row);
  }

  Future<void> resendInvitation(
      TenantScreening screening, String landlordFullName) async {
    await _sendInvitationEmail(screening, landlordFullName);
  }

  // ── Mapper ────────────────────────────────────────────────────────────────────

  TenantScreening _mapScreening(Map<String, dynamic> r) {
    final firstName = (r['applicant_first_name'] as String?) ??
        ((r['applicant_name'] as String?) ?? '').split(' ').first;
    final lastName = (r['applicant_last_name'] as String?) ??
        ((r['applicant_name'] as String?) ?? '').split(' ').skip(1).join(' ');
    return TenantScreening(
      id: r['id'] as String,
      landlordId: r['landlord_id'] as String,
      applicantFirstName: firstName,
      applicantLastName: lastName,
      applicantEmail: (r['applicant_email'] as String?) ?? '',
      propertyId: (r['property_id'] as String?) ?? '',
      propertyAddress: (r['property_address'] as String?) ?? '',
      unitId: (r['unit_id'] as String?) ?? '',
      unitNumber: (r['unit_number'] as String?) ?? '',
      screeningType: ScreeningType.values.firstWhere(
        (t) => t.name == (r['screening_type'] as String?),
        orElse: () => ScreeningType.full,
      ),
      screeningFee: ((r['screening_fee'] as num?) ?? 49).toDouble(),
      status: ScreeningStatus.values.firstWhere(
        (s) => s.name == (r['status'] as String?),
        orElse: () => ScreeningStatus.invited,
      ),
      notes: r['notes'] as String?,
      invitedAt: DateTime.tryParse((r['invited_at'] ?? r['created_at'] ?? '') as String) ?? DateTime.now(),
      completedAt: r['completed_at'] != null ? DateTime.parse(r['completed_at'] as String) : null,
      approvedAt: r['approved_at'] != null ? DateTime.parse(r['approved_at'] as String) : null,
      declinedAt: r['declined_at'] != null ? DateTime.parse(r['declined_at'] as String) : null,
    );
  }

  // ── Email helpers (Resend via NotificationService → Edge Function) ───────────

  Future<void> _sendInvitationEmail(
      TenantScreening s, String landlordFullName) async {
    final link = await loadRentspreeLink(s.landlordId);
    await NotificationService.sendScreeningInvite(
      toEmail:      s.applicantEmail,
      tenantName:   s.applicantFirstName,
      landlordName: landlordFullName,
      unitLabel:    s.propertyAndUnit,
      rentspreeLink: link,
      screeningId:  s.id,
    );
  }

  Future<void> _sendApprovalEmail(
      TenantScreening s, String landlordFullName) async {
    await NotificationService.sendScreeningApproved(
      toEmail:      s.applicantEmail,
      applicantName: s.applicantFirstName,
      unitLabel:    s.propertyAndUnit,
      landlordName: landlordFullName,
      screeningId:  s.id,
    );
  }

  Future<void> _sendAdverseActionEmail(
      TenantScreening s, String landlordFullName) async {
    await NotificationService.sendScreeningDeclined(
      toEmail:      s.applicantEmail,
      applicantName: s.applicantFirstName,
      unitLabel:    s.propertyAndUnit,
      screeningId:  s.id,
    );
  }
}


