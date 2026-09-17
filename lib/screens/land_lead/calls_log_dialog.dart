import 'package:flutter/material.dart';
import '../../widgets/ui/app_components.dart';
import 'package:flutter/services.dart';

import '../../models/lead_call_log.dart';
import '../../services/app_store.dart';
import '../../services/lead_call_log_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/log_dialog_tabs.dart';
import '../../widgets/separate_date_time_fields.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/dialog_error_banner.dart';

class CallsLogDialog extends StatefulWidget {
  final String leadId;
  final String ownerName;
  final bool readOnly;

  const CallsLogDialog({
    super.key,
    required this.leadId,
    this.ownerName = '',
    this.readOnly = false,
  });

  @override
  State<CallsLogDialog> createState() => _CallsLogDialogState();
}

class _CallsLogDialogState extends State<CallsLogDialog> {
  int _tabIndex = 0;
  late DateTime _calledAt = DateTime.now();
  CallDirection _direction = CallDirection.outgoing;
  CallOutcome _outcome = CallOutcome.answered;
  bool _followUpRequired = false;
  // Defaulted to tomorrow so an enabled follow-up starts on a sensible date.
  late DateTime _followUpAt = DateTime.now().add(const Duration(days: 1));
  final _durationCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  bool _saving = false;
  bool _loading = true;
  String? _formError;
  List<LeadCallLog> _logs = [];

  @override
  void initState() {
    super.initState();
    if (widget.readOnly) _tabIndex = 1;
    _loadLogs();
  }

  @override
  void dispose() {
    _durationCtrl.dispose();
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    try {
      final logs = await LeadCallLogService.getForLead(widget.leadId);
      if (mounted) setState(() => _logs = logs);
    } catch (_) {
      // Table may not exist yet — form still works for first save attempt.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editDate() async {
    final updated = await pickLogDate(context, _calledAt);
    if (updated == null || !mounted) return;
    setState(() => _calledAt = updated);
  }

  Future<void> _editTime() async {
    final updated = await pickLogTime(context, _calledAt);
    if (updated == null || !mounted) return;
    setState(() => _calledAt = updated);
  }

  Future<void> _editFollowUpDate() async {
    final updated = await pickLogDate(context, _followUpAt);
    if (updated == null || !mounted) return;
    setState(() => _followUpAt = updated);
  }

  Future<void> _editFollowUpTime() async {
    final updated = await pickLogTime(context, _followUpAt);
    if (updated == null || !mounted) return;
    setState(() => _followUpAt = updated);
  }

  Future<void> _save() async {
    final duration = _durationCtrl.text.trim();
    final details = _detailsCtrl.text.trim();
    if (_outcome == CallOutcome.answered && duration.isEmpty) {
      setState(() => _formError = 'Enter call duration for answered calls');
      return;
    }
    if (_outcome == CallOutcome.answered && details.isEmpty) {
      setState(() => _formError = 'Enter call details');
      return;
    }
    if (_saving) return;

    setState(() {
      _formError = null;
      _saving = true;
    });
    try {
      await LeadCallLogService.create(
        leadId: widget.leadId,
        calledAt: _calledAt,
        duration: duration,
        details: details,
        direction: _direction,
        outcome: _outcome,
        followUpAt: _followUpRequired ? _followUpAt : null,
      );
      if (!mounted) return;
      AppFeedback.success(context, 'Call logged');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _formError = 'Could not save call: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final withLabel = widget.ownerName.trim().isNotEmpty
        ? 'with ${widget.ownerName.trim()}'
        : 'with landowner';

    return Dialog(
      insetPadding: fomraDialogInset(context),
      backgroundColor: context.fomraSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: fomraDialogConstraints(context, maxWidth: 440, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.purple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.call_outlined,
                      color: AppColors.purple,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Calls',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: context.fomraTextPrimary,
                          ),
                        ),
                        Text(
                          AppStore.instance.displayNameForLeadId(widget.leadId),
                          style: TextStyle(
                            fontSize: 12,
                            color: context.fomraTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (!widget.readOnly)
                Text(
                  'Log your call $withLabel',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.fomraTextSecondary,
                  ),
                )
              else
                Text(
                  'Call history for this lead',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.fomraTextSecondary,
                  ),
                ),
              const SizedBox(height: 14),
              if (!widget.readOnly)
                LogDialogTabBar(
                  selectedIndex: _tabIndex,
                  onChanged: (index) => setState(() => _tabIndex = index),
                  historyCount: _logs.length,
                ),
              if (!widget.readOnly) const SizedBox(height: 14),
              Flexible(
                child: widget.readOnly || _tabIndex == 1
                    ? _buildHistory(context)
                    : SingleChildScrollView(child: _buildNewForm(context)),
              ),
              if (!widget.readOnly && _tabIndex == 0) ...[
                const SizedBox(height: 14),
                DialogErrorBanner(message: _formError),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.purple,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Save Call'),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNewForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SeparateDateTimeFields(
          value: _calledAt,
          onEditDate: _editDate,
          onEditTime: _editTime,
        ),
        const SizedBox(height: 12),
        Text(
          'Call type',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.fomraTextSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final option in CallDirection.values) ...[
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: option == CallDirection.outgoing ? 6 : 0,
                  ),
                  child: _DirectionChip(
                    label: option.label,
                    icon: option == CallDirection.outgoing
                        ? Icons.call_made_outlined
                        : Icons.call_received_outlined,
                    selected: _direction == option,
                    onTap: () => setState(() => _direction = option),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Call status',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.fomraTextSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final option in CallOutcome.values) ...[
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: option == CallOutcome.answered ? 6 : 0,
                  ),
                  child: _DirectionChip(
                    label: option.label,
                    icon: option.icon,
                    selected: _outcome == option,
                    onTap: () => setState(() => _outcome = option),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _durationCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          decoration: InputDecoration(
            labelText: 'Call duration (minutes)',
            hintText: _outcome == CallOutcome.answered
                ? 'e.g. 5'
                : 'Optional for not answered',
            filled: true,
            fillColor: context.fomraSurfaceVar.withValues(alpha: 0.55),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.fomraBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.fomraBorder),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _detailsCtrl,
          minLines: 3,
          maxLines: 5,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: 'Call details',
            hintText: _outcome == CallOutcome.answered
                ? 'What was discussed with the landowner?'
                : 'Optional notes about the missed call',
            alignLabelWithHint: true,
            filled: true,
            fillColor: context.fomraSurfaceVar.withValues(alpha: 0.55),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.fomraBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.fomraBorder),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Follow-up: a toggle, and only when on do the date/time appear.
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          activeThumbColor: AppColors.purple,
          title: Text(
            'Follow-up Required',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.fomraTextPrimary,
            ),
          ),
          subtitle: Text(
            'Schedule a reminder to call back',
            style: TextStyle(fontSize: 11, color: context.fomraTextSecondary),
          ),
          value: _followUpRequired,
          onChanged: (v) => setState(() => _followUpRequired = v),
        ),
        if (_followUpRequired) ...[
          const SizedBox(height: 8),
          Text(
            'Follow-up date & time',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.fomraTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          SeparateDateTimeFields(
            value: _followUpAt,
            onEditDate: _editFollowUpDate,
            onEditTime: _editFollowUpTime,
          ),
        ],
      ],
    );
  }

  Widget _buildHistory(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_logs.isEmpty) {
      return const LogDialogHistoryEmpty(message: 'No previous calls yet.');
    }
    return ListView.separated(
      itemCount: _logs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) => _PreviousCallTile(log: _logs[index]),
    );
  }
}

class _DirectionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _DirectionChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.purple.withValues(alpha: 0.12)
          : context.fomraSurfaceVar.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.purple : context.fomraBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppColors.purple : context.fomraTextSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppColors.purple
                      : context.fomraTextPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviousCallTile extends StatelessWidget {
  final LeadCallLog log;

  const _PreviousCallTile({required this.log});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: context.fomraBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatCallDateTime(log.calledAt),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.fomraTextPrimary,
                  ),
                ),
              ),
              Text(
                log.direction.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: log.direction == CallDirection.outgoing
                      ? AppColors.info
                      : AppColors.success,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                log.outcome.icon,
                size: 14,
                color: log.isAnswered ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 4),
              Text(
                log.outcome.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: log.isAnswered ? AppColors.success : AppColors.warning,
                ),
              ),
              if (log.duration.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '${log.duration} min',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.purple,
                  ),
                ),
              ],
            ],
          ),
          if (log.loggedByName.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              log.loggedByName,
              style: TextStyle(
                fontSize: 11,
                color: context.fomraTextSecondary,
              ),
            ),
          ],
          if (log.details.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              log.details,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: context.fomraTextSecondary,
              ),
            ),
          ],
          if (log.followUpAt != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.event_repeat_outlined,
                    size: 13, color: AppColors.purple),
                const SizedBox(width: 4),
                Text(
                  'Follow-up: ${formatCallDateTime(log.followUpAt!)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.purple,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
