import 'package:flutter/material.dart';

import '../models/land_lead.dart';
import '../models/lead_review.dart';
import '../screens/land_lead/filtered_leads_screen.dart';
import '../services/lead_review_service.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';

/// Home dashboard card for reviewers (Management, Reporting Manager, Head):
/// how many active properties are overdue for review, due today, due this
/// week, never reviewed, and reviewed this week. Each tile opens the matching
/// list. Signed / Dropped properties are left out — they need no review.
class PropertyReviewSummary extends StatefulWidget {
  final List<LandLead> leads;
  const PropertyReviewSummary({super.key, required this.leads});

  /// The tiles, in the order shown.
  static const tiles = <ReviewFilter>[
    ReviewFilter.overdue,
    ReviewFilter.dueToday,
    ReviewFilter.dueThisWeek,
    ReviewFilter.notReviewed,
    ReviewFilter.reviewedThisWeek,
  ];

  @override
  State<PropertyReviewSummary> createState() => _PropertyReviewSummaryState();
}

class _PropertyReviewSummaryState extends State<PropertyReviewSummary> {
  @override
  void initState() {
    super.initState();
    LeadReviewIndex.instance.addListener(_rebuild);
    // Force: the dashboard is where people come back to check, so show
    // reviews saved on other devices rather than a cached snapshot.
    LeadReviewIndex.instance.ensureLoaded(force: true);
  }

  @override
  void dispose() {
    LeadReviewIndex.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  static (String, Color, IconData) _style(ReviewFilter f) => switch (f) {
        ReviewFilter.overdue => (
            'Overdue',
            AppColors.error,
            Icons.warning_amber_rounded
          ),
        ReviewFilter.dueToday => (
            'Due today',
            AppColors.warning,
            Icons.today_outlined
          ),
        ReviewFilter.dueThisWeek => (
            'Due this week',
            AppColors.info,
            Icons.date_range_outlined
          ),
        ReviewFilter.notReviewed => (
            'Not reviewed',
            AppColors.purple,
            Icons.help_outline_rounded
          ),
        ReviewFilter.reviewedThisWeek => (
            'Reviewed this week',
            AppColors.success,
            Icons.task_alt_rounded
          ),
        _ => (f.label, AppColors.primary, Icons.fact_check_outlined),
      };

  @override
  Widget build(BuildContext context) {
    final index = LeadReviewIndex.instance;
    final active =
        widget.leads.where((l) => !l.status.isTerminal).toList();
    final groups = {
      for (final f in PropertyReviewSummary.tiles)
        f: active.where((l) => f.matches(index.latestFor(l.leadId))).toList(),
    };

    return LayoutBuilder(
      builder: (context, c) {
        const gap = 10.0;
        final perRow = c.maxWidth >= 720 ? 5 : (c.maxWidth >= 420 ? 3 : 2);
        final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final f in PropertyReviewSummary.tiles)
              SizedBox(
                width: w,
                child: _ReviewTile(
                  label: _style(f).$1,
                  color: _style(f).$2,
                  icon: _style(f).$3,
                  // Until the first load lands, show a dash rather than a
                  // misleading 0 / "everything not reviewed".
                  value: index.isLoaded ? '${groups[f]!.length}' : '–',
                  onTap: !index.isLoaded
                      ? null
                      : () => FilteredLeadsScreen.openList(
                            context,
                            title: 'Reviews · ${_style(f).$1}',
                            subtitle: 'Active properties — ${f.label.toLowerCase()}',
                            leads: groups[f]!,
                            hideReviewFilter: true,
                          ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  const _ReviewTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: context.fomraTextSecondary,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
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
