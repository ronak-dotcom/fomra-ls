import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/land_lead_meeting.dart';
import '../screens/land_lead/meeting_log_dialog.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';

/// Colour for a land's meeting status: owner green, agreement holder blue,
/// relatives / others amber, none grey (null — the caller uses a neutral).
Color? landMeetingStatusColor(LandMeetingStatus s) => switch (s) {
      LandMeetingStatus.ownerMet => AppColors.success,
      LandMeetingStatus.agreementHolderMet => AppColors.info,
      LandMeetingStatus.othersMet => AppColors.warning,
      LandMeetingStatus.none => null,
    };

/// Lead page: who we have met on this land, at a glance. A headline
/// (Land Owner met / only Agreement Holder / only relatives / no meeting yet)
/// and every meeting, newest first, with who attended, when and by whom.
class WhoWeMetCard extends StatefulWidget {
  final List<LandLeadMeeting> meetings;

  /// Opens the full meeting history.
  final VoidCallback? onOpen;

  /// Meetings listed before "+N more".
  final int maxRows;

  /// Phones: start as one line (the headline); tap to show the meetings.
  final bool collapsible;

  const WhoWeMetCard({
    super.key,
    required this.meetings,
    this.onOpen,
    this.maxRows = 4,
    this.collapsible = false,
  });

  @override
  State<WhoWeMetCard> createState() => _WhoWeMetCardState();
}

class _WhoWeMetCardState extends State<WhoWeMetCard> {
  static final _date = DateFormat('d MMM yyyy');
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final meetings = widget.meetings;
    final onOpen = widget.onOpen;
    final maxRows = widget.maxRows;
    final collapsed = widget.collapsible && !_expanded;
    final status = LandMeetingStatusX.of(meetings);
    final color = landMeetingStatusColor(status) ?? context.fomraTextTertiary;
    final sorted = [...meetings]..sort((a, b) => b.metAt.compareTo(a.metAt));
    final (icon, headline, hint) = switch (status) {
      LandMeetingStatus.ownerMet => (
          Icons.verified_rounded,
          'Land Owner met',
          null,
        ),
      LandMeetingStatus.agreementHolderMet => (
          Icons.warning_amber_rounded,
          'Owner not met yet',
          'Only the agreement holder / PoA was met — the land owner meeting '
              'is still pending.',
        ),
      LandMeetingStatus.othersMet => (
          Icons.warning_amber_rounded,
          'Owner not met yet',
          'Only relatives / others were met — the land owner meeting is '
              'still pending.',
        ),
      LandMeetingStatus.none => (
          Icons.event_busy_outlined,
          'No meeting yet',
          'No land owner meeting has been logged on this land.',
        ),
    };
    // Agreement holder alone is still "owner not met": amber headline, the
    // agreement holder shows as a blue pill in the rows below.
    final tone = status == LandMeetingStatus.agreementHolderMet
        ? AppColors.warning
        : color;

    return Material(
      color: tone.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: meetings.isEmpty
            ? null
            : widget.collapsible
                ? () => setState(() => _expanded = !_expanded)
                : onOpen,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tone.withValues(alpha: 0.35), width: 1.4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    meetings.isEmpty
                        ? 'WHO WE MET'
                        : 'WHO WE MET · ${meetings.length} '
                            'MEETING${meetings.length == 1 ? '' : 'S'}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: context.fomraTextTertiary,
                    ),
                  ),
                ),
                if (meetings.isNotEmpty && (onOpen != null || widget.collapsible))
                  Icon(
                      widget.collapsible
                          ? (_expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded)
                          : Icons.chevron_right_rounded,
                      size: 20,
                      color: context.fomraTextTertiary),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Icon(icon, size: 20, color: tone),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    headline,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: tone,
                    ),
                  ),
                ),
              ]),
              if (!collapsed)
              for (final m in sorted.take(maxRows)) ...[
                const SizedBox(height: 8),
                _MeetingRow(meeting: m, date: _date.format(m.metAt)),
              ],
              if (!collapsed && sorted.length > maxRows)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '+${sorted.length - maxRows} earlier meeting'
                    '${sorted.length - maxRows == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: context.fomraTextSecondary,
                    ),
                  ),
                ),
              if (!collapsed && widget.collapsible && onOpen != null &&
                  meetings.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.history_rounded, size: 16),
                    label: const Text('Meeting history'),
                  ),
                ),
              if (!collapsed && hint != null) ...[
                const SizedBox(height: 8),
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: context.fomraTextSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MeetingRow extends StatelessWidget {
  final LandLeadMeeting meeting;
  final String date;
  const _MeetingRow({required this.meeting, required this.date});

  @override
  Widget build(BuildContext context) {
    final m = meeting;
    // Named people when recorded ("Ravi — Son"); otherwise the ticked types.
    final pills = <Widget>[
      if (m.peopleMet.isNotEmpty)
        for (final p in m.peopleMet)
          _Pill(
            text: p.label,
            color: meetingAttendeeColor(PersonMet.attendeeTypeFor(p.relation)),
          )
      else
        for (final t in m.attendeeTypes)
          _Pill(
            text: MeetingAttendeeTypes.short(t),
            color: meetingAttendeeColor(t),
          ),
    ];
    final meta = [
      date,
      if (m.loggedByName.trim().isNotEmpty) m.loggedByName.trim(),
      if (m.managementPresent) 'Management present',
    ].join(' · ');
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...pills,
        Text(
          meta,
          style: TextStyle(fontSize: 13, color: context.fomraTextSecondary),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );
}
