import '../models/land_lead.dart';
import '../models/land_lead_site_visit.dart';
import '../models/land_lead_meeting.dart';
import '../services/management_bi_activity_service.dart';
import 'ai_lead_score.dart';
import 'management_bi_metrics.dart';

// ── Reminder / escalation types ─────────────────────────────────────────────

enum IntelReminderKind {
  noActivity3Days,
  noMeetingAfterAssignment,
  visitNotUpdated,
  surveyPending,
  legalPending,
}

extension IntelReminderKindX on IntelReminderKind {
  String get label => switch (this) {
        IntelReminderKind.noActivity3Days => 'No activity for 3 days',
        IntelReminderKind.noMeetingAfterAssignment =>
          'No meeting after assignment',
        IntelReminderKind.visitNotUpdated => 'Visit not updated',
        IntelReminderKind.surveyPending => 'Survey pending',
        IntelReminderKind.legalPending => 'Legal pending',
      };
}

enum IntelApprovalKind { survey, legal, documents, managementVisit }

extension IntelApprovalKindX on IntelApprovalKind {
  String get label => switch (this) {
        IntelApprovalKind.survey => 'Survey',
        IntelApprovalKind.legal => 'Legal',
        IntelApprovalKind.documents => 'Documents',
        IntelApprovalKind.managementVisit => 'Management visit',
      };
}

class IntelReminderItem {
  final LandLead lead;
  final IntelReminderKind kind;
  final int daysStale;
  final String detail;

  const IntelReminderItem({
    required this.lead,
    required this.kind,
    required this.daysStale,
    required this.detail,
  });
}

class IntelEscalationItem {
  final LandLead lead;
  final String reason;
  final int overdueDays;
  final String? visitId;

  const IntelEscalationItem({
    required this.lead,
    required this.reason,
    required this.overdueDays,
    this.visitId,
  });
}

class IntelApprovalItem {
  final LandLead lead;
  final IntelApprovalKind kind;
  final int pendingDays;
  final String detail;
  final String? visitId;

  const IntelApprovalItem({
    required this.lead,
    required this.kind,
    required this.pendingDays,
    required this.detail,
    this.visitId,
  });
}

class IntelDuplicateGroup {
  final String matchKey;
  final List<String> matchFields;
  final List<LandLead> leads;

  const IntelDuplicateGroup({
    required this.matchKey,
    required this.matchFields,
    required this.leads,
  });
}

class IntelVillagePerf {
  final String village;
  final int total;
  final int signed;
  final double conversionPct;
  final double acres;

  const IntelVillagePerf({
    required this.village,
    required this.total,
    required this.signed,
    required this.conversionPct,
    required this.acres,
  });
}

class IntelExecutiveSpeed {
  final String name;
  final int closed;
  final double avgClosingDays;

  const IntelExecutiveSpeed({
    required this.name,
    required this.closed,
    required this.avgClosingDays,
  });
}

class IntelSeasonalPoint {
  final int month; // 1–12
  final int leadsAdded;
  final int closed;

  const IntelSeasonalPoint({
    required this.month,
    required this.leadsAdded,
    required this.closed,
  });
}

class IntelPredictiveAnalytics {
  final List<IntelVillagePerf> bestVillages;
  final List<IntelExecutiveSpeed> fastestExecutives;
  final double avgNegotiationDays;
  final List<IntelSeasonalPoint> seasonalTrends;
  final double expectedClosingDays;

  const IntelPredictiveAnalytics({
    required this.bestVillages,
    required this.fastestExecutives,
    required this.avgNegotiationDays,
    required this.seasonalTrends,
    required this.expectedClosingDays,
  });
}

class IntelLeadSuggestion {
  final LandLead lead;
  final double score;
  final String reason;

  const IntelLeadSuggestion({
    required this.lead,
    required this.score,
    required this.reason,
  });
}

class IntelRecommendation {
  final LandLead lead;
  final String nextAction;
  final String category; // priority | likely_success | next_action
  final double confidence;
  final String rationale;

  const IntelRecommendation({
    required this.lead,
    required this.nextAction,
    required this.category,
    required this.confidence,
    required this.rationale,
  });
}

class ManagementIntelligenceSnapshot {
  final List<IntelReminderItem> reminders;
  final List<IntelEscalationItem> escalations;
  final List<IntelApprovalItem> approvalQueue;
  final List<IntelDuplicateGroup> duplicates;
  final IntelPredictiveAnalytics predictive;
  final List<IntelLeadSuggestion> bestSuggestions;
  final List<IntelRecommendation> recommendations;

  const ManagementIntelligenceSnapshot({
    required this.reminders,
    required this.escalations,
    required this.approvalQueue,
    required this.duplicates,
    required this.predictive,
    required this.bestSuggestions,
    required this.recommendations,
  });
}

/// Read-only intelligence layer. Never mutates leads.
class ManagementIntelligence {
  /// Live, entry-time duplicate check for one candidate lead against the
  /// already-loaded roster — same normalized owner/phone/survey/village+
  /// owner/location matching as the retrospective dashboard duplicate
  /// scan (_duplicates below), just evaluated for a single new-or-edited
  /// record instead of grouping the whole list. Intended to be called from
  /// the Add/Edit Lead form before save so a likely duplicate is caught
  /// while the executive is still typing, not days later on a dashboard.
  ///
  /// [excludeLeadId] should be the lead's own id when editing, so a lead
  /// never flags itself as its own duplicate.
  static List<({LandLead lead, List<String> matchedFields})>
      findLiveDuplicates(
    LandLead candidate,
    List<LandLead> existingLeads, {
    String? excludeLeadId,
  }) {
    // Only strong signals: a road / area name is shared by many lands (the
    // map fills Location in automatically), so it is not a duplicate on its
    // own. Each match reads as a sentence so the user sees why.
    final owner = _normText(candidate.ownerName);
    final phone = _normPhone(candidate.contactDetails);
    final survey = _normText(candidate.surveyNumber);
    final village = _normText(candidate.village);

    final out = <({LandLead lead, List<String> matchedFields})>[];
    for (final other in existingLeads) {
      if (other.leadId == excludeLeadId) continue;
      final matched = <String>[];
      final sameVillage =
          village.length >= 3 && _normText(other.village) == village;

      if (survey.isNotEmpty &&
          sameVillage &&
          _normText(other.surveyNumber) == survey) {
        matched.add('Same survey no. ${candidate.surveyNumber.trim()} in '
            '${candidate.village.trim()}');
      }
      if (phone.length >= 10 && _normPhone(other.contactDetails) == phone) {
        matched.add('Same owner mobile ${candidate.contactDetails.trim()}');
      }
      if (owner.length >= 3 &&
          sameVillage &&
          _normText(other.ownerName) == owner) {
        matched.add('Same owner name (${candidate.ownerName.trim()}) in '
            '${candidate.village.trim()}');
      }

      if (matched.isNotEmpty) out.add((lead: other, matchedFields: matched));
    }
    return out;
  }

  static ManagementIntelligenceSnapshot build({
    required List<LandLead> leads,
    ManagementBiActivityBundle activity = ManagementBiActivityBundle.empty,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final index = _ActivityIndex.from(activity);

    final reminders = _reminders(leads, index, clock);
    final escalations = _escalations(leads, index, clock);
    final approvals = _approvals(leads, index, clock);
    final duplicates = _duplicates(leads);
    final predictive = _predictive(leads, clock);
    final suggestions = _bestSuggestions(leads, index, clock);
    final recommendations = _recommendations(leads, index, clock);

    return ManagementIntelligenceSnapshot(
      reminders: reminders,
      escalations: escalations,
      approvalQueue: approvals,
      duplicates: duplicates,
      predictive: predictive,
      bestSuggestions: suggestions,
      recommendations: recommendations,
    );
  }

  static List<IntelReminderItem> _reminders(
    List<LandLead> leads,
    _ActivityIndex index,
    DateTime now,
  ) {
    final out = <IntelReminderItem>[];
    for (final lead in leads) {
      if (lead.status == LeadStatus.signed ||
          lead.status == LeadStatus.dropped) {
        continue;
      }
      final age = biLeadAgeDays(lead, now);
      final last = index.latestActivity(lead.leadId) ?? lead.addedOn;
      final idleDays = now.difference(last).inDays;

      if (idleDays >= 3) {
        out.add(IntelReminderItem(
          lead: lead,
          kind: IntelReminderKind.noActivity3Days,
          daysStale: idleDays,
          detail: 'Last activity $idleDays days ago',
        ));
      }
      if (!index.hasMeeting(lead.leadId) &&
          lead.createdByName.trim().isNotEmpty &&
          age >= 3) {
        out.add(IntelReminderItem(
          lead: lead,
          kind: IntelReminderKind.noMeetingAfterAssignment,
          daysStale: age,
          detail: 'Assigned to ${lead.createdByName} — no meeting logged',
        ));
      }
      if (index.hasVisit(lead.leadId)) {
        final visits = index.visitsByLead[lead.leadId] ?? const [];
        if (visits.isNotEmpty) {
          final latest = visits.first.visitedAt;
          final since = now.difference(latest).inDays;
          if (since >= 7 &&
              lead.status != LeadStatus.negotiation &&
              lead.status != LeadStatus.legal) {
            out.add(IntelReminderItem(
              lead: lead,
              kind: IntelReminderKind.visitNotUpdated,
              daysStale: since,
              detail: 'Visit logged $since days ago — status not advanced',
            ));
          }
        }
      }
      if (lead.status == LeadStatus.negotiation &&
          lead.surveyNumber.trim().isEmpty) {
        out.add(IntelReminderItem(
          lead: lead,
          kind: IntelReminderKind.surveyPending,
          daysStale: age,
          detail: 'Negotiation without survey number',
        ));
      }
      if (lead.status == LeadStatus.legal) {
        out.add(IntelReminderItem(
          lead: lead,
          kind: IntelReminderKind.legalPending,
          daysStale: age,
          detail: 'Lead sitting in Legal',
        ));
      }
    }
    out.sort((a, b) => b.daysStale.compareTo(a.daysStale));
    return out;
  }

  static List<IntelEscalationItem> _escalations(
    List<LandLead> leads,
    _ActivityIndex index,
    DateTime now,
  ) {
    final byId = {for (final l in leads) l.leadId: l};
    final out = <IntelEscalationItem>[];

    for (final entry in index.visitsByLead.entries) {
      for (final visit in entry.value) {
        if (!visit.needsApproval) continue;
        final days = now.difference(visit.visitedAt).inDays;
        if (days < 2) continue;
        final lead = byId[entry.key];
        if (lead == null) continue;
        out.add(IntelEscalationItem(
          lead: lead,
          reason: 'Management visit approval overdue',
          overdueDays: days,
          visitId: visit.id,
        ));
      }
    }

    for (final lead in leads) {
      if (lead.status != LeadStatus.legal) continue;
      final days = biLeadAgeDays(lead, now);
      if (days < 21) continue;
      out.add(IntelEscalationItem(
        lead: lead,
        reason: 'Legal stage overdue for review',
        overdueDays: days - 21,
      ));
    }

    out.sort((a, b) => b.overdueDays.compareTo(a.overdueDays));
    return out;
  }

  static List<IntelApprovalItem> _approvals(
    List<LandLead> leads,
    _ActivityIndex index,
    DateTime now,
  ) {
    final out = <IntelApprovalItem>[];
    final byId = {for (final l in leads) l.leadId: l};

    for (final lead in leads) {
      if (lead.status == LeadStatus.negotiation &&
          lead.surveyNumber.trim().isEmpty) {
        out.add(IntelApprovalItem(
          lead: lead,
          kind: IntelApprovalKind.survey,
          pendingDays: biLeadAgeDays(lead, now),
          detail: 'Survey number missing — awaiting survey completion',
        ));
      }
      if (lead.status == LeadStatus.legal) {
        out.add(IntelApprovalItem(
          lead: lead,
          kind: IntelApprovalKind.legal,
          pendingDays: biLeadAgeDays(lead, now),
          detail: 'Legal verification pending',
        ));
        if (lead.accessDetails.trim().isEmpty) {
          out.add(IntelApprovalItem(
            lead: lead,
            kind: IntelApprovalKind.documents,
            pendingDays: biLeadAgeDays(lead, now),
            detail: 'Deal / document details incomplete',
          ));
        }
      }
    }

    for (final entry in index.visitsByLead.entries) {
      for (final visit in entry.value) {
        if (!visit.needsApproval) continue;
        final lead = byId[entry.key];
        if (lead == null) continue;
        out.add(IntelApprovalItem(
          lead: lead,
          kind: IntelApprovalKind.managementVisit,
          pendingDays: now.difference(visit.visitedAt).inDays,
          detail: 'Management site visit awaiting approval',
          visitId: visit.id,
        ));
      }
    }

    out.sort((a, b) => b.pendingDays.compareTo(a.pendingDays));
    return out;
  }

  static String _normPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length >= 10) return digits.substring(digits.length - 10);
    return digits;
  }

  static String _normText(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static List<IntelDuplicateGroup> _duplicates(List<LandLead> leads) {
    final groups = <String, List<LandLead>>{};
    final fields = <String, Set<String>>{};

    void add(String key, String field, LandLead lead) {
      if (key.isEmpty) return;
      (groups[key] ??= []).add(lead);
      (fields[key] ??= {}).add(field);
    }

    for (final lead in leads) {
      final owner = _normText(lead.ownerName);
      final phone = _normPhone(lead.contactDetails);
      final survey = _normText(lead.surveyNumber);
      final village = _normText(lead.village);
      final location = _normText(lead.location);

      if (owner.length >= 3) add('owner:$owner', 'Owner Name', lead);
      if (phone.length >= 10) add('phone:$phone', 'Mobile Number', lead);
      if (survey.length >= 2) add('survey:$survey', 'Survey Number', lead);
      if (village.length >= 3 && owner.length >= 3) {
        add('village_owner:$village|$owner', 'Village + Owner', lead);
      }
      if (location.length >= 5) add('loc:$location', 'Location', lead);
    }

    final out = <IntelDuplicateGroup>[];
    final seenLeadSets = <String>{};

    for (final entry in groups.entries) {
      final unique = <String, LandLead>{};
      for (final l in entry.value) {
        unique[l.leadId] = l;
      }
      if (unique.length < 2) continue;
      final idKey = (unique.keys.toList()..sort()).join(',');
      if (seenLeadSets.contains(idKey)) continue;
      seenLeadSets.add(idKey);
      out.add(IntelDuplicateGroup(
        matchKey: entry.key,
        matchFields: fields[entry.key]!.toList(),
        leads: unique.values.toList(),
      ));
    }

    out.sort((a, b) => b.leads.length.compareTo(a.leads.length));
    return out.take(20).toList();
  }

  static IntelPredictiveAnalytics _predictive(
    List<LandLead> leads,
    DateTime now,
  ) {
    final byVillage = <String, List<LandLead>>{};
    for (final l in leads) {
      final v = l.village.trim().isNotEmpty
          ? l.village.trim()
          : (l.location.trim().isNotEmpty ? l.location.trim() : 'Unknown');
      (byVillage[v] ??= []).add(l);
    }

    final villages = <IntelVillagePerf>[];
    for (final e in byVillage.entries) {
      if (e.value.length < 2) continue;
      final signed =
          e.value.where((l) => l.status == LeadStatus.signed).length;
      villages.add(IntelVillagePerf(
        village: e.key,
        total: e.value.length,
        signed: signed,
        conversionPct: (signed / e.value.length) * 100,
        acres: e.value.fold(0, (s, l) => s + biLeadAcres(l)),
      ));
    }
    villages.sort((a, b) {
      final c = b.conversionPct.compareTo(a.conversionPct);
      if (c != 0) return c;
      return b.signed.compareTo(a.signed);
    });

    final byExec = <String, List<LandLead>>{};
    for (final l in leads) {
      final n = l.createdByName.trim();
      if (n.isEmpty || n.toLowerCase() == 'management') continue;
      (byExec[n] ??= []).add(l);
    }
    final fastest = <IntelExecutiveSpeed>[];
    for (final e in byExec.entries) {
      final closed =
          e.value.where((l) => l.status == LeadStatus.signed).toList();
      if (closed.isEmpty) continue;
      final avg = closed.fold<double>(
            0,
            (s, l) => s + biLeadAgeDays(l, now),
          ) /
          closed.length;
      fastest.add(IntelExecutiveSpeed(
        name: e.key,
        closed: closed.length,
        avgClosingDays: avg,
      ));
    }
    fastest.sort((a, b) => a.avgClosingDays.compareTo(b.avgClosingDays));

    final negotiation =
        leads.where((l) => l.status == LeadStatus.negotiation).toList();
    final avgNeg = negotiation.isEmpty
        ? 0.0
        : negotiation.fold<double>(0, (s, l) => s + biLeadAgeDays(l, now)) /
            negotiation.length;

    final seasonal = List.generate(12, (i) {
      final month = i + 1;
      final added = leads.where((l) => l.addedOn.month == month).length;
      final closed = leads
          .where((l) =>
              l.status == LeadStatus.signed && l.addedOn.month == month)
          .length;
      return IntelSeasonalPoint(
        month: month,
        leadsAdded: added,
        closed: closed,
      );
    });

    final allClosed =
        leads.where((l) => l.status == LeadStatus.signed).toList();
    final expected = allClosed.isEmpty
        ? 30.0
        : allClosed.fold<double>(0, (s, l) => s + biLeadAgeDays(l, now)) /
            allClosed.length;

    return IntelPredictiveAnalytics(
      bestVillages: villages.take(8).toList(),
      fastestExecutives: fastest.take(8).toList(),
      avgNegotiationDays: avgNeg,
      seasonalTrends: seasonal,
      expectedClosingDays: expected,
    );
  }

  /// AI Lead Score (0–100) for a single lead, using the same weighted model
  /// (Lead Progress, Land Quality, Owner Engagement, Documentation, Follow-up
  /// Health, Risk Factors) as [AiLeadScore.compute] — screens that need the
  /// full breakdown (e.g. the lead detail page) should call that directly.
  static double _successScore(LandLead lead, _ActivityIndex index) =>
      AiLeadScore.compute(
        lead: lead,
        meetings: index.meetingsByLead[lead.leadId] ?? const [],
        siteVisits: index.visitsByLead[lead.leadId] ?? const [],
      ).score.toDouble();

  static List<IntelLeadSuggestion> _bestSuggestions(
    List<LandLead> leads,
    _ActivityIndex index,
    DateTime now,
  ) {
    final active = leads.where((l) => l.status.isActive).toList();
    final scored = active
        .map((l) => IntelLeadSuggestion(
              lead: l,
              score: _successScore(l, index),
              reason: _suggestionReason(l, index),
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return scored.take(10).toList();
  }

  static String _suggestionReason(LandLead lead, _ActivityIndex index) {
    final parts = <String>[];
    parts.add(lead.status.shortLabel);
    if (index.hasVisit(lead.leadId)) parts.add('site visit done');
    if (index.hasMeeting(lead.leadId)) parts.add('meeting logged');
    if (lead.surveyNumber.trim().isNotEmpty) parts.add('survey on file');
    if (biLeadAcres(lead) > 0) {
      parts.add('${biLeadAcres(lead).toStringAsFixed(1)} ac');
    }
    return parts.join(' · ');
  }

  static List<IntelRecommendation> _recommendations(
    List<LandLead> leads,
    _ActivityIndex index,
    DateTime now,
  ) {
    final out = <IntelRecommendation>[];
    final active = leads.where((l) => l.status.isActive).toList();

    for (final lead in active) {
      final score = _successScore(lead, index);
      final age = biLeadAgeDays(lead, now);
      final next = _bestNextAction(lead, index, age);

      out.add(IntelRecommendation(
        lead: lead,
        nextAction: next,
        category: 'next_action',
        confidence: (55 + score * 0.35).clamp(40, 95),
        rationale: 'Based on stage, activity and age ($age d)',
      ));

      if (score >= 60) {
        out.add(IntelRecommendation(
          lead: lead,
          nextAction: 'Prioritize follow-up',
          category: 'priority',
          confidence: score.clamp(50, 98),
          rationale: _suggestionReason(lead, index),
        ));
      }
      if (score >= 70 && lead.status != LeadStatus.dropped) {
        out.add(IntelRecommendation(
          lead: lead,
          nextAction: 'Likely to close',
          category: 'likely_success',
          confidence: score.clamp(60, 99),
          rationale: 'High engagement + advanced stage signals',
        ));
      }
    }

    out.sort((a, b) => b.confidence.compareTo(a.confidence));
    return out.take(30).toList();
  }

  static String _bestNextAction(
    LandLead lead,
    _ActivityIndex index,
    int age,
  ) {
    if (!index.hasVisit(lead.leadId) && lead.status.isProspect) {
      return 'Schedule site visit';
    }
    if (!index.hasMeeting(lead.leadId) &&
        lead.status == LeadStatus.prospectMeetingPending) {
      return 'Schedule meeting';
    }
    if (lead.status == LeadStatus.negotiation &&
        lead.surveyNumber.trim().isEmpty) {
      return 'Collect survey / Chitta';
    }
    if (lead.status == LeadStatus.legal) return 'Complete legal documents';
    if (age >= 7) return 'Re-engage owner';
    return 'Update stage progress';
  }
}

class _ActivityIndex {
  final Map<String, List<LandLeadMeeting>> meetingsByLead;
  final Map<String, List<LandLeadSiteVisit>> visitsByLead;

  _ActivityIndex({
    required this.meetingsByLead,
    required this.visitsByLead,
  });

  factory _ActivityIndex.from(ManagementBiActivityBundle bundle) {
    final meetings = <String, List<LandLeadMeeting>>{};
    for (final m in bundle.meetings) {
      (meetings[m.leadId] ??= []).add(m);
    }
    final visits = <String, List<LandLeadSiteVisit>>{};
    for (final v in bundle.siteVisits) {
      (visits[v.leadId] ??= []).add(v);
    }
    return _ActivityIndex(
      meetingsByLead: meetings,
      visitsByLead: visits,
    );
  }

  bool hasMeeting(String id) => meetingsByLead[id]?.isNotEmpty ?? false;
  bool hasVisit(String id) => visitsByLead[id]?.isNotEmpty ?? false;

  DateTime? latestActivity(String id) {
    DateTime? best;
    void consider(DateTime? t) {
      if (t == null) return;
      if (best == null || t.isAfter(best!)) best = t;
    }

    for (final m in meetingsByLead[id] ?? const []) {
      consider(m.metAt);
    }
    for (final v in visitsByLead[id] ?? const []) {
      consider(v.visitedAt);
    }
    return best;
  }
}
