import 'package:flutter/material.dart';

import '../models/land_lead.dart';
import '../theme/app_theme.dart';

/// How much a broker's lands turn into real land owner meetings.
///
/// - **Energy Giver** — meetings with the actual Land Owner on more than 60%
///   of the lands they gave.
/// - **Average** — 40% to 60%.
/// - **Energy Drainer** — under 40%: gives lands but mostly no owner meeting.
///
/// No minimum number of lands: a broker with one land is rated on that one.
enum BrokerEnergy { giver, average, drainer }

extension BrokerEnergyX on BrokerEnergy {
  String get label => switch (this) {
        BrokerEnergy.giver => 'Energy Giver',
        BrokerEnergy.average => 'Average',
        BrokerEnergy.drainer => 'Energy Drainer',
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
  final String name;
  final int lands;

  /// Lands where we met the actual Land Owner (a converted land counts: it
  /// can't be signed without the owner).
  final int ownerMeetings;
  final int converted;
  final int dropped;
  final DateTime? lastLandOn;

  const BrokerEnergyRow({
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
  /// One row per broker (by [LandLead.brokerName], case-insensitive), ranked
  /// best first: meeting rate, then owner meetings, then lands given.
  /// [leadIdsWithOwnerMeeting] are the leads that had a Land Owner meeting.
  static List<BrokerEnergyRow> compute(
    List<LandLead> leads,
    Set<String> leadIdsWithOwnerMeeting,
  ) {
    final byBroker = <String, List<LandLead>>{};
    for (final l in leads) {
      final name = l.brokerName.trim();
      if (name.isEmpty) continue;
      (byBroker[name.toLowerCase()] ??= []).add(l);
    }
    final rows = [
      for (final list in byBroker.values)
        BrokerEnergyRow(
          name: list.first.brokerName.trim(),
          lands: list.length,
          ownerMeetings: list
              .where((l) =>
                  leadIdsWithOwnerMeeting.contains(l.leadId) ||
                  l.status.isAcquired)
              .length,
          converted: list.where((l) => l.status.isAcquired).length,
          dropped: list.where((l) => l.status == LeadStatus.dropped).length,
          lastLandOn: list
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
