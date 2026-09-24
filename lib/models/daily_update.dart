/// One employee's plan-for-the-day and evening recap, replacing the manual
/// WhatsApp-group posting habit with something the app can partly fill in
/// on its own (site visits, meetings, and target progress are all already
/// tracked elsewhere) and generate back into that same shareable text.
library;

/// A planned or actual site visit / self-meeting: a place, optionally tied
/// to a real lead, and who was (or will be) met there.
class DailyUpdateVisit {
  final String? leadId;
  final String place;
  final String withWhom;

  const DailyUpdateVisit({
    this.leadId,
    this.place = '',
    this.withWhom = '',
  });

  bool get isEmpty => place.trim().isEmpty && withWhom.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        'lead_id': leadId,
        'place': place,
        'with_whom': withWhom,
      };

  factory DailyUpdateVisit.fromJson(Map<String, dynamic> j) => DailyUpdateVisit(
        leadId: j['lead_id'] as String?,
        place: j['place'] as String? ?? '',
        withWhom: j['with_whom'] as String? ?? '',
      );
}

/// Loosely categorised so these are reportable later even though most of
/// them (like the WhatsApp example's "Ravi Khirron meeting (BP)") are
/// general/internal rather than about one specific piece of land. category
/// is metadata only — it's never inserted into the generated text, which
/// always shows the person's own note verbatim.
enum HeadMeetingCategory {
  brokerPartner,
  bank,
  internalReview,
  other;

  String get label => switch (this) {
        HeadMeetingCategory.brokerPartner => 'Broker Partner',
        HeadMeetingCategory.bank => 'Bank',
        HeadMeetingCategory.internalReview => 'Internal Review',
        HeadMeetingCategory.other => 'Other',
      };

  String get key => switch (this) {
        HeadMeetingCategory.brokerPartner => 'broker_partner',
        HeadMeetingCategory.bank => 'bank',
        HeadMeetingCategory.internalReview => 'internal_review',
        HeadMeetingCategory.other => 'other',
      };

  static HeadMeetingCategory? fromKey(String? key) => switch (key) {
        'broker_partner' => HeadMeetingCategory.brokerPartner,
        'bank' => HeadMeetingCategory.bank,
        'internal_review' => HeadMeetingCategory.internalReview,
        'other' => HeadMeetingCategory.other,
        _ => null,
      };
}

/// A meeting with Head/management — optionally tied to a specific lead
/// (leadId set), or general/internal (leadId null, category + note carry
/// the meaning instead — e.g. "Ravi Khirron meeting (BP)").
class DailyUpdateHeadMeeting {
  final String? leadId;
  final HeadMeetingCategory? category;
  final String note;

  const DailyUpdateHeadMeeting({
    this.leadId,
    this.category,
    this.note = '',
  });

  bool get isEmpty => leadId == null && note.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        'lead_id': leadId,
        'category': category?.key,
        'note': note,
      };

  factory DailyUpdateHeadMeeting.fromJson(Map<String, dynamic> j) =>
      DailyUpdateHeadMeeting(
        leadId: j['lead_id'] as String?,
        category: HeadMeetingCategory.fromKey(j['category'] as String?),
        note: j['note'] as String? ?? '',
      );
}

/// A free-text activity line, optionally linked to a real Task once turned
/// into one from the daily-update screen.
class DailyUpdateActivity {
  final String text;
  final String? taskId;

  const DailyUpdateActivity({required this.text, this.taskId});

  Map<String, dynamic> toJson() => {'text': text, 'task_id': taskId};

  factory DailyUpdateActivity.fromJson(dynamic raw) {
    if (raw is String) return DailyUpdateActivity(text: raw);
    final j = Map<String, dynamic>.from(raw as Map);
    return DailyUpdateActivity(
      text: j['text'] as String? ?? '',
      taskId: j['task_id'] as String?,
    );
  }
}

/// A full day's entry: the morning plan and the evening recap, same shape,
/// one row per employee per calendar day (upserted twice — plan, then
/// later recap).
class DailyUpdate {
  final String id;
  final String employeeEmail;
  final String employeeName;
  final DateTime date;

  final List<DailyUpdateVisit> planVisits;
  final List<DailyUpdateVisit> planSelfMeetings;
  final List<DailyUpdateHeadMeeting> planHeadMeetings;
  final List<DailyUpdateActivity> planOtherActivities;
  final DateTime? planSubmittedAt;

  final List<DailyUpdateVisit> recapVisits;
  final List<DailyUpdateVisit> recapSelfMeetings;
  final List<DailyUpdateHeadMeeting> recapHeadMeetings;
  final List<DailyUpdateActivity> recapOtherActivities;
  final DateTime? recapSubmittedAt;

  const DailyUpdate({
    required this.id,
    required this.employeeEmail,
    required this.employeeName,
    required this.date,
    this.planVisits = const [],
    this.planSelfMeetings = const [],
    this.planHeadMeetings = const [],
    this.planOtherActivities = const [],
    this.planSubmittedAt,
    this.recapVisits = const [],
    this.recapSelfMeetings = const [],
    this.recapHeadMeetings = const [],
    this.recapOtherActivities = const [],
    this.recapSubmittedAt,
  });

  bool get hasPlan => planSubmittedAt != null;
  bool get hasRecap => recapSubmittedAt != null;

  static List<DailyUpdateVisit> _visits(dynamic raw) => (raw as List?)
          ?.whereType<Map>()
          .map((e) => DailyUpdateVisit.fromJson(Map<String, dynamic>.from(e)))
          .toList() ??
      const [];

  static List<DailyUpdateHeadMeeting> _headMeetings(dynamic raw) => (raw as List?)
          ?.whereType<Map>()
          .map((e) =>
              DailyUpdateHeadMeeting.fromJson(Map<String, dynamic>.from(e)))
          .toList() ??
      const [];

  static List<DailyUpdateActivity> _activities(dynamic raw) => (raw as List?)
          ?.map((e) => DailyUpdateActivity.fromJson(e))
          .toList() ??
      const [];

  factory DailyUpdate.fromJson(Map<String, dynamic> j) => DailyUpdate(
        id: j['id'] as String,
        employeeEmail: j['employee_email'] as String? ?? '',
        employeeName: j['employee_name'] as String? ?? '',
        date: DateTime.parse(j['update_date'] as String),
        planVisits: _visits(j['plan_visits']),
        planSelfMeetings: _visits(j['plan_self_meetings']),
        planHeadMeetings: _headMeetings(j['plan_head_meetings']),
        planOtherActivities: _activities(j['plan_other_activities']),
        planSubmittedAt: (j['plan_submitted_at'] as String?) != null
            ? DateTime.parse(j['plan_submitted_at'] as String)
            : null,
        recapVisits: _visits(j['recap_visits']),
        recapSelfMeetings: _visits(j['recap_self_meetings']),
        recapHeadMeetings: _headMeetings(j['recap_head_meetings']),
        recapOtherActivities: _activities(j['recap_other_activities']),
        recapSubmittedAt: (j['recap_submitted_at'] as String?) != null
            ? DateTime.parse(j['recap_submitted_at'] as String)
            : null,
      );
}
