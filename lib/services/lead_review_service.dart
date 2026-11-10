import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee_profile.dart';
import '../models/lead_review.dart';
import 'auth_service.dart';
import 'role_access.dart';
import 'team_hierarchy.dart';

/// Property reviews recorded on a lead by the Reporting Manager, Head or
/// Management. Degrades gracefully when the `lead_reviews` table is missing
/// (reads return empty, writes throw).
class LeadReviewService {
  static SupabaseClient get _db => Supabase.instance.client;
  static const _table = 'lead_reviews';

  /// Only the Reporting Manager / Head tier and Management may mark a
  /// property reviewed; executives just see the review status.
  static bool get canReview => RoleAccess.canApprove;

  /// How the current reviewer is labelled on the review.
  static String get currentReviewerRole {
    if (AuthService.instance.isManagement) return 'Management';
    final d = TeamHierarchy.currentDesignation;
    if (d == EmployeeDesignations.head) return 'Head';
    if (d == EmployeeDesignations.reportingManager) return 'Reporting Manager';
    return d;
  }

  /// Every review for a lead, newest first.
  static Future<List<LeadReview>> getForLead(String leadId) async {
    try {
      final rows = await _db
          .from(_table)
          .select()
          .eq('lead_id', leadId)
          .order('reviewed_at', ascending: false);
      return (rows as List)
          .map((r) => LeadReview.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Records that the current user reviewed [leadId] now, with an optional
  /// note and date for the next review.
  static Future<LeadReview> create({
    required String leadId,
    String notes = '',
    DateTime? nextReviewDate,
  }) async {
    final user = AuthService.instance.currentUser;
    final row = await _db
        .from(_table)
        .insert({
          'lead_id': leadId,
          'reviewed_at': DateTime.now().toUtc().toIso8601String(),
          'reviewed_by': user?.fullName ?? '',
          'reviewed_by_email': (user?.email ?? '').trim().toLowerCase(),
          'reviewer_role': currentReviewerRole,
          'notes': notes.trim(),
          'next_review_date': nextReviewDate == null
              ? null
              : LeadReview.toDateString(nextReviewDate),
        })
        .select()
        .single();
    final review = LeadReview.fromJson(Map<String, dynamic>.from(row));
    LeadReviewIndex.instance.record(review);
    return review;
  }
}

/// Latest review per lead, loaded in one query, so list screens can filter
/// by review status (reviewed / overdue / due this week …) without a request
/// per lead. RLS limits it to leads the user can see. Listeners are notified
/// when it (re)loads or a new review is recorded.
class LeadReviewIndex extends ChangeNotifier {
  LeadReviewIndex._();
  static final LeadReviewIndex instance = LeadReviewIndex._();

  Map<String, LeadReview> _latest = const {};
  bool _loaded = false;
  Future<void>? _inFlight;
  DateTime? _loadedAt;

  bool get isLoaded => _loaded;

  LeadReview? latestFor(String leadId) => _latest[leadId.trim()];

  /// Loads once, then at most every 2 minutes, unless [force].
  Future<void> ensureLoaded({bool force = false}) {
    final fresh = _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(minutes: 2);
    if (!force && _loaded && fresh) return Future.value();
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('lead_reviews')
          .select()
          .order('reviewed_at', ascending: false)
          .limit(10000);
      final next = <String, LeadReview>{};
      for (final r in rows as List) {
        final review = LeadReview.fromJson(Map<String, dynamic>.from(r));
        // Rows arrive newest first, so the first one per lead is its latest.
        next.putIfAbsent(review.leadId, () => review);
      }
      _latest = next;
      _loaded = true;
      _loadedAt = DateTime.now();
      notifyListeners();
    } catch (e) {
      debugPrint('[reviews] could not load review index: $e');
    }
  }

  /// Replaces the index contents directly — tests only.
  @visibleForTesting
  void debugSeed(Iterable<LeadReview> reviews) {
    _latest = {for (final r in reviews) r.leadId: r};
    _loaded = true;
    _loadedAt = DateTime.now();
    notifyListeners();
  }

  /// Applies a review just saved on this device without a reload.
  void record(LeadReview review) {
    final current = _latest[review.leadId];
    if (current != null && current.reviewedAt.isAfter(review.reviewedAt)) {
      return;
    }
    _latest = {..._latest, review.leadId: review};
    notifyListeners();
  }
}
