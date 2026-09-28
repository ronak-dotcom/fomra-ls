import 'lead_follow_up.dart';

/// One review of a lead's property by the Reporting Manager, Head or
/// Management: who reviewed it, when, a note, and when it is due again.
class LeadReview {
  final String id;
  final String leadId;
  final DateTime reviewedAt;
  final String reviewedBy;
  final String reviewedByEmail;

  /// Management / Head / Reporting Manager — captured at review time.
  final String reviewerRole;
  final String notes;

  /// Date-only; null when no next review was scheduled.
  final DateTime? nextReviewDate;

  const LeadReview({
    required this.id,
    required this.leadId,
    required this.reviewedAt,
    this.reviewedBy = '',
    this.reviewedByEmail = '',
    this.reviewerRole = '',
    this.notes = '',
    this.nextReviewDate,
  });

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Next review date has passed without a newer review.
  bool get isOverdue =>
      nextReviewDate != null && nextReviewDate!.isBefore(_today());

  /// Next review falls on today.
  bool get isDueToday =>
      nextReviewDate != null && !isOverdue && !nextReviewDate!.isAfter(_today());

  /// Days until the next review (negative once overdue); null if unscheduled.
  int? get daysUntilNext => nextReviewDate?.difference(_today()).inDays;

  String get reviewedLabel => LeadFollowUp.formatDateTime(reviewedAt);
  String? get nextReviewLabel =>
      nextReviewDate == null ? null : LeadFollowUp.formatDate(nextReviewDate!);

  /// "yyyy-mm-dd" for a Postgres DATE column.
  static String toDateString(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDate(String? s) {
    final d = DateTime.tryParse(s ?? '');
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  factory LeadReview.fromJson(Map<String, dynamic> j) => LeadReview(
        id: j['id'].toString(),
        leadId: (j['lead_id'] as String? ?? '').trim(),
        reviewedAt:
            DateTime.tryParse(j['reviewed_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
        reviewedBy: j['reviewed_by'] as String? ?? '',
        reviewedByEmail:
            (j['reviewed_by_email'] as String? ?? '').trim().toLowerCase(),
        reviewerRole: j['reviewer_role'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        nextReviewDate: _parseDate(j['next_review_date'] as String?),
      );
}
