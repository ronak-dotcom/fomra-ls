import '../models/land_lead.dart';
import '../models/land_lead_meeting.dart';

/// An employee's progress against the common monthly target.
///
/// Pure maths over dates the caller supplies — no clock, no I/O — so the card
/// and its chart read the same numbers and both are testable.
class MonthlyTargetProgress {
  /// The common target for the month. Zero when management hasn't set one.
  final int target;

  /// Sites/deals completed so far this month.
  final int achieved;

  /// Days in the month.
  final int daysInMonth;

  /// Day of the month "today" falls on (1-based), clamped into the month.
  final int dayOfMonth;

  /// Cumulative achieved at the end of each elapsed day: index 0 is day 1.
  /// Length is [dayOfMonth] — the actual line stops at today rather than
  /// drawing a flat run to the month end.
  final List<int> actualByDay;

  const MonthlyTargetProgress({
    required this.target,
    required this.achieved,
    required this.daysInMonth,
    required this.dayOfMonth,
    required this.actualByDay,
  });

  /// Whether management has set a target for this month at all.
  bool get hasTarget => target > 0;

  /// Still to do. Never negative — beating the target isn't negative work.
  int get remaining => target - achieved > 0 ? target - achieved : 0;

  /// 0-100, capped: 12 of 10 reads as 100% complete, not 120%.
  double get completionPercent {
    if (!hasTarget) return 0;
    final pct = achieved / target * 100;
    return pct > 100 ? 100 : pct;
  }

  /// Where an even run-rate would have you by the end of today. Day 15 of 30 on
  /// a target of 30 expects 15.
  double get expectedToday {
    if (!hasTarget || daysInMonth <= 0) return 0;
    return target * dayOfMonth / daysInMonth;
  }

  /// On track when you're at or above the even run-rate for today.
  bool get isOnTrack => achieved >= expectedToday;

  /// How far ahead (positive) or behind (negative) the run-rate you are.
  double get varianceToday => achieved - expectedToday;

  /// The ideal line: an even run-rate from 0 to [target] across the month.
  /// Index 0 is day 1, so it spans the whole month even before it's elapsed.
  List<double> get targetByDay => [
        for (var day = 1; day <= daysInMonth; day++)
          daysInMonth <= 0 ? 0 : target * day / daysInMonth,
      ];

  /// Builds progress for the month [now] falls in from the dates work was
  /// completed on. [completedOn] may be in any order and may contain dates
  /// outside the month — those are ignored.
  factory MonthlyTargetProgress.forMonth({
    required int target,
    required DateTime now,
    required List<DateTime> completedOn,
  }) {
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final dayOfMonth = now.day.clamp(1, daysInMonth);

    // Completions per day of this month.
    final perDay = List<int>.filled(daysInMonth + 1, 0);
    for (final at in completedOn) {
      if (at.year != now.year || at.month != now.month) continue;
      final day = at.day;
      if (day < 1 || day > daysInMonth) continue;
      perDay[day]++;
    }

    final actualByDay = <int>[];
    var running = 0;
    for (var day = 1; day <= dayOfMonth; day++) {
      running += perDay[day];
      actualByDay.add(running);
    }

    return MonthlyTargetProgress(
      target: target,
      achieved: running,
      daysInMonth: daysInMonth,
      dayOfMonth: dayOfMonth,
      actualByDay: actualByDay,
    );
  }
}

/// Site Visits target: a site visit is the first visit to a land — the one
/// that creates its Lead ID. So it's one per lead the executive added, dated
/// when the lead was added. Revisits and management site visits don't count.
abstract final class SiteVisitTarget {
  static List<LandLead> leadsVisitedBy(
          Iterable<LandLead> leads, String executiveName) =>
      [
        for (final l in leads)
          if (_same(l.createdByName, executiveName)) l,
      ];

  static List<DateTime> datesFor(
          Iterable<LandLead> leads, String executiveName) =>
      [for (final l in leadsVisitedBy(leads, executiveName)) l.addedOn];

  static bool _same(String a, String b) {
    final x = a.trim().toLowerCase();
    return x.isNotEmpty && x == b.trim().toLowerCase();
  }
}

/// Meeting targets count each land once per kind: the first Self meeting
/// (management not present), the first Management meeting and the first
/// meeting with the Broker present on that land, ever. A repeat meeting on
/// the same land (e.g. met in Oct, met again in Nov) never counts again.
///
/// Pass ALL meetings (not just this month's), so "first" is judged against
/// the land's whole history; callers then filter by month and person.
class FirstMeetings {
  final List<LandLeadMeeting> self;
  final List<LandLeadMeeting> management;
  final List<LandLeadMeeting> broker;

  const FirstMeetings._(this.self, this.management, this.broker);

  factory FirstMeetings.of(Iterable<LandLeadMeeting> all) {
    final self = <String, LandLeadMeeting>{};
    final mgmt = <String, LandLeadMeeting>{};
    final broker = <String, LandLeadMeeting>{};
    void keepEarliest(Map<String, LandLeadMeeting> map, LandLeadMeeting m) {
      final cur = map[m.leadId];
      if (cur == null || m.metAt.isBefore(cur.metAt)) map[m.leadId] = m;
    }

    for (final m in all) {
      keepEarliest(m.managementPresent ? mgmt : self, m);
      if (m.attendeeTypes.contains(MeetingAttendeeTypes.broker)) {
        keepEarliest(broker, m);
      }
    }
    return FirstMeetings._(
      self.values.toList(),
      mgmt.values.toList(),
      broker.values.toList(),
    );
  }
}
