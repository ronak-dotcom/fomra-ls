/// Who was actually present on the other side of a meeting. Kept as plain
/// strings (not an enum) so the list can grow later without a schema/app
/// migration — "Land Owner" and "Agreement Holder" are the two values that
/// count toward the landowner-meeting-completed milestone (see
/// LandLeadMeetingService.logMeeting).
class MeetingAttendeeTypes {
  static const landOwner = 'Land Owner';
  static const agreementHolder = 'Agreement Holder / Power of Attorney';
  static const broker = 'Broker';
  static const relative = 'Relative of Owner';
  static const friend = 'Friend';
  static const legalRepresentative = 'Legal Representative';
  static const other = 'Other';

  /// Older meetings were logged with this before Relative and Friend were
  /// split; it's still shown on them but no longer offered.
  static const familyOrFriend = 'Family / Friend';

  /// Offered on the form, in order.
  static const all = [
    landOwner,
    agreementHolder,
    relative,
    friend,
    broker,
    legalRepresentative,
    other,
  ];

  /// Short label for tags ("Agreement Holder / PoA").
  static String short(String type) =>
      type == agreementHolder ? 'Agreement Holder / PoA' : type;

  /// Attendee types that count as "we actually met the decision-maker" for
  /// the landowner-meeting-completed milestone.
  static const countsAsLandownerMeeting = [landOwner, agreementHolder];
}

/// One person met at a meeting, and their relation to the land owner.
class PersonMet {
  final String name;
  final String relation;

  const PersonMet({required this.name, required this.relation});

  /// Relations offered for a person met.
  static const relations = [
    'Land Owner',
    'Agreement Holder / PoA',
    'Son',
    'Daughter',
    'Spouse',
    'Brother',
    'Sister',
    'Father',
    'Mother',
    'Other relative',
    'Friend',
    'Broker',
    'Legal Representative',
    'Other',
  ];

  /// The "Who was met" attendee type a relation implies.
  static String attendeeTypeFor(String relation) => switch (relation) {
        'Land Owner' => MeetingAttendeeTypes.landOwner,
        'Agreement Holder / PoA' => MeetingAttendeeTypes.agreementHolder,
        'Friend' => MeetingAttendeeTypes.friend,
        'Broker' => MeetingAttendeeTypes.broker,
        'Legal Representative' => MeetingAttendeeTypes.legalRepresentative,
        'Other' => MeetingAttendeeTypes.other,
        _ => MeetingAttendeeTypes.relative,
      };

  bool get isEmpty => name.trim().isEmpty && relation.trim().isEmpty;

  /// "Ravi — Son"; just the name or relation when only one is known.
  String get label {
    final n = name.trim(), r = relation.trim();
    if (n.isEmpty) return r;
    if (r.isEmpty) return n;
    return '$n — $r';
  }

  Map<String, dynamic> toJson() => {'name': name.trim(), 'relation': relation};

  factory PersonMet.fromJson(Map<String, dynamic> j) => PersonMet(
        name: j['name']?.toString() ?? '',
        relation: j['relation']?.toString() ?? '',
      );
}

class LandLeadMeeting {
  final String id;
  final String leadId;
  final DateTime metAt;
  final String duration;
  final String notes;
  final String loggedByName;
  final List<String> attendeeTypes;
  final bool managementPresent;
  final List<PersonMet> peopleMet;

  /// When this record was actually entered into the system — distinct from
  /// [metAt], the date the meeting itself took place (which the person
  /// picks). A meeting logged well after it happened (e.g. no signal at the
  /// time, or catching up on a backlog) will have these differ, sometimes
  /// by weeks. Both are shown in the UI so this is never ambiguous.
  final DateTime createdAt;

  const LandLeadMeeting({
    required this.id,
    required this.leadId,
    required this.metAt,
    required this.duration,
    required this.notes,
    required this.loggedByName,
    required this.createdAt,
    this.attendeeTypes = const [],
    this.managementPresent = false,
    this.peopleMet = const [],
  });

  /// The actual land owner was present — ticked as an attendee, or one of
  /// the people met is recorded as the Land Owner. This is what the broker
  /// ranking counts as "the broker gave us a land owner meeting".
  bool get metLandOwner =>
      attendeeTypes.contains(MeetingAttendeeTypes.landOwner) ||
      peopleMet.any((p) => p.relation == 'Land Owner');

  factory LandLeadMeeting.fromJson(Map<String, dynamic> j) => LandLeadMeeting(
        id: j['id'] as String,
        leadId: j['lead_id'] as String,
        metAt: DateTime.parse(j['met_at'] as String),
        duration: j['duration'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        loggedByName: j['logged_by_name'] as String? ?? '',
        // Fallback to metAt only for the unexpected case created_at is
        // somehow absent — Postgres always sets it on insert.
        createdAt: j['created_at'] != null
            ? DateTime.parse(j['created_at'] as String)
            : DateTime.parse(j['met_at'] as String),
        attendeeTypes: (j['attendee_types'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        managementPresent: j['management_present'] as bool? ?? false,
        peopleMet: (j['people_met'] as List?)
                ?.whereType<Map>()
                .map((e) => PersonMet.fromJson(Map<String, dynamic>.from(e)))
                .where((p) => !p.isEmpty)
                .toList() ??
            const [],
      );
}
