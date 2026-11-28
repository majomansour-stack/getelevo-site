import '../core/elevo_logic.dart';

class AppUser {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final String? phone;
  final String? avatarUrl;
  final String subscriptionPlan;
  final String? subscriptionStatus;
  final DateTime? trialEndsAt;
  final DateTime? currentPeriodEnd;
  final int extraPropertyCount;
  final String? stripeCustomerId;
  final String? rentspreeInviteLink;
  final bool foundingMember;
  final String? referralCode;
  final String languagePreference;
  final DateTime createdAt;
  final PaymentMethods? paymentMethods;
  // Mirrors the `welcome_message_sent` column in Supabase users table.
  // Set to true after the automated welcome chat message is injected once.
  final bool welcomeMessageSent;

  /// Set from auth metadata on a landlord who signed up after the
  /// card-free trial was removed.
  final bool planChoiceRequired;

  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.phone,
    this.avatarUrl,
    this.subscriptionPlan = 'free',
    this.subscriptionStatus,
    this.trialEndsAt,
    this.currentPeriodEnd,
    this.extraPropertyCount = 0,
    this.stripeCustomerId,
    this.rentspreeInviteLink,
    this.foundingMember = false,
    this.referralCode,
    this.languagePreference = 'en',
    required this.createdAt,
    this.paymentMethods,
    this.welcomeMessageSent = false,
    this.planChoiceRequired = false,
  });

  AppUser copyWith({
    String? role,
    bool? welcomeMessageSent,
    bool? planChoiceRequired,
  }) {
    return AppUser(
      id: id,
      email: email,
      fullName: fullName,
      role: role ?? this.role,
      phone: phone,
      avatarUrl: avatarUrl,
      subscriptionPlan: subscriptionPlan,
      subscriptionStatus: subscriptionStatus,
      trialEndsAt: trialEndsAt,
      currentPeriodEnd: currentPeriodEnd,
      extraPropertyCount: extraPropertyCount,
      stripeCustomerId: stripeCustomerId,
      rentspreeInviteLink: rentspreeInviteLink,
      foundingMember: foundingMember,
      referralCode: referralCode,
      languagePreference: languagePreference,
      createdAt: createdAt,
      paymentMethods: paymentMethods,
      welcomeMessageSent: welcomeMessageSent ?? this.welcomeMessageSent,
      planChoiceRequired: planChoiceRequired ?? this.planChoiceRequired,
    );
  }

  bool get isLandlord => role == 'landlord';
  bool get isTenant => role == 'tenant';
  bool get isAdmin => role == 'admin';
  bool get isVendor => role == 'vendor';
  String get initials => initialsFor(fullName);
}

class PaymentMethods {
  final List<LandlordPaymentMethod> methods;

  const PaymentMethods({this.methods = const []});

  factory PaymentMethods.fromStored(dynamic raw) {
    return PaymentMethods(methods: userPaymentMethodsFromJson(raw));
  }

  LandlordPaymentMethod? _first(String kind) {
    for (final method in methods) {
      if (method.kind == kind) return method;
    }
    return null;
  }

  String? get zelle => _nullIfEmpty(_first('zelle')?.handle);
  String? get venmo => _nullIfEmpty(_first('venmo')?.handle);
  String? get bankRouting => _first('bank_transfer')?.bankRouting;
  String? get bankAccount => _first('bank_transfer')?.bankAccount;
  String? get checkPayable => _nullIfEmpty(_first('check')?.handle);
  String? get cashInstructions => _nullIfEmpty(_first('cash')?.handle);

  List<PaymentMethodItem> get availableMethods {
    return [
      for (final method in methods)
        if (method.detail.trim().isNotEmpty || method.title.trim().isNotEmpty)
          PaymentMethodItem(
            method.title,
            method.detail.trim().isEmpty ? method.title : method.detail,
          ),
    ];
  }
}

String? _nullIfEmpty(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return trimmed;
}

class PaymentMethodItem {
  final String label;
  final String value;
  const PaymentMethodItem(this.label, this.value);
}
