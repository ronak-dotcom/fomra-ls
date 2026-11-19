import 'dart:async';
import 'package:flutter/material.dart';
import '../../analytics/business_module_metrics.dart';
import '../../models/land_lead.dart';
import '../../analytics/monthly_target_progress.dart';
import '../../models/land_lead_meeting.dart';
import '../../models/lead_follow_up.dart';
import '../../models/monthly_target_submission.dart';
import '../../services/lead_follow_up_service.dart';
import '../../services/management_bi_activity_service.dart';
import '../land_lead/add_lead_screen.dart';
import '../../models/lead_list_filter.dart';
import '../land_lead/filtered_leads_screen.dart';
import '../land_lead/leads_map_screen.dart';
import '../land_lead/management_visit_review_dialog.dart';
import '../../services/approval_chain.dart';
import '../../services/auth_service.dart';
import '../../services/broker_directory.dart';
import '../../services/app_store.dart';
import '../../models/employee_profile.dart';
import '../../services/employee_service.dart';
import '../../services/team_hierarchy.dart';
import '../employee_management/team_management_screen.dart';
import '../../services/land_lead_service.dart';
import '../../services/monthly_target_service.dart';
import '../../services/monthly_target_submission_service.dart';
import '../../services/lead_drop_approval_service.dart';
import '../../services/land_lead_signed_service.dart';
import '../../services/land_lead_site_visit_service.dart';
import '../../services/notification_hub.dart';
import '../../services/push_service.dart';
import '../../services/universal_search_service.dart';
import '../../services/view_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_layout.dart';
import '../../theme/fomra_theme_context.dart';
import '../../models/land_lead_signed_request.dart';
import '../../models/land_lead_site_visit.dart';
import '../settings/employee_monthly_targets_page.dart';
import '../settings/monthly_target_approvals_page.dart';
import '../../widgets/fomra_app_bar.dart';
import '../../widgets/fomra_app_shell.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/management_home_cards.dart';
import '../../analytics/management_bi_metrics.dart';
import '../../widgets/offline_status_banner.dart';
import '../../widgets/portal_home_sections.dart';
import '../../widgets/broker_energy_summary.dart';
import '../../widgets/property_review_summary.dart';
import '../../widgets/team_performance_card.dart';
import '../../analytics/team_performance.dart';
import '../../widgets/ui/app_components.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  DateTime _clock = DateTime.now();

  List<LandLeadSiteVisit> _pendingApprovals = [];
  List<LandLeadSignedRequest> _pendingSigned = [];
  List<LeadDropApprovalRequest> _pendingDropApprovals = [];
  List<MonthlyTargetSubmission> _pendingMonthlyTargets = [];
  bool _loadingApprovals = false;

  /// Meeting history behind the management "No Future Activity" quick action.
  List<LandLeadMeeting> _meetings = const [];

  /// True once this employee's monthly target has been looked up (management
  /// never loads it).
  bool _targetsLoaded = false;

  /// A management-set target (sites added this month) — only used when the
  /// employee has no approved target of their own.
  int _monthlyTargetCount = 0;

  /// True when the resolved target came from the employee's own approved
  /// submission rather than a management-set row.
  bool _monthlyTargetFromEmployee = false;

  /// True when the employee has submitted this month but it is still pending
  /// approval (so My month can explain why no target is active yet).
  bool _monthlyTargetPendingApproval = false;

  /// Approved per-category targets when the active target is the employee's
  /// own approved submission.
  Map<String, int> _approvedTargetValues = const {};
  List<LandLeadMeeting> _targetMeetings = const [];
  List<LeadFollowUp> _overdueFollowUps = const [];
  /// Target lines My month adds under the site visit / meeting lines: broker
  /// targets when set, or a management-set "sites added" target.
  List<(String, MonthlyTargetProgress)> _extraTargets = const [];

  List<LandLead> get _noFutureActivityLeads => NoFutureActivityAnalytics.select(
        AppStore.instance.visibleLeads,
        _isManagement ? _meetings : _targetMeetings,
      );

  int get _activeLeads =>
      _homeSummaryLeads.where((l) => l.status.isActive).length;


  bool get _isManagement => AuthService.instance.isManagement;

  /// Management plus Reporting Managers / Heads have an approvals queue: each
  /// sees only the requests currently waiting on them in the approval chain.
  bool get _canApprove {
    if (_isManagement) return true;
    final d = TeamHierarchy.currentDesignation;
    return d == EmployeeDesignations.reportingManager ||
        d == EmployeeDesignations.head;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppStore.instance.addListener(_onStoreUpdate);
    // Register this device for push under the signed-in audience (guarded).
    PushService.syncToken();
    // Loading, realtime and reminder-sync all live in the hub behind the header
    // bell; the dashboard just follows it.
    NotificationHub.instance.addListener(_onNotificationsChanged);
    _loadPerformanceData();
    if (_canApprove) _loadPendingApprovals();
    if (_isManagement) _loadMeetings();
    if (!_isManagement) {
      _loadMonthlyTarget();
      _loadTargetActivity();
      _loadOverdueFollowUps();
      // Re-scope the Monthly Target card when the Team / Individual toggle flips.
      ViewScope.instance.addListener(_loadMonthlyTarget);
    }
    UniversalSearchService.warmDocumentIndex();
  }

  /// Only management gets the "No Future Activity" quick action, so only
  /// management pays for the meeting history it needs.
  Future<void> _loadMeetings() async {
    final meetings = await ManagementBiActivityService.loadMeetings();
    if (mounted) setState(() => _meetings = meetings);
  }

  Future<void> _loadOverdueFollowUps() async {
    final email = AuthService.instance.currentUser?.email ?? '';
    final due = await LeadFollowUpService.dueForUser(email);
    if (mounted) setState(() => _overdueFollowUps = due);
  }

  /// Resolves each follow-up to its actual lead, deduplicated — an
  /// executive can have more than one overdue follow-up on the same lead,
  /// but the "Overdue Follow-ups" tile should list each site once.
  List<LandLead> _leadsFor(List<LeadFollowUp> followUps) {
    final byId = {for (final l in AppStore.instance.visibleLeads) l.leadId: l};
    final seen = <String>{};
    final out = <LandLead>[];
    for (final f in followUps) {
      final lead = byId[f.leadId];
      if (lead != null && seen.add(lead.leadId)) out.add(lead);
    }
    return out;
  }

  /// Resolves this employee's monthly target for the progress card.
  ///
  /// Prefer an **approved** self-set submission (Settings › My Monthly Targets).
  /// While a submission is **pending**, do not fall back to a management-set
  /// target — show the awaiting-approval empty state instead. Only fall back
  /// to the management-set common/personal target when there is no current
  /// submission (or the last one was rejected).
  Future<void> _loadMonthlyTarget() async {
    final now = DateTime.now();
    final myEmail =
        (AuthService.instance.currentUser?.email ?? '').trim().toLowerCase();

    var targetCount = 0;
    var fromEmployee = false;
    var pendingApproval = false;
    Map<String, int> approvedValues = const {};

    try {
      // Prefer the dedicated approved lookup, then fall back to history so a
      // pending/rejected row can still drive the empty-state copy.
      final approved =
          await MonthlyTargetSubmissionService.approvedForEmployee(
        myEmail,
        now: now,
      );
      if (approved != null) {
        fromEmployee = true;
        targetCount = approved.sitesProgressTarget;
        approvedValues = approved.effectiveValues;
      } else {
        final history =
            await MonthlyTargetSubmissionService.getForEmployee(myEmail);
        final period =
            MonthlyTargetSubmission.periodOf(now.year, now.month);
        MonthlyTargetSubmission? current;
        for (final s in history) {
          if (s.period == period) {
            current = s;
            break;
          }
        }
        if (current != null) {
          if (current.isPending) {
            pendingApproval = true;
          } else if (current.isApproved) {
            fromEmployee = true;
            targetCount = current.sitesProgressTarget;
            approvedValues = current.effectiveValues;
          }
          // Rejected → fall through to management target below.
        }
      }
    } catch (_) {
      // Submission table may be missing — fall through to management target.
    }

    // Only use the management-set target when the employee has nothing in
    // flight for this month (no pending / no approved submission).
    if (!fromEmployee && !pendingApproval) {
      final target =
          await MonthlyTargetService.resolveForEmployee(myEmail, now: now);
      targetCount = target?.target ?? 0;
      fromEmployee = false;
    }

    if (!mounted) return;
    _monthlyTargetCount = pendingApproval ? 0 : targetCount;
    _monthlyTargetFromEmployee = fromEmployee && !pendingApproval;
    _monthlyTargetPendingApproval = pendingApproval;
    _approvedTargetValues = pendingApproval ? const {} : approvedValues;
    _recomputeMonthlyProgress();
  }

  /// Loads the meeting history that feeds the per-category
  /// progress boxes/lines. Bulk reads, scoped to the executive's visible leads
  /// at compute time. Best-effort — an empty result just shows zero achieved.
  Future<void> _loadTargetActivity() async {
    final meetings = await ManagementBiActivityService.loadMeetings();
    if (!mounted) return;
    _targetMeetings = meetings;
    _recomputeMonthlyProgress();
  }

  /// Recompute My month's extra target lines from the cached target and the
  /// CURRENT visibleLeads — cheap and local, so it can run on every store /
  /// scope change. Site visits and meetings against target come from the
  /// Team Performance card itself.
  void _recomputeMonthlyProgress() {
    if (_isManagement) return;
    final now = DateTime.now();
    final visible = AppStore.instance.visibleLeads;
    final visibleIds = {for (final l in visible) l.leadId};
    final extra = <(String, MonthlyTargetProgress)>[];
    final tv = _approvedTargetValues;
    if (_monthlyTargetFromEmployee && tv.isNotEmpty) {
      // New Brokers / Broker Meetings are optional: only when targeted.
      final firsts = FirstMeetings.of(_targetMeetings);
      final brokerMeetings = tv[TargetCategory.brokerMeetings.key] ?? 0;
      if (brokerMeetings > 0) {
        extra.add((
          'Broker meetings',
          MonthlyTargetProgress.forMonth(
            target: brokerMeetings,
            now: now,
            completedOn: [
              for (final m in firsts.broker)
                if (visibleIds.contains(m.leadId)) m.metAt,
            ],
          ),
        ));
      }
      final newBrokers = tv[TargetCategory.newBrokers.key] ?? 0;
      if (newBrokers > 0) {
        extra.add((
          'New brokers',
          MonthlyTargetProgress.forMonth(
            target: newBrokers,
            now: now,
            // A broker counts as "new" the first time they appear on one of
            // this executive's leads.
            completedOn: _newBrokerDatesThisMonth(visible, now),
          ),
        ));
      }
    } else if (!_monthlyTargetPendingApproval && _monthlyTargetCount > 0) {
      // Management-set target: sites added this month.
      extra.add((
        'Sites added',
        MonthlyTargetProgress.forMonth(
          target: _monthlyTargetCount,
          now: now,
          completedOn: [for (final l in visible) l.addedOn],
        ),
      ));
    }

    setState(() {
      _targetsLoaded = true;
      _extraTargets = extra;
    });
  }

  /// A broker counts toward "New Brokers" the first time their name shows
  /// up on this executive's leads at all — i.e. the earliest lead carrying
  /// that broker name was added this month. A broker name seen on any
  /// earlier lead doesn't count again just because they show up on another
  /// lead this month.
  List<DateTime> _newBrokerDatesThisMonth(List<LandLead> leads, DateTime now) {
    final firstSeen = <String, DateTime>{};
    for (final l in leads) {
      // By mobile number: one broker typed two ways is still one broker.
      if (l.brokerName.trim().isEmpty) continue;
      final broker = BrokerDirectory.keyFor(l);
      final existing = firstSeen[broker];
      if (existing == null || l.addedOn.isBefore(existing)) {
        firstSeen[broker] = l.addedOn;
      }
    }
    return [
      for (final d in firstSeen.values)
        if (d.year == now.year && d.month == now.month) d,
    ];
  }

  void _openMyMonthlyTargets() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EmployeeMonthlyTargetsPage()),
    ).then((_) {
      if (mounted && !_isManagement) _loadMonthlyTarget();
    });
  }

  void _onNotificationsChanged() {
    if (!mounted) return;
    setState(() {});
    if (_canApprove) _loadPendingApprovals();
  }

  /// Make sure leads are loaded so both the management leaderboard and an
  /// employee's own "leads added" count have data before those screens are
  /// opened. The employee roster is only needed for the management leaderboard.
  Future<void> _loadPerformanceData() async {
    if (AppStore.instance.leads.isEmpty) {
      try {
        final leads = await LandLeadService.getAll();
        AppStore.instance.setLeads(leads);
      } catch (_) {/* keep whatever is cached */}
    }
    // The roster is needed by the management leaderboard and by Reporting
    // Manager / Head team + performance views, so load it for everyone.
    if (AppStore.instance.employees.isEmpty) {
      try {
        final employees = await EmployeeService.getAll();
        if (employees.isNotEmpty) {
          AppStore.instance.setEmployees(employees);
          if (mounted) setState(() {});
        }
      } catch (_) {/* fall back to lead-derived names */}
    }
  }

  /// Leads the signed-in user may currently see. For a Reporting Manager / Head
  /// this is already their whole team or just themselves, depending on the
  /// header's Team / Individual toggle — see [LeadVisibility].
  List<LandLead> get _myLeads => AppStore.instance.visibleLeads;

  /// Summary tiles on home — all leads for management, scoped leads otherwise.
  List<LandLead> get _homeSummaryLeads =>
      _isManagement ? AppStore.instance.leads : _myLeads;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppStore.instance.removeListener(_onStoreUpdate);
    NotificationHub.instance.removeListener(_onNotificationsChanged);
    ViewScope.instance.removeListener(_loadMonthlyTarget);
    super.dispose();
  }

  void _onStoreUpdate() {
    // Leads just changed in the store — refresh the Monthly Target's signed
    // count from the new visibleLeads (recompute calls setState). Management
    // doesn't show the card, so a plain rebuild is enough for it.
    if (!_isManagement && _targetsLoaded) {
      _recomputeMonthlyProgress();
    } else {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _clock = DateTime.now());
    }
  }

  Future<void> _loadPendingApprovals() async {
    if (!_canApprove) return;
    setState(() => _loadingApprovals = true);
    List<LandLeadSiteVisit> visits = const [];
    try {
      visits = await LandLeadSiteVisitService.getPendingManagementVisits();
    } catch (_) {/* keep existing */}
    List<LandLeadSignedRequest> signed = const [];
    try {
      signed = await LandLeadSignedService.getPending();
    } catch (_) {/* table may not exist yet */}
    List<LeadDropApprovalRequest> dropRequests = const [];
    try {
      dropRequests = await LeadDropApprovalService.getPending();
    } catch (_) {/* notification storage may not exist yet */}
    List<MonthlyTargetSubmission> monthlyTargets = const [];
    try {
      monthlyTargets = await MonthlyTargetSubmissionService.getPending();
    } catch (_) {/* table may not exist yet */}
    if (mounted) {
      setState(() {
        _pendingApprovals = visits;
        _pendingSigned = signed;
        _pendingDropApprovals = dropRequests;
        _pendingMonthlyTargets = monthlyTargets;
        _loadingApprovals = false;
      });
    }
  }

  Future<void> _approveDropRequest(LeadDropApprovalRequest request) async {
    if (!ApprovalChain.canActOn(
        level: request.approvalLevel, pendingWith: request.pendingWith)) {
      if (!mounted) return;
      AppFeedback.error(context, 'This request is not waiting on you.');
      return;
    }
    try {
      await LeadDropApprovalService.review(request: request, approve: true);
      if (!mounted) return;
      AppFeedback.success(context, 'Drop request approved and lead dropped');
      await _loadPendingApprovals();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, 'Could not approve drop request: $e');
    }
  }

  Future<void> _rejectDropRequest(LeadDropApprovalRequest request) async {
    if (!ApprovalChain.canActOn(
        level: request.approvalLevel, pendingWith: request.pendingWith)) {
      if (!mounted) return;
      AppFeedback.error(context, 'This request is not waiting on you.');
      return;
    }
    try {
      await LeadDropApprovalService.review(request: request, approve: false);
      if (!mounted) return;
      AppFeedback.info(context, 'Drop request rejected');
      await _loadPendingApprovals();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, 'Could not reject drop request: $e');
    }
  }

  Future<void> _approveSignedRequest(LandLeadSignedRequest request) async {
    if (!ApprovalChain.canActOn(
        level: request.approvalLevel, pendingWith: request.pendingWith)) {
      if (!mounted) return;
      AppFeedback.error(context, 'This request is not waiting on you.');
      return;
    }
    try {
      await LandLeadSignedService.review(id: request.id, approve: true);
      if (!mounted) return;
      AppFeedback.success(context, 'Project approved and marked as Signed');
      await _loadPendingApprovals();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, 'Could not approve: $e');
    }
  }

  Future<void> _rejectSignedRequest(LandLeadSignedRequest request) async {
    if (!ApprovalChain.canActOn(
        level: request.approvalLevel, pendingWith: request.pendingWith)) {
      if (!mounted) return;
      AppFeedback.error(context, 'This request is not waiting on you.');
      return;
    }
    try {
      await LandLeadSignedService.review(id: request.id, approve: false);
      if (!mounted) return;
      AppFeedback.info(context, 'Signed request rejected');
      await _loadPendingApprovals();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, 'Could not reject: $e');
    }
  }

  Future<void> _reviewPendingVisit(LandLeadSiteVisit visit) async {
    final ok = await showManagementVisitReviewDialog(
      context,
      visitId: visit.id,
      leadId: visit.leadId,
    );
    if (ok == true && mounted) await _loadPendingApprovals();
  }

  Future<void> _approvePendingVisit(LandLeadSiteVisit visit) async {
    if (!ApprovalChain.canActOn(
        level: visit.approvalLevel, pendingWith: visit.pendingWith)) {
      if (!mounted) return;
      AppFeedback.error(context, 'This request is not waiting on you.');
      return;
    }
    try {
      await LandLeadSiteVisitService.review(
        visitId: visit.id,
        status: SiteVisitApprovalStatus.approved,
        notes: '',
      );
      if (!mounted) return;
      AppFeedback.success(context, 'Management site visit approved');
      await _loadPendingApprovals();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, 'Could not approve visit: $e');
    }
  }

  Future<void> _rejectPendingVisit(LandLeadSiteVisit visit) async {
    await _reviewPendingVisit(visit);
  }

  Future<void> _approveMonthlyTarget(MonthlyTargetSubmission s) async {
    try {
      await MonthlyTargetSubmissionService.approve(submission: s);
      if (!mounted) return;
      AppFeedback.success(context, 'Targets approved.');
      await _loadPendingApprovals();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, 'Could not approve targets: $e');
    }
  }

  Future<void> _rejectMonthlyTarget(MonthlyTargetSubmission s) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject targets'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            hintText: 'Why are these targets being rejected?',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (reason == null) return;
    try {
      await MonthlyTargetSubmissionService.reject(
          submission: s, reason: reason);
      if (!mounted) return;
      AppFeedback.info(context, 'Targets rejected.');
      await _loadPendingApprovals();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, 'Could not reject targets: $e');
    }
  }

  Future<void> _editMonthlyTarget(MonthlyTargetSubmission s) async {
    final result = await showMonthlyTargetEditDialog(context, s);
    if (result == null) return;
    try {
      switch (result.action) {
        case MonthlyTargetEditAction.save:
          await MonthlyTargetSubmissionService.saveEdits(
              submission: s, values: result.values);
          if (!mounted) return;
          AppFeedback.success(
              context, 'Changes saved — still pending approval.');
        case MonthlyTargetEditAction.approve:
          await MonthlyTargetSubmissionService.approve(
              submission: s, approvedValues: result.values);
          if (!mounted) return;
          AppFeedback.success(context, 'Targets approved.');
        case MonthlyTargetEditAction.reject:
          final ctrl = TextEditingController();
          final reason = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('Reject targets'),
              content: TextField(
                controller: ctrl,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  hintText: 'Why are these targets being rejected?',
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                  style:
                      FilledButton.styleFrom(backgroundColor: AppColors.error),
                  child: const Text('Reject'),
                ),
              ],
            ),
          );
          if (reason == null) return;
          await MonthlyTargetSubmissionService.reject(
              submission: s, reason: reason);
          if (!mounted) return;
          AppFeedback.info(context, 'Targets rejected.');
      }
      await _loadPendingApprovals();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, 'Action failed: $e');
    }
  }

  void _goTo(String route) => Navigator.pushNamed(context, route);

  void _openAllProjectsMap(List<LandLead> leads) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LeadsMapScreen(leads: leads)),
    );
  }

  void _openAddLead() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddLeadScreen()),
    ).then((saved) {
      if (saved is! LandLead || !mounted) return;
      AppStore.instance.addLead(saved);
      AppFeedback.success(context, 'Site ${saved.leadId} saved.');
    });
  }

  Widget _quickActionsSection(
    List<PortalQuickAction> actions, {
    int? columns,
    bool asCard = false,
  }) {
    final grid = PortalQuickActionsGrid(actions: actions, columns: columns);
    final body = asCard
        ? PortalSectionCard(
            title: 'Quick actions',
            // Matches Today's tasks' subtitle so the two side-by-side boxes'
            // headers are the same height and the cards line up.
            subtitle: 'Common shortcuts',
            icon: Icons.flash_on_rounded,
            child: grid,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(
                title: 'Quick actions',
                icon: Icons.flash_on_rounded,
              ),
              grid,
            ],
          );
    return PortalFadeSection(index: 1, child: body);
  }

  /// What is waiting on an executive / manager: their sites by stage, overdue
  /// follow-ups, sites with no next step, and (for managers) approvals. Only
  /// lines with something waiting get a box; the rest share one "All clear".
  List<AttentionItem> _myAttentionItems(int approvalCount) {
    final active = [
      for (final l in _homeSummaryLeads)
        if (l.status.isActive) l
    ];
    List<LandLead> at(LeadStatus s) => [
          for (final l in active)
            if (l.status == s) l
        ];
    VoidCallback open(String title, String subtitle, List<LandLead> leads) =>
        () => FilteredLeadsScreen.openList(context,
            title: title, subtitle: subtitle, leads: leads);
    final followUps = _leadsFor(_overdueFollowUps);
    final ownerPending = at(LeadStatus.prospectMeetingPending);
    final visitToPlan = at(LeadStatus.prospectMeetingCompleted);
    final negotiation = at(LeadStatus.negotiation);
    final legal = at(LeadStatus.legal);
    final noNextStep = _noFutureActivityLeads;
    return [
      if (_canApprove)
        AttentionItem(
          icon: Icons.approval_outlined,
          color: AppColors.warning,
          title: 'Approvals waiting on you',
          subtitle: 'Site visit, signed, drop and target requests',
          count: approvalCount,
          clearLabel: 'approvals',
          onTap: _openApprovalsList,
        ),
      AttentionItem(
        icon: Icons.notifications_active_outlined,
        color: AppColors.error,
        title: 'Overdue follow-ups',
        subtitle: 'The follow-up date has passed',
        count: followUps.length,
        clearLabel: 'follow-ups',
        onTap: open('Overdue follow-ups', 'Follow-up date has passed',
            followUps),
      ),
      AttentionItem(
        icon: Icons.person_search_outlined,
        color: AppColors.error,
        title: 'Owner not met yet',
        subtitle: 'The land owner meeting is still pending',
        count: ownerPending.length,
        clearLabel: 'owner meetings',
        onTap: open('Owner not met yet', 'Land owner meeting pending',
            ownerPending),
      ),
      AttentionItem(
        icon: Icons.location_on_outlined,
        color: AppColors.info,
        title: 'Site visit to plan',
        subtitle: 'Owner met · schedule the site visit',
        count: visitToPlan.length,
        clearLabel: 'site visits',
        onTap: open('Site visit to plan', 'Owner met · site visit next',
            visitToPlan),
      ),
      AttentionItem(
        icon: Icons.handshake_outlined,
        color: AppColors.info,
        title: 'In negotiation',
        subtitle: 'Follow up on terms',
        count: negotiation.length,
        clearLabel: 'negotiation',
        onTap: open('In negotiation', 'Follow up on terms', negotiation),
      ),
      AttentionItem(
        icon: Icons.gavel_rounded,
        color: AppColors.purple,
        title: 'In legal',
        subtitle: 'Waiting on title / legal clearance',
        count: legal.length,
        clearLabel: 'legal',
        onTap: open('In legal', 'Waiting on legal clearance', legal),
      ),
      AttentionItem(
        icon: Icons.event_busy_outlined,
        color: AppColors.warning,
        title: 'No next step planned',
        subtitle: 'No owner meeting planned and none in '
            '${NoFutureActivityAnalytics.staleDays} days',
        count: noNextStep.length,
        clearLabel: 'next steps',
        onTap: open(
            'No next step planned',
            'Active sites with no Land Owner Meeting scheduled and none in '
                'the last ${NoFutureActivityAnalytics.staleDays} days',
            noNextStep),
      ),
    ];
  }

  /// Employee home: Needs attention (left) + Quick actions 2×2 (right) on
  /// wide screens; stacked on narrow phones.
  Widget _employeeTasksAndQuickActions({
    required int approvalCount,
    required List<PortalQuickAction> quickActions,
  }) {
    final todayTasks = PortalSectionCard(
      title: 'Needs attention',
      subtitle: 'Only what has something waiting · tap a line for the sites',
      icon: Icons.flag_outlined,
      child: AttentionList(items: _myAttentionItems(approvalCount)),
    );
    final quick = _quickActionsSection(
      quickActions,
      columns: 2,
      asCard: true,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = FomraLayout.isMobile(context);
        final sideBySide = !isMobile && constraints.maxWidth >= 720;
        if (isMobile) {
          // Quick actions live in the floating button on phones (see the home
          // Scaffold's FAB), so the card is dropped here to reclaim the space.
          return PortalFadeSection(index: 1, child: todayTasks);
        }
        if (!sideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PortalFadeSection(index: 1, child: todayTasks),
              const SizedBox(height: AppSpacing.lg),
              quick,
            ],
          );
        }
        // Top-aligned: the two boxes size to their own content. Equalising
        // their heights isn't safe here — stretch throws in this scrollable
        // (unbounded-height) Row, and IntrinsicHeight throws because Needs
        // attention uses a LayoutBuilder.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: PortalFadeSection(index: 1, child: todayTasks),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: quick),
          ],
        );
      },
    );
  }

  /// Opens the pending approvals list (management) directly — replaces the old
  /// always-visible Approvals dashboard section.
  void _openApprovalsList() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.fomraSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> wrap(Future<void> Function() fn) async {
            await fn();
            setSheet(() {});
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            maxChildSize: 0.95,
            minChildSize: 0.4,
            builder: (ctx, controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.fomraBorder,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                PortalApprovalsSection(
                  visits: _pendingApprovals,
                  signedRequests: _pendingSigned,
                  dropRequests: _pendingDropApprovals,
                  monthlyTargets: _pendingMonthlyTargets,
                  leads: AppStore.instance.leads,
                  loading: _loadingApprovals,
                  onReview: (v) => wrap(() => _reviewPendingVisit(v)),
                  onApprove: (v) => wrap(() => _approvePendingVisit(v)),
                  onReject: (v) => wrap(() => _rejectPendingVisit(v)),
                  onApproveSigned: (r) => wrap(() => _approveSignedRequest(r)),
                  onRejectSigned: (r) => wrap(() => _rejectSignedRequest(r)),
                  onApproveDrop: (r) => wrap(() => _approveDropRequest(r)),
                  onRejectDrop: (r) => wrap(() => _rejectDropRequest(r)),
                  onApproveMonthlyTarget: (s) =>
                      wrap(() => _approveMonthlyTarget(s)),
                  onRejectMonthlyTarget: (s) =>
                      wrap(() => _rejectMonthlyTarget(s)),
                  onEditMonthlyTarget: (s) =>
                      wrap(() => _editMonthlyTarget(s)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];
  static String _monthName(DateTime d) => _months[d.month - 1];

  /// My month: one line when there is no approved target this month (or it
  /// is waiting for approval) instead of a whole empty card.
  Widget? _targetNote() {
    if (!_targetsLoaded) return null;
    final month = _monthName(_clock);
    if (_monthlyTargetPendingApproval) {
      return _NoteLine(
        icon: Icons.hourglass_top_rounded,
        text: 'Your $month targets are waiting for approval.',
      );
    }
    if (_monthlyTargetFromEmployee) return null;
    return _NoteLine(
      icon: Icons.flag_outlined,
      text: 'No target set for $month.',
      action: 'Set my targets',
      onTap: _openMyMonthlyTargets,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final userName = user?.fullName ?? 'User';
    final displayName = portalHomeDisplayName(
      fullName: userName,
      isManagement: _isManagement,
    );
    final greeting = portalTimeGreeting(_clock, displayName);
    final dateLabel = portalHomeDateLabel(_clock);
    final leads = AppStore.instance.leads;
    final summaryLeads = _homeSummaryLeads;
    final totalLeads = summaryLeads.length;
    final ownerMeetingPending = summaryLeads
        .where((l) => l.status == LeadStatus.prospectMeetingPending)
        .length;
    final closedLeads = [
      for (final l in summaryLeads) if (l.status == LeadStatus.signed) l,
    ];
    final closedAcres =
        closedLeads.fold<double>(0, (t, l) => t + biLeadAcres(l));

    final dropApprovalPending = _pendingDropApprovals.length;
    final approvalCount = _pendingApprovals.length +
        _pendingSigned.length +
        dropApprovalPending +
        _pendingMonthlyTargets.length;


    final designation = TeamHierarchy.currentDesignation;
    final canManageTeam = !_isManagement &&
        (designation == EmployeeDesignations.reportingManager ||
            designation == EmployeeDesignations.head);

    final quickActions = [
      if (!_isManagement)
        PortalQuickAction(
          label: 'Add Lead',
          icon: Icons.add_location_alt_outlined,
          accent: AppColors.primary,
          onTap: _openAddLead,
        ),
      if (canManageTeam)
        PortalQuickAction(
          label: 'Manage Team',
          icon: Icons.groups_2_outlined,
          accent: AppColors.purple,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TeamManagementScreen()),
          ),
        ),
      PortalQuickAction(
        label: 'Show All Projects',
        icon: Icons.map_outlined,
        accent: AppColors.info,
        onTap: () => _openAllProjectsMap(leads),
      ),
      PortalQuickAction(
        label: 'Owner Details',
        icon: Icons.person_outline,
        accent: AppColors.success,
        onTap: () => _goTo('/owner-history'),
      ),
      PortalQuickAction(
        label: 'Broker Details',
        icon: Icons.handshake_outlined,
        accent: AppColors.secondary,
        onTap: () => _goTo('/broker-management'),
      ),
    ];

    return FomraAppShell(
      currentRoute: '/home',
      // The notification bell now lives in the shared header for every page.
      appBar: const FomraAppBar(),
      backgroundColor: context.fomraPageBg,
      // On phones the executive's Quick actions card is dropped in favour of a
      // floating button that opens the same actions in a sheet.
      floatingActionButton: (!_isManagement && FomraLayout.isMobile(context))
          ? PortalQuickActionsFab(actions: quickActions)
          : null,
      body: Column(
        children: [
          const OfflineStatusBanner(),
          Expanded(
            child: SingleChildScrollView(
        padding: FomraLayout.pagePadding(context),
        child: portalHomeWidthConstraint(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PortalFadeSection(
                index: 0,
                child: PortalWelcomeHeader(
                  greeting: greeting,
                  dateLabel: dateLabel,
                  totalLeads: totalLeads,
                  activeLeads: _activeLeads,
                  // Management, Reporting Managers and Heads all get an
                  // "Approval Pending" queue — each scoped to what is waiting
                  // on them in the approval chain.
                  thirdLabel: _canApprove
                      ? 'Waiting for your approval'
                      : 'Owner meeting pending',
                  thirdValue:
                      _canApprove ? approvalCount : ownerMeetingPending,
                  thirdIcon: _canApprove
                      ? Icons.approval_outlined
                      : Icons.event_available_outlined,
                  onThirdTap: _canApprove
                      ? _openApprovalsList
                      : () => FilteredLeadsScreen.open(
                          context, LeadListFilter.ownerMeetingPending),
                  // Management: Closed (with acres) and the shortcuts that
                  // used to be the Quick actions card.
                  fourthLabel: _isManagement
                      ? 'Closed · ${closedAcres.toStringAsFixed(1)} ac'
                      : null,
                  fourthValue: closedLeads.length,
                  fourthIcon: Icons.verified_outlined,
                  onFourthTap: () =>
                      FilteredLeadsScreen.open(context, LeadListFilter.signed),
                  actions: _isManagement
                      ? [
                          PortalHeroAction(
                              label: 'Add lead',
                              icon: Icons.add_location_alt_outlined,
                              onTap: _openAddLead),
                          PortalHeroAction(
                              label: 'All properties',
                              icon: Icons.map_outlined,
                              onTap: () => _openAllProjectsMap(leads)),
                          PortalHeroAction(
                              label: 'Owners',
                              icon: Icons.person_outline,
                              onTap: () => _goTo('/owner-history')),
                          PortalHeroAction(
                              label: 'Brokers',
                              icon: Icons.handshake_outlined,
                              onTap: () => _goTo('/broker-management')),
                        ]
                      : const [],
                  onSummaryTap: (filter) {
                    // "Total sites" opens the full Land Workspace directly;
                    // the other tiles open their filtered list.
                    if (filter == LeadListFilter.totalLeads) {
                      _goTo('/land-lead');
                    } else {
                      FilteredLeadsScreen.open(context, filter);
                    }
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_isManagement) ...[
                const _HomeGroupLabel(number: 1, text: 'Act on these'),
                PortalFadeSection(
                  index: 1,
                  child: PortalSectionCard(
                    title: 'Needs attention',
                    subtitle: 'Tap a line to open those sites',
                    icon: Icons.flag_outlined,
                    child: NeedsAttentionCard(
                      leads: _homeSummaryLeads,
                      approvalCount: approvalCount,
                      onOpenApprovals: _openApprovalsList,
                      noNextStep: _noFutureActivityLeads,
                      noNextStepDays: NoFutureActivityAnalytics.staleDays,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const _HomeGroupLabel(number: 2, text: 'People'),
              ] else ...[
                // Executives / managers: what is waiting on them, next to
                // Quick actions on wide screens.
                _employeeTasksAndQuickActions(
                  approvalCount: approvalCount,
                  quickActions: quickActions,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              // Team Performance: site visits today / week / month and
              // meetings against the month's target, ranked; tap a name for
              // the pipeline. Management and managers see each executive in
              // their scope; an executive sees their own row ("My month",
              // which also carries their target status and broker targets).
              PortalFadeSection(
                index: 1,
                child: PortalSectionCard(
                  title: _canApprove
                      ? 'Team this month'
                      : 'My month · ${_monthName(_clock)}',
                  subtitle: _canApprove
                      ? 'Site visits & meetings against target · tap a '
                          'name for the pipeline and site age'
                      : 'Against your approved target · tap a number for '
                          'the sites',
                  icon: Icons.emoji_events_outlined,
                  child: TeamPerformanceCard(
                    leads: _homeSummaryLeads,
                    onlyExecutive: _canApprove
                        ? null
                        : AuthService.instance.currentUser?.fullName,
                    extraLines: _isManagement
                        ? const []
                        : [
                            for (final (label, p) in _extraTargets)
                              (label, TargetLine(p, const [])),
                          ],
                    note: _isManagement ? null : _targetNote(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Reviewers (Management, Reporting Manager, Head) see what needs
              // reviewing; each tile opens that list.
              if (_canApprove && !_isManagement) ...[
                PortalFadeSection(
                  index: 1,
                  child: PortalSectionCard(
                    title: 'Property Reviews',
                    subtitle: 'Active properties by review status · '
                        'tap a box to open the list',
                    icon: Icons.fact_check_outlined,
                    child: PropertyReviewSummary(leads: _homeSummaryLeads),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (_isManagement) ...[
                PortalFadeSection(
                  index: 2,
                  child: PortalSectionCard(
                    title: 'Brokers · last 120 days',
                    subtitle: 'Energiser = land owner met on over 60% of '
                        'their lands · Low Yield = under 40% · tap a group',
                    icon: Icons.handshake_outlined,
                    child: BrokerEnergySummary(leads: leads),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const _HomeGroupLabel(number: 3, text: 'Properties'),
                PortalFadeSection(
                  index: 3,
                  child: PortalSectionCard(
                    title: 'Property pipeline',
                    subtitle: 'Where every site stands · tap a stage for '
                        'the list',
                    icon: Icons.account_tree_outlined,
                    child: PropertyPipelineCard(leads: _homeSummaryLeads),
                  ),
                ),
              ],
              const SizedBox(height: 88),
            ],
          ),
        ),
      ),
          ),
        ],
      ),
    );
  }
}

/// A one-line note with an optional link, e.g. "No target set for
/// November · Set my targets ›".
class _NoteLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onTap;

  const _NoteLine({
    required this.icon,
    required this.text,
    this.action,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: context.fomraSurfaceVar,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(icon, size: 18, color: context.fomraTextSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.fomraTextSecondary,
                    )),
              ),
              if (action != null)
                Text('$action ›',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    )),
            ]),
          ),
        ),
      );
}

class _HomeGroupLabel extends StatelessWidget {
  final int number;
  final String text;
  const _HomeGroupLabel({required this.number, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Row(children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Text('$number',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.gold,
                )),
          ),
          const SizedBox(width: 8),
          Text(text.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: context.fomraTextSecondary,
              )),
        ]),
      );
}
