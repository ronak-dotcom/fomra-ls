import 'package:flutter/material.dart';

import '../../models/land_lead.dart';
import '../../services/land_lead_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/ui/app_components.dart';

/// Splits part of a parcel off into a new, independently-tracked lead —
/// e.g. part of a parcel is dropped while another part proceeds. Writes
/// through [LandLeadService.splitLead].
class SplitLeadDialog extends StatefulWidget {
  final LandLead parent;

  const SplitLeadDialog({super.key, required this.parent});

  @override
  State<SplitLeadDialog> createState() => _SplitLeadDialogState();
}

class _SplitLeadDialogState extends State<SplitLeadDialog> {
  final _surveyCtrl = TextEditingController();
  final _subDivisionCtrl = TextEditingController();
  final _extentCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _surveyCtrl.dispose();
    _subDivisionCtrl.dispose();
    _extentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_surveyCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Enter the survey number for the new lead.');
      return;
    }
    if (_extentCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Enter the land extent for the new lead.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await LandLeadService.splitLead(
        parent: widget.parent,
        newSurveyNumber: _surveyCtrl.text,
        newSubDivision: _subDivisionCtrl.text,
        newLandExtent: _extentCtrl.text,
      );
      if (!mounted) return;
      Navigator.pop(context, created);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not split lead: $e';
      });
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
            fomraDialogConstraints(context, maxWidth: 460, maxHeight: 520),
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
                      'Split Lead',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Creates a new, independently-tracked lead for part of this '
                'parcel. ${widget.parent.leadId} keeps its own survey list — '
                'edit it separately afterward if it should shrink.',
                style: TextStyle(fontSize: 12.5, color: context.fomraTextSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _surveyCtrl,
                decoration: const InputDecoration(
                  labelText: 'New lead\'s survey number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _subDivisionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Sub-division (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _extentCtrl,
                decoration: const InputDecoration(
                  labelText: 'New lead\'s land extent',
                  hintText: 'e.g. 2.5 acres',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create Split Lead'),
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
