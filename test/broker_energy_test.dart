import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/analytics/broker_energy.dart';
import 'package:fomra_ls/models/land_lead.dart';

LandLead _lead(String id, String broker,
        {LeadStatus status = LeadStatus.prospectMeetingPending,
        DateTime? addedOn}) =>
    LandLead(
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
      addedOn: addedOn ?? DateTime(2026, 10, 1),
      brokerName: broker,
      status: status,
    );

void main() {
  test('thresholds: above 60% giver, 40–60% average, under 40% drainer', () {
    expect(BrokerEnergyX.ofRate(100), BrokerEnergy.giver);
    expect(BrokerEnergyX.ofRate(61), BrokerEnergy.giver);
    expect(BrokerEnergyX.ofRate(60), BrokerEnergy.average);
    expect(BrokerEnergyX.ofRate(40), BrokerEnergy.average);
    expect(BrokerEnergyX.ofRate(39.9), BrokerEnergy.drainer);
    expect(BrokerEnergyX.ofRate(0), BrokerEnergy.drainer);
  });

  test('ranks brokers by owner-meeting share, one land is enough', () {
    final leads = [
      // Kumar: 2 of 3 with an owner meeting → 67% giver.
      _lead('1', 'Kumar'), _lead('2', 'kumar '), _lead('3', 'Kumar'),
      // Selvam: 1 of 4 → 25% drainer.
      _lead('4', 'Selvam'), _lead('5', 'Selvam'),
      _lead('6', 'Selvam'), _lead('7', 'Selvam'),
      // Mani: a single land, converted (counts as owner met) → giver.
      _lead('8', 'Mani', status: LeadStatus.values
          .firstWhere((s) => s.isAcquired)),
      // Anand: 1 of 2 → 50% average.
      _lead('9', 'Anand', addedOn: DateTime(2026, 11, 9)),
      _lead('10', 'Anand', addedOn: DateTime(2026, 9, 1)),
      // No broker: ignored.
      _lead('11', ''),
    ];
    final rows =
        BrokerEnergyAnalytics.compute(leads, {'1', '3', '4', '9'});

    expect(rows.map((r) => r.name), ['Mani', 'Kumar', 'Anand', 'Selvam']);
    final byName = {for (final r in rows) r.name: r};
    expect(byName['Kumar']!.lands, 3);
    expect(byName['Kumar']!.ownerMeetings, 2);
    expect(byName['Kumar']!.energy, BrokerEnergy.giver);
    expect(byName['Mani']!.energy, BrokerEnergy.giver);
    expect(byName['Mani']!.converted, 1);
    expect(byName['Anand']!.energy, BrokerEnergy.average);
    expect(byName['Anand']!.lastLandOn, DateTime(2026, 11, 9));
    expect(byName['Selvam']!.energy, BrokerEnergy.drainer);
    expect(byName['Selvam']!.withoutMeeting, 3);
  });
}
