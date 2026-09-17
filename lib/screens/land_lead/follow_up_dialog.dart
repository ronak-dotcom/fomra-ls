import 'package:flutter/material.dart';

import '../../models/lead_follow_up.dart';
import '../../services/app_store.dart';
import '../../services/lead_follow_up_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/app_feedback.dart';

/// Opens the Follow-up window for a lead: schedule a reminder and review the
/// follow-up history. Returns nothing; callers can ignore the future.
Future<void> showFollowUpDialog(BuildContext context, String leadId) {
  // showFomraDialog opens this as a full-screen page on mobile (a centered modal
  // on desktop), matching the lead's other action dialogs.
  return showFomraDialog<void>(
    context: context,
    builder: (_) => _FollowUpDialog(leadId: leadId),
  );
}

class _FollowUpDialog extends StatefulWidget {
  final String leadId;
  const _FollowUpDialog({required this.leadId});

  @override
  State<_FollowUpDialog> createState() => _FollowUpDialogState();
}

class _FollowUpDialogState extends State<_FollowUpDialog> {
  final _titleCtrl = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;

  List<LeadFollowUp> _history = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await LeadFollowUpService.getForLead(widget.leadId);
    if (!mounted) return;
    setState(() {
      _history = list;
      _loading = false;
    });
  }

  DateTime? get _scheduledAt {
    if (_date == null || _time == null) return null;
    return DateTime(
      _date!.year,
      _date!.month,
      _date!.day,
      _time!.hour,
      _time!.minute,
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        _error = null;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _time = picked;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Enter what the follow-up is for.');
      return;
    }
    if (_date == null) {
      setState(() => _error = 'Follow-up date is required.');
      return;
    }
    if (_time == null) {
      setState(() => _error = 'Follow-up time is required.');
      return;
    }
    final at = _scheduledAt!;
    if (!at.isAfter(DateTime.now())) {
      setState(() => _error = 'Choose a future date and time.');
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await LeadFollowUpService.create(
        leadId: widget.leadId,
        title: _titleCtrl.text,
        remindAt: at,
      );
      if (!mounted) return;
      _titleCtrl.clear();
      setState(() {
        _date = null;
        _time = null;
      });
      await _load();
      if (!mounted) return;
      AppFeedback.success(context, 'Follow-up scheduled for ${LeadFollowUp.formatDateTime(at)}.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _complete(LeadFollowUp f) async {
    try {
      await LeadFollowUpService.markCompleted(f.id);
      await _load();
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Could not update: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: fomraDialogInset(context),
      backgroundColor: context.fomraSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: fomraDialogConstraints(context, maxWidth: 460, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              const SizedBox(height: 6),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _field(context, 'Follow up for', _titleCtrl,
                          hint: 'e.g. Call the owner regarding site visit'),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: _pickerTile(
                            context,
                            label: 'Follow-up Date',
                            value: _date == null
                                ? 'Select date'
                                : LeadFollowUp.formatDate(_date!),
                            icon: Icons.calendar_today_outlined,
                            set: _date != null,
                            onTap: _pickDate,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _pickerTile(
                            context,
                            label: 'Follow-up Time',
                            value: _time == null
                                ? 'Select time'
                                : _time!.format(context),
                            icon: Icons.access_time_outlined,
                            set: _time != null,
                            onTap: _pickTime,
                          ),
                        ),
                      ]),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(_error!,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.error)),
                      ],
                      const SizedBox(height: 14),
                      _buttons(context),
                      const SizedBox(height: 18),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      _historySection(context),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.purple.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.notifications_active_outlined,
                color: AppColors.purple, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Follow-up',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: context.fomraTextPrimary)),
                Text(AppStore.instance.displayNameForLeadId(widget.leadId),
                    style: TextStyle(
                        fontSize: 12, color: context.fomraTextSecondary)),
              ],
            ),
          ),
          IconButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      );

  Widget _field(
    BuildContext context,
    String label,
    TextEditingController ctrl, {
    String? hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: context.fomraSurfaceVar.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.fomraBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.fomraBorder),
        ),
      ),
    );
  }

  Widget _pickerTile(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required bool set,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: context.fomraSurfaceVar.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.fomraBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: context.fomraTextSecondary)),
            const SizedBox(height: 5),
            Row(children: [
              Icon(icon, size: 15, color: AppColors.purple),
              const SizedBox(width: 6),
              Expanded(
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: set
                            ? context.fomraTextPrimary
                            : context.fomraTextSecondary)),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buttons(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.alarm_add_outlined, size: 18),
            label: Text(_saving ? 'Saving…' : 'Save Follow-up'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
          ),
        ],
      );

  Widget _historySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Follow-up history',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: context.fomraTextPrimary)),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No follow-ups yet.',
                style:
                    TextStyle(fontSize: 12.5, color: context.fomraTextSecondary)),
          )
        else
          for (final f in _history) ...[
            _historyRow(context, f),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _historyRow(BuildContext context, LeadFollowUp f) {
    final status = f.status;
    final canComplete = status != FollowUpStatus.completed;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.fomraSurfaceVar.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.fomraBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(f.title.isEmpty ? 'Follow-up' : f.title,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: context.fomraTextPrimary)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: status.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(status.label,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: status.color)),
            ),
          ]),
          if (f.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(f.notes.trim(),
                style: TextStyle(
                    fontSize: 12, color: context.fomraTextSecondary)),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.schedule_outlined,
                size: 13, color: context.fomraTextSecondary),
            const SizedBox(width: 5),
            Expanded(
              child: Text(f.scheduledLabel,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: context.fomraTextPrimary)),
            ),
          ]),
          const SizedBox(height: 3),
          Text(
            'By ${f.createdBy.isEmpty ? '—' : f.createdBy} · ${f.createdLabel}',
            style: TextStyle(fontSize: 10.5, color: context.fomraTextSecondary),
          ),
          if (canComplete) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _complete(f),
                icon: const Icon(Icons.check_circle_outline, size: 15),
                label: const Text('Mark completed'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.success,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
