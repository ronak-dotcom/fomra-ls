import '../services/approval_chain.dart';

enum LandLeadSiteVisitType {
  employee,
  management;

  String get dbValue => name;

  String get label => switch (this) {
        LandLeadSiteVisitType.employee => 'Site visit',
        LandLeadSiteVisitType.management => 'Management site visit',
      };
}

enum SiteVisitApprovalStatus {
  pending,
  approved,
  rejected;

  String get dbValue => name;

  String get label => switch (this) {
        SiteVisitApprovalStatus.pending => 'Pending approval',
        SiteVisitApprovalStatus.approved => 'Approved',
        SiteVisitApprovalStatus.rejected => 'Rejected',
      };

  static SiteVisitApprovalStatus parse(String? raw) =>
      SiteVisitApprovalStatus.values.firstWhere(
        (s) => s.dbValue == raw,
        orElse: () => SiteVisitApprovalStatus.approved,
      );
}

class LandLeadSiteVisit {
  final String id;
  final String leadId;
  final DateTime visitedAt;
  final String loggedByName;
  final LandLeadSiteVisitType visitType;
  final SiteVisitApprovalStatus approvalStatus;
  final String managementNotes;
  final DateTime? reviewedAt;
  final String reviewedByName;

  /// Approval-chain routing (Reporting Manager -> Head -> Management).
  final ApprovalLevel approvalLevel;
  final String pendingWith;
  final String requestedByEmail;

  /// When this record was actually entered — distinct from [visitedAt],
  /// the date the visit itself took place. See LandLeadMeeting.createdAt
  /// for why this matters.
  final DateTime createdAt;

  const LandLeadSiteVisit({
    required this.id,
    required this.leadId,
    required this.visitedAt,
    required this.loggedByName,
    required this.createdAt,
    this.visitType = LandLeadSiteVisitType.employee,
    this.approvalStatus = SiteVisitApprovalStatus.approved,
    this.managementNotes = '',
    this.reviewedAt,
    this.reviewedByName = '',
    this.approvalLevel = ApprovalLevel.management,
    this.pendingWith = '',
    this.requestedByEmail = '',
  });

  bool get needsApproval =>
      visitType == LandLeadSiteVisitType.management &&
      approvalStatus == SiteVisitApprovalStatus.pending;

  factory LandLeadSiteVisit.fromJson(Map<String, dynamic> j) {
    final rawType = j['visit_type'] as String? ?? 'employee';
    final visitType = LandLeadSiteVisitType.values.firstWhere(
      (t) => t.dbValue == rawType,
      orElse: () => LandLeadSiteVisitType.employee,
    );
    final reviewedRaw = j['reviewed_at'];
    return LandLeadSiteVisit(
      id: j['id'] as String,
      leadId: j['lead_id'] as String,
      visitedAt: DateTime.parse(j['visited_at'] as String),
      loggedByName: j['logged_by_name'] as String? ?? '',
      createdAt: j['created_at'] != null
          ? DateTime.parse(j['created_at'] as String)
          : DateTime.parse(j['visited_at'] as String),
      visitType: visitType,
      approvalStatus:
          SiteVisitApprovalStatus.parse(j['approval_status'] as String?),
      managementNotes: j['management_notes'] as String? ?? '',
      reviewedAt: reviewedRaw == null
          ? null
          : DateTime.tryParse(reviewedRaw as String),
      reviewedByName: j['reviewed_by_name'] as String? ?? '',
      approvalLevel: ApprovalLevel.parse(j['approval_level'] as String?),
      pendingWith: j['pending_with'] as String? ?? '',
      requestedByEmail: j['requested_by_email'] as String? ?? '',
    );
  }
}
