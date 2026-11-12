import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/analytics/monthly_target_progress.dart';
import 'package:fomra_ls/models/land_lead.dart';
import 'package:fomra_ls/models/land_lead_site_visit.dart';
import 'package:fomra_ls/services/report_catalog_service.dart';
import 'package:fomra_ls/widgets/site_visit_summary.dart';

LandLead _lead(String id, String by, DateTime on) => LandLead(
      leadId: id,
      inputSource: InputSource.broker,
      location: '',
      gpsCoordinates: '',
      village: 'Pulipakkam',
      taluk: '',
      district: 'Chengalpattu',
      pincode: '',
      surveyNumber: '',
      landExtent: '',
      ownerName: '',
      contactDetails: '',
      landType: LandType.other,
      roadWidth: '',
      accessDetails: '',
      notes: '',
      addedOn: on,
      createdByName: by,
    );

// Thursday 12 Nov 2026, 3 pm. Week starts Monday 9 Nov.
final _now = DateTime(2026, 11, 12, 15);
final _leads = [
  _lead('1', 'Saurabh', DateTime(2026, 11, 12, 10)), // today
  _lead('2', 'Saurabh', DateTime(2026, 11, 9, 9)), // Monday: this week
  _lead('3', 'Saurabh', DateTime(2026, 11, 8, 18)), // Sunday: last week
  _lead('4', 'Devaraj', DateTime(2026, 11, 3)), // this month
  _lead('5', 'Devaraj', DateTime(2026, 10, 31)), // last month
];

void main() {
  test('today / this week (from Monday) / this month per executive', () {
    final rows = SiteVisitPeriods.byExecutive(_leads, now: _now);
    expect(rows.map((r) => r.executive), ['Saurabh', 'Devaraj']);
    final s = rows.first;
    expect([s.today.length, s.week.length, s.month.length], [1, 2, 3]);
    final d = rows.last;
    expect([d.today.length, d.week.length, d.month.length], [0, 0, 1]);
  });

  testWidgets('card shows a team total and each executive', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: SiteVisitSummary(leads: _leads, now: _now)),
    ));
    expect(find.text('Team total'), findsOneWidget);
    expect(find.text('Saurabh'), findsOneWidget);
    expect(find.text('THIS WEEK'), findsOneWidget);
  });

  testWidgets('an executive sees only their own row', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SiteVisitSummary(
            leads: _leads, now: _now, onlyExecutive: 'Devaraj'),
      ),
    ));
    expect(find.text('Devaraj'), findsOneWidget);
    expect(find.text('Saurabh'), findsNothing);
    expect(find.text('Team total'), findsNothing);
  });

  test('Site Visit report: new Lead IDs by executive, revisits apart', () {
    final data = ReportCatalogService.buildPreview(
      kind: ReportKind.siteVisit,
      leads: _leads,
      siteVisits: [
        LandLeadSiteVisit(
          id: 'v',
          leadId: '4',
          visitedAt: DateTime(2026, 11, 7),
          loggedByName: 'Devaraj',
          createdAt: DateTime(2026, 11, 7),
          visitType: LandLeadSiteVisitType.management,
        ),
        // A visit on a land outside the filtered leads is left out.
        LandLeadSiteVisit(
          id: 'w',
          leadId: '99',
          visitedAt: DateTime(2026, 11, 7),
          loggedByName: 'Devaraj',
          createdAt: DateTime(2026, 11, 7),
        ),
      ],
    );
    expect(data.summary.first.value, '5');
    final byExec = data.sections[0];
    expect(byExec.rows.first.sublist(0, 2), ['Saurabh', '3']);
    expect(data.sections[1].rows.length, 5);
    expect(data.sections[2].rows.single.first, '4');
  });
}
