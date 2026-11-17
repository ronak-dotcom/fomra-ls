import 'package:flutter_test/flutter_test.dart';

import 'package:fomra_ls/analytics/business_module_metrics.dart';
import 'package:fomra_ls/models/land_lead.dart';
import 'package:fomra_ls/models/land_lead_meeting.dart';

final _now = DateTime(2026, 7, 15, 12);

LandLead _lead({
  required String id,
  LeadStatus status = LeadStatus.negotiation,
  Duration addedAgo = const Duration(days: 400),
}) =>
    LandLead(
      leadId: id,
      inputSource: InputSource.broker,
      location: 'loc',
      gpsCoordinates: '',
      village: 'v',
      taluk: 't',
      district: 'd',
      pincode: '600001',
      surveyNumber: '1/1',
      landExtent: '1 acre',
      ownerName: 'owner',
      contactDetails: '9000000000',
      landType: LandType.agricultural,
      roadWidth: '20',
      accessDetails: '',
      notes: '',
      addedOn: _now.subtract(addedAgo),
      status: status,
    );

LandLeadMeeting _meeting(String leadId, Duration fromNow) => LandLeadMeeting(
      id: '$leadId-${fromNow.inDays}',
      leadId: leadId,
      metAt: _now.add(fromNow),
      duration: '30m',
      notes: '',
      loggedByName: 'exec',
      createdAt: _now,
    );

List<String> _select(List<LandLead> leads, List<LandLeadMeeting> meetings) =>
    NoFutureActivityAnalytics.select(leads, meetings, now: _now)
        .map((l) => l.leadId)
        .toList();

void main() {
  group('NoFutureActivityAnalytics.select', () {
    test('flags an active lead that has never had a meeting', () {
      expect(_select([_lead(id: 'A')], const []), ['A']);
    });

    test('does not flag a lead with a meeting scheduled ahead', () {
      final lead = _lead(id: 'A');
      final upcoming = _meeting('A', const Duration(days: 3));
      expect(_select([lead], [upcoming]), isEmpty);
    });

    test('does not flag a lead whose last meeting is inside the window', () {
      final lead = _lead(id: 'A');
      final recent = _meeting('A', const Duration(days: -10));
      expect(_select([lead], [recent]), isEmpty);
    });

    test('flags a lead whose last meeting is older than 60 days', () {
      final lead = _lead(id: 'A');
      final stale = _meeting('A', const Duration(days: -61));
      expect(_select([lead], [stale]), ['A']);
    });

    test('an upcoming meeting rescues a lead with a stale past one', () {
      final lead = _lead(id: 'A');
      final meetings = [
        _meeting('A', const Duration(days: -90)),
        _meeting('A', const Duration(days: 2)),
      ];
      expect(_select([lead], meetings), isEmpty);
    });

    test('excludes dropped and signed leads', () {
      final leads = [
        _lead(id: 'DROPPED', status: LeadStatus.dropped),
        _lead(id: 'SIGNED', status: LeadStatus.signed),
        _lead(id: 'ACTIVE'),
      ];
      expect(_select(leads, const []), ['ACTIVE']);
    });

    test('a recent lead with no meetings is not yet stale', () {
      final fresh = _lead(id: 'A', addedAgo: const Duration(days: 5));
      expect(_select([fresh], const []), isEmpty);
    });

    test("another lead's meetings do not rescue this one", () {
      final leads = [_lead(id: 'A'), _lead(id: 'B')];
      final meetings = [_meeting('B', const Duration(days: 5))];
      expect(_select(leads, meetings), ['A']);
    });
  });
}
