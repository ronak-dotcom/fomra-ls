import 'package:flutter/material.dart';

import '../models/land_lead.dart';
import '../models/owner_profile.dart';
import '../services/app_store.dart';
import '../services/land_lead_service.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';
import 'ui/app_feedback.dart';

/// The owner-profile pickers: owner type (choice chips), what exactly they do,
/// where they live (locality / village and town / city, typed) and who
/// decides on selling. Used in the meeting form and the lead page's edit
/// dialog. [initial] seeds the text boxes; every change is reported through
/// [onChanged].
class OwnerProfileFields extends StatefulWidget {
  final OwnerProfileValues initial;
  final ValueChanged<OwnerProfileValues> onChanged;

  /// Shown under the type chips when the type is required but missing.
  final String? typeError;

  const OwnerProfileFields({
    super.key,
    required this.initial,
    required this.onChanged,
    this.typeError,
  });

  @override
  State<OwnerProfileFields> createState() => _OwnerProfileFieldsState();
}

class _OwnerProfileFieldsState extends State<OwnerProfileFields> {
  late OwnerProfileValues _v = widget.initial;
  late final _profession = TextEditingController(text: _v.profession);
  late final _lives = TextEditingController(text: _v.lives);
  late final _town = TextEditingController(text: _v.town);

  @override
  void dispose() {
    _profession.dispose();
    _lives.dispose();
    _town.dispose();
    super.dispose();
  }

  void _set(OwnerProfileValues v) {
    setState(() => _v = v);
    widget.onChanged(v);
  }

  InputDecoration _dec(String label, {String? helper}) => InputDecoration(
        labelText: label,
        helperText: helper,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  @override
  Widget build(BuildContext context) {
    final label = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: context.fomraTextSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Owner is a…', style: label),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (v, _) in OwnerProfile.types)
            ChoiceChip(
              label: Text(OwnerProfile.typeShort(v),
                  style: const TextStyle(fontSize: 12)),
              selected: _v.type == v,
              selectedColor: AppColors.gold.withValues(alpha: 0.22),
              onSelected: (on) => _set(_v.copyWith(type: on ? v : '')),
            ),
        ]),
        if (widget.typeError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(widget.typeError!,
                style: const TextStyle(fontSize: 12, color: AppColors.error)),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _profession,
          textCapitalization: TextCapitalization.sentences,
          decoration: _dec('What exactly does the owner do? (optional)',
              helper: 'e.g. Runs a rice mill in Arakkonam'),
          onChanged: (t) => _set(_v.copyWith(profession: t.trim())),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _lives,
          textCapitalization: TextCapitalization.words,
          decoration: _dec('Lives at — locality / village (optional)',
              helper: 'Area or village, not just the city'),
          onChanged: (t) => _set(_v.copyWith(lives: t.trim())),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _town,
          textCapitalization: TextCapitalization.words,
          decoration: _dec('Town / city (optional)'),
          onChanged: (t) => _set(_v.copyWith(town: t.trim())),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: OwnerProfile.decisionOptions.any((o) => o.$1 == _v.decision)
              ? _v.decision
              : null,
          isExpanded: true,
          decoration: _dec('Who decides on selling (optional)'),
          items: [
            for (final (v, l) in OwnerProfile.decisionOptions)
              DropdownMenuItem(value: v, child: Text(l)),
          ],
          onChanged: (v) => _set(_v.copyWith(decision: v ?? '')),
        ),
      ],
    );
  }
}

/// Lead page: the owner profile at a glance ("Business / Trader · Runs a rice
/// mill · Lives at Velachery, Chennai · Family decides together") with an
/// edit button. Shows a prompt when nothing is recorded yet.
class OwnerProfileStrip extends StatelessWidget {
  final LandLead lead;
  final bool canEdit;
  final ValueChanged<LandLead>? onSaved;

  const OwnerProfileStrip({
    super.key,
    required this.lead,
    this.canEdit = true,
    this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    final v = OwnerProfileValues.of(lead);
    final parts = [
      if (v.profession.isNotEmpty) v.profession,
      if (v.livesAt.isNotEmpty) 'Lives at ${v.livesAt}',
      if (v.decision.isNotEmpty) OwnerProfile.decisionLabel(v.decision),
    ];
    final empty = v.type.isEmpty && parts.isEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: empty
            ? context.fomraSurfaceVar
            : AppColors.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: empty
                ? context.fomraBorder
                : AppColors.gold.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(Icons.badge_outlined,
            size: 20,
            color: empty ? context.fomraTextTertiary : AppColors.gold),
        const SizedBox(width: 10),
        Expanded(
          child: empty
              ? Text(
                  'Owner profile not recorded yet — it is asked when a Land '
                  'Owner meeting is logged.',
                  style: TextStyle(
                      fontSize: 12.5, color: context.fomraTextSecondary),
                )
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('OWNER',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: context.fomraTextTertiary,
                        )),
                    if (v.type.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(OwnerProfile.typeLabel(v.type),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: context.fomraTextPrimary,
                            )),
                      ),
                    for (final p in parts)
                      Text('· $p',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: context.fomraTextSecondary,
                          )),
                  ],
                ),
        ),
        if (canEdit)
          IconButton(
            tooltip: 'Edit owner profile',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => editOwnerProfile(context, lead, onSaved: onSaved),
          ),
      ]),
    );
  }
}

/// Saves [v] on the lead and in the store (profile fields only).
Future<LandLead> saveOwnerProfile(LandLead lead, OwnerProfileValues v) async {
  await LandLeadService.updateOwnerProfile(lead.leadId, v);
  AppStore.instance.patchOwnerProfile(lead.leadId, v);
  return v.applyTo(lead);
}

/// Dialog to correct a lead's owner profile; saves and updates the store.
Future<void> editOwnerProfile(BuildContext context, LandLead lead,
    {ValueChanged<LandLead>? onSaved}) async {
  var values = OwnerProfileValues.of(lead);
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Owner profile'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: OwnerProfileFields(
            initial: values,
            onChanged: (v) => values = v,
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save')),
      ],
    ),
  );
  if (saved != true || !context.mounted) return;
  try {
    final updated = await saveOwnerProfile(lead, values);
    onSaved?.call(updated);
    if (context.mounted) AppFeedback.success(context, 'Owner profile saved');
  } catch (e) {
    if (context.mounted) {
      AppFeedback.error(context, 'Could not save owner profile: $e');
    }
  }
}
