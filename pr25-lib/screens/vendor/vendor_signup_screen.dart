import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../elevo_auth_screens.dart';

class VendorSignupScreen extends StatefulWidget {
  const VendorSignupScreen({super.key});

  @override
  State<VendorSignupScreen> createState() => _VendorSignupScreenState();
}

class _VendorSignupScreenState extends State<VendorSignupScreen> {
  final _nameC = TextEditingController();
  final _companyC = TextEditingController();
  final _phoneC = TextEditingController();
  final _areaC = TextEditingController();
  final _emailC = TextEditingController();
  final _passC = TextEditingController();
  final _confirmC = TextEditingController();
  String? _trade;
  bool _agreed = false;

  @override
  void dispose() {
    _nameC.dispose();
    _companyC.dispose();
    _phoneC.dispose();
    _areaC.dispose();
    _emailC.dispose();
    _passC.dispose();
    _confirmC.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    final name = _nameC.text.trim();
    final company = _companyC.text.trim();
    final email = _emailC.text.trim();
    final pass = _passC.text;
    final confirm = _confirmC.text;

    if (name.isEmpty || email.isEmpty || pass.isEmpty || confirm.isEmpty ||
        _phoneC.text.trim().isEmpty || _areaC.text.trim().isEmpty || _trade == null) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (pass != confirm) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!_agreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agree to the Terms to create the account.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (pass.length < 6) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password must be at least 6 characters.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();
    final auth = context.read<AuthProvider>();
    // role is hardcoded to 'vendor' — sets both users table and Auth metadata.
    final result = await auth.signup(
      fullName: name,
      email: email,
      phone: _phoneC.text.trim(),
      password: pass,
      role: 'vendor',
      vendorDetails: {
        if (company.isNotEmpty) 'company_name': company,
        'service_type': _trade ?? '',
        'service_area': _areaC.text.trim(),
      },
    );

    if (!mounted) return;

    if (result.needsEmailConfirmation) {
      context.go(
        '/check-email?email=${Uri.encodeComponent(result.confirmEmail!)}',
      );
    } else if (result.signedIn) {
      context.go('/vendor');
    } else if (auth.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error!),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? ElevoColors.mutedDark : ElevoColors.muted;
    final note = TextStyle(
      color: muted,
      fontSize: 14.5,
      fontWeight: FontWeight.w500,
    );

    return ElevoAuthLayout(
      onBack: () => context.go('/login'),
      barHeroOnNarrow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ElevoAuthHeading(
            title: 'Vendor / Partner Portal',
            subtitle:
                'Create your vendor account to access jobs, reports, and billing.',
          ),
          const SizedBox(height: 12),
          ElevoTextField(
            controller: _nameC,
            label: 'Full Name',
            hint: 'Your full name',
            icon: Icons.person_outline_rounded,
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            enabled: !auth.isLoading,
          ),
          const SizedBox(height: 12),
          ElevoTextField(
            controller: _companyC,
            label: 'Company name',
            hint: 'Optional',
            icon: Icons.business_outlined,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.words,
            enabled: !auth.isLoading,
          ),
          const SizedBox(height: 12),
          ElevoTextField(
            controller: _phoneC,
            label: 'Phone',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            enabled: !auth.isLoading,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _trade,
            decoration: const InputDecoration(labelText: 'Trade'),
            items: const [
              DropdownMenuItem(value: 'Plumbing', child: Text('Plumbing')),
              DropdownMenuItem(value: 'Electrical', child: Text('Electrical')),
              DropdownMenuItem(value: 'HVAC', child: Text('HVAC')),
              DropdownMenuItem(value: 'Cleaning', child: Text('Cleaning')),
              DropdownMenuItem(value: 'Landscaping', child: Text('Landscaping')),
              DropdownMenuItem(value: 'Handyman', child: Text('Handyman')),
              DropdownMenuItem(value: 'Painting', child: Text('Painting')),
              DropdownMenuItem(value: 'Pest Control', child: Text('Pest Control')),
              DropdownMenuItem(value: 'Other', child: Text('Other')),
            ],
            onChanged: auth.isLoading ? null : (value) => setState(() => _trade = value),
          ),
          const SizedBox(height: 12),
          ElevoTextField(
            controller: _areaC,
            label: 'Service area',
            hint: 'Phoenix, AZ',
            icon: Icons.location_on_outlined,
            enabled: !auth.isLoading,
          ),
          const SizedBox(height: 12),
          ElevoTextField(
            controller: _emailC,
            label: 'Email Address',
            hint: 'name@example.com',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            enabled: !auth.isLoading,
          ),
          const SizedBox(height: 12),
          ElevoTextField(
            controller: _passC,
            label: 'Password',
            icon: Icons.lock_outline_rounded,
            obscure: true,
            autofillHints: const [AutofillHints.newPassword],
            enabled: !auth.isLoading,
          ),
          const SizedBox(height: 12),
          ElevoTextField(
            controller: _confirmC,
            label: 'Confirm Password',
            icon: Icons.lock_reset_rounded,
            obscure: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            enabled: !auth.isLoading,
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _agreed,
            onChanged: auth.isLoading
                ? null
                : (value) => setState(() => _agreed = value ?? false),
            title: const Text('I agree to the Terms'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('By creating an account you agree to the ', style: note),
              ElevoAuthLink(
                label: 'Terms',
                onPressed: () => context.push('/terms'),
              ),
              Text(' and ', style: note),
              ElevoAuthLink(
                label: 'Privacy Policy',
                onPressed: () => context.push('/privacy'),
              ),
              Text('.', style: note),
            ],
          ),
          const SizedBox(height: 12),
          ElevoPrimaryButton(
            label: 'Create Vendor Account',
            loading: auth.isLoading,
            onPressed: _signup,
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Already have an account?', style: note),
              ElevoAuthLink(
                label: 'Sign In',
                onPressed: () => context.go('/login'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
