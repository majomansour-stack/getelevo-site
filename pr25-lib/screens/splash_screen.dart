import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/elevo_logic.dart';
import '../core/web_location.dart';
import '../providers/auth_provider.dart';
import '../theme/theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _fadeIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.6, curve: Curves.easeOut),
    );
    _controller.forward();

    // Wait for both the animation AND the session restore to finish,
    // whichever takes longer, before deciding where to navigate.
    _waitThenNavigate();
  }

  Future<void> _waitThenNavigate() async {
    final auth = context.read<AuthProvider>();

    // Run the animation minimum and the session restore in parallel.
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 2200)),
      auth.waitForRestore(),
    ]);

    if (!mounted) return;
    final fragment =
        browserFragment().isNotEmpty ? browserFragment() : Uri.base.fragment;
    final pending = pendingAppPath(fragment);
    if (auth.passwordRecovery) {
      context.go('/reset-password');
      return;
    }
    if (auth.isLoggedIn) {
      final role = auth.currentUser?.role ?? '';
      if (pending != null) {
        final user = auth.currentUser;
        final redirect = authRedirect(
          loggedIn: true,
          role: role,
          destination: pending,
          plan: user?.subscriptionPlan,
          status: user?.subscriptionStatus,
          trialEndsAt: user?.trialEndsAt,
          planChoiceRequired: user?.planChoiceRequired ?? false,
        );
        context.go(redirect ?? pending);
        return;
      }
      context.go(homeRouteForRole(role));
    } else if (pending != null && authEntryRoutes.contains(pending)) {
      context.go(pending);
    } else if (auth.expiredAuthLink) {
      context.go('/login?link=expired');
    } else {
      context.go('/login');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: FadeTransition(
          opacity: _fadeIn,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/elevo_logo.png',
                height: 353,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: AppTheme.spacingMd),
              Text(
                'Property management, elevated.',
                style: theme.textTheme.bodySmall?.copyWith(
                  letterSpacing: 2.5,
                  fontSize: 12,
                  color: Theme.of(context).extension<ElevoColors>()!.midnight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
