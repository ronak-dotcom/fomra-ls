import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/land_lead_site_visit.dart';
import 'app_settings_service.dart';
import 'app_store.dart';
import 'approval_chain.dart';
import 'audit_log_service.dart';
import 'auth_service.dart';
import 'notifications_service.dart';

class LandLeadSiteVisitService {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<List<LandLeadSiteVisit>> getAllForLead(String leadId) async {
    final rows = await _db
        .from('land_lead_site_visits')
        .select()
        .eq('lead_id', leadId)
        .order('visited_at', ascending: false);
    return (rows as List)
        .map((r) => LandLeadSiteVisit.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  static Future<List<LandLeadSiteVisit>> getForLead(
    String leadId, {
    required LandLeadSiteVisitType visitType,
  }) async {
    final rows = await _db
        .from('land_lead_site_visits')
        .select()
        .eq('lead_id', leadId)
        .eq('visit_type', visitType.dbValue)
        .order('visited_at', ascending: false);
    return (rows as List)
        .map((r) => LandLeadSiteVisit.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  static Future<LandLeadSiteVisit?> getById(String id) async {
    final row = await _db
        .from('land_lead_site_visits')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return LandLeadSiteVisit.fromJson(row);
  }

  /// Pending management-visit requests the signed-in user may act on:
  /// Management sees the management-level queue; a Reporting Manager / Head
  /// sees the ones currently waiting on them.
  static Future<List<LandLeadSiteVisit>> getPendingManagementVisits() async {
    final query = _db
        .from('land_lead_site_visits')
        .select()
        .eq('visit_type', LandLeadSiteVisitType.management.dbValue)
        .eq('approval_status', SiteVisitApprovalStatus.pending.dbValue);

    final rows = AuthService.instance.isManagement
        ? await query
            .eq('approval_level', ApprovalLevel.management.dbValue)
            .order('visited_at', ascending: false)
        : await query
            .eq('pending_with',
                (AuthService.instance.currentUser?.email ?? '')
                    .trim()
                    .toLowerCase())
            .order('visited_at', ascending: false);

    return (rows as List)
        .map((r) => LandLeadSiteVisit.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  static Future<String?> findPendingManagementVisitId(String leadId) async {
    final row = await _db
        .from('land_lead_site_visits')
        .select('id')
        .eq('lead_id', leadId)
        .eq('visit_type', LandLeadSiteVisitType.management.dbValue)
        .eq('approval_status', SiteVisitApprovalStatus.pending.dbValue)
        .order('visited_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row?['id'] as String?;
  }

  static Future<LandLeadSiteVisit> markDone({
    required String leadId,
    required DateTime visitedAt,
    required LandLeadSiteVisitType visitType,
  }) async {
    final userId = _db.auth.currentUser?.id;
    final loggedByName = AuthService.instance.currentUser?.fullName ?? '';
    final loggedByEmail =
        (AuthService.instance.currentUser?.email ?? '').trim().toLowerCase();
    final isEmployee = AuthService.instance.isEmployee;
    final needsApproval =
        visitType == LandLeadSiteVisitType.management && isEmployee;

    // Route to the first approver in the submitter's chain (Management when
    // Role Hierarchy is off or they have no reporting line).
    await AppSettingsService.instance.ensureLoaded();
    final step = ApprovalChain.firstStepFor(loggedByEmail);

    final row = await _db
        .from('land_lead_site_visits')
        .insert({
          'lead_id': leadId,
          'visited_at': visitedAt.toUtc().toIso8601String(),
          'visit_type': visitType.dbValue,
          'approval_status': needsApproval ? 'pending' : 'approved',
          if (loggedByName.isNotEmpty) 'logged_by_name': loggedByName,
          if (userId != null) 'logged_by': userId,
          if (needsApproval) ...{
            'approval_level': step.level.dbValue,
            'pending_with': step.approverEmail,
            'requested_by_email': loggedByEmail,
          },
        })
        .select()
        .single();

    final visit = LandLeadSiteVisit.fromJson(row);

    if (needsApproval) {
      final who = loggedByName.isNotEmpty ? loggedByName : 'An employee';
      try {
        await NotificationsService.create(
          audience: ApprovalChain.audienceFor(step),
          type: 'site_visit',
          title: 'Management site visit requested',
          message: '$who requested a management site visit for Lead #$leadId',
          leadId: leadId,
          referenceId: visit.id,
        );
      } catch (_) {
        // Visit is saved even if notification insert fails (e.g. missing reference_id column).
      }
    }

    return visit;
  }

  /// Approving hands the request to the next approver in the chain; only the
  /// final (Management) approval settles it. Rejecting at any level ends it and
  /// notifies the executive who raised it.
  static Future<LandLeadSiteVisit> review({
    required String visitId,
    required SiteVisitApprovalStatus status,
    required String notes,
  }) async {
    final reviewer = AuthService.instance.currentUser?.fullName ?? 'Management';
    final approved = status == SiteVisitApprovalStatus.approved;

    final current = LandLeadSiteVisit.fromJson(
      await _db
          .from('land_lead_site_visits')
          .select()
          .eq('id', visitId)
          .single(),
    );

    final next = approved
        ? ApprovalChain.nextStepAfter(
            current.requestedByEmail, current.approvalLevel)
        : null;

    if (approved && next != null) {
      final row = await _db
          .from('land_lead_site_visits')
          .update({
            'approval_level': next.level.dbValue,
            'pending_with': next.approverEmail,
          })
          .eq('id', visitId)
          .select()
          .single();

      NotificationsService.create(
        audience: ApprovalChain.audienceFor(next),
        type: 'site_visit',
        title: 'Management site visit requested',
        message:
            '${AppStore.instance.displayNameForLeadId(current.leadId)} site visit approved by $reviewer — awaiting ${next.level.label}',
        leadId: current.leadId,
        referenceId: visitId,
      ).catchError((_) {});

      _notifyRequester(
        current,
        title: 'Site visit request progressed',
        message:
            '${AppStore.instance.displayNameForLeadId(current.leadId)} site visit was approved by $reviewer and is now with ${next.level.label}',
      );
      return LandLeadSiteVisit.fromJson(row);
    }

    final row = await _db
        .from('land_lead_site_visits')
        .update({
          'approval_status': status.dbValue,
          'management_notes': notes.trim(),
          'reviewed_at': DateTime.now().toUtc().toIso8601String(),
          'reviewed_by_name': reviewer,
        })
        .eq('id', visitId)
        .select()
        .single();

    final visit = LandLeadSiteVisit.fromJson(row);

    ({String owner, String broker, String executive}) ctx =
        (owner: '', broker: '', executive: '');
    for (final l in AppStore.instance.leads) {
      if (l.leadId == visit.leadId) {
        ctx = (owner: l.ownerName, broker: l.brokerName, executive: l.createdByName);
        break;
      }
    }
    AuditLogService.log(
      action: approved ? 'approve' : 'reject',
      entityType: 'site_visit',
      entityId: visit.id,
      field: 'approval_status',
      oldValue: 'pending',
      newValue: status.dbValue,
      module: 'Site Visits',
      leadId: visit.leadId,
      ownerName: ctx.owner,
      brokerName: ctx.broker,
      executiveName: ctx.executive,
    ).catchError((_) {});

    NotificationsService.create(
      audience: visit.requestedByEmail.trim().isEmpty
          ? 'employee'
          : visit.requestedByEmail.trim().toLowerCase(),
      type: 'site_visit',
      title: approved
          ? 'Management visit approved'
          : 'Management visit rejected',
      message: approved
          ? '${AppStore.instance.displayNameForLeadId(visit.leadId)} management site visit was approved'
              '${notes.trim().isNotEmpty ? ' — $notes' : ''}'
          : '${AppStore.instance.displayNameForLeadId(visit.leadId)} management site visit was rejected by $reviewer'
              '${notes.trim().isNotEmpty ? ' — $notes' : ''}',
      leadId: visit.leadId,
      referenceId: visit.id,
    ).catchError((_) {});

    return visit;
  }

  /// Notifies the executive who raised the request (personally when we know
  /// their email, otherwise the shared employee audience).
  static void _notifyRequester(
    LandLeadSiteVisit visit, {
    required String title,
    required String message,
  }) {
    final to = visit.requestedByEmail.trim().toLowerCase();
    NotificationsService.create(
      audience: to.isEmpty ? 'employee' : to,
      type: 'site_visit',
      title: title,
      message: message,
      leadId: visit.leadId,
      referenceId: visit.id,
    ).catchError((_) {});
  }
}
