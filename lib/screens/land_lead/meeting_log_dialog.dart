import 'package:flutter/material.dart';
import '../../widgets/ui/app_components.dart';
import 'package:flutter/services.dart';

import '../../models/land_lead_meeting.dart';
import '../../services/app_store.dart';
import '../../services/land_lead_meeting_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/log_dialog_tabs.dart';
import '../../widgets/separate_date_time_fields.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/dialog_error_banner.dart';

class MeetingLogDialog extends StatefulWidget {
  final String leadId;
  final String ownerName;
  final VoidCallback? onMeetingSaved;
  final bool readOnly;

  const MeetingLogDialog({
    super.key,
    required this.leadId,
    this.ownerName = '',
    this.onMeetingSaved,
    this.readOnly = false,
  });

  @override
  State<MeetingLogDialog> createState() => _MeetingLogDialogState();
}

class _MeetingLogDialogState extends State<MeetingLogDialog> {
  int _tabIndex = 0;
  late DateTime _metAt = DateTime.now();
  final _durationCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final Set<String> _attendeeTypes = {};

  /// People met, each a name + relation to the owner. Starts with one row.
  final List<_PersonRow> _people = [_PersonRow()];
  static const _maxPeople = 6;
  bool _managementPresent = false;
  bool _saving = false;
  String? _formError;
  bool _loading = true;
  List<LandLeadMeeting> _meetings = [];

  @override
  void initState() {
    super.initState();
    if (widget.readOnly) _tabIndex = 1;
    _loadMeetings();
  }

  @override
  void dispose() {
    _durationCtrl.dispose();
    _notesCtrl.dispose();
    for (final p in _people) {
      p.nameCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMeetings() async {
    try {
      final meetings = await LandLeadMeetingService.getForLead(widget.leadId);
      if (mounted) setState(() => _meetings = meetings);
    } catch (_) {
      // Table may not exist yet.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editDate() async {
    final updated = await pickLogDate(context, _metAt);
    if (updated == null || !mounted) return;
    setState(() => _metAt = updated);
  }

  Future<void> _editTime() async {
    final updated = await pickLogTime(context, _metAt);
    if (updated == null || !mounted) return;
    setState(() => _metAt = updated);
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
    final duration = _durationCtrl.text.trim();
    if (duration.isEmpty) {
      setState(() => _formError = 'Enter meeting duration');
      return;
    }
    final people = [
      for (final p in _people)
        PersonMet(name: p.nameCtrl.text.trim(), relation: p.relation ?? ''),
    ].where((p) => !p.isEmpty).toList();
    if (people.isEmpty) {
      setState(() => _formError =
          'Add the person met — their name and relation to the owner');
      return;
    }
    if (people.any((p) => p.relation.isEmpty)) {
      setState(() => _formError = 'Select the relation for each person met');
      return;
    }
    // Ticked chips plus whatever the people's relations imply, so the two
    // can never disagree (e.g. a "Son" row always counts as a Relative).
    final attendeeTypes = {
      ..._attendeeTypes,
      for (final p in people) PersonMet.attendeeTypeFor(p.relation),
    };
    if (_saving) return;

    setState(() {
      _formError = null;
      _saving = true;
    });
    try {
      await LandLeadMeetingService.create(
        leadId: widget.leadId,
        metAt: _metAt,
        duration: duration,
        notes: _notesCtrl.text.trim(),
        attendeeTypes: attendeeTypes.toList(),
        managementPresent: _managementPresent,
        peopleMet: people,
      );
      if (!mounted) return;
      widget.onMeetingSaved?.call();
      AppFeedback.success(context, 'Meeting logged');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _formError = 'Could not save meeting: $e');
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
                      Icons.groups_outlined,
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
                          'Meeting',
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
                  'Log your meeting $withLabel',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.fomraTextSecondary,
                  ),
                )
              else
                Text(
                  'Meeting history for this lead',
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
                  historyCount: _meetings.length,
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
                          : const Text('Save Meeting'),
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
          value: _metAt,
          onEditDate: _editDate,
          onEditTime: _editTime,
        ),
        const SizedBox(height: 12),
        _buildPeopleMet(context),
        const SizedBox(height: 12),
        Text(
          'Also present (optional)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.fomraTextSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in MeetingAttendeeTypes.all)
              FilterChip(
                label: Text(MeetingAttendeeTypes.short(type),
                    style: const TextStyle(fontSize: 12)),
                selected: _attendeeTypes.contains(type),
                selectedColor: AppColors.purple.withValues(alpha: 0.18),
                checkmarkColor: AppColors.purple,
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _attendeeTypes.add(type);
                  } else {
                    _attendeeTypes.remove(type);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _managementPresent,
          onChanged: (v) => setState(() => _managementPresent = v ?? false),
          title: const Text('Management was present',
              style: TextStyle(fontSize: 13)),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _durationCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          decoration: _fieldDecoration(
            context,
            'Meeting duration (minutes)',
            hint: 'e.g. 30',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notesCtrl,
          minLines: 3,
          maxLines: 5,
          maxLength: 500,
          decoration: _fieldDecoration(
            context,
            'Meeting notes (optional)',
            hint: 'What was discussed?',
          ).copyWith(alignLabelWithHint: true),
        ),
      ],
    );
  }

  Widget _buildPeopleMet(BuildContext context) {
    final label = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: context.fomraTextSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Who was met — name and relation to the owner', style: label),
        const SizedBox(height: 6),
        for (var i = 0; i < _people.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  key: ValueKey('person-name-$i'),
                  controller: _people[i].nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: _fieldDecoration(context, 'Name',
                          hint: 'e.g. Ravi')
                      .copyWith(isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('person-relation-$i'),
                  isExpanded: true,
                  initialValue: _people[i].relation,
                  menuMaxHeight: 320,
                  decoration: _fieldDecoration(context, 'Relation')
                      .copyWith(isDense: true),
                  items: [
                    for (final r in PersonMet.relations)
                      DropdownMenuItem(
                        value: r,
                        child: Text(r,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                  onChanged: (v) => setState(() => _people[i].relation = v),
                ),
              ),
              if (_people.length > 1)
                IconButton(
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    _people.removeAt(i).nameCtrl.dispose();
                  }),
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: AppColors.error),
                ),
            ],
          ),
        ],
        if (_people.length < _maxPeople)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _people.add(_PersonRow())),
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('Add person'),
              style: TextButton.styleFrom(foregroundColor: AppColors.purple),
            ),
          ),
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
    if (_meetings.isEmpty) {
      return const LogDialogHistoryEmpty(message: 'No previous meetings yet.');
    }
    return ListView.separated(
      itemCount: _meetings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) =>
          _PreviousMeetingTile(meeting: _meetings[index]),
    );
  }
}

class _PersonRow {
  final nameCtrl = TextEditingController();
  String? relation;
}

class _MiniTag extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _PreviousMeetingTile extends StatelessWidget {
  final LandLeadMeeting meeting;

  const _PreviousMeetingTile({required this.meeting});

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
                  formatCallDateTime(meeting.metAt),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.fomraTextPrimary,
                  ),
                ),
              ),
              Text(
                '${meeting.duration} min',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.purple,
                ),
              ),
            ],
          ),
          if (meeting.loggedByName.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              meeting.loggedByName,
              style: TextStyle(
                fontSize: 11,
                color: context.fomraTextSecondary,
              ),
            ),
          ],
          if (meeting.attendeeTypes.isNotEmpty || meeting.managementPresent) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final type in meeting.attendeeTypes)
                  _MiniTag(
                    label: MeetingAttendeeTypes.short(type),
                    color: meetingAttendeeColor(type),
                  ),
                if (meeting.managementPresent)
                  _MiniTag(label: 'Management present', color: AppColors.info),
              ],
            ),
          ],
          if (meeting.peopleMet.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final p in meeting.peopleMet)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  Icon(Icons.person_outline_rounded,
                      size: 14, color: meetingAttendeeColor(
                          PersonMet.attendeeTypeFor(p.relation))),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      p.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                  ),
                ]),
              ),
          ],
          if (meeting.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              meeting.notes,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: context.fomraTextSecondary,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(
              'Logged ${formatCallDateTime(meeting.createdAt)}',
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

/// One colour per kind of person met, used wherever meetings are shown: the
/// owner green, agreement holder blue, relatives amber, others neutral.
Color meetingAttendeeColor(String type) => switch (type) {
      MeetingAttendeeTypes.landOwner => AppColors.success,
      MeetingAttendeeTypes.agreementHolder => AppColors.info,
      MeetingAttendeeTypes.relative ||
      MeetingAttendeeTypes.familyOrFriend =>
        AppColors.warning,
      MeetingAttendeeTypes.broker => AppColors.cyan,
      _ => AppColors.purple,
    };
