/// Landlord referral rules. Stripe is not called from here.
const referralCouponId = 'elevo_landlord_referral_20';
const referralDiscountPercent = 20;
const referralDiscountMonths = 3;
const referralCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// Stripe coupon body. Creating it is a live setup step, not an app action.
Map<String, String> referralCouponFields() {
  return {
    'id': referralCouponId,
    'percent_off': '$referralDiscountPercent',
    'duration': 'repeating',
    'duration_in_months': '$referralDiscountMonths',
    'name': 'Landlord referral 20% for 3 months',
  };
}

String normalizeReferralCode(String raw) {
  return raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
}

bool referralCodeLooksValid(String raw) {
  final code = normalizeReferralCode(raw);
  return RegExp('^ELEVO-[$referralCodeAlphabet]{4}\$').hasMatch(code);
}

/// Four-character code from a non-negative index. Used to prove uniqueness.
String referralCodeFromIndex(int index) {
  if (index < 0) {
    throw ArgumentError.value(index, 'index', 'must be zero or greater');
  }
  final base = referralCodeAlphabet.length;
  final chars = List<String>.filled(4, referralCodeAlphabet[0]);
  var value = index;
  for (var i = 3; i >= 0; i--) {
    chars[i] = referralCodeAlphabet[value % base];
    value ~/= base;
  }
  return 'ELEVO-${chars.join()}';
}

enum ReferralClaimRejection {
  notLandlord,
  badFormat,
  missing,
  ownCode,
  alreadyUsed,
  notNew,
}

/// Server-side claim rules, mirrored by claim_referral_code.
ReferralClaimRejection? referralClaimRejection({
  required bool isLandlord,
  required String code,
  required bool codeExists,
  required bool isOwnCode,
  required bool alreadyUsed,
  required bool hasSubscription,
}) {
  if (!isLandlord) return ReferralClaimRejection.notLandlord;
  if (!referralCodeLooksValid(code)) return ReferralClaimRejection.badFormat;
  if (!codeExists) return ReferralClaimRejection.missing;
  if (isOwnCode) return ReferralClaimRejection.ownCode;
  if (alreadyUsed) return ReferralClaimRejection.alreadyUsed;
  if (hasSubscription) return ReferralClaimRejection.notNew;
  return null;
}

String referralClaimMessage(ReferralClaimRejection reason) {
  switch (reason) {
    case ReferralClaimRejection.notLandlord:
      return 'Only a landlord can use a referral code.';
    case ReferralClaimRejection.badFormat:
    case ReferralClaimRejection.missing:
      return 'That code is not valid.';
    case ReferralClaimRejection.ownCode:
      return 'You cannot use your own code.';
    case ReferralClaimRejection.alreadyUsed:
      return 'This account already used a referral code.';
    case ReferralClaimRejection.notNew:
      return 'Referral codes are only for a new landlord account.';
  }
}

/// A card trial or an active subscription qualifies the referred landlord.
bool referredSubscriptionQualifies(String? stripeStatus) {
  switch ((stripeStatus ?? '').trim().toLowerCase()) {
    case 'trialing':
    case 'trial':
    case 'active':
      return true;
    default:
      return false;
  }
}

enum ReferrerReward { applyCoupon, holdUntilTheySubscribe, skip }

/// What to do for the person who shared the code.
ReferrerReward referrerRewardAction({
  required String? referredStripeStatus,
  required String? referrerSubscriptionId,
  required bool alreadyRewarded,
}) {
  if (alreadyRewarded) return ReferrerReward.skip;
  if (!referredSubscriptionQualifies(referredStripeStatus)) {
    return ReferrerReward.skip;
  }
  final subscription = referrerSubscriptionId?.trim() ?? '';
  if (subscription.isEmpty) return ReferrerReward.holdUntilTheySubscribe;
  return ReferrerReward.applyCoupon;
}

/// Checkout Session fields for a referred landlord. The 7-day trial stays.
Map<String, String> referredCheckoutFields({
  required bool hasReferral,
  required String priceId,
  required String userId,
  required String email,
}) {
  final fields = <String, String>{
    'mode': 'subscription',
    'line_items[0][price]': priceId,
    'line_items[0][quantity]': '1',
    'subscription_data[trial_period_days]': '7',
    'client_reference_id': userId,
    'customer_email': email,
    'metadata[user_id]': userId,
  };
  if (hasReferral) {
    fields['discounts[0][coupon]'] = referralCouponId;
  }
  return fields;
}

/// Form body that adds the coupon to an existing subscription.
Map<String, String> applyCouponToSubscriptionFields() {
  return {'discounts[0][coupon]': referralCouponId};
}
