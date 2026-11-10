import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/land_lead_meeting.dart';
import 'auth_service.dart';

class LandLeadMeetingService {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<List<LandLeadMeeting>> getForLead(String leadId) async {
    final rows = await _db
        .from('land_lead_meetings')
        .select()
        .eq('lead_id', leadId)
        .order('met_at', ascending: false);
    return (rows as List)
        .map((r) => LandLeadMeeting.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  static Future<LandLeadMeeting> create({
    required String leadId,
    required DateTime metAt,
    required String duration,
    String notes = '',
    List<String> attendeeTypes = const [],
    bool managementPresent = false,
    List<PersonMet> peopleMet = const [],
  }) async {
    final userId = _db.auth.currentUser?.id;
    final loggedByName = AuthService.instance.currentUser?.fullName ?? '';

    final row = await _db
        .from('land_lead_meetings')
        .insert({
          'lead_id': leadId,
          'met_at': metAt.toUtc().toIso8601String(),
          'duration': duration.trim(),
          'notes': notes.trim(),
          'attendee_types': attendeeTypes,
          'management_present': managementPresent,
          'people_met': peopleMet
              .where((p) => !p.isEmpty)
              .map((p) => p.toJson())
              .toList(),
          if (loggedByName.isNotEmpty) 'logged_by_name': loggedByName,
          if (userId != null) 'logged_by': userId,
        })
        .select()
        .single();

    // Auto-derived milestone (see the migration comment for the full
    // rationale): stamp the earliest date any owner/agreement-holder
    // meeting happened, so it survives future status changes.
    //
    // Meetings can be logged out of chronological order — metAt is a
    // user-picked date (see meeting_log_dialog.dart's pickLogDate), so
    // someone catching up on a backlog might log a later meeting before
    // an earlier one. "First logged wins" would then permanently record
    // the wrong (later) date. Comparing against the existing value and
    // only updating when the new meeting is actually earlier — or there's
    // no value yet — keeps this correct regardless of entry order.
    final qualifies = attendeeTypes.any(
          (t) => MeetingAttendeeTypes.countsAsLandownerMeeting.contains(t),
        ) ||
        peopleMet.any((p) =>
            p.relation == 'Land Owner' ||
            p.relation == 'Agreement Holder / PoA');
    if (qualifies) {
      final metAtIso = metAt.toUtc().toIso8601String();
      await _db
          .from('land_leads')
          .update({'landowner_meeting_completed_at': metAtIso})
          .eq('id', leadId)
          .or('landowner_meeting_completed_at.is.null,'
              'landowner_meeting_completed_at.gt.$metAtIso');
    }

    return LandLeadMeeting.fromJson(row);
  }

  /// Tests: answer [leadIdsWithLandOwnerMeeting] without a database.
  @visibleForTesting
  static Set<String>? debugOwnerMetIds;

  /// Lead ids (among those the viewer can see) that have had a meeting with
  /// the actual Land Owner — for the broker ranking. One light query for all
  /// leads rather than one per lead.
  static Future<Set<String>> leadIdsWithLandOwnerMeeting() async {
    if (debugOwnerMetIds case final ids?) return ids;
    final rows = await _db
        .from('land_lead_meetings')
        .select('lead_id, attendee_types, people_met');
    final ids = <String>{};
    for (final r in rows as List) {
      final m = Map<String, dynamic>.from(r as Map);
      final types = (m['attendee_types'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];
      final people = (m['people_met'] as List?)
              ?.whereType<Map>()
              .map((e) => PersonMet.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const <PersonMet>[];
      final met = types.contains(MeetingAttendeeTypes.landOwner) ||
          people.any((p) => p.relation == 'Land Owner');
      if (met) ids.add(m['lead_id'].toString());
    }
    return ids;
  }
}
