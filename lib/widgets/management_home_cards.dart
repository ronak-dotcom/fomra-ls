import 'package:flutter/material.dart';

import '../analytics/management_bi_metrics.dart';
import '../models/land_lead.dart';
import '../models/lead_review.dart';
import '../screens/land_lead/filtered_leads_screen.dart';
import '../services/lead_review_service.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';
import 'terms_deal_selector.dart';

/// One line of the management "Needs attention" card.
class AttentionItem {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final int count;
  final VoidCallback? onTap;

  const AttentionItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.count,
    this.onTap,
  });
}

/// Management Home: everything waiting on someone, one tappable line each.
/// Two columns on wide screens, one on phones.
class NeedsAttentionCard extends StatefulWidget {
  /// Sites the viewer may see.
  final List<LandLead> leads;

  /// Requests waiting on the viewer (site visit / signed / drop / targets).
  final int approvalCount;
  final VoidCallback? onOpenApprovals;

  /// Active sites with no land owner meeting planned and none lately.
  final List<LandLead> noNextStep;
  final int noNextStepDays;

  /// Tests: the "current" time.
  final DateTime? now;

  const NeedsAttentionCard({
    super.key,
    required this.leads,
    required this.approvalCount,
    this.onOpenApprovals,
    this.noNextStep = const [],
    this.noNextStepDays = 30,
    this.now,
  });

  @override
  State<NeedsAttentionCard> createState() => _NeedsAttentionCardState();
}

class _NeedsAttentionCardState extends State<NeedsAttentionCard> {
  @override
  void initState() {
    super.initState();
    LeadReviewIndex.instance.addListener(_rebuild);
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

  VoidCallback _list(String title, String subtitle, List<LandLead> leads) =>
      () => FilteredLeadsScreen.openList(context,
          title: title, subtitle: subtitle, leads: leads);

  @override
  Widget build(BuildContext context) {
    final now = widget.now ?? DateTime.now();
    final open = [
      for (final l in widget.leads)
        if (!l.status.isTerminal) l
    ];
    final ownerPending = [
      for (final l in widget.leads)
        if (l.status == LeadStatus.prospectMeetingPending) l,
    ];
    final stuck = [
      for (final l in open)
        if (biLeadAgeDays(l, now) > 90) l,
    ];
    final legal = [
      for (final l in widget.leads)
        if (l.status == LeadStatus.legal) l,
    ];
    final index = LeadReviewIndex.instance;
    final overdue = index.isLoaded
        ? [
            for (final l in open)
              if (ReviewFilter.overdue.matches(index.latestFor(l.leadId))) l,
          ]
        : const <LandLead>[];

    final items = [
      AttentionItem(
        icon: Icons.approval_outlined,
        color: AppColors.warning,
        title: 'Approvals waiting on you',
        subtitle: 'Site visit, signed, drop and target requests',
        count: widget.approvalCount,
        onTap: widget.onOpenApprovals,
      ),
      AttentionItem(
        icon: Icons.person_search_outlined,
        color: AppColors.error,
        title: 'Owner not met yet',
        subtitle: 'The land owner meeting is still pending',
        count: ownerPending.length,
        onTap: _list(
            'Owner not met yet', 'Land owner meeting pending', ownerPending),
      ),
      AttentionItem(
        icon: Icons.hourglass_bottom_rounded,
        color: AppColors.error,
        title: 'Open over 90 days',
        subtitle: 'Added more than 90 days ago and not yet closed',
        count: stuck.length,
        onTap: _list('Open over 90 days',
            'Added more than 90 days ago · not closed or dropped', stuck),
      ),
      AttentionItem(
        icon: Icons.gavel_rounded,
        color: AppColors.purple,
        title: 'In legal',
        subtitle: 'Waiting on title / legal clearance',
        count: legal.length,
        onTap: _list('In legal', 'Waiting on legal clearance', legal),
      ),
      AttentionItem(
        icon: Icons.event_note_outlined,
        color: AppColors.warning,
        title: 'Reviews overdue',
        subtitle: 'The next review date has passed',
        count: overdue.length,
        onTap: _list('Reviews overdue', 'Next review date has passed', overdue),
      ),
      AttentionItem(
        icon: Icons.event_busy_outlined,
        color: AppColors.info,
        title: 'No next step planned',
        subtitle: 'No owner meeting planned and none in '
            '${widget.noNextStepDays} days',
        count: widget.noNextStep.length,
        onTap: _list(
            'No next step planned',
            'Active sites with no Land Owner Meeting scheduled and none in '
                'the last ${widget.noNextStepDays} days',
            widget.noNextStep),
      ),
    ];

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 640;
      final rows = [for (final i in items) _AttentionRow(item: i)];
      if (!wide) {
        return Column(children: [
          for (final r in rows)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: r),
        ]);
      }
      return Column(children: [
        for (var i = 0; i < rows.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: rows[i]),
                  const SizedBox(width: 10),
                  Expanded(
                      child:
                          i + 1 < rows.length ? rows[i + 1] : const SizedBox()),
                ],
              ),
            ),
          ),
      ]);
    });
  }
}

class _AttentionRow extends StatelessWidget {
  final AttentionItem item;
  const _AttentionRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final clear = item.count == 0;
    final color = clear ? context.fomraTextTertiary : item.color;
    return Material(
      color:
          clear ? context.fomraSurfaceVar : item.color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: clear ? null : item.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: clear
                  ? context.fomraBorder
                  : item.color.withValues(alpha: 0.30),
            ),
          ),
          child: Row(children: [
            Icon(item.icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(item.title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: context.fomraTextPrimary,
                      )),
                  Text(item.subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.fomraTextSecondary,
                      )),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              clear ? 'All clear' : '${item.count}',
              style: TextStyle(
                fontSize: clear ? 13 : 22,
                fontWeight: FontWeight.w800,
                color: clear ? AppColors.success : item.color,
              ),
            ),
            if (!clear) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  color: context.fomraTextTertiary),
            ],
          ]),
        ),
      ),
    );
  }
}

/// The deal-term categories shown on the pipeline card, in order.
const dealTermCategories = [
  'Outright Purchase',
  'Joint Venture',
  'Marketing',
  'Deferred Payment',
];

/// A lead's deal-term category, or null when none of [dealTermCategories].
String? dealTermCategoryOf(LandLead lead) {
  final p = parseTermsDeal(lead.accessDetails).primary?.trim().toLowerCase();
  if (p == null || p.isEmpty) return null;
  for (final c in dealTermCategories) {
    if (c.toLowerCase() == p) return c;
  }
  return null;
}

/// Management Home: where every site stands, as one left-to-right row of
/// stages (count + acres), then how the deals are structured. Every stage and
/// deal term opens its list.
class PropertyPipelineCard extends StatelessWidget {
  final List<LandLead> leads;
  const PropertyPipelineCard({super.key, required this.leads});

  static const _stages = <(String, List<LeadStatus>, Color)>[
    (
      'Owner meeting pending',
      [LeadStatus.prospectMeetingPending],
      AppColors.error
    ),
    (
      'Owner met',
      [
        LeadStatus.prospectMeetingCompleted,
        LeadStatus.managementMeetingCompleted,
      ],
      AppColors.info
    ),
    ('Negotiation', [LeadStatus.negotiation], AppColors.purple),
    ('Legal', [LeadStatus.legal], AppColors.warning),
    ('Closed', [LeadStatus.signed], AppColors.success),
  ];

  static const _termColors = [
    AppColors.primary,
    AppColors.purple,
    AppColors.warning,
    AppColors.success,
  ];

  void _open(BuildContext context, String title, List<LandLead> list) {
    if (list.isEmpty) return;
    FilteredLeadsScreen.openList(context,
        title: title, subtitle: '${list.length} sites', leads: list);
  }

  @override
  Widget build(BuildContext context) {
    List<LandLead> having(List<LeadStatus> s) => [
          for (final l in leads)
            if (s.contains(l.status)) l
        ];
    final onHold = having([LeadStatus.onHold]);
    final dropped = having([LeadStatus.dropped]);
    final terms = {
      for (final c in dealTermCategories)
        c: [
          for (final l in leads)
            if (dealTermCategoryOf(l) == c) l
        ],
    };
    final termTotal = terms.values.fold<int>(0, (s, l) => s + l.length);

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 760;
      final tiles = [
        for (final (label, statuses, color) in _stages)
          _StageTile(
            label: label,
            leads: having(statuses),
            color: color,
            onTap: () => _open(context, label, having(statuses)),
          ),
      ];
      final muted =
          TextStyle(fontSize: 12.5, color: context.fomraTextSecondary);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    Expanded(child: tiles[i]),
                    if (i < tiles.length - 1)
                      Icon(Icons.chevron_right_rounded,
                          color: context.fomraTextTertiary),
                  ],
                ],
              ),
            )
          else
            for (final t in tiles)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: t),
          const SizedBox(height: 8),
          Wrap(spacing: 4, children: [
            Text('Also:', style: muted),
            _InlineLink(
                text: '${onHold.length} on hold',
                onTap: () => _open(context, 'On hold', onHold)),
            Text('·', style: muted),
            _InlineLink(
                text: '${dropped.length} dropped',
                onTap: () => _open(context, 'Dropped', dropped)),
          ]),
          if (termTotal > 0) ...[
            const SizedBox(height: 18),
            Text('HOW DEALS ARE STRUCTURED',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: context.fomraTextTertiary,
                )),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Row(children: [
                for (var i = 0; i < dealTermCategories.length; i++)
                  if (terms[dealTermCategories[i]]!.isNotEmpty)
                    Expanded(
                      flex: terms[dealTermCategories[i]]!.length,
                      child: Container(height: 12, color: _termColors[i]),
                    ),
              ]),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 16, runSpacing: 6, children: [
              for (var i = 0; i < dealTermCategories.length; i++)
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _open(context, dealTermCategories[i],
                      terms[dealTermCategories[i]]!),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: _termColors[i], shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${dealTermCategories[i]} '
                      '${(terms[dealTermCategories[i]]!.length / termTotal * 100).round()}%',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: context.fomraTextSecondary,
                      ),
                    ),
                  ]),
                ),
            ]),
          ],
        ],
      );
    });
  }
}

class _StageTile extends StatelessWidget {
  final String label;
  final List<LandLead> leads;
  final Color color;
  final VoidCallback onTap;

  const _StageTile({
    required this.label,
    required this.leads,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final acres = leads.fold<double>(0, (s, l) => s + biLeadAcres(l));
    final empty = leads.isEmpty;
    return Material(
      color: empty ? Colors.transparent : color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: empty ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: empty
                    ? context.fomraBorder
                    : color.withValues(alpha: 0.30)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${leads.length}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: empty ? context.fomraTextTertiary : color,
                  )),
              Text(label,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: context.fomraTextPrimary,
                  )),
              Text('${acres.toStringAsFixed(1)} ac',
                  style: TextStyle(
                      fontSize: 12, color: context.fomraTextSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineLink extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _InlineLink({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Text(text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: context.fomraTextSecondary,
              decoration: TextDecoration.underline,
            )),
      );
}
