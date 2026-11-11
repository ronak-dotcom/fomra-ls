import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/land_lead.dart';
import '../../services/broker_directory.dart';
import '../../services/app_store.dart';
import '../../services/auth_service.dart';
import '../../services/report_catalog_service.dart';
import '../../services/role_access.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_layout.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/fomra_app_bar.dart';
import '../../widgets/fomra_app_shell.dart';
import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/multi_select_field.dart';
import '../land_lead/filtered_leads_screen.dart';
import 'report_viewer_screen.dart';

/// Management + admins can export reports, and executives can export their own
/// (report data is already scoped to their leads via [AppStore.visibleLeads]).
bool get _reportsCanExport =>
    RoleAccess.canExport || AuthService.instance.isEmployee;

enum _StatusFilter { active, closed, dropped }

extension on _StatusFilter {
  String get label => switch (this) {
        _StatusFilter.active => 'Active',
        _StatusFilter.closed => 'Closed',
        _StatusFilter.dropped => 'Dropped',
      };

  bool matches(LeadStatus status) => switch (this) {
        _StatusFilter.active => status.isActive,
        _StatusFilter.closed => status.isAcquired,
        _StatusFilter.dropped => status.isDropped,
      };
}

/// Report categories shown as premium selectable cards.
const _reportCategories = <({String name, List<ReportKind> kinds})>[
  (
    name: 'Performance',
    kinds: [
      ReportKind.employee,
      ReportKind.broker,
      ReportKind.district,
      ReportKind.village,
    ],
  ),
  (
    name: 'Acquisition',
    kinds: [
      ReportKind.pipeline,
      ReportKind.conversion,
      ReportKind.siteAgeing,
      ReportKind.acquisitionSummary,
    ],
  ),
  (
    name: 'Operations',
    kinds: [
      ReportKind.siteVisit,
      ReportKind.pendingApproval,
    ],
  ),
  (
    name: 'Time Reports',
    kinds: [
      ReportKind.daily,
      ReportKind.weekly,
      ReportKind.monthly,
    ],
  ),
];

const _quickReports = <({String label, ReportKind kind})>[
  (label: "Today's Report", kind: ReportKind.daily),
  (label: 'Weekly Report', kind: ReportKind.weekly),
  (label: 'Monthly Report', kind: ReportKind.monthly),
  (label: 'Employee Performance', kind: ReportKind.employee),
  (label: 'Pipeline Report', kind: ReportKind.pipeline),
];

/// Premium enterprise reporting: quick reports, categorized report cards, a
/// slide-in filters drawer, a live summary, an inline preview and export.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final Set<ReportKind> _selectedKinds = {};


  DateTimeRange? _dateRange;
  Set<String> _executive = {};
  Set<String> _district = {};
  Set<String> _village = {};
  Set<String> _broker = {};
  Set<String> _owner = {};
  final Set<LeadStatus> _stages = {};
  _StatusFilter? _status;

  @override
  void initState() {
    super.initState();
    AppStore.instance.addListener(_rebuild);
  }

  @override
  void dispose() {
    AppStore.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  int get _activeFilterCount =>
      (_dateRange != null ? 1 : 0) +
      (_executive.isNotEmpty ? 1 : 0) +
      (_district.isNotEmpty ? 1 : 0) +
      (_village.isNotEmpty ? 1 : 0) +
      (_broker.isNotEmpty ? 1 : 0) +
      (_owner.isNotEmpty ? 1 : 0) +
      (_stages.isNotEmpty ? 1 : 0) +
      (_status != null ? 1 : 0);

  bool get _hasActiveFilters => _activeFilterCount > 0;

  void _clearFilters() {
    setState(() {
      _dateRange = null;
      _executive = {};
      _district = {};
      _village = {};
      _broker = {};
      _owner = {};
      _stages.clear();
      _status = null;
    });
  }

  List<String> _distinct(String Function(LandLead l) pick) {
    final values = AppStore.instance.visibleLeads
        .map(pick)
        .where((v) => v.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  List<LandLead> get _filteredLeads {
    return AppStore.instance.visibleLeads.where((l) {
      if (_dateRange != null) {
        final d = l.addedOn.toLocal();
        final start = _dateRange!.start;
        final end = _dateRange!.end
            .add(const Duration(hours: 23, minutes: 59, seconds: 59));
        if (d.isBefore(start) || d.isAfter(end)) return false;
      }
      if (_executive.isNotEmpty && !_executive.contains(l.createdByName)) return false;
      if (_district.isNotEmpty && !_district.contains(l.district)) return false;
      if (_village.isNotEmpty && !_village.contains(l.village)) return false;
      if (_broker.isNotEmpty && !_broker.contains(l.brokerDisplayName)) return false;
      if (_owner.isNotEmpty && !_owner.contains(l.ownerName)) return false;
      if (_stages.isNotEmpty && !_stages.contains(l.status)) return false;
      if (_status != null && !_status!.matches(l.status)) return false;
      return true;
    }).toList();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _dateRange,
      // A compact input dialog instead of the full-screen calendar (tap the
      // calendar icon inside to switch to the month view if needed).
      initialEntryMode: DatePickerEntryMode.input,
    );
    if (picked != null) setState(() => _dateRange = picked);
  }

  /// "Filtered: 2 filters" style note for the viewer, or null.
  String? get _filterSummary => _hasActiveFilters
      ? 'Filtered ($_activeFilterCount filter${_activeFilterCount == 1 ? '' : 's'})'
      : null;

  /// Reports open to view first — full screen, every row. Downloading is a
  /// separate, deliberate step from inside the viewer.
  void _openReport(ReportKind kind) {
    setState(() {
      _selectedKinds
        ..clear()
        ..add(kind);
    });
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportViewerScreen(
          kind: kind,
          leads: _filteredLeads,
          employees: AppStore.instance.employees,
          filterSummary: _filterSummary,
          canDownload: _reportsCanExport,
        ),
      ),
    );
  }

  void _toggleKind(ReportKind kind) => _openReport(kind);

  void _selectQuickReport(ReportKind kind) => _openReport(kind);

  IconData _icon(ReportKind kind) => switch (kind) {
        ReportKind.daily => Icons.today_outlined,
        ReportKind.weekly => Icons.date_range_outlined,
        ReportKind.monthly => Icons.calendar_month_outlined,
        ReportKind.employee => Icons.badge_outlined,
        ReportKind.district => Icons.map_outlined,
        ReportKind.village => Icons.holiday_village_outlined,
        ReportKind.broker => Icons.handshake_outlined,
        ReportKind.owner => Icons.person_outline,
        ReportKind.conversion => Icons.trending_up_rounded,
        ReportKind.siteAgeing => Icons.hourglass_bottom_rounded,
        ReportKind.pendingApproval => Icons.approval_outlined,
        ReportKind.siteVisit => Icons.apartment_outlined,
        ReportKind.survey => Icons.straighten_outlined,
        ReportKind.legal => Icons.gavel_outlined,
        ReportKind.document => Icons.description_outlined,
        ReportKind.acquisitionSummary => Icons.summarize_outlined,
        ReportKind.pipeline => Icons.filter_alt_outlined,
      };

  // ── Filters drawer ─────────────────────────────────────────────────────────

  void _openFilters() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Filters',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, a1, a2) {
        final width =
            math.min(380.0, MediaQuery.sizeOf(ctx).width * 0.88);
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: context.fomraSurface,
            elevation: 12,
            child: SizedBox(
              width: width,
              height: double.infinity,
              child: SafeArea(
                child: StatefulBuilder(
                  builder: (ctx, setSheet) {
                    void apply(VoidCallback fn) {
                      setState(fn);
                      setSheet(() {});
                    }

                    return _buildFiltersDrawer(ctx, apply);
                  },
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, sec, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero)
              .animate(curved),
          child: child,
        );
      },
    );
  }

  Widget _buildFiltersDrawer(
    BuildContext context,
    void Function(VoidCallback) apply,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.tune_rounded, size: 20),
              const SizedBox(width: 8),
              Text(
                'Filters',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: context.fomraTextPrimary,
                ),
              ),
              const Spacer(),
              if (_hasActiveFilters)
                TextButton(
                  onPressed: () => apply(_clearFilters),
                  child: const Text('Clear'),
                ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await _pickDateRange();
                  apply(() {});
                },
                icon: const Icon(Icons.date_range_outlined, size: 18),
                label: Text(
                  _dateRange == null
                      ? 'Date range'
                      : '${DateFormat('d MMM').format(_dateRange!.start)} – ${DateFormat('d MMM yyyy').format(_dateRange!.end)}',
                ),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              MultiSelectField<String>(
                label: 'Executive',
                icon: Icons.person_outline_rounded,
                options: _distinct((l) => l.createdByName),
                selected: _executive,
                labelOf: (s) => s,
                onChanged: (v) => apply(() => _executive = v),
              ),
              const SizedBox(height: 8),
              MultiSelectField<String>(
                label: 'District',
                icon: Icons.map_outlined,
                options: _distinct((l) => l.district),
                selected: _district,
                labelOf: (s) => s,
                onChanged: (v) => apply(() => _district = v),
              ),
              const SizedBox(height: 8),
              MultiSelectField<String>(
                label: 'Village',
                icon: Icons.location_city_outlined,
                options: _distinct((l) => l.village),
                selected: _village,
                labelOf: (s) => s,
                onChanged: (v) => apply(() => _village = v),
              ),
              const SizedBox(height: 8),
              MultiSelectField<String>(
                label: 'Broker',
                icon: Icons.handshake_outlined,
                options: _distinct((l) => l.brokerDisplayName),
                selected: _broker,
                labelOf: (s) => s,
                onChanged: (v) => apply(() => _broker = v),
              ),
              const SizedBox(height: 8),
              MultiSelectField<String>(
                label: 'Owner',
                icon: Icons.badge_outlined,
                options: _distinct((l) => l.ownerName),
                selected: _owner,
                labelOf: (s) => s,
                onChanged: (v) => apply(() => _owner = v),
              ),
              const SizedBox(height: 8),
              MultiSelectField<LeadStatus>(
                label: 'Stage',
                icon: Icons.timeline_rounded,
                options: leadStatusPipelineOrder,
                selected: _stages,
                labelOf: (s) => s.label,
                onChanged: (v) => apply(() {
                  _stages
                    ..clear()
                    ..addAll(v);
                }),
              ),
              const SizedBox(height: 12),
              _statusDropdown((v) => apply(() => _status = v)),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
              child: Text('Apply${_hasActiveFilters ? ' ($_activeFilterCount)' : ''}'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusDropdown(ValueChanged<_StatusFilter?> onChanged) {
    return DropdownButtonFormField<_StatusFilter>(
      key: ValueKey('rp-status-$_status'),
      initialValue: _status,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Status',
        isDense: true,
        filled: true,
        fillColor: context.fomraSurfaceVar,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('All status')),
        for (final s in _StatusFilter.values)
          DropdownMenuItem(value: s, child: Text(s.label)),
      ],
      onChanged: onChanged,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pad = FomraLayout.pagePadding(context);
    final leadsEmpty = AppStore.instance.visibleLeads.isEmpty;

    return FomraAppShell(
      currentRoute: '/reports',
      appBar: const FomraAppBar(
        moduleName: 'Reports',
      ),
      body: ListView(
        padding: pad,
        children: [
          _titleRow(context),
          const SizedBox(height: 16),
          if (leadsEmpty)
            const AppCard(
              child: EmptyState(
                icon: Icons.summarize_outlined,
                title: 'No site data yet',
                message:
                    'Reports will be available once sites are in the system.',
              ),
            )
          else ...[
            _quickReportsSection(context),
            const SizedBox(height: 20),
            _categoriesSection(context),
            const SizedBox(height: 20),
            _liveSummarySection(context),
            const SizedBox(height: 20),
            _landownerMeetingOutcomeSection(context),
            const SizedBox(height: 20),
            _lostDealAnalysisSection(context),
            const SizedBox(height: 20),
            _brokerPerformanceSection(context),
          ],
        ],
      ),
    );
  }

  Widget _titleRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reports',
                style: TextStyle(
                  fontSize:
                      FomraLayout.responsiveClamp(context, min: 20, max: 22),
                  fontWeight: FontWeight.w800,
                  color: context.fomraTextPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Open any report to view it in full. Download as PDF or Excel '
                'from inside the report when you need a file.',
                style:
                    TextStyle(fontSize: 13, color: context.fomraTextSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _openFilters,
          icon: Badge(
            isLabelVisible: _hasActiveFilters,
            label: Text('$_activeFilterCount'),
            child: const Icon(Icons.tune_rounded, size: 18),
          ),
          label: const Text('Filters'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _quickReportsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, 'Quick reports', Icons.bolt_outlined),
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _quickReports.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final q = _quickReports[i];
              final selected = _selectedKinds.contains(q.kind) &&
                  _selectedKinds.length == 1;
              return Material(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : context.fomraSurface,
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => _selectQuickReport(q.kind),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : context.fomraBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_icon(q.kind),
                            size: 16,
                            color: selected
                                ? AppColors.primary
                                : context.fomraTextSecondary),
                        const SizedBox(width: 6),
                        Text(
                          q.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? AppColors.primary
                                : context.fomraTextPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _categoriesSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(context, 'Report types', Icons.grid_view_outlined,
            trailing: 'Tap a report to open it'),
        const SizedBox(height: 10),
        for (final cat in _reportCategories) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Text(
              cat.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: context.fomraTextSecondary,
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 720 ? 3 : (c.maxWidth >= 480 ? 2 : 1);
              const gap = 10.0;
              final cardW = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final kind in cat.kinds)
                    SizedBox(width: cardW, child: _reportCard(context, kind)),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _reportCard(BuildContext context, ReportKind kind) {
    final selected = _selectedKinds.contains(kind);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _toggleKind(kind),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.06)
                : context.fomraSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : context.fomraBorder,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected ? context.fomraCardShadow : null,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(_icon(kind), size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      kind.label,
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
                      kind.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.25,
                        color: context.fomraTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected ? AppColors.primary : context.fomraBorder,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _liveSummarySection(BuildContext context) {
    final leads = _filteredLeads;
    final executives = _distinctFrom(leads, (l) => l.createdByName);
    final villages = _distinctFrom(leads, (l) => l.village);
    final estPages = _selectedKinds.isEmpty
        ? 0
        : _selectedKinds.length * math.max(1, (leads.length / 25).ceil());
    final rangeLabel = _dateRange == null
        ? 'All time'
        : '${DateFormat('d MMM').format(_dateRange!.start)} – ${DateFormat('d MMM').format(_dateRange!.end)}';

    final cells = <({String label, String value, IconData icon})>[
      (label: 'Records found', value: '${leads.length}', icon: Icons.dataset_outlined),
      (label: 'Executives', value: '$executives', icon: Icons.badge_outlined),
      (label: 'Villages', value: '$villages', icon: Icons.holiday_village_outlined),
      (label: 'Selected reports', value: '${_selectedKinds.length}', icon: Icons.checklist_rounded),
      (label: 'Date range', value: rangeLabel, icon: Icons.date_range_outlined),
      (label: 'Estimated pages', value: '$estPages', icon: Icons.description_outlined),
    ];

    return AppCard(
      interactive: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(context, 'Live summary', Icons.insights_outlined),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 560 ? 3 : 2;
              const gap = 10.0;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final cell in cells)
                    SizedBox(
                      width: w,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.fomraSurfaceVar.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.fomraBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(cell.icon,
                                size: 16, color: context.fomraTextSecondary),
                            const SizedBox(height: 8),
                            Text(
                              cell.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: context.fomraTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              cell.label,
                              style: TextStyle(
                                fontSize: 11,
                                color: context.fomraTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  int _distinctFrom(List<LandLead> leads, String Function(LandLead) pick) =>
      leads.map(pick).where((v) => v.trim().isNotEmpty).toSet().length;

  /// Groups Dropped leads by drop_reason — the data has always been
  /// captured (lead_drop_reason.dart / the drop dialog), it just never had
  /// anywhere to be seen in aggregate before this.
  /// The report this whole feature was built for: of leads where we
  /// actually completed a landowner (or agreement-holder) meeting, what's
  /// their CURRENT status — regardless of how many times it's changed
  /// since, or whether it later went to Legal, got dropped, went on hold,
  /// or signed. Powered by landowner_meeting_completed_at, which is set
  /// once from the meeting log and never touched by later status changes —
  /// see land_lead_meeting_service.dart for how it's derived.
  Widget _landownerMeetingOutcomeSection(BuildContext context) {
    final met = _filteredLeads
        .where((l) => l.landownerMeetingCompletedAt != null)
        .toList();

    final byStatus = <LeadStatus, List<LandLead>>{};
    for (final lead in met) {
      (byStatus[lead.status] ??= []).add(lead);
    }
    final rows = byStatus.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    final total = met.length;

    return AppCard(
      interactive: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(
              context, 'Landowner Meeting Outcome', Icons.groups_outlined,
              trailing: '$total met'),
          const SizedBox(height: 4),
          Text(
            'Of leads where we actually completed a landowner or agreement-holder '
            'meeting, where do they stand today.',
            style: TextStyle(fontSize: 12, color: context.fomraTextSecondary),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(
              'No leads with a completed landowner meeting in the selected range.',
              style: TextStyle(fontSize: 12.5, color: context.fomraTextSecondary),
            )
          else
            for (final row in rows) ...[
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => FilteredLeadsScreen.openList(
                  context,
                  title: '${row.key.label} — met the owner',
                  subtitle: 'Landowner Meeting Outcome',
                  leads: row.value,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: row.key.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              row.key.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: context.fomraTextPrimary,
                              ),
                            ),
                          ),
                          Text(
                            '${row.value.length} (${total == 0 ? 0 : (row.value.length / total * 100).round()}%)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: context.fomraTextSecondary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded,
                              size: 16, color: context.fomraTextSecondary),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : row.value.length / total,
                          minHeight: 6,
                          backgroundColor:
                              context.fomraSurfaceVar.withValues(alpha: 0.5),
                          color: row.key.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _lostDealAnalysisSection(BuildContext context) {
    final dropped =
        _filteredLeads.where((l) => l.status == LeadStatus.dropped).toList();

    final byReason = <String, List<LandLead>>{};
    for (final lead in dropped) {
      final reason = lead.dropReason.trim();
      final key = reason.isEmpty ? 'Not specified' : reason;
      (byReason[key] ??= []).add(lead);
    }
    final rows = byReason.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    final total = dropped.length;

    return AppCard(
      interactive: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(context, 'Lost Deal Analysis', Icons.trending_down_rounded,
              trailing: '$total dropped'),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(
              'No dropped leads in the selected range.',
              style: TextStyle(fontSize: 12.5, color: context.fomraTextSecondary),
            )
          else
            for (final row in rows) ...[
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => FilteredLeadsScreen.openList(
                  context,
                  title: 'Dropped — ${row.key}',
                  subtitle: 'Lost Deal Analysis',
                  leads: row.value,
                ),
                child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.key,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.fomraTextPrimary,
                            ),
                          ),
                        ),
                        Text(
                          '${row.value.length} (${total == 0 ? 0 : (row.value.length / total * 100).round()}%)',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: context.fomraTextSecondary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded,
                            size: 16, color: context.fomraTextSecondary),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : row.value.length / total,
                        minHeight: 6,
                        backgroundColor:
                            context.fomraSurfaceVar.withValues(alpha: 0.5),
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                ),
              ),
            ],
        ],
      ),
    );
  }

  /// Broker performance — deals won/dropped/active and conversion rate per
  /// broker, computed from the same lead data the existing Broker Report
  /// directory already lists but doesn't score.
  Widget _brokerPerformanceSection(BuildContext context) {
    final leads = _filteredLeads
        .where((l) => l.brokerName.trim().isNotEmpty)
        .toList();

    // By mobile number (one broker typed two ways is one row), shown under
    // the Broker Directory's name.
    final byBroker = <String, List<LandLead>>{};
    for (final lead in leads) {
      (byBroker[BrokerDirectory.keyFor(lead)] ??= []).add(lead);
    }

    final rows = byBroker.entries.map((e) {
      final all = e.value;
      final signed = all.where((l) => l.status == LeadStatus.signed).length;
      final dropped = all.where((l) => l.status == LeadStatus.dropped).length;
      final conversion = all.isEmpty ? 0.0 : signed / all.length * 100;
      return (
        key: e.key,
        broker: all.first.brokerDisplayName,
        total: all.length,
        signed: signed,
        dropped: dropped,
        conversion: conversion,
      );
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return AppCard(
      interactive: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(context, 'Broker Performance · Lifetime',
              Icons.handshake_outlined,
              trailing: '${rows.length} brokers'),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openReport(ReportKind.broker),
              icon: const Icon(Icons.open_in_full_rounded, size: 16),
              label: const Text(
                  'Open full Broker report (owner meetings, rating)'),
            ),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(
              'No broker-sourced leads in the selected range.',
              style: TextStyle(fontSize: 12.5, color: context.fomraTextSecondary),
            )
          else ...[
            Row(
              children: [
                Expanded(flex: 24, child: _brokerHeaderCell(context, 'Broker')),
                Expanded(flex: 10, child: _brokerHeaderCell(context, 'Leads')),
                Expanded(flex: 10, child: _brokerHeaderCell(context, 'Signed')),
                Expanded(flex: 12, child: _brokerHeaderCell(context, 'Conv.')),
                const SizedBox(width: 16),
              ],
            ),
            for (final r in rows.take(15))
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => FilteredLeadsScreen.openList(
                  context,
                  title: r.broker,
                  subtitle: 'Broker Performance',
                  leads: byBroker[r.key] ?? const [],
                ),
                child: Row(
                  children: [
                    Expanded(flex: 24, child: _brokerCell(context, r.broker, bold: true)),
                    Expanded(flex: 10, child: _brokerCell(context, '${r.total}')),
                    Expanded(flex: 10, child: _brokerCell(context, '${r.signed}')),
                    Expanded(flex: 12, child: _brokerCell(context, '${r.conversion.round()}%')),
                    SizedBox(
                      width: 16,
                      child: Icon(Icons.chevron_right_rounded,
                          size: 15, color: context.fomraTextSecondary),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _brokerHeaderCell(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: context.fomraTextSecondary,
          ),
        ),
      );

  Widget _brokerCell(BuildContext context, String text, {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: context.fomraTextPrimary,
          ),
        ),
      );

  Widget _sectionLabel(BuildContext context, String text, IconData icon,
      {String? trailing}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: context.fomraTextPrimary,
          ),
        ),
        if (trailing != null) ...[
          const Spacer(),
          Text(
            trailing,
            style: TextStyle(fontSize: 12, color: context.fomraTextSecondary),
          ),
        ],
      ],
    );
  }
}
