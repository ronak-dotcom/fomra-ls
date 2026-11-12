import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/analytics/team_performance.dart';
import 'package:fomra_ls/models/land_lead.dart';
import 'package:fomra_ls/models/land_lead_meeting.dart';
import 'package:fomra_ls/models/monthly_target_submission.dart';
import 'package:fomra_ls/widgets/team_performance_card.dart';

LandLead _lead(String id, String by, DateTime on,
        {LeadStatus status = LeadStatus.prospectMeetingPending,
        String extent = ''}) =>
    LandLead(
      leadId: id,
      inputSource: InputSource.broker,
      location: '',
      gpsCoordinates: '',
      village: 'V',
      taluk: '',
      district: 'D',
      pincode: '',
      surveyNumber: '',
      landExtent: extent,
      ownerName: '',
      contactDetails: '',
      landType: LandType.other,
      roadWidth: '',
      accessDetails: '',
      notes: '',
      addedOn: on,
      createdByName: by,
      status: status,
    );

LandLeadMeeting _meet(String id, String lead, String by, DateTime at,
        {bool mgmt = false}) =>
    LandLeadMeeting(
      id: id,
      leadId: lead,
      metAt: at,
      duration: '',
      notes: '',
      loggedByName: by,
      createdAt: at,
      managementPresent: mgmt,
    );

MonthlyTargetSubmission _target(String name, Map<String, int> v,
        {TargetSubmissionStatus status = TargetSubmissionStatus.approved}) =>
    MonthlyTargetSubmission(
      id: name,
      period: '2026-11',
      employeeEmail: '$name@x',
      employeeName: name,
      submittedValues: v,
      status: status,
      submittedAt: DateTime(2026, 11, 1),
    );

// Thursday 12 Nov 2026, 3 pm (day 12 of 30). Week starts Monday 9 Nov.
final _now = DateTime(2026, 11, 12, 15);
final _leads = [
  _lead('1', 'Saurabh', DateTime(2026, 11, 12, 10)),
  _lead('2', 'Saurabh', DateTime(2026, 11, 9)),
  _lead('3', 'Saurabh', DateTime(2026, 11, 2)),
  _lead('4', 'Devaraj', DateTime(2026, 11, 3), status: LeadStatus.legal),
  _lead('5', 'Devaraj', DateTime(2026, 10, 1),
      status: LeadStatus.signed, extent: '2 acre'),
  _lead('6', 'Management', DateTime(2026, 11, 5)),
];
final _meetings = [
  _meet('a', '5', 'Devaraj', DateTime(2026, 10, 2)), // Oct: first self on 5
  _meet('b', '5', 'Devaraj', DateTime(2026, 11, 4)), // repeat: not counted
  _meet('c', '4', 'Devaraj', DateTime(2026, 11, 5)), // first self on 4
  _meet('d', '4', 'Devaraj', DateTime(2026, 11, 6), mgmt: true),
];
final _targets = [
  _target('Saurabh', {'site_visits': 10, 'self_meetings': 4}),
  _target('Devaraj', {'site_visits': 10, 'management_meetings': 2}),
  _target('Ravi', {'site_visits': 8}, status: TargetSubmissionStatus.pending),
];

void main() {
  final rows = TeamPerformanceRow.build(
      leads: _leads, meetings: _meetings, targets: _targets, now: _now);

  test('ranked by site visits this month; Management left out', () {
    expect(rows.map((r) => (r.executive, r.rank)),
        [('Saurabh', 1), ('Devaraj', 2)]);
  });

  test('today / week / month against the approved target', () {
    final s = rows.first;
    expect([s.today.length, s.week.length, s.siteVisits.achieved], [1, 2, 3]);
    expect(s.siteVisits.target, 10);
    // Day 12 of 30 on 10 expects 4; 3 is behind, not far behind.
    expect(paceOf(s.siteVisits.progress), TargetPace.behind);
    expect(paceOf(s.managementMeetings.progress), TargetPace.none);
  });

  test('meetings count the first per land; pipeline is all time', () {
    final d = rows.last;
    expect(d.selfMeetings.achieved, 1);
    expect(d.selfMeetings.leadIds, ['4']);
    expect(d.managementMeetings.achieved, 1);
    expect(paceOf(d.managementMeetings.progress), TargetPace.onPace);
    expect([d.leads.length, d.legal.length, d.closed.length], [2, 1, 1]);
    expect(d.closedAcres, closeTo(2, 0.01));
  });

  test('a pending target does not count', () {
    expect(rows.any((r) => r.executive == 'Ravi'), isFalse);
  });

  testWidgets('phone: tap a name to show the pipeline', (t) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TeamPerformanceCard(
              leads: _leads, meetings: _meetings, targets: _targets, now: _now),
        ),
      ),
    ));
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('PIPELINE · ALL TIME'), findsNothing);
    await t.tap(find.text('Devaraj'));
    await t.pump();
    expect(find.text('PIPELINE · ALL TIME'), findsOneWidget);
    expect(find.text('2.0 ac'), findsOneWidget);
  });

  testWidgets('an executive sees only their own row, no rank', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TeamPerformanceCard(
            leads: _leads,
            meetings: _meetings,
            targets: _targets,
            now: _now,
            onlyExecutive: 'Devaraj'),
      ),
    ));
    expect(find.text('Devaraj'), findsOneWidget);
    expect(find.text('Saurabh'), findsNothing);
    expect(find.textContaining('#'), findsNothing);
  });
}
