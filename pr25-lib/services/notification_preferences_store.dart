import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/elevo_logic.dart';

/// Reads and writes the notification switches.
///
/// The original table only has `push_enabled`. Email and per-event
/// switches are stored when the owner applies
/// `supabase/fixes_pending_owner_approval.sql`. Until then, the push switch
/// still saves and the caller is told the rest could not be stored.
class NotificationPreferencesStore {
  final SupabaseClient _db;

  NotificationPreferencesStore(this._db);

  Future<NotificationPreferenceSnapshot> load({
    bool defaultPush = true,
    bool defaultEmail = true,
    bool defaultSms = false,
  }) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) {
      return parseNotificationPreferences(
        null,
        defaultPush: defaultPush,
        defaultEmail: defaultEmail,
        defaultSms: defaultSms,
      );
    }
    try {
      final row = await _db
          .from('notification_preferences')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      return parseNotificationPreferences(
        row,
        defaultPush: defaultPush,
        defaultEmail: defaultEmail,
        defaultSms: defaultSms,
      );
    } catch (_) {
      return parseNotificationPreferences(
        null,
        defaultPush: defaultPush,
        defaultEmail: defaultEmail,
        defaultSms: defaultSms,
      );
    }
  }

  /// Returns true when every switch was stored, false when only the push
  /// switch could be stored, and throws when nothing could be stored.
  Future<bool> save(NotificationPreferenceSnapshot snapshot) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) {
      throw Exception('Not signed in');
    }
    final now = DateTime.now();
    try {
      await _db.from('notification_preferences').upsert(
            notificationPreferencePayload(
              userId: uid,
              snapshot: snapshot,
              updatedAt: now,
            ),
            onConflict: 'user_id',
          );
      return true;
    } catch (_) {
      await _db.from('notification_preferences').upsert(
            notificationPreferencePayload(
              userId: uid,
              snapshot: snapshot,
              updatedAt: now,
              includeExtendedColumns: false,
            ),
            onConflict: 'user_id',
          );
      return false;
    }
  }
}
