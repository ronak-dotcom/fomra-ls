import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../analytics/broker_energy.dart';
import '../../analytics/business_module_metrics.dart';
import '../../models/employee_profile.dart';
import '../../models/land_lead.dart';
import '../../models/land_lead_meeting.dart';
import '../../services/lead_review_service.dart';
import '../../services/app_store.dart';
import '../../services/land_lead_meeting_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_layout.dart';
import '../../theme/fomra_theme_context.dart';
import '../../services/auth_service.dart';
import '../../widgets/contact_call_whatsapp.dart';
import '../../widgets/fomra_app_bar.dart';
import '../../widgets/fomra_app_shell.dart';
import '../../widgets/land_workspace_ui.dart';
import '../../widgets/lead_portfolio_breakdown.dart';
import '../../widgets/ui/app_components.dart';
import '../land_lead/lead_detail_screen.dart';

/// Derived from a broker's own leads — brokers have no stored status.
enum BrokerStatus { active, converted, dormant }

extension BrokerStatusX on BrokerStatus {
  String get label => switch (this) {
        BrokerStatus.active => 'Active',
        BrokerStatus.converted => 'Converted',
        BrokerStatus.dormant => 'Dormant',
      };

  String get description => switch (this) {
        BrokerStatus.active => 'Has leads still in the pipeline',
        BrokerStatus.converted => 'No active leads, but has closed sites',
        BrokerStatus.dormant => 'No active leads and no conversions',
      };

  Color get color => switch (this) {
        BrokerStatus.active => AppColors.info,
        BrokerStatus.converted => AppColors.success,
        BrokerStatus.dormant => AppColors.warning,
      };
}

BrokerStatus brokerStatusOf(BrokerPerformanceRow row) {
  if (row.active > 0) return BrokerStatus.active;
  if (row.conversions > 0) return BrokerStatus.converted;
  return BrokerStatus.dormant;
}

enum BrokerSort { ranking, leads, conversions, successRate, name }

extension BrokerSortX on BrokerSort {
  String get label => switch (this) {
        BrokerSort.ranking => 'Ranking',
        BrokerSort.leads => 'Most leads',
        BrokerSort.conversions => 'Most conversions',
        BrokerSort.successRate => 'Success rate',
        BrokerSort.name => 'Name (A–Z)',
      };

  /// [ranking] is ordered by the screen from the energy rows; here it keeps
  /// the incoming order.
  int compare(BrokerPerformanceRow a, BrokerPerformanceRow b) => switch (this) {
        BrokerSort.ranking => 0,
        BrokerSort.leads => b.leads.compareTo(a.leads),
        BrokerSort.conversions => b.conversions.compareTo(a.conversions),
        BrokerSort.successRate => b.successRate.compareTo(a.successRate),
        BrokerSort.name =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      };
}

/// Broker performance: leads, conversions, success rate.
class BrokerManagementScreen extends StatefulWidget {
  const BrokerManagementScreen({super.key});

  @override
  State<BrokerManagementScreen> createState() => _BrokerManagementScreenState();
}

class _BrokerManagementScreenState extends State<BrokerManagementScreen> {
  String _query = '';
  String? _expandedBroker;

  /// District / Village / Assigned Executive / Date Range all come from the
  /// shared workspace filter panel, applied to the leads the broker rows are
  /// aggregated from.
  final LandWorkspaceFilters _filters = LandWorkspaceFilters();
  BrokerStatus? _status;
  BrokerEnergy? _energy;
  BrokerSort _sort = BrokerSort.ranking;

  /// Leads that had a meeting with the actual Land Owner; null while loading.
  Set<String>? _ownerMetIds;

  @override
  void initState() {
    super.initState();
    _loadOwnerMeetings();
    AppStore.instance.addListener(_rebuild);
    // Review status is a filter here; load it and refilter when it changes.
    LeadReviewIndex.instance.addListener(_rebuild);
    LeadReviewIndex.instance.ensureLoaded();
  }

  @override
  void dispose() {
    AppStore.instance.removeListener(_rebuild);
    LeadReviewIndex.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _loadOwnerMeetings() async {
    try {
      final ids = await LandLeadMeetingService.leadIdsWithLandOwnerMeeting();
      if (mounted) setState(() => _ownerMetIds = ids);
    } catch (_) {
      if (mounted) setState(() => _ownerMetIds = <String>{});
    }
  }

  bool get _isManagement => AuthService.instance.isManagement;

  /// Active roster only, like the Land Workspace filter — a deleted user must
  /// not come back via the leads they once added.
  List<String> get _employeeNames {
    final names = AppStore.instance.employees
        .where((e) => e.status == EmployeeStatus.active)
        .map((e) => e.fullName.trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  /// Broker Status and Sort live on this screen; the rest are the shared
  /// panel's, so the count in the Filter button reflects everything applied.
  int get _activeFilterCount =>
      _filters.activeCount +
      (_status == null ? 0 : 1) +
      (_energy == null ? 0 : 1);

  Future<void> _openFilterPanel() async {
    final applied = await showLandWorkspaceFilterPanel(
      context: context,
      initial: _filters,
      employeeNames: _isManagement ? _employeeNames : const [],
      // Broker page: no Lead Source / Pending Status, and a multi-select broker
      // filter (with search + chips) directly below Lead Status.
      showLeadSource: false,
      showPendingStatus: false,
      brokerMultiSelect: true,
    );
    if (applied == null || !mounted) return;
    setState(() {
      _filters.assignFrom(applied);
    });
  }

  void _clearAllFilters() => setState(() {
        _filters.clear();
        _status = null;
        _energy = null;
      });

  /// Leads feeding the broker rows, narrowed by the shared filter panel.
  List<LandLead> get _filteredLeads =>
      AppStore.instance.visibleLeads.where(_filters.matches).toList();

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final metIds = _ownerMetIds;
    final energyRows = metIds == null
        ? const <BrokerEnergyRow>[]
        : BrokerEnergyAnalytics.compute(_filteredLeads, metIds);
    final energyOf = {
      for (final e in energyRows) e.name.toLowerCase(): e,
    };
    final rankOf = {
      for (var i = 0; i < energyRows.length; i++)
        energyRows[i].name.toLowerCase(): i + 1,
    };
    final searched = BrokerPerformanceAnalytics.compute(_filteredLeads)
        .where((r) =>
            q.isEmpty ||
            r.name.toLowerCase().contains(q) ||
            r.contact.toLowerCase().contains(q))
        .where((r) => _status == null || brokerStatusOf(r) == _status)
        .toList();
    // Tile counts follow search + filters, but not the energy pick itself,
    // so tapping one tile doesn't zero the other two.
    final energyCounts = {
      for (final e in BrokerEnergy.values)
        e: searched
            .where((r) => energyOf[r.name.toLowerCase()]?.energy == e)
            .length,
    };
    final rows = searched
        .where((r) =>
            _energy == null ||
            energyOf[r.name.toLowerCase()]?.energy == _energy)
        .toList();
    if (_sort == BrokerSort.ranking) {
      rows.sort((a, b) => (rankOf[a.name.toLowerCase()] ?? 1 << 30)
          .compareTo(rankOf[b.name.toLowerCase()] ?? 1 << 30));
    } else {
      rows.sort(_sort.compare);
    }
    final totalLeads = rows.fold<int>(0, (s, r) => s + r.leads);
    final totalConv = rows.fold<int>(0, (s, r) => s + r.conversions);
    final rate = totalLeads == 0 ? 0.0 : (totalConv / totalLeads) * 100;
    final pct = NumberFormat('0.0');

    final ranked = rows.where((r) => r.leads > 0).toList()
      ..sort((a, b) {
        final byRate = b.successRate.compareTo(a.successRate);
        return byRate != 0 ? byRate : b.conversions.compareTo(a.conversions);
      });
    final topBroker = ranked.isEmpty ? null : ranked.first;

    return FomraAppShell(
      currentRoute: '/broker-management',
      appBar: const FomraAppBar(
        moduleName: 'Broker Management',
      ),
      body: ListView(
        padding: FomraLayout.pagePadding(context),
        children: [
          Text(
            'Broker Management',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: context.fomraTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Performance, leads, conversions, and success rate by broker.',
            style: TextStyle(fontSize: 13, color: context.fomraTextSecondary),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _kpi('Brokers', '${rows.length}', AppColors.primary),
              _kpi('Leads', '$totalLeads', AppColors.info),
              _kpi('Conversions', '$totalConv', AppColors.success),
              _kpi('Success rate', '${pct.format(rate)}%', AppColors.warning),
              if (topBroker != null) _topBrokerKpi(context, topBroker, pct),
            ],
          ),
          const SizedBox(height: 16),
          _BrokerRankingCard(
            counts: metIds == null ? null : energyCounts,
            selected: _energy,
            onSelect: (e) =>
                setState(() => _energy = _energy == e ? null : e),
          ),
          const SizedBox(height: 16),
          LandWorkspaceSearchBar(
            hintText: 'Search broker by name or number…',
            onChanged: (v) => setState(() => _query = v),
            activeFilterCount: _activeFilterCount,
            onFilterTap: _openFilterPanel,
          ),
          const SizedBox(height: 10),
          _BrokerFilterRow(
            status: _status,
            sort: _sort,
            onStatusChanged: (s) => setState(() => _status = s),
            onSortChanged: (s) => setState(() => _sort = s),
          ),
          if (_filters.hasActive) ...[
            const SizedBox(height: 10),
            LandWorkspaceActiveFilterChips(
              filters: _filters,
              onChanged: () => setState(() {}),
              onClearAll: _clearAllFilters,
            ),
          ],
          const SizedBox(height: 16),
          if (rows.isEmpty)
            AppCard(
              child: EmptyState(
                title: _activeFilterCount > 0 || _query.isNotEmpty
                    ? 'No brokers match these filters'
                    : 'No broker leads yet',
                message: _activeFilterCount > 0 || _query.isNotEmpty
                    ? 'Try clearing a filter or searching for a different broker.'
                    : 'Brokers appear when leads include a broker name.',
              ),
            )
          else
            ...rows.map((r) {
              final expanded = _expandedBroker == r.name.toLowerCase();
              // Same filtered set the row's counts came from, so the expanded
              // portfolio can't disagree with the numbers above it.
              final brokerLeads = _filteredLeads
                  .where((l) =>
                      l.brokerName.trim().toLowerCase() == r.name.toLowerCase())
                  .toList();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  onTap: () => setState(() {
                    _expandedBroker = expanded ? null : r.name.toLowerCase();
                  }),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (rankOf[r.name.toLowerCase()] case final rank?)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                '#$rank',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: context.fomraTextTertiary,
                                ),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              r.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: context.fomraTextPrimary,
                              ),
                            ),
                          ),
                          _statusBadge(brokerStatusOf(r)),
                          const SizedBox(width: 8),
                          ContactCallWhatsApp(
                            contact: r.contact,
                            accent: AppColors.secondary,
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            expanded ? Icons.expand_less : Icons.expand_more,
                            color: context.fomraTextSecondary,
                          ),
                        ],
                      ),
                      if (r.contact.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(r.contact,
                            style: TextStyle(
                                color: context.fomraTextSecondary,
                                fontSize: 12)),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _chip('Leads ${r.leads}'),
                          const SizedBox(width: 8),
                          _chip('Converted ${r.conversions}'),
                          const SizedBox(width: 8),
                          _chip('Active ${r.active}'),
                          const Spacer(),
                          Text(
                            '${pct.format(r.successRate)}%',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                      if (energyOf[r.name.toLowerCase()] case final e?) ...[
                        const SizedBox(height: 10),
                        _OwnerMeetingLine(row: e),
                      ],
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: (r.successRate / 100).clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: context.fomraBorder,
                          color: AppColors.success,
                        ),
                      ),
                      if (expanded) ...[
                        const SizedBox(height: 14),
                        _BrokerPortfolioSection(leads: brokerLeads),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, Color color) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: context.fomraTextSecondary)),
        ],
      ),
    );
  }

  Widget _topBrokerKpi(
    BuildContext context,
    BrokerPerformanceRow broker,
    NumberFormat pct,
  ) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_outlined,
                  size: 16, color: AppColors.secondary),
              const SizedBox(width: 6),
              Text(
                'Top Performing Broker',
                style: TextStyle(
                  fontSize: 11,
                  color: context.fomraTextSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            broker.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${pct.format(broker.successRate)}% success · ${broker.conversions} sites closed',
            style: TextStyle(fontSize: 11, color: context.fomraTextSecondary),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(BrokerStatus status) => Tooltip(
        message: status.description,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: status.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: status.color.withValues(alpha: 0.3)),
          ),
          child: Text(
            status.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: status.color,
            ),
          ),
        ),
      );

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: context.fomraSurfaceVar,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11)),
      );
}

/// Energy Giver / Average / Energy Drainer counts; a tile filters the list.
class _BrokerRankingCard extends StatelessWidget {
  /// Null while the owner-meeting data loads.
  final Map<BrokerEnergy, int>? counts;
  final BrokerEnergy? selected;
  final ValueChanged<BrokerEnergy> onSelect;

  const _BrokerRankingCard({
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.leaderboard_outlined,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'Broker Ranking',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: context.fomraTextPrimary,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            'By the share of lands where we met the actual Land Owner '
            '(a converted land counts). Tap a group to see those brokers.',
            style: TextStyle(fontSize: 12, color: context.fomraTextSecondary),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            const gap = 10.0;
            final perRow = c.maxWidth >= 480 ? 3 : 1;
            final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final e in BrokerEnergy.values)
                  SizedBox(
                    width: w,
                    child: _EnergyTile(
                      energy: e,
                      count: counts?[e],
                      selected: selected == e,
                      onTap: counts == null ? null : () => onSelect(e),
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _EnergyTile extends StatelessWidget {
  final BrokerEnergy energy;
  final int? count;
  final bool selected;
  final VoidCallback? onTap;

  const _EnergyTile({
    required this.energy,
    required this.count,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = energy.color;
    return Material(
      color: c.withValues(alpha: selected ? 0.16 : 0.07),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: c.withValues(alpha: selected ? 0.8 : 0.25),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(energy.icon, size: 22, color: c),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      energy.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: c,
                      ),
                    ),
                    Text(
                      energy.rule,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.fomraTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                count == null ? '–' : '$count',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: c,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill showing a broker's Energy Giver / Average / Energy Drainer rating.
class BrokerEnergyBadge extends StatelessWidget {
  final BrokerEnergy energy;
  const BrokerEnergyBadge({super.key, required this.energy});

  @override
  Widget build(BuildContext context) {
    final c = energy.color;
    return Tooltip(
      message: energy.rule,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(energy.icon, size: 12, color: c),
          const SizedBox(width: 3),
          Text(
            energy.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: c,
            ),
          ),
        ]),
      ),
    );
  }
}

/// "Owner met on 3 of 5 lands · 60% · 2 without meeting · last land 9 Nov".
class _OwnerMeetingLine extends StatelessWidget {
  final BrokerEnergyRow row;
  const _OwnerMeetingLine({required this.row});

  @override
  Widget build(BuildContext context) {
    final c = row.energy.color;
    final last = row.lastLandOn;
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        BrokerEnergyBadge(energy: row.energy),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.handshake_outlined, size: 15, color: c),
          const SizedBox(width: 4),
          Text(
            'Owner met on ${row.ownerMeetings} of ${row.lands} '
            '${row.lands == 1 ? 'land' : 'lands'} · '
            '${row.meetingRate.round()}%',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ]),
        if (row.withoutMeeting > 0)
          Text(
            '${row.withoutMeeting} without owner meeting',
            style: TextStyle(fontSize: 12, color: context.fomraTextSecondary),
          ),
        if (last != null)
          Text(
            'Last land ${DateFormat('d MMM yyyy').format(last)}',
            style: TextStyle(fontSize: 12, color: context.fomraTextSecondary),
          ),
      ],
    );
  }
}

/// Broker Status + Sort — the two filters that are specific to this page and so
/// aren't part of the shared lead filter panel.
class _BrokerFilterRow extends StatelessWidget {
  final BrokerStatus? status;
  final BrokerSort sort;
  final ValueChanged<BrokerStatus?> onStatusChanged;
  final ValueChanged<BrokerSort> onSortChanged;

  const _BrokerFilterRow({
    required this.status,
    required this.sort,
    required this.onStatusChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Wrap so the two selectors stack instead of overflowing on narrow phones.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _BrokerFilterDropdown<BrokerStatus?>(
          icon: Icons.flag_outlined,
          value: status,
          items: [
            (value: null, label: 'All statuses', tooltip: null),
            for (final s in BrokerStatus.values)
              (value: s, label: s.label, tooltip: s.description),
          ],
          onChanged: onStatusChanged,
        ),
        _BrokerFilterDropdown<BrokerSort>(
          icon: Icons.swap_vert_rounded,
          value: sort,
          items: [
            for (final s in BrokerSort.values)
              (value: s, label: s.label, tooltip: null),
          ],
          onChanged: onSortChanged,
        ),
      ],
    );
  }
}

class _BrokerFilterDropdown<T> extends StatelessWidget {
  final IconData icon;
  final T value;
  final List<({T value, String label, String? tooltip})> items;
  final ValueChanged<T> onChanged;

  const _BrokerFilterDropdown({
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = items.where((i) => i.value == value).firstOrNull;
    final isDefault = value == null || value == items.first.value;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDefault
            ? context.fomraSurface
            : AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDefault
              ? context.fomraBorder
              : AppColors.primary.withValues(alpha: 0.55),
          width: isDefault ? 1 : 1.4,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.fomraTextPrimary,
          ),
          selectedItemBuilder: (_) => [
            for (final i in items)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: isDefault
                        ? context.fomraTextSecondary
                        : AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    selected?.label ?? i.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDefault
                          ? context.fomraTextPrimary
                          : AppColors.primary,
                    ),
                  ),
                ],
              ),
          ],
          items: [
            for (final i in items)
              DropdownMenuItem<T>(
                value: i.value,
                child: Tooltip(
                  message: i.tooltip ?? '',
                  waitDuration: const Duration(milliseconds: 500),
                  child: Text(i.label),
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null || null is T) onChanged(v as T);
          },
        ),
      ),
    );
  }
}

/// Loads the meetings-conducted count for a broker's leads, then renders the
/// shared portfolio breakdown with a Lead Age column instead of Status.
class _BrokerPortfolioSection extends StatefulWidget {
  final List<LandLead> leads;

  const _BrokerPortfolioSection({required this.leads});

  @override
  State<_BrokerPortfolioSection> createState() =>
      _BrokerPortfolioSectionState();
}

class _BrokerPortfolioSectionState extends State<_BrokerPortfolioSection> {
  bool _loading = true;
  int _meetingsConducted = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _BrokerPortfolioSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leads != widget.leads) _load();
  }

  Future<void> _load() async {
    try {
      final lists = await Future.wait<List<LandLeadMeeting>>(
        widget.leads.map((l) => LandLeadMeetingService.getForLead(l.leadId)),
      );
      final total = lists.fold<int>(0, (s, meetings) => s + meetings.length);
      if (!mounted) return;
      setState(() {
        _meetingsConducted = total;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LeadPortfolioBreakdown(
      leads: widget.leads,
      meetingsConducted: _loading ? null : _meetingsConducted,
      useLeadAgeColumn: true,
      onOpenLead: (lead) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LeadDetailScreen(lead: lead)),
      ),
    );
  }
}
