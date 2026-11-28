/// Plan, trial, RentSpree link, and payment-link rules.
///
/// No Flutter or Supabase imports, so tests can lock the assumptions
/// the database trigger uses as well.
library;

/// Unpaid plan name the database still stores until Stripe writes
/// essential or unlimited. New landlords do not get a card-free trial.
const signupTrialPlan = 'trial';

/// Live landlord Payment Links. Each one collects a card and starts a
/// 7-day Stripe trial. The card is charged when that trial ends.
const stripeEssentialMonthlyLink =
    'https://buy.stripe.com/9B68wI5n21We2Pa15567S0l';
const stripeEssentialAnnualLink =
    'https://buy.stripe.com/dRmcMYeXC6cu2Pa6pp67S0m';
const stripeUnlimitedMonthlyLink =
    'https://buy.stripe.com/4gM5kw2aQ9oG3Te5ll67S0n';
const stripeUnlimitedAnnualLink =
    'https://buy.stripe.com/3cI9AM2aQ7gyfBWaFF67S0o';

/// Essential includes this many properties before any add-on.
const essentialIncludedProperties = 1;

/// Shown when no landlord link and no compile-time link is usable.
const rentspreeHomeUrl = 'https://www.rentspree.com';

/// Mobile return address for the confirmation email.
const mobileAuthRedirect = 'elevo://auth-callback';

/// Auth metadata set on a new landlord so the app can require a plan
/// even before the signup SQL is applied.
bool planChoiceRequiredFromMetadata(Object? raw) {
  return raw == true || raw == 'true';
}

/// Stripe has started a landlord subscription. The webhook stores
/// `trialing` as status `trial` and writes the plan from stripe_plan_map.
bool landlordStripePlanUnlocked({
  required String? plan,
  required String? status,
}) {
  final planKey = plan?.trim().toLowerCase() ?? '';
  if (planKey != 'essential' && planKey != 'unlimited') return false;
  final state = status?.trim().toLowerCase() ?? '';
  return state.isEmpty ||
      state == 'active' ||
      state == 'trialing' ||
      state == 'trial';
}

/// New landlords must pick Essential or Unlimited and open the Stripe
/// Payment Link before the landlord app. A plan that is already set, and
/// a card-free trial that has not ended, stay open. A null trial end is
/// an older row and stays open. Tenants, vendors, and admins are never
/// sent to the plan screen.
bool landlordMustChoosePlan({
  required String? role,
  required String? plan,
  required String? status,
  DateTime? trialEndsAt,
  bool planChoiceRequired = false,
  DateTime? now,
}) {
  final who = role?.trim().toLowerCase() ?? '';
  if (who == 'tenant' || who == 'vendor' || who == 'admin') return false;
  final planKey = plan?.trim().toLowerCase() ?? '';
  if (planKey == 'essential' || planKey == 'unlimited') return false;
  if (planChoiceRequired) return true;
  final legacy = planKey.isEmpty || planKey == 'trial' || planKey == 'free';
  final clock = now ?? DateTime.now();
  final stillOpen = trialEndsAt == null || trialEndsAt.isAfter(clock);
  if (legacy && stillOpen) return false;
  return true;
}

enum LandlordCreateKind { property, unit }

class LandlordCreateDecision {
  final bool allowed;
  final String? message;

  const LandlordCreateDecision.allow()
      : allowed = true,
        message = null;

  const LandlordCreateDecision.block(this.message) : allowed = false;
}

class LandlordPlanSnapshot {
  final String planKey;
  final String status;
  final bool trialActive;
  final bool trialEnded;
  final bool paidActive;
  final bool createsBlocked;
  final int propertyLimit;

  /// Same cap as [propertyLimit]. A unit row counts as one property.
  final int unitLimit;
  final int extraProperties;

  const LandlordPlanSnapshot({
    required this.planKey,
    required this.status,
    required this.trialActive,
    required this.trialEnded,
    required this.paidActive,
    required this.createsBlocked,
    required this.propertyLimit,
    required this.unitLimit,
    required this.extraProperties,
  });

  bool get unlimited => propertyLimit < 0;
}

/// What the landlord screens and the database both enforce.
///
/// Assumptions (also written in the SQL file):
/// * Plan `trial`, `free`, blank, or null is the free trial.
///   A missing trial end counts as still in the trial, so older rows
///   are not locked out. A trial end in the past, with no paying plan,
///   blocks new properties. Existing rows stay readable.
/// * An active trial uses Essential limits: 1 property, plus purchased
///   extra properties. Each extra property adds one property.
/// * A new property row counts as one property. A new unit row also
///   counts as one property, against that same limit. There is no
///   separate allowance of several units on one property.
/// * `essential` or `unlimited` with status `active` or `trialing`
///   is a paying plan. A blank status on those plans also counts as
///   paying, so a mapped purchase is not locked out if the status
///   column has not been filled yet.
/// * `past_due`, `canceled`, `unpaid`, `incomplete`, and
///   `incomplete_expired` are not paying. Stripe leaves a subscription
///   `active` until the period actually ends, so cancel-at-period-end
///   keeps access until that webhook arrives.
/// * `unlimited` has no property cap.
/// * Done for You is a one-time setup purchase. It does not change the plan.
/// * Tenants are never blocked. Vendor tiers have no property
///   limits in the app, so vendors are not blocked here either.
/// * An admin account is not plan-gated.
/// * `founding_member` is not a paid plan.
LandlordPlanSnapshot landlordPlanSnapshot({
  required String? role,
  required String? plan,
  required String? status,
  required DateTime? trialEndsAt,
  required int extraProperties,
  required DateTime now,
}) {
  final who = (role ?? '').trim().toLowerCase();
  final planKey = _normalizePlan(plan);
  final state = (status ?? '').trim().toLowerCase();
  final extras = extraProperties < 0 ? 0 : extraProperties;
  final slots = essentialIncludedProperties + extras;
  final essentialProperties = slots;

  if (who == 'tenant' || who == 'vendor' || who == 'admin') {
    return LandlordPlanSnapshot(
      planKey: planKey,
      status: state,
      trialActive: false,
      trialEnded: false,
      paidActive: false,
      createsBlocked: false,
      propertyLimit: -1,
      unitLimit: -1,
      extraProperties: extras,
    );
  }

  final paying = _isPaying(planKey, state);
  final onFreePlan = planKey == 'trial' || planKey == 'free' || planKey.isEmpty;
  // Stripe trialing is stored as status trial, with trial_ends_at from Stripe.
  // The plan name stays essential or unlimited so the right limits apply.
  final cardTrial = (planKey == 'essential' || planKey == 'unlimited') &&
      (state == 'trial' || state == 'trialing');
  final cardTrialOpen = cardTrial &&
      (trialEndsAt == null || trialEndsAt.isAfter(now));
  final cardTrialEnded = cardTrial &&
      trialEndsAt != null &&
      !trialEndsAt.isAfter(now);
  final trialActive = cardTrialOpen ||
      (onFreePlan && !paying && (trialEndsAt == null || trialEndsAt.isAfter(now)));
  final trialEnded = cardTrialEnded ||
      (onFreePlan &&
          !paying &&
          trialEndsAt != null &&
          !trialEndsAt.isAfter(now));

  final blocked = !paying && !trialActive;
  final unlimited = planKey == 'unlimited' && (paying || cardTrialOpen);

  return LandlordPlanSnapshot(
    planKey: planKey.isEmpty ? 'trial' : planKey,
    status: state.isEmpty ? (onFreePlan ? 'trial' : state) : state,
    trialActive: trialActive,
    trialEnded: trialEnded,
    paidActive: paying,
    createsBlocked: blocked,
    propertyLimit: unlimited ? -1 : essentialProperties,
    unitLimit: unlimited ? -1 : essentialProperties,
    extraProperties: extras,
  );
}

LandlordCreateDecision landlordCreateDecision({
  required String? role,
  required String? plan,
  required String? status,
  required DateTime? trialEndsAt,
  required int extraProperties,
  required int propertyCount,
  required int unitCount,
  required LandlordCreateKind kind,
  required DateTime now,
}) {
  final snap = landlordPlanSnapshot(
    role: role,
    plan: plan,
    status: status,
    trialEndsAt: trialEndsAt,
    extraProperties: extraProperties,
    now: now,
  );
  if (!snap.createsBlocked && snap.unlimited) {
    return const LandlordCreateDecision.allow();
  }
  if (snap.createsBlocked) {
    if (snap.trialEnded || snap.planKey == 'trial' || snap.planKey == 'free') {
      return const LandlordCreateDecision.block(
        'Your 7-day trial has ended. A card is collected upfront to subscribe. '
        'Everything you already added is still here. Subscribe to add properties.',
      );
    }
    return const LandlordCreateDecision.block(
      'Your subscription is not active. Everything you already added is still here. '
      'Subscribe to add properties.',
    );
  }
  final overPropertyLimit = snap.propertyLimit >= 0 &&
      kind == LandlordCreateKind.property &&
      propertyCount >= snap.propertyLimit;
  final overUnitAsProperty = snap.propertyLimit >= 0 &&
      kind == LandlordCreateKind.unit &&
      unitCount >= snap.propertyLimit;
  if (overPropertyLimit || overUnitAsProperty) {
    return const LandlordCreateDecision.block(propertyPlanLimitReachedMessage);
  }
  return const LandlordCreateDecision.allow();
}

/// Shown when a property insert or a unit insert hits the plan cap.
/// The old database wording is recognized so a database that still
/// raises it gets the same message.
const propertyPlanLimitReachedMessage =
    'You\'ve reached your plan\'s property limit. '
    'Add another property for \$12.99/mo, or upgrade to Unlimited.';

bool isPropertyPlanLimitError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('essential plan property limit reached') ||
      text.contains('essential plan unit limit reached');
}

/// Vendor directory tiers. None of these define a per-vendor usage cap
/// in the app, so the vendor screen only displays the real tier.
const vendorTierPlans = <String, String>{
  'basic': 'basic',
  'vendor_basic': 'basic',
  'featured': 'featured',
  'vendor_featured': 'featured',
  'preferred': 'preferred',
  'vendor_preferred': 'preferred',
  'platinum': 'platinum',
  'vendor_platinum': 'platinum',
};

/// Null when the account is not on a vendor tier (trial, landlord plan, blank).
String? vendorTierForPlan(String? plan) {
  final key = (plan ?? '').trim().toLowerCase();
  return vendorTierPlans[key];
}

bool vendorTierIsCurrent({
  required String? plan,
  required String? status,
  required String tier,
}) {
  if (vendorTierForPlan(plan) != tier) return false;
  final state = (status ?? '').trim().toLowerCase();
  return state.isEmpty || state == 'active' || state == 'trialing';
}

String landlordPlanTitle(String? plan) {
  switch (_normalizePlan(plan)) {
    case 'essential':
      return 'Essential';
    case 'unlimited':
      return 'Unlimited';
    default:
      return 'Trial';
  }
}

/// Vendor plans are paid immediately. The plan screen must not say trial.
String vendorPlanStatusLabel(String? status, {required bool hasPaidPlan}) {
  if (!hasPaidPlan) return 'Not subscribed';
  final state = (status ?? '').trim().toLowerCase();
  if (state.isEmpty || state == 'trial' || state == 'trialing') {
    return 'Not subscribed';
  }
  return subscriptionStatusLabel(status);
}

String subscriptionStatusLabel(String? status) {
  switch ((status ?? '').trim().toLowerCase()) {
    case 'active':
      return 'Active';
    case 'trialing':
    case 'trial':
      return 'Trial';
    case 'past_due':
      return 'Past due';
    case 'canceled':
    case 'cancelled':
      return 'Canceled';
    case 'unpaid':
      return 'Unpaid';
    case 'incomplete':
    case 'incomplete_expired':
      return 'Incomplete';
    case 'paused':
      return 'Paused';
    default:
      return 'Trial';
  }
}

/// Null when [raw] is empty or a valid https rentspree.com link.
/// Otherwise a short message for the settings field.
String? validateRentspreeInviteLink(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.scheme != 'https') {
    return 'Use a full https link from rentspree.com.';
  }
  if (uri.userInfo.isNotEmpty || uri.host.isEmpty) {
    return 'Use a full https link from rentspree.com.';
  }
  final host = uri.host.toLowerCase();
  final onRentSpree = host == 'rentspree.com' || host.endsWith('.rentspree.com');
  if (!onRentSpree) {
    return 'The link has to be on rentspree.com.';
  }
  return null;
}

/// Landlord link, then the compile-time link, then the RentSpree homepage.
/// A saved or compile-time value that is not an https rentspree.com URL is skipped.
String resolveRentspreeLink({
  required String? savedLink,
  required String environmentLink,
}) {
  final saved = savedLink?.trim() ?? '';
  if (saved.isNotEmpty && validateRentspreeInviteLink(saved) == null) {
    return saved;
  }
  final fromEnv = environmentLink.trim();
  if (fromEnv.isNotEmpty && validateRentspreeInviteLink(fromEnv) == null) {
    return fromEnv;
  }
  return rentspreeHomeUrl;
}

/// Payment Links accept these query fields so the webhook can match the payer.
Uri paymentLinkUri({
  required String link,
  required String userId,
  required String email,
}) {
  final base = Uri.parse(link);
  return base.replace(queryParameters: {
    ...base.queryParameters,
    'client_reference_id': userId,
    'prefilled_email': email.trim(),
  });
}

/// Public web app base, with a trailing slash. Production lives at /app/.
/// A local server keeps its own path.
String appWebBase({
  required bool isWeb,
  required String origin,
  String path = '/',
}) {
  if (!isWeb) return 'https://getelevo.app/app/';
  var host = origin.trim();
  if (host.endsWith('/')) host = host.substring(0, host.length - 1);
  if (!host.startsWith('https://') && !host.startsWith('http://')) {
    return 'https://getelevo.app/app/';
  }
  var route = path.trim();
  if (route.endsWith('index.html')) {
    route = route.substring(0, route.length - 'index.html'.length);
  }
  if (route.isEmpty) route = '/';
  if (!route.endsWith('/')) route = '$route/';
  final name = Uri.tryParse(host)?.host ?? '';
  final local = name == 'localhost' || name == '127.0.0.1';
  if (!local && route == '/') route = '/app/';
  return '$host$route';
}

/// Web uses the app origin. Mobile uses the custom scheme.
String emailConfirmationRedirect({
  required bool isWeb,
  required String webOrigin,
  String webPath = '/',
}) {
  if (isWeb) {
    return appWebBase(isWeb: true, origin: webOrigin, path: webPath);
  }
  return mobileAuthRedirect;
}

/// Password recovery must land in the app, not on the marketing site.
String passwordResetRedirect({
  required bool isWeb,
  required String origin,
  String path = '/',
}) {
  if (!isWeb) return mobileAuthRedirect;
  return '${appWebBase(isWeb: true, origin: origin, path: path)}';
}

/// Login copy when Supabase has confirmation turned on.
String loginErrorMessage(Object error) {
  final msg = error.toString().toLowerCase();
  if (msg.contains('email not confirmed') || msg.contains('email_not_confirmed')) {
    return 'Confirm your email first. Open the link we sent you, then log in.';
  }
  if (msg.contains('invalid email') ||
      msg.contains('invalid format') ||
      msg.contains('unable to validate email') ||
      msg.contains('email_address_invalid')) {
    return 'Please enter a valid email';
  }
  if (msg.contains('invalid login credentials') || msg.contains('invalid_credentials')) {
    return 'Incorrect email or password. Please try again.';
  }
  if (msg.contains('email already registered') || msg.contains('already registered') ||
      msg.contains('user already registered')) {
    return 'An account with this email already exists.';
  }
  if (msg.contains('password should be at least')) {
    return 'Password must be at least 6 characters.';
  }
  if (msg.contains('rate limit') ||
      msg.contains('over_email_send_rate_limit') ||
      msg.contains('over_request_rate_limit') ||
      msg.contains('too many requests') ||
      msg.contains('429')) {
    return 'Too many attempts. Try again later.';
  }
  if (msg.contains('signup_disabled') || msg.contains('signups not allowed')) {
    return 'Sign-up is not available right now. Email hello@getelevo.app.';
  }
  if (msg.contains('network') || msg.contains('socket')) {
    return 'No internet connection. Please check your network.';
  }
  return 'Something went wrong. Please try again.';
}

bool _isPaying(String planKey, String status) {
  if (planKey != 'essential' && planKey != 'unlimited') return false;
  if (status.isEmpty) return true;
  return status == 'active' || status == 'trialing';
}

String _normalizePlan(String? plan) {
  return (plan ?? '').trim().toLowerCase();
}
