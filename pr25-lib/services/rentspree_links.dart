import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/billing_rules.dart';

/// Landlord's saved link, then the compile-time RENTSPREE_INVITE_LINK,
/// then the RentSpree homepage.
Future<String> loadRentspreeLink(String? landlordId) async {
  String? saved;
  final id = landlordId?.trim() ?? '';
  if (id.isNotEmpty) {
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('rentspree_invite_link')
          .eq('id', id)
          .maybeSingle();
      saved = row?['rentspree_invite_link']?.toString();
    } catch (_) {}
  }
  const environmentLink = String.fromEnvironment('RENTSPREE_INVITE_LINK');
  return resolveRentspreeLink(
    savedLink: saved,
    environmentLink: environmentLink,
  );
}
