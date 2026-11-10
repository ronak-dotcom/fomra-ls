import 'package:flutter/material.dart';

import '../../models/land_lead.dart';
import '../../models/lead_follow_up.dart';
import '../../models/lead_review.dart';
import '../../services/lead_review_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/lead_location_parser.dart';
import '../../utils/maps_navigation.dart';
import '../../widgets/ui/app_feedback.dart';
import 'property_review_dialog.dart';
import '../../widgets/land_workspace_ui.dart';
import '../../widgets/lead_filter_bar.dart';
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

  /// Set when the list itself is a review-status list (dashboard review
  /// boxes). The list then stays live against that status — a property
  /// reviewed from here leaves e.g. the Overdue list — rows show review
  /// details and a Review button, and the Filters panel omits Property
  /// Review, which could only contradict the list.
  final ReviewFilter? reviewFilter;

  const FilteredLeadsScreen({
    super.key,
    this.filter,
    this.presetLeads,
    this.presetTitle,
    this.presetSubtitle,
    this.reviewFilter,
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
    ReviewFilter? reviewFilter,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FilteredLeadsScreen(
          presetLeads: List<LandLead>.from(leads),
          presetTitle: title,
          presetSubtitle: subtitle,
          reviewFilter: reviewFilter,
        ),
      ),
    );
  }

  @override
  State<FilteredLeadsScreen> createState() => _FilteredLeadsScreenState();
}

class _FilteredLeadsScreenState extends State<FilteredLeadsScreen> {
  String _search = '';
  final LandWorkspaceFilters _filters = LandWorkspaceFilters();

  @override
  void initState() {
    super.initState();
    AppStore.instance.addListener(_rebuild);
    LeadReviewIndex.instance.addListener(_rebuild);
  }

  @override
  void dispose() {
    AppStore.instance.removeListener(_rebuild);
    LeadReviewIndex.instance.removeListener(_rebuild);
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
    final reviewFilter = widget.reviewFilter;
    final allLeads = (widget.presetLeads ??
            (filter != null
                ? filterLeads(AppStore.instance.visibleLeads, filter)
                : const <LandLead>[]))
        .where((l) =>
            reviewFilter == null ||
            reviewFilter
                .matches(LeadReviewIndex.instance.latestFor(l.leadId)))
        .toList();
    final leads = allLeads
        .where((l) => _filters.matches(l) && _matchesSearch(l))
        .toList();

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
                if (allLeads.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  LeadFilterBar(
                    filters: _filters,
                    onChanged: () => setState(() {}),
                    onSearch: (q) => setState(() => _search = q),
                    hintText: 'Search within this list — name, village, '
                        'district, survey no…',
                    showReviewStatus: widget.reviewFilter == null,
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
                          : 'No leads match the search or filters.',
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
                        showReview: reviewFilter != null,
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

  /// Review lists: show the latest review (date, by, note, next date) and a
  /// Review button, so a property can be reviewed without opening it.
  final bool showReview;

  const _FilteredLeadRow({
    required this.lead,
    required this.onTap,
    this.showReview = false,
  });

  /// Who is working the lead now: the assignee, else whoever created it.
  String get _executive => lead.assignedToName.trim().isNotEmpty
      ? lead.assignedToName.trim()
      : lead.createdByName.trim();

  Future<void> _openMap(BuildContext context) async {
    final ok = await MapsNavigation.navigateFromGpsString(
      lead.gpsCoordinates,
      label: lead.displayName,
    );
    if (!ok && context.mounted) {
      AppFeedback.warning(context, 'No map location saved for this property');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = lead.displayName;
    final showId = title != 'Lead #${lead.leadId}';
    final location = [
      lead.location,
      lead.village,
      lead.district,
    ].where((s) => s.trim().isNotEmpty).join(', ');
    final hasMap = parseLeadGps(lead.gpsCoordinates) != null;
    final review =
        showReview ? LeadReviewIndex.instance.latestFor(lead.leadId) : null;
    final canReview = showReview && LeadReviewService.canReview;
    final secondary = TextStyle(fontSize: 12, color: context.fomraTextSecondary);

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
                        style: secondary,
                      ),
                    ],
                    if (_executive.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.person_outline_rounded,
                            size: 14, color: context.fomraTextSecondary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Executive: $_executive',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: secondary.copyWith(
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ]),
                    ],
                    if (showReview) ...[
                      const SizedBox(height: 8),
                      _ReviewSummary(review: review),
                    ],
                    if (hasMap || canReview) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (hasMap)
                            OutlinedButton.icon(
                              onPressed: () => _openMap(context),
                              icon: const Icon(Icons.map_outlined, size: 16),
                              label: const Text('Map'),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                textStyle: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                          if (canReview)
                            FilledButton.icon(
                              onPressed: () => showPropertyReviewDialog(
                                  context, lead.leadId),
                              icon: const Icon(Icons.task_alt_rounded,
                                  size: 16),
                              label: const Text('Review'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.purple,
                                visualDensity: VisualDensity.compact,
                                textStyle: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                        ],
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

/// Latest review at a glance: when and by whom, next review date (with an
/// overdue / due-today flag), and the note.
class _ReviewSummary extends StatelessWidget {
  final LeadReview? review;
  const _ReviewSummary({required this.review});

  @override
  Widget build(BuildContext context) {
    final r = review;
    final secondary = TextStyle(fontSize: 12, color: context.fomraTextSecondary);
    if (r == null) {
      return Text('Not reviewed yet',
          style: secondary.copyWith(fontStyle: FontStyle.italic));
    }
    final by = r.reviewedBy.trim();
    final next = r.nextReviewLabel;
    final (String? flag, Color flagColor) = r.isOverdue
        ? ('Overdue ${-(r.daysUntilNext ?? 0)}d', AppColors.error)
        : r.isDueToday
            ? ('Due today', AppColors.warning)
            : (null, AppColors.success);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: context.fomraSurfaceVar.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.fomraBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Last reviewed ${LeadFollowUp.formatDate(r.reviewedAt)}'
                '${by.isEmpty ? '' : ' by $by'}',
                style: secondary.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.fomraTextPrimary),
              ),
              Text('Next: ${next ?? 'not set'}', style: secondary),
              if (flag != null)
                Text(flag,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: flagColor)),
            ],
          ),
          if (r.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              r.notes.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: secondary,
            ),
          ],
        ],
      ),
    );
  }
}
