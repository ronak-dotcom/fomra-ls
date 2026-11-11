import 'package:flutter/material.dart';

import '../models/land_lead.dart';
import '../services/broker_directory.dart';
import '../theme/app_theme.dart';

/// How much a broker's lands turn into real land owner meetings.
///
/// - **Energiser** (Energy Giver) — meetings with the actual Land Owner on more than 60%
///   of the lands they gave.
/// - **Average** — 40% to 60%.
/// - **Low Yield** (was Energy Drainer) — under 40%: gives lands but mostly no owner meeting.
///
/// No minimum number of lands: a broker with one land is rated on that one.
enum BrokerEnergy { giver, average, drainer }

extension BrokerEnergyX on BrokerEnergy {
  String get label => switch (this) {
        BrokerEnergy.giver => 'Energiser',
        BrokerEnergy.average => 'Average',
        BrokerEnergy.drainer => 'Low Yield',
      };

  /// Group heading ("Energisers").
  String get plural => switch (this) {
        BrokerEnergy.giver => 'Energisers',
        BrokerEnergy.average => 'Average',
        BrokerEnergy.drainer => 'Low Yield',
      };

  String get rule => switch (this) {
        BrokerEnergy.giver => 'Owner meeting on more than 60% of lands',
        BrokerEnergy.average => 'Owner meeting on 40–60% of lands',
        BrokerEnergy.drainer => 'Owner meeting on under 40% of lands',
      };

  Color get color => switch (this) {
        BrokerEnergy.giver => AppColors.success,
        BrokerEnergy.average => AppColors.warning,
        BrokerEnergy.drainer => AppColors.error,
      };

  IconData get icon => switch (this) {
        BrokerEnergy.giver => Icons.bolt_rounded,
        BrokerEnergy.average => Icons.horizontal_rule_rounded,
        BrokerEnergy.drainer => Icons.battery_alert_rounded,
      };

  static BrokerEnergy ofRate(double meetingRate) {
    if (meetingRate > 60) return BrokerEnergy.giver;
    if (meetingRate >= 40) return BrokerEnergy.average;
    return BrokerEnergy.drainer;
  }
}

class BrokerEnergyRow {
  /// Mobile number the broker is grouped by (BrokerDirectory.keyFor).
  final String key;
  final String name;
  final int lands;

  /// Lands where we met the actual Land Owner (a converted land counts: it
  /// can't be signed without the owner).
  final int ownerMeetings;
  final int converted;
  final int dropped;
  final DateTime? lastLandOn;

  const BrokerEnergyRow({
    this.key = '',
    required this.name,
    required this.lands,
    required this.ownerMeetings,
    required this.converted,
    required this.dropped,
    required this.lastLandOn,
  });

  /// Share of lands with an owner meeting, 0–100.
  double get meetingRate => lands == 0 ? 0 : ownerMeetings / lands * 100;

  BrokerEnergy get energy => BrokerEnergyX.ofRate(meetingRate);

  /// Lands given with no owner meeting yet.
  int get withoutMeeting => lands - ownerMeetings;
}

abstract final class BrokerEnergyAnalytics {
  /// The Energiser / Low Yield rating is on recent form: lands given in the
  /// last 120 days. Lifetime figures are in Reports > Broker Report.
  static const windowDays = 120;

  /// Leads added within the last [windowDays] days of [now].
  static List<LandLead> recent(List<LandLead> leads, {DateTime? now}) {
    final from = (now ?? DateTime.now())
        .subtract(const Duration(days: windowDays));
    return [for (final l in leads) if (l.addedOn.isAfter(from)) l];
  }

  /// One row per broker (by [LandLead.brokerName], case-insensitive), ranked
  /// best first: meeting rate, then owner meetings, then lands given.
  /// [leadIdsWithOwnerMeeting] are the leads that had a Land Owner meeting.
  static List<BrokerEnergyRow> compute(
    List<LandLead> leads,
    Set<String> leadIdsWithOwnerMeeting,
  ) {
    // By mobile number, shown under the directory's name.
    final dir = BrokerDirectory.instance;
    final byBroker = <String, List<LandLead>>{};
    for (final l in leads) {
      if (l.brokerName.trim().isEmpty) continue;
      (byBroker[BrokerDirectory.keyFor(l)] ??= []).add(l);
    }
    final rows = [
      for (final e in byBroker.entries)
        BrokerEnergyRow(
          key: e.key,
          name: dir.nameFor(e.value.first),
          lands: e.value.length,
          ownerMeetings: e.value
              .where((l) =>
                  leadIdsWithOwnerMeeting.contains(l.leadId) ||
                  l.status.isAcquired)
              .length,
          converted: e.value.where((l) => l.status.isAcquired).length,
          dropped: e.value.where((l) => l.status == LeadStatus.dropped).length,
          lastLandOn: e.value
              .map((l) => l.addedOn)
              .reduce((a, b) => a.isAfter(b) ? a : b),
        ),
    ]..sort(compareRank);
    return rows;
  }

  static int compareRank(BrokerEnergyRow a, BrokerEnergyRow b) {
    final byRate = b.meetingRate.compareTo(a.meetingRate);
    if (byRate != 0) return byRate;
    final byMeetings = b.ownerMeetings.compareTo(a.ownerMeetings);
    if (byMeetings != 0) return byMeetings;
    return b.lands.compareTo(a.lands);
  }
}
