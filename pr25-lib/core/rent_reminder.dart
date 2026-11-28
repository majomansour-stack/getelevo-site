/// America/Phoenix is UTC-7 all year. Rent reminders use that calendar.
DateTime phoenixDate(DateTime instant) {
  final shifted = instant.toUtc().subtract(const Duration(hours: 7));
  return DateTime.utc(shifted.year, shifted.month, shifted.day);
}

int _dueDay(int? dueDay) {
  if (dueDay == null || dueDay < 1) return 1;
  if (dueDay > 31) return 31;
  return dueDay;
}

int _clampDay(int year, int month, int preferred) {
  final last = DateTime.utc(year, month + 1, 0).day;
  return preferred > last ? last : preferred;
}

/// Next due date on or after [phoenixDay]. [phoenixDay] is a UTC date-only.
DateTime nextRentDueOn(DateTime phoenixDay, int? dueDay) {
  final preferred = _dueDay(dueDay);
  final year = phoenixDay.year;
  final month = phoenixDay.month;
  final thisDue = DateTime.utc(year, month, _clampDay(year, month, preferred));
  if (!thisDue.isBefore(phoenixDay)) return thisDue;
  final next = DateTime.utc(year, month + 1, 1);
  return DateTime.utc(
    next.year,
    next.month,
    _clampDay(next.year, next.month, preferred),
  );
}

/// One reminder, exactly two Phoenix days before the due date.
/// [alreadySent] is the email_send_log row for that due date.
bool shouldSendRentReminder({
  required DateTime phoenixToday,
  required int? dueDay,
  required bool alreadySent,
  required bool emailAllowed,
}) {
  if (!emailAllowed || alreadySent) return false;
  final due = nextRentDueOn(phoenixToday, dueDay);
  return due.difference(phoenixToday).inDays == 2;
}
