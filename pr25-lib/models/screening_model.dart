enum ScreeningType { full }

enum ScreeningStatus { invited, complete, approved, declined }

class TenantScreening {
  final String id;
  final String landlordId;
  final String applicantFirstName;
  final String applicantLastName;
  final String applicantEmail;
  final String propertyId;
  final String propertyAddress;
  final String unitId;
  final String unitNumber;
  final ScreeningType screeningType;
  final double screeningFee;
  final ScreeningStatus status;
  final String? notes;
  final DateTime invitedAt;
  final DateTime? completedAt;
  final DateTime? approvedAt;
  final DateTime? declinedAt;

  const TenantScreening({
    required this.id,
    required this.landlordId,
    required this.applicantFirstName,
    required this.applicantLastName,
    required this.applicantEmail,
    required this.propertyId,
    required this.propertyAddress,
    required this.unitId,
    required this.unitNumber,
    required this.screeningType,
    required this.screeningFee,
    this.status = ScreeningStatus.invited,
    this.notes,
    required this.invitedAt,
    this.completedAt,
    this.approvedAt,
    this.declinedAt,
  });

  String get applicantFullName => '$applicantFirstName $applicantLastName';
  String get propertyAndUnit   => '$propertyAddress — Unit $unitNumber';

  String get screeningTypeLabel => 'Full Credit';

  String get feeLabel => 'Full Credit \$49';

  TenantScreening copyWith({
    ScreeningStatus? status,
    String?          notes,
    DateTime?        completedAt,
    DateTime?        approvedAt,
    DateTime?        declinedAt,
  }) =>
      TenantScreening(
        id: id,
        landlordId: landlordId,
        applicantFirstName: applicantFirstName,
        applicantLastName: applicantLastName,
        applicantEmail: applicantEmail,
        propertyId: propertyId,
        propertyAddress: propertyAddress,
        unitId: unitId,
        unitNumber: unitNumber,
        screeningType: screeningType,
        screeningFee: screeningFee,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        invitedAt: invitedAt,
        completedAt: completedAt ?? this.completedAt,
        approvedAt: approvedAt ?? this.approvedAt,
        declinedAt: declinedAt ?? this.declinedAt,
      );

  // ── Supabase serialisation helpers ─────────────────────────────────────────

  Map<String, dynamic> toInsertMap() => {
        'landlord_id':           landlordId,
        'applicant_first_name':  applicantFirstName,
        'applicant_last_name':   applicantLastName,
        'applicant_email':       applicantEmail,
        'property_id':           propertyId,
        'unit_id':               unitId,
        'screening_type':        'full',
        'screening_fee':         screeningFee,
        'status':                'invited',
      };

  factory TenantScreening.fromMap(
    Map<String, dynamic> m, {
    required String propertyAddress,
    required String unitNumber,
  }) =>
      TenantScreening(
        id:                   m['id'] as String,
        landlordId:           m['landlord_id'] as String,
        applicantFirstName:   m['applicant_first_name'] as String,
        applicantLastName:    m['applicant_last_name'] as String,
        applicantEmail:       m['applicant_email'] as String,
        propertyId:           m['property_id'] as String,
        propertyAddress:      propertyAddress,
        unitId:               m['unit_id'] as String,
        unitNumber:           unitNumber,
        screeningType:        ScreeningType.full,
        screeningFee:         (m['screening_fee'] as num).toDouble(),
        status:               _statusFromString(m['status'] as String),
        notes:                m['notes'] as String?,
        invitedAt:            DateTime.parse((m['invited_at'] ?? m['created_at']) as String),
        completedAt:          m['completed_at'] != null
            ? DateTime.parse(m['completed_at'] as String)
            : null,
        approvedAt:           m['approved_at'] != null
            ? DateTime.parse(m['approved_at'] as String)
            : null,
        declinedAt:           m['declined_at'] != null
            ? DateTime.parse(m['declined_at'] as String)
            : null,
      );

  static ScreeningStatus _statusFromString(String s) {
    switch (s) {
      case 'complete':  return ScreeningStatus.complete;
      case 'approved':  return ScreeningStatus.approved;
      case 'declined':  return ScreeningStatus.declined;
      default:          return ScreeningStatus.invited;
    }
  }
}
