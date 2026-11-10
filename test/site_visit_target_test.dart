import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/analytics/monthly_target_progress.dart';
import 'package:fomra_ls/models/land_lead.dart';

LandLead _lead(String id, String by, DateTime on) => LandLead(
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
      addedOn: on,
      createdByName: by,
    );

void main() {
  test('a site visit is each new Lead ID the executive created', () {
    final leads = [
      _lead('123', 'Devaraj', DateTime(2026, 11, 10)),
      _lead('122', 'devaraj ', DateTime(2026, 11, 10)),
      _lead('118', 'Saurabh', DateTime(2026, 11, 9)),
    ];
    expect(SiteVisitTarget.datesFor(leads, 'Devaraj'),
        [DateTime(2026, 11, 10), DateTime(2026, 11, 10)]);
    expect(SiteVisitTarget.leadsVisitedBy(leads, 'Saurabh').single.leadId,
        '118');
    expect(SiteVisitTarget.datesFor(leads, ''), isEmpty);
  });
}
