class Vendor {
  final String id;
  final String landlordId;
  final String name;
  final String company;
  final String category;
  final String phone;
  final String email;
  final double spendLimit;
  final bool isActive;
  final DateTime createdAt;

  const Vendor({
    required this.id,
    required this.landlordId,
    required this.name,
    required this.company,
    required this.category,
    required this.phone,
    required this.email,
    this.spendLimit = 0,
    this.isActive = true,
    required this.createdAt,
  });

  static const List<String> categories = [
    'HVAC',
    'Plumbing',
    'Electrical',
    'Appliance',
    'Roofing',
    'Landscaping',
    'Pest Control',
    'Cleaning',
    'General Handyman',
    'Painting',
    'Flooring',
    'Security',
    'Pool & Spa',
    'Other',
  ];
}
