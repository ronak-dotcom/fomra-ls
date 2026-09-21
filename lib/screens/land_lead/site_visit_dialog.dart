import 'package:flutter/material.dart';
import '../../widgets/ui/app_components.dart';

import '../../models/land_lead_site_visit.dart';
import '../../services/app_store.dart';
import '../../services/auth_service.dart';
import '../../services/land_lead_site_visit_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/separate_date_time_fields.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/dialog_error_banner.dart';

class SiteVisitDialog extends StatefulWidget {
  final String leadId;
  final LandLeadSiteVisitType visitType;
  final VoidCallback? onVisitDone;
  final bool readOnly;

  const SiteVisitDialog({
    super.key,
    required this.leadId,
    this.visitType = LandLeadSiteVisitType.employee,
    this.onVisitDone,
    this.readOnly = false,
  });

  const SiteVisitDialog.management({
    super.key,
    required this.leadId,
    this.onVisitDone,
    this.readOnly = false,
  }) : visitType = LandLeadSiteVisitType.management;

  @override
  State<SiteVisitDialog> createState() => _SiteVisitDialogState();
}

class _SiteVisitDialogState extends State<SiteVisitDialog> {
  late DateTime _visitedAt = DateTime.now();
  bool _saving = false;
  String? _formError;
  bool _loading = true;
  List<LandLeadSiteVisit> _visits = [];

  bool get _isManagement =>
      widget.visitType == LandLeadSiteVisitType.management;

  String get _title =>
      _isManagement ? 'Management site visit' : 'Site visit';

  IconData get _headerIcon => _isManagement
      ? Icons.apartment_outlined
      : Icons.location_on_outlined;

  String get _doneLabel => _isManagement
      ? 'Management site visited'
      : 'Site visit done';

  String get _successMessage => _isManagement
      ? 'Management site visit recorded'
      : 'Site visit marked as done';

  String get _previousLabel => widget.readOnly
      ? 'Visit history'
      : _isManagement
          ? 'Previous management visits'
          : 'Previous site visits';

  @override
  void initState() {
    super.initState();
    _loadVisits();
  }

  Future<void> _loadVisits() async {
    try {
      final visits = await LandLeadSiteVisitService.getForLead(
        widget.leadId,
        visitType: widget.visitType,
      );
      if (mounted) setState(() => _visits = visits);
    } catch (_) {
      // Table may not exist yet.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editDate() async {
    final updated = await pickLogDate(context, _visitedAt);
    if (updated == null || !mounted) return;
    setState(() => _visitedAt = updated);
  }

  Future<void> _editTime() async {
    final updated = await pickLogTime(context, _visitedAt);
    if (updated == null || !mounted) return;
    setState(() => _visitedAt = updated);
  }

  Future<void> _markDone() async {
    if (_saving) return;

    setState(() {
      _formError = null;
      _saving = true;
    });
    try {
      await LandLeadSiteVisitService.markDone(
        leadId: widget.leadId,
        visitedAt: _visitedAt,
        visitType: widget.visitType,
      );
      if (!mounted) return;
      widget.onVisitDone?.call();
      AppFeedback.success(
        context,
        _isManagement && !AuthService.instance.isManagement
            ? 'Management site visit sent for approval'
            : _successMessage,
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _formError = 'Could not save site visit: $e');
      }
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
        constraints: fomraDialogConstraints(context, maxWidth: 440, maxHeight: 520),
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
                    child: Icon(
                      _headerIcon,
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
                          _title,
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
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!widget.readOnly)
                        SeparateDateTimeFields(
                          value: _visitedAt,
                          onEditDate: _editDate,
                          onEditTime: _editTime,
                        ),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      else if (_visits.isNotEmpty) ...[
                        if (!widget.readOnly) const SizedBox(height: 18),
                        Text(
                          _previousLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: context.fomraTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final visit in _visits)
                          _PreviousVisitTile(visit: visit),
                      ] else if (widget.readOnly) ...[
                        const SizedBox(height: 8),
                        Text(
                          'No visits logged yet.',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.fomraTextSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              DialogErrorBanner(message: _formError),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                  if (!widget.readOnly) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _saving ? null : _markDone,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline, size: 18),
                      label: Text(_saving ? 'Saving…' : _doneLabel),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.purple,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviousVisitTile extends StatelessWidget {
  final LandLeadSiteVisit visit;

  const _PreviousVisitTile({required this.visit});

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
              const Icon(Icons.check_circle, size: 16, color: AppColors.purple),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatCallDateTime(visit.visitedAt),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                    if (visit.visitType == LandLeadSiteVisitType.management &&
                        visit.approvalStatus != SiteVisitApprovalStatus.approved)
                      Text(
                        visit.approvalStatus.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: visit.approvalStatus ==
                                  SiteVisitApprovalStatus.rejected
                              ? AppColors.error
                              : AppColors.warning,
                        ),
                      ),
                    if (visit.loggedByName.isNotEmpty)
                      Text(
                        visit.loggedByName,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.fomraTextSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(
              'Logged ${formatCallDateTime(visit.createdAt)}',
              style: TextStyle(
                fontSize: 10.5,
                fontStyle: FontStyle.italic,
                color: context.fomraTextSecondary.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
