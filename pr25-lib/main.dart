import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:go_router/go_router.dart';

import 'core/elevo_logic.dart';
import 'core/web_location.dart';
import 'firebase_options.dart';
import 'theme/theme.dart';
import 'services/auth_service.dart';
import 'services/push_notification_service.dart';
import 'providers/auth_provider.dart';
import 'router/app_router.dart';
import 'services/theme_mode_store.dart';

// Top-level background message handler — must be a top-level function and
// annotated with @pragma('vm:entry-point') so the AOT compiler keeps it.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialized when this handler is called on Android.
  // No additional initialization needed here.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));

  // Firebase is only available on native mobile builds.
  // The web preview has no native platform channel, so skip init there.
  if (!kIsWeb) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  // Defaults stay on the live project. A practice build passes
  // --dart-define=SUPABASE_URL=... and --dart-define=SUPABASE_ANON_KEY=...
  const urlFromEnv = String.fromEnvironment('SUPABASE_URL');
  const keyFromEnv = String.fromEnvironment('SUPABASE_ANON_KEY');
  final launchFragment =
      browserFragment().isNotEmpty ? browserFragment() : Uri.base.fragment;
  final launchQuery =
      browserQuery().isNotEmpty ? browserQuery() : Uri.base.query;
  final recoveryAtLaunch = urlHasRecovery(
    fragment: launchFragment,
    query: launchQuery,
  );
  await Supabase.initialize(
    url: configuredSupabaseValue(urlFromEnv, defaultSupabaseUrl),
    anonKey: configuredSupabaseValue(keyFromEnv, defaultSupabaseAnonKey),
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
  final hadAuthCode = launchQuery.contains('code=') || launchFragment.contains('code=');
  if (kIsWeb && (recoveryAtLaunch || hadAuthCode)) {
    final next = recoveryAtLaunch
        ? '/reset-password'
        : (pendingAppPath(launchFragment) ?? '/splash');
    replaceBrowserHash(next);
  }
  final expiredAuthLink = hadAuthCode &&
      Supabase.instance.client.auth.currentSession == null;
  runApp(ElevoApp(
    passwordRecovery: recoveryAtLaunch && !expiredAuthLink,
    expiredAuthLink: expiredAuthLink,
  ));
}

class ElevoApp extends StatefulWidget {
  final bool passwordRecovery;
  final bool expiredAuthLink;

  const ElevoApp({
    super.key,
    this.passwordRecovery = false,
    this.expiredAuthLink = false,
  });

  @override
  State<ElevoApp> createState() => _ElevoAppState();
}

class _ElevoAppState extends State<ElevoApp> {
  late final AuthProvider _authProvider;
  late final ThemeModeController _themeMode;
  late final GoRouter _router;
  bool _pushInitialized = false;

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider(
      authService: AuthService(),
      passwordRecoveryAtLaunch: widget.passwordRecovery,
      expiredAuthLink: widget.expiredAuthLink,
    );
    _themeMode = ThemeModeController();
    _themeMode.load();
    _router = AppRouter.router(_authProvider);

    // After each login, initialize push once per session.
    _authProvider.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onAuthChanged);
    _themeMode.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (_authProvider.isLoggedIn && !_pushInitialized && !kIsWeb) {
      _pushInitialized = true;
      PushNotificationService.initialize(
        onNotificationTap: _handleNotificationTap,
      );
    }
    if (!_authProvider.isLoggedIn) {
      _pushInitialized = false;
    }
  }

  /// Routes the user to the correct screen based on the [type] field
  /// in the FCM data payload. Called on both foreground tap and cold-start.
  void _handleNotificationTap(Map<String, dynamic> data) {
    final type   = data['type']       as String? ?? '';
    final unitId = data['unit_id']    as String? ?? '';

    final destination = notificationRoute(
      role: _authProvider.currentUser?.role,
      type: type,
      unitId: unitId,
    );
    if (destination != null) {
      _router.push(destination);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _themeMode),
      ],
      child: ListenableBuilder(
        listenable: _themeMode,
        builder: (context, _) => MaterialApp.router(
        title: 'Elevo',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: _themeMode.mode,
        builder: (context, child) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
              statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        routerConfig: _router,
        ),
      ),
    );
  }
}