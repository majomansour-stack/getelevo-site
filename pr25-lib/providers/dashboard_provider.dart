import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/elevo_logic.dart';
import '../models/property_model.dart';
import '../models/maintenance_model.dart';
import '../models/calendar_event_model.dart';

class DashboardProvider extends ChangeNotifier {
  final _db = Supabase.instance.client;

  List<Property> _properties = [];
  List<Property> get properties => _properties;

  List<MaintenanceRequest> _requests = [];
  List<MaintenanceRequest> get requests => _requests;

  List<CalendarEvent> _events = [];
  List<CalendarEvent> get events => _events;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String? _loadError;
  String? get loadError => _loadError;

  double _outstandingBalance = 0;
  double get outstandingBalance => _outstandingBalance;

  double _confirmedThisMonth = 0;
  double get confirmedThisMonth => _confirmedThisMonth;

  int _pendingRentCount = 0;
  int get pendingRentCount => _pendingRentCount;

  double get totalMonthlyIncome =>
      _properties.fold(0.0, (sum, p) => sum + p.monthlyIncome);

  /// Share of units that are occupied. A duplex with one vacant unit is 50%.
  double get occupancyRate {
    final total = _properties.fold<int>(0, (sum, p) => sum + p.totalUnits);
    final occupied = _properties.fold<int>(0, (sum, p) => sum + p.occupiedUnits);
    return occupancyRateFromCounts(occupiedUnits: occupied, totalUnits: total);
  }

  int get openMaintenanceCount =>
      _requests.where((r) => r.status != 'Resolved').length;

  int get urgentMaintenanceCount =>
      _requests.where((r) => r.isEmergency && r.status != 'Resolved').length;

  /// Current rent roll for this month only. Earlier months are left at zero
  /// until confirmed payments are loaded; the old curve invented history.
  List<double> get monthlyIncomeData {
    final monthIndex = DateTime.now().month - 1;
    return List.generate(12, (i) => i == monthIndex ? totalMonthlyIncome : 0);
  }

  Future<void> loadData() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Load properties with their units
      final propRows = await _db
          .from('properties')
          .select('*, units(*)')
          .eq('landlord_id', uid)
          .order('created_at');

      final properties = <Property>[];
      for (final row in propRows) {
        final unitRows = (row['units'] as List<dynamic>?) ?? [];
        final units = unitRows.map<Unit>((u) => _mapUnit(Map<String, dynamic>.from(u as Map))).toList();
        final photo = await _signedPropertyPhoto(row['image_url']?.toString());
        properties.add(_mapProperty(row, units, photo));
      }
      _properties = properties;

      // Load open maintenance requests
      final mrRows = await _db
          .from('maintenance_requests')
          .select()
          .eq('landlord_id', uid)
          .neq('status', 'closed')
          .order('created_at', ascending: false);

      _requests = mrRows.map<MaintenanceRequest>(_mapMaintenance).toList();

      // Load upcoming calendar events
      final evtRows = await _db
          .from('calendar_events')
          .select()
          .eq('landlord_id', uid)
          .gte('start_date', DateTime.now().subtract(const Duration(days: 1)).toIso8601String())
          .order('start_date');

      _events = evtRows.map<CalendarEvent>(_mapCalendarEvent).toList();

      // Load outstanding balance — sum of pending_confirmation payments for
      // all units belonging to this landlord.
      try {
        final unitIds = _properties
            .expand((p) => p.units)
            .map((u) => u.id)
            .toList();
        if (unitIds.isNotEmpty) {
          final dueByUnit = {
            for (final property in _properties)
              for (final unit in property.units) unit.id: unit.rentDueDay,
          };
          final payRows = await _paymentRows(unitIds);
          final now = DateTime.now();
          var pending = 0.0;
          var pendingCount = 0;
          var confirmed = 0.0;
          for (final row in payRows) {
            final amount = ((row['amount'] as num?) ?? 0).toDouble();
            final status = (row['status'] as String?) ?? '';
            if (status == 'pending_confirmation') {
              pending += amount;
              pendingCount += 1;
              continue;
            }
            if (status != 'confirmed') continue;
            final when = confirmedRentMonth(
              period: DateTime.tryParse((row['rent_period'] ?? '').toString()),
              submittedAt: DateTime.tryParse((row['submitted_at'] ?? '').toString()),
              dueDay: dueByUnit[row['unit_id']?.toString() ?? ''],
            );
            if (when != null && when.year == now.year && when.month == now.month) {
              confirmed += amount;
            }
          }
          _outstandingBalance = pending;
          _pendingRentCount = pendingCount;
          _confirmedThisMonth = confirmed;
        } else {
          _outstandingBalance = 0;
          _pendingRentCount = 0;
          _confirmedThisMonth = 0;
        }
      } catch (_) {
        _outstandingBalance = 0;
        _pendingRentCount = 0;
        _confirmedThisMonth = 0;
      }
    } catch (_) {
      _loadError = 'Could not load your portfolio. Pull to refresh.';
      _properties = [];
      _requests = [];
      _events = [];
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> _paymentRows(List<String> unitIds) async {
    try {
      final rows = await _db
          .from('payments')
          .select('amount, status, submitted_at, unit_id, rent_period')
          .inFilter('unit_id', unitIds);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      final rows = await _db
          .from('payments')
          .select('amount, status, submitted_at, unit_id')
          .inFilter('unit_id', unitIds);
      return List<Map<String, dynamic>>.from(rows as List);
    }
  }

  // ── Mappers ────────────────────────────────────────────────────────────────

  Future<String?> _signedPropertyPhoto(String? stored) async {
    final value = stored?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    final path = propertyPhotoObjectPath(value);
    if (path == null) return value;
    try {
      return await _db.storage.from('documents').createSignedUrl(path, 60 * 60 * 24 * 7);
    } catch (_) {
      return null;
    }
  }

  Property _mapProperty(Map<String, dynamic> row, List<Unit> units, String? photoUrl) {
    return Property(
      id: row['id'] as String,
      landlordId: row['landlord_id'] as String,
      name: row['name'] as String,
      address: row['address'] as String,
      city: (row['city'] as String?) ?? '',
      state: (row['state'] as String?) ?? 'AZ',
      zip: (row['zip'] as String?) ?? '',
      photoUrl: photoUrl,
      createdAt: DateTime.parse(row['created_at'] as String),
      units: units,
    );
  }

  Unit _mapUnit(Map<String, dynamic> u) {
    return Unit(
      id: u['id'] as String,
      propertyId: u['property_id'] as String,
      landlordId: u['landlord_id'] as String,
      unitNumber: (u['unit_number'] as String?) ?? '',
      tenantId: u['tenant_id'] as String?,
      tenantName: u['tenant_name'] as String?,
      rentAmount: ((u['rent_amount'] as num?) ?? 0).toDouble(),
      bedrooms: parseBedrooms(u['bedrooms']),
      bathrooms: parseBathrooms(u['bathrooms']),
      leaseStart: u['lease_start'] != null ? DateTime.tryParse(u['lease_start'].toString()) : null,
      leaseEnd: u['lease_end'] != null ? DateTime.tryParse(u['lease_end'].toString()) : null,
      depositAmount: ((u['deposit_amount'] as num?) ?? 0).toDouble(),
      status: (u['status'] as String?) ?? 'vacant',
      createdAt: DateTime.parse(u['created_at'] as String),
      rentDueDay: parseRentDueDay(u['rent_due_day']),
    );
  }

  MaintenanceRequest _mapMaintenance(Map<String, dynamic> r) {
    return MaintenanceRequest(
      id: r['id']?.toString() ?? '',
      unitId: (r['unit_id'] as String?) ?? '',
      propertyId: '',
      landlordId: (r['landlord_id'] as String?) ?? '',
      submittedBy: (r['tenant_id'] as String?) ?? '',
      description: (r['description'] as String?) ?? '',
      category: (r['category'] as String?) ?? 'Other',
      priority: _capitalize((r['priority'] as String?) ?? 'medium'),
      status: mapMaintenanceStatus((r['status'] as String?) ?? 'open'),
      assignedVendorId: r['vendor_user_id']?.toString(),
      assignedVendorName: r['vendor_name'] as String?,
      estimatedCost: r['estimated_cost'] != null ? (r['estimated_cost'] as num).toDouble() : null,
      unitAddress: r['unit_address'] as String?,
      createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ?? DateTime.now(),
      resolvedAt: firstParsedDate(r, ['resolved_at', 'resolved_date']),
      photos: repairPhotoPaths(r['photo_paths']),
    );
  }

  CalendarEvent _mapCalendarEvent(Map<String, dynamic> e) {
    return CalendarEvent(
      id: e['id'] as String,
      landlordId: e['landlord_id'] as String,
      unitId: e['unit_id'] as String?,
      propertyId: e['property_id'] as String?,
      eventType: (e['type'] as String?) ?? 'other',
      eventDate: DateTime.parse(e['start_date'] as String),
      title: e['title'] as String,
      subtitle: e['description'] as String?,
      isCompleted: e['is_completed'] == true,
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
