class MaintenanceRequest {
  final String id;
  final String unitId;
  final String propertyId;
  final String landlordId;
  final String submittedBy;
  final String description;
  final String category;
  final String priority;
  final String status;
  final List<String> photos;
  final String? assignedVendorId;
  final String? assignedVendorName;
  final double? estimatedCost;
  final double? actualCost;
  final String? landlordNotes;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? unitAddress;

  const MaintenanceRequest({
    required this.id,
    required this.unitId,
    required this.propertyId,
    required this.landlordId,
    required this.submittedBy,
    required this.description,
    required this.category,
    this.priority = 'Medium',
    this.status = 'Submitted',
    this.photos = const [],
    this.assignedVendorId,
    this.assignedVendorName,
    this.estimatedCost,
    this.actualCost,
    this.landlordNotes,
    required this.createdAt,
    this.resolvedAt,
    this.unitAddress,
  });

  int get daysOpen => DateTime.now().difference(createdAt).inDays;
  bool get isEmergency => priority == 'Emergency';

  int get statusIndex {
    const stages = ['Submitted', 'Assigned', 'In Progress', 'Resolved'];
    return stages.indexOf(status).clamp(0, 3);
  }

  static const categories = [
    'Plumbing', 'Electrical', 'HVAC', 'Appliance',
    'Structural', 'Pest Control', 'Landscaping', 'Cleaning', 'Other',
  ];

  static const priorities = ['Low', 'Medium', 'High', 'Emergency'];
  static const statuses = ['Submitted', 'Assigned', 'In Progress', 'Resolved'];
}
