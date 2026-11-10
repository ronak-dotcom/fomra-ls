import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/models/land_lead.dart';
import 'package:fomra_ls/screens/land_lead/lead_detail_screen.dart';
import 'package:fomra_ls/services/notification_hub.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  // Lead Detail talks to the auth layer; a dummy client with no stored
  // session makes no requests that matter here.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.invalid', anonKey: 'test-anon-key');
    Supabase.instance.client.auth.stopAutoRefresh();
  });

  testWidgets(
      'on a phone, Quick Actions show four buttons + More, and every other '
      'action is reachable from the More sheet', (t) async {
    t.view.physicalSize = const Size(400, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    await t.pumpWidget(MaterialApp(
      home: LeadDetailScreen(
        lead: LandLead(
          leadId: '40',
          inputSource: InputSource.broker,
          location: '',
          gpsCoordinates: '',
          village: '',
          taluk: '',
          district: '',
          pincode: '',
          surveyNumber: '',
          landExtent: '',
          ownerName: 'Murugan',
          contactDetails: '',
          landType: LandType.other,
          roadWidth: '',
          accessDetails: '',
          notes: '',
          addedOn: DateTime(2026, 10, 1),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }

    const secondary = [
      'Management site visit',
      'Follow-up',
      'Legal',
      'Deal & Risk',
      'Signed',
      'On Hold',
      'Split Lead',
      'Merge Lead',
      'Reassign',
    ];
    // The tall grid is gone: less-used actions are not on the page itself.
    expect(find.text('Split Lead'), findsNothing);
    expect(find.text('More'), findsOneWidget);

    await t.tap(find.text('More'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    for (final label in secondary) {
      expect(find.descendant(of: sheet, matching: find.text(label)),
          findsOneWidget,
          reason: '"$label" must be reachable from More');
    }

    await t.pumpWidget(const SizedBox());
    NotificationHub.instance.stop();
    await t.pump(const Duration(seconds: 15));
  });
}
