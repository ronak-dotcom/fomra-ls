import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/competitor_project.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../utils/competitor_analysis.dart';
import '../../widgets/ui/app_components.dart';

class CompetitorStageChip extends StatelessWidget {
  final CompetitorStage stage;
  const CompetitorStageChip({super.key, required this.stage});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: stage.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        stage.label,
        style: TextStyle(
            fontSize: 11.5, fontWeight: FontWeight.w700, color: stage.color),
      ),
    );
  }
}

/// "Checked 12 Nov 2026" or "Re-check due" (amber).
class CompetitorFreshness extends StatelessWidget {
  final CompetitorProject project;
  const CompetitorFreshness({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final due = project.recheckIsDue();
    final last = project.lastCheckedAt;
    final text = last == null
        ? 'Never checked'
        : 'Checked ${DateFormat('d MMM yyyy').format(last)}';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(due ? Icons.update_rounded : Icons.check_circle_outline_rounded,
          size: 14, color: due ? AppColors.warning : context.fomraTextSecondary),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          due ? '$text · re-check due' : text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: due ? FontWeight.w700 : FontWeight.w500,
            color: due ? AppColors.warning : context.fomraTextSecondary,
          ),
        ),
      ),
    ]);
  }
}

/// One project in a list: name, builder, place, price, plots, freshness.
class CompetitorTile extends StatelessWidget {
  final CompetitorProject project;

  /// e.g. "2.4 km · linked" (lead page) or the nearest lead (menu).
  final String? trailingNote;
  final VoidCallback? onTap;

  /// Opens a linked lead when its number is tapped (null: not tappable,
  /// e.g. a lead this person can't see).
  final void Function(String leadId)? onOpenLead;

  const CompetitorTile({
    super.key,
    required this.project,
    this.trailingNote,
    this.onTap,
    this.onOpenLead,
  });

  @override
  Widget build(BuildContext context) {
    final p = project;
    final sold = p.totalSold, plots = p.totalPlots;
    final sub = [
      if (p.builder.isNotEmpty) p.builder,
      if (p.placeLabel.isNotEmpty) p.placeLabel,
      p.type.label,
    ].join(' · ');
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: '${p.code}  ',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: context.fomraTextSecondary),
                ),
                TextSpan(
                  text: p.name,
                  style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: context.fomraTextPrimary),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          CompetitorStageChip(stage: p.stage),
        ]),
        const SizedBox(height: 3),
        Text(sub,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: context.fomraTextSecondary)),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 6, children: [
          if (p.quotedPrice != null || p.negotiatedPrice != null)
            _fact(
              context,
              Icons.currency_rupee_rounded,
              p.negotiatedPrice != null && p.quotedPrice != null &&
                      p.negotiatedPrice != p.quotedPrice
                  ? '${count(p.negotiatedPrice)} (quoted ${count(p.quotedPrice)}) /sq ft'
                  : '${count(p.dealPrice)} /sq ft',
            ),
          if (plots != null || sold != null)
            _fact(
              context,
              Icons.grid_view_rounded,
              plots != null && sold != null
                  ? '$sold of $plots sold'
                  : plots != null
                      ? '$plots plots'
                      : '$sold sold',
            ),
          if (p.minSqft != null || p.maxSqft != null)
            _fact(
              context,
              Icons.straighten_rounded,
              p.minSqft != null && p.maxSqft != null
                  ? '${count(p.minSqft)}–${count(p.maxSqft)} sq ft'
                  : '${count(p.minSqft ?? p.maxSqft)} sq ft',
            ),
          if (trailingNote != null && trailingNote!.isNotEmpty)
            _fact(context, Icons.near_me_outlined, trailingNote!),
          if (p.point == null)
            _fact(context, Icons.location_off_outlined, 'No pin'),
        ]),
        if (p.linkedLeadIds.isNotEmpty) ...[
          const SizedBox(height: 6),
          _LinkedLeads(ids: p.linkedLeadIds, onOpenLead: onOpenLead),
        ],
        const SizedBox(height: 8),
        CompetitorFreshness(project: p),
      ]),
    );
  }

  Widget _fact(BuildContext context, IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.fomraTextPrimary)),
        ],
      );
}

/// A map pin with the project's ₹/sq ft above it, coloured by stage.
class CompetitorPricePin extends StatelessWidget {
  final CompetitorProject project;
  final bool selected;
  final VoidCallback? onTap;

  const CompetitorPricePin({
    super.key,
    required this.project,
    this.selected = false,
    this.onTap,
  });

  static const width = 74.0;
  static const height = 56.0;

  @override
  Widget build(BuildContext context) {
    final color = project.stage.color;
    final price = project.dealPrice;
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : color,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            price == null ? project.code : '₹${count(price)}',
            maxLines: 1,
            style: const TextStyle(
                color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
          ),
        ),
        Icon(Icons.apartment_rounded,
            color: selected ? AppColors.ink : color, size: 26),
      ]),
    );
  }
}

/// A small blue pin for one of our leads on a competitor map.
class OurLeadPin extends StatelessWidget {
  final String label;
  final bool highlight;
  const OurLeadPin({super.key, required this.label, this.highlight = false});

  static const width = 56.0;
  static const height = 48.0;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColors.error : const Color(0xFF0EA5E9);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            maxLines: 1,
            style: TextStyle(
                color: color, fontSize: 9.5, fontWeight: FontWeight.w800)),
      ),
      Icon(Icons.location_on, color: color, size: highlight ? 32 : 26),
    ]);
  }
}

/// "Linked: #135, #36" — each number opens that lead.
class _LinkedLeads extends StatelessWidget {
  final List<String> ids;
  final void Function(String leadId)? onOpenLead;

  const _LinkedLeads({required this.ids, this.onOpenLead});

  @override
  Widget build(BuildContext context) {
    final sorted = [...ids]..sort((a, b) {
        final x = int.tryParse(a), y = int.tryParse(b);
        return x != null && y != null ? x.compareTo(y) : a.compareTo(b);
      });
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        const Icon(Icons.link_rounded, size: 15, color: AppColors.purple),
        Text('Linked:',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.fomraTextSecondary)),
        for (final id in sorted)
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onOpenLead == null ? null : () => onOpenLead!(id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('#$id',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.purple)),
            ),
          ),
      ],
    );
  }
}
