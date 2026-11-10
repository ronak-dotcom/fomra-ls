import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/models/land_lead.dart';
import 'package:fomra_ls/services/land_lead_service.dart';

LandLead _lead({
  String gps = '12.724987° N, 79.965499° E',
  String location = 'Chennai Metropolitan Area',
  String survey = '40',
  String village = 'Pulipakkam',
  DateTime? addedOn,
}) =>
    LandLead(
      leadId: '123',
      inputSource: InputSource.broker,
      location: location,
      gpsCoordinates: gps,
      village: village,
      taluk: '',
      district: '',
      pincode: '',
      surveyNumber: survey,
      landExtent: '',
      ownerName: 'Owner',
      contactDetails: '',
      landType: LandType.other,
      roadWidth: '',
      accessDetails: '',
      notes: '',
      addedOn: addedOn ?? DateTime(2026, 11, 10, 9, 0),
    );

void main() {
  final created = DateTime(2026, 11, 10, 9, 0);
  final twoHoursLater = created.add(const Duration(hours: 2));
  final halfHourLater = created.add(const Duration(minutes: 30));

  test('moving the map pin after the free window needs approval', () {
    final before = _lead(addedOn: created);
    // ~3 km away.
    final after = _lead(gps: '12.75° N, 79.98° E', addedOn: created);
    final r = LandLeadService.splitCoreFieldChanges(after, before,
        now: twoHoursLater);
    expect(r.pending.map((c) => c.field), contains('gps_coordinates'));
    expect(r.apply.containsKey('gps_coordinates'), isFalse);
  });

  test('changing the location text after the free window needs approval', () {
    final before = _lead(addedOn: created);
    final after = _lead(location: 'Somewhere else', addedOn: created);
    final r = LandLeadService.splitCoreFieldChanges(after, before,
        now: twoHoursLater);
    expect(r.pending.map((c) => c.field), ['location']);
  });

  test('same-day edits are no longer free after 1 hour (survey 40 -> 725)',
      () {
    final before = _lead(addedOn: created);
    final after = _lead(survey: '725', addedOn: created);
    final r = LandLeadService.splitCoreFieldChanges(after, before,
        now: twoHoursLater);
    expect(r.pending.map((c) => c.field), ['survey_number']);
  });

  test('within the first hour, changes apply directly', () {
    final before = _lead(addedOn: created);
    final after = _lead(
        survey: '725', gps: '12.75° N, 79.98° E', addedOn: created);
    final r = LandLeadService.splitCoreFieldChanges(after, before,
        now: halfHourLater);
    expect(r.pending, isEmpty);
    expect(r.apply['survey_number'], '725');
    expect(r.apply['gps_coordinates'], '12.75° N, 79.98° E');
  });

  test('filling a blank field is always free', () {
    final before = _lead(gps: '', addedOn: created);
    final after = _lead(addedOn: created);
    final r = LandLeadService.splitCoreFieldChanges(after, before,
        now: twoHoursLater);
    expect(r.pending, isEmpty);
    expect(r.apply.containsKey('gps_coordinates'), isTrue);
  });

  test('re-capturing GPS at the same spot (a few metres off, other format) '
      'is not a change', () {
    final before = _lead(addedOn: created);
    // Same point ~10 m away, stored in the LIVE| format.
    final after = _lead(
      gps: 'LIVE|12.725070|79.965520|8.0|2026-11-10T11:00:00.000Z',
      addedOn: created,
    );
    final r = LandLeadService.splitCoreFieldChanges(after, before,
        now: twoHoursLater);
    expect(r.pending, isEmpty);
    expect(r.apply.containsKey('gps_coordinates'), isFalse);
  });
}
