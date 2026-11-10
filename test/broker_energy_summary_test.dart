import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/models/land_lead.dart';
import 'package:fomra_ls/services/land_lead_meeting_service.dart';
import 'package:fomra_ls/widgets/broker_energy_summary.dart';

LandLead _lead(String id, String broker) => LandLead(
      leadId: id,
      inputSource: InputSource.broker,
      location: '',
      gpsCoordinates: '',
      village: '',
      taluk: '',
      district: '',
      pincode: '',
      surveyNumber: '',
      landExtent: '',
      ownerName: '',
      contactDetails: '',
      landType: LandType.other,
      roadWidth: '',
      accessDetails: '',
      notes: '',
      addedOn: DateTime(2026, 10, 1),
      brokerName: broker,
    );

void main() {
  tearDown(() => LandLeadMeetingService.debugOwnerMetIds = null);

  testWidgets('home card lists Energisers and Drainers under headings',
      (t) async {
    LandLeadMeetingService.debugOwnerMetIds = {'1', '2', '3'};
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BrokerEnergySummary(leads: [
            _lead('1', 'Kalaiselvakumar'), _lead('2', 'Kalaiselvakumar'),
            _lead('3', 'Selvam'), _lead('4', 'Selvam'),
            _lead('5', 'Selvam'), _lead('6', 'Selvam'),
          ]),
        ),
      ),
    ));
    await t.pump();

    expect(find.text('Energisers'), findsOneWidget);
    expect(find.text('Drainers'), findsOneWidget);
    expect(find.text('Kalaiselvakumar'), findsOneWidget);
    expect(find.text('met 2/2 · 100%'), findsOneWidget);
    expect(find.text('Selvam'), findsOneWidget);
    expect(find.text('met 1/4 · 25%'), findsOneWidget);
  });
}
