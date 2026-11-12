import 'package:flutter/material.dart';

import '../analytics/monthly_target_progress.dart';
import '../models/land_lead.dart';
import '../screens/land_lead/filtered_leads_screen.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';

/// Home card: site visits (new Lead IDs) per executive for today, this week
/// (from Monday) and this month. Each number opens the properties behind it.
/// [leads] is already scoped to what the viewer may see; pass
/// [onlyExecutive] to show just that person (executives see their own row).
class SiteVisitSummary extends StatelessWidget {
  final List<LandLead> leads;
  final String? onlyExecutive;

  /// Tests: the "current" time.
  final DateTime? now;

  const SiteVisitSummary({
    super.key,
    required this.leads,
    this.onlyExecutive,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    final only = onlyExecutive?.trim().toLowerCase();
    final rows = SiteVisitPeriods.byExecutive(leads, now: now)
        .where((r) => only == null || r.executive.toLowerCase() == only)
        .toList();
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No site visits this month yet.',
          style: TextStyle(fontSize: 13.5, color: context.fomraTextSecondary),
        ),
      );
    }
    final showTotal = rows.length > 1;
    final total = SiteVisitPeriods(
      executive: 'Team total',
      today: [for (final r in rows) ...r.today],
      week: [for (final r in rows) ...r.week],
      month: [for (final r in rows) ...r.month],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeaderRow(),
        if (showTotal) _Row(row: total, emphasised: true),
        for (final r in rows) _Row(row: r),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    TextStyle s() => TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: context.fomraTextTertiary,
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(flex: 5, child: Text('EXECUTIVE', style: s())),
        Expanded(
            flex: 3,
            child: Text('TODAY', style: s(), textAlign: TextAlign.center)),
        Expanded(
            flex: 3,
            child: Text('THIS WEEK', style: s(), textAlign: TextAlign.center)),
        Expanded(
            flex: 3,
            child:
                Text('THIS MONTH', style: s(), textAlign: TextAlign.center)),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final SiteVisitPeriods row;
  final bool emphasised;
  const _Row({required this.row, this.emphasised = false});

  void _open(BuildContext context, String period, List<LandLead> leads) {
    if (leads.isEmpty) return;
    FilteredLeadsScreen.openList(
      context,
      title: 'Site visits · ${row.executive}',
      subtitle: '$period · new Lead IDs',
      leads: leads,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget cell(String period, List<LandLead> leads, Color color) => Expanded(
          flex: 3,
          child: Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: leads.isEmpty ? null : () => _open(context, period, leads),
              child: Container(
                constraints: const BoxConstraints(minWidth: 44),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: leads.isEmpty
                      ? Colors.transparent
                      : color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${leads.length}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: leads.isEmpty ? context.fomraTextTertiary : color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.fomraDivider)),
      ),
      child: Row(children: [
        Expanded(
          flex: 5,
          child: Text(
            row.executive,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: emphasised ? FontWeight.w800 : FontWeight.w700,
              color: context.fomraTextPrimary,
            ),
          ),
        ),
        cell('Today', row.today, AppColors.success),
        cell('This week', row.week, AppColors.info),
        cell('This month', row.month, AppColors.purple),
      ]),
    );
  }
}
