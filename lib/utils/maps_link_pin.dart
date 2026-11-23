import 'package:latlong2/latlong.dart';

import '../services/api_client.dart';
import 'lead_location_parser.dart';

/// The pin in typed coordinates or a full Google Maps URL, or null.
LatLng? pinFromText(String text) {
  final t = Uri.decodeFull(text.trim());
  if (t.isEmpty) return null;
  final patterns = [
    RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)'),
    RegExp(r'[?&](?:q|query|ll|destination|center)=(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)'),
    RegExp(r'/(?:place|search|dir)/(-?\d+(?:\.\d+)?)\s*,\s*\+?(-?\d+(?:\.\d+)?)'),
    RegExp(r'@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)'),
  ];
  for (final re in patterns) {
    final m = re.firstMatch(t);
    if (m != null) {
      final lat = double.tryParse(m.group(1)!);
      final lng = double.tryParse(m.group(2)!);
      if (lat != null && lng != null && lat.abs() <= 90 && lng.abs() <= 180) {
        return LatLng(lat, lng);
      }
    }
  }
  if (t.startsWith('http')) return null;
  // "12.91, 80.03", degrees / minutes, LIVE|… — as leads accept.
  return parseLeadGps(t);
}

bool looksLikeMapsLink(String text) {
  final t = text.trim().toLowerCase();
  return t.startsWith('https://') &&
      (t.contains('goo.gl') || t.contains('google.') || t.contains('g.co/'));
}

/// Reads the pin from [text]; short links (maps.app.goo.gl) are opened on
/// the server. Throws with a readable message when nothing is found.
Future<LatLng> resolvePin(String text) async {
  final direct = pinFromText(text);
  if (direct != null) return direct;
  if (!looksLikeMapsLink(text)) {
    throw Exception('Paste a Google Maps link or coordinates like 12.91, 80.03.');
  }
  final res = await ApiClient.get(
      '/api/competitors/resolve-map?url=${Uri.encodeQueryComponent(text.trim())}');
  final lat = (res['lat'] as num?)?.toDouble();
  final lng = (res['lng'] as num?)?.toDouble();
  if (lat == null || lng == null) {
    throw Exception(res['error']?.toString() ?? 'No pin found in that link.');
  }
  return LatLng(lat, lng);
}
