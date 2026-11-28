/// Models for the ELEVO Preferred Partners directory.
/// Mirrors the vendor_applications and vendor_contacts Supabase tables.

/// Whole dollar amounts stay whole. $39.99 stays $39.99.
String formatVendorPrice(double amount) {
  if (amount == amount.roundToDouble()) return amount.toStringAsFixed(0);
  return amount.toStringAsFixed(2);
}

enum PartnerTier { platinum, preferred, featured, basic }

extension PartnerTierExtension on PartnerTier {
  String get label {
    switch (this) {
      case PartnerTier.platinum:  return 'Platinum';
      case PartnerTier.preferred: return 'Preferred';
      case PartnerTier.featured:  return 'Featured';
      case PartnerTier.basic:     return 'Basic';
    }
  }

  double get monthlyPrice {
    switch (this) {
      case PartnerTier.platinum:  return 199;
      case PartnerTier.preferred: return 149;
      case PartnerTier.featured:  return 89.99;
      case PartnerTier.basic:     return 39.99;
    }
  }

  int get sortOrder {
    switch (this) {
      case PartnerTier.platinum:  return 0;
      case PartnerTier.preferred: return 1;
      case PartnerTier.featured:  return 2;
      case PartnerTier.basic:     return 3;
    }
  }

  static PartnerTier fromString(String s) {
    switch (s.toLowerCase()) {
      case 'platinum':  return PartnerTier.platinum;
      case 'preferred': return PartnerTier.preferred;
      case 'featured':  return PartnerTier.featured;
      default:          return PartnerTier.basic;
    }
  }
}

enum PartnerStatus { pending, active, declined }

extension PartnerStatusExtension on PartnerStatus {
  String get label {
    switch (this) {
      case PartnerStatus.pending:  return 'Pending';
      case PartnerStatus.active:   return 'Active';
      case PartnerStatus.declined: return 'Declined';
    }
  }

  static PartnerStatus fromString(String s) {
    switch (s.toLowerCase()) {
      case 'active':   return PartnerStatus.active;
      case 'declined': return PartnerStatus.declined;
      default:         return PartnerStatus.pending;
    }
  }
}

/// A live, approved vendor listing shown in the directory.
/// Corresponds to a vendor_applications row with status = active.
class PartnerListing {
  final String id;
  final String businessName;
  final String ownerName;
  final String category;
  final String phone;
  final String email;
  final String? website;
  final String serviceArea;
  final String? description;
  final PartnerTier tier;
  final double rating;
  final int reviewCount;
  final String? logoUrl;
  final List<String> workPhotos;
  final int callTaps;
  final int emailTaps;
  final int messageTaps;

  const PartnerListing({
    required this.id,
    required this.businessName,
    required this.ownerName,
    required this.category,
    required this.phone,
    required this.email,
    this.website,
    required this.serviceArea,
    this.description,
    required this.tier,
    this.rating = 0,
    this.reviewCount = 0,
    this.logoUrl,
    this.workPhotos = const [],
    this.callTaps = 0,
    this.emailTaps = 0,
    this.messageTaps = 0,
  });
}

/// A vendor application — pending, active, or declined.
/// Maps 1-to-1 with the vendor_applications Supabase table.
class PartnerApplication {
  final String id;
  final String businessName;
  final String ownerName;
  final String category;
  final String yearsInBusiness;
  final String phone;
  final String email;
  final String? website;
  final String serviceArea;
  final String licenseNumber;
  final String? contractorLicense;
  final bool hasInsurance;
  final PartnerTier tier;
  final PartnerStatus status;
  final double monthlyPrice;
  final String? licenseUrl;
  final String? insuranceUrl;
  final String? logoUrl;
  final List<String>? workPhotos;
  final DateTime submittedAt;
  final DateTime? approvedAt;
  final DateTime? declinedAt;
  final String? adminNotes;

  const PartnerApplication({
    required this.id,
    required this.businessName,
    required this.ownerName,
    required this.category,
    required this.yearsInBusiness,
    required this.phone,
    required this.email,
    this.website,
    required this.serviceArea,
    required this.licenseNumber,
    this.contractorLicense,
    required this.hasInsurance,
    required this.tier,
    required this.status,
    required this.monthlyPrice,
    this.licenseUrl,
    this.insuranceUrl,
    this.logoUrl,
    this.workPhotos,
    required this.submittedAt,
    this.approvedAt,
    this.declinedAt,
    this.adminNotes,
  });

  PartnerApplication copyWith({PartnerStatus? status, DateTime? approvedAt, DateTime? declinedAt}) {
    return PartnerApplication(
      id: id,
      businessName: businessName,
      ownerName: ownerName,
      category: category,
      yearsInBusiness: yearsInBusiness,
      phone: phone,
      email: email,
      website: website,
      serviceArea: serviceArea,
      licenseNumber: licenseNumber,
      contractorLicense: contractorLicense,
      hasInsurance: hasInsurance,
      tier: tier,
      status: status ?? this.status,
      monthlyPrice: monthlyPrice,
      licenseUrl: licenseUrl,
      insuranceUrl: insuranceUrl,
      logoUrl: logoUrl,
      workPhotos: workPhotos,
      submittedAt: submittedAt,
      approvedAt: approvedAt ?? this.approvedAt,
      declinedAt: declinedAt ?? this.declinedAt,
      adminNotes: adminNotes,
    );
  }
}

/// Categories shown in the directory filter chips.
const List<String> kPartnerCategories = [
  'All',
  'Plumber',
  'Electrician',
  'HVAC',
  'Handyman',
  'Painter',
  'Landscaper',
  'Pest Control',
  'Locksmith',
  'Cleaning',
  'Other',
];

/// Years-in-business options for the join form.
const List<String> kYearsInBusiness = [
  'Less than 1 year',
  '1 to 3 years',
  '3 to 5 years',
  '5 to 10 years',
  'More than 10 years',
];
