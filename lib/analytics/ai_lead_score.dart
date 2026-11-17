import '../models/land_lead.dart';
import '../models/land_lead_legal_document.dart';
import '../models/land_lead_meeting.dart';
import '../models/land_lead_site_visit.dart';
import 'management_bi_metrics.dart';

/// Score bands for the weighted AI Lead Score (0-100).
enum AiScoreBand { excellent, good, moderate, needsAttention, highRisk }

extension AiScoreBandX on AiScoreBand {
  String get label => switch (this) {
        AiScoreBand.excellent => 'Excellent',
        AiScoreBand.good => 'Good',
        AiScoreBand.moderate => 'Moderate',
        AiScoreBand.needsAttention => 'Needs Attention',
        AiScoreBand.highRisk => 'High Risk',
      };

  static AiScoreBand forScore(int score) {
    if (score >= 90) return AiScoreBand.excellent;
    if (score >= 75) return AiScoreBand.good;
    if (score >= 60) return AiScoreBand.moderate;
    if (score >= 40) return AiScoreBand.needsAttention;
    return AiScoreBand.highRisk;
  }
}

/// One weighted factor in the AI score (e.g. "Land Quality — 20%").
class AiScoreCategory {
  final String label;
  final double weightPercent;
  final double rawScore; // 0-100, before weighting
  final List<String> notes;

  const AiScoreCategory({
    required this.label,
    required this.weightPercent,
    required this.rawScore,
    required this.notes,
  });

  double get weightedPoints => rawScore * weightPercent / 100;
}

class AiLeadScoreResult {
  final int score;
  final AiScoreBand band;
  final List<AiScoreCategory> categories;

  const AiLeadScoreResult({
    required this.score,
    required this.band,
    required this.categories,
  });
}

/// Weighted AI Lead Score based on real land-acquisition factors:
/// Lead Progress & Stage (25%), Land Quality (20%), Owner Engagement (20%),
/// Documentation (15%), Follow-up Health (10%), Risk Factors (10%, scored as
/// 100 minus deductions so a risk-free lead still earns the full 10%).
abstract final class AiLeadScore {
  static AiLeadScoreResult compute({
    required LandLead lead,
    List<LandLeadMeeting> meetings = const [],
    List<LandLeadSiteVisit> siteVisits = const [],
    List<LandLeadLegalDocument> legalDocs = const [],
    List<LandLead> allLeads = const [],
    int overdueTaskCount = 0,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final categories = <AiScoreCategory>[
      _progressCategory(lead, legalDocs),
      _qualityCategory(lead),
      _engagementCategory(meetings, siteVisits),
      _documentationCategory(legalDocs),
      _followUpCategory(lead, meetings, siteVisits, overdueTaskCount, clock),
      _riskCategory(lead, meetings, siteVisits, legalDocs, allLeads, clock),
    ];
    final total =
        categories.fold<double>(0, (s, c) => s + c.weightedPoints);
    final score = total.clamp(0, 100).round();
    return AiLeadScoreResult(
      score: score,
      band: AiScoreBandX.forScore(score),
      categories: categories,
    );
  }

  // ── Lead Progress & Stage (25%) ─────────────────────────────────────────

  static AiScoreCategory _progressCategory(
    LandLead lead,
    List<LandLeadLegalDocument> legalDocs,
  ) {
    final stagePts = switch (lead.status) {
      LeadStatus.dropped => 0.0,
      LeadStatus.onHold => 20.0,
      LeadStatus.prospectMeetingPending => 20.0,
      LeadStatus.prospectMeetingCompleted => 40.0,
      LeadStatus.managementMeetingCompleted => 50.0,
      LeadStatus.negotiation => 60.0,
      LeadStatus.legal => 82.0,
      LeadStatus.signed => 100.0,
    };
    final surveyPts = lead.surveyNumber.trim().isNotEmpty ? 100.0 : 0.0;
    final presentTypes = _presentDocTypes(legalDocs);
    final legalPts =
        (presentTypes.length / _requiredDocTypes.length * 100).clamp(0, 100);
    final agreementPts = switch (lead.status) {
      LeadStatus.signed => 100.0,
      LeadStatus.legal => 65.0,
      LeadStatus.negotiation => 35.0,
      _ => 0.0,
    };
    final raw = (stagePts + surveyPts + legalPts + agreementPts) / 4;

    return AiScoreCategory(
      label: 'Lead Progress & Stage',
      weightPercent: 25,
      rawScore: raw,
      notes: [
        'Stage: ${lead.status.shortLabel}',
        surveyPts > 0 ? 'Survey number on file' : 'Survey number missing',
        'Legal docs: ${presentTypes.length}/${_requiredDocTypes.length} types uploaded',
        lead.status == LeadStatus.signed
            ? 'Agreement completed'
            : lead.status == LeadStatus.legal
                ? 'Agreement in legal review'
                : lead.status == LeadStatus.negotiation
                    ? 'Agreement in negotiation'
                    : 'Agreement not started',
      ],
    );
  }

  // ── Land Quality (20%) ──────────────────────────────────────────────────

  static AiScoreCategory _qualityCategory(LandLead lead) {
    final acres = biLeadAcres(lead);
    final acresPts = acres >= 2
        ? 100.0
        : acres >= 1
            ? 75.0
            : acres >= 0.5
                ? 50.0
                : acres > 0
                    ? 25.0
                    : 0.0;

    final roadFeet = _parseLeadingNumber(lead.roadWidth);
    final roadPts = roadFeet == null
        ? 0.0
        : roadFeet >= 30
            ? 100.0
            : roadFeet >= 20
                ? 75.0
                : roadFeet >= 10
                    ? 50.0
                    : 25.0;

    final access = lead.accessDetails.trim().toLowerCase();
    const infraKeywords = [
      'water',
      'electricity',
      'power',
      'drainage',
      'school',
      'hospital',
      'highway',
      'bus',
      'road',
    ];
    final hits = infraKeywords.where(access.contains).length;
    final infraPts = access.isEmpty
        ? 0.0
        : (50.0 + hits * 12.5).clamp(0, 100);

    final demandPts = switch (lead.landType) {
      LandType.commercial => 100.0,
      LandType.residential => 85.0,
      LandType.industrial => 70.0,
      LandType.nonAgricultural => 55.0,
      LandType.agricultural => 40.0,
      LandType.other => 30.0,
    };

    final raw = (acresPts + roadPts + infraPts + demandPts) / 4;
    return AiScoreCategory(
      label: 'Land Quality',
      weightPercent: 20,
      rawScore: raw,
      notes: [
        acres > 0 ? '${acres.toStringAsFixed(2)} acres' : 'Extent not recorded',
        roadFeet != null ? 'Road width ${roadFeet.round()} ft' : 'Road access not recorded',
        access.isEmpty ? 'No infrastructure notes' : '$hits infrastructure signal(s) noted',
        'Land type: ${_landTypeLabel(lead.landType)}',
      ],
    );
  }

  // ── Owner Engagement (20%) ──────────────────────────────────────────────

  static AiScoreCategory _engagementCategory(
    List<LandLeadMeeting> meetings,
    List<LandLeadSiteVisit> siteVisits,
  ) {
    // Meetings and site visits (the team doesn't log calls in the app).
    final meetingsPts = (meetings.length * 50.0).clamp(0, 100);
    final visitsPts = (siteVisits.length * 50.0).clamp(0, 100);
    final raw = (meetingsPts + visitsPts) / 2;
    return AiScoreCategory(
      label: 'Owner Engagement',
      weightPercent: 20,
      rawScore: raw,
      notes: [
        '${meetings.length} meeting(s) completed',
        '${siteVisits.length} site visit(s) logged',
      ],
    );
  }

  // ── Documentation (15%) ─────────────────────────────────────────────────

  static AiScoreCategory _documentationCategory(
    List<LandLeadLegalDocument> legalDocs,
  ) {
    final present = _presentDocTypes(legalDocs);
    final raw =
        (present.length / _requiredDocTypes.length * 100).clamp(0, 100).toDouble();
    final missing =
        _requiredDocTypes.where((t) => !present.contains(t)).toList();
    return AiScoreCategory(
      label: 'Documentation',
      weightPercent: 15,
      rawScore: raw,
      notes: [
        'Uploaded: ${present.isEmpty ? 'none' : present.map(_docTypeLabel).join(', ')}',
        missing.isEmpty
            ? 'All mandatory documents present'
            : 'Missing: ${missing.map(_docTypeLabel).join(', ')}',
      ],
    );
  }

  // ── Follow-up Health (10%) ──────────────────────────────────────────────

  static AiScoreCategory _followUpCategory(
    LandLead lead,
    List<LandLeadMeeting> meetings,
    List<LandLeadSiteVisit> siteVisits,
    int overdueTaskCount,
    DateTime now,
  ) {
    final lastActivity = _lastActivityDate(lead, meetings, siteVisits);
    final daysSince = now.difference(lastActivity).inDays;
    final recencyPts = daysSince <= 3
        ? 100.0
        : daysSince <= 7
            ? 80.0
            : daysSince <= 14
                ? 55.0
                : daysSince <= 30
                    ? 25.0
                    : 0.0;

    final overduePts = overdueTaskCount == 0
        ? 100.0
        : overdueTaskCount == 1
            ? 60.0
            : 20.0;

    final ageDays = biLeadAgeDays(lead, now).clamp(1, 100000);
    final totalActivity = meetings.length + siteVisits.length;
    final expectedTouchpoints = (ageDays / 14).clamp(1, 100000);
    final frequencyPts =
        (totalActivity / expectedTouchpoints * 100).clamp(0, 100);

    final raw = (recencyPts + overduePts + frequencyPts) / 3;
    return AiScoreCategory(
      label: 'Follow-up Health',
      weightPercent: 10,
      rawScore: raw,
      notes: [
        'Last activity $daysSince day(s) ago',
        overdueTaskCount == 0
            ? 'No overdue tasks'
            : '$overdueTaskCount overdue task(s)',
        'Timeline consistency: ${frequencyPts.round()}%',
      ],
    );
  }

  // ── Risk Factors (10%, scored 100 = risk-free) ──────────────────────────

  static AiScoreCategory _riskCategory(
    LandLead lead,
    List<LandLeadMeeting> meetings,
    List<LandLeadSiteVisit> siteVisits,
    List<LandLeadLegalDocument> legalDocs,
    List<LandLead> allLeads,
    DateTime now,
  ) {
    var deductions = 0.0;
    final notes = <String>[];

    final lastActivity = _lastActivityDate(lead, meetings, siteVisits);
    final inactiveDays = now.difference(lastActivity).inDays;
    if (inactiveDays > 30) {
      deductions += 40;
      notes.add('Inactive for $inactiveDays days');
    } else if (inactiveDays > 14) {
      deductions += 20;
      notes.add('No activity in $inactiveDays days');
    }

    final activeNegotiation =
        lead.status == LeadStatus.negotiation || lead.status == LeadStatus.legal;
    if (activeNegotiation &&
        _presentDocTypes(legalDocs).length < (_requiredDocTypes.length / 2)) {
      deductions += 15;
      notes.add('Missing mandatory documents for this stage');
    }

    final noteText = '${lead.notes} ${lead.dropNotes}'.toLowerCase();
    const legalIssueKeywords = ['dispute', 'litigation', 'objection', 'legal issue', 'court'];
    if (legalIssueKeywords.any(noteText.contains)) {
      deductions += 20;
      notes.add('Legal issue flagged in notes');
    }

    final isDuplicate = allLeads.any((other) =>
        other.leadId != lead.leadId &&
        lead.contactDetails.trim().isNotEmpty &&
        other.contactDetails.trim() == lead.contactDetails.trim() &&
        lead.gpsCoordinates.trim().isNotEmpty &&
        other.gpsCoordinates.trim() == lead.gpsCoordinates.trim());
    if (isDuplicate) {
      deductions += 30;
      notes.add('Possible duplicate lead detected');
    }

    if (lead.status == LeadStatus.dropped) {
      deductions += 40;
      notes.add('Lead marked as dropped');
    }

    if (notes.isEmpty) notes.add('No risk indicators detected');

    final raw = (100 - deductions).clamp(0, 100).toDouble();
    return AiScoreCategory(
      label: 'Risk Factors',
      weightPercent: 10,
      rawScore: raw,
      notes: notes,
    );
  }

  // ── Shared helpers ───────────────────────────────────────────────────────

  static const _requiredDocTypes = ['patta', 'chitta', 'fmb', 'ec', 'sale deed'];

  static String _docTypeLabel(String type) => switch (type) {
        'patta' => 'Patta',
        'chitta' => 'Chitta',
        'fmb' => 'FMB',
        'ec' => 'EC',
        'sale deed' => 'Sale Deed',
        _ => type,
      };

  static Set<String> _presentDocTypes(List<LandLeadLegalDocument> docs) {
    final found = <String>{};
    for (final d in docs) {
      final n = d.fileName.toLowerCase();
      if (n.contains('patta')) found.add('patta');
      if (n.contains('chitta')) found.add('chitta');
      if (n.contains('fmb')) found.add('fmb');
      if (RegExp(r'(^|[^a-z])ec([^a-z]|$)').hasMatch(n) ||
          n.contains('encumbrance')) {
        found.add('ec');
      }
      if (n.contains('sale') || n.contains('deed')) found.add('sale deed');
    }
    return found;
  }

  static DateTime _lastActivityDate(
    LandLead lead,
    List<LandLeadMeeting> meetings,
    List<LandLeadSiteVisit> siteVisits,
  ) {
    var latest = lead.addedOn;
    for (final m in meetings) {
      if (m.metAt.isAfter(latest)) latest = m.metAt;
    }
    for (final v in siteVisits) {
      if (v.visitedAt.isAfter(latest)) latest = v.visitedAt;
    }
    return latest;
  }

  static double? _parseLeadingNumber(String raw) {
    final match = RegExp(r'[\d.]+').firstMatch(raw);
    if (match == null) return null;
    return double.tryParse(match.group(0)!);
  }

  static String _landTypeLabel(LandType t) => switch (t) {
        LandType.agricultural => 'Agricultural',
        LandType.nonAgricultural => 'Non-agricultural',
        LandType.residential => 'Residential',
        LandType.commercial => 'Commercial',
        LandType.industrial => 'Industrial',
        LandType.other => 'Other',
      };
}
