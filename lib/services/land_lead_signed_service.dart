import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/land_lead.dart';
import '../models/land_lead_signed_request.dart';
import '../models/land_lead_site_visit.dart' show SiteVisitApprovalStatus;
import 'app_settings_service.dart';
import 'app_store.dart';
import 'approval_chain.dart';
import 'auth_service.dart';
import 'land_lead_service.dart';
import 'notifications_service.dart';

/// Signed-off approval workflow: an employee submits a lead as "Project Signed"
/// (with supporting photos/documents). The request stays pending until
/// management approves it — only then does the lead stage become Signed.
///
/// Degrades gracefully if the `land_lead_signed_requests` table is missing
/// (callers surface the error / treat pending count as zero).
class LandLeadSignedService {
  static SupabaseClient get _db => Supabase.instance.client;
  static const _table = 'land_lead_signed_requests';

  static Future<LandLeadSignedRequest> submit({
    required String leadId,
    required String note,
    required List<String> photoUrls,
  }) async {
    final userId = _db.auth.currentUser?.id;
    final by = AuthService.instance.currentUser?.fullName ?? '';
    final byEmail =
        (AuthService.instance.currentUser?.email ?? '').trim().toLowerCase();

    // Honour Feature Controls › Role Hierarchy (flat mode → Management).
    await AppSettingsService.instance.ensureLoaded();
    final step = ApprovalChain.firstStepFor(byEmail);

    final row = await _db
        .from(_table)
        .insert({
          'lead_id': leadId,
          'requested_by_name': by,
          'requested_by_email': byEmail,
          if (userId != null) 'requested_by': userId,
          'note': note.trim(),
          'photo_urls': photoUrls,
          'status': SiteVisitApprovalStatus.pending.dbValue,
          'approval_level': step.level.dbValue,
          'pending_with': step.approverEmail,
        })
        .select()
        .single();

    final request = LandLeadSignedRequest.fromJson(row);

    final who = by.isNotEmpty ? by : 'An employee';
    try {
      await NotificationsService.create(
        audience: ApprovalChain.audienceFor(step),
        type: 'signed',
        title: 'Project Signed approval requested',
        message: '$who submitted Lead #$leadId to be marked as Signed',
        leadId: leadId,
        referenceId: request.id,
      );
    } catch (_) {
      // Request is saved even if the notification insert fails.
    }

    return request;
  }

  /// Pending requests the signed-in user may act on: Management sees the
  /// management-level queue; a Reporting Manager / Head sees the ones waiting
  /// on them.
  static Future<List<LandLeadSignedRequest>> getPending() async {
    final query = _db
        .from(_table)
        .select()
        .eq('status', SiteVisitApprovalStatus.pending.dbValue);

    final rows = AuthService.instance.isManagement
        ? await query
            .eq('approval_level', ApprovalLevel.management.dbValue)
            .order('created_at', ascending: false)
        : await query
            .eq('pending_with',
                (AuthService.instance.currentUser?.email ?? '')
                    .trim()
                    .toLowerCase())
            .order('created_at', ascending: false);

    return (rows as List)
        .map((r) => LandLeadSignedRequest.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  static Future<int> countPending() async {
    try {
      return (await getPending()).length;
    } catch (_) {
      return 0;
    }
  }

  /// Signed requests logged against a single lead (pending, approved, rejected).
  /// Returns an empty list when the table is missing so the lead detail page
  /// can still render its Activity Timeline.
  static Future<List<LandLeadSignedRequest>> getForLead(String leadId) async {
    try {
      final rows = await _db
          .from(_table)
          .select()
          .eq('lead_id', leadId)
          .order('created_at', ascending: false);
      return (rows as List)
          .map((r) => LandLeadSignedRequest.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Requests approved between [from] and [to] — the sites/deals actually closed
  /// in that window, which is what monthly target progress counts. A lead only
  /// reaches Signed through this workflow, so `reviewed_at` is the completion
  /// date.
  ///
  /// Returns nothing rather than throwing if the table is missing, so a
  /// dashboard never breaks on it.
  static Future<List<LandLeadSignedRequest>> getApprovedBetween({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final rows = await _db
          .from(_table)
          .select()
          .eq('status', SiteVisitApprovalStatus.approved.dbValue)
          .gte('reviewed_at', from.toUtc().toIso8601String())
          .lte('reviewed_at', to.toUtc().toIso8601String())
          .order('reviewed_at', ascending: true);

      return (rows as List)
          .map((r) => LandLeadSignedRequest.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Approving advances the request to the next approver in the chain; only the
  /// final (Management) approval marks the lead Signed. Rejecting at ANY level
  /// ends the request and notifies the executive who raised it.
  static Future<LandLeadSignedRequest> review({
    required String id,
    required bool approve,
    String notes = '',
  }) async {
    final reviewer = AuthService.instance.currentUser?.fullName ?? 'Management';

    // Read the current state so we know where it sits in the chain.
    final current = LandLeadSignedRequest.fromJson(
      await _db.from(_table).select().eq('id', id).single(),
    );

    final next = approve
        ? ApprovalChain.nextStepAfter(current.requestedByEmail, current.approvalLevel)
        : null;

    if (approve && next != null) {
      // Hand off to the next level — still pending, not yet Signed.
      final row = await _db
          .from(_table)
          .update({
            'approval_level': next.level.dbValue,
            'pending_with': next.approverEmail,
          })
          .eq('id', id)
          .select()
          .single();
      final advanced = LandLeadSignedRequest.fromJson(row);

      NotificationsService.create(
        audience: ApprovalChain.audienceFor(next),
        type: 'signed',
        title: 'Project Signed approval requested',
        message:
            '${current.requestedByName.isEmpty ? 'An executive' : current.requestedByName} · '
            '${AppStore.instance.displayNameForLeadId(current.leadId)} approved by $reviewer — awaiting ${next.level.label}',
        leadId: current.leadId,
        referenceId: id,
      ).catchError((_) {});

      _notifySubmitter(
        current,
        title: 'Signed request progressed',
        message:
            '${AppStore.instance.displayNameForLeadId(current.leadId)} was approved by $reviewer and is now with ${next.level.label}',
      );
      return advanced;
    }

    // Final approval, or a rejection at any level.
    final row = await _db
        .from(_table)
        .update({
          'status': approve
              ? SiteVisitApprovalStatus.approved.dbValue
              : SiteVisitApprovalStatus.rejected.dbValue,
          'reviewed_at': DateTime.now().toUtc().toIso8601String(),
          'reviewed_by_name': reviewer,
        })
        .eq('id', id)
        .select()
        .single();

    final request = LandLeadSignedRequest.fromJson(row);

    if (approve) {
      // Only now does the lead actually become Signed.
      try {
        await LandLeadService.updateStatus(request.leadId, LeadStatus.signed);
        AppStore.instance.updateLeadStatus(request.leadId, LeadStatus.signed);
      } catch (_) {
        // Status persistence may fail offline; the approval is still recorded.
      }
    }

    _notifySubmitter(
      request,
      title: approve ? 'Project approved & signed' : 'Signed request rejected',
      message: approve
          ? '${AppStore.instance.displayNameForLeadId(request.leadId)} was approved and marked as Signed'
              '${notes.trim().isNotEmpty ? ' — $notes' : ''}'
          : '${AppStore.instance.displayNameForLeadId(request.leadId)} signed request was rejected by $reviewer'
              '${notes.trim().isNotEmpty ? ' — $notes' : ''}',
    );

    return request;
  }

  /// Notifies the executive who raised the request (personally when we know
  /// their email, otherwise the shared employee audience).
  static void _notifySubmitter(
    LandLeadSignedRequest request, {
    required String title,
    required String message,
  }) {
    final to = request.requestedByEmail.trim().toLowerCase();
    NotificationsService.create(
      audience: to.isEmpty ? 'employee' : to,
      type: 'signed',
      title: title,
      message: message,
      leadId: request.leadId,
      referenceId: request.id,
    ).catchError((_) {});
  }
}
