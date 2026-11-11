import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/employee_profile.dart';
import '../../models/land_lead.dart';
import '../../services/report_catalog_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_layout.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/app_table.dart';
import '../land_lead/filtered_leads_screen.dart';
import '../land_lead/lead_detail_screen.dart';

/// A report opened full-screen: every row, searchable and sortable, with
/// its KPIs on top. Nothing downloads until the user taps Download and picks
/// PDF or Excel — and the file holds exactly what was on screen.
class ReportViewerScreen extends StatefulWidget {
  final ReportKind kind;
  final List<LandLead> leads;
  final List<EmployeeProfile> employees;

  /// "Filtered: District Kanchipuram · Executive Devaraj" — shown under the
  /// title so the viewer knows the report is narrowed.
  final String? filterSummary;
  final bool canDownload;

  /// Tests: show this data instead of building it.
  final ReportPreviewData? debugData;

  const ReportViewerScreen({
    super.key,
    required this.kind,
    required this.leads,
    this.employees = const [],
    this.filterSummary,
    this.canDownload = true,
    this.debugData,
  });

  @override
  State<ReportViewerScreen> createState() => _ReportViewerScreenState();
}

class _ReportViewerScreenState extends State<ReportViewerScreen> {
  ReportPreviewData? _data;
  Object? _error;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.debugData != null) {
      _data = widget.debugData;
      return;
    }
    setState(() => _error = null);
    try {
      final data = await ReportCatalogService.buildLivePreview(
        kind: widget.kind,
        leads: widget.leads,
        employees: widget.employees,
        // Viewing shows every row; only a PDF download is capped.
        capForPdf: false,
      );
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _download() async {
    final data = _data;
    if (data == null) return;
    final format = await showModalBottomSheet<ReportFormat>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Download ${widget.kind.label}',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined,
                  color: AppColors.error),
              title: const Text('PDF'),
              subtitle: const Text('For sharing and printing'),
              onTap: () => Navigator.pop(ctx, ReportFormat.pdf),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined,
                  color: AppColors.success),
              title: const Text('Excel'),
              subtitle: const Text('Every row, for working with the data'),
              onTap: () => Navigator.pop(ctx, ReportFormat.excel),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (format == null || !mounted) return;
    setState(() => _downloading = true);
    try {
      await ReportCatalogService.exportViewed(
        kind: widget.kind,
        data: data,
        format: format,
      );
      if (mounted) {
        AppFeedback.success(context,
            'Downloaded as ${format == ReportFormat.pdf ? 'PDF' : 'Excel'}.');
      }
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Download failed: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      backgroundColor: context.fomraPageBg,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        title: Text(widget.kind.label),
        actions: [
          if (widget.canDownload && data != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _downloading ? null : _download,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.ink,
                ),
                icon: _downloading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded, size: 18),
                label: const Text('Download'),
              ),
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Could not build the report',
                message: '$_error',
                action: FilledButton(
                    onPressed: _load, child: const Text('Try again')),
              ),
            )
          : data == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: FomraLayout.pagePadding(context),
                  children: [
                    Text(
                      'Generated ${DateFormat('dd MMM yyyy, h:mm a').format(data.generatedAt)}'
                      '${widget.filterSummary == null ? '' : ' · ${widget.filterSummary}'}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.fomraTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _KpiRow(summary: data.summary),
                    const SizedBox(height: 18),
                    for (final section in data.sections) ...[
                      _SectionView(section: section),
                      const SizedBox(height: 18),
                    ],
                  ],
                ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  final List<({String label, String value})> summary;
  const _KpiRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final s in summary)
          Container(
            constraints: const BoxConstraints(minWidth: 120),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: context.fomraSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.fomraBorder),
              boxShadow: context.fomraCardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: context.fomraTextPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  s.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.fomraTextSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One table of the report: search, sort by any column, and every row
/// (shown 50 at a time so very long reports stay quick).
class _SectionView extends StatefulWidget {
  final ReportPreviewSection section;
  const _SectionView({required this.section});

  @override
  State<_SectionView> createState() => _SectionViewState();
}

class _SectionViewState extends State<_SectionView> {
  static const _page = 50;
  String _query = '';
  int? _sortCol;
  bool _asc = true;
  int _shown = _page;

  /// Numbers ("12", "45%", "1,200") sort as numbers; the rest as text.
  static num? _asNum(String v) =>
      num.tryParse(v.replaceAll(RegExp(r'[,%₹\s]'), ''));

  @override
  Widget build(BuildContext context) {
    final sec = widget.section;
    final q = _query.trim().toLowerCase();
    final idx = <int>[
      for (var i = 0; i < sec.rows.length; i++)
        if (q.isEmpty ||
            sec.rows[i].any((c) => c.toLowerCase().contains(q)))
          i,
    ];
    if (_sortCol != null) {
      final c = _sortCol!;
      idx.sort((a, b) {
        final x = c < sec.rows[a].length ? sec.rows[a][c] : '';
        final y = c < sec.rows[b].length ? sec.rows[b][c] : '';
        final nx = _asNum(x), ny = _asNum(y);
        final r = nx != null && ny != null
            ? nx.compareTo(ny)
            : x.toLowerCase().compareTo(y.toLowerCase());
        return _asc ? r : -r;
      });
    }
    final visible = idx.take(_shown).toList();

    return AppCard(
      interactive: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                '${sec.title} · ${sec.count}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: context.fomraTextPrimary,
                ),
              ),
            ),
          ]),
          if (sec.rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(sec.emptyMessage,
                  style: TextStyle(color: context.fomraTextSecondary)),
            )
          else ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    onChanged: (v) => setState(() {
                      _query = v;
                      _shown = _page;
                    }),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                      hintText: 'Search this table…',
                    ),
                  ),
                ),
                DropdownButton<int?>(
                  value: _sortCol,
                  hint: const Text('Sort by…'),
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('Original order')),
                    for (var i = 0; i < sec.headers.length; i++)
                      DropdownMenuItem<int?>(
                          value: i, child: Text(sec.headers[i])),
                  ],
                  onChanged: (v) => setState(() => _sortCol = v),
                ),
                if (_sortCol != null)
                  IconButton(
                    tooltip: _asc ? 'Ascending' : 'Descending',
                    onPressed: () => setState(() => _asc = !_asc),
                    icon: Icon(_asc
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded),
                  ),
                if (q.isNotEmpty)
                  Text(
                    '${idx.length} match${idx.length == 1 ? '' : 'es'}',
                    style: TextStyle(
                        fontSize: 12.5, color: context.fomraTextSecondary),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            AppDataTable(
              minWidth: 120.0 * sec.headers.length,
              columns: [for (final h in sec.headers) AppTableColumn(h)],
              rows: [
                for (final i in visible)
                  AppTableRow(
                    cells: [for (final c in sec.rows[i]) Text(c)],
                    onTap: i >= sec.rowLeads.length || sec.rowLeads[i].isEmpty
                        ? null
                        : () {
                            final leads = sec.rowLeads[i];
                            if (leads.length == 1) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      LeadDetailScreen(lead: leads.first),
                                ),
                              );
                            } else {
                              FilteredLeadsScreen.openList(
                                context,
                                title: sec.rows[i].first,
                                subtitle: sec.title,
                                leads: leads,
                              );
                            }
                          },
                  ),
              ],
            ),
            if (idx.length > visible.length)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Center(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _shown += _page),
                    child: Text(
                        'Show more (${idx.length - visible.length} left)'),
                  ),
                ),
              ),
            if (sec.rowLeads.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Tap a row to open its lands.',
                  style: TextStyle(
                      fontSize: 12, color: context.fomraTextTertiary),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
