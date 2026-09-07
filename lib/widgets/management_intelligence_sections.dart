import 'package:flutter/material.dart';

import '../analytics/management_intelligence.dart';
import '../models/land_lead.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';
import 'management_bi_sections.dart';

const _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

class IntelDisclaimer extends StatelessWidget {
  const IntelDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Recommendations only — lead data is never changed automatically.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.fomraTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reminders ───────────────────────────────────────────────────────────────

class IntelRemindersSection extends StatelessWidget {
  final List<IntelReminderItem> items;
  final ValueChanged<LandLead>? onViewLead;

  const IntelRemindersSection({
    super.key,
    required this.items,
    this.onViewLead,
  });

  @override
  Widget build(BuildContext context) {
    return BiSectionCard(
      title: 'Automatic Reminders',
      subtitle: 'Activity gaps and pending stage signals',
      icon: Icons.notifications_active_outlined,
      accent: AppColors.warning,
      trailing: Text(
        '${items.length}',
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.warning,
        ),
      ),
      child: Column(
        children: [
          const IntelDisclaimer(),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Text(
              'No reminders right now.',
              style: TextStyle(color: context.fomraTextSecondary),
            )
          else
            for (final item in items.take(12))
              _IntelRow(
                title: item.kind.label,
                subtitle:
                    'Lead #${item.lead.leadId} · ${item.detail} · ${item.daysStale}d',
                color: AppColors.warning,
                onTap: onViewLead == null
                    ? null
                    : () => onViewLead!(item.lead),
              ),
        ],
      ),
    );
  }
}

// ── Escalations ─────────────────────────────────────────────────────────────

class IntelEscalationsSection extends StatelessWidget {
  final List<IntelEscalationItem> items;
  final ValueChanged<LandLead>? onViewLead;

  const IntelEscalationsSection({
    super.key,
    required this.items,
    this.onViewLead,
  });

  @override
  Widget build(BuildContext context) {
    return BiSectionCard(
      title: 'Automatic Escalations',
      subtitle: 'Overdue approvals flagged for management attention',
      icon: Icons.priority_high_rounded,
      accent: AppColors.error,
      child: Column(
        children: [
          const IntelDisclaimer(),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Text(
              'No escalations.',
              style: TextStyle(color: context.fomraTextSecondary),
            )
          else
            for (final item in items.take(10))
              _IntelRow(
                title: item.reason,
                subtitle:
                    'Lead #${item.lead.leadId} · ${item.overdueDays}d overdue',
                color: AppColors.error,
                onTap: onViewLead == null
                    ? null
                    : () => onViewLead!(item.lead),
              ),
        ],
      ),
    );
  }
}

// ── Approval Queue ──────────────────────────────────────────────────────────

class IntelApprovalQueueSection extends StatelessWidget {
  final List<IntelApprovalItem> items;
  final ValueChanged<LandLead>? onViewLead;

  const IntelApprovalQueueSection({
    super.key,
    required this.items,
    this.onViewLead,
  });

  @override
  Widget build(BuildContext context) {
    final survey =
        items.where((i) => i.kind == IntelApprovalKind.survey).length;
    final legal =
        items.where((i) => i.kind == IntelApprovalKind.legal).length;
    final docs =
        items.where((i) => i.kind == IntelApprovalKind.documents).length;
    final visits = items
        .where((i) => i.kind == IntelApprovalKind.managementVisit)
        .length;

    return BiSectionCard(
      title: 'Approval Queue',
      subtitle: 'Survey · Legal · Documents · Management visits',
      icon: Icons.fact_check_outlined,
      accent: AppColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const IntelDisclaimer(),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _CountChip('Survey', survey, AppColors.warning)),
              const SizedBox(width: 8),
              Expanded(child: _CountChip('Legal', legal, AppColors.secondary)),
              const SizedBox(width: 8),
              Expanded(child: _CountChip('Docs', docs, AppColors.info)),
              const SizedBox(width: 8),
              Expanded(
                  child: _CountChip('Visits', visits, AppColors.primary)),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text(
              'Approval queue is clear.',
              style: TextStyle(color: context.fomraTextSecondary),
            )
          else
            for (final item in items.take(12))
              _IntelRow(
                title: '${item.kind.label} · ${item.lead.displayName}',
                subtitle:
                    '#${item.lead.leadId} · ${item.detail} · ${item.pendingDays}d pending',
                color: AppColors.secondary,
                onTap: onViewLead == null
                    ? null
                    : () => onViewLead!(item.lead),
              ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _CountChip(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.fomraTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Duplicates ──────────────────────────────────────────────────────────────

class IntelDuplicatesSection extends StatelessWidget {
  final List<IntelDuplicateGroup> groups;
  final ValueChanged<LandLead>? onViewLead;

  const IntelDuplicatesSection({
    super.key,
    required this.groups,
    this.onViewLead,
  });

  @override
  Widget build(BuildContext context) {
    return BiSectionCard(
      title: 'Duplicate Detection',
      subtitle: 'Owner · Mobile · Survey · Village · Location',
      icon: Icons.copy_all_outlined,
      accent: AppColors.error,
      child: Column(
        children: [
          const IntelDisclaimer(),
          const SizedBox(height: 10),
          if (groups.isEmpty)
            Text(
              'No likely duplicates found.',
              style: TextStyle(color: context.fomraTextSecondary),
            )
          else
            for (final g in groups.take(8))
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.fomraSurfaceVar.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.fomraBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Match: ${g.matchFields.join(', ')} · ${g.leads.length} leads',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final lead in g.leads)
                          ActionChip(
                            label: Text(lead.displayName),
                            onPressed: onViewLead == null
                                ? null
                                : () => onViewLead!(lead),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// ── Predictive analytics ────────────────────────────────────────────────────

class IntelPredictiveSection extends StatelessWidget {
  final IntelPredictiveAnalytics data;

  const IntelPredictiveSection({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return BiSectionCard(
      title: 'Predictive Analytics',
      subtitle: 'Villages · executives · negotiation · seasonality · closing',
      icon: Icons.insights_outlined,
      accent: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const IntelDisclaimer(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  label: 'Avg negotiation',
                  value: '${data.avgNegotiationDays.toStringAsFixed(0)}d',
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatBox(
                  label: 'Expected closing',
                  value: '${data.expectedClosingDays.toStringAsFixed(0)}d',
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Best performing villages',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: context.fomraTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          if (data.bestVillages.isEmpty)
            Text('Not enough village data yet.',
                style: TextStyle(color: context.fomraTextSecondary))
          else
            for (final v in data.bestVillages.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        v.village,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${v.signed}/${v.total} · ${v.conversionPct.round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.fomraTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 12),
          Text(
            'Fastest closing executives',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: context.fomraTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          if (data.fastestExecutives.isEmpty)
            Text('No closed deals yet.',
                style: TextStyle(color: context.fomraTextSecondary))
          else
            for (final e in data.fastestExecutives.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${e.closed} closed · avg ${e.avgClosingDays.toStringAsFixed(0)}d',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.fomraTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 12),
          Text(
            'Seasonal trends (leads added / closed by month)',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: context.fomraTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in data.seasonalTrends)
                if (p.leadsAdded > 0 || p.closed > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: context.fomraSurfaceVar,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.fomraBorder),
                    ),
                    child: Text(
                      '${_kMonths[p.month - 1]} +${p.leadsAdded}/✓${p.closed}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatBox({
    required this.label,
    required this.value,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
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

// ── Best suggestions + AI recommendations ───────────────────────────────────

class IntelSuggestionsSection extends StatelessWidget {
  final List<IntelRecommendation> recommendations;
  final ValueChanged<LandLead>? onViewLead;

  const IntelSuggestionsSection({
    super.key,
    required this.recommendations,
    this.onViewLead,
  });

  @override
  Widget build(BuildContext context) {
    final nextActions = recommendations
        .where((r) => r.category == 'next_action')
        .take(6)
        .toList();
    final priority = recommendations
        .where((r) => r.category == 'priority')
        .take(6)
        .toList();
    final likely = recommendations
        .where((r) => r.category == 'likely_success')
        .take(6)
        .toList();

    return BiSectionCard(
      title: 'AI Recommendation Engine',
      subtitle: 'Best next action · priority leads · likely successful deals',
      icon: Icons.auto_awesome_outlined,
      accent: const Color(0xFF8B5CF6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const IntelDisclaimer(),
          const SizedBox(height: 12),
          _RecoBlock(
            title: 'Best next action',
            items: nextActions,
            onViewLead: onViewLead,
          ),
          _RecoBlock(
            title: 'Priority leads',
            items: priority,
            onViewLead: onViewLead,
          ),
          _RecoBlock(
            title: 'Likely successful deals',
            items: likely,
            onViewLead: onViewLead,
          ),
        ],
      ),
    );
  }
}

class _RecoBlock extends StatelessWidget {
  final String title;
  final List<IntelRecommendation> items;
  final ValueChanged<LandLead>? onViewLead;

  const _RecoBlock({
    required this.title,
    required this.items,
    this.onViewLead,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: context.fomraTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          if (items.isEmpty)
            Text(
              'None yet.',
              style: TextStyle(
                fontSize: 12,
                color: context.fomraTextSecondary,
              ),
            )
          else
            for (final r in items)
              _IntelRow(
                title: '${r.nextAction} · ${r.lead.displayName}',
                subtitle:
                    '#${r.lead.leadId} · ${r.confidence.round()}% confidence · ${r.rationale}',
                color: AppColors.primary,
                onTap: onViewLead == null ? null : () => onViewLead!(r.lead),
              ),
        ],
      ),
    );
  }
}

class _IntelRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _IntelRow({
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 11, color: context.fomraTextSecondary),
      ),
      trailing: onTap == null
          ? null
          : Icon(Icons.chevron_right, color: context.fomraTextTertiary),
    );
  }
}
