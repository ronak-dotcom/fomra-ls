import 'package:flutter/material.dart';

import '../../models/lead_drop_reason.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../services/lead_drop_reason_catalog_service.dart';
import '../../widgets/dictation_bar.dart';

class LeadDropReasonResult {
  final LeadDropReason reason;
  final String notes;

  const LeadDropReasonResult({
    required this.reason,
    required this.notes,
  });
}

Future<LeadDropReasonResult?> showLeadDropReasonDialog(BuildContext context) {
  return showDialog<LeadDropReasonResult>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    builder: (_) => const LeadDropReasonDialog(),
  );
}

class LeadDropReasonDialog extends StatefulWidget {
  const LeadDropReasonDialog({super.key});

  @override
  State<LeadDropReasonDialog> createState() => _LeadDropReasonDialogState();
}

class _LeadDropReasonDialogState extends State<LeadDropReasonDialog> {
  @override
  void initState() {
    super.initState();
    // Pick up reasons management added since the app opened.
    LeadDropReasonCatalogService.instance.load(force: true);
  }

  LeadDropReason? _reason;
  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason;
    if (reason == null) return;
    Navigator.pop(
      context,
      LeadDropReasonResult(reason: reason, notes: _notesCtrl.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
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
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.cancel_outlined,
                      color: AppColors.error,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Request drop approval',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: context.fomraTextPrimary,
                          ),
                        ),
                        Text(
                          'Select a reason and add notes for management review',
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
              const SizedBox(height: 16),
              Text(
                'Reason',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: context.fomraTextSecondary,
                ),
              ),
              const SizedBox(height: 6),
              AnimatedBuilder(
                animation: LeadDropReasonCatalogService.instance,
                builder: (context, _) {
                  final reasons = LeadDropReasonCatalogService.instance.current;
                  LeadDropReason? selected;
                  if (_reason != null) {
                    for (final reason in reasons) {
                      if (reason.id == _reason!.id) {
                        selected = reason;
                        break;
                      }
                    }
                  }
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.fomraBorder),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<LeadDropReason>(
                        value: selected,
                        isExpanded: true,
                        hint: Text(
                          'Select drop reason…',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.fomraTextSecondary,
                          ),
                        ),
                        items: reasons
                            .map(
                              (r) => DropdownMenuItem(
                                value: r,
                                child: Text(
                                  r.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: context.fomraTextPrimary,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => _reason = value),
                      ),
                    ),
                  );
                },
              ),
              if (_reason != null) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _notesCtrl,
                  minLines: 2,
                  maxLines: 8,
                  maxLength: kNotesMaxLength,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Notes',
                    hintText: 'Add details for management review…',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                DictationBar(controller: _notesCtrl),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _reason == null ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error,
                    ),
                    child: const Text('Submit for approval'),
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
