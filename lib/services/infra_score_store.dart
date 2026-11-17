import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The infrastructure score saved per lead and radius (lead_infra_scores),
/// so a lead's score loads instantly after the first time and doesn't depend
/// on the public map-data servers. A saved score is reused while the pin
/// hasn't moved (~100 m) and it is under 90 days old.
abstract final class InfraScoreStore {
  static const maxAge = Duration(days: 90);

  static SupabaseClient get _db => Supabase.instance.client;

  static bool _samePlace(num a, num b) => (a - b).abs() < 0.001;

  /// The saved payload (marked `cachedForLead`), or null to fetch afresh.
  static Future<Map<String, dynamic>?> load(
      String leadId, int radiusKm, double lat, double lon) async {
    try {
      final row = await _db
          .from('lead_infra_scores')
          .select()
          .eq('lead_id', leadId)
          .eq('radius_km', radiusKm)
          .maybeSingle();
      if (row == null) return null;
      final fetched = DateTime.tryParse(row['fetched_at']?.toString() ?? '');
      if (fetched == null || DateTime.now().difference(fetched) > maxAge) {
        return null;
      }
      if (!_samePlace(row['lat'] as num, lat) ||
          !_samePlace(row['lon'] as num, lon)) {
        return null;
      }
      final payload = Map<String, dynamic>.from(row['payload'] as Map);
      final scores = payload['scores'];
      if (scores is! Map || scores.isEmpty) return null;
      return {...payload, 'cachedForLead': true};
    } catch (e) {
      debugPrint('[infra] could not read saved score: $e');
      return null;
    }
  }

  /// Saves a freshly fetched payload; failures are ignored (it just loads
  /// from the map servers again next time).
  static Future<void> save(String leadId, int radiusKm, double lat, double lon,
      Map<String, dynamic> payload) async {
    final scores = payload['scores'];
    if (scores is! Map || scores.isEmpty) return;
    try {
      await _db.from('lead_infra_scores').upsert({
        'lead_id': leadId,
        'radius_km': radiusKm,
        'lat': lat,
        'lon': lon,
        'payload': payload,
        'fetched_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[infra] could not save score: $e');
    }
  }
}
