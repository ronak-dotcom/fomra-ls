import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/models/lead_review.dart';

LeadReview _review({required DateTime reviewedAt, DateTime? next}) =>
    LeadReview(
      id: 'r',
      leadId: 'L1',
      reviewedAt: reviewedAt,
      nextReviewDate: next,
    );

void main() {
  // Wednesday 11 Nov 2026, 3pm. Its week runs Mon 9 Nov – Sun 15 Nov.
  final now = DateTime(2026, 11, 11, 15);

  bool m(ReviewFilter f, LeadReview? r) => f.matches(r, now: now);

  test('never reviewed is only "Not reviewed"', () {
    for (final f in ReviewFilter.values) {
      expect(m(f, null), f == ReviewFilter.notReviewed, reason: f.name);
    }
  });

  test('reviewed this week covers Monday 00:00 to Sunday 23:59', () {
    expect(
        m(ReviewFilter.reviewedThisWeek,
            _review(reviewedAt: DateTime(2026, 11, 9))),
        isTrue);
    expect(
        m(ReviewFilter.reviewedThisWeek,
            _review(reviewedAt: DateTime(2026, 11, 15, 23, 59))),
        isTrue);
    expect(
        m(ReviewFilter.reviewedThisWeek,
            _review(reviewedAt: DateTime(2026, 11, 8, 23, 59))),
        isFalse);
  });

  test('overdue, due today, due this week, upcoming', () {
    final past = _review(
        reviewedAt: DateTime(2026, 11, 1), next: DateTime(2026, 11, 10));
    final today = _review(
        reviewedAt: DateTime(2026, 11, 1), next: DateTime(2026, 11, 11));
    final sunday = _review(
        reviewedAt: DateTime(2026, 11, 1), next: DateTime(2026, 11, 15));
    final nextWeek = _review(
        reviewedAt: DateTime(2026, 11, 1), next: DateTime(2026, 11, 16));

    expect(m(ReviewFilter.overdue, past), isTrue);
    expect(m(ReviewFilter.overdue, today), isFalse);

    expect(m(ReviewFilter.dueToday, today), isTrue);
    expect(m(ReviewFilter.dueToday, sunday), isFalse);

    expect(m(ReviewFilter.dueThisWeek, today), isTrue);
    expect(m(ReviewFilter.dueThisWeek, sunday), isTrue);
    expect(m(ReviewFilter.dueThisWeek, nextWeek), isFalse);
    expect(m(ReviewFilter.dueThisWeek, past), isFalse);

    expect(m(ReviewFilter.upcoming, today), isTrue);
    expect(m(ReviewFilter.upcoming, nextWeek), isTrue);
    expect(m(ReviewFilter.upcoming, past), isFalse);
  });

  test('reviewed without a next date', () {
    final r = _review(reviewedAt: DateTime(2026, 11, 2));
    expect(m(ReviewFilter.reviewed, r), isTrue);
    expect(m(ReviewFilter.notScheduled, r), isTrue);
    expect(m(ReviewFilter.upcoming, r), isFalse);
    expect(m(ReviewFilter.overdue, r), isFalse);
  });
}
