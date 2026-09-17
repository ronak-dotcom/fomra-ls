import '../models/app_notification.dart';
import '../models/land_lead.dart';
import '../models/lead_drop_reason.dart';
import '../services/app_settings_service.dart';
import '../services/app_store.dart';
import '../services/approval_chain.dart';
import '../services/auth_service.dart';
import '../services/land_lead_service.dart';
import '../services/notifications_service.dart';

class LeadDropApprovalRequest {
  final AppNotification notification;
  final LeadDropReason reason;
  final String notes;
  final String requestedByName;
  final String requestedByEmail;
  final ApprovalLevel approvalLevel;

  const LeadDropApprovalRequest({
    required this.notification,
    required this.reason,
    required this.notes,
    required this.requestedByName,
    this.requestedByEmail = '',
    this.approvalLevel = ApprovalLevel.management,
  });

  String get id => notification.id;
  String get leadId => notification.leadId ?? '';
  DateTime get createdAt => notification.time;
  bool get isPending => !notification.isRead;

  /// The drop request IS the notification, so its audience is who it's
  /// currently waiting on ('management' or an approver's email).
  String get pendingWith => notification.audience;
}

class LeadDropApprovalService {
  static const _requestPrefix = 'Drop request · ';

  static bool isDropRequest(AppNotification notification) =>
      notification.type == NotificationType.pendingApproval &&
      notification.title.startsWith(_requestPrefix);

  static LeadDropApprovalRequest? toRequest(AppNotification notification) {
    if (!isDropRequest(notification)) return null;
    final reasonLabel = notification.title.substring(_requestPrefix.length).trim();
    final reason = LeadDropReason(
      id: normalizeLeadDropReasonId(reasonLabel),
      label: reasonLabel,
    );
    return LeadDropApprovalRequest(
      notification: notification,
      reason: reason,
      notes: _extractNotes(notification.message),
      requestedByName: _extractRequestedBy(notification.message),
      requestedByEmail: _extractLine(notification.message, 'requested by email:'),
      approvalLevel: ApprovalLevel.parse(
        _extractLine(notification.message, 'level:'),
      ),
    );
  }

  static Future<LeadDropApprovalRequest> submit({
    required String leadId,
    required LeadDropReason reason,
    required String notes,
  }) async {
    final by = AuthService.instance.currentUser?.fullName ?? 'Employee';
    final byEmail =
        (AuthService.instance.currentUser?.email ?? '').trim().toLowerCase();
    // Route to the first approver in the chain. The request IS the
    // notification, so its audience is who it currently waits on.
    await AppSettingsService.instance.ensureLoaded();
    final step = ApprovalChain.firstStepFor(byEmail);

    final created = await NotificationsService.createAndReturn(
      audience: ApprovalChain.audienceFor(step),
      type: 'pending_approval',
      title: 'Drop request · ${reason.label}',
      message: _encodeMessage(
        requestedBy: by.trim().isEmpty ? 'Employee' : by.trim(),
        requestedByEmail: byEmail,
        notes: notes,
        level: step.level,
      ),
      leadId: leadId,
      referenceId: leadId,
    );
    return LeadDropApprovalRequest(
      notification: created,
      reason: reason,
      notes: notes.trim(),
      requestedByName: by.trim().isEmpty ? 'Employee' : by.trim(),
      requestedByEmail: byEmail,
      approvalLevel: step.level,
    );
  }

  static String _encodeMessage({
    required String requestedBy,
    required String requestedByEmail,
    required String notes,
    required ApprovalLevel level,
  }) =>
      [
        'Requested by: $requestedBy',
        'Requested by email: $requestedByEmail',
        'Level: ${level.dbValue}',
        'Notes: ${notes.trim().isEmpty ? '—' : notes.trim()}',
      ].join('\n');

  /// Pending drop requests waiting on the signed-in user (Management sees the
  /// 'management' queue; a Reporting Manager / Head sees their own).
  static Future<List<LeadDropApprovalRequest>> getPending() async {
    final audience = AuthService.instance.isManagement
        ? 'management'
        : (AuthService.instance.currentUser?.email ?? '').trim().toLowerCase();
    if (audience.isEmpty) return const [];
    final notifications =
        await NotificationsService.getAll(audience: audience);
    return notifications
        .where(isDropRequest)
        .where((notification) => !notification.isRead)
        .map(toRequest)
        .whereType<LeadDropApprovalRequest>()
        .toList();
  }

  /// Approving hands the request to the next approver in the chain (the request
  /// notification is re-addressed to them); only the final (Management)
  /// approval actually drops the lead. Rejecting at any level ends the request
  /// and notifies the executive — the lead's stage is left untouched.
  static Future<void> review({
    required LeadDropApprovalRequest request,
    required bool approve,
  }) async {
    final reviewer = AuthService.instance.currentUser?.fullName ?? 'Management';
    final next = approve
        ? ApprovalChain.nextStepAfter(
            request.requestedByEmail, request.approvalLevel)
        : null;

    if (approve && next != null) {
      // Re-route the same request up to the next approver.
      await NotificationsService.reroute(
        id: request.id,
        audience: ApprovalChain.audienceFor(next),
        message: _encodeMessage(
          requestedBy: request.requestedByName,
          requestedByEmail: request.requestedByEmail,
          notes: request.notes,
          level: next.level,
        ),
      );
      await _notifySubmitter(
        request,
        type: 'verification',
        title: 'Drop request progressed',
        message:
            '${AppStore.instance.displayNameForLeadId(request.leadId)} drop request was approved by $reviewer and is now with ${next.level.label}',
      );
      return;
    }

    if (approve) {
      await LandLeadService.markDropped(
        leadId: request.leadId,
        reasonLabel: request.reason.label,
        notes: request.notes,
      );
      AppStore.instance.updateLeadStatus(request.leadId, LeadStatus.dropped);
    }

    await NotificationsService.markRead(request.id);
    await _notifySubmitter(
      request,
      type: approve ? 'verification' : 'alert',
      title: approve ? 'Drop request approved' : 'Drop request rejected',
      message: approve
          ? '${AppStore.instance.displayNameForLeadId(request.leadId)} was approved and marked as Dropped'
          : '${AppStore.instance.displayNameForLeadId(request.leadId)} drop request was rejected by $reviewer — the stage is unchanged',
    );
  }

  static Future<void> _notifySubmitter(
    LeadDropApprovalRequest request, {
    required String type,
    required String title,
    required String message,
  }) async {
    final to = request.requestedByEmail.trim().toLowerCase();
    await NotificationsService.create(
      audience: to.isEmpty ? 'employee' : to,
      type: type,
      title: title,
      message: message,
      leadId: request.leadId,
      referenceId: request.id,
    );
  }

  static String _extractLine(String message, String prefix) {
    for (final line in message.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.toLowerCase().startsWith(prefix)) {
        return trimmed.substring(prefix.length).trim();
      }
    }
    return '';
  }

  static String _extractRequestedBy(String message) {
    final v = _extractLine(message, 'requested by:');
    return v.isEmpty ? 'Employee' : v;
  }

  static String _extractNotes(String message) => _extractLine(message, 'notes:');
}