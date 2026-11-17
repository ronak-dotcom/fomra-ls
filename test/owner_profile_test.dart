import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/models/land_lead.dart';
import 'package:fomra_ls/models/owner_profile.dart';
import 'package:fomra_ls/screens/land_lead/meeting_log_dialog.dart';
import 'package:fomra_ls/widgets/land_workspace_ui.dart';
import 'package:fomra_ls/widgets/owner_profile_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

LandLead _lead(String id, {String type = '', String lives = '', String decision = ''}) =>
    LandLead(
      leadId: id, inputSource: InputSource.broker, location: '',
      gpsCoordinates: '', village: 'V', taluk: '', district: 'D', pincode: '',
      surveyNumber: '', landExtent: '', ownerName: 'Ravi', contactDetails: '',
      landType: LandType.other, roadWidth: '', accessDetails: '', notes: '',
      addedOn: DateTime(2026, 11, 1), createdByName: 'Saurabh',
      ownerOccupation: type, ownerLives: lives, ownerDecision: decision,
    );

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.invalid', anonKey: 'x');
  });

  test('labels: known keys, short names, and old free text as written', () {
    expect(OwnerProfile.types.length, 9);
    expect(OwnerProfile.typeLabel('farmer'), 'Farmer / Agriculturist');
    expect(OwnerProfile.typeShort('institution'), 'Institution');
    expect(OwnerProfile.livesLabel('chennai'), 'Chennai');
    expect(OwnerProfile.decisionLabel('family'), 'Family decides together');
    expect(OwnerProfile.typeLabel('Doctor'), 'Doctor');
  });

  test('Owner type filter keeps only the chosen types', () {
    final f = LandWorkspaceFilters(ownerTypes: {'farmer', 'politician'});
    expect(f.matches(_lead('1', type: 'farmer')), isTrue);
    expect(f.matches(_lead('2', type: 'business')), isFalse);
    expect(f.matches(_lead('3')), isFalse);
    expect(f.activeCount, 2);
    expect(f.copy().ownerTypes, {'farmer', 'politician'});
    f.clear();
    expect(f.matches(_lead('3')), isTrue);
  });

  testWidgets('lead page strip shows the profile, or a prompt', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          OwnerProfileStrip(
              lead: _lead('1', type: 'farmer', lives: 'local_village',
                  decision: 'family'),
              canEdit: false),
          OwnerProfileStrip(lead: _lead('2'), canEdit: false),
        ]),
      ),
    ));
    expect(find.text('Farmer / Agriculturist'), findsOneWidget);
    expect(find.text('· In the village'), findsOneWidget);
    expect(find.text('· Family decides together'), findsOneWidget);
    expect(find.textContaining('not recorded yet'), findsOneWidget);
  });

  testWidgets('meeting form asks the owner profile only when the owner is met',
      (t) async {
    t.view.physicalSize = const Size(600, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MeetingLogDialog(leadId: '1', ownerName: 'Ravi', lead: _lead('1')),
      ),
    ));
    await t.pump();
    expect(find.text('Owner profile'), findsNothing);
    await t.tap(find.widgetWithText(FilterChip, 'Land Owner'));
    await t.pump();
    expect(find.text('Owner profile'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Farmer'), findsOneWidget);
  });
}
