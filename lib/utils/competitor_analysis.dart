import 'dart:convert';
import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../models/competitor_project.dart';
import '../models/land_lead.dart';
import 'lead_location_parser.dart';

/// A competitor project as seen from one lead: how far, and why it shows.
class NearbyCompetitor {
  final CompetitorProject project;

  /// Straight-line distance from the lead's pin (null when either has no GPS).
  final double? km;
  final bool sameVillage;
  final bool linked;

  const NearbyCompetitor({
    required this.project,
    required this.km,
    required this.sameVillage,
    required this.linked,
  });

  /// Short reason, e.g. "2.4 km" / "Same village" / "Linked".
  String get reason {
    final parts = <String>[
      if (km != null) '${km!.toStringAsFixed(1)} km',
      if (sameVillage) 'same village',
      if (linked) 'linked',
    ];
    if (parts.isEmpty) return '';
    final s = parts.join(' · ');
    return s[0].toUpperCase() + s.substring(1);
  }
}

String _villageKey(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

const _distance = Distance();

double kmBetween(LatLng a, LatLng b) =>
    _distance.as(LengthUnit.Meter, a, b) / 1000;

/// Projects within [radiusKm] of the lead, in its village, or linked to it
/// by hand — nearest first, then the rest by name.
List<NearbyCompetitor> nearbyCompetitors(
  LandLead lead,
  List<CompetitorProject> all, {
  double radiusKm = 5,
}) {
  final pin = parseLeadGps(lead.gpsCoordinates);
  final village = _villageKey(lead.village);
  final out = <NearbyCompetitor>[];
  for (final p in all) {
    final km = (pin != null && p.point != null) ? kmBetween(pin, p.point!) : null;
    final same = village.isNotEmpty && _villageKey(p.village) == village;
    final linked = p.linkedLeadIds.contains(lead.leadId);
    if ((km != null && km <= radiusKm) || same || linked) {
      out.add(NearbyCompetitor(
          project: p, km: km, sameVillage: same, linked: linked));
    }
  }
  out.sort((a, b) {
    if (a.km != null && b.km != null) return a.km!.compareTo(b.km!);
    if (a.km != null) return -1;
    if (b.km != null) return 1;
    return a.project.name.compareTo(b.project.name);
  });
  return out;
}

/// The lead nearest to a project (by GPS), with its distance in km.
(LandLead, double)? nearestLead(CompetitorProject p, List<LandLead> leads) {
  final at = p.point;
  if (at == null) return null;
  (LandLead, double)? best;
  for (final l in leads) {
    final pin = parseLeadGps(l.gpsCoordinates);
    if (pin == null) continue;
    final km = kmBetween(at, pin);
    if (best == null || km < best.$2) best = (l, km);
  }
  return best;
}

/// Linear-interpolated percentile of sorted values (q in 0..1).
double percentile(List<double> sorted, double q) {
  if (sorted.isEmpty) return double.nan;
  if (sorted.length == 1) return sorted.first;
  final pos = (sorted.length - 1) * q;
  final lo = pos.floor();
  final hi = pos.ceil();
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

/// Plots sold per month since the project's first launch (null when the
/// sold count or a past launch date is missing).
double? plotsPerMonth(CompetitorProject p, [DateTime? now]) {
  final sold = p.totalSold;
  final launch = p.firstLaunch;
  final today = now ?? DateTime.now();
  if (sold == null || sold <= 0 || launch == null || launch.isAfter(today)) {
    return null;
  }
  final months = today.difference(launch).inDays / 30.44;
  return sold / math.max(1, months);
}

/// Share of a plotted layout's land that becomes saleable plots (the rest is
/// roads, parks / OSR and common areas) — used for the sell-out estimate.
const saleableShare = 0.55;

/// Suggested price and sell speed for a lead, from nearby plotted layouts.
class CompetitorPriceSummary {
  /// Plotted layouts with a price that were used.
  final List<CompetitorProject> used;
  final double low; // 25th percentile
  final double median;
  final double high; // 75th percentile
  final double average;
  final double min;
  final double max;

  /// Median plots sold per month, and how many projects it comes from.
  final double? plotsPerMonth;
  final int speedCount;

  /// Typical plot size in the area (median of each project's mid size).
  final double typicalPlotSqft;

  const CompetitorPriceSummary({
    required this.used,
    required this.low,
    required this.median,
    required this.high,
    required this.average,
    required this.min,
    required this.max,
    required this.plotsPerMonth,
    required this.speedCount,
    required this.typicalPlotSqft,
  });

  /// Plots a layout on [acres] would give at [saleableShare].
  int plotsFor(double acres) =>
      (acres * 43560 * saleableShare / typicalPlotSqft).floor();

  /// Months to sell [plots] at the area's median pace (null without a pace).
  double? monthsToSell(int plots) =>
      plotsPerMonth == null || plotsPerMonth! <= 0 ? null : plots / plotsPerMonth!;
}

/// Null when no nearby plotted layout has a price.
CompetitorPriceSummary? priceSummary(
  Iterable<CompetitorProject> projects, {
  DateTime? now,
}) {
  final used = [
    for (final p in projects)
      if (p.type == CompetitorType.layout && p.dealPrice != null && p.dealPrice! > 0)
        p,
  ];
  if (used.isEmpty) return null;
  final prices = [for (final p in used) p.dealPrice!]..sort();
  final speeds = [
    for (final p in used)
      if (plotsPerMonth(p, now) != null) plotsPerMonth(p, now)!,
  ]..sort();
  final sizes = [
    for (final p in used)
      if (p.minSqft != null && p.maxSqft != null)
        (p.minSqft! + p.maxSqft!) / 2
      else if (p.minSqft != null)
        p.minSqft!.toDouble()
      else if (p.maxSqft != null)
        p.maxSqft!.toDouble(),
  ]..sort();
  return CompetitorPriceSummary(
    used: used,
    low: percentile(prices, 0.25),
    median: percentile(prices, 0.5),
    high: percentile(prices, 0.75),
    average: prices.reduce((a, b) => a + b) / prices.length,
    min: prices.first,
    max: prices.last,
    plotsPerMonth: speeds.isEmpty ? null : percentile(speeds, 0.5),
    speedCount: speeds.length,
    typicalPlotSqft: sizes.isEmpty ? 1200 : percentile(sizes, 0.5),
  );
}

final _inr = NumberFormat.decimalPattern('en_IN');

/// "5", "2.25", "1.1" (no trailing ".0").
String acresLabel(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toString();

/// "₹3,500" (no decimals).
String rupees(num? v) => v == null ? '—' : '₹${_inr.format(v.round())}';

/// "1,200" (no decimals) or "—".
String count(num? v) => v == null ? '—' : _inr.format(v.round());

String _plc(CompetitorProject p) => [
      if (p.plcCorner != null) 'Corner +${p.plcCorner!.round()}',
      if (p.plcFacing != null) 'Facing +${p.plcFacing!.round()}',
      if (p.plcRoad != null) 'Main road +${p.plcRoad!.round()}',
    ].join(', ');

String _sizes(CompetitorProject p) {
  final a = p.minSqft, b = p.maxSqft;
  if (a == null && b == null) return '';
  if (a != null && b != null) return '${count(a)}–${count(b)}';
  return count(a ?? b);
}

String _launch(CompetitorProject p) {
  final d = p.firstLaunch;
  return d == null ? '' : DateFormat('MMM yyyy').format(d);
}

/// The comparison table in the team's sheet layout: (header, value) per
/// column, one row per project.
const comparisonHeaders = [
  'S.No',
  'Code',
  'Builder',
  'Project',
  'Location',
  'Approval',
  'RERA',
  'Extent (acres)',
  'Plots',
  'Launch',
  'Sold',
  'Available',
  'Plot sizes (sq ft)',
  'Pre-launch ₹/sq ft',
  'Quoted ₹/sq ft',
  'PLC (extra ₹/sq ft)',
  'Negotiated ₹/sq ft',
  'Main road (ft)',
  'Documentation ₹',
  'Distance (km)',
  'Sales contacts',
  'Phones',
  'Map link',
  'Amenities',
  'GLV ₹/sq ft',
  'Stage',
  'Last checked',
];

/// [plainNumbers]: no thousands commas (for the CSV, so Excel reads numbers).
List<String> comparisonRow(int index, NearbyCompetitor n, {bool plainNumbers = false}) {
  final p = n.project;
  String numOrBlank(num? v) => v == null
      ? ''
      : plainNumbers
          ? v.round().toString()
          : _inr.format(v.round());
  return [
    '${index + 1}',
    p.code,
    p.builder,
    p.name,
    p.placeLabel,
    [p.approvalAuthority, p.approvalNo].where((s) => s.trim().isNotEmpty).join(' '),
    p.reraNo,
    p.extentAcres == null ? '' : acresLabel(p.extentAcres!),
    numOrBlank(p.totalPlots),
    _launch(p),
    numOrBlank(p.totalSold),
    numOrBlank(p.totalAvailable),
    _sizes(p),
    numOrBlank(p.preLaunchPrice),
    numOrBlank(p.quotedPrice),
    _plc(p),
    numOrBlank(p.negotiatedPrice),
    numOrBlank(p.mainRoadFt),
    numOrBlank(p.documentationCharges),
    n.km == null ? '' : n.km!.toStringAsFixed(1),
    [for (final c in p.allContacts) c.label].join('; '),
    [for (final c in p.allContacts) if (c.phone.trim().isNotEmpty) c.phone.trim()].join('; '),
    p.mapsLink,
    p.amenities,
    numOrBlank(p.glv),
    p.stage.label,
    p.lastCheckedAt == null ? '' : DateFormat('d MMM yyyy').format(p.lastCheckedAt!),
  ];
}

String _csvCell(String v) {
  final needs = v.contains(',') || v.contains('"') || v.contains('\n');
  final s = v.replaceAll('"', '""');
  return needs ? '"$s"' : s;
}

/// The comparison table as a CSV file Excel opens (UTF-8 with BOM so ₹ and
/// Tamil names show correctly).
List<int> comparisonCsv(List<NearbyCompetitor> rows, {String title = ''}) {
  final lines = <String>[
    if (title.isNotEmpty) _csvCell(title),
    comparisonHeaders.map(_csvCell).join(','),
    for (var i = 0; i < rows.length; i++)
      comparisonRow(i, rows[i], plainNumbers: true).map(_csvCell).join(','),
  ];
  return [0xEF, 0xBB, 0xBF, ...utf8.encode(lines.join('\r\n'))];
}

/// Projects whose 120-day re-check is due and that fall to this person:
/// they own it, or its nearest lead (or a lead it is linked to) is one of
/// [myLeadIds].
List<CompetitorProject> recheckDueFor({
  required List<CompetitorProject> all,
  required String myEmail,
  required Set<String> myLeadIds,
  required List<LandLead> allLeads,
  DateTime? now,
}) {
  final me = myEmail.trim().toLowerCase();
  return [
    for (final p in all)
      if (p.recheckIsDue(now) &&
          ((me.isNotEmpty && p.ownerEmail.trim().toLowerCase() == me) ||
              p.linkedLeadIds.any(myLeadIds.contains) ||
              myLeadIds.contains(nearestLead(p, allLeads)?.$1.leadId)))
        p,
  ];
}
