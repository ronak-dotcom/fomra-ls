import 'package:flutter/material.dart';

import '../analytics/broker_energy.dart';
import '../models/land_lead.dart';
import '../screens/broker/broker_management_screen.dart';
import '../services/land_lead_meeting_service.dart';
import '../theme/fomra_theme_context.dart';

/// Management Home card: who the Energisers and Drainers are among brokers,
/// by the share of their lands where we met the actual Land Owner. Each
/// heading opens the Broker page filtered to that group.
class BrokerEnergySummary extends StatefulWidget {
  final List<LandLead> leads;

  /// Names shown per group before "+N more".
  final int maxNames;

  const BrokerEnergySummary({super.key, required this.leads, this.maxNames = 5});

  @override
  State<BrokerEnergySummary> createState() => _BrokerEnergySummaryState();
}

class _BrokerEnergySummaryState extends State<BrokerEnergySummary> {
  Set<String>? _ownerMetIds;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ids = await LandLeadMeetingService.leadIdsWithLandOwnerMeeting();
      if (mounted) setState(() => _ownerMetIds = ids);
    } catch (_) {
      if (mounted) setState(() => _ownerMetIds = <String>{});
    }
  }

  void _open(BrokerEnergy? energy) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BrokerManagementScreen(initialEnergy: energy),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ids = _ownerMetIds;
    if (ids == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final rows = BrokerEnergyAnalytics.compute(widget.leads, ids);
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No broker leads yet.',
          style: TextStyle(fontSize: 13, color: context.fomraTextSecondary),
        ),
      );
    }
    List<BrokerEnergyRow> group(BrokerEnergy e) =>
        rows.where((r) => r.energy == e).toList();
    final givers = group(BrokerEnergy.giver);
    // Worst first: the lowest meeting share is the biggest drain.
    final drainers = group(BrokerEnergy.drainer).reversed.toList();
    final average = group(BrokerEnergy.average).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, c) {
          final giverCol = _GroupColumn(
            energy: BrokerEnergy.giver,
            rows: givers,
            maxNames: widget.maxNames,
            onOpen: () => _open(BrokerEnergy.giver),
          );
          final drainerCol = _GroupColumn(
            energy: BrokerEnergy.drainer,
            rows: drainers,
            maxNames: widget.maxNames,
            onOpen: () => _open(BrokerEnergy.drainer),
          );
          if (c.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [giverCol, const SizedBox(height: 10), drainerCol],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: giverCol),
                const SizedBox(width: 10),
                Expanded(child: drainerCol),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                average == 0
                    ? 'Rated on owner meetings: Energiser above 60%, '
                        'Drainer under 40%.'
                    : '$average average broker${average == 1 ? '' : 's'} '
                        '(40–60% owner meetings).',
                style: TextStyle(
                  fontSize: 12,
                  color: context.fomraTextSecondary,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _open(null),
              icon: const Icon(Icons.leaderboard_outlined, size: 16),
              label: const Text('Full ranking'),
            ),
          ],
        ),
      ],
    );
  }
}

class _GroupColumn extends StatelessWidget {
  final BrokerEnergy energy;
  final List<BrokerEnergyRow> rows;
  final int maxNames;
  final VoidCallback onOpen;

  const _GroupColumn({
    required this.energy,
    required this.rows,
    required this.maxNames,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final c = energy.color;
    final shown = rows.take(maxNames).toList();
    final more = rows.length - shown.length;
    return Material(
      color: c.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(energy.icon, size: 18, color: c),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    energy.plural,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: c,
                    ),
                  ),
                ),
                Text(
                  '${rows.length}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: c,
                  ),
                ),
              ]),
              Text(
                energy.rule,
                style: TextStyle(
                  fontSize: 11,
                  color: context.fomraTextSecondary,
                ),
              ),
              const SizedBox(height: 8),
              if (shown.isEmpty)
                Text(
                  'None right now',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.fomraTextTertiary,
                  ),
                ),
              for (final r in shown)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.fomraTextPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'met ${r.ownerMeetings}/${r.lands} · '
                      '${r.meetingRate.round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: c,
                      ),
                    ),
                  ]),
                ),
              if (more > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '+$more more',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
