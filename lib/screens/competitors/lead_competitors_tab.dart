import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/competitor_project.dart';
import '../../models/land_lead.dart';
import '../../services/app_store.dart';
import '../../services/auth_service.dart';
import '../../services/competitor_service.dart';
import '../../services/csv_saver_stub.dart'
    if (dart.library.html) '../../services/csv_saver_web.dart'
    if (dart.library.io) '../../services/csv_saver_io.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../utils/competitor_analysis.dart';
import '../../utils/lead_location_parser.dart';
import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/app_feedback.dart';
import '../land_lead/lead_detail_screen.dart';
import 'competitor_detail_screen.dart';
import 'competitor_dialogs.dart';
import 'competitor_form_screen.dart';
import 'competitor_map.dart';
import 'competitor_widgets.dart';

enum _LeadView { list, table, map }

/// The lead page's Competitors tab: projects within 2 / 5 / 10 km, in the
/// same village, or linked by hand — as a list, the team's comparison table
/// or a map. Management also sees the suggested price and sell speed, the
/// Excel download and the property-portal listings ([portalListings]).
class LeadCompetitorsTab extends StatefulWidget {
  final LandLead lead;
  final Widget? portalListings;

  const LeadCompetitorsTab({super.key, required this.lead, this.portalListings});

  @override
  State<LeadCompetitorsTab> createState() => _LeadCompetitorsTabState();
}

class _LeadCompetitorsTabState extends State<LeadCompetitorsTab> {
  double _radius = 5;
  _LeadView _view = _LeadView.list;

  @override
  void initState() {
    super.initState();
    CompetitorService.instance.addListener(_rebuild);
    CompetitorService.instance.ensureLoaded();
  }

  @override
  void dispose() {
    CompetitorService.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  LandLead get lead => widget.lead;

  void _open(CompetitorProject p) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CompetitorDetailScreen(projectId: p.id),
      ));

  /// Another lead the project is linked to (this lead's own number does
  /// nothing).
  void _openOtherLead(String id) {
    if (id == lead.leadId) return;
    final l = AppStore.instance.visibleLeads.where((l) => l.leadId == id).firstOrNull;
    if (l == null) {
      AppFeedback.info(context, 'Lead #$id is not in your list.');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LeadDetailScreen(lead: l),
    ));
  }

  Future<void> _add() async {
    await CompetitorFormScreen.open(context,
        linkLeadId: lead.leadId, initialVillage: lead.village);
  }

  Future<void> _linkExisting(List<NearbyCompetitor> shown) async {
    final picked = await pickCompetitors(context, exclude: {
      for (final c in CompetitorService.instance.all)
        if (c.linkedLeadIds.contains(lead.leadId)) c.id,
    });
    if (picked.isEmpty) return;
    try {
      await CompetitorService.instance
          .linkProjects(lead.leadId, [for (final p in picked) p.id]);
      if (mounted) {
        AppFeedback.success(
            context,
            picked.length == 1
                ? 'Linked ${picked.first.code} ${picked.first.name}.'
                : 'Linked ${picked.length} projects.');
      }
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Could not link: $e');
    }
  }

  Future<void> _download(List<NearbyCompetitor> rows) async {
    try {
      final bytes = comparisonCsv(rows,
          title: 'Competitors near lead #${lead.leadId} ${lead.displayName} '
              '(within ${_radius.round()} km, same village or linked)');
      await saveCsv(Uint8List.fromList(bytes),
          'Competitors_Lead_${lead.leadId}_${_radius.round()}km.csv');
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Could not download: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = CompetitorService.instance;
    final isMgmt = AuthService.instance.isManagement;
    final hasPin = parseLeadGps(lead.gpsCoordinates) != null;

    if (!svc.isLoaded) {
      return AppCard(
        child: svc.lastError != null
            ? EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load competitor projects',
                message: '${svc.lastError}',
                action: FilledButton(
                  onPressed: () => svc.ensureLoaded(force: true),
                  child: const Text('Try again'),
                ),
              )
            : const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
      );
    }

    final nearby = nearbyCompetitors(lead, svc.all, radiusKm: _radius);
    final summary = isMgmt ? priceSummary(nearby.map((n) => n.project)) : null;

    final controls = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<double>(
          segments: const [
            ButtonSegment(value: 2, label: Text('2 km')),
            ButtonSegment(value: 5, label: Text('5 km')),
            ButtonSegment(value: 10, label: Text('10 km')),
          ],
          selected: {_radius},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _radius = s.first),
        ),
        SegmentedButton<_LeadView>(
          segments: const [
            ButtonSegment(
                value: _LeadView.list,
                icon: Icon(Icons.view_list_rounded, size: 18),
                label: Text('List')),
            ButtonSegment(
                value: _LeadView.table,
                icon: Icon(Icons.table_chart_outlined, size: 18),
                label: Text('Table')),
            ButtonSegment(
                value: _LeadView.map,
                icon: Icon(Icons.map_outlined, size: 18),
                label: Text('Map')),
          ],
          selected: {_view},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _view = s.first),
        ),
      ],
    );

    final actions = Wrap(spacing: 8, runSpacing: 8, children: [
      FilledButton.tonalIcon(
        onPressed: _add,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Add project'),
      ),
      OutlinedButton.icon(
        onPressed: () => _linkExisting(nearby),
        icon: const Icon(Icons.add_link_rounded, size: 18),
        label: const Text('Link existing'),
      ),
      if (isMgmt && nearby.isNotEmpty)
        OutlinedButton.icon(
          onPressed: () => _download(nearby),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Excel'),
        ),
    ]);

    Widget content;
    if (nearby.isEmpty) {
      content = AppCard(
        child: EmptyState(
          icon: Icons.apartment_rounded,
          title: 'No competitor projects found',
          message: hasPin
              ? 'Nothing within ${_radius.round()} km, in ${lead.village.isEmpty ? 'this village' : lead.village} '
                  'or linked yet. Try 10 km, or add a project the team knows.'
              : 'This lead has no GPS pin, so only same-village and linked '
                  'projects can show. Add the pin, or link a project.',
        ),
      );
    } else {
      switch (_view) {
        case _LeadView.list:
          content = Column(children: [
            for (final n in nearby) ...[
              CompetitorTile(
                project: n.project,
                trailingNote: n.reason,
                onTap: () => _open(n.project),
                onOpenLead: _openOtherLead,
              ),
              const SizedBox(height: 10),
            ],
          ]);
        case _LeadView.table:
          content = _ComparisonTable(rows: nearby, onOpen: _open);
        case _LeadView.map:
          content = SizedBox(
            height: 440,
            child: CompetitorMap(
              projects: [for (final n in nearby) n.project],
              focusLead: hasPin ? lead : null,
              radiusKm: hasPin ? _radius : null,
              onOpenProject: _open,
            ),
          );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary != null) ...[
          _SummaryCard(lead: lead, summary: summary, radiusKm: _radius),
          const SizedBox(height: 12),
        ],
        controls,
        const SizedBox(height: 10),
        Text(
          '${nearby.length} project${nearby.length == 1 ? '' : 's'} within '
          '${_radius.round()} km, in the same village or linked'
          '${hasPin ? '' : ' · this lead has no GPS pin'}',
          style: TextStyle(fontSize: 12.5, color: context.fomraTextSecondary),
        ),
        const SizedBox(height: 10),
        actions,
        const SizedBox(height: 12),
        content,
        if (widget.portalListings != null) ...[
          const SizedBox(height: 14),
          AppCard(
            padding: EdgeInsets.zero,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: const Icon(Icons.public_rounded),
                title: const Text('Property portal listings'),
                subtitle: const Text(
                    'Projects advertised on MagicBricks, 99acres, Housing… (management)'),
                childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                children: [widget.portalListings!],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Management: what our land could sell for and how fast, from the plotted
/// layouts shown.
class _SummaryCard extends StatelessWidget {
  final LandLead lead;
  final CompetitorPriceSummary summary;
  final double radiusKm;

  const _SummaryCard({
    required this.lead,
    required this.summary,
    required this.radiusKm,
  });

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final sqft = parseLandExtentSqft(lead.landExtent);
    final acres = sqft == null || sqft <= 0 ? null : sqft / 43560;
    final plots = acres == null ? null : s.plotsFor(acres);
    final months = plots == null || plots <= 0 ? null : s.monthsToSell(plots);

    Widget stat(String value, String label, {Color? color}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color ?? context.fomraTextPrimary)),
            Text(label,
                style: TextStyle(fontSize: 12, color: context.fomraTextSecondary)),
          ],
        );

    return AppCard(
      padding: const EdgeInsets.all(16),
      borderColor: AppColors.success.withValues(alpha: 0.4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.insights_rounded, size: 18, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Suggested selling price',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: context.fomraTextPrimary)),
          ),
          Text('Management only',
              style: TextStyle(fontSize: 11.5, color: context.fomraTextSecondary)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 28, runSpacing: 12, children: [
          stat('${rupees(s.low)}–${rupees(s.high)}', 'per sq ft (middle half)',
              color: AppColors.success),
          stat(rupees(s.median), 'median'),
          stat(rupees(s.average), 'average'),
          if (s.plotsPerMonth != null)
            stat(s.plotsPerMonth!.toStringAsFixed(1), 'plots sold / month (median)',
                color: AppColors.primary),
        ]),
        const SizedBox(height: 12),
        Text(
          'From the deal price (negotiated, else quoted) of ${s.used.length} '
          'plotted layout${s.used.length == 1 ? '' : 's'} within '
          '${radiusKm.round()} km / same village / linked · range '
          '${rupees(s.min)}–${rupees(s.max)}'
          '${s.speedCount == 0 ? '' : ' · sell speed from ${s.speedCount} with launch date and sold count'}.',
          style: TextStyle(fontSize: 12.5, height: 1.4, color: context.fomraTextSecondary),
        ),
        if (plots != null && plots > 0) ...[
          const SizedBox(height: 8),
          Text(
            months == null
                ? 'A layout on this land (${acres!.toStringAsFixed(2)} acres) would give about '
                    '$plots plots of ~${count(s.typicalPlotSqft)} sq ft '
                    '(${(saleableShare * 100).round()}% saleable).'
                : 'A layout on this land (${acres!.toStringAsFixed(2)} acres) would give about '
                    '$plots plots of ~${count(s.typicalPlotSqft)} sq ft '
                    '(${(saleableShare * 100).round()}% saleable) and sell out in about '
                    '${months < 1.5 ? '1 month' : '${months.round()} months'} at the area’s median pace.',
            style: TextStyle(
                fontSize: 13, height: 1.4, fontWeight: FontWeight.w600,
                color: context.fomraTextPrimary),
          ),
        ],
      ]),
    );
  }
}

/// The team's sheet layout, scrolled sideways on phones.
class _ComparisonTable extends StatelessWidget {
  final List<NearbyCompetitor> rows;
  final ValueChanged<CompetitorProject> onOpen;

  const _ComparisonTable({required this.rows, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final headerStyle = TextStyle(
        fontSize: 12, fontWeight: FontWeight.w800, color: context.fomraTextPrimary);
    const cellStyle = TextStyle(fontSize: 12.5);
    return AppCard(
      padding: const EdgeInsets.all(4),
      child: Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 40,
            dataRowMinHeight: 38,
            dataRowMaxHeight: 64,
            columnSpacing: 18,
            horizontalMargin: 12,
            showCheckboxColumn: false,
            columns: [
              for (final h in comparisonHeaders)
                DataColumn(label: Text(h, style: headerStyle)),
            ],
            rows: [
              for (var i = 0; i < rows.length; i++)
                DataRow(
                  onSelectChanged: (_) => onOpen(rows[i].project),
                  cells: [
                    for (final v in comparisonRow(i, rows[i]))
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(v,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: cellStyle),
                      )),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
