import 'package:flutter/material.dart';
import '../../widgets/ui/app_components.dart';

import '../../models/land_lead.dart';
import '../../services/land_lead_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/lead_auto_notes.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/log_dialog_tabs.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/dialog_error_banner.dart';

class NotesLogDialog extends StatefulWidget {
  final LandLead lead;
  final ValueChanged<LandLead>? onSaved;
  final bool readOnly;

  const NotesLogDialog({
    super.key,
    required this.lead,
    this.onSaved,
    this.readOnly = false,
  });

  @override
  State<NotesLogDialog> createState() => _NotesLogDialogState();
}

class _NotesLogDialogState extends State<NotesLogDialog> {
  int _tabIndex = 0;
  final _noteCtrl = TextEditingController();
  bool _saving = false;
  String? _formError;
  late List<String> _previousNotes;
  late String _existingNotes;

  @override
  void initState() {
    super.initState();
    if (widget.readOnly) _tabIndex = 1;
    _existingNotes = widget.lead.notes;
    _previousNotes = _parseNotes(_existingNotes);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  /// Newest first. The auto-generated nearby block counts as one note, so it
  /// doesn't bury the manual history under a tile per category.
  List<String> _parseNotes(String raw) {
    if (raw.trim().isEmpty) return [];
    return LeadAutoNotes.splitEntries(raw).reversed.toList();
  }

  InputDecoration _fieldDecoration(BuildContext context, String label,
      {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
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

  Future<void> _save() async {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _formError = 'Type a note before saving');
      return;
    }
    if (_saving) return;

    setState(() {
      _formError = null;
      _saving = true;
    });
    final stamp = DateTime.now().toLocal();
    final entry =
        '[${stamp.day}/${stamp.month}/${stamp.year} ${stamp.hour}:${stamp.minute.toString().padLeft(2, '0')}] $text';
    final merged = _existingNotes.trim().isEmpty
        ? entry
        : '${_existingNotes.trim()}\n$entry';

    try {
      final updated = widget.lead.copyWith(notes: merged);
      final saved = await LandLeadService.update(updated);
      if (!mounted) return;
      widget.onSaved?.call(saved);
      AppFeedback.success(context, 'Note saved');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _formError = 'Could not save note: $e');
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
                      Icons.sticky_note_2_outlined,
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
                          'Notes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: context.fomraTextPrimary,
                          ),
                        ),
                        Text(
                          widget.lead.displayName,
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
                  'Add a note for this lead',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.fomraTextSecondary,
                  ),
                )
              else
                Text(
                  'Notes history for this lead',
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
                  historyCount: _previousNotes.length,
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
                          : const Text('Save Note'),
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
    return TextField(
      controller: _noteCtrl,
      minLines: 4,
      maxLines: 8,
      maxLength: 500,
      decoration: _fieldDecoration(
        context,
        'Your note',
        hint: 'Type your note here…',
      ).copyWith(alignLabelWithHint: true),
    );
  }

  Widget _buildHistory(BuildContext context) {
    if (_previousNotes.isEmpty) {
      return const LogDialogHistoryEmpty(message: 'No previous notes yet.');
    }
    return ListView.separated(
      itemCount: _previousNotes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) => _PreviousNoteTile(text: _previousNotes[index]),
    );
  }
}

class _PreviousNoteTile extends StatelessWidget {
  final String text;

  const _PreviousNoteTile({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: context.fomraBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: context.fomraTextPrimary,
        ),
      ),
    );
  }
}
