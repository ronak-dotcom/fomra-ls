import 'package:flutter/material.dart';

import '../models/land_lead.dart';
import '../models/lead_follow_up.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';
import '../utils/employee_lead_next_action.dart';

IconData _actionIcon(EmployeeNextActionKind kind) => switch (kind) {
      EmployeeNextActionKind.callOwner => Icons.phone_in_talk_outlined,
      EmployeeNextActionKind.landOwnerMeeting => Icons.handshake_outlined,
      EmployeeNextActionKind.siteVisit => Icons.place_outlined,
      EmployeeNextActionKind.legalVerification => Icons.balance_outlined,
      EmployeeNextActionKind.managementSiteVisit => Icons.apartment_outlined,
      EmployeeNextActionKind.projectSigning => Icons.task_alt_rounded,
      EmployeeNextActionKind.none => Icons.check_circle_outline,
    };

/// Next-action + pending-task banners for employee lead detail.
class EmployeeLeadGuidanceBanners extends StatelessWidget {
  final EmployeeLeadWorkflowInsight insight;

  /// The follow-up to surface, or null when none is scheduled (empty state).
  final LeadFollowUp? nextFollowUp;

  /// Opens the follow-up dialog — tapping the Follow-up card, whether it shows a
  /// scheduled reminder or the "add follow-up" empty state.
  final VoidCallback? onFollowUp;
  final VoidCallback? onOpenTasks;
  final VoidCallback? onNextActionTap;

  const EmployeeLeadGuidanceBanners({
    super.key,
    required this.insight,
    this.nextFollowUp,
    this.onFollowUp,
    this.onOpenTasks,
    this.onNextActionTap,
  });

  @override
  Widget build(BuildContext context) {
    // Priority is derived from the lead's own pending tasks — reusing existing
    // data, not a new field: overdue → High, due today → Medium, else Normal.
    final tasks = insight.tasks;
    final ({String label, Color color})? priority = !insight.nextAction.isPending
        ? null
        : tasks.overdue > 0
            ? (label: 'High', color: AppColors.error)
            : tasks.dueToday > 0
                ? (label: 'Medium', color: AppColors.warning)
                : (label: 'Normal', color: AppColors.info);

    final nextAction = _NextActionBanner(
      action: insight.nextAction,
      stage: insight.stage,
      priority: priority,
      onTap: onNextActionTap,
    );
    final followUpCard = _FollowUpCard(followUp: nextFollowUp, onTap: onFollowUp);
    final tasksCard = _TasksCard(summary: insight.tasks, onTap: onOpenTasks);

    return LayoutBuilder(
      builder: (context, c) {
        // Three equal columns when wide: Next Action · Follow-up · Tasks.
        // Medium: Next Action on top, Follow-up beside Tasks. Narrow: stack.
        if (c.maxWidth >= 640) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: nextAction),
                const SizedBox(width: 10),
                Expanded(child: followUpCard),
                const SizedBox(width: 10),
                Expanded(child: tasksCard),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            nextAction,
            const SizedBox(height: 8),
            if (c.maxWidth >= 360)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: followUpCard),
                    const SizedBox(width: 8),
                    Expanded(child: tasksCard),
                  ],
                ),
              )
            else ...[
              followUpCard,
              const SizedBox(height: 8),
              tasksCard,
            ],
          ],
        );
      },
    );
  }
}

/// Shared header row for a guidance card: a tinted icon and a tiny caps title.
class _CardHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final Widget? trailing;

  const _CardHeader({
    required this.icon,
    required this.title,
    required this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(
          title,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: color,
          ),
        ),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

/// The one activity the executive has to do next, its stage and a derived
/// priority — kept to a compact height (title, short description, stage,
/// priority) so it sits neatly beside / above the lead summary.
class _NextActionBanner extends StatelessWidget {
  final EmployeeNextAction action;
  final LeadStatus stage;
  final ({String label, Color color})? priority;
  final VoidCallback? onTap;

  const _NextActionBanner({
    required this.action,
    required this.stage,
    this.priority,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = action.isPending ? stage.color : AppColors.success;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        // Nothing to open once the pipeline is done.
        onTap: action.isPending ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(
                icon: Icons.bolt_rounded,
                title: 'NEXT ACTION',
                color: accent,
                trailing: priority == null
                    ? null
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: priority!.color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.flag_rounded,
                                size: 11, color: priority!.color),
                            const SizedBox(width: 4),
                            Text(
                              priority!.label,
                              style: TextStyle(
                                color: priority!.color,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_actionIcon(action.kind), size: 17, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          action.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: context.fomraTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          action.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                            color: context.fomraTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Follow-up card — the lead's next scheduled follow-up (with its status), or
/// an "add follow-up" empty state. Taps open the follow-up dialog. Sits between
/// Next Action and Tasks, where Status & Timeline used to be.
class _FollowUpCard extends StatelessWidget {
  final LeadFollowUp? followUp;
  final VoidCallback? onTap;

  const _FollowUpCard({this.followUp, this.onTap});

  @override
  Widget build(BuildContext context) {
    final f = followUp;
    final status = f?.statusAt(DateTime.now());
    final accent = status?.color ?? AppColors.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: context.fomraSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.fomraBorder),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(
                icon: Icons.notifications_active_outlined,
                title: 'FOLLOW-UP',
                color: accent,
                trailing: onTap == null
                    ? null
                    : Icon(
                        f == null
                            ? Icons.add_rounded
                            : Icons.chevron_right_rounded,
                        size: 16,
                        color: context.fomraTextSecondary,
                      ),
              ),
              const SizedBox(height: 10),
              if (f == null) ...[
                Text(
                  'No follow-up scheduled',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: context.fomraTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap to add a follow-up reminder',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: context.fomraTextSecondary,
                  ),
                ),
              ] else ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status!.label,
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _StatPair(label: 'Scheduled', value: f.scheduledLabel),
                if (f.title.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _StatPair(label: 'About', value: f.title.trim()),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A small stacked label + value used inside the guidance cards.
class _StatPair extends StatelessWidget {
  final String label;
  final String value;
  const _StatPair({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _MicroLabel(label),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: context.fomraTextPrimary,
          ),
        ),
      ],
    );
  }
}

/// Tasks card — the lead's Due Today and Overdue counts; taps through to tasks.
class _TasksCard extends StatelessWidget {
  final EmployeePendingTaskSummary summary;
  final VoidCallback? onTap;

  const _TasksCard({required this.summary, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: context.fomraSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.fomraBorder),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(
                icon: Icons.check_circle_outline_rounded,
                title: 'TASKS',
                color: AppColors.primary,
                trailing: onTap == null
                    ? null
                    : Icon(Icons.chevron_right_rounded,
                        size: 16, color: context.fomraTextSecondary),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _TaskStat(
                      label: 'Due Today',
                      value: '${summary.dueToday}',
                      color: AppColors.warning,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TaskStat(
                      label: 'Overdue',
                      value: '${summary.overdue}',
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiny muted caps label used inside the Status & Time card.
class _MicroLabel extends StatelessWidget {
  final String text;
  const _MicroLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: context.fomraTextSecondary,
      ),
    );
  }
}

class _TaskStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _TaskStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 18,
                height: 1,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: context.fomraTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Expandable floating quick-action menu for employee lead detail.
class EmployeeLeadQuickFab extends StatefulWidget {
  final LandLead lead;
  final Future<void> Function(String scheme) onLaunchContact;
  final ValueChanged<String> onDetailAction;
  final ValueChanged<LandLead>? onLeadUpdated;
  final VoidCallback? onActivityChanged;

  const EmployeeLeadQuickFab({
    super.key,
    required this.lead,
    required this.onLaunchContact,
    required this.onDetailAction,
    this.onLeadUpdated,
    this.onActivityChanged,
  });

  @override
  State<EmployeeLeadQuickFab> createState() => _EmployeeLeadQuickFabState();
}

class _EmployeeLeadQuickFabState extends State<EmployeeLeadQuickFab>
    with SingleTickerProviderStateMixin {
  bool _open = false;
  bool _busy = false;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  Future<void> _run(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _open = false;
    });
    _c.reverse();
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final actions = <({IconData icon, String label, Color color, VoidCallback onTap})>[
      (
        icon: Icons.call_outlined,
        label: 'Call',
        color: AppColors.success,
        onTap: () => _run(() => widget.onLaunchContact('tel')),
      ),
      (
        icon: Icons.location_on_outlined,
        label: 'Visit',
        color: AppColors.primary,
        onTap: () => _run(() async {
          widget.onDetailAction('Site visit');
        }),
      ),
      (
        icon: Icons.chat_rounded,
        label: 'WhatsApp',
        color: const Color(0xFF25D366),
        onTap: () => _run(() => widget.onLaunchContact('https://wa.me')),
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_open)
          ...[
            for (var i = 0; i < actions.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FadeTransition(
                  opacity: _c,
                  child: ScaleTransition(
                    scale: _c,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Material(
                          color: context.fomraSurface,
                          elevation: 2,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: Text(
                              actions[i].label,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FloatingActionButton.small(
                          heroTag: 'lead_fab_${actions[i].label}',
                          backgroundColor: actions[i].color,
                          onPressed: actions[i].onTap,
                          child: Icon(actions[i].icon, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        FloatingActionButton(
          heroTag: 'lead_fab_main',
          onPressed: _busy ? null : _toggle,
          backgroundColor: AppColors.primary,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(_open ? Icons.close_rounded : Icons.bolt_rounded),
        ),
      ],
    );
  }
}
