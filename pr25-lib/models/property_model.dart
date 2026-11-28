class Property {
  final String id;
  final String landlordId;
  final String name;
  final String address;
  final String city;
  final String state;
  final String zip;
  final String? photoUrl;
  final DateTime createdAt;
  final List<Unit> units;

  const Property({
    required this.id,
    required this.landlordId,
    required this.name,
    required this.address,
    this.city = '',
    this.state = 'AZ',
    this.zip = '',
    this.photoUrl,
    required this.createdAt,
    this.units = const [],
  });

  int get totalUnits => units.length;
  int get occupiedUnits => units.where((u) => u.status == 'occupied').length;
  double get occupancyRate => totalUnits > 0 ? occupiedUnits / totalUnits : 0;
  double get monthlyIncome => units.fold(0.0, (sum, u) => sum + (u.status == 'occupied' ? u.rentAmount : 0));

  /// Rent entered on the units, including a unit that does not have a tenant yet.
  double get enteredRent => units.fold(0.0, (sum, u) => sum + u.rentAmount);
  String get fullAddress => '$address, $city, $state $zip';
}

class Unit {
  final String id;
  final String propertyId;
  final String landlordId;
  final String unitNumber;
  final String? tenantId;
  final String? tenantName;
  final double rentAmount;
  final DateTime? leaseStart;
  final DateTime? leaseEnd;
  final double depositAmount;
  final String status;
  final DateTime createdAt;
  final int openTickets;
  final int? bedrooms;
  final double? bathrooms;
  final int? rentDueDay;

  const Unit({
    required this.id,
    required this.propertyId,
    required this.landlordId,
    required this.unitNumber,
    this.tenantId,
    this.tenantName,
    required this.rentAmount,
    this.leaseStart,
    this.leaseEnd,
    this.depositAmount = 0,
    this.status = 'vacant',
    required this.createdAt,
    this.openTickets = 0,
    this.bedrooms,
    this.bathrooms,
    this.rentDueDay,
  });

  bool get isOccupied => status == 'occupied';
  bool get isVacant => status == 'vacant';

  double get leaseProgress {
    if (leaseStart == null || leaseEnd == null) return 0;
    final total = leaseEnd!.difference(leaseStart!).inDays;
    final elapsed = DateTime.now().difference(leaseStart!).inDays;
    if (total <= 0) return 0;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  int get daysRemaining {
    if (leaseEnd == null) return 0;
    return leaseEnd!.difference(DateTime.now()).inDays;
  }
}
