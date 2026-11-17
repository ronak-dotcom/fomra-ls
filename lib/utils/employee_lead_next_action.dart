import '../models/land_lead.dart';
import '../models/land_lead_meeting.dart';
import '../models/land_lead_site_visit.dart';
import '../screens/task_management/task_management_screen.dart';

/// The activities a lead is worked through, in the order they happen. The card
/// shows the first one that is still pending.
enum EmployeeNextActionKind {
  landOwnerMeeting,
  siteVisit,
  legalVerification,
  managementSiteVisit,
  projectSigning,
  none,
}

/// The single pending activity to put in front of the executive.
///
/// Carries no due date, priority or overdue flag on purpose: what matters is
/// *what* to do next and *why*, and the pipeline itself decides the order.
class EmployeeNextAction {
  final EmployeeNextActionKind kind;

  /// Short imperative title, e.g. "Conduct Site Visit".
  final String title;

  /// Why this is the next action, in one sentence.
  final String description;

  const EmployeeNextAction({
    required this.kind,
    required this.title,
    required this.description,
  });

  bool get isPending => kind != EmployeeNextActionKind.none;
}

class EmployeePendingTaskSummary {
  final int dueToday;
  final int overdue;
  final int pendingSinceDays;
  final List<Task> dueTodayTasks;
  final List<Task> overdueTasks;

  const EmployeePendingTaskSummary({
    required this.dueToday,
    required this.overdue,
    required this.pendingSinceDays,
    required this.dueTodayTasks,
    required this.overdueTasks,
  });
}

class EmployeeLeadWorkflowInsight {
  final EmployeeNextAction nextAction;
  final EmployeePendingTaskSummary tasks;

  /// The lead's current stage, shown beside the action for context.
  final LeadStatus stage;

  const EmployeeLeadWorkflowInsight({
    required this.nextAction,
    required this.tasks,
    required this.stage,
  });
}

class EmployeeLeadWorkflow {
  static EmployeeLeadWorkflowInsight build({
    required LandLead lead,
    required List<LandLeadSiteVisit> siteVisits,
    required List<LandLeadMeeting> meetings,
    required int legalDocCount,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final tasks = tasksForLead(lead.leadId);
    return EmployeeLeadWorkflowInsight(
      stage: lead.status,
      nextAction: _nextAction(
        lead: lead,
        siteVisits: siteVisits,
        meetings: meetings,
        legalDocCount: legalDocCount,
      ),
      tasks: _taskSummary(tasks, clock),
    );
  }

  static EmployeePendingTaskSummary _taskSummary(
    List<Task> tasks,
    DateTime now,
  ) {
    final open = tasks.where((t) => t.status != TaskStatus.done).toList();
    final today = DateTime(now.year, now.month, now.day);
    final dueToday = <Task>[];
    final overdue = <Task>[];
    var oldestPending = 0;

    for (final t in open) {
      final due = DateTime(t.dueDate.year, t.dueDate.month, t.dueDate.day);
      if (t.isOverdue || due.isBefore(today)) {
        overdue.add(t);
      } else if (due == today) {
        dueToday.add(t);
      }
      final pending = today
          .difference(DateTime(
            t.createdAt.year,
            t.createdAt.month,
            t.createdAt.day,
          ))
          .inDays;
      if (pending > oldestPending) oldestPending = pending;
    }

    return EmployeePendingTaskSummary(
      dueToday: dueToday.length,
      overdue: overdue.length,
      pendingSinceDays: oldestPending,
      dueTodayTasks: dueToday,
      overdueTasks: overdue,
    );
  }

  /// The highest-priority activity still pending, in the order the pipeline is
  /// actually worked: land owner meeting -> site visit -> legal ->
  /// management site visit -> signing.
  ///
  /// Read from the same meeting / visit / document data the Activity
  /// Timeline shows, so completing an activity moves the card on by itself.
  static EmployeeNextAction _nextAction({
    required LandLead lead,
    required List<LandLeadSiteVisit> siteVisits,
    required List<LandLeadMeeting> meetings,
    required int legalDocCount,
  }) {
    // A closed lead has no next step, whatever is missing behind it.
    if (lead.status == LeadStatus.dropped) {
      return const EmployeeNextAction(
        kind: EmployeeNextActionKind.none,
        title: 'No Pending Action',
        description: 'This lead was dropped, so nothing is left to do on it.',
      );
    }
    if (lead.status == LeadStatus.signed) {
      return const EmployeeNextAction(
        kind: EmployeeNextActionKind.none,
        title: 'No Pending Action',
        description:
            'The project is signed and every activity on this lead is complete.',
      );
    }

    if (meetings.isEmpty) {
      return const EmployeeNextAction(
        kind: EmployeeNextActionKind.landOwnerMeeting,
        title: 'Conduct Land Owner Meeting',
        description: 'No land owner meeting is logged yet. Meet the owner '
            'before visiting the site.',
      );
    }

    if (!_hasVisit(siteVisits, LandLeadSiteVisitType.employee)) {
      return const EmployeeNextAction(
        kind: EmployeeNextActionKind.siteVisit,
        title: 'Conduct Site Visit',
        description: 'The land owner meeting is done. Visit the site and log '
            'what you find before the legal check.',
      );
    }

    if (legalDocCount == 0) {
      return const EmployeeNextAction(
        kind: EmployeeNextActionKind.legalVerification,
        title: 'Complete Legal Verification',
        description: 'The site visit is done, but no legal document has been '
            'collected yet.',
      );
    }

    if (!_hasVisit(siteVisits, LandLeadSiteVisitType.management)) {
      return const EmployeeNextAction(
        kind: EmployeeNextActionKind.managementSiteVisit,
        title: 'Management Site Visit',
        description: 'Legal documents are in. Management still needs to see '
            'the site before the project can be signed.',
      );
    }

    return const EmployeeNextAction(
      kind: EmployeeNextActionKind.projectSigning,
      title: 'Project Signing',
      description: 'Every activity is complete. Close the deal and mark the '
          'project as signed.',
    );
  }

  /// A visit counts as made unless it was rejected — one still awaiting
  /// approval has already happened, so it is not pending on the executive.
  static bool _hasVisit(
    List<LandLeadSiteVisit> visits,
    LandLeadSiteVisitType type,
  ) =>
      visits.any((v) =>
          v.visitType == type &&
          v.approvalStatus != SiteVisitApprovalStatus.rejected);
}

/// Legal document kinds for camera capture.
enum LegalDocCaptureKind { patta, chitta, fmb, saleDeed }

extension LegalDocCaptureKindX on LegalDocCaptureKind {
  String get label => switch (this) {
        LegalDocCaptureKind.patta => 'Patta',
        LegalDocCaptureKind.chitta => 'Chitta',
        LegalDocCaptureKind.fmb => 'FMB',
        LegalDocCaptureKind.saleDeed => 'Sale Deed',
      };

  String filePrefix(String original) => '${label}_$original';
}
