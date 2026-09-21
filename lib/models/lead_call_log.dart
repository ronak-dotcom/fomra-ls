import 'package:flutter/material.dart';

enum CallDirection {
  outgoing,
  incoming;

  String get label => switch (this) {
        CallDirection.outgoing => 'Outgoing',
        CallDirection.incoming => 'Incoming',
      };

  String get dbValue => name;

  static CallDirection fromDb(String? raw) {
    return CallDirection.values.firstWhere(
      (d) => d.dbValue == raw,
      orElse: () => CallDirection.outgoing,
    );
  }
}

enum CallOutcome {
  answered,
  notAnswered;

  String get label => switch (this) {
        CallOutcome.answered => 'Answered',
        CallOutcome.notAnswered => 'Not answered',
      };

  String get dbValue => switch (this) {
        CallOutcome.answered => 'answered',
        CallOutcome.notAnswered => 'not_answered',
      };

  static CallOutcome fromDb(String? raw) {
    if (raw == 'not_answered') return CallOutcome.notAnswered;
    return CallOutcome.answered;
  }

  IconData get icon => switch (this) {
        CallOutcome.answered => Icons.check_circle_outline_rounded,
        CallOutcome.notAnswered => Icons.phone_missed_rounded,
      };
}

class LeadCallLog {
  final String id;
  final String leadId;
  final DateTime calledAt;
  final String duration;
  final String details;
  final CallDirection direction;
  final CallOutcome outcome;
  final String loggedByName;

  /// When a follow-up was scheduled for this call, or null if none.
  final DateTime? followUpAt;

  /// When this record was actually entered — distinct from [calledAt], the
  /// date the call itself took place. See LandLeadMeeting.createdAt.
  final DateTime createdAt;

  const LeadCallLog({
    required this.id,
    required this.leadId,
    required this.calledAt,
    required this.duration,
    required this.details,
    this.direction = CallDirection.outgoing,
    this.outcome = CallOutcome.answered,
    required this.loggedByName,
    this.followUpAt,
    required this.createdAt,
  });

  factory LeadCallLog.fromJson(Map<String, dynamic> j) => LeadCallLog(
        id: j['id'] as String,
        leadId: j['lead_id'] as String,
        calledAt: DateTime.parse(j['called_at'] as String),
        duration: j['duration'] as String? ?? '',
        details: j['details'] as String? ?? '',
        direction: CallDirection.fromDb(j['direction'] as String?),
        outcome: CallOutcome.fromDb(j['outcome'] as String?),
        loggedByName: j['logged_by_name'] as String? ?? '',
        followUpAt: (j['follow_up_at'] as String?) != null
            ? DateTime.tryParse(j['follow_up_at'] as String)?.toLocal()
            : null,
        createdAt: j['created_at'] != null
            ? DateTime.parse(j['created_at'] as String)
            : DateTime.parse(j['called_at'] as String),
      );

  bool get isAnswered => outcome == CallOutcome.answered;

  /// Whether a follow-up was scheduled for this call.
  bool get needsFollowUp => followUpAt != null;
}

class CallActivityMetrics {
  final int outgoingNotAnswered;
  final int outgoingAnswered;
  final int incomingNotAnswered;
  final int incomingAnswered;

  const CallActivityMetrics({
    this.outgoingNotAnswered = 0,
    this.outgoingAnswered = 0,
    this.incomingNotAnswered = 0,
    this.incomingAnswered = 0,
  });

  static const zero = CallActivityMetrics();

  factory CallActivityMetrics.fromLogs(List<LeadCallLog> logs) {
    var outgoingNotAnswered = 0;
    var outgoingAnswered = 0;
    var incomingNotAnswered = 0;
    var incomingAnswered = 0;

    for (final log in logs) {
      final answered = log.isAnswered;
      switch (log.direction) {
        case CallDirection.outgoing:
          if (answered) {
            outgoingAnswered++;
          } else {
            outgoingNotAnswered++;
          }
        case CallDirection.incoming:
          if (answered) {
            incomingAnswered++;
          } else {
            incomingNotAnswered++;
          }
      }
    }

    return CallActivityMetrics(
      outgoingNotAnswered: outgoingNotAnswered,
      outgoingAnswered: outgoingAnswered,
      incomingNotAnswered: incomingNotAnswered,
      incomingAnswered: incomingAnswered,
    );
  }
}
