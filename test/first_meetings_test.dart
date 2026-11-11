import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/analytics/monthly_target_progress.dart';
import 'package:fomra_ls/models/land_lead_meeting.dart';

LandLeadMeeting _m(String lead, DateTime at,
        {bool mgmt = false, bool broker = false}) =>
    LandLeadMeeting(
      id: '$lead-$at',
      leadId: lead,
      metAt: at,
      duration: '30',
      notes: '',
      loggedByName: 'Saurabh',
      createdAt: at,
      managementPresent: mgmt,
      attendeeTypes: [
        MeetingAttendeeTypes.landOwner,
        if (broker) MeetingAttendeeTypes.broker,
      ],
    );

void main() {
  test('each land counts once per kind: first self, first management', () {
    final f = FirstMeetings.of([
      // Land A: self in Oct, self again in Nov (repeat), management in Dec.
      _m('A', DateTime(2026, 11, 6)),
      _m('A', DateTime(2026, 10, 2), broker: true),
      _m('A', DateTime(2026, 12, 1), mgmt: true, broker: true),
      // Land B: first meeting in Nov.
      _m('B', DateTime(2026, 11, 9)),
    ]);
    // The Nov repeat on A doesn't count; Oct (A) and Nov (B) do.
    expect(f.self.map((m) => (m.leadId, m.metAt)).toSet(), {
      ('A', DateTime(2026, 10, 2)),
      ('B', DateTime(2026, 11, 9)),
    });
    // Management's first meeting on A counts even though A was met before.
    expect(f.management.single.metAt, DateTime(2026, 12, 1));
    // Broker present: first time on A only (Oct).
    expect(f.broker.single.metAt, DateTime(2026, 10, 2));
  });
}
