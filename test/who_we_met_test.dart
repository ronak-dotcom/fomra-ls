import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/models/land_lead_meeting.dart';
import 'package:fomra_ls/widgets/who_we_met_card.dart';

LandLeadMeeting _m(DateTime at, List<String> types,
        {List<PersonMet> people = const [], bool mgmt = false}) =>
    LandLeadMeeting(
      id: '$at',
      leadId: '6',
      metAt: at,
      duration: '30',
      notes: '',
      loggedByName: 'Saurabh',
      createdAt: at,
      attendeeTypes: types,
      peopleMet: people,
      managementPresent: mgmt,
    );

void main() {
  test('status: owner, then agreement holder, then relatives, then none', () {
    expect(LandMeetingStatusX.of(const []), LandMeetingStatus.none);
    expect(
        LandMeetingStatusX.of([
          _m(DateTime(2026, 10, 2), [MeetingAttendeeTypes.agreementHolder]),
        ]),
        LandMeetingStatus.agreementHolderMet);
    expect(
        LandMeetingStatusX.of([
          _m(DateTime(2026, 10, 2), [MeetingAttendeeTypes.familyOrFriend]),
        ]),
        LandMeetingStatus.othersMet);
    expect(
        LandMeetingStatusX.of([
          _m(DateTime(2026, 10, 2), [MeetingAttendeeTypes.agreementHolder]),
          _m(DateTime(2026, 11, 6), const [],
              people: const [PersonMet(name: 'Kumar', relation: 'Land Owner')]),
        ]),
        LandMeetingStatus.ownerMet);
  });

  Future<void> pump(WidgetTester t, List<LandLeadMeeting> m) =>
      t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: WhoWeMetCard(meetings: m))),
      ));

  testWidgets('owner met: green headline and every meeting listed',
      (t) async {
    await pump(t, [
      _m(DateTime(2026, 8, 24), [MeetingAttendeeTypes.landOwner]),
      _m(DateTime(2026, 11, 6), const [],
          people: const [PersonMet(name: 'Kumar', relation: 'Land Owner')]),
      _m(DateTime(2026, 9, 14),
          [MeetingAttendeeTypes.landOwner, MeetingAttendeeTypes.broker],
          mgmt: true),
    ]);
    expect(find.text('WHO WE MET · 3 MEETINGS'), findsOneWidget);
    expect(find.text('Land Owner met'), findsOneWidget);
    expect(find.text('Kumar — Land Owner'), findsOneWidget);
    expect(find.text('14 Sep 2026 · Saurabh · Management present'),
        findsOneWidget);
  });

  testWidgets('only agreement holder: owner not met yet', (t) async {
    await pump(t, [
      _m(DateTime(2026, 10, 2),
          [MeetingAttendeeTypes.agreementHolder, MeetingAttendeeTypes.broker]),
    ]);
    expect(find.text('Owner not met yet'), findsOneWidget);
    expect(find.text('Agreement Holder / PoA'), findsOneWidget);
    expect(find.textContaining('Only the agreement holder'), findsOneWidget);
  });

  testWidgets('no meetings: says so', (t) async {
    await pump(t, const []);
    expect(find.text('No meeting yet'), findsOneWidget);
  });

  testWidgets('on phones it starts as one line and expands on tap',
      (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WhoWeMetCard(
          collapsible: true,
          onOpen: () {},
          meetings: [
            _m(DateTime(2026, 11, 6), [MeetingAttendeeTypes.landOwner]),
          ],
        ),
      ),
    ));
    expect(find.text('Land Owner met'), findsOneWidget);
    expect(find.text('6 Nov 2026 · Saurabh'), findsNothing);
    await t.tap(find.text('Land Owner met'));
    await t.pump();
    expect(find.text('6 Nov 2026 · Saurabh'), findsOneWidget);
    expect(find.text('Meeting history'), findsOneWidget);
  });

  test('old Family / Friend meetings read as Relative / Friend', () {
    expect(MeetingAttendeeTypes.short(MeetingAttendeeTypes.familyOrFriend),
        'Relative / Friend');
  });
}
