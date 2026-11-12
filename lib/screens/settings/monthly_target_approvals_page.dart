import 'package:flutter/material.dart';

import '../../models/monthly_target_submission.dart';
import '../../services/monthly_target_submission_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/fomra_app_shell.dart';
import '../../widgets/fomra_breadcrumb.dart';
import '../../widgets/monthly_target_editor.dart';
import '../../widgets/portal_page_layout.dart';
import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/app_feedback.dart';

enum MonthlyTargetEditAction { save, approve, reject }

class MonthlyTargetEditResult {
  final MonthlyTargetEditAction action;
  final Map<String, int> values;
  const MonthlyTargetEditResult(this.action, this.values);
}

/// Shared edit modal used by Target Approvals and the home Approvals sheet.
Future<MonthlyTargetEditResult?> showMonthlyTargetEditDialog(
  BuildContext context,
  MonthlyTargetSubmission submission,
) {
  return showDialog<MonthlyTargetEditResult>(
    context: context,
    builder: (_) => _EditTargetsDialog(submission: submission),
  );
}

/// Management page listing pending monthly-target submissions. Each can be
/// approved, rejected, or edited (save stays pending; approve notifies).
class MonthlyTargetApprovalsPage extends StatefulWidget {
  /// When embedded as a tab, drop the app shell/header and section heading and
  /// render just the pending list.
  final bool embedded;

  const MonthlyTargetApprovalsPage({super.key, this.embedded = false});

  @override
  State<MonthlyTargetApprovalsPage> createState() =>
      _MonthlyTargetApprovalsPageState();
}

class _MonthlyTargetApprovalsPageState
    extends State<MonthlyTargetApprovalsPage> {
  List<MonthlyTargetSubmission> _pending = const [];
  bool _loading = true;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final pending = await MonthlyTargetSubmissionService.getPending();
    if (!mounted) return;
    setState(() {
      _pending = pending;
      _loading = false;
    });
  }

  Future<void> _run(
    MonthlyTargetSubmission s,
    Future<void> Function() action,
    String okMessage,
  ) async {
    if (_busy.contains(s.id)) return;
    setState(() => _busy.add(s.id));
    try {
      await action();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      AppFeedback.success(context, okMessage);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, 'Action failed: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(s.id));
    }
  }

  Future<void> _approve(MonthlyTargetSubmission s,
      {Map<String, int>? approvedValues}) {
    return _run(
      s,
      () => MonthlyTargetSubmissionService.approve(
          submission: s, approvedValues: approvedValues),
      'Targets approved.',
    );
  }

  Future<void> _reject(MonthlyTargetSubmission s) async {
    final reason = await _askReason(context);
    if (reason == null) return;
    await _run(
      s,
      () => MonthlyTargetSubmissionService.reject(submission: s, reason: reason),
      'Targets rejected.',
    );
  }

  Future<void> _saveEdits(
      MonthlyTargetSubmission s, Map<String, int> values) {
    return _run(
      s,
      () => MonthlyTargetSubmissionService.saveEdits(
          submission: s, values: values),
      'Changes saved — still pending approval.',
    );
  }

  Future<String?> _askReason(BuildContext context) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject targets'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            hintText: 'Why are these targets being rejected?',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _editTargets(MonthlyTargetSubmission s) async {
    final result = await showMonthlyTargetEditDialog(context, s);
    if (result == null) return;
    switch (result.action) {
      case MonthlyTargetEditAction.save:
        await _saveEdits(s, result.values);
      case MonthlyTargetEditAction.approve:
        await _approve(s, approvedValues: result.values);
      case MonthlyTargetEditAction.reject:
        await _reject(s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (!widget.embedded)
                  const SectionHeader(
                    title: 'Monthly Target Approvals',
                    subtitle:
                        'Review, edit, approve, or reject the monthly targets employees submit.',
                    icon: Icons.fact_check_outlined,
                  ),
                if (_pending.isEmpty)
                  const AppCard(
                    interactive: false,
                    child: EmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'No pending submissions',
                      message:
                          'Employee target submissions awaiting approval appear here.',
                    ),
                  )
                else
                  for (final s in _pending) ...[
                    _card(context, s),
                    const SizedBox(height: AppSpacing.md),
                  ],
              ],
            ),
    );
    if (widget.embedded) return body;
    return FomraAppShell(
      currentRoute: '/settings',
      appBar: FomraSubPageAppBar(
        title: 'Target Approvals',
        breadcrumbs: FomraBreadcrumbs.forSettingsChild('Target Approvals'),
      ),
      backgroundColor: context.fomraPageBg,
      body: body,
    );
  }

  Widget _card(BuildContext context, MonthlyTargetSubmission s) {
    final busy = _busy.contains(s.id);
    final statusColor = s.status.color;
    return AppCard(
      interactive: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.employeeName.isEmpty ? s.employeeEmail : s.employeeName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (s.employeeCode.isNotEmpty) 'ID ${s.employeeCode}',
                        if (s.designation.isNotEmpty) s.designation,
                        if (s.department.isNotEmpty) s.department,
                      ].join(' · '),
                      style: TextStyle(
                          fontSize: 12, color: context.fomraTextSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _chip(context, s.monthLabel, AppColors.info),
                  const SizedBox(height: 6),
                  _chip(context, s.status.label, statusColor),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Current Status',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.fomraTextSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            s.status.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Submitted ${_fmtDate(s.submittedAt)}',
            style: TextStyle(fontSize: 11.5, color: context.fomraTextSecondary),
          ),
          const SizedBox(height: 12),
          _valuesGrid(context, s.approvedValues ?? s.submittedValues),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, c) {
            final edit = OutlinedButton.icon(
              onPressed: busy ? null : () => _editTargets(s),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit Targets'),
            );
            final reject = OutlinedButton.icon(
              onPressed: busy ? null : () => _reject(s),
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Reject'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
            );
            final approve = FilledButton.icon(
              onPressed: busy ? null : () => _approve(s),
              icon: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, size: 16),
              label: const Text('Approve'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            );
            if (c.maxWidth < 420) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  approve,
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: edit),
                    const SizedBox(width: 8),
                    Expanded(child: reject),
                  ]),
                ],
              );
            }
            return Row(
              children: [
                edit,
                const Spacer(),
                reject,
                const SizedBox(width: 8),
                approve,
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _valuesGrid(BuildContext context, Map<String, int> values) {
    final entries = [
      for (final cat in TargetCategory.values)
        if (values.containsKey(cat.key)) (cat, values[cat.key]!),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (cat, value) in entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.fomraSurfaceVar.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.fomraBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(cat.icon, size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('${cat.label}: ',
                  style: TextStyle(
                      fontSize: 12, color: context.fomraTextSecondary)),
              Text('$value',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: context.fomraTextPrimary)),
            ]),
          ),
      ],
    );
  }

  Widget _chip(BuildContext context, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      );

  static String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

enum _EditAction { save, approve, reject }

/// Management edit modal: Save Changes (stays pending), Approve, or Reject.
class _EditTargetsDialog extends StatefulWidget {
  final MonthlyTargetSubmission submission;
  const _EditTargetsDialog({required this.submission});

  @override
  State<_EditTargetsDialog> createState() => _EditTargetsDialogState();
}

class _EditTargetsDialogState extends State<_EditTargetsDialog> {
  late Map<String, int> _values = Map.of(
    widget.submission.approvedValues ?? widget.submission.submittedValues,
  );
  String? _error;

  bool _validate() {
    if (_values.isEmpty) {
      setState(() => _error = 'Keep at least one category selected.');
      return false;
    }
    return true;
  }

  MonthlyTargetEditResult _toPublic(_EditAction action) =>
      MonthlyTargetEditResult(
        switch (action) {
          _EditAction.save => MonthlyTargetEditAction.save,
          _EditAction.approve => MonthlyTargetEditAction.approve,
          _EditAction.reject => MonthlyTargetEditAction.reject,
        },
        action == _EditAction.reject ? const {} : _values,
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.submission;
    final statusColor = s.status.color;
    return Dialog(
      backgroundColor: context.fomraSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edit targets',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      s.status.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${s.employeeName.isEmpty ? s.employeeEmail : s.employeeName} · ${s.monthLabel}',
                style:
                    TextStyle(fontSize: 12, color: context.fomraTextSecondary),
              ),
              const SizedBox(height: 12),
              Text(
                'Current Status',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.fomraTextSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                s.status.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
              const SizedBox(height: 16),
              MonthlyTargetEditor(
                initial: _values,
                onChanged: (v) {
                  _values = v;
                  if (_error != null) setState(() => _error = null);
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.error)),
              ],
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.pop(context, _toPublic(_EditAction.reject)),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      if (!_validate()) return;
                      Navigator.pop(context, _toPublic(_EditAction.save));
                    },
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Save Changes'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      if (!_validate()) return;
                      Navigator.pop(context, _toPublic(_EditAction.approve));
                    },
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Approve'),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success),
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
