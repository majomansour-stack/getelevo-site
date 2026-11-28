/// Pure helpers for Elevo flows. No Supabase or Flutter bindings, so unit
/// tests can prove role routing, status mapping, and payload shapes.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'billing_rules.dart';

/// Live project. A test build can override these with
/// `--dart-define=SUPABASE_URL=...` and `--dart-define=SUPABASE_ANON_KEY=...`.
const defaultSupabaseUrl = 'https://xehpakgyqraajutfcvrn.supabase.co';
const defaultSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhlaHBha2d5cXJhYWp1dGZjdnJuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA0MjU4OTQsImV4cCI6MjA5NjAwMTg5NH0.0NUhOlEck-WeXPRkB9TUGPUO5UBc1xRzB3L1ZRN6tVQ';

/// Turns an email into an ILIKE pattern that matches that address only.
/// Underscores and percent signs are literal, not wildcards.
String ilikeLiteral(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}

/// Opening a chat marks the opener's incoming notes read.
/// A named counterparty limits that to notes from that person.
bool shouldMarkMessageRead({
  required String me,
  required String receiverId,
  required String senderId,
  required bool isRead,
  String? counterpartyId,
}) {
  if (isRead || receiverId != me) return false;
  final party = counterpartyId?.trim() ?? '';
  if (party.isEmpty) return true;
  return senderId == party;
}

/// Empty means "no build override", so the live value stays in place.
String configuredSupabaseValue(String fromEnvironment, String liveDefault) {
  final override = fromEnvironment.trim();
  if (override.isEmpty) return liveDefault;
  return override;
}

const authEntryRoutes = <String>{
  '/login',
  '/signup',
  '/check-email',
  '/vendor-signup',
  '/splash',
  '/reset-password',
  '/terms',
  '/privacy',
};

/// Calendar date in the device's local zone. Rent math must not use the clock time.
DateTime dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

/// A stored due day of 1–31. Anything else means the day is not set.
int? parseRentDueDay(Object? value) {
  if (value == null) return null;
  final parsed = value is num ? value.toInt() : int.tryParse(value.toString());
  if (parsed == null || parsed < 1 || parsed > 31) return null;
  return parsed;
}

int _clampedDueDay(int year, int month, int? dueDay) {
  final preferred = dueDay ?? 1;
  final last = DateTime(year, month + 1, 0).day;
  return preferred > last ? last : preferred;
}

/// Next rent due date. An unset [dueDay] is the 1st. A 31st in a shorter
/// month lands on that month's last day.
DateTime nextRentDueDate(DateTime today, {int? dueDay}) {
  final day = dateOnly(today);
  final dueThis = DateTime(day.year, day.month, _clampedDueDay(day.year, day.month, dueDay));
  if (!day.isAfter(dueThis)) return dueThis;
  final next = DateTime(day.year, day.month + 1, 1);
  return DateTime(next.year, next.month, _clampedDueDay(next.year, next.month, dueDay));
}

int daysUntilRentDue(DateTime today, {int? dueDay}) {
  return nextRentDueDate(today, dueDay: dueDay).difference(dateOnly(today)).inDays;
}

const _monthNames = <String>[
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Rows saved before rent_period existed. Most notices are sent a few days
/// before the due date, so they belong to the due date that followed.
/// New notices store rent_period (see [rentNoticeTargetMonth]).
DateTime rentNoticeMonth(DateTime submitted, {int? dueDay}) {
  final due = nextRentDueDate(
    submitted.isUtc ? submitted.toLocal() : submitted,
    dueDay: dueDay,
  );
  return DateTime(due.year, due.month);
}

/// Month a new "I Have Paid" notice is for.
///
/// Normally the month of the next due date on the card, so paying a few
/// days early counts for that month. When this month's due date has passed
/// and nothing was sent for this month, the notice is late rent for this
/// month, but only within 14 days of the due date. [sentMonths] holds
/// 'yyyy-m' keys of notices already sent (pending or confirmed).
DateTime rentNoticeTargetMonth(
  DateTime today, {
  int? dueDay,
  Set<String> sentMonths = const {},
}) {
  final day = dateOnly(today);
  final thisDue = DateTime(day.year, day.month, _clampedDueDay(day.year, day.month, dueDay));
  final daysLate = day.difference(thisDue).inDays;
  if (daysLate > 0 && daysLate <= 14 && !sentMonths.contains('${day.year}-${day.month}')) {
    return DateTime(day.year, day.month);
  }
  final due = nextRentDueDate(today, dueDay: dueDay);
  return DateTime(due.year, due.month);
}

/// The due date a new notice is counting for. In the late window that is
/// this month's due date, not the next one.
DateTime rentNoticeDueDate(
  DateTime today, {
  int? dueDay,
  Set<String> sentMonths = const {},
}) {
  final month = rentNoticeTargetMonth(today, dueDay: dueDay, sentMonths: sentMonths);
  return DateTime(month.year, month.month, _clampedDueDay(month.year, month.month, dueDay));
}

String rentMonthLabel(DateTime month) => '${_monthNames[month.month - 1]} ${month.year}';

/// Due date inside a notice month, clamped to that month's last day.
DateTime dueDateInMonth(DateTime month, {int? dueDay}) {
  return DateTime(month.year, month.month, _clampedDueDay(month.year, month.month, dueDay));
}

/// The rent month a notice belongs to when no rent_period was stored.
String rentPeriodLabel(DateTime submitted, {int? dueDay}) {
  final month = rentNoticeMonth(submitted, dueDay: dueDay);
  return '${_monthNames[month.month - 1]} ${month.year}';
}

/// Countdown for the due date the notice is actually counting.
String rentCountdownUntil(DateTime today, DateTime due) {
  final days = dateOnly(due).difference(dateOnly(today)).inDays;
  if (days < 0) return 'Late';
  if (days == 0) return 'Due today';
  if (days == 1) return '1 day';
  return '$days days';
}

String rentCountdownLabel(DateTime today, {int? dueDay}) {
  final days = daysUntilRentDue(today, dueDay: dueDay);
  if (days == 0) return 'Due today';
  if (days == 1) return '1 day';
  return '$days days';
}

/// First day of the month before the due date. A notice in that window
/// belongs to the upcoming due date.
DateTime rentPeriodStart(DateTime today, {int? dueDay}) {
  final due = nextRentDueDate(today, dueDay: dueDay);
  return DateTime(due.year, due.month - 1, 1);
}

bool paymentCoversRentPeriod(DateTime? submitted, DateTime today, {int? dueDay}) {
  if (submitted == null) return false;
  final start = rentPeriodStart(today, dueDay: dueDay);
  final due = nextRentDueDate(today, dueDay: dueDay);
  final end = DateTime(due.year, due.month + 1, 1);
  final day = dateOnly(submitted.toLocal());
  return !day.isBefore(start) && day.isBefore(end);
}

/// Month a confirmed payment is counted in. This is the due month the rent
/// notice named, never the month of `confirmed_at`.
///
/// [period] is that month when it was stored on the payment. Otherwise a
/// notice belongs to the due date that followed [submittedAt]. A payment
/// with neither a period nor a submission is not counted.
DateTime? confirmedRentMonth({
  DateTime? period,
  DateTime? submittedAt,
  int? dueDay,
  bool hasDueDay = true,
}) {
  if (period != null) {
    final day = period.isUtc ? period.toLocal() : period;
    return DateTime(day.year, day.month);
  }
  if (submittedAt == null) return null;
  return rentNoticeMonth(submittedAt, dueDay: hasDueDay ? dueDay : null);
}

bool isPendingRentStatus(String? status) {
  final value = (status ?? '').trim().toLowerCase();
  return value == 'pending' || value == 'pending_confirmation';
}

bool leaseDatesAreSet(DateTime? start, DateTime? end) =>
    start != null && end != null;

String countPhrase(int count, String singular, String plural) {
  final n = count < 0 ? 0 : count;
  return '$n ${n == 1 ? singular : plural}';
}

/// A password-reset or magic-link landing. `code` alone is not enough:
/// signup confirmation uses a code too.
bool urlHasRecovery({required String fragment, required String query}) {
  final blob = '$query&$fragment';
  if (RegExp(r'(?:^|[?&#])type=recovery(?:&|$)', caseSensitive: false)
      .hasMatch(blob)) {
    return true;
  }
  return fragment.contains('access_token=') &&
      blob.toLowerCase().contains('type=recovery');
}

/// App path stored in the URL fragment, ignoring the splash and auth tokens.
String? pendingAppPath(String fragment) {
  final raw = fragment.trim();
  if (raw.isEmpty) return null;
  if (raw.contains('access_token=') ||
      raw.toLowerCase().contains('type=recovery')) {
    return null;
  }
  final path = raw.split('?').first;
  if (!path.startsWith('/')) return null;
  if (path == '/' || path == '/splash') return null;
  return path;
}

String startupLocation({required String fragment, required String query}) {
  final pending = pendingAppPath(fragment);
  if (urlHasRecovery(fragment: fragment, query: query) ||
      pending == '/reset-password') {
    return '/reset-password';
  }
  return pending ?? '/splash';
}

/// Display label used by maintenance screens for a database status.
String mapMaintenanceStatus(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'open':
    case 'submitted':
      return 'Submitted';
    case 'assigned':
      return 'Assigned';
    case 'in_progress':
    case 'in progress':
      return 'In Progress';
    case 'resolved':
    case 'closed':
      return 'Resolved';
    default:
      return 'Submitted';
  }
}

/// Job-thread rows carry a maintenance request id. A database that has not
/// added that column yet has no key, and those rows stay 1:1 messages.
bool isJobChatMessage(Map<String, dynamic> row) {
  if (!row.containsKey('maintenance_request_id')) return false;
  final value = row['maintenance_request_id'];
  return value != null && value.toString().trim().isNotEmpty;
}

/// A repair job is finished when its status is resolved, closed, or completed.
/// The thread stays readable and does not take new messages.
bool maintenanceThreadIsClosed(String? status) {
  switch (status?.trim().toLowerCase()) {
    case 'resolved':
    case 'closed':
    case 'completed':
      return true;
    default:
      return false;
  }
}

/// A participant sees a job message only from the time they joined until
/// they left. That matches 1:1 chat: you keep messages you were party to,
/// and you do not see messages sent after you were removed.
bool jobMessageVisibleToParticipant({
  required DateTime messageAt,
  required DateTime joinedAt,
  DateTime? leftAt,
}) {
  if (messageAt.isBefore(joinedAt)) return false;
  if (leftAt != null && !messageAt.isBefore(leftAt)) return false;
  return true;
}

/// Push goes to the other people currently in the job thread.
List<String> jobChatNotifyIds({
  required String senderId,
  required Iterable<String> activeParticipantIds,
}) {
  final ids = <String>[];
  final seen = <String>{};
  for (final id in activeParticipantIds) {
    final trimmed = id.trim();
    if (trimmed.isEmpty || trimmed == senderId || !seen.add(trimmed)) continue;
    ids.add(trimmed);
  }
  return ids;
}

class JobChatParticipant {
  final String userId;
  final String name;
  final String role;
  final bool active;

  const JobChatParticipant({
    required this.userId,
    required this.name,
    required this.role,
    this.active = true,
  });

  String get roleLabel {
    switch (role.trim().toLowerCase()) {
      case 'landlord':
        return 'Landlord';
      case 'tenant':
        return 'Tenant';
      case 'vendor':
        return 'Vendor';
      default:
        return role;
    }
  }
}

/// Database value stored for a display status.
String maintenanceStatusToDb(String display) {
  switch (display.trim()) {
    case 'Submitted':
      return 'open';
    case 'Assigned':
      return 'assigned';
    case 'In Progress':
      return 'in_progress';
    case 'Resolved':
      return 'resolved';
    default:
      return 'open';
  }
}

/// Database status for a vendor job, whether the caller has the display
/// label or the stored value.
String vendorJobDbStatus(String currentStatus) =>
    maintenanceStatusToDb(mapMaintenanceStatus(currentStatus));

/// Status values a vendor may save. Assigned stays in the menu only while
/// the job is already assigned, so the current value is a real choice.
List<String> vendorJobStatusOptions(String currentStatus) {
  switch (vendorJobDbStatus(currentStatus)) {
    case 'assigned':
      return const ['assigned', 'in_progress', 'resolved'];
    case 'in_progress':
      return const ['in_progress', 'resolved'];
    case 'resolved':
      return const ['resolved'];
    default:
      return const ['in_progress', 'resolved'];
  }
}

/// Dropdown value that matches the job and is always one of [vendorJobStatusOptions].
String vendorJobStatusInitial(String currentStatus) {
  final db = vendorJobDbStatus(currentStatus);
  final options = vendorJobStatusOptions(currentStatus);
  return options.contains(db) ? db : options.first;
}

const Map<String, String> vendorJobStatusLabels = {
  'open': 'Submitted',
  'assigned': 'Assigned',
  'in_progress': 'In Progress',
  'resolved': 'Resolved',
};

/// Company line for the signed-in vendor. Checks metadata in order and
/// hides a blank value or one that repeats the person's name.
String vendorCompanyFromMetadata(Map<String, dynamic>? metadata, String? fullName) {
  final meta = metadata ?? const <String, dynamic>{};
  final name = (fullName ?? '').trim().toLowerCase();
  for (final key in const ['company_name', 'business_name', 'company']) {
    final value = meta[key]?.toString().trim() ?? '';
    if (value.isEmpty) continue;
    if (value.toLowerCase() == name) return '';
    return value;
  }
  return '';
}

/// First parseable timestamp among [keys]. Supports both column names the
/// app has used for a resolved maintenance request.
DateTime? firstParsedDate(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    final value = row[key];
    if (value == null) continue;
    if (value is DateTime) return value;
    final parsed = DateTime.tryParse(value.toString());
    if (parsed != null) return parsed;
  }
  return null;
}

/// Role stored on the account.
///
/// A non-default row role wins. When the users row was auto-created as
/// `landlord` but signup metadata has a real role, the metadata wins.
/// Blank values fall back to landlord, which is the app's default shell.
String resolveStoredRole({required String rowRole, required String metaRole}) {
  final row = rowRole.trim();
  final meta = metaRole.trim();
  if (row.isNotEmpty && row != 'landlord') return row;
  if (meta.isNotEmpty) return meta;
  if (row.isNotEmpty) return row;
  return 'landlord';
}

double occupancyRateFromCounts({
  required int occupiedUnits,
  required int totalUnits,
}) {
  if (totalUnits <= 0) return 0;
  return occupiedUnits / totalUnits;
}

/// Vacant, occupied, or partial when only some units on a property are filled.
String propertyOccupancyLabel({required int occupied, required int total}) {
  if (total <= 0 || occupied <= 0) return 'Vacant';
  if (occupied >= total) return 'Occupied';
  return 'Partial';
}

String homeRouteForRole(String? role) {
  switch (role) {
    case 'vendor':
      return '/vendor';
    case 'tenant':
      return '/tenant';
    default:
      return '/landlord';
  }
}

/// Where a signed-in user should be sent, or null to stay put.
/// Logged-out visitors may only open the auth screens.
String? authRedirect({
  required bool loggedIn,
  required String? role,
  required String destination,
  bool startLandlordCheckout = false,
  String? plan,
  String? status,
  DateTime? trialEndsAt,
  bool planChoiceRequired = false,
  DateTime? now,
  bool sessionReady = true,
  bool passwordRecovery = false,
}) {
  if (!sessionReady) return null;
  if (passwordRecovery) {
    return destination == '/reset-password' ? null : '/reset-password';
  }
  if (!loggedIn) {
    if (authEntryRoutes.contains(destination)) return null;
    return '/login';
  }

  final home = homeRouteForRole(role);
  if (destination == '/reset-password') return home;
  final mustChoose = landlordMustChoosePlan(
    role: role,
    plan: plan,
    status: status,
    trialEndsAt: trialEndsAt,
    planChoiceRequired: planChoiceRequired,
    now: now,
  );
  if (destination == '/login' ||
      destination == '/signup' ||
      destination == '/check-email') {
    if (mustChoose) return '/choose-plan';
    if (startLandlordCheckout && role != 'tenant' && role != 'vendor') {
      return '/choose-plan';
    }
    return home;
  }

  if (role == 'vendor') {
    final allowed = destination.startsWith('/vendor') ||
        destination.startsWith('/partners') ||
        destination == '/account/profile' ||
        destination == '/terms' ||
        destination == '/privacy';
    return allowed ? null : '/vendor';
  }

  if (role == 'tenant') {
    final allowed = destination.startsWith('/tenant') ||
        destination.startsWith('/partners') ||
        destination == '/account/profile' ||
        destination == '/terms' ||
        destination == '/privacy';
    return allowed ? null : '/tenant';
  }

  // Landlord and admin share the landlord shell. Admin may also open /admin.
  if (mustChoose) {
    if (destination == '/choose-plan' ||
        destination == '/terms' ||
        destination == '/privacy') {
      return null;
    }
    return '/choose-plan';
  }
  if (destination == '/choose-plan') return home;
  if (destination.startsWith('/tenant')) return '/landlord';
  if (destination.startsWith('/vendor')) return '/landlord';
  if (destination.startsWith('/admin') && role != 'admin') return '/landlord';
  return null;
}

/// Screen to open when a push notification is tapped.
String? notificationRoute({
  required String? role,
  required String type,
  String unitId = '',
}) {
  final tenant = role == 'tenant';
  final vendor = role == 'vendor';
  switch (type) {
    case 'message':
      if (tenant) return '/tenant/messages';
      if (vendor) {
        return unitId.isEmpty ? '/vendor/messages' : '/vendor/messages/$unitId';
      }
      return unitId.isEmpty
          ? '/landlord/messages'
          : '/landlord/messages/chat/$unitId';
    case 'rent_reminder':
    case 'rent_increase':
      return tenant ? '/tenant' : '/landlord';
    case 'rent_paid':
      return '/landlord';
    case 'lease_expiring':
      return tenant ? '/tenant' : '/landlord/more/calendar';
    case 'maintenance':
      if (vendor) return '/vendor/jobs';
      if (tenant) return '/tenant/maintenance';
      return '/landlord/more/maintenance';
    case 'vendor_approved':
    case 'vendor_declined':
      return '/vendor';
    case 'tenant_accepted':
      return '/landlord/properties';
    case 'screening_ready':
      return '/landlord/more/screening';
    case 'announcement':
      return tenant ? '/tenant/messages' : '/landlord/messages';
    default:
      return null;
  }
}

/// Live `documents` rows are owned by `owner_id` and also store `name`,
/// `file_type`, and `file_size`. The older names (`landlord_id`, `tenant_id`,
/// `file_name`, `doc_type`, `file_size_bytes`) are still on the table, so a
/// write fills both sets. `owner_id` is the signed-in uploader: the live
/// "Owner manages documents" policy allows the insert only when it matches.
Map<String, dynamic> documentInsertPayload({
  required String uid,
  required bool isLandlord,
  required String fileName,
  required String fileUrl,
  required String docType,
  required int fileSizeBytes,
  String? unitId,
  String? counterpartyId,
}) {
  return {
    'owner_id': uid,
    'name': fileName,
    'file_type': docType,
    'file_size': fileSizeBytes,
    if (isLandlord) 'landlord_id': uid,
    if (!isLandlord) 'tenant_id': uid,
    if (!isLandlord && counterpartyId != null && counterpartyId.isNotEmpty)
      'landlord_id': counterpartyId,
    if (isLandlord && counterpartyId != null && counterpartyId.isNotEmpty)
      'tenant_id': counterpartyId,
    if (unitId != null && unitId.isNotEmpty) 'unit_id': unitId,
    'file_name': fileName,
    'file_url': fileUrl,
    'doc_type': docType,
    'file_size_bytes': fileSizeBytes,
  };
}

String documentsOrFilter(String uid) =>
    'owner_id.eq.$uid,landlord_id.eq.$uid,tenant_id.eq.$uid';

const repairPhotoLimit = 5;
const repairPhotoBucket = 'maintenance-photos';
const repairPhotoMaxSide = 1600;
const repairPhotoJpegQuality = 80;

/// Resize so the longest side is at most [repairPhotoMaxSide] and re-encode
/// as JPEG. Bytes that cannot be decoded (for example a HEIC file the
/// platform has not already converted) are returned unchanged so the upload
/// still works.
Uint8List shrinkRepairPhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > repairPhotoMaxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: repairPhotoMaxSide)
        : img.copyResize(image, height: repairPhotoMaxSide);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: repairPhotoJpegQuality));
}

/// Storage name for a photo that was re-encoded as JPEG.
String repairPhotoJpegName(String fileName) {
  final safe = storageSafeFileName(fileName);
  final dot = safe.lastIndexOf('.');
  final stem = dot <= 0 ? safe : safe.substring(0, dot);
  return '${stem.isEmpty ? 'photo' : stem}.jpg';
}

/// `{tenant}/{request}/{time}_{file}` so the existing repair-photo rule
/// can match the request id in the second folder.
String repairPhotoStoragePath({
  required String tenantId,
  required String requestId,
  required String fileName,
  required int timestamp,
}) {
  return '$requestId/${timestamp}_${storageSafeFileName(fileName)}';
}

/// Paths stored on a repair. A signed or public URL is reduced to a path.
List<String> repairPhotoPaths(dynamic raw) {
  if (raw is! List) return const [];
  final paths = <String>[];
  for (final item in raw) {
    final path = storageObjectPath(item?.toString(), repairPhotoBucket);
    if (path == null || path.isEmpty) continue;
    paths.add(path);
  }
  return paths;
}

/// Landlord of the unit, the vendor on this job, or the tenant who lives
/// there now when the repair was opened during their tenancy.
bool canReadRepairPhoto({
  required bool isUnitLandlord,
  required bool isCurrentTenant,
  required bool requestCreatedDuringTenancy,
  required bool isAssignedVendor,
}) {
  if (isUnitLandlord || isAssignedVendor) return true;
  return isCurrentTenant && requestCreatedDuringTenancy;
}

/// Storage object keys reject spaces and punctuation. The original name
/// stays on the document row for display.
String storageSafeFileName(String name) {
  final base = name.split(RegExp(r'[\\/]')).last.trim();
  final cleaned = base.replaceAll(RegExp(r'[^\w.\-]'), '_');
  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return 'file';
  return cleaned;
}

/// Path inside [bucket]. A bare path is kept. An older public or signed
/// URL is reduced to the path, and the token query string is dropped.
String? storageObjectPath(String? stored, String bucket) {
  final value = stored?.trim() ?? '';
  if (value.isEmpty || bucket.trim().isEmpty) return null;
  final markers = [
    '/object/public/$bucket/',
    '/object/sign/$bucket/',
    '/object/authenticated/$bucket/',
  ];
  for (final marker in markers) {
    final index = value.indexOf(marker);
    if (index == -1) continue;
    var path = value.substring(index + marker.length);
    final query = path.indexOf('?');
    if (query != -1) path = path.substring(0, query);
    if (path.isEmpty) return null;
    return Uri.decodeComponent(path);
  }
  if (value.contains('://')) return null;
  return value;
}

/// Path inside the photo-logs bucket.
///
/// New rows store the path. Older rows stored a public or signed URL.
String? photoLogObjectPath(String? stored) =>
    storageObjectPath(stored, 'photo-logs');

/// `{uploader}/maintenance/{request}/{time}_{file}` in the documents bucket.
/// The maintenance folder is readable by the assigned vendor. The unit
/// folder and the unit chat folder are not.
String jobChatAttachmentPath({
  required String uploaderId,
  required String requestId,
  required String fileName,
  required int timestamp,
}) {
  return '$uploaderId/maintenance/$requestId/${timestamp}_${storageSafeFileName(fileName)}';
}

/// Message text for a chat file. The second line is the storage path,
/// never a signed URL.
String chatFileMessage(String fileName, String path) =>
    'Shared a file: ${fileName.trim()}\n$path';

/// A file shared in chat, whether the stored line is a path or an old URL.
class StoredChatFile {
  final String label;
  final String path;

  const StoredChatFile({required this.label, required this.path});
}

StoredChatFile? storedChatFile(String text) {
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i].trim();
    if (raw.isEmpty) continue;
    final path = storageObjectPath(raw, 'documents');
    if (path == null || !path.contains('/')) continue;
    final looksStored = raw.contains('://') ||
        (i > 0 && lines[i - 1].trim().startsWith('Shared a file:'));
    if (!looksStored) continue;
    var label = 'Shared file';
    if (i > 0 && lines[i - 1].trim().startsWith('Shared a file:')) {
      label = lines[i - 1].trim().substring('Shared a file:'.length).trim();
    }
    if (label.isEmpty) label = 'Shared file';
    return StoredChatFile(label: label, path: path);
  }
  return null;
}

const propertyDeleteBlockedMessage = 'Move the tenant out of every unit first.';

/// Plain sentence for records the database keeps, so delete is not attempted.
/// Returns null when nothing listed is still attached.
String? historyBlocksDeleteMessage({
  required String subject,
  required int documents,
  required int photoLogs,
  required int calendarEvents,
  required int screenings,
}) {
  String label(int count, String singular, String plural) =>
      '$count ${count == 1 ? singular : plural}';
  final parts = <String>[
    if (documents > 0) label(documents, 'document', 'documents'),
    if (photoLogs > 0) label(photoLogs, 'photo log', 'photo logs'),
    if (calendarEvents > 0) label(calendarEvents, 'calendar event', 'calendar events'),
    if (screenings > 0) label(screenings, 'screening', 'screenings'),
  ];
  if (parts.isEmpty) return null;
  final joined = parts.length == 1
      ? parts.single
      : parts.length == 2
          ? '${parts[0]} and ${parts[1]}'
          : '${parts.sublist(0, parts.length - 1).join(', ')}, and ${parts.last}';
  final pronoun = parts.length == 1 ? 'it' : 'them';
  return 'This $subject still has $joined. Remove $pronoun first to delete it.';
}

/// True when a unit still has someone living there, matching the delete block.
bool unitStillHasTenant({String? status, String? tenantId}) {
  final tenant = tenantId?.trim() ?? '';
  return tenant.isNotEmpty || (status ?? '').trim().toLowerCase() == 'occupied';
}

/// Columns cleared when a landlord moves the current tenant out.
/// `tenant_since` is set by the database trigger, not by this map.
Map<String, dynamic> unitMoveOutUpdate() => {
      'tenant_id': null,
      'tenant_name': null,
      'invited_email': null,
      'status': 'vacant',
    };

/// Prefer the newer file name, then the live `name` column.
String documentFileName(Map<String, dynamic> row) {
  for (final key in ['file_name', 'name']) {
    final value = row[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return 'Document';
}

/// Prefer `doc_type`, then the live `file_type` column.
String documentDocType(Map<String, dynamic> row) {
  for (final key in ['doc_type', 'file_type']) {
    final value = row[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return 'Other';
}

int documentFileSize(Map<String, dynamic> row) {
  for (final key in ['file_size_bytes', 'file_size']) {
    final value = row[key];
    if (value is num) return value.toInt();
  }
  return 0;
}

/// Live `vendor_contacts` stores who sent a note about a directory listing.
/// It has `sender_id`, `listing_id`, and `message` — not `vendor_id`.
Map<String, dynamic> vendorContactInsert({
  required String listingId,
  required String senderId,
  required String message,
}) {
  return {
    'listing_id': listingId,
    'sender_id': senderId,
    'message': message,
  };
}

/// A directory listing may only have the live `name` column filled in.
String partnerBusinessName(Map<String, dynamic> row) {
  for (final key in ['business_name', 'name']) {
    final value = row[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

/// Closing a job writes the live `resolved_date` and the columns the app
/// already reads (`resolved_at`, `completed_at`).
Map<String, String> maintenanceCloseTimestamps(DateTime when) {
  final stamp = when.toUtc().toIso8601String();
  return {
    'resolved_at': stamp,
    'resolved_date': stamp,
    'completed_at': stamp,
  };
}

/// Ids that can appear on a maintenance row for this vendor account.
/// Includes the auth user id and any landlord directory rows that share
/// the vendor's email.
List<String> maintenanceVendorIds({
  required String authUserId,
  required Iterable<String> directoryVendorIds,
}) {
  final ids = <String>{
    if (authUserId.isNotEmpty) authUserId,
    ...directoryVendorIds.where((id) => id.trim().isNotEmpty),
  };
  return ids.toList();
}

String initialsFor(String fullName) {
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  if (parts.isNotEmpty) return parts[0][0].toUpperCase();
  return '?';
}

const blockedMessageTerms = <String>[
  'fuck',
  'shit',
  'bitch',
  'asshole',
  'bastard',
  'cunt',
  'damn',
  'piss',
  'kill',
  'murder',
  'threaten',
  'attack',
  'hurt you',
  'find you',
  'click here',
  'bit.ly',
  'free money',
  'cash prize',
  'winner',
];

/// Who a reply in an existing unit chat should go to.
///
/// A named counterparty wins (tenant talking to one vendor, or the reverse).
/// The unit's landlord, looking at the whole unit, replies to whoever wrote
/// last. A vendor's general messages screen replies to the landlord.
String? chatReplyReceiver({
  required String me,
  required String? landlordId,
  required String? tenantId,
  String? counterpartyId,
  required List<String> senderIdsOldestFirst,
}) {
  final named = counterpartyId?.trim() ?? '';
  if (named.isNotEmpty) return named;
  final isLandlord = landlordId != null && landlordId.isNotEmpty && me == landlordId;
  final isTenant = tenantId != null && tenantId.isNotEmpty && me == tenantId;
  if (isTenant) return landlordId;
  for (final sender in senderIdsOldestFirst.reversed) {
    if (sender.isNotEmpty && sender != me && sender != 'system') return sender;
  }
  return isLandlord ? tenantId : landlordId;
}

/// Whether this viewer should see one message.
///
/// The unit's landlord sees the whole unit, including tenant-vendor notes.
/// Everyone else sees only the conversation with [counterpartyId].
bool chatMessageVisible({
  required String me,
  required String? landlordId,
  required String? counterpartyId,
  required String senderId,
  required String receiverId,
}) {
  final viewerIsLandlord =
      landlordId != null && landlordId.isNotEmpty && me == landlordId;
  final party = counterpartyId?.trim() ?? '';
  if (viewerIsLandlord && party.isEmpty) return true;
  if (senderId == 'system') {
    return party.isEmpty || party == landlordId;
  }
  if (party.isEmpty) {
    return senderId == me || receiverId == me;
  }
  return senderId == party || receiverId == party;
}

const _chatMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Reads a Supabase `timestamptz` value as an absolute instant.
///
/// PostgREST usually includes an offset. A bare clock with no zone is still
/// UTC (`timestamptz` / `now()`), not the phone's local time.
DateTime? parseServerTimestamp(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is! String) return null;
  final raw = value.trim();
  if (raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  if (_timestampHasZone(raw)) return parsed;
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  );
}

bool _timestampHasZone(String raw) {
  if (raw.endsWith('Z') || raw.endsWith('z')) return true;
  return RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw);
}

/// Local chat clock: `3:42 PM` today, `Yesterday 3:42 PM`, otherwise a date
/// plus that time. [now] is injectable so tests can pin the calendar day.
String formatChatTimestamp(DateTime createdAt, {DateTime? now}) {
  final local = createdAt.toLocal();
  final clock = (now ?? DateTime.now()).toLocal();
  final time = _chatClock(local);
  final today = DateTime(clock.year, clock.month, clock.day);
  final day = DateTime(local.year, local.month, local.day);
  if (day == today) return time;
  if (day == today.subtract(const Duration(days: 1))) {
    return 'Yesterday $time';
  }
  final date = local.year == clock.year
      ? '${_chatMonths[local.month - 1]} ${local.day}'
      : '${_chatMonths[local.month - 1]} ${local.day}, ${local.year}';
  return '$date, $time';
}

String _chatClock(DateTime local) {
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

bool containsBlockedLanguage(String text) {
  final lower = text.toLowerCase();
  for (final term in blockedMessageTerms) {
    if (lower.contains(term)) return true;
  }
  return false;
}

class NotificationPreferenceSnapshot {
  final bool pushEnabled;
  final bool emailEnabled;
  final bool smsEnabled;
  final Map<String, bool> events;

  const NotificationPreferenceSnapshot({
    required this.pushEnabled,
    required this.emailEnabled,
    required this.smsEnabled,
    required this.events,
  });
}

NotificationPreferenceSnapshot parseNotificationPreferences(
  Map<String, dynamic>? row, {
  bool defaultPush = true,
  bool defaultEmail = true,
  bool defaultSms = false,
}) {
  if (row == null) {
    return NotificationPreferenceSnapshot(
      pushEnabled: defaultPush,
      emailEnabled: defaultEmail,
      smsEnabled: defaultSms,
      events: const {},
    );
  }
  final rawEvents = row['events'];
  final events = <String, bool>{};
  if (rawEvents is Map) {
    rawEvents.forEach((key, value) {
      if (value is bool) events[key.toString()] = value;
    });
  }
  return NotificationPreferenceSnapshot(
    pushEnabled: row['push_enabled'] is bool
        ? row['push_enabled'] as bool
        : defaultPush,
    emailEnabled: row['email_enabled'] is bool
        ? row['email_enabled'] as bool
        : defaultEmail,
    smsEnabled:
        row['sms_enabled'] is bool ? row['sms_enabled'] as bool : defaultSms,
    events: events,
  );
}

Map<String, dynamic> notificationPreferencePayload({
  required String userId,
  required NotificationPreferenceSnapshot snapshot,
  required DateTime updatedAt,
  bool includeExtendedColumns = true,
}) {
  return {
    'user_id': userId,
    'push_enabled': snapshot.pushEnabled,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    if (includeExtendedColumns) ...{
      'email_enabled': snapshot.emailEnabled,
      'sms_enabled': snapshot.smsEnabled,
      'events': snapshot.events,
    },
  };
}

// ── Landlord payment instructions ──────────────────────────────────────────
//
// Stored on public.payment_methods (one row per landlord). The flat columns
// match supabase/practice/00_reconstructed_base_schema.sql. The `methods`
// list is added by supabase/payment_methods_access.sql and is what the
// screens edit. Elevo never charges the tenant; these are instructions only.

const paymentMethodKinds = <String>[
  'zelle',
  'venmo',
  'cash_app',
  'paypal',
  'bank_transfer',
  'check',
  'cash',
  'other',
];

String paymentMethodKindLabel(String kind) {
  switch (kind) {
    case 'zelle':
      return 'Zelle';
    case 'venmo':
      return 'Venmo';
    case 'cash_app':
      return 'Cash App';
    case 'paypal':
      return 'PayPal';
    case 'bank_transfer':
      return 'Bank Transfer';
    case 'check':
      return 'Check';
    case 'cash':
      return 'Cash';
    default:
      return 'Other';
  }
}

String normalizePaymentMethodKind(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'zelle':
      return 'zelle';
    case 'venmo':
      return 'venmo';
    case 'cashapp':
    case 'cash_app':
    case 'cash app':
      return 'cash_app';
    case 'paypal':
      return 'paypal';
    case 'bank':
    case 'bank_transfer':
    case 'bank transfer':
      return 'bank_transfer';
    case 'check':
      return 'check';
    case 'cash':
      return 'cash';
    default:
      return 'other';
  }
}

class LandlordPaymentMethod {
  final String id;
  final String kind;
  final String handle;
  final String instructions;
  final int sortOrder;
  final String? bankRouting;
  final String? bankAccount;

  const LandlordPaymentMethod({
    required this.id,
    required this.kind,
    this.handle = '',
    this.instructions = '',
    this.sortOrder = 0,
    this.bankRouting,
    this.bankAccount,
  });

  bool get hasContent {
    return handle.trim().isNotEmpty ||
        instructions.trim().isNotEmpty ||
        (bankRouting ?? '').trim().isNotEmpty ||
        (bankAccount ?? '').trim().isNotEmpty;
  }

  /// Name shown to the tenant.
  String get title {
    if (kind == 'other') {
      final name = handle.trim();
      return name.isEmpty ? 'Other' : name;
    }
    if (kind == 'bank_transfer' && handle.trim().isNotEmpty) {
      return 'Bank Transfer (${handle.trim()})';
    }
    return paymentMethodKindLabel(kind);
  }

  /// Handle and instructions, ready to read or copy.
  String get detail {
    final lines = <String>[];
    if (kind == 'bank_transfer') {
      final routing = (bankRouting ?? '').trim();
      final account = (bankAccount ?? '').trim();
      if (routing.isNotEmpty) lines.add('Routing: $routing');
      if (account.isNotEmpty) lines.add('Account: $account');
      if (instructions.trim().isNotEmpty) lines.add(instructions.trim());
    } else if (kind == 'check') {
      if (handle.trim().isNotEmpty) lines.add('Payable to: ${handle.trim()}');
      if (instructions.trim().isNotEmpty) lines.add(instructions.trim());
    } else if (kind == 'other') {
      if (instructions.trim().isNotEmpty) lines.add(instructions.trim());
    } else {
      if (handle.trim().isNotEmpty) lines.add(handle.trim());
      if (instructions.trim().isNotEmpty) lines.add(instructions.trim());
    }
    return lines.join('\n');
  }

  String get copyText {
    final body = detail.trim();
    if (body.isNotEmpty) return body;
    return handle.trim();
  }

  LandlordPaymentMethod copyWith({
    String? id,
    String? kind,
    String? handle,
    String? instructions,
    int? sortOrder,
    String? bankRouting,
    String? bankAccount,
    bool clearBankRouting = false,
    bool clearBankAccount = false,
  }) {
    return LandlordPaymentMethod(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      handle: handle ?? this.handle,
      instructions: instructions ?? this.instructions,
      sortOrder: sortOrder ?? this.sortOrder,
      bankRouting: clearBankRouting ? null : (bankRouting ?? this.bankRouting),
      bankAccount: clearBankAccount ? null : (bankAccount ?? this.bankAccount),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind,
      'handle': handle.trim(),
      'instructions': instructions.trim(),
      'sort_order': sortOrder,
      'bank_routing': _nullIfBlank(bankRouting),
      'bank_account': _nullIfBlank(bankAccount),
    };
  }
}

class UnitLandlordLink {
  final String? tenantId;
  final String? invitedEmail;
  final String? unitLandlordId;
  final String? propertyLandlordId;

  const UnitLandlordLink({
    this.tenantId,
    this.invitedEmail,
    this.unitLandlordId,
    this.propertyLandlordId,
  });
}

String? _nullIfBlank(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return trimmed;
}

String _text(dynamic value) => value?.toString().trim() ?? '';

/// Landlord whose instructions this tenant should see.
/// The unit's own landlord wins. The property landlord is only a fallback
/// when the unit row has no landlord id.
String? landlordIdForTenantPaymentMethods({
  String? unitLandlordId,
  String? propertyLandlordId,
}) {
  final unit = unitLandlordId?.trim() ?? '';
  if (unit.isNotEmpty) return unit;
  final property = propertyLandlordId?.trim() ?? '';
  if (property.isNotEmpty) return property;
  return null;
}

/// Same rule as public.my_unit_landlord_ids() in
/// supabase/payment_methods_access.sql.
bool tenantMayReadLandlordPaymentMethods({
  required String methodLandlordId,
  required String? viewerId,
  required String? viewerEmail,
  required List<UnitLandlordLink> links,
}) {
  final target = methodLandlordId.trim();
  final viewer = viewerId?.trim() ?? '';
  final email = viewerEmail?.trim().toLowerCase() ?? '';
  if (target.isEmpty || viewer.isEmpty) return false;
  for (final link in links) {
    final landlord = landlordIdForTenantPaymentMethods(
      unitLandlordId: link.unitLandlordId,
      propertyLandlordId: link.propertyLandlordId,
    );
    if (landlord != target) continue;
    if ((link.tenantId ?? '').trim() == viewer) return true;
    final invited = (link.invitedEmail ?? '').trim().toLowerCase();
    if (email.isNotEmpty && invited.isNotEmpty && invited == email) {
      return true;
    }
  }
  return false;
}

List<LandlordPaymentMethod> landlordPaymentMethodsFromRows(List rows) {
  final maps = <Map<String, dynamic>>[];
  for (final row in rows) {
    if (row is Map) maps.add(Map<String, dynamic>.from(row));
  }
  maps.sort((a, b) => _rowStamp(b).compareTo(_rowStamp(a)));
  for (final row in maps) {
    final parsed = landlordPaymentMethodsFromRow(row);
    if (parsed.isNotEmpty) return parsed;
  }
  return const [];
}

List<LandlordPaymentMethod> landlordPaymentMethodsFromRow(
  Map<String, dynamic> row,
) {
  final fromList = _methodsFromJson(row['methods']);
  if (fromList.isNotEmpty) return _sorted(fromList);
  return _methodsFromFlatColumns(row);
}

/// users.payment_methods jsonb, including the older key names.
List<LandlordPaymentMethod> userPaymentMethodsFromJson(dynamic raw) {
  if (raw is String && raw.trim().isNotEmpty) {
    return _methodsFromFlatColumns(_decodeMap(raw));
  }
  if (raw is Map) {
    return _methodsFromFlatColumns(Map<String, dynamic>.from(raw));
  }
  return const [];
}

Map<String, dynamic> _decodeMap(String raw) {
  try {
    final decoded = _jsonDecode(raw);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return const {};
}

dynamic _jsonDecode(String raw) {
  // Local import-free decode so this file stays a single library.
  // dart:convert is imported at the top of the call via a top-level function
  // defined below after the import is added.
  return jsonDecode(raw);
}

DateTime _rowStamp(Map<String, dynamic> row) {
  final updated = DateTime.tryParse(_text(row['updated_at']));
  final created = DateTime.tryParse(_text(row['created_at']));
  return updated ?? created ?? DateTime.fromMillisecondsSinceEpoch(0);
}

List<LandlordPaymentMethod> _methodsFromJson(dynamic raw) {
  dynamic value = raw;
  if (value is String && value.trim().isNotEmpty) {
    try {
      value = jsonDecode(value);
    } catch (_) {
      return const [];
    }
  }
  if (value is! List || value.isEmpty) return const [];
  final items = <LandlordPaymentMethod>[];
  for (final entry in value) {
    if (entry is! Map) continue;
    final map = Map<String, dynamic>.from(entry);
    final method = LandlordPaymentMethod(
      id: _text(map['id']).isEmpty
          ? 'method-${items.length}'
          : _text(map['id']),
      kind: normalizePaymentMethodKind(map['kind']?.toString()),
      handle: _text(map['handle']),
      instructions: _text(map['instructions']),
      sortOrder: int.tryParse('${map['sort_order']}') ?? items.length,
      bankRouting: _nullIfBlank(map['bank_routing']?.toString()),
      bankAccount: _nullIfBlank(map['bank_account']?.toString()),
    );
    if (method.hasContent) items.add(method);
  }
  return items;
}

List<LandlordPaymentMethod> _methodsFromFlatColumns(Map<String, dynamic> row) {
  final items = <LandlordPaymentMethod>[];
  void add(LandlordPaymentMethod method) {
    if (method.hasContent) items.add(method.copyWith(sortOrder: items.length));
  }

  add(LandlordPaymentMethod(
    id: 'flat-zelle',
    kind: 'zelle',
    handle: _text(row['zelle']),
  ));
  add(LandlordPaymentMethod(
    id: 'flat-venmo',
    kind: 'venmo',
    handle: _text(row['venmo']),
  ));
  add(LandlordPaymentMethod(
    id: 'flat-cashapp',
    kind: 'cash_app',
    handle: _firstText(row, const ['cashapp', 'cash_app']),
  ));
  add(LandlordPaymentMethod(
    id: 'flat-paypal',
    kind: 'paypal',
    handle: _text(row['paypal']),
  ));

  final bankName = _text(row['bank_name']);
  final routing = _firstText(row, const ['bank_routing', 'routing']);
  final account = _firstText(row, const ['bank_account', 'account']);
  add(LandlordPaymentMethod(
    id: 'flat-bank',
    kind: 'bank_transfer',
    handle: bankName,
    bankRouting: _nullIfBlank(routing),
    bankAccount: _nullIfBlank(account),
  ));

  final checkPayable = _firstText(row, const ['check_payable', 'check']);
  add(LandlordPaymentMethod(
    id: 'flat-check',
    kind: 'check',
    handle: checkPayable,
  ));
  final cashNote = _firstText(row, const ['cash_instructions', 'cash']);
  add(LandlordPaymentMethod(
    id: 'flat-cash',
    kind: 'cash',
    handle: cashNote,
  ));

  final otherName = _text(row['other_method']);
  final otherNote = _text(row['other_instructions']);
  if (otherName.isNotEmpty || otherNote.isNotEmpty) {
    final kind = _classifyOther(otherName);
    final already = items.any((method) => method.kind == kind && kind != 'other');
    if (!already) {
      final named = kind == 'other' &&
          otherName.isNotEmpty &&
          otherName.toLowerCase() != 'other';
      add(LandlordPaymentMethod(
        id: 'flat-other',
        kind: kind,
        handle: named
            ? otherName
            : (kind == 'check' || kind == 'cash' ? '' : otherName),
        instructions: otherNote.isNotEmpty
            ? otherNote
            : (named ? '' : otherName),
      ));
    }
  }
  return items;
}

String _classifyOther(String name) {
  final normalized = name.trim().toLowerCase();
  if (normalized == 'check' ||
      normalized == 'checks' ||
      normalized == 'personal check') {
    return 'check';
  }
  if (normalized == 'cash' || normalized == 'cash payment') return 'cash';
  return 'other';
}

String _firstText(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    final value = _text(row[key]);
    if (value.isNotEmpty) return value;
  }
  return '';
}

List<LandlordPaymentMethod> _sorted(List<LandlordPaymentMethod> items) {
  final copy = [...items]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return [
    for (var i = 0; i < copy.length; i++) copy[i].copyWith(sortOrder: i),
  ];
}

List<LandlordPaymentMethod> upsertPaymentMethod(
  List<LandlordPaymentMethod> methods,
  LandlordPaymentMethod method,
) {
  final next = [...methods];
  final index = next.indexWhere((item) => item.id == method.id);
  if (index >= 0) {
    next[index] = method;
  } else {
    next.add(method.copyWith(sortOrder: next.length));
  }
  return _sorted(next);
}

List<LandlordPaymentMethod> withoutPaymentMethod(
  List<LandlordPaymentMethod> methods,
  String id,
) {
  return _sorted(methods.where((method) => method.id != id).toList());
}

List<LandlordPaymentMethod> movePaymentMethod(
  List<LandlordPaymentMethod> methods,
  int index,
  int delta,
) {
  final target = index + delta;
  if (index < 0 ||
      index >= methods.length ||
      target < 0 ||
      target >= methods.length) {
    return [
      for (var i = 0; i < methods.length; i++) methods[i].copyWith(sortOrder: i),
    ];
  }
  final next = [...methods];
  final item = next.removeAt(index);
  next.insert(target, item);
  return [
    for (var i = 0; i < next.length; i++) next[i].copyWith(sortOrder: i),
  ];
}

String? validatePaymentMethodDraft({
  required String kind,
  String handle = '',
  String instructions = '',
  String? bankRouting,
  String? bankAccount,
}) {
  final method = LandlordPaymentMethod(
    id: 'draft',
    kind: normalizePaymentMethodKind(kind),
    handle: handle,
    instructions: instructions,
    bankRouting: bankRouting,
    bankAccount: bankAccount,
  );
  if (!method.hasContent) {
    return 'Add a handle or instructions';
  }
  return null;
}

/// Columns written to public.payment_methods. Flat columns stay filled so
/// an older reader still sees Zelle, Venmo, and the bank numbers.
Map<String, dynamic> paymentMethodsWritePayload({
  required String landlordId,
  required List<LandlordPaymentMethod> methods,
  required DateTime updatedAt,
  bool includeLandlordId = true,
}) {
  final ordered = _sorted(methods.where((method) => method.hasContent).toList());
  LandlordPaymentMethod? firstOf(String kind) {
    for (final method in ordered) {
      if (method.kind == kind) return method;
    }
    return null;
  }

  final bank = firstOf('bank_transfer');
  final check = firstOf('check');
  final cash = firstOf('cash');
  final other = firstOf('other');
  String? otherMethod;
  String? otherInstructions;
  if (check != null) {
    otherMethod = 'Check';
    otherInstructions = _nullIfBlank(check.detail);
  } else if (cash != null) {
    otherMethod = 'Cash';
    otherInstructions = _nullIfBlank(
      cash.instructions.trim().isNotEmpty ? cash.instructions : cash.handle,
    );
  } else if (other != null) {
    otherMethod = _nullIfBlank(other.handle) ?? 'Other';
    otherInstructions = _nullIfBlank(other.instructions);
  }

  return {
    if (includeLandlordId) 'landlord_id': landlordId,
    'zelle': _nullIfBlank(firstOf('zelle')?.handle),
    'venmo': _nullIfBlank(firstOf('venmo')?.handle),
    'cashapp': _nullIfBlank(firstOf('cash_app')?.handle),
    'paypal': _nullIfBlank(firstOf('paypal')?.handle),
    'bank_name': _nullIfBlank(bank?.handle),
    'bank_routing': _nullIfBlank(bank?.bankRouting),
    'bank_account': _nullIfBlank(bank?.bankAccount),
    'other_method': otherMethod,
    'other_instructions': otherInstructions,
    'methods': [for (final method in ordered) method.toJson()],
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

bool paymentMethodWriteReturnedRows(List<dynamic>? rows) {
  return rows != null && rows.isNotEmpty;
}

// ── Property and unit forms ────────────────────────────────────────────────

String propertyDisplayName(String address, String address2) {
  final street = address.trim();
  final line2 = address2.trim();
  if (street.isEmpty) return '';
  if (line2.isEmpty) return street;
  return '$street $line2';
}

String? validatePropertyAddress(String? value) {
  if (value == null || value.trim().isEmpty) return 'Address is required';
  return null;
}

String? validatePropertyCity(String? value) {
  if (value == null || value.trim().isEmpty) return 'City is required';
  return null;
}

/// Five-digit ZIP. Arizona addresses must fall in the Arizona range.
String? validatePropertyZip(String? raw, {String state = 'AZ'}) {
  final zip = raw?.trim() ?? '';
  if (!RegExp(r'^\d{5}$').hasMatch(zip)) {
    return 'Enter a 5-digit ZIP code';
  }
  final normalizedState = state.trim().toUpperCase();
  if (normalizedState.isEmpty || normalizedState == 'AZ') {
    final number = int.parse(zip);
    if (number < 85001 || number > 86556) {
      return 'Enter an Arizona ZIP code';
    }
  }
  return null;
}

const propertyTypeOptions = <String>[
  'House',
  'Condo',
  'Townhouse',
  'Apartment',
  'Duplex',
  'Other',
];

/// Empty means the landlord has not chosen a type. A known label is
/// returned with the list's capitalization. Anything else is kept as typed
/// so an older value is not wiped.
String? normalizePropertyType(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;
  for (final option in propertyTypeOptions) {
    if (option.toLowerCase() == value.toLowerCase()) return option;
  }
  return value;
}

Map<String, dynamic> propertyWritePayload({
  required String address,
  required String address2,
  required String city,
  required String zip,
  String? state,
  String? landlordId,
  String? propertyType,
}) {
  final storedState = (state == null || state.trim().isEmpty)
      ? 'AZ'
      : state.trim().toUpperCase();
  return {
    if (landlordId != null && landlordId.isNotEmpty) 'landlord_id': landlordId,
    'name': propertyDisplayName(address, address2),
    'address': address.trim(),
    'address2': address2.trim(),
    'city': city.trim(),
    'state': storedState,
    'zip': zip.trim(),
    'property_type': normalizePropertyType(propertyType),
  };
}

/// Stored in properties.image_url. The first folder is the landlord id so
/// the existing documents storage rule lets them read it back.
String propertyPhotoStoragePath({
  required String landlordId,
  required String propertyId,
  required String fileName,
  required int timestamp,
}) {
  final base = fileName.split(RegExp(r'[\\/]')).last;
  final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final cleaned = safe.isEmpty ? 'photo.jpg' : safe;
  return '$landlordId/property_$propertyId/${timestamp}_$cleaned';
}

/// Path inside the documents bucket, or null when [stored] is already a URL
/// or empty. New photos are saved as `documents/<path>`.
String? propertyPhotoObjectPath(String? stored) {
  final value = stored?.trim() ?? '';
  const prefix = 'documents/';
  if (!value.startsWith(prefix)) return null;
  final path = value.substring(prefix.length);
  if (path.isEmpty) return null;
  return path;
}

const unitStatusOptions = <String>['vacant', 'occupied', 'notice'];

bool isKnownUnitStatus(String status) => unitStatusOptions.contains(status);

double? parseMoneyAmount(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  var text = value.toString().trim();
  if (text.isEmpty) return null;
  text = text.replaceAll('\$', '').replaceAll(',', '').trim();
  return double.tryParse(text);
}

String? validateMoneyField(String? raw, {required bool requiredField}) {
  final text = (raw ?? '').trim().replaceAll('\$', '').replaceAll(',', '');
  if (text.isEmpty) {
    return requiredField ? 'Enter a valid amount' : null;
  }
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) {
    return 'Enter a valid amount';
  }
  final amount = double.tryParse(text);
  if (amount == null || amount < 0) return 'Enter a valid amount';
  if (requiredField && amount <= 0) return 'Enter a valid amount';
  return null;
}

String formatDateColumn(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

/// Reads a date column without shifting the calendar day across time zones.
DateTime? parseDateColumn(dynamic value) {
  final text = value?.toString() ?? '';
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(year, month, day);
}

String? validateLeaseDates(DateTime? start, DateTime? end) {
  if (start != null && end != null && end.isBefore(start)) {
    return 'Lease end date must be on or after the start date';
  }
  return null;
}

/// Whole number from 0 (a studio) through 20. Blank is allowed.
int? parseBedrooms(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  final amount = parseMoneyAmount(text);
  if (amount == null || amount != amount.roundToDouble()) return null;
  final bedrooms = amount.round();
  if (bedrooms < 0 || bedrooms > 20) return null;
  return bedrooms;
}

String? validateBedrooms(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  if (parseBedrooms(text) == null) {
    return 'Enter a whole number from 0 to 20';
  }
  return null;
}

/// Bathrooms from 0 to 20 in half steps (0, 0.5, 1, 1.5). Blank is allowed.
double? parseBathrooms(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  final amount = parseMoneyAmount(text);
  if (amount == null || amount < 0 || amount > 20) return null;
  final doubled = amount * 2;
  if ((doubled - doubled.round()).abs() > 0.001) return null;
  return doubled.round() / 2;
}

String? validateBathrooms(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  if (parseBathrooms(text) == null) {
    return 'Enter bathrooms from 0 to 20, in half steps';
  }
  return null;
}

String formatBathrooms(double bathrooms) {
  if (bathrooms == bathrooms.roundToDouble()) {
    return bathrooms.toStringAsFixed(0);
  }
  return bathrooms.toStringAsFixed(1);
}

/// Short line for a unit card, such as "Studio · 1 bath" or "2 bed · 1.5 bath".
String? unitSizeLabel({int? bedrooms, double? bathrooms}) {
  final parts = <String>[];
  if (bedrooms != null) {
    parts.add(bedrooms == 0 ? 'Studio' : '$bedrooms bed');
  }
  if (bathrooms != null) {
    parts.add('${formatBathrooms(bathrooms)} bath');
  }
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

/// Why a unit may or may not be deleted.
///
/// A unit with a tenant, messages, or payment records stays. Messages and
/// payment records are never removed by deleting a unit. Other attached
/// records are named in [warnings] so the confirmation can say the database
/// may remove them with the unit.
class UnitDeleteDecision {
  final bool allowed;
  final String? blockReason;
  final List<String> warnings;

  const UnitDeleteDecision({
    required this.allowed,
    this.blockReason,
    this.warnings = const [],
  });
}

UnitDeleteDecision decideUnitDelete({
  required String status,
  required String? tenantId,
  required bool hasMessages,
  required bool hasPayments,
  bool hasMaintenance = false,
  bool hasDocuments = false,
  bool hasPhotos = false,
  bool hasRentHistory = false,
}) {
  final tenant = tenantId?.trim() ?? '';
  if (status.trim().toLowerCase() == 'occupied' || tenant.isNotEmpty) {
    return const UnitDeleteDecision(
      allowed: false,
      blockReason:
          'This unit still has a tenant, so it cannot be deleted. Move the tenant out first.',
    );
  }
  if (hasMessages || hasPayments) {
    final pieces = <String>[
      if (hasMessages) 'messages',
      if (hasPayments) 'payment records',
    ];
    final joined = pieces.length == 2
        ? '${pieces[0]} and ${pieces[1]}'
        : pieces.single;
    return UnitDeleteDecision(
      allowed: false,
      blockReason:
          'This unit still has $joined. Deleting the unit would also remove that history, so the unit was left in place.',
    );
  }
  return UnitDeleteDecision(
    allowed: true,
    warnings: [
      if (hasMaintenance) 'maintenance requests',
      if (hasDocuments) 'documents',
      if (hasPhotos) 'photos',
      if (hasRentHistory) 'rent change notes',
    ],
  );
}

String unitDeleteConfirmation({
  required String unitNumber,
  required List<String> warnings,
}) {
  final label = unitNumber.trim().isEmpty ? 'this unit' : 'unit $unitNumber';
  if (warnings.isEmpty) {
    return 'Delete $label? This removes only that unit. It has no tenant, messages, or payment records.';
  }
  final extra = warnings.join(', ');
  return 'Delete $label? This removes only that unit. It is also tied to $extra, and the database may remove those with the unit. Messages and payment records are not attached.';
}

Map<String, dynamic> unitWritePayload({
  required String propertyId,
  required String landlordId,
  required String unitNumber,
  required String status,
  required double rentAmount,
  required double depositAmount,
  required double additionalDeposit,
  DateTime? leaseStart,
  DateTime? leaseEnd,
  int? bedrooms,
  double? bathrooms,
}) {
  return {
    'property_id': propertyId,
    'landlord_id': landlordId,
    'unit_number': unitNumber.trim(),
    'status': isKnownUnitStatus(status) ? status : 'vacant',
    'rent_amount': rentAmount,
    'deposit_amount': depositAmount,
    'additional_deposit': additionalDeposit,
    'lease_start': leaseStart == null ? null : formatDateColumn(leaseStart),
    'lease_end': leaseEnd == null ? null : formatDateColumn(leaseEnd),
    'bedrooms': bedrooms,
    'bathrooms': bathrooms,
  };
}
