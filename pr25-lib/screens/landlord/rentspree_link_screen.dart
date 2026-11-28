import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/billing_rules.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/screening/rentspree_how_it_works.dart';

/// The landlord's own RentSpree screening link. Open RentSpree and
/// screening emails use this before the compile-time fallback.
class RentSpreeLinkScreen extends StatefulWidget {
  const RentSpreeLinkScreen({super.key});

  @override
  State<RentSpreeLinkScreen> createState() => _RentSpreeLinkScreenState();
}

class _RentSpreeLinkScreenState extends State<RentSpreeLinkScreen> {
  final _ctrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _hasSavedLink = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final saved = context.read<AuthProvider>().currentUser?.rentspreeInviteLink?.trim() ?? '';
      setState(() => _hasSavedLink = saved.isNotEmpty);
      if (saved.isNotEmpty && _ctrl.text.isEmpty) {
        _ctrl.text = saved;
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final uid = auth.currentUser?.id;
    if (uid == null) return;
    final trimmed = _ctrl.text.trim();
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('users').update({
        'rentspree_invite_link': trimmed.isEmpty ? null : trimmed,
      }).eq('id', uid);
      await auth.refreshProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('RentSpree link saved.')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save that link. ${error.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RentSpree link'),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          children: [
            RentSpreeHowItWorks(needsLink: !_hasSavedLink),
            const SizedBox(height: AppTheme.spacingMd),
            Text(
              'Paste the screening link from your RentSpree account. '
              'Open RentSpree and the emails sent to applicants will use it. '
              'Leave it blank to use the shared Elevo link, or the RentSpree homepage if that is not set.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppTheme.spacingMd),
            TextFormField(
              controller: _ctrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'RentSpree link',
                hintText: 'https://www.rentspree.com/...',
              ),
              validator: validateRentspreeInviteLink,
            ),
            const SizedBox(height: AppTheme.spacingLg),
            ElevatedButton(
              onPressed: _saving
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      _save();
                    },
              child: Text(_saving ? 'Saving…' : 'Save link'),
            ),
          ],
        ),
      ),
    );
  }
}
