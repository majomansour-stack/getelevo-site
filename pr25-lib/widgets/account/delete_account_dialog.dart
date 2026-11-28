import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';

const _deleteFallback =
    'Could not delete the account. Email hello@getelevo.app.';

String _deleteErrorText(Object? data) {
  if (data is Map && data['error'] is String && (data['error'] as String).trim().isNotEmpty) {
    return (data['error'] as String).trim();
  }
  return _deleteFallback;
}

void _showDeleteError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Confirms, then deletes the signed-in account.
///
/// The request body is empty on purpose. The edge function takes the user
/// from the JWT and ignores any user id a caller might send.
Future<void> confirmAndDeleteAccount(BuildContext context) async {
  final colors = Theme.of(context).extension<ElevoColors>()!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete account?'),
      content: const Text(
        'This turns off your login and clears your name, email, and phone. '
        'Elevo keeps the account row so a property, unit, or payment instruction '
        'other people still need is not removed. Your name is taken off repairs, '
        'payments, and messages where it can be. '
        'Deleting the account cancels your Stripe subscription immediately. '
        'There is no refund for the current period. '
        'This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Delete account', style: TextStyle(color: colors.urgentRed)),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    final response = await Supabase.instance.client.functions.invoke(
      'delete-account',
      body: const <String, dynamic>{},
    );
    final data = response.data;
    final failed = response.status >= 300 ||
        (data is Map && data['error'] != null);
    if (failed) {
      _showDeleteError(context, _deleteErrorText(data));
      return;
    }
  } on FunctionException catch (error) {
    if (context.mounted) {
      _showDeleteError(context, _deleteErrorText(error.details));
    }
    return;
  } catch (_) {
    if (context.mounted) {
      _showDeleteError(context, _deleteFallback);
    }
    return;
  }

  if (!context.mounted) return;
  await context.read<AuthProvider>().logout();
  if (!context.mounted) return;
  context.go('/login');
}
