import 'package:supabase_flutter/supabase_flutter.dart';

/// Centralized service for sending all transactional emails via the
/// Supabase `send-email` Edge Function (powered by Resend).
///
/// Call sites never build HTML directly — they pass a typed [EmailType]
/// and a data map; the Edge Function owns the templates.
class NotificationService {
  NotificationService._();

  static final _client = Supabase.instance.client;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Welcome email sent immediately after a landlord signs up.
  static Future<bool> sendWelcome({
    required String toEmail,
    required String firstName,
  }) => _send(
        to: toEmail,
        type: 'welcome',
        data: {'firstName': firstName},
      );

  /// Tenant invitation email sent from the Invite Tenant screen.
  static Future<bool> sendTenantInvite({
    required String toEmail,
    required String tenantName,
    required String landlordName,
    required String unitLabel,
    required String unitId,
  }) => _send(
        to: toEmail,
        type: 'tenant_invite',
        data: {
          'tenantName':   tenantName,
          'landlordName': landlordName,
          'unitLabel':    unitLabel,
          'unitId':       unitId,
        },
      );

  /// Maintenance status update email sent to the tenant when a landlord
  /// changes the status of a request.
  static Future<bool> sendMaintenanceUpdate({
    required String toEmail,
    required String tenantName,
    required String newStatus,
    required String description,
    required String requestId,
    String? unitLabel,
    String? vendorName,
    String? landlordNote,
  }) => _send(
        to: toEmail,
        type: 'maintenance_update',
        data: {
          'tenantName':   tenantName,
          'newStatus':    newStatus,
          'description':  description,
          'requestId':    requestId,
          if (unitLabel    != null) 'unitLabel':    unitLabel,
          if (vendorName   != null) 'vendorName':   vendorName,
          if (landlordNote != null) 'landlordNote': landlordNote,
        },
      );

  /// Tenant screening invitation sent from the Screening Form screen.
  /// Pass [rentspreeLink] with the resolved property-specific or fallback URL
  /// and [propertyAddress] so the template can include context for the applicant.
  static Future<bool> sendScreeningInvite({
    required String toEmail,
    required String tenantName,
    required String landlordName,
    required String unitLabel,
    required String rentspreeLink,
    required String screeningId,
    String? propertyAddress,
  }) => _send(
        to: toEmail,
        type: 'screening_invite',
        data: {
          'tenantName':      tenantName,
          'landlordName':    landlordName,
          'unitLabel':       unitLabel,
          'rentspreeLink':   rentspreeLink,
          'screeningId':     screeningId,
          if (propertyAddress != null) 'propertyAddress': propertyAddress,
        },
      );

  /// Screening approval email sent to the applicant when a landlord approves.
  static Future<bool> sendScreeningApproved({
    required String toEmail,
    required String applicantName,
    required String unitLabel,
    required String landlordName,
    required String screeningId,
    String? landlordNote,
  }) => _send(
        to: toEmail,
        type: 'screening_approved',
        data: {
          'applicantName': applicantName,
          'unitLabel':     unitLabel,
          'landlordName':  landlordName,
          'screeningId':   screeningId,
          if (landlordNote != null) 'landlordNote': landlordNote,
        },
      );

  /// Adverse-action / screening declined email sent to the applicant.
  /// Includes full FCRA-compliant language as required by federal law.
  static Future<bool> sendScreeningDeclined({
    required String toEmail,
    required String applicantName,
    required String unitLabel,
    required String screeningId,
  }) => _send(
        to: toEmail,
        type: 'screening_declined',
        data: {
          'applicantName': applicantName,
          'unitLabel':     unitLabel,
          'screeningId':   screeningId,
        },
      );

  /// Partner application notification.
  /// [status] must be one of: 'received', 'approved', 'declined'.
  static Future<bool> sendPartnerNotification({
    required String toEmail,
    required String applicantName,
    required String status,
    String? businessName,
    String? category,
    String? tier,
    String? adminNote,
    required String applicationId,
  }) => _send(
        to: toEmail,
        type: 'partner_notification',
        data: {
          'applicantName': applicantName,
          'status':        status,
          if (businessName != null) 'businessName': businessName,
          if (category     != null) 'category':     category,
          if (tier         != null) 'tier':          tier,
          if (adminNote    != null) 'adminNote':     adminNote,
          'applicationId': applicationId,
        },
      );

  /// Tenant tells their own landlord that they paid rent outside Elevo.
  static Future<bool> sendRentPaid({
    required String toEmail,
    required String tenantName,
    required String amount,
    required String monthLabel,
    required String unitId,
  }) => _send(
        to: toEmail,
        type: 'rent_paid',
        data: {
          'tenantName': tenantName,
          'amount': amount,
          'monthLabel': monthLabel,
          'unitId': unitId,
        },
      );

  /// Rent increase/change notification sent to the tenant when the landlord
  /// updates the rent amount for their unit.
  static Future<bool> sendRentIncrease({
    required String toEmail,
    required String tenantName,
    required String unitLabel,
    required String previousAmount,
    required String newAmount,
    required String unitId,
  }) => _send(
        to: toEmail,
        type: 'rent_increase',
        data: {
          'tenantName':     tenantName,
          'unitLabel':      unitLabel,
          'previousAmount': previousAmount,
          'newAmount':      newAmount,
          'unitId':         unitId,
        },
      );

  // ── Internal dispatcher ─────────────────────────────────────────────────────

  /// Landlord announcement. The edge function template must be deployed
  /// before these emails deliver. See supabase/functions/send-email.
  static Future<bool> sendAnnouncement({
    required String toEmail,
    required String tenantName,
    required String landlordName,
    required String unitLabel,
    required String subject,
    required String message,
    required String unitId,
  }) => _send(
        to: toEmail,
        type: 'announcement',
        data: {
          'tenantName': tenantName,
          'landlordName': landlordName,
          'unitLabel': unitLabel,
          'subject': subject,
          'message': message,
          'unitId': unitId,
        },
      );

  /// Message from a landlord or tenant to a preferred partner.
  static Future<bool> sendPartnerMessage({
    required String toEmail,
    required String businessName,
    required String senderName,
    required String message,
    required String listingId,
  }) => _send(
        to: toEmail,
        type: 'partner_message',
        data: {
          'businessName': businessName,
          'senderName': senderName,
          'message': message,
          'listingId': listingId,
        },
      );

  // ── Internal dispatcher ─────────────────────────────────────────────────────

  /// Returns true when the edge function accepted the email.
  static Future<bool> _send({
    required String to,
    required String type,
    required Map<String, String> data,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'send-email',
        body: {'to': to, 'type': type, 'data': data},
      );
      final hasError = response.data is Map &&
          (response.data as Map).containsKey('error');
      return response.status < 300 && !hasError;
    } catch (_) {
      return false;
    }
  }
}
