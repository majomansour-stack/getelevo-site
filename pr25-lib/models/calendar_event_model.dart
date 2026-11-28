class CalendarEvent {
  final String id;
  final String? unitId;
  final String landlordId;
  final String? tenantId;
  final String eventType;
  final DateTime eventDate;
  final String title;
  final bool isCompleted;
  final String urgency;
  final String? subtitle;
  final String? propertyId;
  final String? propertyName;

  const CalendarEvent({
    required this.id,
    this.unitId,
    required this.landlordId,
    this.tenantId,
    required this.eventType,
    required this.eventDate,
    required this.title,
    this.isCompleted = false,
    this.urgency = 'normal',
    this.subtitle,
    this.propertyId,
    this.propertyName,
  });

  int get daysUntil => eventDate.difference(DateTime.now()).inDays;
  bool get isOverdue => daysUntil < 0 && !isCompleted;

  CalendarEvent copyWith({
    String? id,
    String? unitId,
    String? landlordId,
    String? tenantId,
    String? eventType,
    DateTime? eventDate,
    String? title,
    bool? isCompleted,
    String? urgency,
    String? subtitle,
    String? propertyId,
    String? propertyName,
  }) =>
      CalendarEvent(
        id: id ?? this.id,
        unitId: unitId ?? this.unitId,
        landlordId: landlordId ?? this.landlordId,
        tenantId: tenantId ?? this.tenantId,
        eventType: eventType ?? this.eventType,
        eventDate: eventDate ?? this.eventDate,
        title: title ?? this.title,
        isCompleted: isCompleted ?? this.isCompleted,
        urgency: urgency ?? this.urgency,
        subtitle: subtitle ?? this.subtitle,
        propertyId: propertyId ?? this.propertyId,
        propertyName: propertyName ?? this.propertyName,
      );
}
