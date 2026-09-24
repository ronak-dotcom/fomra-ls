import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/daily_update.dart';
import 'auth_service.dart';

/// Morning plan / evening recap, one row per employee per calendar day.
///
/// Degrades gracefully when the `daily_updates` table is missing: reads
/// return nothing and writes throw, matching MonthlyTargetSubmissionService's
/// convention so a workspace that hasn't run the migration doesn't crash.
class DailyUpdateService {
  static SupabaseClient get _db => Supabase.instance.client;
  static const _table = 'daily_updates';

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String get _myEmail =>
      (AuthService.instance.currentUser?.email ?? '').trim().toLowerCase();
  static String get _myName => AuthService.instance.currentUser?.fullName ?? '';

  /// This employee's entry for one day, or null if neither plan nor recap
  /// has been started yet.
  static Future<DailyUpdate?> getForDate(DateTime date, {String? email}) async {
    try {
      final rows = await _db
          .from(_table)
          .select()
          .eq('employee_email', (email ?? _myEmail))
          .eq('update_date', dateKey(date))
          .limit(1);
      if (rows.isEmpty) return null;
      return DailyUpdate.fromJson(rows.first as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Every employee's entry for one day — for management to review the
  /// whole team's plan/recap at a glance rather than a WhatsApp scrollback.
  static Future<List<DailyUpdate>> allForDate(DateTime date) async {
    try {
      final rows = await _db
          .from(_table)
          .select()
          .eq('update_date', dateKey(date));
      final list = (rows as List)
          .map((r) => DailyUpdate.fromJson(r as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.employeeName.compareTo(b.employeeName));
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// A quick history strip (e.g. "did I log yesterday's recap?") — most
  /// recent first.
  static Future<List<DailyUpdate>> recentForMe({int days = 14}) async {
    try {
      final since = DateTime.now().subtract(Duration(days: days));
      final rows = await _db
          .from(_table)
          .select()
          .eq('employee_email', _myEmail)
          .gte('update_date', dateKey(since))
          .order('update_date', ascending: false);
      return (rows as List)
          .map((r) => DailyUpdate.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> savePlan({
    required DateTime date,
    required List<DailyUpdateVisit> visits,
    required List<DailyUpdateVisit> selfMeetings,
    required List<DailyUpdateHeadMeeting> headMeetings,
    required List<DailyUpdateActivity> otherActivities,
  }) async {
    await _db.from(_table).upsert(
      {
        'employee_email': _myEmail,
        'employee_name': _myName,
        'update_date': dateKey(date),
        'plan_visits': visits.map((v) => v.toJson()).toList(),
        'plan_self_meetings': selfMeetings.map((v) => v.toJson()).toList(),
        'plan_head_meetings': headMeetings.map((v) => v.toJson()).toList(),
        'plan_other_activities':
            otherActivities.map((a) => a.toJson()).toList(),
        'plan_submitted_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'update_date,employee_email',
    );
  }

  static Future<void> saveRecap({
    required DateTime date,
    required List<DailyUpdateVisit> visits,
    required List<DailyUpdateVisit> selfMeetings,
    required List<DailyUpdateHeadMeeting> headMeetings,
    required List<DailyUpdateActivity> otherActivities,
  }) async {
    await _db.from(_table).upsert(
      {
        'employee_email': _myEmail,
        'employee_name': _myName,
        'update_date': dateKey(date),
        'recap_visits': visits.map((v) => v.toJson()).toList(),
        'recap_self_meetings': selfMeetings.map((v) => v.toJson()).toList(),
        'recap_head_meetings': headMeetings.map((v) => v.toJson()).toList(),
        'recap_other_activities':
            otherActivities.map((a) => a.toJson()).toList(),
        'recap_submitted_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'update_date,employee_email',
    );
  }
}
