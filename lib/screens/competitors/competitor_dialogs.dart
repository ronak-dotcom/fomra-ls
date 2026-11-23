import 'package:flutter/material.dart';

import '../../models/competitor_project.dart';
import '../../models/land_lead.dart';
import '../../services/competitor_service.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/app_form.dart';

String _n(num? v) {
  if (v == null) return '';
  return v == v.roundToDouble() ? v.round().toString() : v.toString();
}

double? _num(String s) => double.tryParse(s.replaceAll(RegExp(r'[,₹\s]'), ''));

/// Records a price & sales check (prices now, sold / left per phase).
/// Returns the updated project.
Future<CompetitorProject?> showCompetitorCheckDialog(
  BuildContext context,
  CompetitorProject project,
) =>
    showFomraDialog<CompetitorProject>(
      context: context,
      builder: (_) => _CheckDialog(project: project),
    );

class _CheckDialog extends StatefulWidget {
  final CompetitorProject project;
  const _CheckDialog({required this.project});

  @override
  State<_CheckDialog> createState() => _CheckDialogState();
}

class _CheckDialogState extends State<_CheckDialog> {
  late final p = widget.project;
  late final _pre = TextEditingController(text: _n(p.preLaunchPrice));
  late final _quoted = TextEditingController(text: _n(p.quotedPrice));
  late final _negotiated = TextEditingController(text: _n(p.negotiatedPrice));
  late final _sold = [
    for (final ph in p.phases) TextEditingController(text: _n(ph.sold)),
  ];
  late final _left = [
    for (final ph in p.phases) TextEditingController(text: _n(ph.available)),
  ];
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_pre, _quoted, _negotiated, _notes, ..._sold, ..._left]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final phases = [
        for (var i = 0; i < p.phases.length; i++)
          CompetitorPhase(
            id: p.phases[i].id,
            label: p.phases[i].label,
            sold: _num(_sold[i].text)?.round(),
            available: _num(_left[i].text)?.round(),
          ),
      ];
      final saved = await CompetitorService.instance.addCheck(
        p,
        preLaunchPrice: _num(_pre.text),
        quotedPrice: _num(_quoted.text),
        negotiatedPrice: _num(_negotiated.text),
        phases: phases,
        notes: _notes.text,
      );
      if (!mounted) return;
      AppFeedback.success(context, 'Check saved for ${p.code}.');
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppFeedback.error(context, 'Could not save: $e');
      }
    }
  }

  Widget _num3(List<(TextEditingController, String)> fields) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: AppFormField(
                controller: fields[i].$1,
                label: fields[i].$2,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: fomraDialogInset(context),
      title: Text('Price check · ${p.name}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Today's figures from the site or their sales team. The "
                'project is due for its next check in '
                '${CompetitorProject.recheckDays} days.',
                style: TextStyle(fontSize: 13, color: context.fomraTextSecondary),
              ),
              const SizedBox(height: 14),
              Text('₹ per sq ft',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: context.fomraTextPrimary)),
              const SizedBox(height: 8),
              _num3([
                (_pre, 'Pre-launch'),
                (_quoted, 'Quoted'),
                (_negotiated, 'Negotiated'),
              ]),
              if (p.phases.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Plots sold / left',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.fomraTextPrimary)),
                for (var i = 0; i < p.phases.length; i++) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${p.phases[i].label.isEmpty ? 'Phase ${i + 1}' : p.phases[i].label}'
                    '${p.phases[i].plots == null ? '' : ' · ${p.phases[i].plots} plots'}',
                    style: TextStyle(
                        fontSize: 12.5, color: context.fomraTextSecondary),
                  ),
                  const SizedBox(height: 6),
                  _num3([(_sold[i], 'Sold'), (_left[i], 'Left')]),
                ],
              ],
              const SizedBox(height: 16),
              AppFormField(
                controller: _notes,
                label: 'Notes',
                hint: 'Offers, new phase, demand…',
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        FormActionBar(
          submitLabel: 'Save check',
          loading: _saving,
          onSubmit: _saving ? null : _save,
          onCancel: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Picks leads to link (tick several; search by number, name or village).
Future<List<LandLead>> pickLeads(
  BuildContext context, {
  required List<LandLead> leads,
  Set<String> exclude = const {},
  String title = 'Link to leads',
}) async =>
    await showFomraDialog<List<LandLead>>(
      context: context,
      builder: (_) => _MultiPickerDialog<LandLead>(
        title: title,
        hint: 'Search lead no., name or village…',
        noun: 'lead',
        items: [
          for (final l in leads)
            if (!exclude.contains(l.leadId)) l,
        ],
        keyOf: (l) => l.leadId,
        titleOf: (l) => '#${l.leadId} · ${l.displayName}',
        subtitleOf: (l) => [l.village, l.taluk]
            .where((s) => s.trim().isNotEmpty)
            .join(', '),
        matches: (l, q) =>
            l.leadId.toLowerCase().contains(q) ||
            l.displayName.toLowerCase().contains(q) ||
            l.village.toLowerCase().contains(q) ||
            l.taluk.toLowerCase().contains(q),
      ),
    ) ??
    const [];

/// Picks competitor projects to link (tick several; search by code, name,
/// builder or village).
Future<List<CompetitorProject>> pickCompetitors(
  BuildContext context, {
  Set<String> exclude = const {},
}) async =>
    await showFomraDialog<List<CompetitorProject>>(
      context: context,
      builder: (_) => _MultiPickerDialog<CompetitorProject>(
        title: 'Link competitor projects',
        hint: 'Search code, project, builder or village…',
        noun: 'project',
        items: [
          for (final p in CompetitorService.instance.all)
            if (!exclude.contains(p.id)) p,
        ],
        keyOf: (p) => p.id,
        titleOf: (p) => '${p.code} · ${p.name}',
        subtitleOf: (p) => [p.builder, p.placeLabel]
            .where((s) => s.trim().isNotEmpty)
            .join(' · '),
        matches: (p, q) =>
            p.code.toLowerCase().contains(q) ||
            p.name.toLowerCase().contains(q) ||
            p.builder.toLowerCase().contains(q) ||
            p.village.toLowerCase().contains(q),
      ),
    ) ??
    const [];

class _MultiPickerDialog<T> extends StatefulWidget {
  final String title;
  final String hint;
  final String noun;
  final List<T> items;
  final String Function(T) keyOf;
  final String Function(T) titleOf;
  final String Function(T) subtitleOf;
  final bool Function(T, String) matches;

  const _MultiPickerDialog({
    super.key,
    required this.title,
    required this.hint,
    required this.noun,
    required this.items,
    required this.keyOf,
    required this.titleOf,
    required this.subtitleOf,
    required this.matches,
  });

  @override
  State<_MultiPickerDialog<T>> createState() => _MultiPickerDialogState<T>();
}

class _MultiPickerDialogState<T> extends State<_MultiPickerDialog<T>> {
  String _q = '';
  final Set<String> _picked = {};

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = [
      for (final i in widget.items)
        if (q.isEmpty || widget.matches(i, q)) i,
    ];
    final n = _picked.length;
    return AlertDialog(
      insetPadding: fomraDialogInset(context),
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        height: 460,
        child: Column(children: [
          TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: widget.hint,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(
                        widget.items.isEmpty
                            ? 'Already linked to everything.'
                            : 'Nothing matches.',
                        style: TextStyle(color: context.fomraTextSecondary)))
                : ListView.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final item = shown[i];
                      final key = widget.keyOf(item);
                      final sub = widget.subtitleOf(item);
                      return CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _picked.contains(key),
                        title: Text(widget.titleOf(item)),
                        subtitle: sub.isEmpty ? null : Text(sub),
                        onChanged: (v) => setState(
                            () => v == true ? _picked.add(key) : _picked.remove(key)),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: n == 0
              ? null
              : () => Navigator.of(context).pop([
                    for (final i in widget.items)
                      if (_picked.contains(widget.keyOf(i))) i,
                  ]),
          child: Text(n == 0
              ? 'Link'
              : 'Link $n ${widget.noun}${n == 1 ? '' : 's'}'),
        ),
      ],
    );
  }
}

/// Add or edit one sales contact. Returns the contact (null: cancelled).
Future<CompetitorContact?> showContactDialog(
  BuildContext context, {
  CompetitorContact? existing,
}) =>
    showFomraDialog<CompetitorContact>(
      context: context,
      builder: (_) => _ContactDialog(existing: existing),
    );

class _ContactDialog extends StatefulWidget {
  final CompetitorContact? existing;
  const _ContactDialog({this.existing});

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late CompetitorContactRole _role =
      widget.existing?.role ?? CompetitorContactRole.sales;
  late bool _main = widget.existing?.isMain ?? false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty && _phone.text.trim().isEmpty) {
      AppFeedback.warning(context, 'Type a name or a phone number.');
      return;
    }
    Navigator.of(context).pop(CompetitorContact(
      id: widget.existing?.id ?? '',
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      role: _role,
      isMain: _main,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: fomraDialogInset(context),
      title: Text(widget.existing == null ? 'Add sales contact' : 'Edit contact'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppFormField(controller: _name, label: 'Name', autofocus: true),
              const SizedBox(height: 12),
              AppFormField(
                  controller: _phone,
                  label: 'Phone',
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              DropdownButtonFormField<CompetitorContactRole>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  for (final r in CompetitorContactRole.values)
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: (r) => setState(() => _role = r ?? _role),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _main,
                onChanged: (v) => setState(() => _main = v ?? false),
                title: const Text('Main contact'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FormActionBar(
          submitLabel: 'Save',
          onSubmit: _save,
          onCancel: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
