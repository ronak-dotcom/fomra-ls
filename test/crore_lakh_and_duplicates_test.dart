import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/analytics/management_intelligence.dart';
import 'package:fomra_ls/models/land_lead.dart';
import 'package:fomra_ls/widgets/crore_lakh_field.dart';

LandLead _lead(String id,
        {String village = 'Mappedu',
        String survey = '',
        String location = 'Thandalam Road',
        String owner = '',
        String phone = ''}) =>
    LandLead(
      leadId: id, inputSource: InputSource.broker, location: location,
      gpsCoordinates: '', village: village, taluk: '', district: 'D',
      pincode: '', surveyNumber: survey, landExtent: '', ownerName: owner,
      contactDetails: phone, landType: LandType.other, roadWidth: '',
      accessDetails: '', notes: '', addedOn: DateTime(2026, 11, 1),
      createdByName: 'Saurabh',
    );

void main() {
  group('Crores + Lakhs', () {
    test('format and total', () {
      expect(CroreLakh.format(7, 50), '₹7.50 Cr');
      expect(CroreLakh.format(5, 0), '₹5 Cr');
      expect(CroreLakh.format(0, 50), '₹50 L');
      expect(CroreLakh.format(7, 5), '₹7.05 Cr');
      expect(CroreLakh.rupees(7, 50), 75000000);
      expect(CroreLakh.grouped(75000000), '7,50,00,000');
    });

    test('reads what it writes and clear older entries', () {
      expect(CroreLakh.parse('₹7.50 Cr'), (7, 50));
      expect(CroreLakh.parse('₹50 L'), (0, 50));
      expect(CroreLakh.parse('3.5 cr per acre'), (3, 50));
      expect(CroreLakh.parse('10 cr per acre'), (10, 0));
      expect(CroreLakh.parse('40000000'), (4, 0));
      expect(CroreLakh.parse('75,00,000'), (0, 75));
    });

    test('leaves unclear entries alone', () {
      expect(CroreLakh.parse('4.5'), isNull);
      expect(CroreLakh.parse('DISCUSS WITH DIRECT'), isNull);
      expect(CroreLakh.parse(''), isNull);
    });
  });

  group('Duplicate check', () {
    test('same road / location alone is not a duplicate (Lead 133 vs 118)',
        () {
      final hits = ManagementIntelligence.findLiveDuplicates(
          _lead('new', survey: '1254'), [_lead('118')]);
      expect(hits, isEmpty);
    });

    test('same survey no. in the same village is', () {
      final hits = ManagementIntelligence.findLiveDuplicates(
          _lead('new', survey: '1254'), [_lead('87', survey: '1254')]);
      expect(hits.single.matchedFields.single,
          'Same survey no. 1254 in Mappedu');
    });

    test('same survey no. in another village is not', () {
      final hits = ManagementIntelligence.findLiveDuplicates(
          _lead('new', survey: '12'),
          [_lead('9', survey: '12', village: 'Nemili')]);
      expect(hits, isEmpty);
    });

    test('same owner mobile anywhere is', () {
      final hits = ManagementIntelligence.findLiveDuplicates(
          _lead('new', phone: '9841309113'),
          [_lead('9', village: 'Nemili', phone: '9841309113')]);
      expect(hits.single.matchedFields.single,
          'Same owner mobile 9841309113');
    });
  });
}
