import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/maintenance_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/dashboard/landlord_home.dart';

class LandlordDashboardScreen extends StatelessWidget {
  const LandlordDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final dashboard = context.watch<DashboardProvider>();
    final colors = Theme.of(context).extension<ElevoColors>()!;
    MaintenanceRequest? recent;
    for (final request in dashboard.requests) {
      if (request.status != 'Resolved') {
        recent = request;
        break;
      }
    }

    return Scaffold(
      backgroundColor: colors.canvas,
      body: dashboard.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: colors.olive,
              onRefresh: dashboard.loadData,
              child: LandlordHome(
                fullName: auth.currentUser?.fullName ?? '',
                occupancyRate: dashboard.occupancyRate,
                propertyCount: dashboard.properties.length,
                monthlyRent: dashboard.totalMonthlyIncome,
                confirmedThisMonth: dashboard.confirmedThisMonth,
                pendingRentCount: dashboard.pendingRentCount,
                onRentChanged: dashboard.loadData,
                openRepairs: dashboard.openMaintenanceCount,
                urgentRepairs: dashboard.urgentMaintenanceCount,
                properties: dashboard.properties,
                recentRepair: recent,
                loadError: dashboard.loadError,
              ),
            ),
    );
  }
}
