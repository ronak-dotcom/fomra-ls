import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../analytics/management_bi_metrics.dart';
import '../analytics/management_intelligence.dart';
import '../analytics/monthly_target_progress.dart';
import '../models/app_notification.dart';
import '../models/land_lead.dart';
import '../models/land_lead_meeting.dart';
import '../models/land_lead_site_visit.dart';
import '../models/monthly_target_submission.dart';
import '../screens/land_lead/filtered_leads_screen.dart';
import '../services/app_store.dart';
import '../services/dashboard_layout_prefs.dart';
import '../services/management_bi_activity_service.dart';
import '../services/monthly_target_submission_service.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';
import '../utils/lead_location_parser.dart';
import 'management_bi_sections.dart';
import 'management_intelligence_sections.dart';
import 'portal_home_sections.dart';
import 'terms_deal_selector.dart';
import 'ui/app_components.dart';
import 'ui/profile_avatar.dart';

const _kCardRadius = 20.0;
const _kFocusDistricts = [
  'Chennai',
  'Kanchipuram',
  'Chengalpattu',
  'Thiruvallur',
];

// The named deal terms shown in the donut. Leads whose term doesn't match one
// of these fall into the 'Others' bucket, which is intentionally NOT charted —
// see _dealTermsDistribution.
const _kDealCategories = [
  'Outright Purchase',
  'Joint Venture',
  'Marketing',
  'Deferred Payment',
];

// ── Date / KPI helpers (from dashboard_screen patterns) ─────────────────────

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _isSameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

int _countLeadsBetween(List<LandLead> leads, DateTime start, DateTime end) {
  final s = _dayOnly(start);
  final e = _dayOnly(end);
  return leads.where((l) {
    final d = _dayOnly(l.addedOn);
    return !d.isBefore(s) && !d.isAfter(e);
  }).length;
}

(int current, int previous) _weekOverWeekCounts(List<LandLead> leads) {
  final today = _dayOnly(DateTime.now());
  final thisWeekStart = today.subtract(const Duration(days: 6));
  final lastWeekEnd = today.subtract(const Duration(days: 7));
  final lastWeekStart = today.subtract(const Duration(days: 13));
  final current = _countLeadsBetween(leads, thisWeekStart, today);
  final previous = _countLeadsBetween(leads, lastWeekStart, lastWeekEnd);
  return (current, previous);
}

List<LandLead> _leadsWithStatus(List<LandLead> leads, LeadStatus status) =>
    leads.where((l) => l.status == status).toList();

List<LandLead> _signedLeads(List<LandLead> leads) =>
    leads.where((l) => l.status == LeadStatus.signed).toList();

double _acresFromSqft(double sqft) => sqft / 43560;

double _leadAcres(LandLead lead) {
  final sqft = parseLandExtentSqft(lead.landExtent);
  if (sqft == null) return 0;
  return _acresFromSqft(sqft);
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
  if (diff.inHours < 24) return '${diff.inHours} hours ago';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return '${time.day}/${time.month}/${time.year}';
}

String _dealCategory(String? primary) {
  if (primary == null || primary.trim().isEmpty) return 'Others';
  final p = primary.trim();
  for (final c in _kDealCategories) {
    if (c == 'Others') continue;
    if (p.toLowerCase() == c.toLowerCase()) return c;
  }
  return 'Others';
}

Map<String, int> _dealTermsDistribution(List<LandLead> leads) {
  final counts = {for (final c in _kDealCategories) c: 0};
  for (final lead in leads) {
    final parsed = parseTermsDeal(lead.accessDetails);
    final cat = _dealCategory(parsed.primary);
    // 'Others' is not charted, so those leads are left out of the totals — the
    // percentages read against the named deal terms only.
    if (!counts.containsKey(cat)) continue;
    counts[cat] = counts[cat]! + 1;
  }
  return counts;
}

List<LandLead> _leadsWithDealTerm(List<LandLead> leads, String category) => leads
    .where((l) => _dealCategory(parseTermsDeal(l.accessDetails).primary) ==
        category)
    .toList();

/// Open a full-screen list of the leads behind a dashboard box / chart slice.
void _openLeadsList(
  BuildContext context,
  String title,
  String subtitle,
  List<LandLead> leads,
) {
  FilteredLeadsScreen.openList(
    context,
    title: title,
    subtitle: subtitle,
    leads: leads,
  );
}

({int signed, int negotiation, int legal, int total, double acres})
    _employeeMetrics(
  String name,
  List<LandLead> leads,
) {
  final mine = leads
      .where((l) =>
          l.createdByName.trim().toLowerCase() == name.trim().toLowerCase())
      .toList();
  final signed = mine.where((l) => l.status == LeadStatus.signed).length;
  final negotiation =
      mine.where((l) => l.status == LeadStatus.negotiation).length;
  final legal = mine.where((l) => l.status == LeadStatus.legal).length;
  final acres = mine
      .where((l) => l.status == LeadStatus.signed)
      .fold<double>(0, (sum, l) => sum + _leadAcres(l));
  return (
    signed: signed,
    negotiation: negotiation,
    legal: legal,
    total: mine.length,
    acres: acres,
  );
}

double _conversionPercent(int signed, int total) =>
    total == 0 ? 0 : (signed / total) * 100;

/// A pending management-approval entry (signed / drop / management visit)
/// surfaced in the pending-workflow dashboard.
class PendingApprovalItem {
  final String leadId;
  final String label;
  final DateTime since;

  const PendingApprovalItem({
    required this.leadId,
    required this.label,
    required this.since,
  });
}

// ── Main widget ─────────────────────────────────────────────────────────────

class ManagementExecutiveDashboard extends StatefulWidget {
  final List<LandLead> leads;
  final List<PortalTeamPerf> teamRows;
  final List<AppNotification> notifications;
  final ValueChanged<LandLead>? onViewLead;

  /// Pending management approvals (signed / drop / visit requests) — feeds the
  /// "Management Approval Pending" card in the pending-workflow dashboard.
  final List<PendingApprovalItem> pendingApprovals;

  /// When provided, renders exactly these widgets in this order as a fixed
  /// (non-customizable) layout — no toolbar or executive KPI strip. Used to
  /// surface a specific subset of BI widgets on another screen (e.g. Dashboard).
  final List<String>? widgetIds;

  const ManagementExecutiveDashboard({
    super.key,
    required this.leads,
    required this.teamRows,
    required this.notifications,
    this.onViewLead,
    this.pendingApprovals = const [],
    this.widgetIds,
  });

  @override
  State<ManagementExecutiveDashboard> createState() =>
      _ManagementExecutiveDashboardState();
}

class _ManagementExecutiveDashboardState
    extends State<ManagementExecutiveDashboard> {
  ManagementBiActivityBundle _activity = ManagementBiActivityBundle.empty;
  List<String> _order = List.of(DashboardLayoutPrefs.defaultOrder);
  bool _loadingActivity = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant ManagementExecutiveDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leads.length != widget.leads.length) {
      // Refresh activity when lead set changes materially.
      _loadActivity();
    }
  }

  Future<void> _bootstrap() async {
    final order = await DashboardLayoutPrefs.loadOrder();
    if (mounted) setState(() => _order = order);
    await _loadActivity();
  }

  Future<void> _loadActivity() async {
    setState(() => _loadingActivity = true);
    final bundle = await ManagementBiActivityService.loadAll();
    if (!mounted) return;
    setState(() {
      _activity = bundle;
      _loadingActivity = false;
    });
  }

  Widget _buildWidget(
    String id,
    ManagementBiSnapshot snap,
    ManagementIntelligenceSnapshot intel,
    bool isDesktop,
  ) {
    switch (id) {
      case 'pipeline':
        return BiPipelineSection(
          summary: snap.pipeline,
          leads: widget.leads,
        );
      case 'pipelineDeals':
        return LayoutBuilder(
          builder: (context, c) {
            final pipeline = BiPipelineSection(
              summary: snap.pipeline,
              leads: widget.leads,
            );
            final donut = _DealTermsDonutCard(leads: widget.leads);
            // Lead Ageing fills the empty space beside the Deal Terms donut so
            // the dashboard's top section stays balanced.
            final ageing = BiAgeingSection(
              rows: snap.ageing,
              onViewLead: widget.onViewLead,
            );
            final pendingStages = _PendingStagesCard(leads: widget.leads);
            if (c.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  pipeline,
                  const SizedBox(height: AppSpacing.lg),
                  donut,
                  const SizedBox(height: AppSpacing.lg),
                  pendingStages,
                  const SizedBox(height: AppSpacing.lg),
                  ageing,
                ],
              );
            }
            // Both columns start on the same line and each card is exactly as
            // wide as the one above it (7:3 of the row, minus one 24px gutter).
            //
            // The two columns are levelled to a shared height so the section
            // reads as a clean rectangle. IntrinsicHeight can't do it — Pipeline
            // Dashboard and Site Ageing build through a LayoutBuilder, which
            // refuses intrinsics (see dashboard_grid_alignment_test) — so
            // _LeveledPipelineColumns measures the columns' natural heights
            // after layout and grows Pipeline + Site Ageing by an equal amount
            // to meet the taller (right) column's bottom.
            return _LeveledPipelineColumns(
              pipeline: pipeline,
              ageing: ageing,
              donut: donut,
              pendingStages: pendingStages,
              // Re-measure when the width or the lead set changes.
              signature: '${c.maxWidth.round()}|${widget.leads.length}',
            );
          },
        );
      case 'monthlyTargets':
        return _TeamMonthlyTargetsCard(
          leads: widget.leads,
          meetings: _activity.meetings,
          siteVisits: _activity.siteVisits,
        );
      case 'reminders':
        return IntelRemindersSection(
          items: intel.reminders,
          onViewLead: widget.onViewLead,
        );
      case 'escalations':
        return IntelEscalationsSection(
          items: intel.escalations,
          onViewLead: widget.onViewLead,
        );
      case 'approvals':
        return IntelApprovalQueueSection(
          items: intel.approvalQueue,
          onViewLead: widget.onViewLead,
        );
      case 'recommendations':
        return IntelSuggestionsSection(
          recommendations: intel.recommendations,
          onViewLead: widget.onViewLead,
        );
      case 'predictive':
        return IntelPredictiveSection(data: intel.predictive);
      case 'duplicates':
        return IntelDuplicatesSection(
          groups: intel.duplicates,
          onViewLead: widget.onViewLead,
        );
      case 'funnel':
        return BiFunnelSection(rows: snap.funnel);
      case 'ageing':
        return BiAgeingSection(
          rows: snap.ageing,
          onViewLead: widget.onViewLead,
        );
      case 'bottlenecks':
        return BiBottleneckSection(rows: snap.bottlenecks);
      case 'pendingWorkflow':
        return _PendingWorkflowDashboard(
          leads: widget.leads,
          approvals: widget.pendingApprovals,
          onViewLead: widget.onViewLead,
        );
      case 'sla':
        return BiSlaSection(
          summary: snap.sla,
          onViewLead: widget.onViewLead,
        );
      case 'executives':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BiExecutiveSection(rows: snap.executives),
            const SizedBox(height: AppSpacing.md),
            _EmployeeLeaderboardCard(
              teamRows: widget.teamRows,
              leads: widget.leads,
            ),
          ],
        );
      case 'executivesTable':
        return BiExecutiveSection(rows: snap.executives);
      case 'leaderboard':
        return _EmployeeLeaderboardCard(
          teamRows: widget.teamRows,
          leads: widget.leads,
        );
      case 'heatmap':
        return BiHeatmapSection(rows: snap.heatmap);
      case 'district':
        return DistrictPerformanceCard(leads: widget.leads);
      case 'dealTerms':
        return _DealTermsDonutCard(leads: widget.leads);
      case 'activities':
        return _RecentActivitiesCard(notifications: widget.notifications);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.leads.isEmpty) {
      return const _DashboardCard(
        child: Column(
          children: [
            EmptyState(
              icon: Icons.analytics_outlined,
              title: 'No pipeline data yet',
              message:
                  'Leads added by your team will populate this executive dashboard automatically.',
            ),
            PortalEmptyHint(
              hint: 'Add leads or view the leads list to get started.',
            ),
          ],
        ),
      );
    }

    final snap = ManagementBiMetrics.build(
      leads: widget.leads,
      activity: _activity,
    );
    final intel = ManagementIntelligence.build(
      leads: widget.leads,
      activity: _activity,
    );
    const gap = AppSpacing.md;
    final isDesktop = MediaQuery.sizeOf(context).width >= 1024;

    // Fixed subset layout (e.g. widgets relocated to the Dashboard screen):
    // no toolbar, no KPI strip, no customize — just the requested widgets.
    final fixed = widget.widgetIds;
    if (fixed != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < fixed.length; i++) ...[
            if (i > 0) const SizedBox(height: gap),
            _buildWidget(fixed[i], snap, intel, isDesktop),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BiToolbar(
          loading: _loadingActivity,
        ),
        const SizedBox(height: gap),
        // Keep classic KPI strip as a fixed executive snapshot.
        _ExecutiveTopRow(
          leads: widget.leads,
          isDesktop: isDesktop,
          isTablet: MediaQuery.sizeOf(context).width >= 640,
        ),
        const SizedBox(height: gap),
        for (var i = 0; i < _order.length; i++) ...[
          if (i > 0) const SizedBox(height: gap),
          _buildWidget(_order[i], snap, intel, isDesktop),
        ],
      ],
    );
  }
}

class _BiToolbar extends StatelessWidget {
  final bool loading;

  const _BiToolbar({
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Business Intelligence',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: context.fomraTextPrimary,
          ),
        ),
        if (loading) ...[
          const SizedBox(width: 10),
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ],
    );
  }
}

// ── Shared card shell ───────────────────────────────────────────────────────

class _DashboardCard extends StatelessWidget {
  final Widget child;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Color? borderColor;

  /// When set, the whole card becomes clickable — AppCard supplies the hover
  /// lift and pointer cursor for free.
  final VoidCallback? onTap;

  const _DashboardCard({
    required this.child,
    this.title,
    this.subtitle,
    this.icon,
    this.onTap,
  }) : borderColor = null;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      radius: _kCardRadius,
      onTap: onTap,
      interactive: onTap != null,
      borderColor: borderColor,
      borderWidth: borderColor != null ? 1.5 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null && icon != null) ...[
            SectionHeader(
              title: title!,
              subtitle: subtitle,
              icon: icon!,
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
            ),
          ],
          child,
        ],
      ),
    );
  }
}

// ── Row 1: KPIs left, deal terms right ────────────────────────────────────────

class _ExecutiveTopRow extends StatelessWidget {
  final List<LandLead> leads;
  final bool isDesktop;
  final bool isTablet;

  const _ExecutiveTopRow({
    required this.leads,
    required this.isDesktop,
    required this.isTablet,
  });

  @override
  Widget build(BuildContext context) {
    const gap = AppSpacing.md;

    if (!isTablet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeroKpiStrip(
            leads: leads,
            isDesktop: isDesktop,
            isTablet: isTablet,
            inRow: false,
          ),
          const SizedBox(height: gap),
          _DealTermsDonutCard(leads: leads),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: isDesktop ? 6 : 5,
          child: _HeroKpiStrip(
            leads: leads,
            isDesktop: isDesktop,
            isTablet: isTablet,
            inRow: true,
          ),
        ),
        const SizedBox(width: gap),
        Expanded(
          flex: isDesktop ? 4 : 5,
          child: _DealTermsDonutCard(leads: leads, inline: true),
        ),
      ],
    );
  }
}

// ── Row 2: Hero KPI strip ─────────────────────────────────────────────────────

class _HeroKpiStrip extends StatelessWidget {
  final List<LandLead> leads;
  final bool isDesktop;
  final bool isTablet;
  final bool inRow;

  const _HeroKpiStrip({
    required this.leads,
    required this.isDesktop,
    required this.isTablet,
    this.inRow = false,
  });

  @override
  Widget build(BuildContext context) {
    final signed = _signedLeads(leads);
    final signedPct =
        leads.isEmpty ? 0.0 : (signed.length / leads.length) * 100;

    final kpiDefs = [
      _CompactKpiDef(
        label: 'Negotiation',
        filterLeads: _leadsWithStatus(leads, LeadStatus.negotiation),
        allLeads: _leadsWithStatus(leads, LeadStatus.negotiation),
        icon: Icons.handshake_outlined,
        accent: const Color(0xFFEA580C),
        todayLabel: 'Today',
        periodLabel: 'This month',
      ),
      _CompactKpiDef(
        label: 'Legal Verification',
        filterLeads: _leadsWithStatus(leads, LeadStatus.legal),
        allLeads: _leadsWithStatus(leads, LeadStatus.legal),
        icon: Icons.gavel_outlined,
        accent: AppColors.secondary,
        todayLabel: 'Today',
        periodLabel: 'This month',
      ),
    ];

    if (inRow) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _SignedLeadsRing(
            percent: signedPct,
            count: signed.length,
            onTap: () =>
                _openLeadsList(context, 'Signed Leads', 'Signed leads', signed),
          ),
          const SizedBox(width: AppSpacing.md),
          for (var i = 0; i < kpiDefs.length; i++) ...[
            Expanded(
              child: _CompactKpiCard(
                def: kpiDefs[i],
                onTap: () => _openLeadsList(context, kpiDefs[i].label,
                    kpiDefs[i].label, kpiDefs[i].filterLeads),
              ),
            ),
            if (i < kpiDefs.length - 1) const SizedBox(width: AppSpacing.md),
          ],
        ],
      );
    }

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _SignedLeadsRing(
          percent: signedPct,
          count: signed.length,
          onTap: () =>
              _openLeadsList(context, 'Signed Leads', 'Signed leads', signed),
        ),
        for (final def in kpiDefs)
          SizedBox(
            width: isDesktop ? 220 : isTablet ? 240 : double.infinity,
            child: _CompactKpiCard(
              def: def,
              onTap: () => _openLeadsList(
                  context, def.label, def.label, def.filterLeads),
            ),
          ),
      ],
    );
  }
}

class _SignedLeadsRing extends StatelessWidget {
  final double percent;
  final int count;
  final VoidCallback? onTap;

  const _SignedLeadsRing({
    required this.percent,
    required this.count,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: percent.clamp(0, 100)),
      duration: AppMotion.slow,
      curve: AppMotion.curve,
      builder: (context, animatedPct, _) {
        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
          width: 132,
          height: 132,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 132,
                height: 132,
                child: CircularProgressIndicator(
                  value: animatedPct / 100,
                  strokeWidth: 10,
                  backgroundColor:
                      context.fomraSurfaceVar.withValues(alpha: 0.6),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.primary,
                  ),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${animatedPct.round()}%',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: context.fomraTextPrimary,
                    ),
                  ),
                  Text(
                    'Signed Leads',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.fomraTextSecondary,
                    ),
                  ),
                  Text(
                    '$count total',
                    style: TextStyle(
                      fontSize: 10,
                      color: context.fomraTextTertiary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        );
      },
    );
  }
}

class _CompactKpiDef {
  final String label;
  final List<LandLead> filterLeads;
  final List<LandLead> allLeads;
  final IconData icon;
  final Color accent;
  final String todayLabel;
  final String periodLabel;

  const _CompactKpiDef({
    required this.label,
    required this.filterLeads,
    required this.allLeads,
    required this.icon,
    required this.accent,
    required this.todayLabel,
    required this.periodLabel,
  });
}

class _CompactKpiCard extends StatelessWidget {
  final _CompactKpiDef def;
  final VoidCallback? onTap;

  const _CompactKpiCard({required this.def, this.onTap});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final trend = _weekOverWeekCounts(def.allLeads);
    final today =
        def.allLeads.where((l) => _isSameDay(l.addedOn, now)).length;
    final period =
        def.allLeads.where((l) => _isSameMonth(l.addedOn, now)).length;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: def.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(def.icon, color: def.accent, size: 18),
              ),
              const Spacer(),
              KpiPerformanceBadge(
                currentValue: trend.$1,
                previousValue: trend.$2,
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedCounter(
            value: def.filterLeads.length,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: context.fomraTextPrimary,
            ),
          ),
          Text(
            def.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.fomraTextPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _KpiMetaChip(label: def.todayLabel, value: '$today'),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _KpiMetaChip(label: def.periodLabel, value: '$period'),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

class _KpiMetaChip extends StatelessWidget {
  final String label;
  final String value;

  const _KpiMetaChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: context.fomraSurfaceVar,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9, color: context.fomraTextSecondary),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.fomraTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The pipeline-vs-deal-terms grid, levelled to a shared height.
///
/// The left column (Pipeline Dashboard + Site Ageing) is usually shorter than
/// the right (Deal Terms donut + Pending Stages), leaving whitespace under Site
/// Ageing. IntrinsicHeight — the normal way to level two columns — throws here
/// because both left cards build through a LayoutBuilder.
///
/// So we measure instead: render the columns at their natural height, read the
/// three heights after layout, then grow Pipeline and Site Ageing by an EQUAL
/// amount so the left column's bottom meets the right column's. When the left
/// column is already the taller one, nothing is resized. Re-measures whenever
/// [signature] (width + lead count) changes.
class _LeveledPipelineColumns extends StatefulWidget {
  final Widget pipeline;
  final Widget ageing;
  final Widget donut;
  final Widget pendingStages;
  final String signature;

  const _LeveledPipelineColumns({
    required this.pipeline,
    required this.ageing,
    required this.donut,
    required this.pendingStages,
    required this.signature,
  });

  @override
  State<_LeveledPipelineColumns> createState() =>
      _LeveledPipelineColumnsState();
}

class _LeveledPipelineColumnsState extends State<_LeveledPipelineColumns> {
  static const double _gap = AppSpacing.lg;

  final GlobalKey _pipeKey = GlobalKey();
  final GlobalKey _ageKey = GlobalKey();
  final GlobalKey _rightKey = GlobalKey();

  // Target heights once measured; null means "render natural and measure".
  double? _pipeHeight;
  double? _ageHeight;

  @override
  void didUpdateWidget(covariant _LeveledPipelineColumns old) {
    super.didUpdateWidget(old);
    if (old.signature != widget.signature) {
      // Width or data changed — drop back to natural size and re-measure so a
      // stale height never sticks.
      _pipeHeight = null;
      _ageHeight = null;
    }
  }

  double? _measuredHeight(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final h = box.size.height;
    return h > 0 ? h : null;
  }

  void _measure() {
    if (_pipeHeight != null) return; // already sized for these inputs
    final p = _measuredHeight(_pipeKey);
    final a = _measuredHeight(_ageKey);
    final r = _measuredHeight(_rightKey);
    if (p == null || a == null || r == null) return;

    final leftNatural = p + _gap + a;
    // Only ever grow the left column, never compress it.
    final extra = (r - leftNatural) / 2;
    if (extra <= 0.5) return; // right isn't taller — leave both cards natural
    if (!mounted) return;
    setState(() {
      _pipeHeight = p + extra;
      _ageHeight = a + extra;
    });
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());

    final pipeline = _pipeHeight == null
        ? KeyedSubtree(key: _pipeKey, child: widget.pipeline)
        : SizedBox(height: _pipeHeight, child: widget.pipeline);
    final ageing = _ageHeight == null
        ? KeyedSubtree(key: _ageKey, child: widget.ageing)
        : SizedBox(height: _ageHeight, child: widget.ageing);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The shorter Site Ageing card and the smaller donut free up room, so
        // the Pipeline Dashboard takes a wider share.
        Expanded(
          flex: 7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pipeline,
              const SizedBox(height: _gap),
              ageing,
            ],
          ),
        ),
        const SizedBox(width: _gap),
        Expanded(
          flex: 3,
          child: KeyedSubtree(
            key: _rightKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                widget.donut,
                const SizedBox(height: _gap),
                widget.pendingStages,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Row 1: Deal Terms Donut ───────────────────────────────────────────────────

class _DealTermsDonutCard extends StatefulWidget {
  final List<LandLead> leads;
  final bool inline;

  const _DealTermsDonutCard({
    required this.leads,
    this.inline = false,
  });

  @override
  State<_DealTermsDonutCard> createState() => _DealTermsDonutCardState();
}

class _DealTermsDonutCardState extends State<_DealTermsDonutCard> {
  int _touchedIndex = -1;

  static const _colors = [
    AppColors.primary,
    AppColors.secondary,
    AppColors.warning,
    AppColors.success,
    AppColors.cyan,
  ];

  @override
  Widget build(BuildContext context) {
    final dist = _dealTermsDistribution(widget.leads);
    final total = dist.values.fold<int>(0, (a, b) => a + b);
    final sections = <PieChartSectionData>[];
    // Maps each rendered pie section back to its category index, so touches
    // (which report the section index) highlight/open the right category even
    // when zero-count categories are skipped.
    final sectionCats = <int>[];

    final chartSize = widget.inline ? 120.0 : 132.0;
    final pieRadius = widget.inline ? 36.0 : 34.0;
    final touchedRadius = widget.inline ? 40.0 : 39.0;
    final centerRadius = widget.inline ? 28.0 : 30.0;

    for (var i = 0; i < _kDealCategories.length; i++) {
      final cat = _kDealCategories[i];
      final count = dist[cat] ?? 0;
      if (count == 0 && total > 0) continue;
      final pct = total == 0 ? 0.0 : (count / total) * 100;
      final touched = i == _touchedIndex;
      sectionCats.add(i);
      sections.add(
        PieChartSectionData(
          value: count == 0 ? 1 : count.toDouble(),
          title: touched ? '${pct.round()}%' : '',
          titleStyle: TextStyle(
            fontSize: widget.inline ? 9 : 11,
            fontWeight: FontWeight.w700,
            color: context.fomraTextPrimary,
          ),
          color: _colors[i % _colors.length],
          radius: touched ? touchedRadius : pieRadius,
          titlePositionPercentageOffset: 0.55,
        ),
      );
    }

    if (sections.isEmpty) {
      sections.add(
        PieChartSectionData(
          value: 1,
          color: context.fomraSurfaceVar,
          radius: pieRadius,
          title: '',
        ),
      );
    }

    final legendItems = List.generate(_kDealCategories.length, (i) {
      final cat = _kDealCategories[i];
      final count = dist[cat] ?? 0;
      final pct = total == 0 ? 0 : ((count / total) * 100).round();
      return GestureDetector(
        onTap: () => _openLeadsList(
          context,
          cat,
          'Leads with "$cat" deal terms',
          _leadsWithDealTerm(widget.leads, cat),
        ),
        child: _LegendChip(
          color: _colors[i % _colors.length],
          label: cat,
          value: '$pct%',
          selected: i == _touchedIndex,
          compact: true,
        ),
      );
    });

    // Inline keeps the wrapped chips; the dashboard card stacks the legend
    // vertically down the right-hand side of the chart.
    final legend = widget.inline
        ? Wrap(spacing: 6, runSpacing: 4, children: legendItems)
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < legendItems.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                Align(alignment: Alignment.centerLeft, child: legendItems[i]),
              ],
            ],
          );

    final chart = SizedBox(
      width: chartSize,
      height: chartSize,
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: centerRadius,
          sections: sections,
          pieTouchData: PieTouchData(
            touchCallback: (event, response) {
              final idx = response?.touchedSection?.touchedSectionIndex ?? -1;
              final catIndex =
                  (idx >= 0 && idx < sectionCats.length) ? sectionCats[idx] : -1;
              setState(() => _touchedIndex = catIndex);
              if (event is FlTapUpEvent && catIndex >= 0) {
                final cat = _kDealCategories[catIndex];
                _openLeadsList(
                  context,
                  cat,
                  'Leads with "$cat" deal terms',
                  _leadsWithDealTerm(widget.leads, cat),
                );
              }
            },
          ),
        ),
      ),
    );

    return _DashboardCard(
      title: 'Deal Terms Distribution',
      subtitle: widget.inline ? null : 'Parsed from access details',
      icon: Icons.pie_chart_outline_rounded,
      // The donut card is Deal Terms Distribution only — the pending stages
      // live in their own card (see _PendingStagesCard).
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          chart,
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: legend),
        ],
      ),
    );
  }
}

/// Compact "Pending Stages" card: Negotiation + Legal Progress counts, each
/// opening that stage's lead list.
class _PendingStagesCard extends StatelessWidget {
  final List<LandLead> leads;

  const _PendingStagesCard({required this.leads});

  @override
  Widget build(BuildContext context) {
    final negotiation = _leadsWithStatus(leads, LeadStatus.negotiation);
    final legal = _leadsWithStatus(leads, LeadStatus.legal);
    return _DashboardCard(
      title: 'Pending Stages',
      subtitle: 'Open deals awaiting progress',
      icon: Icons.pending_actions_outlined,
      child: Row(
        children: [
          Expanded(
            child: _StageMiniCard(
              label: 'Negotiation',
              count: negotiation.length,
              icon: Icons.handshake_outlined,
              color: LeadStatus.negotiation.color,
              onTap: () => _openLeadsList(
                context,
                'Negotiation',
                'Leads currently in negotiation',
                negotiation,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _StageMiniCard(
              label: 'Legal Progress',
              count: legal.length,
              icon: Icons.gavel_outlined,
              color: LeadStatus.legal.color,
              onTap: () => _openLeadsList(
                context,
                'Legal Progress',
                'Leads currently in legal',
                legal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StageMiniCard extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _StageMiniCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.24)),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.fomraTextSecondary,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  final bool selected;
  final bool compact;

  const _LegendChip({
    required this.color,
    required this.label,
    required this.value,
    this.selected = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.14) : context.fomraSurfaceVar,
        borderRadius: BorderRadius.circular(8),
        border: selected ? Border.all(color: color.withValues(alpha: 0.5)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: context.fomraTextSecondary),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: context.fomraTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Row 4: District Performance ───────────────────────────────────────────────

enum _DistrictSort { district, acres, deals, rate }

class _PendingRow {
  final String leadId;
  final String owner;
  final String executive;
  final String stage;
  final DateTime since;
  final LandLead? lead;

  const _PendingRow({
    required this.leadId,
    required this.owner,
    required this.executive,
    required this.stage,
    required this.since,
    required this.lead,
  });
}

/// Replaces the old bottleneck dashboard with compact accordion cards for the
/// three pending workflows: Legal, Land Owner Meeting, and Management Approval.
class _PendingWorkflowDashboard extends StatelessWidget {
  final List<LandLead> leads;
  final List<PendingApprovalItem> approvals;
  final ValueChanged<LandLead>? onViewLead;

  const _PendingWorkflowDashboard({
    required this.leads,
    required this.approvals,
    required this.onViewLead,
  });

  LandLead? _leadById(String id) {
    for (final l in leads) {
      if (l.leadId == id) return l;
    }
    return null;
  }

  List<_PendingRow> _fromLeads(List<LandLead> ls) => ls
      .map((l) => _PendingRow(
            leadId: l.leadId,
            owner: l.ownerName.trim().isEmpty ? '—' : l.ownerName.trim(),
            executive:
                l.createdByName.trim().isEmpty ? '—' : l.createdByName.trim(),
            stage: l.status.label,
            since: l.addedOn,
            lead: l,
          ))
      .toList();

  @override
  Widget build(BuildContext context) {
    final legal =
        _fromLeads(leads.where((l) => l.status == LeadStatus.legal).toList());
    final meeting = _fromLeads(leads
        .where((l) => l.status == LeadStatus.prospectMeetingPending)
        .toList());
    final approvalRows = approvals.map((a) {
      final l = _leadById(a.leadId);
      return _PendingRow(
        leadId: a.leadId,
        owner: (l != null && l.ownerName.trim().isNotEmpty)
            ? l.ownerName.trim()
            : '—',
        executive: (l != null && l.createdByName.trim().isNotEmpty)
            ? l.createdByName.trim()
            : '—',
        stage: l != null ? '${a.label} · ${l.status.label}' : a.label,
        since: a.since,
        lead: l,
      );
    }).toList();

    return _DashboardCard(
      title: 'Pending Workflow',
      subtitle: 'Items awaiting action across the pipeline',
      icon: Icons.pending_actions_outlined,
      child: Column(
        children: [
          _PendingAccordionCard(
            title: 'Legal Pending',
            color: AppColors.warning,
            rows: legal,
            onViewLead: onViewLead,
          ),
          const SizedBox(height: AppSpacing.sm),
          _PendingAccordionCard(
            title: 'Land Owner Meeting Pending',
            color: LeadStatus.prospectMeetingPending.color,
            rows: meeting,
            onViewLead: onViewLead,
          ),
          const SizedBox(height: AppSpacing.sm),
          _PendingAccordionCard(
            title: 'Management Approval Pending',
            color: AppColors.primary,
            rows: approvalRows,
            onViewLead: onViewLead,
          ),
        ],
      ),
    );
  }
}

class _PendingAccordionCard extends StatefulWidget {
  final String title;
  final Color color;
  final List<_PendingRow> rows;
  final ValueChanged<LandLead>? onViewLead;

  const _PendingAccordionCard({
    required this.title,
    required this.color,
    required this.rows,
    required this.onViewLead,
  });

  @override
  State<_PendingAccordionCard> createState() => _PendingAccordionCardState();
}

class _PendingAccordionCardState extends State<_PendingAccordionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.rows.length;
    return Container(
      decoration: BoxDecoration(
        color: context.fomraSurfaceVar.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.fomraBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: count == 0
                ? null
                : () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: count == 0 ? AppColors.success : widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: widget.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: count == 0
                          ? context.fomraTextTertiary
                          : context.fomraTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: [
                      const Divider(height: 1),
                      for (final row in widget.rows)
                        _PendingLeadTile(
                          row: row,
                          onOpen:
                              (row.lead != null && widget.onViewLead != null)
                                  ? () => widget.onViewLead!(row.lead!)
                                  : null,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _PendingLeadTile extends StatelessWidget {
  final _PendingRow row;
  final VoidCallback? onOpen;

  const _PendingLeadTile({required this.row, required this.onOpen});

  Widget _kv(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.fomraTextSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.fomraTextPrimary,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.fomraBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv(context, 'Lead ID', '#${row.leadId}'),
          const SizedBox(height: 4),
          _kv(context, 'Owner', row.owner),
          const SizedBox(height: 4),
          _kv(context, 'Executive', row.executive),
          const SizedBox(height: 4),
          _kv(context, 'Current Stage', row.stage),
          const SizedBox(height: 4),
          _kv(context, 'Pending Since', _relativeTime(row.since)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: const Text('Open Lead'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DistrictPerformanceCard extends StatefulWidget {
  final List<LandLead> leads;

  const DistrictPerformanceCard({super.key, required this.leads});

  @override
  State<DistrictPerformanceCard> createState() =>
      DistrictPerformanceCardState();
}

class _DistrictRow {
  final String district;
  final double acres;
  final int total;
  final int signed;
  final double rate;
  final bool isFocus;

  const _DistrictRow({
    required this.district,
    required this.acres,
    required this.total,
    required this.signed,
    required this.rate,
    required this.isFocus,
  });
}

class DistrictPerformanceCardState extends State<DistrictPerformanceCard> {
  _DistrictSort _sort = _DistrictSort.rate;
  bool _asc = false;

  List<_DistrictRow> _buildRows() {
    final byDistrict = <String, List<LandLead>>{};
    for (final lead in widget.leads) {
      final d = lead.district.trim();
      if (d.isEmpty) continue;
      byDistrict.putIfAbsent(d, () => []).add(lead);
    }

    final rows = <_DistrictRow>[];
    for (final entry in byDistrict.entries) {
      final signed =
          entry.value.where((l) => l.status == LeadStatus.signed).toList();
      final acres = signed.fold<double>(0, (s, l) => s + _leadAcres(l));
      final total = entry.value.length;
      final rate = _conversionPercent(signed.length, total);
      final isFocus = _kFocusDistricts.any(
        (f) => f.toLowerCase() == entry.key.toLowerCase(),
      );
      rows.add(_DistrictRow(
        district: entry.key,
        acres: acres,
        total: total,
        signed: signed.length,
        rate: rate,
        isFocus: isFocus,
      ));
    }

    rows.sort((a, b) {
      int cmp;
      switch (_sort) {
        case _DistrictSort.district:
          cmp = a.district.compareTo(b.district);
        case _DistrictSort.acres:
          cmp = a.acres.compareTo(b.acres);
        case _DistrictSort.deals:
          cmp = a.total.compareTo(b.total);
        case _DistrictSort.rate:
          cmp = a.rate.compareTo(b.rate);
      }
      if (a.isFocus != b.isFocus) return a.isFocus ? -1 : 1;
      return _asc ? cmp : -cmp;
    });

    return rows;
  }

  void _toggleSort(_DistrictSort col) {
    setState(() {
      if (_sort == col) {
        _asc = !_asc;
      } else {
        _sort = col;
        _asc = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows();
    final maxAcres = rows.fold<double>(0, (m, r) => math.max(m, r.acres));

    return _DashboardCard(
      title: 'District Performance',
      subtitle: 'Chennai region focus districts',
      icon: Icons.map_outlined,
      child: rows.isEmpty
          ? Text(
              'No district data available.',
              style: TextStyle(color: context.fomraTextSecondary),
            )
          : Column(
              children: [
                _DistrictTableHeader(onSort: _toggleSort, sort: _sort),
                const SizedBox(height: 6),
                for (final row in rows.take(12)) ...[
                  _DistrictTableRow(
                    row: row,
                    maxAcres: maxAcres == 0 ? 1 : maxAcres,
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
    );
  }
}

class _DistrictTableHeader extends StatelessWidget {
  final void Function(_DistrictSort) onSort;
  final _DistrictSort sort;

  const _DistrictTableHeader({required this.onSort, required this.sort});

  @override
  Widget build(BuildContext context) {
    Widget hdr(String label, _DistrictSort col, {int flex = 1}) {
      final active = sort == col;
      return Expanded(
        flex: flex,
        child: InkWell(
          onTap: () => onSort(col),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                color: active
                    ? AppColors.primary
                    : context.fomraTextSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        hdr('District', _DistrictSort.district, flex: 2),
        hdr('Acres', _DistrictSort.acres),
        hdr('Deals', _DistrictSort.deals),
        hdr('Rate', _DistrictSort.rate),
      ],
    );
  }
}

class _DistrictTableRow extends StatelessWidget {
  final _DistrictRow row;
  final double maxAcres;

  const _DistrictTableRow({required this.row, required this.maxAcres});

  @override
  Widget build(BuildContext context) {
    final progress = (row.acres / maxAcres).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: row.isFocus
            ? AppColors.primary.withValues(alpha: 0.04)
            : context.fomraSurfaceVar.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: row.isFocus
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : context.fomraSurfaceVar,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        row.district,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.fomraTextPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Text(
                  row.acres.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.fomraTextPrimary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  '${row.total}',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.fomraTextPrimary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  '${row.rate.round()}%',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: context.fomraBorder.withValues(alpha: 0.3),
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Row 4: Recent Activities ──────────────────────────────────────────────────

class _RecentActivitiesCard extends StatelessWidget {
  final List<AppNotification> notifications;

  const _RecentActivitiesCard({required this.notifications});

  (IconData, Color) _activityStyle(AppNotification n) {
    final t = '${n.title} ${n.message}'.toLowerCase();
    if (t.contains('assigned')) {
      return (Icons.person_add_alt_1_outlined, AppColors.info);
    }
    if (n.type == NotificationType.siteVisit || t.contains('site visit')) {
      return (Icons.apartment_outlined, AppColors.primary);
    }
    if (t.contains('legal') || t.contains('document')) {
      return (Icons.description_outlined, AppColors.success);
    }
    if (t.contains('joint venture') || t.contains('jv')) {
      return (Icons.handshake_outlined, AppColors.secondary);
    }
    if (t.contains('registration')) {
      return (Icons.assignment_turned_in_outlined, AppColors.warning);
    }
    if (t.contains('agreement') || t.contains('signed')) {
      return (Icons.verified_outlined, AppColors.success);
    }
    return switch (n.type) {
      NotificationType.lead => (Icons.location_on_outlined, AppColors.info),
      NotificationType.assignedLead =>
        (Icons.assignment_ind_outlined, AppColors.info),
      NotificationType.pendingLead =>
        (Icons.hourglass_bottom_outlined, AppColors.warning),
      NotificationType.pendingApproval =>
        (Icons.approval_outlined, AppColors.warning),
      NotificationType.slaBreach =>
        (Icons.timer_off_outlined, AppColors.error),
      NotificationType.overdueTask =>
        (Icons.assignment_late_outlined, AppColors.error),
      NotificationType.reminder =>
        (Icons.notifications_active_outlined, AppColors.info),
      NotificationType.task => (Icons.task_alt_outlined, AppColors.warning),
      NotificationType.document =>
        (Icons.description_outlined, AppColors.success),
      NotificationType.verification =>
        (Icons.verified_outlined, AppColors.secondary),
      NotificationType.siteVisit =>
        (Icons.apartment_outlined, AppColors.primary),
      NotificationType.signed => (Icons.check_circle, AppColors.success),
      NotificationType.alert => (Icons.warning_amber, AppColors.error),
    };
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...notifications]
      ..sort((a, b) => b.time.compareTo(a.time));
    final items = sorted.take(10).toList();

    return _DashboardCard(
      title: 'Recent Activities',
      subtitle: 'Latest team updates',
      icon: Icons.history_rounded,
      child: items.isEmpty
          ? Text(
              'No recent activity.',
              style: TextStyle(color: context.fomraTextSecondary),
            )
          : Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  _ActivityTile(
                    notification: items[i],
                    style: _activityStyle(items[i]),
                    isLast: i == items.length - 1,
                  ),
                ],
              ],
            ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final AppNotification notification;
  final (IconData, Color) style;
  final bool isLast;

  const _ActivityTile({
    required this.notification,
    required this.style,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color) = style;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: context.fomraBorder.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.fomraTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notification.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.fomraTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _relativeTime(notification.time),
                    style: TextStyle(
                      fontSize: 10,
                      color: context.fomraTextTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Row 5: Employee Leaderboard ─────────────────────────────────────────────

/// Every employee with an approved monthly target this period, each
/// category shown against real achieved counts — the same computation
/// home_screen.dart already does for a single employee's own progress card
/// (site visits from LandLeadSiteVisit, self/management meetings split by
/// LandLeadMeeting.managementPresent), just run per-employee by matching
/// loggedByName rather than scoping to one person's visible leads.
///
/// Self-contained: fetches its own approved-submissions list rather than
/// threading a new async dependency through the parent dashboard's already
/// complex bootstrap sequence. meetings/siteVisits are passed in since the
/// parent already loads them for other cards — no need to fetch twice.
class _TeamMonthlyTargetsCard extends StatefulWidget {
  final List<LandLead> leads;
  final List<LandLeadMeeting> meetings;
  final List<LandLeadSiteVisit> siteVisits;

  const _TeamMonthlyTargetsCard({
    required this.leads,
    required this.meetings,
    required this.siteVisits,
  });

  @override
  State<_TeamMonthlyTargetsCard> createState() =>
      _TeamMonthlyTargetsCardState();
}

class _TeamMonthlyTargetsCardState extends State<_TeamMonthlyTargetsCard> {
  List<MonthlyTargetSubmission> _approved = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _TeamMonthlyTargetsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-derive rows when the underlying activity (meetings/visits) refreshes
    // — cheap, no network call, just a rebuild against the cached submissions.
    if (oldWidget.leads.length != widget.leads.length ||
        oldWidget.meetings.length != widget.meetings.length ||
        oldWidget.siteVisits.length != widget.siteVisits.length) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final period = MonthlyTargetSubmission.periodOf(now.year, now.month);
    final all = await MonthlyTargetSubmissionService.allForPeriod(period);
    if (!mounted) return;
    setState(() {
      _approved = all.where((s) => s.isApproved).toList()
        ..sort((a, b) => a.employeeName.compareTo(b.employeeName));
      _loading = false;
    });
  }

  static const _categories = [
    (TargetCategory.siteVisits, 'Site Visits', AppColors.primary),
    (TargetCategory.selfMeetings, 'Self Meetings', AppColors.success),
    (TargetCategory.managementMeetings, 'Management Meetings', AppColors.warning),
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final subtitle =
        '${MonthlyTargetSubmission.monthName(now.month)} ${now.year}';

    return _DashboardCard(
      title: 'Monthly Targets',
      subtitle: subtitle,
      icon: Icons.flag_outlined,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : _approved.isEmpty
              ? Text(
                  'No approved targets set for this month yet.',
                  style: TextStyle(color: context.fomraTextSecondary),
                )
              : Column(
                  children: [
                    for (final s in _approved) ...[
                      _employeeTargetRow(context, s),
                      if (s != _approved.last)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Divider(height: 1),
                        ),
                    ],
                  ],
                ),
    );
  }

  Widget _employeeTargetRow(BuildContext context, MonthlyTargetSubmission s) {
    final now = DateTime.now();
    final name = s.employeeName.trim().toLowerCase();
    final tv = s.effectiveValues;

    final visitDates = [
      for (final v in widget.siteVisits)
        if (v.visitType == LandLeadSiteVisitType.employee &&
            v.loggedByName.trim().toLowerCase() == name)
          v.visitedAt,
      for (final l in widget.leads)
        if (l.isLiveGpsVerified && l.createdByName.trim().toLowerCase() == name)
          l.addedOn,
    ];
    final selfMeetingDates = [
      for (final m in widget.meetings)
        if (m.loggedByName.trim().toLowerCase() == name &&
            !m.managementPresent)
          m.metAt,
    ];
    final managementMeetingDates = [
      for (final m in widget.meetings)
        if (m.loggedByName.trim().toLowerCase() == name &&
            m.managementPresent)
          m.metAt,
    ];
    final datesByCategory = {
      TargetCategory.siteVisits: visitDates,
      TargetCategory.selfMeetings: selfMeetingDates,
      TargetCategory.managementMeetings: managementMeetingDates,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.employeeName.isEmpty ? s.employeeEmail : s.employeeName,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: context.fomraTextPrimary,
          ),
        ),
        const SizedBox(height: 8),
        for (final (category, label, color) in _categories)
          if (tv.containsKey(category.key))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _targetProgressLine(
                context,
                label: label,
                color: color,
                progress: MonthlyTargetProgress.forMonth(
                  target: tv[category.key] ?? 0,
                  now: now,
                  completedOn: datesByCategory[category] ?? const [],
                ),
              ),
            ),
      ],
    );
  }

  Widget _targetProgressLine(
    BuildContext context, {
    required String label,
    required Color color,
    required MonthlyTargetProgress progress,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 132,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: context.fomraTextSecondary),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.completionPercent / 100,
              minHeight: 6,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: Text(
            '${progress.achieved}/${progress.target}',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.fomraTextPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmployeeLeaderboardCard extends StatelessWidget {
  final List<PortalTeamPerf> teamRows;
  final List<LandLead> leads;

  const _EmployeeLeaderboardCard({
    required this.teamRows,
    required this.leads,
  });

  @override
  Widget build(BuildContext context) {
    final top = teamRows.take(10).toList();

    return _DashboardCard(
      title: 'Employee Performance',
      subtitle: 'Top performers by conversion',
      icon: Icons.emoji_events_outlined,
      child: top.isEmpty
          ? Text(
              'No employee activity yet.',
              style: TextStyle(color: context.fomraTextSecondary),
            )
          : Column(
              children: [
                for (final row in top) ...[
                  _LeaderboardRow(row: row, leads: leads),
                  if (row != top.last) const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final PortalTeamPerf row;
  final List<LandLead> leads;

  const _LeaderboardRow({required this.row, required this.leads});

  @override
  Widget build(BuildContext context) {
    final metrics = _employeeMetrics(row.name, leads);
    final conversion = _conversionPercent(metrics.signed, metrics.total);
    final isTop = row.rank == 1;
    final accent = isTop ? AppColors.accentLight : AppColors.primary;

    String? avatarEmail;
    for (final e in AppStore.instance.employees) {
      if (e.fullName.trim().toLowerCase() == row.name.trim().toLowerCase()) {
        avatarEmail = e.email;
        break;
      }
    }

    // The same attribution the leaderboard scores by, so the opened list holds
    // exactly this employee's leads. Reuses the existing filtered-list screen.
    final theirLeads = leads
        .where((l) =>
            l.createdByName.trim().toLowerCase() == row.name.trim().toLowerCase())
        .toList();

    return _DashboardCard(
      onTap: theirLeads.isEmpty
          ? null
          : () => _openLeadsList(
                context,
                row.name,
                '${theirLeads.length} lead${theirLeads.length == 1 ? '' : 's'} assigned',
                theirLeads,
              ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ProfileAvatar(
                    email: avatarEmail,
                    name: row.name,
                    radius: 17,
                    backgroundColor: accent.withValues(alpha: 0.15),
                    foregroundColor:
                        isTop ? AppColors.warning : AppColors.primary,
                  ),
                  if (isTop)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: AppColors.accentLight,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.emoji_events,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: context.fomraTextPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isTop
                                ? AppColors.accentLight.withValues(alpha: 0.2)
                                : context.fomraSurfaceVar,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '#${row.rank}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isTop
                                  ? const Color(0xFFB45309)
                                  : context.fomraTextSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      row.designation.isNotEmpty
                          ? row.designation
                          : row.statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.fomraTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${(row.percent * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    'Score',
                    style: TextStyle(
                      fontSize: 9,
                      color: context.fomraTextTertiary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _LeaderStat(label: 'Leads', value: '${metrics.total}'),
              _LeaderStat(label: 'Closed', value: '${metrics.signed}'),
              _LeaderStat(label: 'Neg.', value: '${metrics.negotiation}'),
              _LeaderStat(label: 'Legal', value: '${metrics.legal}'),
              _LeaderStat(
                label: 'Acres',
                value: metrics.acres.toStringAsFixed(1),
              ),
              _LeaderStat(label: 'Conv.', value: '${conversion.round()}%'),
            ],
          ),
        ],
      ),
    );
  }
}


class _LeaderStat extends StatelessWidget {
  final String label;
  final String value;

  const _LeaderStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(fontSize: 10, color: context.fomraTextSecondary),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: context.fomraTextPrimary,
          ),
        ),
      ],
    );
  }
}
