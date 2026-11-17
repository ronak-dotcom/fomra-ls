import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/land_lead_meeting.dart';
import '../models/land_lead_site_visit.dart';

/// Bulk activity fetch for management BI — parallel queries, no N+1.
class ManagementBiActivityBundle {
  final List<LandLeadMeeting> meetings;
  final List<LandLeadSiteVisit> siteVisits;

  const ManagementBiActivityBundle({
    required this.meetings,
    required this.siteVisits,
  });

  static const empty = ManagementBiActivityBundle(
    meetings: [],
    siteVisits: [],
  );
}

class ManagementBiActivityService {
  static SupabaseClient get _db => Supabase.instance.client;

  /// Loads meeting / site-visit rows in one round-trip batch.
  /// Failures on any table degrade gracefully to empty lists.
  static Future<ManagementBiActivityBundle> loadAll() async {
    final results = await Future.wait([
      _safeMeetings(),
      _safeVisits(),
    ]);
    return ManagementBiActivityBundle(
      meetings: results[0] as List<LandLeadMeeting>,
      siteVisits: results[1] as List<LandLeadSiteVisit>,
    );
  }

  /// Meetings only — for callers that need meeting history without paying for
  /// the site-visit query. Degrades to an empty list on failure.
  static Future<List<LandLeadMeeting>> loadMeetings() => _safeMeetings();

  /// Site visits only. Degrades to an empty list on failure.
  static Future<List<LandLeadSiteVisit>> loadSiteVisits() => _safeVisits();

  static Future<List<LandLeadMeeting>> _safeMeetings() async {
    try {
      final rows = await _db
          .from('land_lead_meetings')
          .select()
          .order('met_at', ascending: false)
          .limit(5000);
      return (rows as List)
          .map((r) => LandLeadMeeting.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<LandLeadSiteVisit>> _safeVisits() async {
    try {
      final rows = await _db
          .from('land_lead_site_visits')
          .select()
          .order('visited_at', ascending: false)
          .limit(5000);
      return (rows as List)
          .map((r) => LandLeadSiteVisit.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
