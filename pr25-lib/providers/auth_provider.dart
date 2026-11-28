import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;
import '../core/billing_rules.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class SignupResult {
  final bool signedIn;
  final String? confirmEmail;

  const SignupResult({required this.signedIn, this.confirmEmail});

  bool get needsEmailConfirmation => confirmEmail != null && confirmEmail!.isNotEmpty;
}

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  late final StreamSubscription _authSub;

  // Completes when the initial restoreSession() call finishes.
  late final Future<void> _restoreFuture;

  /// Awaitable that resolves once the initial session restore is done.
  Future<void> waitForRestore() => _restoreFuture;

  bool _sessionReady = false;
  bool get sessionReady => _sessionReady;

  bool _passwordRecovery;
  bool get passwordRecovery => _passwordRecovery;

  /// A reset or sign-in code was in the launch URL and did not become a session.
  final bool expiredAuthLink;

  AuthProvider({
    required AuthService authService,
    bool passwordRecoveryAtLaunch = false,
    this.expiredAuthLink = false,
  })  : _authService = authService,
        _passwordRecovery = passwordRecoveryAtLaunch {
    // Restore any existing session on cold start.
    _restoreFuture = _authService.restoreSession().whenComplete(() {
      _sessionReady = true;
      notifyListeners();
    });

    // Listen for sign-in / sign-out events from Supabase.
    _authSub = _authService.authStateChanges.listen((authState) async {
      switch (authState.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.tokenRefreshed:
        case AuthChangeEvent.userUpdated:
          // Only restore if the profile isn't already set (e.g. cold-start
          // token refresh). During signup/login the profile is fetched
          // directly — skip restoreSession to avoid stomping that already-correct result.
          // This prevents the signedIn event (which fires ~200ms after login completes)
          // from overwriting a correctly-fetched vendor profile with a stale/wrong one.
          if (_authService.currentUser == null) {
            await _authService.restoreSession();
            notifyListeners();
          }
          // If currentUser is already set (login path), do NOT notify again —
          // _login() in login_screen.dart already reads the role and calls context.go().
          break;
        case AuthChangeEvent.signedOut:
          _passwordRecovery = false;
          _authService.clearLocalSession();
          notifyListeners();
          break;
        case AuthChangeEvent.passwordRecovery:
          _passwordRecovery = true;
          if (_authService.currentUser == null) {
            await _authService.restoreSession();
          }
          _sessionReady = true;
          notifyListeners();
          break;
        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  // ─── Accessors ──────────────────────────────────────────────────────────

  AppUser? get currentUser => _authService.currentUser;
  bool get isLoggedIn      => _authService.isLoggedIn;
  bool get isLandlord      => currentUser?.isLandlord ?? false;
  bool get isVendor        => currentUser?.isVendor ?? false;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  // ─── Auth actions ────────────────────────────────────────────────────────

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _authService.login(email, password);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = loginErrorMessage(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<SignupResult> signup({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    required String role,
    Map<String, String> vendorDetails = const {},
    String referralCode = '',
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _authService.signup(
        fullName: fullName,
        email: email,
        phone: phone,
        password: password,
        role: role,
        vendorDetails: vendorDetails,
        referralCode: referralCode,
      );
      _isLoading = false;
      notifyListeners();
      return const SignupResult(signedIn: true);
    } on EmailConfirmationRequired catch (e) {
      _isLoading = false;
      notifyListeners();
      return SignupResult(signedIn: false, confirmEmail: e.email);
    } catch (e) {
      _error = loginErrorMessage(e);
      _isLoading = false;
      notifyListeners();
      return const SignupResult(signedIn: false);
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    notifyListeners();
  }

  Future<void> resetPassword(String email) async {
    await _authService.resetPassword(email);
  }

  Future<void> updatePassword(String password) async {
    await _authService.updatePassword(password);
    _passwordRecovery = false;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    await _authService.refreshProfile();
    notifyListeners();
  }

  /// Null when the email was sent. Otherwise a short message.
  Future<String?> resendSignupConfirmation(String email) async {
    try {
      await _authService.resendSignupConfirmation(email);
      return null;
    } catch (e) {
      return loginErrorMessage(e);
    }
  }

  /// Marks the welcome message as sent so it is never injected again.
  Future<void> markWelcomeMessageSent() async {
    await _authService.markWelcomeMessageSent();
    notifyListeners();
  }

}
