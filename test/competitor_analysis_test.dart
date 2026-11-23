import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/models/competitor_project.dart';
import 'package:fomra_ls/models/land_lead.dart';
import 'package:fomra_ls/utils/competitor_analysis.dart';
import 'package:fomra_ls/utils/maps_link_pin.dart';

LandLead lead(String id, {String gps = '', String village = '', String extent = ''}) =>
    LandLead(
      leadId: id,
      inputSource: InputSource.broker,
      location: '',
      gpsCoordinates: gps,
      village: village,
      taluk: '',
      district: '',
      pincode: '',
      surveyNumber: '',
      landExtent: extent,
      ownerName: '',
      contactDetails: '',
      landType: LandType.other,
      roadWidth: '',
      accessDetails: '',
      notes: '',
      addedOn: DateTime(2026, 1, 1),
    );

CompetitorProject project(
  String id, {
  double? lat,
  double? lng,
  String village = '',
  double? quoted,
  double? negotiated,
  CompetitorType type = CompetitorType.layout,
  List<CompetitorPhase> phases = const [],
  List<String> links = const [],
  DateTime? checked,
  String ownerEmail = '',
}) =>
    CompetitorProject(
      id: id,
      code: id,
      name: 'Project $id',
      lat: lat,
      lng: lng,
      village: village,
      quotedPrice: quoted,
      negotiatedPrice: negotiated,
      type: type,
      phases: phases,
      linkedLeadIds: links,
      lastCheckedAt: checked,
      ownerEmail: ownerEmail,
    );

void main() {
  // Lead 135 (Serapanenchery) and a few projects around it.
  final l135 = lead('135', gps: '12.858079, 79.981719', village: 'Serapanenchery', extent: '1.05 acres');
  final springField = project('springfield', lat: 12.86207, lng: 79.979943, quoted: 2400, negotiated: 2100);
  final aloka = project('aloka', lat: 12.8843879, lng: 79.9849435, quoted: 2999, negotiated: 2799);
  final markAvenue = project('mark', lat: 12.9142547, lng: 80.0324985, quoted: 3500, negotiated: 3000);
  final noPinSameVillage = project('village', village: 'serapanenchery ', quoted: 3000);
  final linkedFar = project('linked', lat: 13.2, lng: 80.3, links: ['135'], quoted: 5000);

  group('nearbyCompetitors', () {
    test('by distance, village and hand links; nearest first', () {
      final all = [markAvenue, aloka, springField, noPinSameVillage, linkedFar];
      final at5 = nearbyCompetitors(l135, all, radiusKm: 5);
      expect(at5.map((n) => n.project.id),
          ['springfield', 'aloka', 'linked', 'village']);
      expect(at5.first.km, lessThan(1));
      expect(at5.firstWhere((n) => n.project.id == 'village').sameVillage, isTrue);
      expect(at5.firstWhere((n) => n.project.id == 'linked').linked, isTrue);

      final at10 = nearbyCompetitors(l135, all, radiusKm: 10);
      expect(at10.map((n) => n.project.id), contains('mark'));
      final at2 = nearbyCompetitors(l135, all, radiusKm: 2);
      expect(at2.map((n) => n.project.id), isNot(contains('aloka')));
    });

    test('a lead without GPS still gets village and linked projects', () {
      final noGps = lead('135', village: 'Serapanenchery');
      final out = nearbyCompetitors(noGps, [springField, noPinSameVillage, linkedFar]);
      expect(out.map((n) => n.project.id), ['linked', 'village']);
      expect(out.every((n) => n.km == null), isTrue);
    });
  });

  test('percentile interpolates', () {
    expect(percentile([1, 2, 3, 4], 0.5), 2.5);
    expect(percentile([1, 2, 3, 4, 5], 0.25), 2);
    expect(percentile([7], 0.75), 7);
  });

  group('priceSummary', () {
    test('plotted layouts only, negotiated before quoted', () {
      final villa = project('villa', quoted: 9000, type: CompetitorType.villa);
      final s = priceSummary([springField, aloka, markAvenue, villa, project('x')])!;
      expect(s.used.length, 3);
      expect(s.median, 2799);
      expect(s.min, 2100);
      expect(s.max, 3000);
      expect(s.average, closeTo((2100 + 2799 + 3000) / 3, 0.01));
    });

    test('null without a priced layout', () {
      expect(priceSummary([project('a'), project('v', quoted: 1, type: CompetitorType.villa)]), isNull);
    });

    test('sell speed and sell-out estimate', () {
      final now = DateTime(2026, 11, 12);
      final fast = project('f', negotiated: 3000, phases: [
        CompetitorPhase(launchDate: DateTime(2025, 11, 12), sold: 120, minPlotSqft: 1000, maxPlotSqft: 1400),
      ]);
      final slow = project('s', negotiated: 2800, phases: [
        CompetitorPhase(launchDate: DateTime(2024, 11, 12), sold: 48, minPlotSqft: 800, maxPlotSqft: 1200),
      ]);
      final future = project('u', negotiated: 3500, phases: [
        CompetitorPhase(launchDate: DateTime(2027, 1, 1), sold: 50),
      ]);
      expect(plotsPerMonth(fast, now), closeTo(10, 0.1));
      expect(plotsPerMonth(future, now), isNull);
      final s = priceSummary([fast, slow, future], now: now)!;
      expect(s.speedCount, 2);
      expect(s.plotsPerMonth, closeTo(6, 0.1));
      expect(s.typicalPlotSqft, 1100);
      // 1 acre → 43,560 × 55% / 1,100 ≈ 21 plots → ~3.5 months at 6 / month.
      expect(s.plotsFor(1), 21);
      expect(s.monthsToSell(21), closeTo(3.5, 0.1));
    });
  });

  test('totals and sizes come from phases', () {
    final p = project('p', phases: [
      const CompetitorPhase(plots: 102, sold: 84, available: 18, minPlotSqft: 600, maxPlotSqft: 1700),
      const CompetitorPhase(plots: 160, sold: 28, available: 130, minPlotSqft: 650),
    ]);
    expect(p.totalPlots, 262);
    expect(p.totalSold, 112);
    expect(p.totalAvailable, 148);
    expect(p.minSqft, 600);
    expect(p.maxSqft, 1700);
    expect(project('e').totalPlots, isNull);
  });

  group('re-checks', () {
    final now = DateTime(2026, 11, 23);
    test('due after 120 days', () {
      expect(project('a', checked: DateTime(2026, 11, 12)).recheckIsDue(now), isFalse);
      expect(project('b', checked: DateTime(2026, 7, 1)).recheckIsDue(now), isTrue);
      expect(project('c').recheckIsDue(now), isTrue);
    });

    test('fall to the owner and the nearest lead', () {
      final old = DateTime(2026, 1, 1);
      final mine = project('mine', checked: old, ownerEmail: 'Devaraj@fomrahousing.in');
      final nearMyLead = project('near', lat: 12.86207, lng: 79.979943, checked: old);
      final linked = project('linked', checked: old, links: ['135']);
      final fresh = project('fresh', lat: 12.86207, lng: 79.979943, checked: DateTime(2026, 11, 1));
      final other = project('other', lat: 12.86207, lng: 79.979943, checked: old);
      final l36 = lead('36', gps: '12.896480, 80.046792');
      final leads = [l135, l36];
      final forMe = recheckDueFor(
        all: [mine, nearMyLead, linked, fresh],
        myEmail: 'devaraj@fomrahousing.in',
        myLeadIds: {'135'},
        allLeads: leads,
        now: now,
      );
      expect(forMe.map((p) => p.id), ['mine', 'near', 'linked']);
      final forOther = recheckDueFor(
        all: [other],
        myEmail: 'someone@fomrahousing.in',
        myLeadIds: {'36'},
        allLeads: leads,
        now: now,
      );
      expect(forOther, isEmpty);
    });
  });

  test('comparison CSV has the sheet columns and opens in Excel', () {
    final n = nearbyCompetitors(l135, [springField]);
    final bytes = comparisonCsv(n, title: 'Near lead 135');
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    final text = utf8.decode(bytes.skip(3).toList());
    final lines = text.split('\r\n');
    expect(lines[0], 'Near lead 135');
    expect(lines[1].split(',').length, comparisonHeaders.length);
    expect(lines[2], contains('Project springfield'));
    expect(lines[2], contains(',2400,,2100,'));
  });

  group('pinFromText', () {
    test('reads the place pin from a full Google Maps link', () {
      final p = pinFromText(
          'https://www.google.com/maps/place/X/@12.9,80.0,17z/data=!3m1!4b1!8m2!3d12.9142547!4d80.0324985');
      expect(p!.latitude, 12.9142547);
      expect(p.longitude, 80.0324985);
    });

    test('reads typed coordinates', () {
      final p = pinFromText('12.86207, 79.979943');
      expect(p!.latitude, 12.86207);
    });

    test('a short link needs the server', () {
      expect(pinFromText('https://maps.app.goo.gl/bHCuDfAhviAd39bp8'), isNull);
      expect(looksLikeMapsLink('https://maps.app.goo.gl/bHCuDfAhviAd39bp8'), isTrue);
      expect(looksLikeMapsLink('hello'), isFalse);
    });
  });

  test('fromJson reads the database row with phases and links', () {
    final p = CompetitorProject.fromJson({
      'id': 'x',
      'code': 'C-017',
      'name': 'Spring Field',
      'project_type': 'layout',
      'stage': 'upcoming',
      'lat': 12.86207,
      'lng': '79.979943',
      'quoted_price': '2400',
      'negotiated_price': 2100,
      'last_checked_at': '2026-11-12T06:30:00+00:00',
      'created_at': '2026-11-20T06:30:00+00:00',
      'competitor_phases': [
        {'id': 'b', 'label': 'Phase 2', 'sort': 1, 'plots': 10},
        {'id': 'a', 'label': 'Phase 1', 'sort': 0, 'plots': 84, 'sold': 30, 'available': 54},
      ],
      'competitor_lead_links': [
        {'lead_id': '135'},
      ],
    });
    expect(p.stage, CompetitorStage.upcoming);
    expect(p.point!.longitude, 79.979943);
    expect(p.quotedPrice, 2400);
    expect(p.phases.map((x) => x.label), ['Phase 1', 'Phase 2']);
    expect(p.totalPlots, 94);
    expect(p.linkedLeadIds, ['135']);
    expect(p.dealPrice, 2100);
    expect(p.recheckDue!.isAfter(DateTime(2027, 3, 1)), isTrue);
  });
}
