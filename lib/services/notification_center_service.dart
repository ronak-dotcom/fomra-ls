import 'package:shared_preferences/shared_preferences.dart';

import '../analytics/management_bi_metrics.dart';
import '../analytics/management_intelligence.dart';
import '../models/land_lead.dart';
import '../screens/task_management/task_management_screen.dart';
import '../services/app_store.dart';
import '../services/auth_service.dart';
import '../services/field_calendar_service.dart';
import '../services/lead_follow_up_service.dart';
import '../services/management_bi_activity_service.dart';
import '../services/notifications_service.dart';

/// Produces Notification Center alerts for:
/// Assigned Leads, Pending Leads, Pending Approvals, SLA Breaches,
/// Overdue Tasks, Reminder Alerts — with daily dedupe so we don't spam.
abstract final class NotificationCenterService {
  static const _prefsPrefix = 'notif_sync_v1_';
  static DateTime? _lastRun;

  /// Idempotent sync — safe to call on home load / app resume.
  static Future<int> syncAlerts({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastRun != null &&
        now.difference(_lastRun!) < const Duration(minutes: 5)) {
      return 0;
    }
    _lastRun = now;

    final isManagement = AuthService.instance.isManagement;
    final audience = isManagement ? 'management' : 'employee';
    final me =
        (AuthService.instance.currentUser?.fullName ?? '').trim().toLowerCase();

    try {
      if (isManagement) {
        return await _syncManagement(audience);
      }
      return await _syncEmployee(audience, me);
    } catch (_) {
      return 0;
    }
  }

  static Future<int> _syncManagement(String audience) async {
    var n = 0;
    final leads = AppStore.instance.leads;
    if (leads.isEmpty) return 0;

    final activity = await ManagementBiActivityService.loadAll();
    final bi = ManagementBiMetrics.build(leads: leads, activity: activity);
    final intel =
        ManagementIntelligence.build(leads: leads, activity: activity);

    for (final item in intel.approvalQueue.take(8)) {
      final ok = await _emitOnce(
        key: 'approval_${item.kind.name}_${item.lead.leadId}',
        audience: audience,
        title: 'Pending Approval · ${item.kind.label}',
        message: '${item.lead.displayName} — ${item.detail}',
        type: 'pending_approval',
        leadId: item.lead.leadId,
        referenceId: item.visitId,
      );
      if (ok) n++;
    }

    for (final item in bi.sla.overdue.take(10)) {
      final ok = await _emitOnce(
        key: 'sla_${item.kind.name}_${item.lead.leadId}',
        audience: audience,
        title: 'SLA Breach · ${item.kind.label}',
        message:
            '${item.lead.displayName} exceeded ${item.kind.targetDays}-day SLA.',
        type: 'sla_breach',
        leadId: item.lead.leadId,
      );
      if (ok) n++;
    }

    // NOTE: Executive-facing reminders (no activity, owner not contacted,
    // no meeting after assignment, follow-ups) are intentionally NOT synced
    // here — those belong only to the assigned Executive's notifications.
    // Management only receives approval requests, escalations (SLA breaches)
    // and management-specific alerts (pending leads, overdue tasks).

    final pending = leads
        .where((l) =>
            l.status.isActive &&
            DateTime.now().difference(l.addedOn).inDays >= 7)
        .take(8);
    for (final lead in pending) {
      final ok = await _emitOnce(
        key: 'pending_lead_${lead.leadId}',
        audience: audience,
        title: 'Pending Lead',
        message:
            '${lead.displayName} still open (${DateTime.now().difference(lead.addedOn).inDays} days).',
        type: 'pending_lead',
        leadId: lead.leadId,
      );
      if (ok) n++;
    }

    n += await _syncOverdueTasks(audience, forUser: null);
    n += await _syncFollowUpReminders(audience);
    return n;
  }

  static Future<int> _syncEmployee(String audience, String me) async {
    var n = 0;
    if (me.isEmpty) return 0;

    final myLeads = AppStore.instance.leads
        .where((l) => l.createdByName.trim().toLowerCase() == me)
        .toList();

    for (final lead in myLeads.where((l) => l.status.isActive).take(8)) {
      final days = DateTime.now().difference(lead.addedOn).inDays;
      if (days < 3) continue;
      final ok = await _emitOnce(
        key: 'emp_pending_${lead.leadId}',
        audience: audience,
        title: 'Pending Lead',
        message:
            '${lead.displayName} needs follow-up ($days days).',
        type: 'pending_lead',
        leadId: lead.leadId,
      );
      if (ok) n++;
    }

    for (final lead in myLeads
        .where((l) => l.status == LeadStatus.prospectMeetingPending)
        .take(5)) {
      final ok = await _emitOnce(
        key: 'emp_meeting_${lead.leadId}',
        audience: audience,
        title: 'Reminder · Meeting pending',
        message: 'Schedule or complete meeting for ${lead.displayName}.',
        type: 'reminder',
        leadId: lead.leadId,
      );
      if (ok) n++;
    }

    n += await _syncCalendarReminders(audience);
    n += await _syncOverdueTasks(audience, forUser: me);
    n += await _syncFollowUpReminders(audience);
    return n;
  }

  /// Turns due, pending follow-ups (created by the signed-in user) into
  /// `reminder` notifications — surfaced in the panel/badge/toast, linking back
  /// to the lead. Daily dedupe via [_emitOnce] keeps a due follow-up to one ping.
  static Future<int> _syncFollowUpReminders(String audience) async {
    var n = 0;
    final myEmail =
        (AuthService.instance.currentUser?.email ?? '').trim().toLowerCase();
    if (myEmail.isEmpty) return 0;
    try {
      final due = await LeadFollowUpService.dueForUser(myEmail);
      for (final f in due.take(10)) {
        final ok = await _emitOnce(
          key: 'followup_${f.id}',
          audience: audience,
          title: 'Follow-up Reminder',
          message:
              '${AppStore.instance.displayNameForLeadId(f.leadId)}\n${f.title}\n\nScheduled:\n${f.scheduledLabel}',
          type: 'reminder',
          leadId: f.leadId,
          referenceId: f.id,
        );
        if (ok) n++;
      }
    } catch (_) {}
    return n;
  }

  static Future<int> _syncCalendarReminders(String audience) async {
    var n = 0;
    try {
      final due = await FieldCalendarService.dueReminders();
      for (final e in due.take(10)) {
        final ok = await _emitOnce(
          key: 'cal_reminder_${e.id}',
          audience: audience,
          title: 'Reminder · ${e.kind.label}',
          message: e.title,
          type: 'reminder',
          leadId: e.leadId.trim().isEmpty ? null : e.leadId,
          referenceId: e.id,
        );
        if (ok) n++;
      }
    } catch (_) {}
    return n;
  }

  static Future<int> _syncOverdueTasks(
    String audience, {
    required String? forUser,
  }) async {
    var n = 0;
    final tasks = sharedTasks.where((t) {
      if (t.status == TaskStatus.done) return false;
      if (!t.isOverdue && !t.isSlaBreached) return false;
      if (forUser == null || forUser.isEmpty) return true;
      return t.assignedTo.any((a) => a.trim().toLowerCase() == forUser);
    }).take(8);

    for (final task in tasks) {
      final type = task.isSlaBreached ? 'sla_breach' : 'overdue_task';
      final title =
          task.isSlaBreached ? 'SLA Breach · Task' : 'Overdue Task';
      final ok = await _emitOnce(
        key: '${type}_${task.id}',
        audience: audience,
        title: title,
        message: '${task.title} (due ${_fmt(task.dueDate)})',
        type: type,
        leadId: task.module.trim().isEmpty ? null : task.module.trim(),
        referenceId: task.id,
      );
      if (ok) n++;
    }
    return n;
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static Future<bool> _emitOnce({
    required String key,
    required String audience,
    required String title,
    required String message,
    required String type,
    String? leadId,
    String? referenceId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final dayKey = '$_prefsPrefix${_dayStamp()}_$key';
    if (prefs.getBool(dayKey) == true) return false;

    try {
      await NotificationsService.create(
        audience: audience,
        title: title,
        message: message,
        type: type,
        leadId: leadId,
        referenceId: referenceId ?? key,
      );
      await prefs.setBool(dayKey, true);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _dayStamp() {
    final n = DateTime.now();
    return '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}';
  }
}
