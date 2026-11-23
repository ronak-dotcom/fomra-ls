import 'package:flutter/material.dart';

import '../../models/competitor_project.dart';
import '../../models/land_lead.dart';
import '../../services/app_store.dart';
import '../../services/competitor_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_layout.dart';
import '../../theme/fomra_theme_context.dart';
import '../../utils/competitor_analysis.dart';
import '../../widgets/fomra_app_bar.dart';
import '../../widgets/fomra_app_shell.dart';
import '../../widgets/ui/app_components.dart';
import '../land_lead/lead_detail_screen.dart';
import 'competitor_detail_screen.dart';
import 'competitor_form_screen.dart';
import 'competitor_map.dart';
import 'competitor_widgets.dart';

/// The Competitors menu: every nearby developer project the team tracks,
/// as a list or on a map with our leads, with quick add.
class CompetitorsScreen extends StatefulWidget {
  /// Start with only the projects due for their re-check.
  final bool initialDueOnly;

  /// Show only these projects (e.g. the re-checks that fall to me).
  final Set<String>? onlyIds;
  final String? title;

  const CompetitorsScreen({
    super.key,
    this.initialDueOnly = false,
    this.onlyIds,
    this.title,
  });

  @override
  State<CompetitorsScreen> createState() => _CompetitorsScreenState();
}

enum _View { list, map }

class _CompetitorsScreenState extends State<CompetitorsScreen> {
  _View _view = _View.list;
  String _query = '';
  final Set<CompetitorStage> _stages = {};
  final Set<CompetitorType> _types = {};
  late bool _dueOnly = widget.initialDueOnly;

  @override
  void initState() {
    super.initState();
    CompetitorService.instance.addListener(_rebuild);
    CompetitorService.instance.ensureLoaded(force: true);
  }

  @override
  void dispose() {
    CompetitorService.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  List<CompetitorProject> _filtered(List<CompetitorProject> all) {
    final q = _query.trim().toLowerCase();
    final only = widget.onlyIds;
    return [
      for (final p in all)
        if ((only == null || only.contains(p.id)) &&
            (_stages.isEmpty || _stages.contains(p.stage)) &&
            (_types.isEmpty || _types.contains(p.type)) &&
            (!_dueOnly || p.recheckIsDue()) &&
            (q.isEmpty ||
                p.code.toLowerCase().contains(q) ||
                p.name.toLowerCase().contains(q) ||
                p.builder.toLowerCase().contains(q) ||
                p.village.toLowerCase().contains(q) ||
                p.taluk.toLowerCase().contains(q)))
          p,
    ];
  }

  Future<void> _add() async {
    final saved = await CompetitorFormScreen.open(context);
    if (saved != null && mounted) _open(saved);
  }

  void _open(CompetitorProject p) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CompetitorDetailScreen(projectId: p.id),
      ));

  void _openLead(LandLead l) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LeadDetailScreen(lead: l),
      ));

  @override
  Widget build(BuildContext context) {
    final svc = CompetitorService.instance;
    final only = widget.onlyIds;
    final all = [
      for (final p in svc.all)
        if (only == null || only.contains(p.id)) p,
    ];
    final shown = _filtered(all);
    final leads = AppStore.instance.visibleLeads;
    final due = all.where((p) => p.recheckIsDue()).length;
    final pad = FomraLayout.pagePadding(context);

    final header = Padding(
      padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title ?? 'Competitors',
                  style: TextStyle(
                      fontSize: FomraLayout.responsiveClamp(context, min: 20, max: 22),
                      fontWeight: FontWeight.w800,
                      color: context.fomraTextPrimary)),
              const SizedBox(height: 2),
              Text(
                'Developer projects near our sites: prices, plots sold and '
                'sales pace. Re-check each one every '
                '${CompetitorProject.recheckDays} days.',
                style: TextStyle(fontSize: 13, color: context.fomraTextSecondary),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          if (!FomraLayout.isMobile(context))
            FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add project'),
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search project, builder, village, code…',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SegmentedButton<_View>(
            segments: const [
              ButtonSegment(
                  value: _View.list,
                  icon: Icon(Icons.view_list_rounded),
                  label: Text('List')),
              ButtonSegment(
                  value: _View.map,
                  icon: Icon(Icons.map_outlined),
                  label: Text('Map')),
            ],
            selected: {_view},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _view = s.first),
          ),
        ]),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            FilterChip(
              avatar: const Icon(Icons.update_rounded, size: 16),
              label: Text('Re-check due  $due'),
              selected: _dueOnly,
              onSelected: (v) => setState(() => _dueOnly = v),
            ),
            const SizedBox(width: 8),
            for (final s in CompetitorStage.values) ...[
              FilterChip(
                label: Text(s.label),
                selected: _stages.contains(s),
                onSelected: (v) => setState(
                    () => v ? _stages.add(s) : _stages.remove(s)),
              ),
              const SizedBox(width: 8),
            ],
            for (final t in CompetitorType.values) ...[
              FilterChip(
                label: Text(t.label),
                selected: _types.contains(t),
                onSelected: (v) =>
                    setState(() => v ? _types.add(t) : _types.remove(t)),
              ),
              const SizedBox(width: 8),
            ],
          ]),
        ),
        const SizedBox(height: 10),
        Text(
          '${shown.length} of ${all.length} project${all.length == 1 ? '' : 's'}'
          '${shown.where((p) => p.point == null).isEmpty ? '' : ' · ${shown.where((p) => p.point == null).length} without a pin'}',
          style: TextStyle(fontSize: 12.5, color: context.fomraTextSecondary),
        ),
        const SizedBox(height: 10),
      ]),
    );

    Widget body;
    if (!svc.isLoaded) {
      body = svc.lastError != null
          ? Center(
              child: EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load the projects',
                message: '${svc.lastError}',
                action: FilledButton(
                  onPressed: () => svc.ensureLoaded(force: true),
                  child: const Text('Try again'),
                ),
              ),
            )
          : const Center(child: CircularProgressIndicator());
    } else if (_view == _View.map) {
      body = Padding(
        padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, pad.bottom),
        child: CompetitorMap(
          projects: shown,
          leads: leads,
          onOpenProject: _open,
          onOpenLead: _openLead,
        ),
      );
    } else if (shown.isEmpty) {
      body = ListView(padding: pad.copyWith(top: 0), children: [
        AppCard(
          child: EmptyState(
            icon: Icons.apartment_rounded,
            title: all.isEmpty ? 'No projects yet' : 'Nothing matches',
            message: all.isEmpty
                ? 'Add the first developer project near one of our sites.'
                : 'Try a different search or filter.',
            action: all.isEmpty
                ? FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add project'),
                  )
                : null,
          ),
        ),
      ]);
    } else {
      body = RefreshIndicator(
        onRefresh: () => svc.ensureLoaded(force: true),
        child: ListView.separated(
          padding: pad.copyWith(top: 0, bottom: pad.bottom + 80),
          itemCount: shown.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final p = shown[i];
            final near = nearestLead(p, leads);
            return CompetitorTile(
              project: p,
              trailingNote: near == null
                  ? null
                  : '${near.$2.toStringAsFixed(1)} km from #${near.$1.leadId}',
              onTap: () => _open(p),
            );
          },
        ),
      );
    }

    return FomraAppShell(
      currentRoute: '/competitors',
      appBar: const FomraAppBar(moduleName: 'Competitors'),
      floatingActionButton: FomraLayout.isMobile(context)
          ? FloatingActionButton.extended(
              onPressed: _add,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add project'),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, Expanded(child: body)],
      ),
    );
  }
}
