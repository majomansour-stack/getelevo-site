import 'package:flutter/material.dart';
import '../models/partner_model.dart';
import '../services/partner_service.dart';

/// Max spots for the Platinum tier across the entire directory.
const int kPlatinumMaxSpots = 2;

/// Max spots for the Preferred tier per category.
const int kPreferredMaxSpotsPerCategory = 2;

/// Manages the Preferred Partners directory and admin application panel.
/// Route-scoped — wired in app_router.dart at the /partners route.
class PartnerProvider extends ChangeNotifier {
  final PartnerService _service;

  PartnerProvider({PartnerService? service})
      : _service = service ?? PartnerService();

  // ── Directory state ────────────────────────────────────────────────────
  List<PartnerListing> _allListings = [];
  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool _isLoading = false;
  String? _error;

  List<PartnerListing> get allListings => _allListings;
  String get selectedCategory => _selectedCategory;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// True when the Platinum tier has reached its global spot limit.
  bool get isPlatinumFull {
    final count = _allListings.where((l) => l.tier == PartnerTier.platinum).length;
    return count >= kPlatinumMaxSpots;
  }

  /// Returns the set of categories where Preferred spots are fully taken.
  Set<String> get preferredFullCategories {
    final counts = <String, int>{};
    for (final l in _allListings) {
      if (l.tier == PartnerTier.preferred) {
        counts[l.category] = (counts[l.category] ?? 0) + 1;
      }
    }
    return counts.entries
        .where((e) => e.value >= kPreferredMaxSpotsPerCategory)
        .map((e) => e.key)
        .toSet();
  }

  List<PartnerListing> get filteredListings {
    var list = _allListings;
    if (_selectedCategory != 'All') {
      list = list.where((v) => v.category == _selectedCategory).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((v) =>
              v.businessName.toLowerCase().contains(q) ||
              v.category.toLowerCase().contains(q) ||
              v.serviceArea.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  /// Returns listings grouped by category, each group sorted by tier then name.
  Map<String, List<PartnerListing>> get listingsByCategory {
    final grouped = <String, List<PartnerListing>>{};
    for (final listing in filteredListings) {
      grouped.putIfAbsent(listing.category, () => []).add(listing);
    }
    return grouped;
  }

  // ── Admin state ────────────────────────────────────────────────────────
  List<PartnerApplication> _applications = [];
  String _adminFilter = 'All';

  List<PartnerApplication> get applications => _applications;
  String get adminFilter => _adminFilter;

  List<PartnerApplication> get filteredApplications {
    if (_adminFilter == 'All') return _applications;
    return _applications
        .where((a) => a.status.label == _adminFilter)
        .toList();
  }

  // ── Load ───────────────────────────────────────────────────────────────

  Future<void> loadListings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _allListings = await _service.fetchListings();
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadApplications() async {
    _isLoading = true;
    notifyListeners();
    try {
      _applications = await _service.fetchApplications();
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  // ── Filters ────────────────────────────────────────────────────────────

  void setCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setSearch(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setAdminFilter(String filter) {
    _adminFilter = filter;
    notifyListeners();
  }

  // ── Admin actions ──────────────────────────────────────────────────────

  Future<void> approveApplication(String id) async {
    await _service.approveApplication(id);
    await loadApplications();
    await loadListings();
  }

  Future<void> declineApplication(String id) async {
    await _service.declineApplication(id);
    await loadApplications();
  }

  // ── Join flow ──────────────────────────────────────────────────────────

  Future<void> submitApplication(PartnerApplication application) async {
    await _service.submitApplication(application);
  }

  // ── Contact tracking ───────────────────────────────────────────────────

  Future<void> logContact({
    required String vendorId,
    required String userId,
    required String type,
  }) async {
    await _service.logContactTap(
        vendorId: vendorId, contactedBy: userId, contactType: type);
  }
}
