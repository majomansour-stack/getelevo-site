import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/billing_rules.dart';
import '../providers/auth_provider.dart';
import '../screens/elevo_auth_screens.dart';

/// Login screen wired to the existing AuthProvider and routes.
Widget buildElevoLogin({String? initialError}) => ElevoLoginScreen(
      initialError: initialError,
      onSignIn: _signIn,
      onSignUp: (context) => context.go('/signup'),
      onForgotPassword: _forgotPassword,
      onResendConfirmation: _resendConfirmation,
      onVendorPortal: (context) => context.go('/vendor-signup'),
    );

/// Sign-up screen wired to the existing AuthProvider and routes.
Widget buildElevoSignUp({String? initialEmail, String? initialRole}) {
  ElevoRole? role;
  switch (initialRole) {
    case 'tenant':
      role = ElevoRole.tenant;
    case 'landlord':
      role = ElevoRole.landlord;
    case 'vendor':
      role = ElevoRole.vendor;
  }
  return ElevoSignUpScreen(
    initialRole: role,
    initialEmail: initialEmail,
    onSignUp: _signUp,
    onSignIn: (context) => context.go('/login'),
    onBack: (context) => context.go('/login'),
    onOpenTerms: (context) => context.push('/terms'),
    onOpenPrivacy: (context) => context.push('/privacy'),
  );
}

/// Privacy screen wired to the existing router.
Widget buildElevoPrivacy() => ElevoPrivacyScreen(
      onBack: (context) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/login');
        }
      },
    );

/// Terms screen wired to the existing router.
Widget buildElevoTerms() => ElevoTermsScreen(
      onBack: (context) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/login');
        }
      },
    );

Future<void> _signIn(BuildContext context, String email, String password) async {
  final auth = context.read<AuthProvider>();
  final ok = await auth.login(email, password);
  if (!ok) {
    throw ElevoAuthException(auth.error ?? 'Something went wrong. Please try again.');
  }
  if (!context.mounted) return;
  final role = auth.currentUser?.role ?? '';
  if (role == 'vendor') {
    context.go('/vendor');
  } else if (role == 'tenant') {
    context.go('/tenant');
  } else {
    // Landlord, admin and any unrecognised role land on the landlord shell.
    context.go('/landlord');
  }
}

Future<void> _signUp(BuildContext context, ElevoSignUpData data) async {
  final auth = context.read<AuthProvider>();
  final result = await auth.signup(
    fullName: data.fullName,
    email: data.email,
    phone: data.phone,
    password: data.password,
    role: data.role.name,
    vendorDetails: data.vendorDetails,
    referralCode: data.referralCode,
  );
  if (!context.mounted) return;
  if (result.needsEmailConfirmation) {
    final email = Uri.encodeComponent(result.confirmEmail!);
    final checkout = data.role.name == 'landlord' ? '&checkout=1' : '';
    context.go('/check-email?email=$email$checkout');
    return;
  }
  if (!result.signedIn) {
    throw ElevoAuthException(auth.error ?? 'Something went wrong. Please try again.');
  }
  if (data.role.name == 'landlord' && data.referralCode.trim().isNotEmpty) {
    try {
      await Supabase.instance.client.rpc(
        'claim_referral_code',
        params: {'p_code': data.referralCode.trim()},
      );
    } catch (error) {
      throw ElevoAuthException(
        error.toString().replaceFirst('Exception: ', ''),
      );
    }
  }
  if (auth.isVendor) {
    context.go('/vendor');
  } else if (auth.isLandlord) {
    context.go('/landlord/more/subscription');
  } else {
    context.go('/tenant');
  }
}

Future<void> _resendConfirmation(BuildContext context, String email) async {
  if (email.trim().isEmpty) {
    throw const ElevoAuthException('Enter your email above, then resend the confirmation.');
  }
  final auth = context.read<AuthProvider>();
  final message = await auth.resendSignupConfirmation(email);
  if (!context.mounted) return;
  if (message != null) throw ElevoAuthException(message);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Confirmation email sent to ${email.trim()}'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

Future<void> _forgotPassword(BuildContext context, String email) async {
  if (email.isEmpty) {
    throw const ElevoAuthException('Enter your email above, then tap Forgot password.');
  }
  final auth = context.read<AuthProvider>();
  final messenger = ScaffoldMessenger.of(context);
  try {
    await auth.resetPassword(email);
  } catch (e) {
    throw ElevoAuthException(loginErrorMessage(e));
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text('Reset link sent to $email'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
