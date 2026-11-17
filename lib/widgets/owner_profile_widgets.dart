import 'package:flutter/material.dart';

import '../models/land_lead.dart';
import '../models/owner_profile.dart';
import '../services/app_store.dart';
import '../services/land_lead_service.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';
import 'ui/app_feedback.dart';

/// The three owner-profile pickers: owner type (choice chips), where they
/// live and who decides (dropdowns). Values are OwnerProfile keys; '' = not
/// chosen. Used in the meeting form and the lead page's edit dialog.
class OwnerProfileFields extends StatelessWidget {
  final String type;
  final String lives;
  final String decision;
  final ValueChanged<String> onType;
  final ValueChanged<String> onLives;
  final ValueChanged<String> onDecision;

  /// Shown under the type chips when the type is required but missing.
  final String? typeError;

  const OwnerProfileFields({
    super.key,
    required this.type,
    required this.lives,
    required this.decision,
    required this.onType,
    required this.onLives,
    required this.onDecision,
    this.typeError,
  });

  @override
  Widget build(BuildContext context) {
    TextStyle label() => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: context.fomraTextSecondary,
        );
    Widget dropdown(String hint, String value, List<(String, String)> options,
            ValueChanged<String> onChanged) =>
        DropdownButtonFormField<String>(
          initialValue: options.any((o) => o.$1 == value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: hint,
            isDense: true,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: [
            for (final (v, l) in options)
              DropdownMenuItem(value: v, child: Text(l)),
          ],
          onChanged: (v) => onChanged(v ?? ''),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Owner is a…', style: label()),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (v, _) in OwnerProfile.types)
            ChoiceChip(
              label: Text(OwnerProfile.typeShort(v),
                  style: const TextStyle(fontSize: 12)),
              selected: type == v,
              selectedColor: AppColors.gold.withValues(alpha: 0.22),
              onSelected: (on) => onType(on ? v : ''),
            ),
        ]),
        if (typeError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(typeError!,
                style: const TextStyle(fontSize: 12, color: AppColors.error)),
          ),
        const SizedBox(height: 12),
        dropdown('Lives (optional)', lives, OwnerProfile.livesOptions, onLives),
        const SizedBox(height: 10),
        dropdown('Who decides on selling (optional)', decision,
            OwnerProfile.decisionOptions, onDecision),
      ],
    );
  }
}

/// Lead page: the owner profile at a glance ("Farmer · In the village ·
/// Family decides together") with an edit button. Shows a prompt when
/// nothing is recorded yet.
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
    final type = lead.ownerOccupation.trim();
    final parts = [
      if (lead.ownerLives.trim().isNotEmpty)
        OwnerProfile.livesLabel(lead.ownerLives),
      if (lead.ownerDecision.trim().isNotEmpty)
        OwnerProfile.decisionLabel(lead.ownerDecision),
    ];
    final empty = type.isEmpty && parts.isEmpty;
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
                    if (type.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(OwnerProfile.typeLabel(type),
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

/// Dialog to correct a lead's owner profile; saves and updates the store.
Future<void> editOwnerProfile(BuildContext context, LandLead lead,
    {ValueChanged<LandLead>? onSaved}) async {
  var type = lead.ownerOccupation.trim();
  var lives = lead.ownerLives.trim();
  var decision = lead.ownerDecision.trim();
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Owner profile'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: OwnerProfileFields(
              type: type,
              lives: lives,
              decision: decision,
              onType: (v) => setState(() => type = v),
              onLives: (v) => setState(() => lives = v),
              onDecision: (v) => setState(() => decision = v),
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
    ),
  );
  if (saved != true || !context.mounted) return;
  try {
    await LandLeadService.updateOwnerProfile(lead.leadId,
        type: type, lives: lives, decision: decision);
    final updated = lead.copyWith(
        ownerOccupation: type, ownerLives: lives, ownerDecision: decision);
    AppStore.instance.replaceLead(updated);
    onSaved?.call(updated);
    if (context.mounted) AppFeedback.success(context, 'Owner profile saved');
  } catch (e) {
    if (context.mounted) {
      AppFeedback.error(context, 'Could not save owner profile: $e');
    }
  }
}
