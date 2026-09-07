import 'package:flutter/material.dart';

import '../../models/land_lead.dart';
import '../../models/lead_list_filter.dart';
import '../../services/app_store.dart';
import '../../theme/fomra_layout.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/fomra_app_bar.dart';
import '../../widgets/fomra_breadcrumb.dart';
import '../../widgets/fomra_app_shell.dart';
import '../../widgets/ui/app_components.dart';
import 'lead_detail_screen.dart';

class FilteredLeadsScreen extends StatefulWidget {
  final LeadListFilter? filter;
  final List<LandLead>? presetLeads;
  final String? presetTitle;
  final String? presetSubtitle;

  const FilteredLeadsScreen({
    super.key,
    this.filter,
    this.presetLeads,
    this.presetTitle,
    this.presetSubtitle,
  });

  static void open(BuildContext context, LeadListFilter filter) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FilteredLeadsScreen(filter: filter),
      ),
    );
  }

  /// Open with an explicit set of leads (e.g. a dashboard box or donut slice)
  /// that doesn't map to a [LeadListFilter].
  static void openList(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<LandLead> leads,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FilteredLeadsScreen(
          presetLeads: List<LandLead>.from(leads),
          presetTitle: title,
          presetSubtitle: subtitle,
        ),
      ),
    );
  }

  @override
  State<FilteredLeadsScreen> createState() => _FilteredLeadsScreenState();
}

class _FilteredLeadsScreenState extends State<FilteredLeadsScreen> {
  String _search = '';

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

  bool _matchesSearch(LandLead l) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;
    return l.displayName.toLowerCase().contains(q) ||
        l.ownerName.toLowerCase().contains(q) ||
        l.leadId.toLowerCase().contains(q) ||
        l.location.toLowerCase().contains(q) ||
        l.village.toLowerCase().contains(q) ||
        l.taluk.toLowerCase().contains(q) ||
        l.district.toLowerCase().contains(q) ||
        l.surveyNumber.toLowerCase().contains(q) ||
        l.brokerName.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.filter;
    final title = widget.presetTitle ?? filter?.title ?? 'Leads';
    final subtitle = widget.presetSubtitle ?? filter?.subtitle ?? '';
    final allLeads = widget.presetLeads ??
        (filter != null
            ? filterLeads(AppStore.instance.visibleLeads, filter)
            : const <LandLead>[]);
    final leads = allLeads.where(_matchesSearch).toList();

    return FomraAppShell(
      currentRoute: '/land-lead',
      appBar: FomraAppBar(
        moduleName: title,
        // A filtered list (Negotiation, Legal, …) sits under Land Workspace.
        breadcrumbs: FomraBreadcrumbs.under(
          const [FomraBreadcrumbs.landWorkspace],
          title,
        ),
      ),
      backgroundColor: context.fomraPageBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: FomraLayout.pagePadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: title,
                  subtitle:
                      '${leads.length} lead${leads.length == 1 ? '' : 's'}'
                      '${allLeads.length == leads.length ? '' : ' of ${allLeads.length}'}'
                      '${subtitle.isEmpty ? '' : ' · $subtitle'}',
                  icon: Icons.list_alt_rounded,
                ),
                if (allLeads.length > 1) ...[
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (q) => setState(() => _search = q),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search within this list — name, village, '
                          'district, survey no…',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => setState(() => _search = ''),
                            ),
                      filled: true,
                      fillColor: context.fomraSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: context.fomraBorder),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: leads.isEmpty
                ? Center(
                    child: Text(
                      allLeads.isEmpty
                          ? 'No leads in this category yet.'
                          : 'No leads match "$_search".',
                      style: TextStyle(color: context.fomraTextSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: leads.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: context.fomraBorder.withValues(alpha: 0.7),
                    ),
                    itemBuilder: (_, index) {
                      final lead = leads[index];
                      return _FilteredLeadRow(
                        lead: lead,
                        // No trail passed: the lead detail names itself and the
                        // path (… > this filter > Lead X) comes from the stack.
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LeadDetailScreen(lead: lead),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilteredLeadRow extends StatelessWidget {
  final LandLead lead;
  final VoidCallback onTap;

  const _FilteredLeadRow({
    required this.lead,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = lead.displayName;
    final showId = title != 'Lead #${lead.leadId}';
    final location = [
      lead.location,
      lead.village,
      lead.district,
    ].where((s) => s.trim().isNotEmpty).join(', ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                    if (showId) ...[
                      const SizedBox(height: 2),
                      Text(
                        '#${lead.leadId}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: context.fomraTextSecondary,
                        ),
                      ),
                    ],
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        location,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.fomraTextSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: lead.status.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: lead.status.color.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Text(
                      lead.status.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: lead.status.color,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.fomraTextTertiary,
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
