import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/elevo_logic.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/messages_provider.dart';
import '../screens/check_email_screen.dart';
import '../core/web_location.dart';
import '../screens/account_profile_screen.dart';
import '../screens/reset_password_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/tenant/tenant_payment_history_screen.dart';
import 'elevo_auth_wiring.dart';
import '../screens/landlord/landlord_shell.dart';
import '../screens/landlord/landlord_dashboard_screen.dart';
import '../screens/landlord/properties_screen.dart';
import '../screens/landlord/property_detail_screen.dart';
import '../screens/landlord/messages_list_screen.dart';
import '../screens/landlord/more_screen.dart';
import '../screens/landlord/maintenance_landlord_screen.dart';
import '../screens/landlord/vendors_screen.dart';
import '../screens/landlord/calendar_screen.dart';
import '../screens/choose_plan_screen.dart';
import '../screens/subscription_screen.dart';
import '../screens/landlord/invite_tenant_screen.dart';
import '../screens/landlord/screening_list_screen.dart';
import '../providers/screening_provider.dart';
import '../screens/landlord/add_edit_property_screen.dart';
import '../screens/landlord/add_edit_unit_screen.dart';
import '../screens/tenant/tenant_shell.dart';
import '../screens/tenant/tenant_dashboard_screen.dart';
import '../screens/tenant/tenant_messages_screen.dart';
import '../screens/tenant/tenant_maintenance_screen.dart';
import '../screens/tenant/tenant_more_screen.dart';
import '../screens/tenant/tenant_notification_preferences_screen.dart';
import '../screens/tenant/tenant_settings_screen.dart';
import '../screens/tenant/tenant_photo_log_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/documents_screen.dart';
import '../screens/qanda_screen.dart';
import '../screens/landlord/private_vault_screen.dart';
import '../screens/landlord/referral_screen.dart';
import '../screens/landlord/reporting_screen.dart';
import '../screens/landlord/vendor_detail_screen.dart';
import '../screens/landlord/notification_preferences_screen.dart';
import '../screens/partners/preferred_partners_screen.dart';
import '../screens/partners/partner_join_screen.dart';
import '../screens/partners/partner_applications_screen.dart';
import '../providers/partner_provider.dart';
import '../screens/vendor/vendor_shell.dart';
import '../screens/vendor/vendor_dashboard_screen.dart';
import '../screens/vendor/vendor_jobs_screen.dart';
import '../screens/vendor/vendor_reporting_screen.dart';
import '../screens/vendor/vendor_signup_screen.dart';
import '../screens/vendor/vendor_subscription_screen.dart';
import '../screens/vendor/vendor_messages_screen.dart';
import '../screens/landlord/bulk_announcement_screen.dart';
import '../screens/landlord/payment_methods_screen.dart';
import '../screens/landlord/rentspree_link_screen.dart';

final _rootKey        = GlobalKey<NavigatorState>();
final _lBranch0Key    = GlobalKey<NavigatorState>();
final _lBranch1Key    = GlobalKey<NavigatorState>();
final _lBranch2Key    = GlobalKey<NavigatorState>();
final _lBranch3Key    = GlobalKey<NavigatorState>();
final _tBranch0Key    = GlobalKey<NavigatorState>();
final _tBranch1Key    = GlobalKey<NavigatorState>();
final _tBranch2Key    = GlobalKey<NavigatorState>();
final _tBranch3Key    = GlobalKey<NavigatorState>();
final _vBranch0Key    = GlobalKey<NavigatorState>();
final _vBranch1Key    = GlobalKey<NavigatorState>();
final _vBranch2Key    = GlobalKey<NavigatorState>();
final _vBranch3Key    = GlobalKey<NavigatorState>();

class AppRouter {
  static GoRouter router(AuthProvider authProvider) => GoRouter(
    navigatorKey: _rootKey,
    initialLocation: startupLocation(
      fragment: browserFragment().isNotEmpty
          ? browserFragment()
          : Uri.base.fragment,
      query: browserQuery().isNotEmpty ? browserQuery() : Uri.base.query,
    ),
    refreshListenable: authProvider,
    redirect: (context, state) {
      // Use the full URI path so we check the destination, not the current location.
      final user = authProvider.currentUser;
      return authRedirect(
        loggedIn: authProvider.isLoggedIn,
        role: user?.role,
        destination: state.uri.path,
        startLandlordCheckout: state.uri.queryParameters['checkout'] == '1',
        plan: user?.subscriptionPlan,
        status: user?.subscriptionStatus,
        trialEndsAt: user?.trialEndsAt,
        planChoiceRequired: user?.planChoiceRequired ?? false,
        sessionReady: authProvider.sessionReady,
        passwordRecovery: authProvider.passwordRecovery,
      );
    },
    routes: [
      GoRoute(path: '/splash',         builder: (_, __) => const SplashScreen()),
      GoRoute(
        path: '/login',
        builder: (_, state) => buildElevoLogin(
          initialError: state.uri.queryParameters['link'] == 'expired'
              ? 'This reset link is invalid or has expired. Request a new one.'
              : null,
        ),
      ),
      GoRoute(
        path: '/signup',
        builder: (_, state) => buildElevoSignUp(
          initialEmail: state.uri.queryParameters['email'],
          initialRole: state.uri.queryParameters['role'],
        ),
      ),
      GoRoute(path: '/reset-password', builder: (_, __) => const ResetPasswordScreen()),
      GoRoute(path: '/account/profile', builder: (_, __) => const AccountProfileScreen()),
      GoRoute(
        path: '/check-email',
        builder: (_, state) => CheckEmailScreen(
          email: state.uri.queryParameters['email'] ?? '',
        ),
      ),
      GoRoute(path: '/vendor-signup',  builder: (_, __) => const VendorSignupScreen()),
      GoRoute(path: '/choose-plan',    builder: (_, __) => const ChoosePlanScreen()),
      GoRoute(path: '/terms',          builder: (_, __) => buildElevoTerms()),
      GoRoute(path: '/privacy',        builder: (_, __) => buildElevoPrivacy()),

      // ── Preferred Partners directory (landlord + tenant) ─────────────────
      GoRoute(
        path: '/partners',
        builder: (context, __) => ChangeNotifierProvider(
          create: (_) => PartnerProvider(),
          child: const PreferredPartnersScreen(),
        ),
        routes: [
          GoRoute(
            path: 'join',
            builder: (context, __) => ChangeNotifierProvider(
              create: (_) => PartnerProvider(),
              child: const PartnerJoinScreen(),
            ),
          ),
        ],
      ),

      // ── Admin panel (admin role only) ─────────────────────────────────────
      GoRoute(
        path: '/admin/partner-applications',
        builder: (context, __) => ChangeNotifierProvider(
          create: (_) => PartnerProvider(),
          child: const PartnerApplicationsScreen(),
        ),
      ),

      // ── Landlord Shell ──────────────────────────────────────────────
      // DashboardProvider is hoisted to the shell level so all 4 branches
      // (Dashboard, Properties, Messages, More) share one instance and
      // every sub-route (maintenance, calendar, reports, screening, invite)
      // can call context.watch/read<DashboardProvider>() without crashing.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => ChangeNotifierProvider(
          create: (_) => DashboardProvider()..loadData(),
          child: LandlordShell(child: navigationShell),
        ),
        branches: [
          // Branch 0 – Overview / Dashboard
          StatefulShellBranch(
            navigatorKey: _lBranch0Key,
            routes: [
              GoRoute(
                path: '/landlord',
                builder: (_, __) => const LandlordDashboardScreen(),
                routes: [
                  GoRoute(
                    path: 'property/:id',
                    builder: (context, state) => PropertyDetailScreen(
                      propertyId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Branch 1 – Properties
          StatefulShellBranch(
            navigatorKey: _lBranch1Key,
            routes: [
              GoRoute(
                path: '/landlord/properties',
                builder: (_, __) => const PropertiesScreen(),
                routes: [
                  GoRoute(
                    path: 'add',
                    builder: (_, __) => const AddEditPropertyScreen(),
                  ),
                  GoRoute(
                    path: 'announce',
                    builder: (_, __) => const BulkAnnouncementScreen(),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => PropertyDetailScreen(
                      propertyId: state.pathParameters['id']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        builder: (context, state) => AddEditPropertyScreen(
                          propertyId: state.pathParameters['id'],
                        ),
                      ),
                      GoRoute(
                        path: 'add-unit',
                        builder: (context, state) => AddEditUnitScreen(
                          propertyId: state.pathParameters['id']!,
                        ),
                      ),
                      GoRoute(
                        path: 'unit/:unitId/edit',
                        builder: (context, state) => AddEditUnitScreen(
                          propertyId: state.pathParameters['id']!,
                          unitId: state.pathParameters['unitId'],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          // Branch 2 – Messages
          StatefulShellBranch(
            navigatorKey: _lBranch2Key,
            routes: [
              GoRoute(
                path: '/landlord/messages',
                builder: (context, state) => ChangeNotifierProvider(
                  create: (_) => MessagesProvider()..loadConversations(),
                  child: const MessagesListScreen(),
                ),
                routes: [
                  GoRoute(
                    path: 'chat/:unitId',
                    builder: (context, state) {
                      final unitId = state.pathParameters['unitId']!;
                      final name   = state.uri.queryParameters['name'] ?? '';
                      final addr   = state.uri.queryParameters['addr'] ?? '';
                      return ChangeNotifierProvider(
                        create: (_) => MessagesProvider(),
                        child: ChatScreen(
                          unitId: unitId,
                          otherPartyName: name,
                          unitAddress: addr,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),

          // Branch 3 – More
          StatefulShellBranch(
            navigatorKey: _lBranch3Key,
            routes: [
              GoRoute(
                path: '/landlord/more',
                builder: (_, __) => const MoreScreen(),
                routes: [
                  GoRoute(path: 'maintenance',    builder: (_, __) => const MaintenanceLandlordScreen()),
                  GoRoute(
                    path: 'vendors',
                    builder: (_, __) => const VendorsScreen(),
                    routes: [
                      GoRoute(
                        path: ':vendorId',
                        builder: (_, state) => VendorDetailScreen(
                          vendorId: state.pathParameters['vendorId']!,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(path: 'calendar',       builder: (_, __) => const CalendarScreen()),
                  GoRoute(path: 'documents',      builder: (_, __) => const DocumentsScreen(isLandlord: true)),
                  GoRoute(path: 'subscription',   builder: (_, __) => const SubscriptionScreen()),
                  GoRoute(path: 'rentspree',      builder: (_, __) => const RentSpreeLinkScreen()),
                  GoRoute(path: 'invite-tenant',  builder: (_, __) => const InviteTenantScreen()),
                  GoRoute(
                    path: 'screening',
                    builder: (context, __) {
                      final auth = context.read<AuthProvider>();
                      return ChangeNotifierProvider(
                        create: (_) => ScreeningProvider(
                          landlordId: auth.currentUser?.id ?? '',
                          landlordFullName: auth.currentUser?.fullName ?? 'Landlord',
                        )..load(),
                        child: const ScreeningListScreen(),
                      );
                    },
                  ),
                  GoRoute(path: 'vault',          builder: (_, __) => const PrivateVaultScreen()),
                  GoRoute(path: 'reports',        builder: (_, __) => const ReportingScreen()),
                  GoRoute(path: 'referral',       builder: (_, __) => const ReferralScreen()),
                  GoRoute(path: 'qanda',          builder: (_, __) => const QAndAScreen(isLandlord: true)),
                  GoRoute(path: 'payment-methods', builder: (_, __) => const PaymentMethodsScreen()),
                 GoRoute(path: 'notifications',  builder: (_, __) => const NotificationPreferencesScreen()),
                ],
              ),
            ],
          ),
        ],
      ),

      // ── Vendor Shell ────────────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            VendorShell(child: navigationShell),
        branches: [
          // Branch 0 – Dashboard
          StatefulShellBranch(
            navigatorKey: _vBranch0Key,
            routes: [
              GoRoute(
                path: '/vendor',
                builder: (_, __) => const VendorDashboardScreen(),
              ),
            ],
          ),
          // Branch 1 – Jobs
          StatefulShellBranch(
            navigatorKey: _vBranch1Key,
            routes: [
              GoRoute(
                path: '/vendor/jobs',
                builder: (_, __) => const VendorJobsScreen(),
              ),
            ],
          ),
          // Branch 2 – Messages
          StatefulShellBranch(
            navigatorKey: _vBranch2Key,
            routes: [
              GoRoute(
                path: '/vendor/messages',
                builder: (_, __) => const VendorMessagesScreen(),
                routes: [
                  GoRoute(
                    path: ':unitId',
                    builder: (context, state) {
                      final unitId = state.pathParameters['unitId']!;
                      final name = state.uri.queryParameters['name'] ?? 'Landlord';
                      final addr = state.uri.queryParameters['addr'] ?? '';
                      return ChangeNotifierProvider(
                        create: (_) => MessagesProvider(),
                        child: ChatScreen(
                          unitId: unitId,
                          otherPartyName: name,
                          unitAddress: addr,
                          counterpartyId: state.uri.queryParameters['with'],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 3 – Reports
          StatefulShellBranch(
            navigatorKey: _vBranch3Key,
            routes: [
              GoRoute(
                path: '/vendor/reports',
                builder: (_, __) => const VendorReportingScreen(),
              ),
            ],
          ),
          // Branch 4 – Subscription / Plan
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(),
            routes: [
              GoRoute(
                path: '/vendor/subscription',
                builder: (_, __) => const VendorSubscriptionScreen(),
              ),
            ],
          ),
        ],
      ),

      // ── Tenant Shell ────────────────────────────────────────────────
      // MessagesProvider is hoisted to shell scope so the dashboard can
      // inject the one-time welcome message and the Messages tab reads
      // from the same instance without duplication.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ChangeNotifierProvider(
              create: (_) => MessagesProvider(),
              child: TenantShell(child: navigationShell),
            ),
        branches: [
          // Branch 0 – Home
          StatefulShellBranch(
            navigatorKey: _tBranch0Key,
            routes: [
              GoRoute(
                path: '/tenant',
                builder: (_, __) => const TenantDashboardScreen(),
                routes: [
                  GoRoute(
                    path: 'payments',
                    builder: (_, __) => const TenantPaymentHistoryScreen(),
                  ),
                ],
              ),
            ],
          ),

          // Branch 1 – Messages
          StatefulShellBranch(
            navigatorKey: _tBranch1Key,
            routes: [
              GoRoute(
                path: '/tenant/messages',
                builder: (_, __) => const TenantMessagesScreen(),
              ),
            ],
          ),

          // Branch 2 – Maintenance
          StatefulShellBranch(
            navigatorKey: _tBranch2Key,
            routes: [
              GoRoute(
                path: '/tenant/maintenance',
                builder: (_, __) => const TenantMaintenanceScreen(),
                routes: [
                  GoRoute(
                    path: 'chat/:unitId',
                    builder: (context, state) {
                      final unitId = state.pathParameters['unitId']!;
                      final name = state.uri.queryParameters['name'] ?? 'Vendor';
                      final addr = state.uri.queryParameters['addr'] ?? '';
                      return ChangeNotifierProvider(
                        create: (_) => MessagesProvider(),
                        child: ChatScreen(
                          unitId: unitId,
                          otherPartyName: name,
                          unitAddress: addr,
                          counterpartyId: state.uri.queryParameters['with'],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),

          // Branch 3 – More
          StatefulShellBranch(
            navigatorKey: _tBranch3Key,
            routes: [
              GoRoute(
                path: '/tenant/more',
                builder: (_, __) => const TenantMoreScreen(),
                routes: [
                  GoRoute(path: 'documents',      builder: (_, __) => const DocumentsScreen(isLandlord: false)),
                  GoRoute(path: 'qanda',           builder: (_, __) => const QAndAScreen(isLandlord: false)),
                  GoRoute(path: 'notifications',   builder: (_, __) => const TenantNotificationPreferencesScreen()),
                  GoRoute(path: 'settings',        builder: (_, __) => const TenantSettingsScreen()),
                  GoRoute(path: 'photos',          builder: (_, __) => const TenantPhotoLogScreen()),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
