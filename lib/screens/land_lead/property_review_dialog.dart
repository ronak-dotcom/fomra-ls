import 'package:flutter/material.dart';

import '../../models/lead_follow_up.dart';
import '../../models/lead_review.dart';
import '../../services/app_store.dart';
import '../../services/lead_review_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/app_feedback.dart';

/// Opens the Property Review window for a lead: record a review (Reporting
/// Manager / Head / Management only, and never on a locked lead) and see the
/// review history. Resolves to true when a new review was saved.
Future<bool> showPropertyReviewDialog(
  BuildContext context,
  String leadId, {
  bool canRecord = true,
}) async {
  final saved = await showFomraDialog<bool>(
    context: context,
    builder: (_) => _PropertyReviewDialog(
      leadId: leadId,
      canRecord: canRecord && LeadReviewService.canReview,
    ),
  );
  return saved ?? false;
}

class _PropertyReviewDialog extends StatefulWidget {
  final String leadId;
  final bool canRecord;
  const _PropertyReviewDialog({required this.leadId, required this.canRecord});

  @override
  State<_PropertyReviewDialog> createState() => _PropertyReviewDialogState();
}

class _PropertyReviewDialogState extends State<_PropertyReviewDialog> {
  final _notesCtrl = TextEditingController();
  DateTime? _nextDate;

  List<LeadReview> _history = const [];
  bool _loading = true;
  bool _saving = false;
  bool _savedAny = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await LeadReviewService.getForLead(widget.leadId);
    if (!mounted) return;
    setState(() {
      _history = list;
      _loading = false;
    });
  }

  Future<void> _pickNextDate() async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextDate ?? DateTime(now.year, now.month, now.day + 7),
      firstDate: tomorrow,
      lastDate: DateTime(now.year + 2),
      helpText: 'Next review date',
    );
    if (picked != null) {
      setState(() {
        _nextDate = picked;
        _error = null;
      });
    }
  }

  void _quickPick(int days) {
    final now = DateTime.now();
    setState(() {
      _nextDate = DateTime(now.year, now.month, now.day + days);
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_notesCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Add a review note.');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await LeadReviewService.create(
        leadId: widget.leadId,
        notes: _notesCtrl.text,
        nextReviewDate: _nextDate,
      );
      if (!mounted) return;
      _savedAny = true;
      AppFeedback.success(
        context,
        _nextDate == null
            ? 'Property marked as reviewed.'
            : 'Reviewed. Next review on ${LeadFollowUp.formatDate(_nextDate!)}.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: fomraDialogInset(context),
      backgroundColor: context.fomraSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints:
            fomraDialogConstraints(context, maxWidth: 480, maxHeight: 740),
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
                      if (widget.canRecord) ...[
                        _form(context),
                        const SizedBox(height: 18),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                      ],
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
            child: const Icon(Icons.fact_check_outlined,
                color: AppColors.purple, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Property Review',
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
            onPressed:
                _saving ? null : () => Navigator.pop(context, _savedAny),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      );

  Widget _form(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: context.fomraBorder),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Reviewing as ${LeadReviewService.currentReviewerRole} · '
          '${LeadFollowUp.formatDateTime(DateTime.now())}',
          style: TextStyle(fontSize: 11.5, color: context.fomraTextSecondary),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _notesCtrl,
          minLines: 3,
          maxLines: 6,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(
            labelText: 'Review note',
            hintText: 'e.g. Checked documents and pricing; push for owner '
                'meeting this week',
            alignLabelWithHint: true,
            isDense: true,
            filled: true,
            fillColor: context.fomraSurfaceVar.withValues(alpha: 0.5),
            border: border,
            enabledBorder: border,
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _pickNextDate,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: context.fomraSurfaceVar.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.fomraBorder),
            ),
            child: Row(children: [
              const Icon(Icons.event_repeat_outlined,
                  size: 16, color: AppColors.purple),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Next Review Date (optional)',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: context.fomraTextSecondary)),
                    const SizedBox(height: 3),
                    Text(
                      _nextDate == null
                          ? 'Select date'
                          : LeadFollowUp.formatDate(_nextDate!),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _nextDate == null
                              ? context.fomraTextSecondary
                              : context.fomraTextPrimary),
                    ),
                  ],
                ),
              ),
              if (_nextDate != null)
                IconButton(
                  tooltip: 'Clear',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: () => setState(() => _nextDate = null),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (label, days) in const [
              ('1 week', 7),
              ('2 weeks', 14),
              ('1 month', 30),
            ])
              ActionChip(
                label: Text(label, style: const TextStyle(fontSize: 11.5)),
                visualDensity: VisualDensity.compact,
                onPressed: () => _quickPick(days),
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!,
              style: const TextStyle(fontSize: 12, color: AppColors.error)),
        ],
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed:
                  _saving ? null : () => Navigator.pop(context, _savedAny),
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
                  : const Icon(Icons.task_alt_rounded, size: 18),
              label: Text(_saving ? 'Saving…' : 'Mark Reviewed'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
            ),
          ],
        ),
      ],
    );
  }

  Widget _historySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Review history',
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
            child: Text('This property has not been reviewed yet.',
                style: TextStyle(
                    fontSize: 12.5, color: context.fomraTextSecondary)),
          )
        else
          for (final r in _history) ...[
            _historyRow(context, r),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _historyRow(BuildContext context, LeadReview r) {
    final who = [
      if (r.reviewedBy.trim().isNotEmpty) r.reviewedBy.trim(),
      if (r.reviewerRole.trim().isNotEmpty) r.reviewerRole.trim(),
    ].join(' · ');
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
          Text(r.reviewedLabel,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.fomraTextPrimary)),
          if (who.isNotEmpty)
            Text(who,
                style: TextStyle(
                    fontSize: 11.5, color: context.fomraTextSecondary)),
          if (r.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(r.notes.trim(),
                style: TextStyle(
                    fontSize: 12.5, color: context.fomraTextPrimary)),
          ],
          if (r.nextReviewLabel != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.event_repeat_outlined,
                  size: 13, color: AppColors.purple),
              const SizedBox(width: 4),
              Text('Next review: ${r.nextReviewLabel}',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: context.fomraTextSecondary)),
            ]),
          ],
        ],
      ),
    );
  }
}

/// Compact card on Lead Detail showing the latest property review — when it
/// was reviewed, by whom, the note, and when the next review is due (with an
/// Overdue / Due today flag). Tapping opens the review dialog.
class PropertyReviewCard extends StatelessWidget {
  final LeadReview? latest;
  final int reviewCount;

  /// Whether the current user may record a review here (RM / Head /
  /// Management on an unlocked lead).
  final bool canRecord;
  final VoidCallback onOpen;

  const PropertyReviewCard({
    super.key,
    required this.latest,
    required this.reviewCount,
    required this.canRecord,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final r = latest;
    return Container(
      decoration: BoxDecoration(
        color: context.fomraSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.fomraBorder),
        boxShadow: context.fomraCardShadow,
      ),
      padding: const EdgeInsets.fromLTRB(14, 11, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined,
                  size: 15, color: AppColors.purple),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Property Review',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: context.fomraTextPrimary,
                  ),
                ),
              ),
              if (r != null) _dueBadge(r),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: onOpen,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppColors.purple,
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
                icon: Icon(
                    canRecord ? Icons.task_alt_rounded : Icons.history_rounded,
                    size: 16),
                label: Text(canRecord
                    ? 'Review'
                    : (reviewCount > 0 ? 'History ($reviewCount)' : 'History')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (r == null)
            Text(
              canRecord
                  ? 'Not reviewed yet. Tap Review to record your review and '
                      'set the next review date.'
                  : 'Not reviewed yet by the Reporting Manager / Management.',
              style:
                  TextStyle(fontSize: 12, color: context.fomraTextSecondary),
            )
          else ...[
            _row(
              context,
              'Last reviewed',
              [
                r.reviewedLabel,
                if (r.reviewedBy.trim().isNotEmpty) 'by ${r.reviewedBy.trim()}',
                if (r.reviewerRole.trim().isNotEmpty)
                  '(${r.reviewerRole.trim()})',
              ].join(' '),
            ),
            const SizedBox(height: 6),
            _row(context, 'Next review', r.nextReviewLabel ?? 'Not scheduled'),
            if (r.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              _row(context, 'Note', r.notes.trim()),
            ],
            if (canRecord && reviewCount > 1) ...[
              const SizedBox(height: 4),
              Text('$reviewCount reviews in history',
                  style: TextStyle(
                      fontSize: 10.5, color: context.fomraTextSecondary)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: context.fomraTextSecondary)),
        const SizedBox(height: 2),
        Text(value,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: context.fomraTextPrimary)),
      ],
    );
  }

  Widget _dueBadge(LeadReview r) {
    final days = r.daysUntilNext;
    if (days == null) return const SizedBox.shrink();
    final (String text, Color color) = r.isOverdue
        ? ('Overdue ${-days}d', AppColors.error)
        : r.isDueToday
            ? ('Due today', AppColors.warning)
            : ('In ${days}d', AppColors.success);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
    );
  }
}
