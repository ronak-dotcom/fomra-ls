import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/lead_change_request.dart';
import 'audit_log_service.dart';
import 'auth_service.dart';
import 'notifications_service.dart';

/// Human-readable labels for LandLeadService._auditedFields' column names,
/// used when showing a pending change request to management. Kept here
/// rather than duplicated in the UI, so the label always matches which
/// fields this rule actually covers.
const leadChangeFieldLabels = <String, String>{
  'owner_name': 'Owner Name',
  'contact_details': 'Owner Contact Number',
  'broker_name': 'Broker Name',
  'broker_contact': 'Broker Number',
  'land_extent': 'Land Extent',
  'survey_number': 'Survey Number',
  'sub_division': 'Sub Division',
  'village': 'Village',
  'taluk': 'Taluk',
  'district': 'District',
  'location': 'Location',
  'gps_coordinates': 'Map Location (GPS)',
};

/// Generalizes the same rule LandLeadRenameService established for the
/// lead's name to the rest of its core info (see leadChangeFieldLabels):
/// free to fill in a blank field any time; free to edit an already-filled
/// field within LandLeadService.freeEditWindow (1 hour) of the lead being
/// saved; editing or clearing an already-filled field after that needs
/// management approval, and
/// — unlike the rename flow — is simply never written to land_leads
/// unless/until approved, rather than applied then reverted.
class LeadChangeApprovalService {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<void> submitPending({
    required String leadId,
    required List<LeadFieldChange> changes,
  }) async {
    if (changes.isEmpty) return;
    final userName = AuthService.instance.currentUser?.fullName ?? '';
    final userEmail = AuthService.instance.currentUser?.email ?? '';
    final userId = _db.auth.currentUser?.id;

    await _db.from('lead_change_requests').insert({
      'lead_id': leadId,
      'changes': {for (final c in changes) c.field: c.toJson()},
      'requested_by': userId,
      'requested_by_name': userName,
      'requested_by_email': userEmail,
    });

    final summary = changes.map((c) => c.label).join(', ');
    await NotificationsService.create(
      audience: 'management',
      type: 'pending_approval',
      title: 'Lead info change request · Lead $leadId',
      message: '$userName wants to change: $summary.',
      leadId: leadId,
    );
  }

  static Future<List<LeadChangeRequest>> getPending() async {
    try {
      final rows = await _db
          .from('lead_change_requests')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      return (rows as List)
          .map((r) => LeadChangeRequest.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// "Owner Name, Map Location (GPS)" for the lead's change request still
  /// waiting on management, or null if none — so the screen that saved an
  /// edit can say which fields were held back instead of a plain "updated".
  static Future<String?> pendingFieldsSummary(String leadId) async {
    final pending = await getPendingForLead(leadId);
    if (pending == null || pending.changes.isEmpty) return null;
    return pending.changes.map((c) => c.label).join(', ');
  }

  static Future<LeadChangeRequest?> getPendingForLead(String leadId) async {
    try {
      final rows = await _db
          .from('lead_change_requests')
          .select()
          .eq('lead_id', leadId)
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(1);
      final list = rows as List;
      if (list.isEmpty) return null;
      return LeadChangeRequest.fromJson(Map<String, dynamic>.from(list.first));
    } catch (_) {
      return null;
    }
  }

  /// Writes every changed field to land_leads for the first time — a
  /// rejected request never touched the row at all, so there is nothing
  /// to "revert" on rejection, only nothing to apply.
  static Future<void> approve(LeadChangeRequest request) async {
    final reviewerName = AuthService.instance.currentUser?.fullName ?? '';
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final payload = <String, dynamic>{
      for (final c in request.changes) c.field: c.newValue,
      'updated_at': nowIso,
    };
    await _db.from('land_leads').update(payload).eq('id', request.leadId);

    await _db.from('lead_change_requests').update({
      'status': 'approved',
      'reviewed_by_name': reviewerName,
      'reviewed_at': nowIso,
    }).eq('id', request.id);

    for (final c in request.changes) {
      await AuditLogService.log(
        action: 'update_approved',
        entityType: 'lead',
        entityId: request.leadId,
        field: c.field,
        oldValue: c.oldValue,
        newValue: c.newValue,
        module: 'Lead',
        leadId: request.leadId,
        executiveName: reviewerName,
      );
    }

    await NotificationsService.create(
      audience: request.requestedByEmail,
      type: 'verification',
      title: 'Lead info change approved · Lead ${request.leadId}',
      message: 'Your changes to '
          '${request.changes.map((c) => c.label).join(', ')} were approved.',
      leadId: request.leadId,
    );
  }

  static Future<void> reject(
    LeadChangeRequest request, {
    String reason = '',
  }) async {
    final reviewerName = AuthService.instance.currentUser?.fullName ?? '';
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await _db.from('lead_change_requests').update({
      'status': 'rejected',
      'reviewed_by_name': reviewerName,
      'reviewed_at': nowIso,
      'rejection_reason': reason.trim(),
    }).eq('id', request.id);

    await NotificationsService.create(
      audience: request.requestedByEmail,
      type: 'reminder',
      title: 'Lead info change rejected · Lead ${request.leadId}',
      message: reason.trim().isEmpty
          ? 'Your requested changes to '
              '${request.changes.map((c) => c.label).join(', ')} were not approved.'
          : reason.trim(),
      leadId: request.leadId,
    );
  }
}
