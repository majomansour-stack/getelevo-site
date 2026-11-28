import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/billing_rules.dart';
import '../core/elevo_logic.dart';
import '../models/user_model.dart';
import 'notification_service.dart';
import 'push_notification_service.dart';

/// Sign-up created the account, and Supabase is waiting for the
/// confirmation link before it will start a session.
class EmailConfirmationRequired implements Exception {
  final String email;
  const EmailConfirmationRequired(this.email);
}

class AuthService {
  final _client = Supabase.instance.client;

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // ─── Signup ──────────────────────────────────────────────────────────────
  // 1. Create the Supabase auth account (DB trigger auto-creates the users row)
  // 2. Sign in to get a session
  // 3. Read the row the trigger created, update it with extra fields
  // 4. Return the user — never fails silently

  Future<AppUser> signup({
    required String fullName,
    required String email,
    required String password,
    required String role,
    required String phone,
    Map<String, String> vendorDetails = const {},
    String referralCode = '',
  }) async {
    // Step 1 — create auth account. The DB trigger fires here and writes the users row.
    // Vendor details (company_name, service_type, service_area, license_number)
    // are stored in the account's profile metadata.
    final signUpRes = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: emailConfirmationRedirect(
        isWeb: kIsWeb,
        webOrigin: kIsWeb ? Uri.base.origin : '',
        webPath: kIsWeb ? Uri.base.path : '/',
      ),
      data: {
        'full_name': fullName.trim(),
        'role': role,
        'phone': phone.trim(),
        if (role == 'landlord') 'plan_choice_required': true,
        if (role == 'landlord' && referralCode.trim().isNotEmpty)
          'referral_code': referralCode.trim(),
        ...vendorDetails,
      },
    );

    if (signUpRes.user == null) {
      throw Exception('Could not create account. Please try again.');
    }

    // Confirmation is on: Supabase created the user and emailed a link.
    // There is no session until they open it, so the profile update and
    // the unit claim wait until the next sign-in.
    if (signUpRes.session == null) {
      throw EmailConfirmationRequired(email.trim());
    }

    final uid = signUpRes.user!.id;
    final landlord = role == 'landlord';

    // Step 3 — update the row the trigger wrote with the full details.
    // A new landlord does not receive a future card-free trial. Shortening
    // trial_ends_at is allowed by the database trigger.
    final patch = <String, dynamic>{
      'full_name': fullName.trim(),
      'role': role,
      'phone': phone.trim(),
      'welcome_message_sent': false,
    };
    if (landlord) {
      patch['trial_ends_at'] = DateTime.now().toUtc().toIso8601String();
    }
    try {
      await _client.from('users').update(patch).eq('id', uid);
    } catch (_) {
      // If update fails the trigger row is still usable — proceed.
    }
    try {
      await _client.from('profiles').update({
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'role': role,
      }).eq('id', uid);
    } catch (_) {}

    // Step 4 — read back the final row.
    try {
      _currentUser = await _fetchProfile(uid);
    } catch (_) {
      // Fallback: build from what we know locally.
      _currentUser = AppUser(
        id: uid,
        email: email.trim(),
        fullName: fullName.trim(),
        role: role,
        phone: phone.trim(),
        subscriptionPlan: signupTrialPlan,
        subscriptionStatus: 'trial',
        trialEndsAt: landlord ? DateTime.now().toUtc() : null,
        createdAt: DateTime.now(),
        welcomeMessageSent: false,
        planChoiceRequired: landlord,
      );
    }

    // Step 5 — if the new account is a tenant, find their invited unit by email
    // and link them immediately so the dashboard loads without polling.
    if (role == 'tenant') {
      try {
        final normalizedEmail = email.trim().toLowerCase();
        final inviteRows = await _client
            .from('units')
            .select('id')
            .eq('invited_email', normalizedEmail)
            .limit(1);
        if (inviteRows.isNotEmpty) {
          final unitId = inviteRows.first['id'] as String?;
          if (unitId != null) {
            await _client.from('units').update({
              'tenant_id': uid,
              'status': 'occupied',
            }).eq('id', unitId);
          }
        }
      } catch (_) {
        // Link failure is non-fatal — dashboard fallback path will retry.
      }
    }

    // Step 6 — send welcome email via Resend Edge Function.
    final firstName = fullName.trim().split(' ').first;
    try {
      await NotificationService.sendWelcome(
        toEmail:   email.trim(),
        firstName: firstName,
      );
    } catch (_) {
      // Welcome email failure is non-fatal — user account is already created.
    }

    return _currentUser!;
  }

  // ─── Login ───────────────────────────────────────────────────────────────

  Future<AppUser> login(String email, String password) async {
    final res = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    if (res.user == null) throw Exception('Incorrect email or password.');

    final uid = res.user!.id;

    // Always fetch the freshest user record from the Supabase Auth server.
    // res.user!.userMetadata can be stale (cached); getUser() is authoritative.
    String metaRole = '';
    try {
      final freshUser = await _client.auth.getUser();
      metaRole = freshUser.user?.userMetadata?['role']?.toString() ?? '';
    } catch (_) {
      // Fallback: use the metadata from the sign-in response.
      metaRole = res.user!.userMetadata?['role']?.toString() ?? '';
    }

    AppUser? profileUser;
    try {
      profileUser = await _fetchProfile(uid);
    } catch (_) {
      // Row missing — write it now (handles accounts created before trigger existed).
      final role = metaRole.isNotEmpty ? metaRole : 'landlord';
      final landlord = role != 'tenant' && role != 'vendor' && role != 'admin';
      final row = <String, dynamic>{
        'id': uid,
        'email': res.user!.email ?? email.trim(),
        'full_name': res.user!.userMetadata?['full_name'] ?? '',
        'role': role,
        'phone': res.user!.userMetadata?['phone'] ?? '',
        'welcome_message_sent': false,
      };
      if (landlord) {
        row['trial_ends_at'] = DateTime.now().toUtc().toIso8601String();
      }
      try {
        await _client.from('users').upsert(row, onConflict: 'id');
        profileUser = await _fetchProfile(uid);
      } catch (_) {
        profileUser = AppUser(
          id: uid,
          email: res.user!.email ?? email.trim(),
          fullName: res.user!.userMetadata?['full_name']?.toString() ?? '',
          role: role,
          phone: res.user!.userMetadata?['phone']?.toString(),
          subscriptionPlan: signupTrialPlan,
          subscriptionStatus: 'trial',
          trialEndsAt: landlord ? DateTime.now().toUtc() : null,
          createdAt: DateTime.now(),
          welcomeMessageSent: false,
          planChoiceRequired: landlord &&
              planChoiceRequiredFromMetadata(
                res.user!.userMetadata?['plan_choice_required'],
              ),
        );
      }
    }

    // Role resolution: determine the most authoritative role from three sources
    // in priority order:
    //   1. The users table row (most explicit — set by admin or signup flow)
    //   2. Supabase Auth metadata (set at signup, reliable for non-null values)
    //   3. Default to 'landlord' only as a last resort
    //
    // The users table row takes priority UNLESS it is blank/null (which happens
    // when the row was auto-created by a DB trigger without the role column being
    // set, or when an admin created the account in the Supabase dashboard).
    final rowRole = profileUser.role; // already read from DB via _mapProfile
    final resolvedRole =
        resolveStoredRole(rowRole: rowRole, metaRole: metaRole);

    _currentUser = (resolvedRole != rowRole)
        ? profileUser.copyWith(role: resolvedRole)
        : profileUser;

    // If the account is a tenant and no unit is linked yet, attempt auto-link
    // by matching the invited_email on units — identical to signup Step 5.
    // This self-heals accounts where the signup-time link silently failed.
    if (resolvedRole == 'tenant') {
      try {
        final normalizedEmail = (res.user!.email ?? email.trim()).toLowerCase().trim();
        // Only attempt if no unit is already linked to this uid.
        final existing = await _client
            .from('units')
            .select('id')
            .eq('tenant_id', uid)
            .limit(1);
        if (existing.isEmpty) {
          final inviteRows = await _client
              .from('units')
              .select('id')
              .eq('invited_email', normalizedEmail)
              .limit(1);
          if (inviteRows.isNotEmpty) {
            final unitId = inviteRows.first['id'] as String?;
            if (unitId != null) {
              await _client.from('units').update({
                'tenant_id': uid,
                'status': 'occupied',
              }).eq('id', unitId);
            }
          }
        }
      } catch (_) {
        // Link failure is non-fatal — dashboard Fallback 2 will retry.
      }
    }

    return _currentUser!;
  }

  // ─── Logout ──────────────────────────────────────────────────────────────

  Future<void> logout() async {
    try {
      await PushNotificationService.removeToken();
    } catch (_) {}
    await _client.auth.signOut();
    clearLocalSession();
  }

  /// Sends the confirmation email again. Used from the check-email screen.
  Future<void> resendSignupConfirmation(String email) async {
    await _client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: emailConfirmationRedirect(
        isWeb: kIsWeb,
        webOrigin: kIsWeb ? Uri.base.origin : '',
        webPath: kIsWeb ? Uri.base.path : '/',
      ),
    );
  }

  /// Reloads plan, trial, and RentSpree fields after a payment or a settings save.
  Future<void> refreshProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    final keptRole = _currentUser?.role;
    final profile = await _fetchProfile(uid);
    _currentUser = (keptRole != null && keptRole != profile.role)
        ? profile.copyWith(role: keptRole)
        : profile;
  }

  /// Drops the in-memory profile without calling the network.
  /// Used when Supabase reports that the session is already gone.
  void clearLocalSession() {
    _currentUser = null;
  }

  // ─── Password reset ──────────────────────────────────────────────────────

  Future<void> resetPassword(String email) async {
    await _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: passwordResetRedirect(
        isWeb: kIsWeb,
        origin: kIsWeb ? Uri.base.origin : '',
        path: kIsWeb ? Uri.base.path : '/',
      ),
    );
  }

  Future<void> updatePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  // ─── Welcome message flag ─────────────────────────────────────────────────

  Future<void> markWelcomeMessageSent() async {
    if (_currentUser == null) return;
    try {
      await _client
          .from('users')
          .update({'welcome_message_sent': true}).eq('id', _currentUser!.id);
    } catch (_) {}
    _currentUser = _currentUser!.copyWith(welcomeMessageSent: true);
  }

  // ─── Session restore ──────────────────────────────────────────────────────

  Future<void> restoreSession() async {
    final session = _client.auth.currentSession;
    if (session == null) {
      _currentUser = null;
      return;
    }
    final uid = session.user.id;
    try {
      final profileUser = await _fetchProfile(uid);

      // Apply the same role resolution as login() so vendors aren't
      // misrouted on app restart when the users row has a null/blank role.
      String metaRole = '';
      try {
        final freshUser = await _client.auth.getUser();
        metaRole = freshUser.user?.userMetadata?['role']?.toString() ?? '';
      } catch (_) {
        metaRole = session.user.userMetadata?['role']?.toString() ?? '';
      }

      final rowRole = profileUser.role;
      final resolvedRole =
          resolveStoredRole(rowRole: rowRole, metaRole: metaRole);

      _currentUser = (resolvedRole != rowRole)
          ? profileUser.copyWith(role: resolvedRole)
          : profileUser;

      // Auto-link tenant to their invited unit on session restore — identical
      // to the logic in login(). This ensures cold-starts and app-resumes
      // complete the link before the dashboard mounts, eliminating the
      // Fallback 2 retry delay on the tenant dashboard.
      if (resolvedRole == 'tenant') {
        try {
          final email = session.user.email?.toLowerCase().trim();
          final existing = await _client
              .from('units')
              .select('id')
              .eq('tenant_id', uid)
              .limit(1);
          if (existing.isEmpty && email != null) {
            final inviteRows = await _client
                .from('units')
                .select('id')
                .eq('invited_email', email)
                .limit(1);
            if (inviteRows.isNotEmpty) {
              final unitId = inviteRows.first['id'] as String?;
              if (unitId != null) {
                await _client.from('units').update({
                  'tenant_id': uid,
                  'status':    'occupied',
                }).eq('id', unitId);
              }
            }
          }
        } catch (_) {
          // Non-fatal — dashboard Fallback 2 remains as a safety net.
        }
      }
    } catch (_) {
      _currentUser = null;
    }
  }

  // ─── Private helpers ─────────────────────────────────────────────────────

  Future<AppUser> _fetchProfile(String userId) async {
    final data = await _client
        .from('users')
        .select()
        .eq('id', userId)
        .single();
    return _mapProfile(data).copyWith(
      planChoiceRequired: planChoiceRequiredFromMetadata(
        _client.auth.currentUser?.userMetadata?['plan_choice_required'],
      ),
    );
  }

  AppUser _mapProfile(Map<String, dynamic> row) {
    PaymentMethods? paymentMethods;
    final pmRaw = row['payment_methods'];
    if (pmRaw is Map || (pmRaw is String && pmRaw.trim().isNotEmpty)) {
      final parsed = PaymentMethods.fromStored(pmRaw);
      if (parsed.methods.isNotEmpty) paymentMethods = parsed;
    }
    return AppUser(
      id: row['id']?.toString() ?? '',
      email: row['email']?.toString() ?? '',
      fullName: row['full_name']?.toString() ?? '',
      role: row['role']?.toString() ?? 'landlord',
      phone: row['phone']?.toString(),
      avatarUrl: row['avatar_url']?.toString(),
      subscriptionPlan: row['subscription_plan']?.toString() ?? signupTrialPlan,
      subscriptionStatus: row['subscription_status']?.toString(),
      trialEndsAt: _toDateTime(row['trial_ends_at']),
      currentPeriodEnd: _toDateTime(row['current_period_end']),
      extraPropertyCount: (row['extra_property_count'] as num?)?.toInt() ?? 0,
      stripeCustomerId: row['stripe_customer_id']?.toString(),
      rentspreeInviteLink: row['rentspree_invite_link']?.toString(),
      foundingMember: row['founding_member'] == true,
      referralCode: row['referral_code']?.toString(),
      languagePreference: row['language_preference']?.toString() ?? 'en',
      createdAt: _toDateTime(row['created_at']) ?? DateTime.now(),
      welcomeMessageSent: row['welcome_message_sent'] == true,
      paymentMethods: paymentMethods,
    );
  }

  DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}
