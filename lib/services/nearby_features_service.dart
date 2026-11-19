import 'package:latlong2/latlong.dart';

import '../utils/lead_auto_notes.dart';
import 'api_client.dart';
import 'infra_score_store.dart';

/// Nearby map features around a site, from the same Overpass-backed POI service
/// the Market Intelligence infrastructure tab uses — so both read one source.
abstract final class NearbyFeaturesService {
  /// Radius for a lead's automatic notes. The endpoint only accepts 2, 5 or 10.
  static const notesRadiusKm = 2;

  /// Features grouped by the service's category names (`Water Bodies`,
  /// `Schools`, `Cemeteries`, …), ready for [LeadAutoNotes.generate].
  ///
  /// With [leadId], the lead's saved infrastructure score is used when there
  /// is one (no map-server call), and a fresh answer is saved for next time.
  static Future<Map<String, List<NearbyFeature>>> fetch(
    LatLng at, {
    int radiusKm = notesRadiusKm,
    String? leadId,
    double? roadWidthFt,
  }) async {
    var data = leadId == null
        ? null
        : await InfraScoreStore.load(
            leadId, radiusKm, at.latitude, at.longitude);
    if (data == null) {
      data = await ApiClient.post(
        '/api/poi/infrastructure',
        {
          'lat': at.latitude,
          'lon': at.longitude,
          'radiusKm': radiusKm,
          if (roadWidthFt != null) 'roadWidthFt': roadWidthFt,
        },
        auth: false,
      ).timeout(const Duration(seconds: 35));
      if (leadId != null) {
        InfraScoreStore.save(
            leadId, radiusKm, at.latitude, at.longitude, data);
      }
    }

    final places = (data['places'] as Map?)?.cast<String, dynamic>() ?? {};
    final result = <String, List<NearbyFeature>>{};

    places.forEach((category, raw) {
      if (raw is! List) return;
      final features = <NearbyFeature>[
        for (final entry in raw)
          if (entry is Map)
            NearbyFeature(
              name: (entry['name'] ?? '').toString(),
              distanceKm: (entry['distance'] as num?)?.toDouble(),
            ),
      ];
      if (features.isNotEmpty) result[category] = features;
    });

    return result;
  }
}
