import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/elevo_logic.dart';

/// Bumped after a vendor saves a job so open vendor screens refetch.
final ValueNotifier<int> vendorJobsRevision = ValueNotifier<int>(0);

void notifyVendorJobsChanged() {
  vendorJobsRevision.value++;
}

/// Loads maintenance rows that belong to the signed-in vendor.
///
/// A job may be tagged with the vendor's login id (`vendor_user_id` or
/// `vendor_id`) or with a landlord directory row that uses the same email.
class VendorMaintenanceQuery {
  final SupabaseClient _db;

  VendorMaintenanceQuery(this._db);

  Future<List<Map<String, dynamic>>> loadForCurrentUser() async {
    final user = _db.auth.currentUser;
    final uid = user?.id;
    if (uid == null) return const [];

    final email = user?.email?.toLowerCase().trim();
    final directoryIds = <String>[];
    if (email != null && email.isNotEmpty) {
      try {
        final vendorRows = await _db.from('vendor_self_directory').select('id, email');
        for (final row in vendorRows) {
          final rowEmail = (row['email'] as String?)?.toLowerCase().trim();
          final id = row['id']?.toString() ?? '';
          if (rowEmail == email && id.isNotEmpty) directoryIds.add(id);
        }
      } catch (_) {
        // Directory read can be blocked until the vendor SELECT policy exists.
      }
    }

    final ids = maintenanceVendorIds(
      authUserId: uid,
      directoryVendorIds: directoryIds,
    );
    final inList = ids.join(',');

    try {
      final rows = await _db
          .from('maintenance_requests')
          .select()
          .or('vendor_user_id.eq.$uid,vendor_id.in.($inList)')
          .order('created_at', ascending: false);
      return rows.map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (_) {
      final rows = await _db
          .from('maintenance_requests')
          .select()
          .inFilter('vendor_id', ids)
          .order('created_at', ascending: false);
      return rows.map((row) => Map<String, dynamic>.from(row)).toList();
    }
  }
}
