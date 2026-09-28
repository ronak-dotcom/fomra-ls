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
    return LeadReview.fromJson(Map<String, dynamic>.from(row));
  }
}
