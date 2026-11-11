import 'package:flutter/material.dart';

import '../../models/land_lead.dart';
import '../../services/broker_directory.dart';
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
        l.brokerName.toLowerCase().contains(q) ||
        l.brokerDisplayName.toLowerCase().contains(q);
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
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: leads.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
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
    // Location, village and district often repeat each other; keep each
    // comma-separated part once.
    final seen = <String>{};
    final location = [lead.location, lead.village, lead.district]
        .expand((s) => s.split(','))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && seen.add(s.toLowerCase()))
        .join(', ');
    final hasMap = parseLeadGps(lead.gpsCoordinates) != null;
    final review =
        showReview ? LeadReviewIndex.instance.latestFor(lead.leadId) : null;
    final canReview = showReview && LeadReviewService.canReview;
    // Keep the app font (Inter) — a bare TextStyle here would drop it.
    final buttonText = Theme.of(context)
        .textTheme
        .labelLarge
        ?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700);
    // On phones the stage chip moves under the title so long names get the
    // full width instead of breaking mid-word.
    final narrow = MediaQuery.sizeOf(context).width < 560;

    return Container(
      decoration: BoxDecoration(
        color: context.fomraSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.fomraBorder),
        boxShadow: context.fomraCardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Name + stage ─────────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          color: context.fomraTextPrimary,
                        ),
                      ),
                    ),
                    if (!narrow) ...[
                      const SizedBox(width: 10),
                      _StageChip(status: lead.status),
                    ],
                    Icon(Icons.chevron_right_rounded,
                        color: context.fomraTextTertiary),
                  ],
                ),
                const SizedBox(height: 8),
                // ── ID · location · executive ───────────────────────────
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (narrow) _StageChip(status: lead.status),
                    if (showId) _IdTag(id: lead.leadId),
                    if (location.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.place_outlined,
                              size: 15, color: context.fomraTextTertiary),
                          const SizedBox(width: 3),
                          // Flexible, not a fixed cap: shrinks to the card
                          // width on phones and ends in "…".
                          Flexible(
                            child: Text(
                              location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: context.fomraTextSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (_executive.isNotEmpty) _ExecutiveTag(name: _executive),
                  ],
                ),
                if (showReview) ...[
                  const SizedBox(height: 12),
                  _ReviewSummary(review: review),
                ],
                if (hasMap || canReview) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (hasMap)
                        OutlinedButton.icon(
                          onPressed: () => _openMap(context),
                          icon: const Icon(Icons.map_outlined, size: 16),
                          label: const Text('Map'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.info,
                            side: BorderSide(
                                color: AppColors.info.withValues(alpha: 0.4)),
                            visualDensity: VisualDensity.compact,
                            textStyle: buttonText,
                          ),
                        ),
                      if (canReview)
                        FilledButton.icon(
                          onPressed: () =>
                              showPropertyReviewDialog(context, lead.leadId),
                          icon: const Icon(Icons.task_alt_rounded, size: 16),
                          label: const Text('Review'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.purple,
                            visualDensity: VisualDensity.compact,
                            textStyle: buttonText,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StageChip extends StatelessWidget {
  final LeadStatus status;
  const _StageChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: status.color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: status.color,
        ),
      ),
    );
  }
}

/// Lead number as a small neutral tag.
class _IdTag extends StatelessWidget {
  final String id;
  const _IdTag({required this.id});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: context.fomraSurfaceVar,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '#$id',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: context.fomraTextSecondary,
        ),
      ),
    );
  }
}

/// Executive name in its own coloured tag so it is easy to pick out.
class _ExecutiveTag extends StatelessWidget {
  final String name;
  const _ExecutiveTag({required this.name});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Executive',
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 3, 9, 3),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_rounded, size: 14, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(
              name,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Latest review at a glance, on a panel whose left edge shows its state:
/// red overdue, amber due today, green on track, grey never reviewed.
class _ReviewSummary extends StatelessWidget {
  final LeadReview? review;
  const _ReviewSummary({required this.review});

  @override
  Widget build(BuildContext context) {
    final r = review;
    final Color accent = r == null
        ? context.fomraTextTertiary
        : r.isOverdue
            ? AppColors.error
            : r.isDueToday
                ? AppColors.warning
                : AppColors.success;

    final label = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: context.fomraTextTertiary,
    );
    final value = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      color: context.fomraTextPrimary,
    );

    Widget content;
    if (r == null) {
      content = Text(
        'Not reviewed yet',
        style: value.copyWith(color: context.fomraTextSecondary),
      );
    } else {
      final by = r.reviewedBy.trim();
      final String? flag = r.isOverdue
          ? 'Overdue ${-(r.daysUntilNext ?? 0)}d'
          : r.isDueToday
              ? 'Due today'
              : null;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LAST REVIEWED', style: label),
                  const SizedBox(height: 3),
                  Text.rich(TextSpan(children: [
                    TextSpan(
                        text: LeadFollowUp.formatDate(r.reviewedAt),
                        style: value),
                    if (by.isNotEmpty) ...[
                      TextSpan(
                        text: '  by ',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: context.fomraTextSecondary),
                      ),
                      TextSpan(
                        text: by,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.purple,
                        ),
                      ),
                    ],
                  ])),
                ],
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NEXT REVIEW', style: label),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(r.nextReviewLabel ?? 'Not set', style: value),
                      if (flag != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            flag,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
          if (r.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.format_quote_rounded,
                    size: 16, color: context.fomraTextTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    r.notes.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      fontStyle: FontStyle.italic,
                      color: context.fomraTextPrimary.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        color: accent.withValues(alpha: 0.06),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: content,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
