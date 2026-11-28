import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/billing_rules.dart';

/// Opens a Stripe Payment Link with the signed-in person attached,
/// so the webhook can match the payment to their account.
Future<bool> openStripePaymentLink({
  required String link,
  required String? userId,
  required String? email,
}) async {
  final id = userId?.trim() ?? '';
  final address = email?.trim() ?? '';
  if (id.isEmpty || address.isEmpty) return false;
  final uri = paymentLinkUri(link: link, userId: id, email: address);
  if (!await canLaunchUrl(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Opens a Checkout Session when this landlord used a referral code.
/// Returns an error message, or null when Stripe opened.
/// A missing price secret returns the message and does not open a link.
Future<String?> openReferralCheckout({
  required String plan,
  required bool annual,
}) async {
  try {
    final response = await Supabase.instance.client.functions.invoke(
      'stripe-checkout',
      body: {'plan': plan, 'annual': annual},
    );
    final data = response.data;
    if (data is Map && data['url'] is String) {
      final opened = await launchUrl(
        Uri.parse(data['url'] as String),
        mode: LaunchMode.externalApplication,
      );
      return opened ? null : 'Could not open the payment page.';
    }
    if (data is Map && data['error'] is String) return data['error'] as String;
    return 'Could not open the payment page.';
  } on FunctionException catch (error) {
    final details = error.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    return 'Could not open the payment page.';
  } catch (_) {
    return 'Could not open the payment page.';
  }
}

/// Opens the Stripe billing portal. Returns an error message, or null
/// when the page was opened.
Future<String?> openBillingPortal() async {
  try {
    final response = await Supabase.instance.client.functions.invoke(
      'stripe-billing-portal',
    );
    final data = response.data;
    if (data is Map && data['url'] is String) {
      final uri = Uri.parse(data['url'] as String);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return opened ? null : 'Could not open the billing page.';
    }
    if (data is Map && data['error'] is String) return data['error'] as String;
    return 'Could not open the billing page.';
  } on FunctionException catch (error) {
    final details = error.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    return 'No Stripe billing account yet. Choose a plan first, then you can manage it here.';
  } catch (_) {
    return 'Could not open the billing page.';
  }
}
