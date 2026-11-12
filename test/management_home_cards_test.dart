import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/models/land_lead.dart';
import 'package:fomra_ls/widgets/management_home_cards.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

LandLead _lead(String id, LeadStatus s, int daysAgo, {String extent = '1 acre'}) =>
    LandLead(
      leadId: id, inputSource: InputSource.broker, location: '',
      gpsCoordinates: '', village: 'V', taluk: '', district: 'D', pincode: '',
      surveyNumber: '', landExtent: extent, ownerName: '', contactDetails: '',
      landType: LandType.other, roadWidth: '', accessDetails: '', notes: '',
      addedOn: DateTime(2026, 11, 12).subtract(Duration(days: daysAgo)),
      createdByName: 'Saurabh', status: s,
    );

final _leads = [
  _lead('1', LeadStatus.prospectMeetingPending, 5),
  _lead('2', LeadStatus.prospectMeetingPending, 120),
  _lead('3', LeadStatus.legal, 100),
  _lead('4', LeadStatus.signed, 200, extent: '2 acre'),
  _lead('5', LeadStatus.dropped, 300),
  _lead('6', LeadStatus.prospectMeetingCompleted, 10),
  _lead('7', LeadStatus.managementMeetingCompleted, 10),
  _lead('8', LeadStatus.onHold, 10),
];

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.invalid', anonKey: 'x');
  });

  testWidgets('Needs attention counts and "All clear"', (t) async {
    t.view.physicalSize = const Size(1000, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NeedsAttentionCard(
          leads: _leads,
          approvalCount: 0,
          noNextStep: [_leads.first],
          now: DateTime(2026, 11, 12),
        ),
      ),
    ));
    expect(find.text('All clear'), findsWidgets); // no approvals
    Text countOf(String title) => t.widget<Text>(find.descendant(
        of: find.ancestor(of: find.text(title), matching: find.byType(Row)).first,
        matching: find.byWidgetPredicate(
            (w) => w is Text && int.tryParse(w.data ?? '') != null)));
    expect(countOf('Owner not met yet').data, '2');
    // Open (not closed / dropped) and added over 90 days ago: 2 and 3.
    expect(countOf('Open over 90 days').data, '2');
    expect(countOf('In legal').data, '1');
    expect(countOf('No next step planned').data, '1');
  });

  testWidgets('Property pipeline: stages with acres, on hold / dropped',
      (t) async {
    t.view.physicalSize = const Size(1000, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: PropertyPipelineCard(leads: _leads)),
    ));
    expect(find.text('Owner meeting pending'), findsOneWidget);
    // Owner met = completed + management meeting completed.
    final met = find.ancestor(
        of: find.text('Owner met'), matching: find.byType(Column)).first;
    expect(find.descendant(of: met, matching: find.text('2')), findsOneWidget);
    expect(find.text('2.0 ac'), findsWidgets); // closed: one 2-acre site
    expect(find.text('1 on hold'), findsOneWidget);
    expect(find.text('1 dropped'), findsOneWidget);
  });
}
