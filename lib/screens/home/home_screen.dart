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
import '../land_lead/lead_detail_screen.dart';
import '../land_lead/leads_map_screen.dart';
import '../land_lead/management_visit_review_dialog.dart';
import '../../services/approval_chain.dart';
import '../../services/auth_service.dart';
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
import '../../models/app_notification.dart';
import '../../models/land_lead_signed_request.dart';
import '../../models/land_lead_site_visit.dart';
import '../settings/employee_monthly_targets_page.dart';
import '../settings/monthly_target_approvals_page.dart';
import '../../widgets/fomra_app_bar.dart';
import '../../widgets/fomra_app_shell.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/management_executive_dashboard.dart';
import '../../widgets/offline_status_banner.dart';
import '../../widgets/monthly_target_progress_card.dart';
import '../../widgets/portal_home_sections.dart';
import '../../widgets/ui/app_components.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  DateTime _clock = DateTime.now();

  /// Read-only view of the shared notification state the header bell owns —
  /// the management dashboard renders the same list the bell does.
  List<AppNotification> get _notifications =>
      NotificationHub.instance.notifications;

  List<LandLeadSiteVisit> _pendingApprovals = [];
  List<LandLeadSignedRequest> _pendingSigned = [];
  List<LeadDropApprovalRequest> _pendingDropApprovals = [];
  List<MonthlyTargetSubmission> _pendingMonthlyTargets = [];
  bool _loadingApprovals = false;

  /// Meeting history behind the management "No Future Activity" quick action.
  List<LandLeadMeeting> _meetings = const [];

  /// This employee's progress against their monthly target. Null until the
  /// first load lands; management never loads it.
  MonthlyTargetProgress? _monthlyProgress;

  /// The resolved target number (from an approved employee submission when
  /// present, otherwise the management-set common/personal target). Cached so
  /// progress can be recomputed locally from visibleLeads without re-fetching.
  int _monthlyTargetCount = 0;

  /// True when the resolved target came from the employee's own approved
  /// submission rather than a management-set row.
  bool _monthlyTargetFromEmployee = false;

  /// True when the employee has submitted this month but it is still pending
  /// approval (so the card can explain why no target is active yet).
  bool _monthlyTargetPendingApproval = false;

  /// Approved per-category targets (leads / site_visits / meetings) when the
  /// active target is the employee's own approved submission — drives the
  /// per-category boxes and lines on the progress card.
  Map<String, int> _approvedTargetValues = const {};
  List<LandLeadMeeting> _targetMeetings = const [];
  List<LeadFollowUp> _overdueFollowUps = const [];
  List<LandLeadSiteVisit> _targetSiteVisits = const [];
  List<MonthlyTargetCategoryProgress> _monthlyCategories = const [];

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

  /// Loads the meeting + employee site-visit history that feeds the per-category
  /// progress boxes/lines. Bulk reads, scoped to the executive's visible leads
  /// at compute time. Best-effort — an empty result just shows zero achieved.
  Future<void> _loadTargetActivity() async {
    final results = await Future.wait([
      ManagementBiActivityService.loadMeetings(),
      ManagementBiActivityService.loadSiteVisits(),
    ]);
    if (!mounted) return;
    _targetMeetings = results[0] as List<LandLeadMeeting>;
    _targetSiteVisits = results[1] as List<LandLeadSiteVisit>;
    _recomputeMonthlyProgress();
  }

  /// Recompute the card from the cached target and the CURRENT visibleLeads —
  /// cheap and local, so it can run on every store/scope change.
  ///
  /// Achieved = sites SOURCED (leads added) this month in the current scope.
  /// visibleLeads is the single scoping rule (role + Team/Individual toggle), so
  /// a manager in Team view gets the whole team's sites and an executive gets
  /// their own. Each lead counts on the day it was added; forMonth keeps only
  /// the ones added this month.
  void _recomputeMonthlyProgress() {
    if (_isManagement) return;
    final now = DateTime.now();
    final visible = AppStore.instance.visibleLeads;
    final visibleIds = {for (final l in visible) l.leadId};
    final leadDates = [for (final l in visible) l.addedOn];

    final overall = MonthlyTargetProgress.forMonth(
      target: _monthlyTargetCount,
      now: now,
      completedOn: leadDates,
    );

    // Per-category boxes/lines only when the target is the employee's approved
    // submission. New Brokers / Broker Meetings only appear when the
    // executive actually targeted them — they're optional, so an untouched
    // category shouldn't clutter the card with a permanent "0/0".
    var categories = const <MonthlyTargetCategoryProgress>[];
    final tv = _approvedTargetValues;
    if (_monthlyTargetFromEmployee && tv.isNotEmpty) {
      final visitDates = [
        for (final v in _targetSiteVisits)
          if (v.visitType == LandLeadSiteVisitType.employee &&
              visibleIds.contains(v.leadId))
            v.visitedAt,
      ];
      // Self vs Management Meetings is a real distinction, not a relabeling —
      // it's exactly what land_lead_meetings.management_present already
      // records (see meeting_log_dialog.dart's "Management present" toggle).
      final selfMeetingDates = [
        for (final m in _targetMeetings)
          if (visibleIds.contains(m.leadId) && !m.managementPresent) m.metAt,
      ];
      final managementMeetingDates = [
        for (final m in _targetMeetings)
          if (visibleIds.contains(m.leadId) && m.managementPresent) m.metAt,
      ];
      categories = [
        MonthlyTargetCategoryProgress(
          label: 'Site Visits',
          color: AppColors.primary,
          progress: MonthlyTargetProgress.forMonth(
              target: tv[TargetCategory.siteVisits.key] ?? 0,
              now: now,
              completedOn: visitDates),
        ),
        MonthlyTargetCategoryProgress(
          label: 'Self Meetings',
          color: AppColors.success,
          progress: MonthlyTargetProgress.forMonth(
              target: tv[TargetCategory.selfMeetings.key] ?? 0,
              now: now,
              completedOn: selfMeetingDates),
        ),
        MonthlyTargetCategoryProgress(
          label: 'Management Meetings',
          color: AppColors.warning,
          progress: MonthlyTargetProgress.forMonth(
              target: tv[TargetCategory.managementMeetings.key] ?? 0,
              now: now,
              completedOn: managementMeetingDates),
        ),
        if (tv.containsKey(TargetCategory.brokerMeetings.key))
          MonthlyTargetCategoryProgress(
            label: 'Broker Meetings',
            color: AppColors.purple,
            progress: MonthlyTargetProgress.forMonth(
              target: tv[TargetCategory.brokerMeetings.key] ?? 0,
              now: now,
              completedOn: [
                for (final m in _targetMeetings)
                  if (visibleIds.contains(m.leadId) &&
                      m.attendeeTypes.contains(MeetingAttendeeTypes.broker))
                    m.metAt,
              ],
            ),
          ),
        if (tv.containsKey(TargetCategory.newBrokers.key))
          MonthlyTargetCategoryProgress(
            label: 'New Brokers',
            color: AppColors.cyan,
            progress: MonthlyTargetProgress.forMonth(
              target: tv[TargetCategory.newBrokers.key] ?? 0,
              now: now,
              // A broker counts as "new" the first time their name appears
              // on one of this executive's leads — i.e. never seen on any
              // lead added before that one.
              completedOn: _newBrokerDatesThisMonth(visible, now),
            ),
          ),
      ];
    }

    setState(() {
      _monthlyProgress = overall;
      _monthlyCategories = categories;
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
      final broker = l.brokerName.trim().toLowerCase();
      if (broker.isEmpty) continue;
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

  int get _myLeadCount => _myLeads.length;

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
    if (!_isManagement && _monthlyProgress != null) {
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

  /// Employee home: Today's tasks (left) + Quick actions 2×2 (right) on wide
  /// screens; stacked on narrow phones.
  Widget _employeeTasksAndQuickActions({
    required String employeeName,
    required List<PortalQuickAction> quickActions,
  }) {
    final todayTasks = _EmployeeTodayTasksSection(
      employeeName: employeeName,
      overdueFollowUpLeads: _leadsFor(_overdueFollowUps),
      staleLeads: _noFutureActivityLeads,
      onOpenLead: (lead) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => LeadDetailScreen(lead: lead)),
        );
      },
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
        // (unbounded-height) Row, and IntrinsicHeight throws because Today's
        // tasks uses a LayoutBuilder.
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
    final teamRows = buildPortalTeamPerformance(leads);

    final dropApprovalPending = _pendingDropApprovals.length;
    final approvalCount = _pendingApprovals.length +
        _pendingSigned.length +
        dropApprovalPending +
        _pendingMonthlyTargets.length;

    final pendingApprovalItems = <PendingApprovalItem>[
      for (final v in _pendingApprovals)
        PendingApprovalItem(
          leadId: v.leadId,
          label: 'Management site visit',
          since: v.visitedAt,
        ),
      for (final s in _pendingSigned)
        PendingApprovalItem(
          leadId: s.leadId,
          label: 'Project Signed',
          since: s.createdAt,
        ),
      for (final d in _pendingDropApprovals)
        PendingApprovalItem(
          leadId: d.leadId,
          label: 'Drop request',
          since: d.createdAt,
        ),
      for (final t in _pendingMonthlyTargets)
        PendingApprovalItem(
          leadId: t.id,
          label: 'Monthly Target Approval',
          since: t.submittedAt,
        ),
    ];

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
      if (_isManagement)
        PortalQuickAction(
          label: 'No Future Activity',
          subtitle: '${_noFutureActivityLeads.length} '
              'site${_noFutureActivityLeads.length == 1 ? '' : 's'} · no meeting '
              '${NoFutureActivityAnalytics.staleDays}+ days',
          icon: Icons.event_busy_outlined,
          accent: AppColors.error,
          onTap: () => FilteredLeadsScreen.openList(
            context,
            title: 'No Future Activity',
            subtitle:
                'Active sites with no Land Owner Meeting scheduled and none in '
                'the last ${NoFutureActivityAnalytics.staleDays} days',
            leads: _noFutureActivityLeads,
          ),
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
                  thirdLabel:
                      _canApprove ? 'Approval Pending' : 'Owner meeting pending',
                  thirdValue:
                      _canApprove ? approvalCount : ownerMeetingPending,
                  thirdIcon: _canApprove
                      ? Icons.approval_outlined
                      : Icons.event_available_outlined,
                  onThirdTap: _canApprove
                      ? _openApprovalsList
                      : () => FilteredLeadsScreen.open(
                          context, LeadListFilter.ownerMeetingPending),
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
                _quickActionsSection(quickActions),
                const SizedBox(height: AppSpacing.lg),
                PortalFadeSection(
                  index: 2,
                  child: ManagementExecutiveDashboard(
                    leads: leads,
                    teamRows: teamRows,
                    notifications: _notifications,
                    pendingApprovals: pendingApprovalItems,
                    widgetIds: const [
                      'pipelineDeals',
                      'leaderboard',
                      'monthlyTargets',
                      'pendingWorkflow',
                    ],
                    onViewLead: (lead) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LeadDetailScreen(lead: lead),
                        ),
                      );
                    },
                  ),
                ),
              ] else ...[
                // Employee: Today's tasks (left) + Quick actions 2×2 (right).
                _employeeTasksAndQuickActions(
                  employeeName: userName,
                  quickActions: quickActions,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_monthlyProgress != null) ...[
                  PortalFadeSection(
                    index: 2,
                    child: PortalSectionCard(
                      title: 'Monthly Target Progress',
                      subtitle: canManageTeam && ViewScope.instance.isTeam
                          ? "Your team's sites this month against the target"
                          : (_monthlyTargetFromEmployee
                              ? 'Your approved targets · sites this month'
                              : 'Your sites this month against the target'),
                      icon: Icons.flag_outlined,
                      child: MonthlyTargetProgressCard(
                        progress: _monthlyProgress!,
                        month: DateTime.now(),
                        pendingApproval: _monthlyTargetPendingApproval,
                        onSetTarget: _openMyMonthlyTargets,
                        categories: _monthlyCategories,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                PortalFadeSection(
                  index: 3,
                  child: PortalSectionCard(
                    title: canManageTeam ? 'Performance' : 'My performance',
                    subtitle: canManageTeam
                        ? 'Use the Team / Individual switch in the header to '
                            'change what this covers'
                        : 'Your site contribution this period',
                    icon: Icons.groups_rounded,
                    child: _RolePerformanceCard(
                      isTeamLead: canManageTeam,
                      count: _myLeadCount,
                      onTap: () => _goTo('/land-lead'),
                    ),
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

/// Sites added, for whatever the header's Team / Individual toggle currently
/// covers — [count] is already scoped by [LeadVisibility], so this only picks
/// the wording.
class _RolePerformanceCard extends StatelessWidget {
  final bool isTeamLead;
  final int count;
  final VoidCallback? onTap;

  const _RolePerformanceCard({
    required this.isTeamLead,
    required this.count,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final showTeam = isTeamLead && ViewScope.instance.isTeam;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      radius: AppColors.radiusMd,
      interactive: onTap != null,
      onTap: onTap,
      child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.emoji_events_outlined,
                  size: 17,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showTeam ? 'Team Sites Added' : 'Sites Added',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      showTeam
                          ? "Your team's total contribution to the pipeline"
                          : 'Your total contribution to the pipeline',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: context.fomraTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedCounter(
                value: count,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      fontSize: 18,
                    ),
              ),
            ],
      ),
    );
  }
}

class _EmployeeTodayTasksSection extends StatelessWidget {
  final String employeeName;
  final ValueChanged<LandLead> onOpenLead;
  final List<LandLead> overdueFollowUpLeads;
  final List<LandLead> staleLeads;

  const _EmployeeTodayTasksSection({
    required this.employeeName,
    required this.onOpenLead,
    this.overdueFollowUpLeads = const [],
    this.staleLeads = const [],
  });

  List<LandLead> get _myActiveLeads => AppStore.instance.leads
      .where((l) =>
          l.createdByName.trim() == employeeName.trim() && l.status.isActive)
      .toList();

  void _openCategory(
    BuildContext context,
    String title,
    Color color,
    List<LandLead> leads,
  ) {
    if (leads.isEmpty) return;
    FilteredLeadsScreen.openList(
      context,
      title: title,
      subtitle: '$title follow-up queue',
      leads: leads,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mine = _myActiveLeads;
    final categories = <
        ({String label, IconData icon, Color color, List<LandLead> leads})>[
      if (overdueFollowUpLeads.isNotEmpty)
        (
          label: 'Overdue Follow-ups',
          icon: Icons.notifications_active_outlined,
          color: AppColors.error,
          leads: overdueFollowUpLeads,
        ),
      if (staleLeads.isNotEmpty)
        (
          label: 'No Recent Activity',
          icon: Icons.event_busy_outlined,
          color: AppColors.warning,
          leads: staleLeads,
        ),
      (
        label: 'Call Pending',
        icon: Icons.call_outlined,
        color: AppColors.info,
        leads: mine
            .where((l) => l.status == LeadStatus.negotiation)
            .toList(),
      ),
      (
        label: 'Meeting Pending',
        icon: Icons.groups_outlined,
        color: LeadStatus.prospectMeetingPending.color,
        leads: mine
            .where((l) => l.status == LeadStatus.prospectMeetingPending)
            .toList(),
      ),
      (
        label: 'Site Visit Pending',
        icon: Icons.location_on_outlined,
        color: LeadStatus.prospectMeetingCompleted.color,
        leads: mine
            .where((l) => l.status == LeadStatus.prospectMeetingCompleted)
            .toList(),
      ),
      (
        label: 'Legal Pending',
        icon: Icons.gavel_outlined,
        color: LeadStatus.legal.color,
        leads: mine.where((l) => l.status == LeadStatus.legal).toList(),
      ),
    ];
    final total = categories.fold<int>(0, (s, c) => s + c.leads.length);

    return PortalSectionCard(
      title: "Today's tasks",
      subtitle: 'Compact follow-up cards',
      icon: Icons.today_rounded,
      child: total == 0
          ? const EmptyState(
              icon: Icons.task_alt_outlined,
              title: 'No pending tasks',
              message:
                  'Active leads you add will show pending follow-ups here.',
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                // Mobile: a 2×2 grid of square tiles. Wider screens keep the
                // 2-up row cards (single column only when truly narrow).
                final mobile = FomraLayout.isMobile(context);
                // Match the Quick actions 2-col grid (gap 12, card height 100)
                // exactly, so the two side-by-side boxes end at the same height
                // without stretch/IntrinsicHeight (both crash with this Wrap).
                const gap = 12.0;
                final twoCols = mobile || constraints.maxWidth >= 360;
                final cardWidth = twoCols
                    ? (constraints.maxWidth - gap) / 2
                    : constraints.maxWidth;
                // The Quick actions grid wraps its cards in vertical:4 padding —
                // match it so the two side-by-side boxes are exactly equal.
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final c in categories)
                      SizedBox(
                        width: cardWidth,
                        height: mobile ? cardWidth : 100,
                        child: _TaskSummaryCard(
                          label: c.label,
                          count: c.leads.length,
                          icon: c.icon,
                          color: c.color,
                          subtitle: switch (c.label) {
                            'Call Pending' => 'Follow up by call',
                            'Meeting Pending' => 'Land owner meeting due',
                            'Site Visit Pending' => 'Schedule the site visit',
                            _ => 'Legal verification pending',
                          },
                          onTap: c.leads.isEmpty
                              ? null
                              : () => _openCategory(context, c.label, c.color, c.leads),
                        ),
                      ),
                  ],
                  ),
                );
              },
            ),
    );
  }
}

class _TaskSummaryCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _TaskSummaryCard({
    required this.label,
    required this.subtitle,
    required this.count,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      radius: AppColors.radiusMd,
      interactive: onTap != null,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: context.fomraTextPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(subtitle,
              style: TextStyle(fontSize: 10.5, color: context.fomraTextSecondary)),
        ],
      ),
    );
  }
}
