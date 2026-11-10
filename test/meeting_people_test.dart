import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/models/land_lead.dart';
import 'package:fomra_ls/models/land_lead_meeting.dart';

Map<String, dynamic> _row({List<String> types = const [], List people = const []}) => {
      'id': 'm1',
      'lead_id': 'L1',
      'met_at': '2026-11-09T10:00:00Z',
      'created_at': '2026-11-09T12:00:00Z',
      'attendee_types': types,
      'people_met': people,
    };

void main() {
  test('people met are read with their relation to the owner', () {
    final m = LandLeadMeeting.fromJson(_row(people: [
      {'name': 'Ravi', 'relation': 'Son'},
      {'name': '', 'relation': ''},
    ]));
    expect(m.peopleMet.map((p) => p.label), ['Ravi — Son']);
    expect(m.metLandOwner, isFalse);
  });

  test('land owner met via attendee tick or a person recorded as owner', () {
    expect(
        LandLeadMeeting.fromJson(
                _row(types: [MeetingAttendeeTypes.landOwner]))
            .metLandOwner,
        isTrue);
    expect(
        LandLeadMeeting.fromJson(_row(people: [
          {'name': 'Kumar', 'relation': 'Land Owner'}
        ])).metLandOwner,
        isTrue);
    // An agreement holder is not the land owner for the broker ranking.
    expect(
        LandLeadMeeting.fromJson(
                _row(types: [MeetingAttendeeTypes.agreementHolder]))
            .metLandOwner,
        isFalse);
  });

  test('relations map onto the who-was-met types', () {
    expect(PersonMet.attendeeTypeFor('Land Owner'),
        MeetingAttendeeTypes.landOwner);
    expect(PersonMet.attendeeTypeFor('Agreement Holder / PoA'),
        MeetingAttendeeTypes.agreementHolder);
    for (final r in ['Son', 'Daughter', 'Spouse', 'Other relative']) {
      expect(PersonMet.attendeeTypeFor(r), MeetingAttendeeTypes.relative);
    }
    expect(PersonMet.attendeeTypeFor('Friend'), MeetingAttendeeTypes.friend);
    // Relative and Friend are separate choices now; the old combined one
    // is no longer offered.
    expect(MeetingAttendeeTypes.all, contains(MeetingAttendeeTypes.relative));
    expect(MeetingAttendeeTypes.all,
        isNot(contains(MeetingAttendeeTypes.familyOrFriend)));
  });

  test('lead contact type label', () {
    expect(LeadContactTypes.label('', ''), '');
    expect(LeadContactTypes.label(LeadContactTypes.landOwner, 'Son'),
        'Land Owner');
    expect(LeadContactTypes.label(LeadContactTypes.relative, 'Son'),
        'Relative of Owner (Son)');
  });
}
