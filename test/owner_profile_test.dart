import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/models/land_lead.dart';
import 'package:fomra_ls/models/owner_profile.dart';
import 'package:fomra_ls/screens/land_lead/meeting_log_dialog.dart';
import 'package:fomra_ls/services/meeting_flags_index.dart';
import 'package:fomra_ls/widgets/land_workspace_ui.dart';
import 'package:fomra_ls/widgets/owner_profile_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

LandLead _lead(String id,
        {String type = '',
        String profession = '',
        String lives = '',
        String town = '',
        String decision = '',
        LeadStatus status = LeadStatus.prospectMeetingPending}) =>
    LandLead(
      leadId: id, inputSource: InputSource.broker, location: '',
      gpsCoordinates: '', village: 'V', taluk: '', district: 'D', pincode: '',
      surveyNumber: '', landExtent: '', ownerName: 'Ravi', contactDetails: '',
      landType: LandType.other, roadWidth: '', accessDetails: '', notes: '',
      addedOn: DateTime(2026, 11, 1), createdByName: 'Saurabh', status: status,
      ownerOccupation: type, ownerProfession: profession, ownerLives: lives,
      ownerTown: town, ownerDecision: decision,
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
    expect(OwnerProfile.decisionLabel('family'), 'Family decides together');
    expect(OwnerProfile.typeLabel('Doctor'), 'Doctor');
  });

  test('profile values: locality + town read as one place', () {
    final v = OwnerProfileValues.of(
        _lead('1', lives: 'Velachery', town: 'Chennai'));
    expect(v.livesAt, 'Velachery, Chennai');
    expect(const OwnerProfileValues(town: 'Chennai').livesAt, 'Chennai');
    expect(v.applyTo(_lead('2')).ownerLives, 'Velachery');
  });

  test('Owner type filter keeps only the chosen types', () {
    final f = LandWorkspaceFilters(ownerTypes: {'farmer', 'politician'});
    expect(f.matches(_lead('1', type: 'farmer')), isTrue);
    expect(f.matches(_lead('2', type: 'business')), isFalse);
    expect(f.matches(_lead('3')), isFalse);
    expect(f.activeCount, 2);
    f.clear();
    expect(f.matches(_lead('3')), isTrue);
  });

  test('"Had a management meeting" keeps dropped leads with one', () {
    MeetingFlagsIndex.instance.debugSeed(['7']);
    final f = LandWorkspaceFilters(hadManagementMeeting: true);
    expect(f.matches(_lead('7', status: LeadStatus.dropped)), isTrue);
    expect(f.matches(_lead('8', status: LeadStatus.dropped)), isFalse);
    expect(
        f.matches(_lead('9', status: LeadStatus.managementMeetingCompleted)),
        isTrue);
    expect(f.copy().hadManagementMeeting, isTrue);
  });

  test('stage after a meeting', () {
    expect(
        statusAfterMeeting(LeadStatus.prospectMeetingPending,
            managementPresent: false),
        LeadStatus.prospectMeetingCompleted);
    expect(
        statusAfterMeeting(LeadStatus.prospectMeetingCompleted,
            managementPresent: true),
        LeadStatus.managementMeetingCompleted);
    expect(
        statusAfterMeeting(LeadStatus.negotiation, managementPresent: true),
        isNull);
    expect(
        statusAfterMeeting(LeadStatus.prospectMeetingCompleted,
            managementPresent: false),
        isNull);
  });

  testWidgets('lead page strip shows the profile once, or a prompt',
      (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          OwnerProfileStrip(
              lead: _lead('1',
                  type: 'business',
                  profession: 'Runs a rice mill',
                  lives: 'Velachery',
                  town: 'Chennai',
                  decision: 'family'),
              canEdit: false),
          OwnerProfileStrip(lead: _lead('2'), canEdit: false),
        ]),
      ),
    ));
    expect(find.text('Business / Trader'), findsOneWidget);
    expect(find.text('· Runs a rice mill'), findsOneWidget);
    expect(find.text('· Lives at Velachery, Chennai'), findsOneWidget);
    expect(find.text('· Family decides together'), findsOneWidget);
    expect(find.textContaining('not recorded yet'), findsOneWidget);
  });

  testWidgets(
      'meeting form: owner profile and owner mobile only when the owner is met',
      (t) async {
    t.view.physicalSize = const Size(600, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child:
              MeetingLogDialog(leadId: '1', ownerName: 'Ravi', lead: _lead('1')),
        ),
      ),
    ));
    await t.pump();
    expect(find.text('Owner profile'), findsNothing);
    expect(find.text('Owner mobile'), findsNothing);
    await t.tap(find.widgetWithText(FilterChip, 'Land Owner'));
    await t.pump();
    expect(find.text('Owner profile'), findsOneWidget);
    expect(find.text('Lives at — locality / village (optional)'),
        findsOneWidget);

    // Choosing "Land Owner" as a person's relation asks for their mobile.
    await t.tap(find.byKey(const ValueKey('person-relation-0')));
    await t.pumpAndSettle();
    await t.tap(find.text('Land Owner').last);
    await t.pumpAndSettle();
    expect(find.text('Owner mobile'), findsOneWidget);
  });
}
