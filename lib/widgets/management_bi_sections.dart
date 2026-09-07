import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../analytics/management_bi_metrics.dart';
import '../models/land_lead.dart';
import '../screens/land_lead/filtered_leads_screen.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';
import 'ui/app_components.dart';

const _kBiCardRadius = 20.0;

class BiSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final Color? accent;
  final Widget? trailing;

  const BiSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.child,
    this.accent,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.primary;
    return AppCard(
      padding: const EdgeInsets.all(14),
      radius: _kBiCardRadius,
      interactive: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.fomraTextSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

String biFormatAcres(double acres) {
  if (acres >= 100) return acres.toStringAsFixed(0);
  if (acres >= 10) return acres.toStringAsFixed(1);
  return acres.toStringAsFixed(2);
}

String biFormatPct(double pct) => '${pct.round()}%';

// ── 1. Pipeline ─────────────────────────────────────────────────────────────

class BiPipelineSection extends StatelessWidget {
  final BiPipelineSummary summary;
  final List<LandLead> leads;

  const BiPipelineSection({
    super.key,
    required this.summary,
    this.leads = const [],
  });

  void _open(
    BuildContext context,
    String title,
    String subtitle,
    List<LandLead> subset,
  ) {
    FilteredLeadsScreen.openList(
      context,
      title: title,
      subtitle: subtitle,
      leads: subset,
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = leads.where((l) => l.status.isActive).toList();
    // Pipeline Acres lists only the mid/late pipeline stages — a lead whose land
    // owner meeting is still pending isn't counted as being in the pipeline yet.
    const pipelineStages = {
      LeadStatus.prospectMeetingCompleted,
      LeadStatus.negotiation,
      LeadStatus.legal,
      LeadStatus.managementMeetingCompleted,
    };
    final pipeline =
        leads.where((l) => pipelineStages.contains(l.status)).toList();
    final signed =
        leads.where((l) => l.status == LeadStatus.signed).toList();
    final tappable = leads.isNotEmpty;

    final tiles = [
        _PipeTile('Total Leads', '${summary.totalLeads}', Icons.hub_outlined,
          AppColors.primary,
          onTap: tappable
              ? () => _open(context, 'Total Leads', 'Every lead', leads)
              : null),
      _PipeTile('Total Acres', biFormatAcres(summary.totalAcres),
          Icons.landscape_outlined, AppColors.success,
          onTap: tappable
              ? () => _open(context, 'Total Acres', 'All leads', leads)
              : null),
      _PipeTile('Pipeline Acres', biFormatAcres(summary.pipelineAcres),
          Icons.stacked_bar_chart_rounded, AppColors.info,
          onTap: tappable
              ? () => _open(
                  context, 'Pipeline Acres', 'Active pipeline leads', pipeline)
              : null),
      _PipeTile('Active Deals', '${summary.activeDeals}',
          Icons.trending_up_rounded, AppColors.warning,
          onTap: tappable
              ? () =>
                  _open(context, 'Active Deals', 'Active pipeline leads', active)
              : null),
      _PipeTile('Closed Deals', '${summary.closedDeals}',
          Icons.verified_outlined, const Color(0xFF10B981),
          onTap: tappable
              ? () => _open(context, 'Closed Deals', 'Signed leads', signed)
              : null),
    ];

    return BiSectionCard(
      title: 'Pipeline Dashboard',
      subtitle: 'Portfolio snapshot across the sourcing funnel',
      icon: Icons.dashboard_customize_outlined,
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 720;
          if (wide) {
            return Row(
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: tiles[i]),
                ],
              ],
            );
          }
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in tiles)
                SizedBox(
                  width: (c.maxWidth - 10) / 2,
                  child: t,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PipeTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  const _PipeTile(this.label, this.value, this.icon, this.accent,
      {this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    final decoration = BoxDecoration(
      color: context.fomraSurfaceVar.withValues(alpha: 0.55),
      borderRadius: radius,
      border: Border.all(color: context.fomraBorder),
    );
    final content = Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 14, color: accent),
                ),
                const Spacer(),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: context.fomraTextPrimary,
                    height: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: context.fomraTextPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Tap for leads',
              style: TextStyle(
                fontSize: 10.5,
                color: context.fomraTextSecondary,
              ),
            ),
          ],
        ),
      );

    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: content);
    }
    // A real InkWell (not a bare GestureDetector) so the tile shows a pointer
    // cursor + press feedback on web and the tap is reliable inside scrolls.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Ink(decoration: decoration, child: content),
        ),
      ),
    );
  }
}

// ── 2. Conversion Funnel ────────────────────────────────────────────────────

class BiFunnelSection extends StatelessWidget {
  final List<BiFunnelStageRow> rows;

  const BiFunnelSection({super.key, required this.rows});
  @override
  Widget build(BuildContext context) {
    final maxCount =
        rows.fold<int>(0, (m, r) => r.leadCount > m ? r.leadCount : m);
    return BiSectionCard(
      title: 'Conversion Funnel',
      subtitle: 'Lead count, acres, conversion and drop-off by stage',
      icon: Icons.filter_alt_outlined,
      accent: AppColors.secondary,
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FunnelRow(
                row: row,
                maxCount: maxCount == 0 ? 1 : maxCount,
              ),
            ),
        ],
      ),
    );
  }
}

class _FunnelRow extends StatelessWidget {
  final BiFunnelStageRow row;
  final int maxCount;

  const _FunnelRow({required this.row, required this.maxCount});

  @override
  Widget build(BuildContext context) {
    final isDropped = row.stage == BiFunnelStage.dropped;
    final barColor = isDropped ? AppColors.error : AppColors.primary;
    final widthFactor = (row.leadCount / maxCount).clamp(0.04, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                row.stage.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.fomraTextPrimary,
                ),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: widthFactor,
                  minHeight: 10,
                  backgroundColor: context.fomraSurfaceVar,
                  color: barColor.withValues(alpha: 0.85),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 28,
              child: Text(
                '${row.leadCount}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: context.fomraTextPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 92),
          child: Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              _MetaChip('${biFormatAcres(row.acres)} ac'),
              _MetaChip('Conv ${biFormatPct(row.conversionPct)}'),
              _MetaChip(
                'Drop ${biFormatPct(row.dropOffPct)}',
                tone: row.dropOffPct > 25 ? AppColors.error : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String text;
  final Color? tone;

  const _MetaChip(this.text, {this.tone});

  @override
  Widget build(BuildContext context) {
    final c = tone ?? context.fomraTextSecondary;
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: c,
      ),
    );
  }
}

// ── 3. Lead Ageing ──────────────────────────────────────────────────────────

class BiAgeingSection extends StatelessWidget {
  final List<BiAgeBucketRow> rows;
  final ValueChanged<LandLead>? onViewLead;

  const BiAgeingSection({
    super.key,
    required this.rows,
    this.onViewLead,
  });

  @override
  Widget build(BuildContext context) {
    return BiSectionCard(
      title: 'Site Ageing',
      subtitle: 'Open deals by age — 90+ days highlighted as overdue',
      icon: Icons.hourglass_bottom_rounded,
      accent: AppColors.warning,
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth >= 720 ? 4 : 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final row in rows)
                SizedBox(
                  width: (c.maxWidth - 10 * (cols - 1)) / cols,
                  child: _AgeTile(row: row, onViewLead: onViewLead),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AgeTile extends StatelessWidget {
  final BiAgeBucketRow row;
  final ValueChanged<LandLead>? onViewLead;

  const _AgeTile({required this.row, this.onViewLead});

  @override
  Widget build(BuildContext context) {
    final overdue = row.bucket.isOverdue;
    final accent = overdue ? AppColors.error : AppColors.warning;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: row.leads.isEmpty
            ? null
            : () => FilteredLeadsScreen.openList(
                  context,
                  title: 'Site Ageing — ${row.bucket.label}',
                  subtitle: '${row.leads.length} lead${row.leads.length == 1 ? '' : 's'}',
                  leads: row.leads,
                ),
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: overdue ? 0.12 : 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: accent.withValues(alpha: overdue ? 0.45 : 0.22),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.bucket.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: context.fomraTextSecondary,
                      ),
                    ),
                  ),
                  if (overdue)
                    const Text(
                      'OVERDUE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.error,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${row.leadCount}',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: context.fomraTextPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${biFormatAcres(row.acres)} ac',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.fomraTextSecondary,
                      ),
                    ),
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

// ── 4. Bottlenecks ──────────────────────────────────────────────────────────

class BiBottleneckSection extends StatelessWidget {
  final List<BiBottleneckRow> rows;

  const BiBottleneckSection({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return BiSectionCard(
      title: 'Bottleneck Dashboard',
      subtitle: 'Automatically detected stalls with average pending days',
      icon: Icons.warning_amber_rounded,
      accent: AppColors.error,
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.fomraSurfaceVar.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.fomraBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: context.fomraTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Avg ${row.avgPendingDays.toStringAsFixed(1)} days pending',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.fomraTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: (row.count > 0
                                ? AppColors.error
                                : AppColors.success)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${row.count}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: row.count > 0
                              ? AppColors.error
                              : AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 5. Executive Performance ────────────────────────────────────────────────

class BiExecutiveSection extends StatelessWidget {
  final List<BiExecutiveRow> rows;

  const BiExecutiveSection({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return BiSectionCard(
      title: 'Executive Performance',
      subtitle: 'Ranked by conversion — pipeline and activity depth',
      icon: Icons.emoji_events_outlined,
      accent: AppColors.warning,
      child: rows.isEmpty
          ? Text(
              'No executive-owned leads yet.',
              style: TextStyle(color: context.fomraTextSecondary),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 44,
                dataRowMaxHeight: 56,
                dividerThickness: 1,
                headingRowColor:
                    WidgetStateProperty.all(context.fomraSurfaceVar),
                headingTextStyle:
                    Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: context.fomraTextSecondary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('EXECUTIVE')),
                  DataColumn(label: Text('ASSIGNED'), numeric: true),
                  DataColumn(label: Text('CONVERTED'), numeric: true),
                  DataColumn(label: Text('PIPELINE AC'), numeric: true),
                  DataColumn(label: Text('CONV %'), numeric: true),
                  DataColumn(label: Text('AVG CLOSE D'), numeric: true),
                  DataColumn(label: Text('MEETINGS'), numeric: true),
                  DataColumn(label: Text('VISITS'), numeric: true),
                  DataColumn(label: Text('LEGAL'), numeric: true),
                  DataColumn(label: Text('AGREEMENTS'), numeric: true),
                ],
                rows: [
                  for (final entry
                      in rows.take(15).toList().asMap().entries)
                    DataRow(
                      color: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.hovered)) {
                          return AppColors.primary.withValues(alpha: 0.06);
                        }
                        return entry.key.isOdd
                            ? context.fomraSurfaceVar.withValues(alpha: 0.4)
                            : null;
                      }),
                      cells: [
                        DataCell(Text('${entry.value.rank}')),
                        DataCell(Text(
                          entry.value.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        )),
                        DataCell(Text('${entry.value.assignedLeads}')),
                        DataCell(Text('${entry.value.convertedLeads}')),
                        DataCell(Text(biFormatAcres(entry.value.pipelineAcres))),
                        DataCell(Text(biFormatPct(entry.value.conversionPct))),
                        DataCell(Text(
                            entry.value.avgClosingDays.toStringAsFixed(0))),
                        DataCell(Text('${entry.value.meetings}')),
                        DataCell(Text('${entry.value.siteVisits}')),
                        DataCell(Text('${entry.value.legalCount}')),
                        DataCell(Text('${entry.value.agreementSuccess}')),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

// ── 6. Activity Heat Map ────────────────────────────────────────────────────

class BiHeatmapSection extends StatelessWidget {
  final List<BiVillageHeatRow> rows;

  const BiHeatmapSection({super.key, required this.rows});

  Color _color(BiHeatLevel level) => switch (level) {
        BiHeatLevel.active => const Color(0xFF10B981),
        BiHeatLevel.moderate => const Color(0xFFF59E0B),
        BiHeatLevel.idle => const Color(0xFFEF4444),
      };

  @override
  Widget build(BuildContext context) {
    return BiSectionCard(
      title: 'Activity Heat Map',
      subtitle: 'Village-wise activity — green active · yellow moderate · red idle',
      icon: Icons.map_outlined,
      accent: const Color(0xFF06B6D4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final level in BiHeatLevel.values) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _color(level),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  level.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.fomraTextSecondary,
                  ),
                ),
                const SizedBox(width: 14),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(
              'No village data yet.',
              style: TextStyle(color: context.fomraTextSecondary),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final row in rows.take(36))
                  Container(
                    width: 150,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _color(row.level).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _color(row.level).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.village,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: context.fomraTextPrimary,
                          ),
                        ),
                        if (row.district.isNotEmpty)
                          Text(
                            row.district,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.fomraTextSecondary,
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          '${row.leadCount} leads · ${row.daysSinceActivity}d',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _color(row.level),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── 7. SLA Dashboard ────────────────────────────────────────────────────────

class BiSlaSection extends StatelessWidget {
  final BiSlaSummary summary;
  final ValueChanged<LandLead>? onViewLead;

  const BiSlaSection({
    super.key,
    required this.summary,
    this.onViewLead,
  });

  @override
  Widget build(BuildContext context) {
    return BiSectionCard(
      title: 'SLA Dashboard',
      subtitle: 'First call · site visit · survey · legal · agreement deadlines',
      icon: Icons.timer_outlined,
      accent: AppColors.primary,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _SlaStat(
                  label: 'Due Today',
                  count: summary.dueToday.length,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SlaStat(
                  label: 'Upcoming',
                  count: summary.upcoming.length,
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SlaStat(
                  label: 'Overdue',
                  count: summary.overdue.length,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SlaList(
            title: 'Overdue',
            items: summary.overdue.take(8).toList(),
            color: AppColors.error,
            onViewLead: onViewLead,
          ),
          _SlaList(
            title: 'Due today',
            items: summary.dueToday.take(6).toList(),
            color: AppColors.warning,
            onViewLead: onViewLead,
          ),
          _SlaList(
            title: 'Upcoming',
            items: summary.upcoming.take(6).toList(),
            color: AppColors.info,
            onViewLead: onViewLead,
          ),
        ],
      ),
    );
  }
}

class _SlaStat extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SlaStat({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.fomraTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SlaList extends StatelessWidget {
  final String title;
  final List<BiSlaItem> items;
  final Color color;
  final ValueChanged<LandLead>? onViewLead;

  const _SlaList({
    required this.title,
    required this.items,
    required this.color,
    this.onViewLead,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          for (final item in items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              onTap: onViewLead == null
                  ? null
                  : () => onViewLead!(item.lead),
              title: Text(
                '${item.kind.label} · ${item.lead.displayName}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('#${item.lead.leadId} · ${item.ageDays}d old'),
              trailing: Text(
                item.daysRemaining < 0
                    ? '${-item.daysRemaining}d late'
                    : item.daysRemaining == 0
                        ? 'Today'
                        : '${item.daysRemaining}d left',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Mini funnel chart (optional visual) ─────────────────────────────────────

class BiFunnelSparkChart extends StatelessWidget {
  final List<BiFunnelStageRow> rows;

  const BiFunnelSparkChart({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final data = rows
        .where((r) => r.stage != BiFunnelStage.dropped)
        .toList();
    if (data.isEmpty) return const SizedBox.shrink();
    final maxY =
        data.fold<int>(0, (m, r) => r.leadCount > m ? r.leadCount : m) + 1.0;

    return SizedBox(
      height: 160,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= data.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      data[i].stage.label.split(' ').first,
                      style: TextStyle(
                        fontSize: 9,
                        color: context.fomraTextTertiary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < data.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: data[i].leadCount.toDouble(),
                    width: 12,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(4)),
                    color: AppColors.primary.withValues(alpha: 0.8),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
