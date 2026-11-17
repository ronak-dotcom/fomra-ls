import '../models/land_lead.dart';
import '../models/land_lead_meeting.dart';
import '../models/land_lead_site_visit.dart';
import '../utils/lead_location_parser.dart';
import '../services/management_bi_activity_service.dart';

// ── Shared helpers ──────────────────────────────────────────────────────────

double biLeadAcres(LandLead lead) {
  final sqft = parseLandExtentSqft(lead.landExtent);
  if (sqft == null || sqft <= 0) return 0;
  return sqft / 43560;
}

int biLeadAgeDays(LandLead lead, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final a = lead.addedOn.toLocal();
  final start = DateTime(a.year, a.month, a.day);
  final today = DateTime(n.year, n.month, n.day);
  return today.difference(start).inDays;
}

/// Funnel stages requested by product — mapped onto current LeadStatus + activity.
enum BiFunnelStage {
  newLead,
  contacted,
  meeting,
  managementMeeting,
  siteVisit,
  negotiation,
  survey,
  legal,
  agreement,
  closed,
  dropped,
}

extension BiFunnelStageX on BiFunnelStage {
  String get label => switch (this) {
        BiFunnelStage.newLead => 'New',
        BiFunnelStage.contacted => 'Contacted',
        BiFunnelStage.meeting => 'Meeting',
        BiFunnelStage.managementMeeting => 'Management Meeting Completed',
        BiFunnelStage.siteVisit => 'Site Visit',
        BiFunnelStage.negotiation => 'Negotiation',
        BiFunnelStage.survey => 'Survey',
        BiFunnelStage.legal => 'Legal',
        BiFunnelStage.agreement => 'Agreement',
        BiFunnelStage.closed => 'Closed',
        BiFunnelStage.dropped => 'Dropped',
      };
}

enum BiAgeBucket { d0to30, d31to60, d61to90, d90plus }

extension BiAgeBucketX on BiAgeBucket {
  String get label => switch (this) {
        BiAgeBucket.d0to30 => '0–30 Days',
        BiAgeBucket.d31to60 => '31–60 Days',
        BiAgeBucket.d61to90 => '61–90 Days',
        BiAgeBucket.d90plus => '90+ Days',
      };

  bool get isOverdue => this == BiAgeBucket.d90plus;

  /// Bucket for a lead's age in days — shared by the Lead Ageing dashboard
  /// widget and any UI showing a per-lead age bucket (e.g. Broker Management).
  static BiAgeBucket forAgeDays(int age) => age <= 30
      ? BiAgeBucket.d0to30
      : age <= 60
          ? BiAgeBucket.d31to60
          : age <= 90
              ? BiAgeBucket.d61to90
              : BiAgeBucket.d90plus;
}

enum BiHeatLevel { active, moderate, idle }

extension BiHeatLevelX on BiHeatLevel {
  String get label => switch (this) {
        BiHeatLevel.active => 'Active',
        BiHeatLevel.moderate => 'Moderate',
        BiHeatLevel.idle => 'Idle',
      };
}

enum BiSlaKind { siteVisit, survey, legal, agreement }

extension BiSlaKindX on BiSlaKind {
  String get label => switch (this) {
        BiSlaKind.siteVisit => 'Site Visit',
        BiSlaKind.survey => 'Survey',
        BiSlaKind.legal => 'Legal',
        BiSlaKind.agreement => 'Agreement',
      };

  /// Target days from lead creation (approximated — no per-stage timestamps).
  int get targetDays => switch (this) {
        BiSlaKind.siteVisit => 7,
        BiSlaKind.survey => 14,
        BiSlaKind.legal => 21,
        BiSlaKind.agreement => 30,
      };
}

enum BiSlaUrgency { dueToday, upcoming, overdue }

// ── Result models ───────────────────────────────────────────────────────────

class BiPipelineSummary {
  final int totalLeads;
  final double totalAcres;
  final double pipelineAcres;
  final int activeDeals;
  final int closedDeals;

  const BiPipelineSummary({
    required this.totalLeads,
    required this.totalAcres,
    required this.pipelineAcres,
    required this.activeDeals,
    required this.closedDeals,
  });
}

class BiFunnelStageRow {
  final BiFunnelStage stage;
  final int leadCount;
  final double acres;
  final double conversionPct;
  final double dropOffPct;

  const BiFunnelStageRow({
    required this.stage,
    required this.leadCount,
    required this.acres,
    required this.conversionPct,
    required this.dropOffPct,
  });
}

class BiAgeBucketRow {
  final BiAgeBucket bucket;
  final int leadCount;
  final double acres;
  final List<LandLead> leads;

  const BiAgeBucketRow({
    required this.bucket,
    required this.leadCount,
    required this.acres,
    required this.leads,
  });
}

class BiBottleneckRow {
  final String id;
  final String label;
  final int count;
  final double avgPendingDays;
  final List<LandLead> leads;

  const BiBottleneckRow({
    required this.id,
    required this.label,
    required this.count,
    required this.avgPendingDays,
    required this.leads,
  });
}

class BiExecutiveRow {
  final String name;
  final int assignedLeads;
  final int convertedLeads;
  final double pipelineAcres;
  final double conversionPct;
  final double avgClosingDays;
  final int meetings;
  final int siteVisits;
  final int legalCount;
  final int agreementSuccess;
  final int rank;

  const BiExecutiveRow({
    required this.name,
    required this.assignedLeads,
    required this.convertedLeads,
    required this.pipelineAcres,
    required this.conversionPct,
    required this.avgClosingDays,
    required this.meetings,
    required this.siteVisits,
    required this.legalCount,
    required this.agreementSuccess,
    required this.rank,
  });
}

class BiVillageHeatRow {
  final String village;
  final String district;
  final int leadCount;
  final BiHeatLevel level;
  final int daysSinceActivity;

  const BiVillageHeatRow({
    required this.village,
    required this.district,
    required this.leadCount,
    required this.level,
    required this.daysSinceActivity,
  });
}

class BiSlaItem {
  final BiSlaKind kind;
  final LandLead lead;
  final BiSlaUrgency urgency;
  final int ageDays;
  final int daysRemaining;

  const BiSlaItem({
    required this.kind,
    required this.lead,
    required this.urgency,
    required this.ageDays,
    required this.daysRemaining,
  });
}

class BiSlaSummary {
  final List<BiSlaItem> dueToday;
  final List<BiSlaItem> upcoming;
  final List<BiSlaItem> overdue;

  const BiSlaSummary({
    required this.dueToday,
    required this.upcoming,
    required this.overdue,
  });
}

class ManagementBiSnapshot {
  final BiPipelineSummary pipeline;
  final List<BiFunnelStageRow> funnel;
  final List<BiAgeBucketRow> ageing;
  final List<BiBottleneckRow> bottlenecks;
  final List<BiExecutiveRow> executives;
  final List<BiVillageHeatRow> heatmap;
  final BiSlaSummary sla;

  const ManagementBiSnapshot({
    required this.pipeline,
    required this.funnel,
    required this.ageing,
    required this.bottlenecks,
    required this.executives,
    required this.heatmap,
    required this.sla,
  });
}

// ── Index helpers ───────────────────────────────────────────────────────────

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

  bool hasMeeting(String id) => (meetingsByLead[id]?.isNotEmpty ?? false);
  bool hasVisit(String id) => (visitsByLead[id]?.isNotEmpty ?? false);

  int meetingCount(String id) => meetingsByLead[id]?.length ?? 0;
  int visitCount(String id) => visitsByLead[id]?.length ?? 0;

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

// ── Builder ─────────────────────────────────────────────────────────────────

class ManagementBiMetrics {
  static ManagementBiSnapshot build({
    required List<LandLead> leads,
    ManagementBiActivityBundle activity = ManagementBiActivityBundle.empty,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final index = _ActivityIndex.from(activity);

    return ManagementBiSnapshot(
      pipeline: _pipeline(leads),
      funnel: _funnel(leads, index),
      ageing: _ageing(leads, clock),
      bottlenecks: _bottlenecks(leads, index, clock),
      executives: _executives(leads, index, clock),
      heatmap: _heatmap(leads, index, clock),
      sla: _sla(leads, index, clock),
    );
  }

  static BiPipelineSummary _pipeline(List<LandLead> leads) {
    var totalAcres = 0.0;
    var pipelineAcres = 0.0;
    var active = 0;
    var closed = 0;
    for (final l in leads) {
      final acres = biLeadAcres(l);
      totalAcres += acres;
      if (l.status == LeadStatus.signed) {
        closed++;
      } else if (l.status != LeadStatus.dropped) {
        active++;
        pipelineAcres += acres;
      }
    }
    return BiPipelineSummary(
      totalLeads: leads.length,
      totalAcres: totalAcres,
      pipelineAcres: pipelineAcres,
      activeDeals: active,
      closedDeals: closed,
    );
  }

  /// Assign each lead to exactly one funnel stage (mutually exclusive).
  static BiFunnelStage _stageFor(LandLead lead, _ActivityIndex index) {
    switch (lead.status) {
      case LeadStatus.dropped:
        return BiFunnelStage.dropped;
      case LeadStatus.onHold:
        // Classify by whichever stage it was paused from, so a paused deal
        // still shows up where it actually sits in the funnel rather than
        // vanishing into an unclassified bucket. Falls back to the earliest
        // stage if that wasn't recorded (e.g. legacy rows).
        final previous = lead.onHoldPreviousStatus;
        if (previous == null || previous == LeadStatus.onHold) {
          return BiFunnelStage.newLead;
        }
        return _stageFor(lead.copyWith(status: previous), index);
      case LeadStatus.signed:
        return BiFunnelStage.closed;
      case LeadStatus.legal:
        // Agreement = legal with deal terms filled; else Legal.
        final deal = lead.accessDetails.trim();
        if (deal.isNotEmpty) return BiFunnelStage.agreement;
        return BiFunnelStage.legal;
      case LeadStatus.negotiation:
        return BiFunnelStage.negotiation;
      case LeadStatus.managementMeetingCompleted:
        return BiFunnelStage.managementMeeting;
      case LeadStatus.prospectMeetingCompleted:
        if (index.hasVisit(lead.leadId)) return BiFunnelStage.siteVisit;
        return BiFunnelStage.meeting;
      case LeadStatus.prospectMeetingPending:
        if (index.hasVisit(lead.leadId)) return BiFunnelStage.siteVisit;
        if (index.hasMeeting(lead.leadId)) return BiFunnelStage.meeting;
        if (lead.contactDetails.trim().isNotEmpty) {
          return BiFunnelStage.contacted;
        }
        return BiFunnelStage.newLead;
    }
  }

  static List<BiFunnelStageRow> _funnel(
    List<LandLead> leads,
    _ActivityIndex index,
  ) {
    final buckets = {for (final s in BiFunnelStage.values) s: <LandLead>[]};
    for (final l in leads) {
      buckets[_stageFor(l, index)]!.add(l);
    }

    // Ordered path excluding dropped for conversion chain.
    const path = [
      BiFunnelStage.newLead,
      BiFunnelStage.contacted,
      BiFunnelStage.meeting,
      BiFunnelStage.managementMeeting,
      BiFunnelStage.siteVisit,
      BiFunnelStage.negotiation,
      BiFunnelStage.legal,
      BiFunnelStage.agreement,
      BiFunnelStage.closed,
    ];

    // Cumulative "reached or past this stage" for conversion %.
    final stageRank = {
      for (var i = 0; i < path.length; i++) path[i]: i,
    };
    stageRank[BiFunnelStage.dropped] = -1;

    int rankOf(LandLead l) => stageRank[_stageFor(l, index)] ?? -1;

    final totalNonDropped =
        leads.where((l) => l.status != LeadStatus.dropped).length;

    final rows = <BiFunnelStageRow>[];
    for (var i = 0; i < path.length; i++) {
      final stage = path[i];
      final inStage = buckets[stage]!;
      final acres = inStage.fold<double>(0, (s, l) => s + biLeadAcres(l));
      final reachedOrPast =
          leads.where((l) => rankOf(l) >= i).length;
      final conversionPct = totalNonDropped == 0
          ? 0.0
          : (reachedOrPast / totalNonDropped) * 100;

      double dropOffPct = 0;
      if (i > 0) {
        final prevReached =
            leads.where((l) => rankOf(l) >= i - 1).length;
        final currReached = reachedOrPast;
        dropOffPct = prevReached == 0
            ? 0
            : ((prevReached - currReached) / prevReached) * 100;
      }

      rows.add(BiFunnelStageRow(
        stage: stage,
        leadCount: inStage.length,
        acres: acres,
        conversionPct: conversionPct,
        dropOffPct: dropOffPct.clamp(0, 100),
      ));
    }

    final dropped = buckets[BiFunnelStage.dropped]!;
    rows.add(BiFunnelStageRow(
      stage: BiFunnelStage.dropped,
      leadCount: dropped.length,
      acres: dropped.fold(0, (s, l) => s + biLeadAcres(l)),
      conversionPct: leads.isEmpty
          ? 0
          : (dropped.length / leads.length) * 100,
      dropOffPct: leads.isEmpty
          ? 0
          : (dropped.length / leads.length) * 100,
    ));

    return rows;
  }

  static List<BiAgeBucketRow> _ageing(List<LandLead> leads, DateTime now) {
    final active = leads
        .where((l) => l.status != LeadStatus.signed && l.status != LeadStatus.dropped)
        .toList();
    final map = {
      BiAgeBucket.d0to30: <LandLead>[],
      BiAgeBucket.d31to60: <LandLead>[],
      BiAgeBucket.d61to90: <LandLead>[],
      BiAgeBucket.d90plus: <LandLead>[],
    };
    for (final l in active) {
      final age = biLeadAgeDays(l, now);
      map[BiAgeBucketX.forAgeDays(age)]!.add(l);
    }
    return [
      for (final b in BiAgeBucket.values)
        BiAgeBucketRow(
          bucket: b,
          leadCount: map[b]!.length,
          acres: map[b]!.fold(0, (s, l) => s + biLeadAcres(l)),
          leads: map[b]!,
        ),
    ];
  }

  static List<BiBottleneckRow> _bottlenecks(
    List<LandLead> leads,
    _ActivityIndex index,
    DateTime now,
  ) {
    double avgDays(List<LandLead> list) {
      if (list.isEmpty) return 0;
      final sum = list.fold<int>(0, (s, l) => s + biLeadAgeDays(l, now));
      return sum / list.length;
    }

    final legalPending =
        leads.where((l) => l.status == LeadStatus.legal).toList();

    final ownerApproval = <LandLead>[];
    final pendingVisitLeadIds = <String>{};
    for (final v in index.visitsByLead.entries) {
      for (final visit in v.value) {
        if (visit.needsApproval) pendingVisitLeadIds.add(v.key);
      }
    }
    for (final l in leads) {
      if (pendingVisitLeadIds.contains(l.leadId)) ownerApproval.add(l);
    }

    final documentPending = leads
        .where((l) =>
            l.status == LeadStatus.legal && l.accessDetails.trim().isEmpty)
        .toList();

    return [
      BiBottleneckRow(
        id: 'legal',
        label: 'Legal Pending',
        count: legalPending.length,
        avgPendingDays: avgDays(legalPending),
        leads: legalPending,
      ),
      BiBottleneckRow(
        id: 'owner',
        label: 'Owner Approval Pending',
        count: ownerApproval.length,
        avgPendingDays: avgDays(ownerApproval),
        leads: ownerApproval,
      ),
      BiBottleneckRow(
        id: 'document',
        label: 'Document Pending',
        count: documentPending.length,
        avgPendingDays: avgDays(documentPending),
        leads: documentPending,
      ),
    ];
  }

  static List<BiExecutiveRow> _executives(
    List<LandLead> leads,
    _ActivityIndex index,
    DateTime now,
  ) {
    final byName = <String, List<LandLead>>{};
    for (final l in leads) {
      final name = l.createdByName.trim();
      if (name.isEmpty || name.toLowerCase() == 'management') continue;
      (byName[name] ??= []).add(l);
    }

    final rows = <BiExecutiveRow>[];
    for (final entry in byName.entries) {
      final mine = entry.value;
      final converted =
          mine.where((l) => l.status == LeadStatus.signed).toList();
      final pipelineAcres = mine
          .where((l) => l.status.isActive)
          .fold<double>(0, (s, l) => s + biLeadAcres(l));
      final conversion =
          mine.isEmpty ? 0.0 : (converted.length / mine.length) * 100;

      var closingSum = 0.0;
      for (final l in converted) {
        closingSum += biLeadAgeDays(l, now).toDouble();
      }
      final avgClose =
          converted.isEmpty ? 0.0 : closingSum / converted.length;

      var meetings = 0;
      var visits = 0;
      for (final l in mine) {
        meetings += index.meetingCount(l.leadId);
        visits += index.visitCount(l.leadId);
      }

      final legalCount =
          mine.where((l) => l.status == LeadStatus.legal).length;
      final agreementSuccess = converted.length;

      rows.add(BiExecutiveRow(
        name: entry.key,
        assignedLeads: mine.length,
        convertedLeads: converted.length,
        pipelineAcres: pipelineAcres,
        conversionPct: conversion,
        avgClosingDays: avgClose,
        meetings: meetings,
        siteVisits: visits,
        legalCount: legalCount,
        agreementSuccess: agreementSuccess,
        rank: 0,
      ));
    }

    // Rank by conversion then volume.
    rows.sort((a, b) {
      final c = b.conversionPct.compareTo(a.conversionPct);
      if (c != 0) return c;
      return b.convertedLeads.compareTo(a.convertedLeads);
    });

    return [
      for (var i = 0; i < rows.length; i++)
        BiExecutiveRow(
          name: rows[i].name,
          assignedLeads: rows[i].assignedLeads,
          convertedLeads: rows[i].convertedLeads,
          pipelineAcres: rows[i].pipelineAcres,
          conversionPct: rows[i].conversionPct,
          avgClosingDays: rows[i].avgClosingDays,
          meetings: rows[i].meetings,
          siteVisits: rows[i].siteVisits,
          legalCount: rows[i].legalCount,
          agreementSuccess: rows[i].agreementSuccess,
          rank: i + 1,
        ),
    ];
  }

  static List<BiVillageHeatRow> _heatmap(
    List<LandLead> leads,
    _ActivityIndex index,
    DateTime now,
  ) {
    final groups = <String, List<LandLead>>{};
    for (final l in leads) {
      final village = l.village.trim().isNotEmpty
          ? l.village.trim()
          : (l.location.trim().isNotEmpty ? l.location.trim() : 'Unknown');
      final district = l.district.trim();
      final key = '$village|$district';
      (groups[key] ??= []).add(l);
    }

    final rows = <BiVillageHeatRow>[];
    for (final entry in groups.entries) {
      final parts = entry.key.split('|');
      final village = parts.first;
      final district = parts.length > 1 ? parts[1] : '';
      var latest = DateTime.fromMillisecondsSinceEpoch(0);
      for (final l in entry.value) {
        if (l.addedOn.isAfter(latest)) latest = l.addedOn;
        final act = index.latestActivity(l.leadId);
        if (act != null && act.isAfter(latest)) latest = act;
      }
      final days = now.difference(latest).inDays;
      final level = days <= 7
          ? BiHeatLevel.active
          : days <= 30
              ? BiHeatLevel.moderate
              : BiHeatLevel.idle;
      rows.add(BiVillageHeatRow(
        village: village,
        district: district,
        leadCount: entry.value.length,
        level: level,
        daysSinceActivity: days.clamp(0, 9999),
      ));
    }

    rows.sort((a, b) {
      final lc = a.level.index.compareTo(b.level.index);
      if (lc != 0) return lc;
      return b.leadCount.compareTo(a.leadCount);
    });
    return rows;
  }

  static BiSlaSummary _sla(
    List<LandLead> leads,
    _ActivityIndex index,
    DateTime now,
  ) {
    final items = <BiSlaItem>[];

    void addIfOpen({
      required BiSlaKind kind,
      required LandLead lead,
      required bool resolved,
    }) {
      if (resolved) return;
      if (lead.status == LeadStatus.signed ||
          lead.status == LeadStatus.dropped) {
        return;
      }
      final age = biLeadAgeDays(lead, now);
      final target = kind.targetDays;
      final remaining = target - age;
      final urgency = remaining < 0
          ? BiSlaUrgency.overdue
          : remaining == 0
              ? BiSlaUrgency.dueToday
              : BiSlaUrgency.upcoming;
      // Cap upcoming to within 7 days of deadline to keep the list useful.
      if (urgency == BiSlaUrgency.upcoming && remaining > 7) return;
      items.add(BiSlaItem(
        kind: kind,
        lead: lead,
        urgency: urgency,
        ageDays: age,
        daysRemaining: remaining,
      ));
    }

    for (final l in leads) {
      addIfOpen(
        kind: BiSlaKind.siteVisit,
        lead: l,
        resolved: index.hasVisit(l.leadId) ||
            l.status == LeadStatus.negotiation ||
            l.status == LeadStatus.legal,
      );
      addIfOpen(
        kind: BiSlaKind.survey,
        lead: l,
        resolved: l.surveyNumber.trim().isNotEmpty ||
            l.status == LeadStatus.legal ||
            !(l.status == LeadStatus.negotiation),
      );
      addIfOpen(
        kind: BiSlaKind.legal,
        lead: l,
        resolved: l.status != LeadStatus.legal,
      );
      addIfOpen(
        kind: BiSlaKind.agreement,
        lead: l,
        resolved: l.status != LeadStatus.legal ||
            l.accessDetails.trim().isNotEmpty,
      );
    }

    return BiSlaSummary(
      dueToday:
          items.where((i) => i.urgency == BiSlaUrgency.dueToday).toList(),
      upcoming:
          items.where((i) => i.urgency == BiSlaUrgency.upcoming).toList(),
      overdue:
          items.where((i) => i.urgency == BiSlaUrgency.overdue).toList(),
    );
  }
}
