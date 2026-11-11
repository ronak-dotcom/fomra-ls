import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/analytics/broker_energy.dart';
import 'package:fomra_ls/analytics/business_module_metrics.dart';
import 'package:fomra_ls/models/land_lead.dart';
import 'package:fomra_ls/services/broker_directory.dart';
import 'package:fomra_ls/services/report_catalog_service.dart';

LandLead _lead(String id, String broker, String phone, {DateTime? on}) =>
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
      addedOn: on ?? DateTime.now().subtract(const Duration(days: 5)),
      brokerName: broker,
      brokerContact: phone,
    );

void main() {
  setUp(() => BrokerDirectory.instance.debugSeed(const [
        BrokerEntry(
          phone: '9514813669',
          displayName: 'K. Mani',
          aliases: ['mani', 'K.MANI', 'k.mani'],
        ),
        BrokerEntry(
          phone: '9841309113',
          displayName: 'Sebastin',
          aliases: ['sebastin', 'sabestin'],
        ),
        BrokerEntry(phone: '9876500001', displayName: 'Kalaiarasu'),
      ]));

  test('phone key is the last 10 digits; short numbers have none', () {
    expect(BrokerDirectory.phoneKey('+91 95148-13669'), '9514813669');
    expect(BrokerDirectory.phoneKey('12345'), isNull);
    expect(BrokerDirectory.formatPhone('9514813669'), '95148 13669');
  });

  test('a lead shows the directory name for its number', () {
    final l = _lead('1', 'mani', '95148 13669');
    expect(l.brokerDisplayName, 'K. Mani');
    // Unknown number: what was typed.
    expect(_lead('2', 'Raju', '9000000000').brokerDisplayName, 'Raju');
  });

  test('suggestions find near-spellings and partial numbers', () {
    expect(BrokerDirectory.instance.suggest('kalai').first.displayName,
        'Kalaiarasu');
    expect(BrokerDirectory.instance.suggest('sabastin').first.displayName,
        'Sebastin');
    expect(BrokerDirectory.instance.suggest('98413').single.displayName,
        'Sebastin');
    expect(BrokerDirectory.instance.suggest('k'), isEmpty);
  });

  test('one number typed under several names is one broker everywhere', () {
    final leads = [
      _lead('1', 'mani', '9514813669'),
      _lead('2', 'K.MANI', '9514813669'),
      _lead('3', 'kalaiarasi(maheshwari)', '9514813669'),
      // Same name, different number: a different broker.
      _lead('4', 'mani', '9381154120'),
    ];
    final perf = BrokerPerformanceAnalytics.compute(leads);
    expect(perf.length, 2);
    final kMani = perf.firstWhere((r) => r.key == '9514813669');
    expect(kMani.name, 'K. Mani');
    expect(kMani.leads, 3);

    final energy = BrokerEnergyAnalytics.compute(leads, {'1'});
    expect(energy.firstWhere((r) => r.key == '9514813669').ownerMeetings, 1);
  });

  test('ranking window keeps only lands from the last 120 days', () {
    final now = DateTime(2026, 11, 11);
    final leads = [
      _lead('1', 'a', '9000000001', on: DateTime(2026, 11, 1)),
      _lead('2', 'a', '9000000001', on: DateTime(2026, 5, 1)),
    ];
    expect(BrokerEnergyAnalytics.recent(leads, now: now).map((l) => l.leadId),
        ['1']);
  });

  test('broker report is lifetime, one row per number, with owner met %', () {
    final data = ReportCatalogService.buildPreview(
      kind: ReportKind.broker,
      leads: [
        _lead('1', 'mani', '9514813669'),
        _lead('2', 'K.MANI', '9514813669',
            on: DateTime.now().subtract(const Duration(days: 400))),
        _lead('3', 'sabestin', '9841309113'),
      ],
      ownerMetLeadIds: {'1', '2'},
    );
    final sec = data.sections.single;
    expect(sec.rows.length, 2);
    final mani = sec.rows.firstWhere((r) => r.first == 'K. Mani');
    // The 400-day-old land counts: the report is lifetime.
    expect(mani.sublist(1, 6), ['95148 13669', '2', '2', '100%', 'Energiser']);
    expect(sec.rowLeads[sec.rows.indexOf(mani)].length, 2);
  });
}
