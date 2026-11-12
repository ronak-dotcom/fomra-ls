import '../models/land_lead.dart';
import '../models/land_lead_meeting.dart';
import '../models/monthly_target_submission.dart';
import '../utils/lead_location_parser.dart';
import 'management_bi_metrics.dart';
import 'monthly_target_progress.dart';

/// One line of a monthly target: what was achieved this month, against the
/// approved target (0 = none set), and the lands behind the number.
class TargetLine {
  final MonthlyTargetProgress progress;
  final List<String> leadIds;
  const TargetLine(this.progress, this.leadIds);

  int get achieved => progress.achieved;
  int get target => progress.target;
}

/// How an executive is pacing against a target for today's date.
enum TargetPace { none, onPace, behind, farBehind }

TargetPace paceOf(MonthlyTargetProgress p) {
  if (!p.hasTarget) return TargetPace.none;
  if (p.isOnTrack) return TargetPace.onPace;
  // At least 60% of where an even run-rate would have them today.
  return p.achieved >= p.expectedToday * 0.6
      ? TargetPace.behind
      : TargetPace.farBehind;
}

/// Home "Team Performance": per executive, site visits today / this week /
/// this month (new Lead IDs), self and management meetings this month (first
/// per land), each against the month's approved target, plus their pipeline.
/// Ranked by site visits this month.
class TeamPerformanceRow {
  final String executive;
  final int rank;
  final List<LandLead> today;
  final List<LandLead> week;
  final TargetLine siteVisits;
  final TargetLine selfMeetings;
  final TargetLine managementMeetings;

  /// Pipeline (all time): every Lead ID they created, and those now in
  /// negotiation, legal and closed (signed).
  final List<LandLead> leads;
  final List<LandLead> negotiation;
  final List<LandLead> legal;
  final List<LandLead> closed;
  final double closedAcres;

  /// Their open sites (not closed or dropped) by age since the Lead ID was
  /// created: 0–30, 31–60, 61–90 and 90+ days.
  final List<List<LandLead>> openByAge;

  const TeamPerformanceRow({
    required this.executive,
    required this.rank,
    required this.today,
    required this.week,
    required this.siteVisits,
    required this.selfMeetings,
    required this.managementMeetings,
    required this.leads,
    required this.negotiation,
    required this.legal,
    required this.closed,
    required this.closedAcres,
    required this.openByAge,
  });

  /// [leads] and [meetings] are what the viewer may see; pass ALL meetings so
  /// "first meeting on a land" is judged on its whole history. [targets] are
  /// this month's submissions (only approved ones count). [now] is local.
  static List<TeamPerformanceRow> build({
    required List<LandLead> leads,
    required List<LandLeadMeeting> meetings,
    required List<MonthlyTargetSubmission> targets,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final day = DateTime(n.year, n.month, n.day);
    final weekStart = day.subtract(Duration(days: day.weekday - 1));
    final monthStart = DateTime(n.year, n.month, 1);
    String key(String s) => s.trim().toLowerCase();
    bool inMonth(DateTime d) {
      final l = d.toLocal();
      return !l.isBefore(monthStart) && !l.isAfter(n);
    }

    final display = <String, String>{};
    final byExec = <String, List<LandLead>>{};
    for (final l in leads) {
      final k = key(l.createdByName);
      if (k.isEmpty || k == 'management') continue;
      display.putIfAbsent(k, () => l.createdByName.trim());
      (byExec[k] ??= []).add(l);
    }
    final approved = <String, MonthlyTargetSubmission>{};
    final period = MonthlyTargetSubmission.periodOf(n.year, n.month);
    for (final t in targets) {
      if (!t.isApproved || t.period != period) continue;
      final k = key(t.employeeName);
      if (k.isEmpty) continue;
      approved[k] = t;
      display.putIfAbsent(k, () => t.employeeName.trim());
    }

    final firsts = FirstMeetings.of(meetings);
    TargetLine line(Map<String, int> values, String category,
        List<(DateTime, String)> done) {
      return TargetLine(
        MonthlyTargetProgress.forMonth(
          target: values[category] ?? 0,
          now: n,
          completedOn: [for (final d in done) d.$1],
        ),
        [for (final d in done) d.$2],
      );
    }

    List<(DateTime, String)> meetingsBy(List<LandLeadMeeting> list, String k) =>
        [
          for (final m in list)
            if (key(m.loggedByName) == k && inMonth(m.metAt))
              (m.metAt, m.leadId),
        ];

    final rows = <TeamPerformanceRow>[];
    for (final k in display.keys) {
      final mine = byExec[k] ?? const <LandLead>[];
      final values = approved[k]?.effectiveValues ?? const <String, int>{};
      final month = [
        for (final l in mine)
          if (inMonth(l.addedOn)) l
      ];
      final closed = [
        for (final l in mine)
          if (l.status == LeadStatus.signed) l,
      ];
      rows.add(TeamPerformanceRow(
        executive: display[k]!,
        rank: 0,
        today: [
          for (final l in month)
            if (!l.addedOn.toLocal().isBefore(day)) l,
        ],
        week: [
          for (final l in month)
            if (!l.addedOn.toLocal().isBefore(weekStart)) l,
        ],
        siteVisits: line(values, TargetCategory.siteVisits.key,
            [for (final l in month) (l.addedOn, l.leadId)]),
        selfMeetings: line(values, TargetCategory.selfMeetings.key,
            meetingsBy(firsts.self, k)),
        managementMeetings: line(values, TargetCategory.managementMeetings.key,
            meetingsBy(firsts.management, k)),
        leads: mine,
        negotiation: [
          for (final l in mine)
            if (l.status == LeadStatus.negotiation) l,
        ],
        legal: [
          for (final l in mine)
            if (l.status == LeadStatus.legal) l
        ],
        closed: closed,
        closedAcres: closed.fold<double>(
            0, (s, l) => s + (parseLandExtentSqft(l.landExtent) ?? 0) / 43560),
        openByAge: [
          for (final b in BiAgeBucket.values)
            [
              for (final l in mine)
                if (!l.status.isTerminal &&
                    BiAgeBucketX.forAgeDays(biLeadAgeDays(l, n)) == b)
                  l,
            ],
        ],
      ));
    }

    // Most site visits this month first; ties go to the further pipeline.
    rows.sort((a, b) {
      for (final c in [
        b.siteVisits.achieved.compareTo(a.siteVisits.achieved),
        b.closed.length.compareTo(a.closed.length),
        b.legal.length.compareTo(a.legal.length),
        b.negotiation.length.compareTo(a.negotiation.length),
      ]) {
        if (c != 0) return c;
      }
      return a.executive.toLowerCase().compareTo(b.executive.toLowerCase());
    });
    return [
      for (var i = 0; i < rows.length; i++) rows[i]._withRank(i + 1),
    ];
  }

  TeamPerformanceRow _withRank(int r) => TeamPerformanceRow(
        executive: executive,
        rank: r,
        today: today,
        week: week,
        siteVisits: siteVisits,
        selfMeetings: selfMeetings,
        managementMeetings: managementMeetings,
        leads: leads,
        negotiation: negotiation,
        legal: legal,
        closed: closed,
        closedAcres: closedAcres,
        openByAge: openByAge,
      );
}
