import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/billing_rules.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';

/// True when this landlord may create [kind]. Otherwise opens the
/// subscription screen, which explains the trial or the plan limit.
bool landlordCreateAllowed(BuildContext context, LandlordCreateKind kind) {
  final user = context.read<AuthProvider>().currentUser;
  var propertyCount = 0;
  var unitCount = 0;
  try {
    final properties = context.read<DashboardProvider>().properties;
    propertyCount = properties.length;
    unitCount = properties.fold<int>(0, (sum, property) => sum + property.units.length);
  } catch (_) {}

  final decision = landlordCreateDecision(
    role: user?.role,
    plan: user?.subscriptionPlan,
    status: user?.subscriptionStatus,
    trialEndsAt: user?.trialEndsAt,
    extraProperties: user?.extraPropertyCount ?? 0,
    propertyCount: propertyCount,
    unitCount: unitCount,
    kind: kind,
    now: DateTime.now(),
  );
  if (decision.allowed) return true;
  final message = decision.message;
  if (message != null && message.isNotEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
  context.go('/landlord/more/subscription');
  return false;
}

bool planLimitBlocked(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('subscription required') || text.contains('plan limit');
}

/// True when [error] is a plan block and the subscription screen was opened.
bool openSubscriptionForPlanError(BuildContext context, Object error) {
  final atPropertyLimit = isPropertyPlanLimitError(error);
  if (!atPropertyLimit && !planLimitBlocked(error)) return false;
  if (atPropertyLimit) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(propertyPlanLimitReachedMessage)),
    );
  }
  context.go('/landlord/more/subscription');
  return true;
}
