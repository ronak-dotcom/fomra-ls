import '../models/daily_update.dart';

/// Builds the WhatsApp-style text block from a day's plan or recap — the
/// same shape either time, since the morning and evening posts look
/// similar. Best-effort match to the format already in use; the exact
/// wording/spacing is easy to tune once someone sees real generated output
/// next to what they'd have typed by hand.
class DailyUpdateFormatter {
  static String format({
    required List<DailyUpdateVisit> visits,
    required List<DailyUpdateVisit> selfMeetings,
    required List<DailyUpdateHeadMeeting> headMeetings,
    required List<DailyUpdateActivity> otherActivities,
    required int siteVisitTarget,
    required int siteVisitAchieved,
    required int headMeetingTarget,
    required int headMeetingAchieved,
  }) {
    final buf = StringBuffer();

    final realVisits = visits.where((v) => !v.isEmpty).toList();
    for (final v in realVisits) {
      final place = v.place.trim();
      final who = v.withWhom.trim();
      if (place.isEmpty) {
        buf.writeln(who);
      } else if (who.isEmpty) {
        buf.writeln(place);
      } else {
        buf.writeln('$place - met $who');
      }
    }
    if (realVisits.isNotEmpty) buf.writeln();

    final realSelfMeetings = selfMeetings.where((v) => !v.isEmpty).length;
    buf.writeln(
        '🤝 *Planned Meetings - ${realSelfMeetings == 0 ? 'nil' : realSelfMeetings}');
    buf.writeln();

    final realHeadMeetings = headMeetings.where((m) => !m.isEmpty).toList();
    buf.writeln('👨\u200d💼 *Meeting with Head - ${realHeadMeetings.length}');
    if (realHeadMeetings.isNotEmpty) {
      buf.writeln();
      for (final m in realHeadMeetings) {
        final note = m.note.trim();
        if (note.isNotEmpty) buf.writeln(note);
      }
    }
    buf.writeln();

    final realActivities =
        otherActivities.where((a) => a.text.trim().isNotEmpty).toList();
    if (realActivities.isNotEmpty) {
      buf.writeln('Other activities:');
      for (final a in realActivities) {
        buf.writeln(a.text.trim());
      }
      buf.writeln();
    }

    // Auto-generated from the real Monthly Targets data — never manually
    // typed, so it can never drift from the actual number. Order confirmed
    // against the example: Saurabh's actual Site Visit target is 30, and
    // the sample showed "30/15" — target first, then achieved.
    buf.writeln('S.V. - $siteVisitTarget/$siteVisitAchieved');
    buf.write('H.M - $headMeetingTarget/$headMeetingAchieved');

    return buf.toString().trim();
  }
}
