import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/models/land_lead.dart';
import 'package:fomra_ls/models/lead_review.dart';
import 'package:fomra_ls/screens/land_lead/filtered_leads_screen.dart';
import 'package:fomra_ls/services/lead_review_service.dart';
import 'package:fomra_ls/services/notification_hub.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

LandLead _lead(String id) => LandLead(
      leadId: id,
      leadName: 'Vallakkottai 12 Acre',
      inputSource: InputSource.broker,
      location: '',
      gpsCoordinates: '12.8467, 80.0473',
      village: 'Vallakkottai',
      taluk: '',
      district: 'Kanchipuram',
      pincode: '',
      surveyNumber: '',
      landExtent: '',
      ownerName: '',
      contactDetails: '',
      landType: LandType.other,
      roadWidth: '',
      accessDetails: '',
      notes: '',
      addedOn: DateTime(2026, 1, 1),
      createdByName: 'Devaraj',
    );

DateTime _day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + offset);
}

void main() {
  // The row asks the auth layer whether the viewer may review, which needs a
  // Supabase client. A dummy one with no stored session makes no requests.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );
    // No session to refresh; its periodic timer would outlive the test.
    Supabase.instance.client.auth.stopAutoRefresh();
  });

  testWidgets(
      'overdue review list shows executive, last review, note and Map, '
      'and drops a property once it is reviewed', (t) async {
    t.view.physicalSize = const Size(1400, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    LeadReviewIndex.instance.debugSeed([
      LeadReview(
        id: '1',
        leadId: '40',
        reviewedAt: _day(-10),
        reviewedBy: 'Management',
        notes: 'Check patta copy before owner meeting',
        nextReviewDate: _day(-2),
      ),
    ]);

    await t.pumpWidget(MaterialApp(
      home: FilteredLeadsScreen(
        presetLeads: [_lead('40')],
        presetTitle: 'Reviews · Overdue',
        presetSubtitle: 'Active properties — review overdue',
        reviewFilter: ReviewFilter.overdue,
      ),
    ));
    await t.pump();

    expect(find.text('Vallakkottai 12 Acre'), findsOneWidget);
    expect(find.text('Executive: Devaraj'), findsOneWidget);
    expect(find.textContaining('Last reviewed'), findsOneWidget);
    expect(find.textContaining('by Management'), findsOneWidget);
    expect(find.text('Overdue 2d'), findsOneWidget);
    expect(find.text('Check patta copy before owner meeting'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Map'), findsOneWidget);

    // A new review with a future next date takes it off the Overdue list.
    LeadReviewIndex.instance.record(LeadReview(
      id: '2',
      leadId: '40',
      reviewedAt: DateTime.now(),
      nextReviewDate: _day(7),
    ));
    await t.pump();
    expect(find.text('Vallakkottai 12 Acre'), findsNothing);

    // The app shell's notification bell starts a poll + realtime channel;
    // stop them so no timer outlives the test.
    await t.pumpWidget(const SizedBox());
    NotificationHub.instance.stop();
    await t.pump(const Duration(seconds: 11));
  });
}
