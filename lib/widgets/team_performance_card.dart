import 'package:flutter/material.dart';

import '../analytics/monthly_target_progress.dart';
import '../analytics/team_performance.dart';
import '../models/land_lead.dart';
import '../models/land_lead_meeting.dart';
import '../models/monthly_target_submission.dart';
import '../screens/land_lead/filtered_leads_screen.dart';
import '../services/management_bi_activity_service.dart';
import '../services/monthly_target_submission_service.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';

/// Home "Team Performance": site visits today / this week / this month and
/// self / management meetings, each against the month's approved target, per
/// executive, ranked by site visits this month. Tap an executive for their
/// pipeline (leads, negotiation, legal, closed); tap any number for the
/// properties behind it.
///
/// [leads] is already scoped to what the viewer may see; [onlyExecutive]
/// shows just that person (executives see their own row).
class TeamPerformanceCard extends StatefulWidget {
  final List<LandLead> leads;
  final String? onlyExecutive;

  /// Tests: data and clock. When [meetings] / [targets] are given nothing is
  /// loaded.
  final List<LandLeadMeeting>? meetings;
  final List<MonthlyTargetSubmission>? targets;
  final DateTime? now;

  const TeamPerformanceCard({
    super.key,
    required this.leads,
    this.onlyExecutive,
    this.meetings,
    this.targets,
    this.now,
  });

  @override
  State<TeamPerformanceCard> createState() => _TeamPerformanceCardState();
}

class _TeamPerformanceCardState extends State<TeamPerformanceCard> {
  List<LandLeadMeeting> _meetings = const [];
  List<MonthlyTargetSubmission> _targets = const [];
  final _open = <String>{};

  @override
  void initState() {
    super.initState();
    _meetings = widget.meetings ?? const [];
    _targets = widget.targets ?? const [];
    if (widget.meetings == null || widget.targets == null) _load();
  }

  Future<void> _load() async {
    final n = widget.now ?? DateTime.now();
    final results = await Future.wait([
      widget.meetings == null
          ? ManagementBiActivityService.loadMeetings()
          : Future.value(widget.meetings!),
      widget.targets == null
          ? MonthlyTargetSubmissionService.allForPeriod(
                  MonthlyTargetSubmission.periodOf(n.year, n.month))
              .catchError((_) => <MonthlyTargetSubmission>[])
          : Future.value(widget.targets!),
    ]);
    if (!mounted) return;
    setState(() {
      _meetings = results[0] as List<LandLeadMeeting>;
      _targets = results[1] as List<MonthlyTargetSubmission>;
    });
  }

  void _openList(String title, String subtitle, List<LandLead> leads) {
    if (leads.isEmpty) return;
    FilteredLeadsScreen.openList(context,
        title: title, subtitle: subtitle, leads: leads);
  }

  List<LandLead> _byIds(List<String> ids) {
    final want = ids.toSet();
    final seen = <String>{};
    return [
      for (final l in widget.leads)
        if (want.contains(l.leadId) && seen.add(l.leadId)) l,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final only = widget.onlyExecutive?.trim().toLowerCase();
    final rows = TeamPerformanceRow.build(
      leads: widget.leads,
      meetings: _meetings,
      targets: _targets,
      now: widget.now,
    ).where((r) => only == null || r.executive.toLowerCase() == only).toList();
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No site visits or targets this month yet.',
          style: TextStyle(fontSize: 13.5, color: context.fomraTextSecondary),
        ),
      );
    }
    final showRank = rows.length > 1;
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 760;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide) _header(context) else if (showRank) _teamLine(rows),
          for (final r in rows)
            wide ? _wideRow(r, showRank) : _phoneRow(r, showRank),
          const SizedBox(height: 10),
          Text(
            '${showRank ? 'Ranked by site visits this month (new Lead IDs). ' : ''}'
            'Meetings count the first one per land. Bars: green on pace for '
            "today's date, amber behind, red far behind. Tap "
            '${showRank ? 'a name' : 'your name'} for the pipeline and site age, any '
            'number for the properties.',
            style: TextStyle(
                fontSize: 12, height: 1.4, color: context.fomraTextSecondary),
          ),
        ],
      );
    });
  }

  // ── Wide (desktop / tablet) ───────────────────────────────────────────────

  TextStyle _h(BuildContext context) => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: context.fomraTextTertiary,
      );

  Widget _header(BuildContext context) {
    Widget hd(String s, int f) => Expanded(
        flex: f,
        child: Text(s, textAlign: TextAlign.center, style: _h(context)));
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        const SizedBox(width: 40),
        Expanded(flex: 4, child: Text('EXECUTIVE', style: _h(context))),
        hd('TODAY', 2),
        hd('WEEK', 2),
        hd('SITE VISITS · MONTH', 4),
        hd('SELF MEETINGS', 4),
        hd('MGMT MEETINGS', 4),
        const SizedBox(width: 28),
      ]),
    );
  }

  Widget _wideRow(TeamPerformanceRow r, bool showRank) {
    final open = _open.contains(r.executive);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.fomraDivider)),
      ),
      child: Column(children: [
        InkWell(
          onTap: () => _toggle(r.executive),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              SizedBox(width: 40, child: showRank ? _Rank(r.rank) : null),
              Expanded(flex: 4, child: _name(r)),
              Expanded(
                  flex: 2,
                  child: _count(
                      r.today,
                      AppColors.success,
                      () => _openList('Site visits · ${r.executive}',
                          'Today · new Lead IDs', r.today))),
              Expanded(
                  flex: 2,
                  child: _count(
                      r.week,
                      AppColors.info,
                      () => _openList('Site visits · ${r.executive}',
                          'This week · new Lead IDs', r.week))),
              Expanded(flex: 4, child: _target(r, 'Site visits', r.siteVisits)),
              Expanded(
                  flex: 4, child: _target(r, 'Self meetings', r.selfMeetings)),
              Expanded(
                  flex: 4,
                  child:
                      _target(r, 'Management meetings', r.managementMeetings)),
              SizedBox(
                width: 28,
                child: Icon(
                    open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: context.fomraTextTertiary),
              ),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 28, 12),
            child: _pipeline(r),
          ),
      ]),
    );
  }

  // ── Phone ─────────────────────────────────────────────────────────────────

  Widget _teamLine(List<TeamPerformanceRow> rows) {
    int sum(int Function(TeamPerformanceRow) f) =>
        rows.fold(0, (s, r) => s + f(r));
    final target = sum((r) => r.siteVisits.target);
    return Text(
      'Team · Today ${sum((r) => r.today.length)} · '
      'Week ${sum((r) => r.week.length)} · '
      'Month ${sum((r) => r.siteVisits.achieved)}'
      '${target > 0 ? '/$target' : ''}',
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: context.fomraTextSecondary,
      ),
    );
  }

  Widget _phoneRow(TeamPerformanceRow r, bool showRank) {
    final open = _open.contains(r.executive);
    final top = showRank && r.rank == 1;
    Widget stat(String label, List<LandLead> leads, Color color, String sub) =>
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _openList(
              'Site visits · ${r.executive}', '$sub · new Lead IDs', leads),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Column(children: [
              Text('${leads.length}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: leads.isEmpty ? context.fomraTextTertiary : color,
                  )),
              Text(label, style: _h(context).copyWith(fontSize: 10)),
            ]),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: context.fomraSurfaceVar,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              top ? AppColors.gold.withValues(alpha: 0.6) : context.fomraBorder,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                if (showRank) ...[_Rank(r.rank), const SizedBox(width: 10)],
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _toggle(r.executive),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Flexible(child: _name(r, size: 16)),
                        Icon(
                            open
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 20,
                            color: context.fomraTextTertiary),
                      ]),
                    ),
                  ),
                ),
                stat('TODAY', r.today, AppColors.success, 'Today'),
                stat('WEEK', r.week, AppColors.info, 'This week'),
              ]),
              _phoneLine(r, 'Site visits', r.siteVisits),
              _phoneLine(r, 'Self meetings', r.selfMeetings),
              _phoneLine(r, 'Mgmt meetings', r.managementMeetings,
                  listLabel: 'Management meetings'),
              if (open) ...[
                const SizedBox(height: 12),
                Divider(height: 1, color: context.fomraDivider),
                const SizedBox(height: 10),
                _pipeline(r, compact: true),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _phoneLine(TeamPerformanceRow r, String label, TargetLine t,
      {String? listLabel}) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openLine(r, listLabel ?? label, t),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(
            width: 112,
            child: Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.fomraTextSecondary,
                )),
          ),
          Expanded(child: _Bar(t.progress)),
          const SizedBox(width: 10),
          SizedBox(width: 58, child: _fraction(t, align: TextAlign.right)),
        ]),
      ),
    );
  }

  // ── Shared pieces ─────────────────────────────────────────────────────────

  void _toggle(String exec) => setState(() {
        if (!_open.remove(exec)) _open.add(exec);
      });

  void _openLine(TeamPerformanceRow r, String label, TargetLine t) {
    final leads = _byIds(t.leadIds);
    _openList('$label · ${r.executive}', '${leads.length} this month', leads);
  }

  Widget _name(TeamPerformanceRow r, {double size = 14.5}) => Text(
        r.executive,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w800,
          color: context.fomraTextPrimary,
        ),
      );

  Widget _count(List<LandLead> leads, Color color, VoidCallback onTap) =>
      Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: leads.isEmpty ? null : onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: leads.isEmpty ? context.fomraTextTertiary : color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      );

  Widget _fraction(TargetLine t, {TextAlign align = TextAlign.center}) {
    final color = _paceColor(context, paceOf(t.progress), t.achieved);
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: '${t.achieved}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        TextSpan(
          text: t.target > 0 ? ' / ${t.target}' : '',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: context.fomraTextTertiary,
          ),
        ),
      ]),
      textAlign: align,
    );
  }

  Widget _target(TeamPerformanceRow r, String label, TargetLine t) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openLine(r, label, t),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Column(children: [
            _fraction(t),
            const SizedBox(height: 4),
            _Bar(t.progress),
          ]),
        ),
      );

  Widget _pipeline(TeamPerformanceRow r, {bool compact = false}) {
    Widget tile(String label, List<LandLead> leads, Color color,
            {String? extra, String? short, String sub = 'Pipeline'}) =>
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openList('$label · ${r.executive}', sub, leads),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: leads.isEmpty
                    ? Colors.transparent
                    : color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.fomraDivider),
              ),
              child: Column(children: [
                Text(
                  '${leads.length}',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: leads.isEmpty ? context.fomraTextTertiary : color,
                  ),
                ),
                const SizedBox(height: 2),
                Text((compact ? short ?? label : label).toUpperCase(),
                    maxLines: 1, style: _h(context).copyWith(fontSize: 10)),
                if (extra != null)
                  Text(extra,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      )),
              ]),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 3, bottom: 6),
          child: Text('PIPELINE · ALL TIME',
              style: _h(context).copyWith(color: AppColors.purple)),
        ),
        IntrinsicHeight(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          tile('Leads', r.leads, context.fomraTextPrimary),
          tile('Negotiation', r.negotiation, AppColors.purple, short: 'Neg.'),
          tile('Legal', r.legal, AppColors.warning),
          tile('Closed', r.closed, AppColors.success,
              extra: r.closed.isEmpty
                  ? null
                  : '${r.closedAcres.toStringAsFixed(1)} ac'),
        ])),
        Padding(
          padding: const EdgeInsets.only(left: 3, top: 12, bottom: 6),
          child: Text('OPEN SITES BY AGE',
              style: _h(context).copyWith(color: AppColors.info)),
        ),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < 4; i++)
              tile(
                  const [
                    '0–30 days',
                    '31–60 days',
                    '61–90 days',
                    '90+ days'
                  ][i],
                  r.openByAge[i],
                  _ageColors[i],
                  short: const ['0–30 d', '31–60 d', '61–90 d', '90+ d'][i],
                  sub: 'Open sites by age'),
          ]),
        ),
      ],
    );
  }
}

const _ageColors = [
  AppColors.success,
  AppColors.info,
  AppColors.warning,
  AppColors.error,
];

Color _paceColor(BuildContext context, TargetPace pace, int achieved) =>
    switch (pace) {
      TargetPace.onPace => AppColors.success,
      TargetPace.behind => AppColors.warning,
      TargetPace.farBehind => AppColors.error,
      TargetPace.none =>
        achieved > 0 ? context.fomraTextPrimary : context.fomraTextTertiary,
    };

class _Bar extends StatelessWidget {
  final MonthlyTargetProgress p;
  const _Bar(this.p);

  @override
  Widget build(BuildContext context) {
    final pace = paceOf(p);
    final color = _paceColor(context, pace, p.achieved);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: p.hasTarget ? p.completionPercent / 100 : 0,
        minHeight: 5,
        backgroundColor: pace == TargetPace.none
            ? context.fomraDivider
            : color.withValues(alpha: 0.15),
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

class _Rank extends StatelessWidget {
  final int rank;
  const _Rank(this.rank);

  @override
  Widget build(BuildContext context) {
    final gold = rank == 1;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: gold
            ? AppColors.gold.withValues(alpha: 0.18)
            : context.fomraSurfaceVar,
        border: Border.all(color: gold ? AppColors.gold : context.fomraBorder),
      ),
      child: Text(
        '#$rank',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: gold ? AppColors.gold : context.fomraTextSecondary,
        ),
      ),
    );
  }
}
