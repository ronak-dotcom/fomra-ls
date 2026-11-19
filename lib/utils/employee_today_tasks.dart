import '../models/land_lead.dart';
import '../screens/task_management/task_management_screen.dart';

class EmployeeTodayTaskItem {
  final LandLead lead;
  final String followUp;
  final List<EmployeePendingWork> pendingWork;

  const EmployeeTodayTaskItem({
    required this.lead,
    required this.followUp,
    required this.pendingWork,
  });

  bool get hasDueToday =>
      pendingWork.any((w) => w.isDueToday || w.isOverdue);
}

class EmployeePendingWork {
  final String label;
  final TaskStatus status;
  final DateTime dueDate;
  final bool isDueToday;
  final bool isOverdue;

  const EmployeePendingWork({
    required this.label,
    required this.status,
    required this.dueDate,
    required this.isDueToday,
    required this.isOverdue,
  });
}

String followUpLabelForLead(LandLead lead) => switch (lead.status) {
      LeadStatus.prospectMeetingPending =>
        'Schedule and complete land owner meeting',
      LeadStatus.prospectMeetingCompleted =>
        'Conduct site visit or log next meeting',
      LeadStatus.managementMeetingCompleted =>
        'Schedule site visit or continue negotiation prep',
      LeadStatus.negotiation =>
        'Continue negotiation — log meetings and follow up on terms',
      LeadStatus.legal => 'Complete legal verification and documents',
      LeadStatus.onHold => '',
      LeadStatus.signed => '',
      LeadStatus.dropped => '',
    };

List<EmployeeTodayTaskItem> buildEmployeeTodayTasks({
  required String employeeName,
  required List<LandLead> leads,
  required List<Task> tasks,
  DateTime? now,
}) {
  final me = employeeName.trim().toLowerCase();
  if (me.isEmpty) return [];

  final clock = (now ?? DateTime.now()).toLocal();
  final today = DateTime(clock.year, clock.month, clock.day);

  bool isToday(DateTime date) {
    final local = date.toLocal();
    return local.year == today.year &&
        local.month == today.month &&
        local.day == today.day;
  }

  bool isPastDue(DateTime date) {
    final local = date.toLocal();
    final dueDay = DateTime(local.year, local.month, local.day);
    return dueDay.isBefore(today);
  }

  final myActiveLeads = leads
      .where((l) =>
          l.createdByName.trim().toLowerCase() == me && l.status.isActive)
      .toList();

  final items = <EmployeeTodayTaskItem>[];

  for (final lead in myActiveLeads) {
    final followUp = followUpLabelForLead(lead);
    final pendingWork = tasks
        .where((t) => t.module == lead.leadId && t.status != TaskStatus.done)
        .map((t) {
          final dueToday = isToday(t.dueDate);
          final overdue =
              t.status == TaskStatus.overdue || isPastDue(t.dueDate);
          return EmployeePendingWork(
            label: t.title.trim().isEmpty ? 'Untitled task' : t.title.trim(),
            status: t.status,
            dueDate: t.dueDate,
            isDueToday: dueToday,
            isOverdue: overdue,
          );
        })
        .toList()
      ..sort((a, b) {
        final aUrgent = a.isDueToday || a.isOverdue ? 0 : 1;
        final bUrgent = b.isDueToday || b.isOverdue ? 0 : 1;
        if (aUrgent != bUrgent) return aUrgent.compareTo(bUrgent);
        return a.dueDate.compareTo(b.dueDate);
      });

    items.add(EmployeeTodayTaskItem(
      lead: lead,
      followUp: followUp,
      pendingWork: pendingWork,
    ));
  }

  items.sort((a, b) {
    final aUrgent = a.hasDueToday ? 0 : 1;
    final bUrgent = b.hasDueToday ? 0 : 1;
    if (aUrgent != bUrgent) return aUrgent.compareTo(bUrgent);
    return b.lead.addedOn.compareTo(a.lead.addedOn);
  });

  return items;
}
