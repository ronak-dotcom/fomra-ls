import 'package:flutter/material.dart';
import '../../widgets/ui/app_components.dart';

import '../../services/app_store.dart';
import '../../services/land_lead_legal_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/ui/app_feedback.dart';

/// Legal action window: capture Legal Queries and Legal Notes for a lead.
/// Document upload has been removed; both fields are persisted in the existing
/// `reference_notes` backend column (encoded together — no schema change).
class LegalDocumentsDialog extends StatefulWidget {
  final String leadId;
  final bool readOnly;

  const LegalDocumentsDialog({
    super.key,
    required this.leadId,
    this.readOnly = false,
  });

  @override
  State<LegalDocumentsDialog> createState() => _LegalDocumentsDialogState();
}

class _LegalDocumentsDialogState extends State<LegalDocumentsDialog> {
  static const _queriesMarker = '[Legal Queries]';
  static const _notesMarker = '[Legal Notes]';

  final _queriesCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _queriesCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final raw = await LandLeadLegalService.getReferenceNotes(widget.leadId);
      final decoded = _decode(raw);
      if (!mounted) return;
      setState(() {
        _queriesCtrl.text = decoded.queries;
        _notesCtrl.text = decoded.notes;
      });
    } catch (_) {
      // Table may not exist yet — start with empty fields.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  ({String queries, String notes}) _decode(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return (queries: '', notes: '');
    final qIdx = text.indexOf(_queriesMarker);
    final nIdx = text.indexOf(_notesMarker);
    if (qIdx == -1 && nIdx == -1) {
      // Legacy reference notes — treat the whole blob as Legal Notes.
      return (queries: '', notes: text);
    }
    String section(int start, int end) {
      if (start == -1) return '';
      final from = start + (start == qIdx ? _queriesMarker.length : _notesMarker.length);
      final to = end == -1 ? text.length : end;
      return text.substring(from, to).trim();
    }

    if (qIdx != -1 && nIdx != -1) {
      if (qIdx < nIdx) {
        return (queries: section(qIdx, nIdx), notes: section(nIdx, -1));
      }
      return (queries: section(qIdx, -1), notes: section(nIdx, qIdx));
    }
    if (qIdx != -1) return (queries: section(qIdx, -1), notes: '');
    return (queries: '', notes: section(nIdx, -1));
  }

  String _encode() {
    final q = _queriesCtrl.text.trim();
    final n = _notesCtrl.text.trim();
    if (q.isEmpty && n.isEmpty) return '';
    return '$_queriesMarker\n$q\n\n$_notesMarker\n$n';
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await LandLeadLegalService.saveReferenceNotes(widget.leadId, _encode());
      if (mounted) {
        AppFeedback.success(context, 'Legal details saved');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, 'Could not save: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _fieldDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
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
    );
  }

  Widget _readOnlyBlock(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            color: context.fomraTextSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value.trim().isEmpty ? '—' : value.trim(),
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: context.fomraTextPrimary,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: fomraDialogInset(context),
      backgroundColor: context.fomraSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: fomraDialogConstraints(context, maxWidth: 480, maxHeight: 620),
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
                      Icons.gavel_outlined,
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
                          'Legal',
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
              Text(
                widget.readOnly
                    ? 'Legal queries and notes for this lead'
                    : 'Record legal queries and notes for this lead',
                style: TextStyle(
                  fontSize: 12,
                  color: context.fomraTextSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.readOnly) ...[
                              _readOnlyBlock(
                                  'Legal Queries', _queriesCtrl.text),
                              const SizedBox(height: 16),
                              _readOnlyBlock('Legal Notes', _notesCtrl.text),
                            ] else ...[
                              TextField(
                                controller: _queriesCtrl,
                                minLines: 3,
                                maxLines: 5,
                                maxLength: 500,
                                decoration: _fieldDecoration(
                                  'Legal Queries',
                                  'Raise queries for legal review…',
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _notesCtrl,
                                minLines: 3,
                                maxLines: 5,
                                maxLength: 500,
                                decoration: _fieldDecoration(
                                  'Legal Notes',
                                  'Add legal notes / reference…',
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(widget.readOnly ? 'Close' : 'Cancel'),
                  ),
                  if (!widget.readOnly) ...[
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
                          : const Text('Save'),
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
