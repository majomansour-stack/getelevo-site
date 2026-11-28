import 'package:supabase_flutter/supabase_flutter.dart';

/// Name, phone, email, and payment instructions for the tenant's landlord.
/// The database function does not return plan, Stripe, or subscription fields.
Future<Map<String, dynamic>?> fetchLandlordContact(
  SupabaseClient db,
  String landlordId,
) async {
  if (landlordId.isEmpty) return null;
  try {
    final rows = await db.rpc(
      'landlord_contact_for_tenant',
      params: {'p_landlord': landlordId},
    );
    if (rows is List && rows.isNotEmpty && rows.first is Map) {
      return Map<String, dynamic>.from(rows.first as Map);
    }
    if (rows is Map) return Map<String, dynamic>.from(rows);
  } catch (_) {}
  return null;
}
