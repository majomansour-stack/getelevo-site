import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/elevo_logic.dart';
import '../models/partner_model.dart';
import '../providers/partner_provider.dart' show kPlatinumMaxSpots, kPreferredMaxSpotsPerCategory;
import 'notification_service.dart';
import 'push_notification_service.dart';

/// Handles all Preferred Partners data operations against Supabase.
/// Directory listings and vendor applications are stored in `partner_listings`
/// and `vendor_applications` tables respectively.
class PartnerService {
  final _db = Supabase.instance.client;

  // Cached listing counts for sync capacity checks — populated after fetchListings().
  int _cachedPlatinumCount = 0;
  final Map<String, int> _cachedPreferredCountByCategory = {};

  // ─────────────────────────────────────────────────────────────────────────
  // Sync capacity helpers — backed by cached counts from last fetchListings()
  // ─────────────────────────────────────────────────────────────────────────

  bool get isPlatinumFull => _cachedPlatinumCount >= kPlatinumMaxSpots;

  bool isPreferredFullForCategory(String category) =>
      (_cachedPreferredCountByCategory[category] ?? 0) >= kPreferredMaxSpotsPerCategory;

  // ─────────────────────────────────────────────────────────────────────────
  // Directory queries
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<PartnerListing>> fetchListings() async {
    final rows = await _db
        .from('partner_listings')
        .select()
        .eq('status', 'active')
        .order('tier');

    final listings = rows.map<PartnerListing>(_mapListing).toList();

    // Update cached capacity counts
    _cachedPlatinumCount =
        listings.where((l) => l.tier == PartnerTier.platinum).length;
    _cachedPreferredCountByCategory.clear();
    for (final l in listings.where((l) => l.tier == PartnerTier.preferred)) {
      _cachedPreferredCountByCategory[l.category] =
          (_cachedPreferredCountByCategory[l.category] ?? 0) + 1;
    }

    listings.sort((a, b) {
      final tierCmp = a.tier.sortOrder.compareTo(b.tier.sortOrder);
      if (tierCmp != 0) return tierCmp;
      return a.businessName.compareTo(b.businessName);
    });
    return listings;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Admin application queries
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<PartnerApplication>> fetchApplications() async {
    final rows = await _db
        .from('vendor_applications')
        .select()
        .order('submitted_at', ascending: false);
    return rows.map<PartnerApplication>(_mapApplication).toList();
  }

  Future<void> approveApplication(String applicationId) async {
    final row = await _db.from('vendor_applications').update({
      'status': 'active',
      'approved_at': DateTime.now().toIso8601String(),
    }).eq('id', applicationId).select().single();
    final application = _mapApplication(row);
    try {
      await _db.from('partner_listings').insert({
        'name': application.businessName,
        'business_name': application.businessName,
        'owner_name': application.ownerName,
        'category': application.category,
        'phone': application.phone,
        'email': application.email,
        'website': application.website,
        'service_area': application.serviceArea,
        'tier': application.tier.name,
        'status': 'active',
        'license_number': application.licenseNumber,
        'has_insurance': application.hasInsurance,
      }).select();
    } catch (_) {
      // The application is already active. A missing directory column
      // should not undo that approval.
    }
    // Email via Resend
    await NotificationService.sendPartnerNotification(
      toEmail:       application.email,
      applicantName: application.ownerName,
      status:        'approved',
      businessName:  application.businessName,
      category:      application.category,
      tier:          '${application.tier.name[0].toUpperCase()}${application.tier.name.substring(1)}',
      applicationId: applicationId,
    );
    // Push notification — look up vendor user_id by email
    try {
      final userRow = await _db
          .from('users')
          .select('id')
          .eq('email', application.email)
          .maybeSingle();
      if (userRow != null) {
        await PushNotificationService.notifyVendorApproved(
          vendorId:   userRow['id'] as String,
          vendorName: application.ownerName,
        );
      }
    } catch (_) {}
  }

  Future<void> declineApplication(String applicationId) async {
    final row = await _db.from('vendor_applications').update({
      'status': 'declined',
      'declined_at': DateTime.now().toIso8601String(),
    }).eq('id', applicationId).select().single();
    final application = _mapApplication(row);
    // Email via Resend
    await NotificationService.sendPartnerNotification(
      toEmail:       application.email,
      applicantName: application.ownerName,
      status:        'declined',
      businessName:  application.businessName,
      applicationId: applicationId,
    );
    // Push notification — look up vendor user_id by email
    try {
      final userRow = await _db
          .from('users')
          .select('id')
          .eq('email', application.email)
          .maybeSingle();
      if (userRow != null) {
        await PushNotificationService.notifyVendorDeclined(
          vendorId:   userRow['id'] as String,
          vendorName: application.ownerName,
        );
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Join application submission
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> submitApplication(PartnerApplication application) async {
    final inserted = await _db.from('vendor_applications').insert({
      'name': application.businessName,
      'business_name': application.businessName,
      'owner_name': application.ownerName,
      'category': application.category,
      'years_in_business': application.yearsInBusiness,
      'phone': application.phone,
      'email': application.email,
      'website': application.website,
      'service_area': application.serviceArea,
      'license_number': application.licenseNumber,
      if (application.contractorLicense != null)
        'contractor_license': application.contractorLicense,
      'has_insurance': application.hasInsurance,
      'tier': application.tier.name,
      'status': 'pending',
      'monthly_price': application.monthlyPrice,
      'submitted_at': application.submittedAt.toIso8601String(),
    }).select('id').single();
    final applicationId = inserted['id'] as String;
    // Notify the applicant their submission was received
    await NotificationService.sendPartnerNotification(
      toEmail:       application.email,
      applicantName: application.ownerName,
      status:        'received',
      businessName:  application.businessName,
      category:      application.category,
      tier:          '${application.tier.name[0].toUpperCase()}${application.tier.name.substring(1)}',
      applicationId: applicationId,
    );
    // Notify the ELEVO admin team
    await NotificationService.sendPartnerNotification(
      toEmail:       'hello@getelevo.app',
      applicantName: 'Admin',
      status:        'received',
      businessName:  application.businessName,
      category:      '${application.category} · ${application.tier.name} · ${application.ownerName} · ${application.email} · ${application.phone}',
      applicationId: applicationId,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Contact tap tracking
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> logContactTap({
    required String vendorId,
    required String contactedBy,
    required String contactType, // 'call' | 'email' | 'message'
    String? message,
  }) async {
    final body = (message != null && message.trim().isNotEmpty)
        ? message.trim()
        : contactType;
    await _db.from('vendor_contacts').insert(vendorContactInsert(
          listingId: vendorId,
          senderId: contactedBy,
          message: body,
        ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Mappers
  // ─────────────────────────────────────────────────────────────────────────

  PartnerListing _mapListing(Map<String, dynamic> r) {
    return PartnerListing(
      id: r['id'] as String,
      businessName: partnerBusinessName(r),
      ownerName: (r['owner_name'] as String?) ?? '',
      category: (r['category'] as String?) ?? '',
      phone: (r['phone'] as String?) ?? '',
      email: (r['email'] as String?) ?? '',
      website: r['website'] as String?,
      serviceArea: (r['service_area'] as String?) ?? '',
      description: r['description'] as String?,
      tier: PartnerTier.values.firstWhere(
        (t) => t.name == (r['tier'] as String?),
        orElse: () => PartnerTier.basic,
      ),
      rating: ((r['rating'] as num?) ?? 0).toDouble(),
      reviewCount: (r['review_count'] as num?)?.toInt() ?? 0,
      logoUrl: r['logo_url'] as String?,
      workPhotos: _stringList(r['work_photos']),
    );
  }

  PartnerApplication _mapApplication(Map<String, dynamic> r) {
    return PartnerApplication(
      id: r['id'] as String,
      businessName: partnerBusinessName(r),
      ownerName: (r['owner_name'] as String?) ?? '',
      category: (r['category'] as String?) ?? '',
      yearsInBusiness: r['years_in_business']?.toString() ?? '',
      phone: (r['phone'] as String?) ?? '',
      email: (r['email'] as String?) ?? '',
      website: r['website'] as String?,
      serviceArea: (r['service_area'] as String?) ?? '',
      licenseNumber: (r['license_number'] as String?) ?? '',
      hasInsurance: (r['has_insurance'] as bool?) ?? false,
      tier: PartnerTier.values.firstWhere(
        (t) => t.name == (r['tier'] as String?),
        orElse: () => PartnerTier.basic,
      ),
      status: PartnerStatus.values.firstWhere(
        (s) => s.name == (r['status'] as String?),
        orElse: () => PartnerStatus.pending,
      ),
      monthlyPrice: ((r['monthly_price'] as num?) ?? 0).toDouble(),
      submittedAt: DateTime.tryParse(r['submitted_at']?.toString() ?? '') ??
          DateTime.tryParse(r['created_at']?.toString() ?? '') ??
          DateTime.now(),
      approvedAt: r['approved_at'] != null
          ? DateTime.parse(r['approved_at'] as String)
          : null,
      declinedAt: r['declined_at'] != null
          ? DateTime.parse(r['declined_at'] as String)
          : null,
      logoUrl: r['logo_url'] as String?,
    );
  }
}

List<String> _stringList(dynamic raw) {
  if (raw is List) {
    return raw.map((item) => item.toString()).toList();
  }
  return const [];
}
