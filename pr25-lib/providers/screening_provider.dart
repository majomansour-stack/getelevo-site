import 'package:flutter/foundation.dart';

import '../models/screening_model.dart';
import '../services/screening_service.dart';

class ScreeningProvider extends ChangeNotifier {
  final ScreeningService _service;
  final String landlordId;
  final String landlordFullName;

  ScreeningProvider({
    required this.landlordId,
    required this.landlordFullName,
    ScreeningService? service,
  }) : _service = service ?? ScreeningService();

  List<TenantScreening> _screenings = [];
  bool _isLoading = false;
  String? _error;

  List<TenantScreening> get screenings => _screenings;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    if (landlordId.isEmpty) {
      _screenings = [];
      _error = 'Sign in again to load screenings.';
      _isLoading = false;
      notifyListeners();
      return;
    }
    try {
      _screenings = await _service.fetchForLandlord(landlordId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Create ────────────────────────────────────────────────────────────────

  /// Returns the saved record on success, throws on failure.
  Future<TenantScreening> sendScreeningRequest(TenantScreening draft) async {
    _isLoading = true;
    notifyListeners();
    try {
      final saved = await _service.createScreening(
        screening: draft,
        landlordFullName: landlordFullName,
      );
      _screenings.insert(0, saved);
      return saved;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Saves the record to the database with status 'invited' but does NOT send
  /// any email — the caller opens the RentSpree website directly instead.
  Future<void> saveScreeningRecord(TenantScreening draft) async {
    _isLoading = true;
    notifyListeners();
    try {
      final saved = await _service.saveRecordOnly(draft);
      _screenings.insert(0, saved);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Status updates ────────────────────────────────────────────────────────

  Future<void> markComplete(String screeningId, String notes) async {
    final updated = await _service.markComplete(screeningId, notes);
    _replaceInList(updated);
  }

  Future<void> approveApplicant(String screeningId) async {
    final updated =
        await _service.approveApplicant(screeningId, landlordFullName);
    _replaceInList(updated);
  }

  Future<void> declineApplicant(String screeningId) async {
    final updated =
        await _service.declineApplicant(screeningId, landlordFullName);
    _replaceInList(updated);
  }

  Future<void> updateNotes(String screeningId, String notes) async {
    final updated = await _service.updateNotes(screeningId, notes);
    _replaceInList(updated);
  }

  Future<void> resendInvitation(TenantScreening screening) async {
    await _service.resendInvitation(screening, landlordFullName);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _replaceInList(TenantScreening updated) {
    final idx = _screenings.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) {
      _screenings[idx] = updated;
      notifyListeners();
    }
  }

  TenantScreening? findById(String id) {
    try {
      return _screenings.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }
}
