import '../models/land_lead.dart';
import '../models/land_lead_meeting.dart';
import '../services/broker_directory.dart';
import '../utils/lead_location_parser.dart';
import '../widgets/terms_deal_selector.dart';

/// Active sites that have gone quiet: nothing on the calendar ahead and no Land
/// Owner Meeting for [staleDays] days.
///
/// A lead counts as stalled when it has no Land Owner Meeting scheduled in the
/// future AND its most recent meeting was over [staleDays] days ago — for a lead
/// that never had one, the clock runs from when it was added. Signed and Dropped
/// leads are excluded, since [LeadStatusX.isActive] already covers both.
abstract final class NoFutureActivityAnalytics {
  static const staleDays = 60;

  static List<LandLead> select(
    List<LandLead> leads,
    List<LandLeadMeeting> meetings, {
    int days = staleDays,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final cutoff = at.subtract(Duration(days: days));

    final byLead = <String, List<LandLeadMeeting>>{};
    for (final m in meetings) {
      (byLead[m.leadId] ??= []).add(m);
    }

    return leads.where((lead) {
      if (!lead.status.isActive) return false;
      final own = byLead[lead.leadId] ?? const <LandLeadMeeting>[];
      // Anything booked ahead means the site does have future activity.
      if (own.any((m) => m.metAt.toLocal().isAfter(at))) return false;
      final lastMeeting = own.isEmpty
          ? null
          : own
              .map((m) => m.metAt.toLocal())
              .reduce((a, b) => a.isAfter(b) ? a : b);
      return (lastMeeting ?? lead.addedOn.toLocal()).isBefore(cutoff);
    }).toList();
  }
}

class BrokerPerformanceRow {
  /// What the broker is grouped by — their mobile number (see
  /// BrokerDirectory.keyFor). Use this, not [name], to find their leads.
  final String key;
  final String name;
  final String contact;
  final int leads;
  final int conversions;
  final int active;
  final double successRate;

  const BrokerPerformanceRow({
    this.key = '',
    required this.name,
    required this.contact,
    required this.leads,
    required this.conversions,
    required this.active,
    required this.successRate,
  });
}

abstract final class BrokerPerformanceAnalytics {
  static List<BrokerPerformanceRow> compute(List<LandLead> leads) {
    // Grouped by mobile number, shown under the directory's name, so one
    // broker typed two ways still counts as one.
    final dir = BrokerDirectory.instance;
    final map = <String, List<LandLead>>{};
    for (final l in leads) {
      if (l.brokerName.trim().isEmpty) continue;
      (map[BrokerDirectory.keyFor(l)] ??= []).add(l);
    }
    final rows = map.entries.map((e) {
      final list = e.value;
      final conversions = list.where((l) => l.status.isAcquired).length;
      final active = list.where((l) => l.status.isActive).length;
      final contact = list
          .map((l) => l.brokerContact.trim())
          .firstWhere((c) => c.isNotEmpty, orElse: () => '');
      return BrokerPerformanceRow(
        key: e.key,
        name: dir.nameFor(list.first),
        contact: contact,
        leads: list.length,
        conversions: conversions,
        active: active,
        successRate: list.isEmpty ? 0 : (conversions / list.length) * 100,
      );
    }).toList()
      ..sort((a, b) => b.leads.compareTo(a.leads));
    return rows;
  }
}

class AcquisitionCostResult {
  final double acres;
  final double? totalCost;
  final double? costPerAcre;
  final String source;

  const AcquisitionCostResult({
    required this.acres,
    required this.totalCost,
    required this.costPerAcre,
    required this.source,
  });
}

abstract final class AcquisitionCostCalculator {
  /// Parse ₹ amounts from free text (commas, L/Cr suffixes).
  static double? parseMoney(String raw) {
    var t = raw.trim().toLowerCase().replaceAll(',', '');
    if (t.isEmpty) return null;
    t = t.replaceAll(RegExp(r'[₹rs\.\s]'), '');
    var mult = 1.0;
    if (t.endsWith('cr') || t.endsWith('crore')) {
      mult = 10000000;
      t = t.replaceAll(RegExp(r'crore|cr'), '');
    } else if (t.endsWith('l') || t.endsWith('lac') || t.endsWith('lakh')) {
      mult = 100000;
      t = t.replaceAll(RegExp(r'lakh|lac|l'), '');
    }
    final n = double.tryParse(t);
    if (n == null) return null;
    return n * mult;
  }

  static double acresFromLead(LandLead lead) {
    final sqft = parseLandExtentSqft(lead.landExtent);
    if (sqft == null || sqft <= 0) return 0;
    return sqft / 43560;
  }

  static double? totalCostFromLead(LandLead lead) {
    final parsed = parseTermsDeal(lead.accessDetails);
    for (final dealFields in parsed.fields.values) {
      final raw = dealFields['total_land_cost'];
      if (raw != null && raw.trim().isNotEmpty) {
        final v = parseMoney(raw);
        if (v != null) return v;
      }
    }
    // Fallback: scan accessDetails lines for Total Land Cost.
    for (final line in lead.accessDetails.split('\n')) {
      if (line.toLowerCase().contains('total land cost')) {
        final colon = line.indexOf(':');
        if (colon > 0) {
          final v = parseMoney(line.substring(colon + 1));
          if (v != null) return v;
        }
      }
    }
    return null;
  }

  static AcquisitionCostResult fromLead(LandLead lead) {
    final acres = acresFromLead(lead);
    final total = totalCostFromLead(lead);
    final perAcre =
        (total != null && acres > 0) ? total / acres : null;
    return AcquisitionCostResult(
      acres: acres,
      totalCost: total,
      costPerAcre: perAcre,
      source: total != null ? 'Deal terms' : 'Extent only',
    );
  }

  static AcquisitionCostResult fromInputs({
    required double acres,
    required double totalCost,
  }) {
    return AcquisitionCostResult(
      acres: acres,
      totalCost: totalCost,
      costPerAcre: acres > 0 ? totalCost / acres : null,
      source: 'Manual',
    );
  }
}
