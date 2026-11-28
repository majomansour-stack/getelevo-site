import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/auth_provider.dart';

/// Confirms the current password, then saves a new one. Used by every role.
Future<void> showChangePasswordSheet(BuildContext context) async {
  final currentCtrl = TextEditingController();
  final nextCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Change Password', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: currentCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current Password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nextCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New Password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm New Password'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final next = nextCtrl.text;
                  if (next.length < 6) {
                    messenger.showSnackBar(const SnackBar(
                      content: Text('Password must be at least 6 characters.'),
                    ));
                    return;
                  }
                  if (next != confirmCtrl.text) {
                    messenger.showSnackBar(const SnackBar(
                      content: Text('The new passwords do not match.'),
                    ));
                    return;
                  }
                  final email = context.read<AuthProvider>().currentUser?.email;
                  if (email == null || email.isEmpty) return;
                  try {
                    await Supabase.instance.client.auth.signInWithPassword(
                      email: email,
                      password: currentCtrl.text,
                    );
                    await context.read<AuthProvider>().updatePassword(next);
                    if (ctx.mounted) Navigator.pop(ctx);
                    messenger.showSnackBar(const SnackBar(
                      content: Text('Password updated successfully.'),
                    ));
                  } catch (_) {
                    messenger.showSnackBar(const SnackBar(
                      content: Text(
                        'Could not update the password. Check the current password and try again.',
                      ),
                    ));
                  }
                },
                child: const Text('Update Password'),
              ),
            ),
          ],
        ),
      );
    },
  );
  currentCtrl.dispose();
  nextCtrl.dispose();
  confirmCtrl.dispose();
}
