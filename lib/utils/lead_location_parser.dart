import 'package:latlong2/latlong.dart';

import '../models/gps_fix.dart';

/// Standard display format for saved GPS coordinates.
String formatLeadGps(double lat, double lng) =>
    '${lat.toStringAsFixed(6)}° N, ${lng.toStringAsFixed(6)}° E';

/// Metres between two stored GPS values (any format [parseLeadGps] reads),
/// or null when either can't be parsed.
double? gpsDistanceMeters(String a, String b) {
  final pa = parseLeadGps(a);
  final pb = parseLeadGps(b);
  if (pa == null || pb == null) return null;
  return const Distance().as(LengthUnit.Meter, pa, pb);
}

/// A stored GPS value as plain readable coordinates (the LIVE| storage
/// format carries accuracy and a timestamp nobody needs to read); falls back
/// to the raw text when it can't be parsed.
String gpsForDisplay(String gps) {
  final p = parseLeadGps(gps);
  return p == null ? gps.trim() : formatLeadGps(p.latitude, p.longitude);
}

/// Parses GPS strings from add-lead / lead records.
///
/// Supports:
/// - Verified live: `LIVE|<lat>|<lng>|<accuracy>|<iso8601>`
/// - DMS: `13°07'08.7"N 80°16'53.0"E`
/// - Decimal with labels: `13.119083° N, 80.281389° E`
/// - Plain decimals: `13.119083, 80.281389`
LatLng? parseLeadGps(String gps) {
  final live = GpsFix.tryParse(gps);
  if (live != null) return live.point;

  final trimmed = gps.trim();
  if (trimmed.isEmpty) return null;

  final dms = _parseDms(trimmed);
  if (dms != null) return dms;

  final labeled = _parseLabeledDecimal(trimmed);
  if (labeled != null) return labeled;

  final parts = trimmed.split(',');
  if (parts.length >= 2) {
    final lat = double.tryParse(parts[0].replaceAll(RegExp(r'[^\d.\-]'), ''));
    final lng = double.tryParse(parts[1].replaceAll(RegExp(r'[^\d.\-]'), ''));
    if (lat != null && lng != null && _isValidLatLng(lat, lng)) {
      return LatLng(lat, lng);
    }
  }

  final spaceParts = trimmed.split(RegExp(r'\s+'));
  if (spaceParts.length >= 2) {
    final lat = double.tryParse(
      spaceParts[0].replaceAll(RegExp(r'[^\d.\-]'), ''),
    );
    final lng = double.tryParse(
      spaceParts[1].replaceAll(RegExp(r'[^\d.\-]'), ''),
    );
    if (lat != null && lng != null && _isValidLatLng(lat, lng)) {
      return LatLng(lat, lng);
    }
  }
  return null;
}

bool _isValidLatLng(double lat, double lng) =>
    lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;

double _dmsToDecimal({
  required double degrees,
  required double minutes,
  required double seconds,
  required String hemisphere,
}) {
  var value = degrees + (minutes / 60) + (seconds / 3600);
  final h = hemisphere.toUpperCase();
  if (h == 'S' || h == 'W') value = -value;
  return value;
}

/// DMS e.g. `13°07'08.7"N 80°16'53.0"E` or `13°07'08.7" N, 80°16'53.0" E`.
LatLng? _parseDms(String input) {
  if (!input.contains('°')) return null;

  final normalized = input
      .replaceAll('′', "'")
      .replaceAll('’', "'")
      .replaceAll('″', '"')
      .replaceAll('\u201C', '"')
      .replaceAll('\u201D', '"')
      .trim();

  final match = RegExp(
    r"(\d+(?:\.\d+)?)\s*°\s*"
    r"(\d+(?:\.\d+)?)?\s*'?\s*"
    r'(\d+(?:\.\d+)?)?\s*"?\s*'
    r"([NS])\D*"
    r"(\d+(?:\.\d+)?)\s*°\s*"
    r"(\d+(?:\.\d+)?)?\s*'?\s*"
    r'(\d+(?:\.\d+)?)?\s*"?\s*'
    r'([EW])',
    caseSensitive: false,
  ).firstMatch(normalized);

  if (match == null) return null;

  final latDeg = double.parse(match.group(1)!);
  final latMin = double.tryParse(match.group(2) ?? '') ?? 0;
  final latSec = double.tryParse(match.group(3) ?? '') ?? 0;
  final latHem = match.group(4)!;

  final lngDeg = double.parse(match.group(5)!);
  final lngMin = double.tryParse(match.group(6) ?? '') ?? 0;
  final lngSec = double.tryParse(match.group(7) ?? '') ?? 0;
  final lngHem = match.group(8)!;

  final lat = _dmsToDecimal(
    degrees: latDeg,
    minutes: latMin,
    seconds: latSec,
    hemisphere: latHem,
  );
  final lng = _dmsToDecimal(
    degrees: lngDeg,
    minutes: lngMin,
    seconds: lngSec,
    hemisphere: lngHem,
  );

  if (!_isValidLatLng(lat, lng)) return null;
  return LatLng(lat, lng);
}

/// Decimal degrees with N/E labels, e.g. `13.119083° N, 80.281389° E`.
LatLng? _parseLabeledDecimal(String input) {
  // Skip strings that look like DMS (minutes/seconds markers).
  if (input.contains("'") || input.contains('"')) return null;

  final match = RegExp(
    r'(-?\d+(?:\.\d+)?)\s*°?\s*([NS]).*?(-?\d+(?:\.\d+)?)\s*°?\s*([EW])',
    caseSensitive: false,
  ).firstMatch(input);

  if (match == null) return null;

  var lat = double.tryParse(match.group(1)!);
  var lng = double.tryParse(match.group(3)!);
  if (lat == null || lng == null) return null;

  if (match.group(2)!.toUpperCase() == 'S') lat = -lat.abs();
  if (match.group(4)!.toUpperCase() == 'W') lng = -lng.abs();

  lat = lat.abs();
  lng = lng.abs();

  if (!_isValidLatLng(lat, lng)) return null;
  return LatLng(lat, lng);
}

/// Converts land extent text (acres, cents, sqft) to square feet.
double? parseLandExtentSqft(String extent) {
  final lower = extent.trim().toLowerCase();
  if (lower.isEmpty) return null;

  final numMatch = RegExp(r'([\d.]+)').firstMatch(lower);
  if (numMatch == null) return null;
  final n = double.tryParse(numMatch.group(1)!);
  if (n == null || n <= 0) return null;

  if (lower.contains('acre')) return n * 43560;
  if (lower.contains('hectare') || lower.contains('hect')) return n * 107639;
  if (lower.contains('ground')) return n * 2400; // TN unit: 1 ground = 2400 sqft
  if (lower.contains('cent')) return n * 435.6;
  if (lower.contains('sq')) return n;
  return n; // bare number → assume already in sqft
}

/// Extracts numeric road width in feet from lead text.
double? parseRoadWidthFt(String roadWidth) {
  final match = RegExp(r'([\d.]+)').firstMatch(roadWidth.trim());
  if (match == null) return null;
  return double.tryParse(match.group(1)!);
}
