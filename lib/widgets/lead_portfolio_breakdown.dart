import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../analytics/management_bi_metrics.dart';
import '../models/land_lead.dart';
import '../models/land_lead_meeting.dart';
import 'who_we_met_card.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';
import '../utils/lead_location_parser.dart';

/// Acres for a lead parsed from its land extent (0 when unparseable).
double leadPortfolioAcres(LandLead lead) {
  final sqft = parseLandExtentSqft(lead.landExtent);
  if (sqft == null || sqft <= 0) return 0;
  return sqft / 43560;
}

/// Portfolio breakdown for an owner or broker: summary cards + a full table of
/// every linked lead. Pure presentation — no business logic or data mutation.
class LeadPortfolioBreakdown extends StatelessWidget {
  final List<LandLead> leads;
  final ValueChanged<LandLead> onOpenLead;

  /// When set, the "Dropped Leads" summary card is replaced with a
  /// "Meetings Conducted" card showing this count instead.
  final int? meetingsConducted;

  /// When true, the table's last column shows a Lead Age bucket
  /// (0-30/31-60/61-90/90+ days) instead of the Active/Closed/Dropped status.
  final bool useLeadAgeColumn;

  /// When true, an Active/Closed/Dropped summary card is shown only if its
  /// count is > 0 — so a single-status owner sees just that one box, not all
  /// three empty ones.
  final bool hideEmptyStatusCards;

  /// Total Land Owner Meetings conducted across [leads]. Shown as an extra
  /// "Meetings Conducted" card *beside* Dropped Leads (not instead of it)
  /// whenever provided.
  final int? meetingsBesideDropped;

  /// Broker view, counted per land (repeat meetings on one land count once):
  /// lands where we met the actual Land Owner, and lands with any meeting.
  /// Shown as "Owner Met: X of Y lands" and "Lands with Meetings" beside the
  /// status cards. Null while loading or when not a broker view.
  final ({int ownerMet, int withMeeting})? landMeetings;

  /// Broker view: who was met on each land (by lead id). When given, the
  /// table gets a Meeting column, rows are tinted by it (green owner ·
  /// blue agreement holder · amber relatives/others) and owner-met lands are
  /// listed first.
  final Map<String, LandMeetingStatus>? meetingStatus;

  const LeadPortfolioBreakdown({
    super.key,
    required this.leads,
    required this.onOpenLead,
    this.meetingsConducted,
    this.useLeadAgeColumn = false,
    this.meetingsBesideDropped,
    this.hideEmptyStatusCards = false,
    this.landMeetings,
    this.meetingStatus,
  });

  @override
  Widget build(BuildContext context) {
    final ms = meetingStatus;
    LandMeetingStatus statusOf(LandLead l) =>
        ms?[l.leadId] ?? LandMeetingStatus.none;
    final sorted = [...leads]..sort((a, b) {
        if (ms != null) {
          final byMeeting = statusOf(a).rank.compareTo(statusOf(b).rank);
          if (byMeeting != 0) return byMeeting;
        }
        return b.addedOn.compareTo(a.addedOn);
      });
    final total = sorted.length;
    final totalAcres =
        sorted.fold<double>(0, (s, l) => s + leadPortfolioAcres(l));
    final active = sorted.where((l) => l.status.isActive).length;
    final closed = sorted.where((l) => l.status.isAcquired).length;
    final dropped = sorted.where((l) => l.status.isDropped).length;
    final df = DateFormat('dd MMM yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SummaryCard(
              label: 'Total Properties',
              value: '$total',
              icon: Icons.home_work_outlined,
              color: AppColors.primary,
            ),
            _SummaryCard(
              label: 'Total Acres',
              value: totalAcres.toStringAsFixed(2),
              icon: Icons.crop_square_outlined,
              color: AppColors.info,
            ),
            if (!hideEmptyStatusCards || active > 0)
              _SummaryCard(
                label: 'Active Leads',
                value: '$active',
                icon: Icons.trending_up_rounded,
                color: AppColors.warning,
              ),
            if (!hideEmptyStatusCards || closed > 0)
              _SummaryCard(
                label: 'Closed Leads',
                value: '$closed',
                icon: Icons.verified_outlined,
                color: AppColors.success,
              ),
            if (landMeetings case final lm?) ...[
              _SummaryCard(
                label: 'Owner Met',
                value: '${lm.ownerMet} of $total',
                icon: Icons.handshake_outlined,
                color: AppColors.success,
              ),
              _SummaryCard(
                label: 'Any Meeting (incl. Agreement Holder / relatives)',
                value: '${lm.withMeeting}',
                icon: Icons.groups_outlined,
                color: AppColors.secondary,
              ),
            ],
            if (meetingsConducted != null)
              _SummaryCard(
                label: 'Meetings Conducted',
                value: '$meetingsConducted',
                icon: Icons.groups_outlined,
                color: AppColors.secondary,
              )
            else ...[
              if (!hideEmptyStatusCards || dropped > 0)
                _SummaryCard(
                  label: 'Dropped Leads',
                  value: '$dropped',
                  icon: Icons.cancel_outlined,
                  color: AppColors.error,
                ),
              if (meetingsBesideDropped != null)
                _SummaryCard(
                  label: 'Meetings Conducted',
                  value: '$meetingsBesideDropped',
                  icon: Icons.groups_outlined,
                  color: AppColors.secondary,
                ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 42,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 52,
            columnSpacing: 22,
            headingTextStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: context.fomraTextSecondary,
            ),
            dataTextStyle: TextStyle(
              fontSize: 12.5,
              color: context.fomraTextPrimary,
            ),
            columns: [
              const DataColumn(label: Text('Lead ID')),
              const DataColumn(label: Text('Property')),
              const DataColumn(label: Text('Village')),
              if (ms != null) const DataColumn(label: Text('Meeting')),
              const DataColumn(label: Text('Survey No.')),
              const DataColumn(label: Text('Acres')),
              const DataColumn(label: Text('Current Stage')),
              const DataColumn(label: Text('Assigned Executive')),
              const DataColumn(label: Text('Last Activity')),
              DataColumn(label: Text(useLeadAgeColumn ? 'Lead Age' : 'Status')),
            ],
            rows: [
              for (final l in sorted)
                DataRow(
                  // Tinted by who was met, so met lands stand out.
                  color: ms == null
                      ? null
                      : WidgetStatePropertyAll(
                          landMeetingStatusColor(statusOf(l))
                              ?.withValues(alpha: 0.07)),
                  cells: [
                    DataCell(
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        if (ms != null) ...[
                          Container(
                            width: 4,
                            height: 30,
                            decoration: BoxDecoration(
                              color: landMeetingStatusColor(statusOf(l)) ??
                                  Colors.transparent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        InkWell(
                          onTap: () => onOpenLead(l),
                          child: Text(
                            '#${l.leadId}',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ]),
                    ),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Text(
                          _propertyLabel(l),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(_value(l.village))),
                    if (ms != null)
                      DataCell(_MeetingPill(status: statusOf(l))),
                    DataCell(Text(_value(l.surveyNumber))),
                    DataCell(Text(leadPortfolioAcres(l).toStringAsFixed(2))),
                    DataCell(Text(l.status.label)),
                    DataCell(Text(_value(l.createdByName))),
                    DataCell(Text(df.format(l.addedOn))),
                    DataCell(useLeadAgeColumn
                        ? _LeadAgePill(lead: l)
                        : _StatusPill(status: l.status)),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _value(String raw) => raw.trim().isEmpty ? '—' : raw.trim();

  /// A meaningful property identifier so every lead row is recognisable even
  /// when the free-text location is blank.
  static String _propertyLabel(LandLead l) {
    if (l.location.trim().isNotEmpty) return l.location.trim();
    final parts = <String>[
      if (l.surveyNumber.trim().isNotEmpty) 'Survey ${l.surveyNumber.trim()}',
      if (l.village.trim().isNotEmpty) l.village.trim(),
    ];
    if (parts.isNotEmpty) return parts.join(' · ');
    if (l.taluk.trim().isNotEmpty) return l.taluk.trim();
    if (l.district.trim().isNotEmpty) return l.district.trim();
    return 'Lead #${l.leadId}';
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: context.fomraTextSecondary),
          ),
        ],
      ),
    );
  }
}

class _MeetingPill extends StatelessWidget {
  final LandMeetingStatus status;
  const _MeetingPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = landMeetingStatusColor(status) ?? context.fomraTextTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status == LandMeetingStatus.none
            ? context.fomraSurfaceVar
            : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (status == LandMeetingStatus.ownerMet) ...[
          Icon(Icons.check_circle_rounded, size: 13, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          status.badge,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ]),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final LeadStatus status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = status.isAcquired
        ? ('Closed', AppColors.success)
        : status.isDropped
            ? ('Dropped', AppColors.error)
            : ('Active', AppColors.warning);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _LeadAgePill extends StatelessWidget {
  final LandLead lead;

  const _LeadAgePill({required this.lead});

  @override
  Widget build(BuildContext context) {
    final bucket = BiAgeBucketX.forAgeDays(biLeadAgeDays(lead));
    final color = bucket.isOverdue ? AppColors.error : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        bucket.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
