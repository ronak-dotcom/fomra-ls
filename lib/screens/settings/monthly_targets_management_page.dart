import 'package:flutter/material.dart';

import '../../analytics/monthly_target_progress.dart';
import '../../models/employee_profile.dart';
import '../../models/land_lead.dart';
import '../../models/land_lead_meeting.dart';
import '../../models/land_lead_site_visit.dart';
import '../../models/monthly_target_submission.dart';
import '../../services/app_store.dart';
import '../../services/employee_service.dart';
import '../../services/management_bi_activity_service.dart';
import '../../services/monthly_target_submission_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/fomra_app_shell.dart';
import '../../widgets/fomra_breadcrumb.dart';
import '../../widgets/monthly_target_editor.dart';
import '../../widgets/portal_page_layout.dart';
import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/app_feedback.dart';
import 'monthly_target_approvals_page.dart';

/// Management "Monthly Targets" — two tabs:
///  • Target   — every employee with their current-month target, editable.
///  • Approval — pending employee submissions to approve/reject/edit.
class MonthlyTargetsManagementPage extends StatelessWidget {
  const MonthlyTargetsManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: FomraAppShell(
        currentRoute: '/settings',
        appBar: FomraSubPageAppBar(
          title: 'Monthly Targets',
          breadcrumbs: FomraBreadcrumbs.forSettingsChild('Monthly Targets'),
        ),
        backgroundColor: context.fomraPageBg,
        body: Column(
          children: [
            Material(
              color: context.fomraSurface,
              child: TabBar(
                labelColor: AppColors.primary,
                unselectedLabelColor: context.fomraTextSecondary,
                indicatorColor: AppColors.primary,
                labelStyle:
                    const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                tabs: const [
                  Tab(text: 'Target'),
                  Tab(text: 'Approval'),
                ],
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  _TargetTab(),
                  MonthlyTargetApprovalsPage(embedded: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetTab extends StatefulWidget {
  const _TargetTab();

  @override
  State<_TargetTab> createState() => _TargetTabState();
}

class _TargetTabState extends State<_TargetTab> {
  final DateTime _now = DateTime.now();
  List<EmployeeProfile> _employees = const [];
  Map<String, MonthlyTargetSubmission> _byEmail = const {};
  List<LandLead> _leads = const [];
  List<LandLeadMeeting> _meetings = const [];
  List<LandLeadSiteVisit> _siteVisits = const [];
  bool _loading = true;
  String _search = '';

  String get _period => MonthlyTargetSubmission.periodOf(_now.year, _now.month);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      EmployeeService.getAll(),
      MonthlyTargetSubmissionService.allForPeriod(_period),
      ManagementBiActivityService.loadMeetings(),
      ManagementBiActivityService.loadSiteVisits(),
    ]);
    if (!mounted) return;
    final employees = (results[0] as List<EmployeeProfile>)
        .where((e) => e.status == EmployeeStatus.active)
        .toList()
      ..sort((a, b) =>
          a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    final subs = results[1] as List<MonthlyTargetSubmission>;
    setState(() {
      _employees = employees;
      _byEmail = {for (final s in subs) s.employeeEmail: s};
      _meetings = results[2] as List<LandLeadMeeting>;
      _siteVisits = results[3] as List<LandLeadSiteVisit>;
      _leads = AppStore.instance.leads;
      _loading = false;
    });
  }

  /// Achieved *dates* for [employee] this month, per mandatory category —
  /// dates rather than a plain count so MonthlyTargetProgress (the same
  /// run-rate/on-track logic the employee's own Home card uses) can be
  /// reused here directly instead of a second, separately-maintained copy
  /// of that math.
  Map<TargetCategory, List<DateTime>> _achievedDatesFor(EmployeeProfile employee) {
    final name = employee.fullName.trim().toLowerCase();
    if (name.isEmpty) return const {};
    final myLeads = [
      for (final l in _leads)
        if (l.createdByName.trim().toLowerCase() == name) l,
    ];
    if (myLeads.isEmpty) return const {};
    final myLeadIds = {for (final l in myLeads) l.leadId};

    final siteVisits = <DateTime>[];
    final selfMeetings = <DateTime>[];
    final managementMeetings = <DateTime>[];
    final brokerMeetings = <DateTime>[];
    for (final v in _siteVisits) {
      if (v.visitType == LandLeadSiteVisitType.employee &&
          myLeadIds.contains(v.leadId)) {
        siteVisits.add(v.visitedAt);
      }
    }
    for (final m in _meetings) {
      if (!myLeadIds.contains(m.leadId)) continue;
      (m.managementPresent ? managementMeetings : selfMeetings).add(m.metAt);
      if (m.attendeeTypes.contains(MeetingAttendeeTypes.broker)) {
        brokerMeetings.add(m.metAt);
      }
    }
    // A broker counts as "new" the first time their name appears on any of
    // this employee's leads — same rule as the employee's own Home card.
    final firstSeen = <String, DateTime>{};
    for (final l in myLeads) {
      final broker = l.brokerName.trim().toLowerCase();
      if (broker.isEmpty) continue;
      final existing = firstSeen[broker];
      if (existing == null || l.addedOn.isBefore(existing)) {
        firstSeen[broker] = l.addedOn;
      }
    }
    return {
      TargetCategory.siteVisits: siteVisits,
      TargetCategory.selfMeetings: selfMeetings,
      TargetCategory.managementMeetings: managementMeetings,
      TargetCategory.brokerMeetings: brokerMeetings,
      TargetCategory.newBrokers: firstSeen.values.toList(),
    };
  }

  Future<void> _edit(EmployeeProfile e) async {
    final email = e.email.trim().toLowerCase();
    final existing = _byEmail[email];
    final values = await showDialog<Map<String, int>>(
      context: context,
      builder: (_) => _EditEmployeeTargetDialog(
        employeeName: e.fullName.isEmpty ? e.email : e.fullName,
        monthLabel: MonthlyTargetSubmission.periodOf(_now.year, _now.month),
        initial: existing?.effectiveValues ?? const {},
      ),
    );
    if (values == null) return;
    try {
      await MonthlyTargetSubmissionService.setByManagement(
        year: _now.year,
        month: _now.month,
        values: values,
        employeeEmail: email,
        employeeName: e.fullName,
        employeeCode: e.id,
        department: e.department,
        designation: e.designation,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      AppFeedback.success(context, 'Target saved for ${e.fullName}.');
    } catch (err) {
      if (!mounted) return;
      AppFeedback.error(context, 'Could not save: $err');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          SectionHeader(
            title: 'Employee Targets',
            subtitle:
                'Set or edit each executive\'s targets for ${MonthlyTargetSubmission.monthName(_now.month)} ${_now.year}.',
            icon: Icons.flag_outlined,
          ),
          if (_employees.length > 1) ...[
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search by name or designation…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                filled: true,
                fillColor: context.fomraSurfaceVar,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Builder(builder: (context) {
            final q = _search.trim().toLowerCase();
            final visible = q.isEmpty
                ? _employees
                : _employees
                    .where((e) =>
                        e.fullName.toLowerCase().contains(q) ||
                        e.designation.toLowerCase().contains(q))
                    .toList();
            if (_employees.isEmpty) {
              return const AppCard(
                interactive: false,
                child: EmptyState(
                  icon: Icons.people_outline,
                  title: 'No active executives',
                  message: 'Active executives will appear here.',
                ),
              );
            }
            if (visible.isEmpty) {
              return AppCard(
                interactive: false,
                child: EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matches',
                  message: 'No one matches "$_search".',
                ),
              );
            }
            return Column(
              children: [
                for (final e in visible) ...[
                  _row(context, e),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }

  /// Target vs. achieved for the three mandatory categories — what
  /// management was missing entirely before: the Target tab showed only
  /// the goal number, never how each executive is actually tracking
  /// against it.
  Widget _achievementRow(
    BuildContext context,
    EmployeeProfile e,
    Map<String, int> targetValues,
  ) {
    final dates = _achievedDatesFor(e);
    final cats = [
      TargetCategory.siteVisits,
      TargetCategory.selfMeetings,
      TargetCategory.managementMeetings,
      TargetCategory.brokerMeetings,
      TargetCategory.newBrokers,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final c in cats)
          if (targetValues.containsKey(c.key))
            _achievementChip(
              context,
              label: c.label,
              progress: MonthlyTargetProgress.forMonth(
                target: targetValues[c.key] ?? 0,
                now: _now,
                completedOn: dates[c] ?? const [],
              ),
            ),
      ],
    );
  }

  Widget _achievementChip(
    BuildContext context, {
    required String label,
    required MonthlyTargetProgress progress,
  }) {
    final onTrack = progress.target <= 0 || progress.isOnTrack;
    final color = onTrack ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label: ${progress.achieved}/${progress.target}',
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Widget _row(BuildContext context, EmployeeProfile e) {
    final sub = _byEmail[e.email.trim().toLowerCase()];
    final values = sub?.effectiveValues ?? const <String, int>{};
    final summary = [
      for (final c in TargetCategory.values)
        if (values.containsKey(c.key)) '${c.label} ${values[c.key]}',
    ];
    return AppCard(
      interactive: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.fullName.isEmpty ? e.email : e.fullName,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: context.fomraTextPrimary,
                  ),
                ),
                if (e.designation.isNotEmpty)
                  Text(e.designation,
                      style: TextStyle(
                          fontSize: 11.5, color: context.fomraTextSecondary)),
                const SizedBox(height: 6),
                Text(
                  summary.isEmpty ? 'No target set' : summary.join(' · '),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight:
                        summary.isEmpty ? FontWeight.w500 : FontWeight.w700,
                    color: summary.isEmpty
                        ? context.fomraTextSecondary
                        : context.fomraTextPrimary,
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: sub.status.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(sub.status.label,
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: sub.status.color)),
                  ),
                ],
                if (sub != null && sub.status == TargetSubmissionStatus.approved) ...[
                  const SizedBox(height: 8),
                  _achievementRow(context, e, values),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () => _edit(e),
            icon: const Icon(Icons.edit_outlined, size: 15),
            label: const Text('Edit'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small dialog to set/edit one employee's per-category target.
class _EditEmployeeTargetDialog extends StatefulWidget {
  final String employeeName;
  final String monthLabel;
  final Map<String, int> initial;

  const _EditEmployeeTargetDialog({
    required this.employeeName,
    required this.monthLabel,
    required this.initial,
  });

  @override
  State<_EditEmployeeTargetDialog> createState() =>
      _EditEmployeeTargetDialogState();
}

class _EditEmployeeTargetDialogState extends State<_EditEmployeeTargetDialog> {
  late Map<String, int> _values = Map.of(widget.initial);
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.fomraSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Edit target',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.fomraTextPrimary)),
              const SizedBox(height: 2),
              Text(widget.employeeName,
                  style: TextStyle(
                      fontSize: 12, color: context.fomraTextSecondary)),
              const SizedBox(height: 16),
              MonthlyTargetEditor(
                initial: widget.initial,
                onChanged: (v) {
                  _values = v;
                  if (_error != null) setState(() => _error = null);
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.error)),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () {
                      if (_values.isEmpty) {
                        setState(() =>
                            _error = 'Select at least one category.');
                        return;
                      }
                      Navigator.pop(context, _values);
                    },
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Save changes'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
