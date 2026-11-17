import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Which leads have ever had a meeting with management present — whatever
/// their stage now (dropped and on-hold included). Feeds the "Had a
/// management meeting" filter, which judges a lead on its meeting history
/// rather than its current status.
class MeetingFlagsIndex extends ChangeNotifier {
  MeetingFlagsIndex._();
  static final MeetingFlagsIndex instance = MeetingFlagsIndex._();

  Set<String> _managementMet = const {};
  bool _loaded = false;
  Future<void>? _inFlight;
  DateTime? _loadedAt;

  bool get isLoaded => _loaded;

  bool hadManagementMeeting(String leadId) =>
      _managementMet.contains(leadId.trim());

  /// Loads once, then at most every 2 minutes, unless [force].
  Future<void> ensureLoaded({bool force = false}) {
    final fresh = _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(minutes: 2);
    if (!force && _loaded && fresh) return Future.value();
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('land_lead_meetings')
          .select('lead_id')
          .eq('management_present', true)
          .limit(10000);
      _managementMet = {
        for (final r in rows as List) (r['lead_id'] ?? '').toString().trim(),
      };
      _loaded = true;
      _loadedAt = DateTime.now();
      notifyListeners();
    } catch (e) {
      debugPrint('[meetings] could not load meeting flags: $e');
    }
  }

  /// Marks a lead after a meeting with management is logged here.
  void markManagementMeeting(String leadId) {
    if (_managementMet.contains(leadId)) return;
    _managementMet = {..._managementMet, leadId};
    notifyListeners();
  }

  /// Replaces the index contents directly — tests only.
  @visibleForTesting
  void debugSeed(Iterable<String> managementMetLeadIds) {
    _managementMet = {...managementMetLeadIds};
    _loaded = true;
    _loadedAt = DateTime.now();
    notifyListeners();
  }
}
