import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';
import 'add_lead_ui.dart';
import 'crore_lakh_field.dart';

// ── Configurable deal type definitions ─────────────────────────────────────────

enum DealFieldType { text, dropdown }

class DealFieldConfig {
  final String id;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final int maxLines;
  final DealFieldType type;
  final List<String> options;

  const DealFieldConfig({
    required this.id,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.type = DealFieldType.text,
    this.options = const [],
  });
}

class DealTypeConfig {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final List<DealFieldConfig> fields;

  const DealTypeConfig({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.fields,
  });
}

/// Static registry — extend here to add future deal types. Each Term shows
/// only its own fields; there is no subtype selection.
const kDealTypeConfigs = <DealTypeConfig>[
  DealTypeConfig(
    id: 'outright_purchase',
    title: 'Outright Purchase',
    description: 'Direct land acquisition with defined payment structure',
    icon: Icons.currency_rupee_rounded,
    fields: [
      DealFieldConfig(
        id: 'rate_per_acre',
        label: 'Rate per Acre',
        hint: 'e.g. ₹50,00,000',
        icon: Icons.payments_outlined,
        keyboardType: TextInputType.number,
      ),
    ],
  ),
  DealTypeConfig(
    id: 'joint_venture',
    title: 'Joint Venture',
    description: 'Partnership-based development with shared returns',
    icon: Icons.handshake_rounded,
    fields: [
      DealFieldConfig(
        id: 'advance_amount',
        label: 'Advance Amount',
        hint: 'e.g. ₹10,00,000',
        icon: Icons.account_balance_wallet_outlined,
        keyboardType: TextInputType.number,
      ),
      DealFieldConfig(
        id: 'advance_type',
        label: 'Advance Type',
        hint: 'Select advance type',
        icon: Icons.swap_horiz_rounded,
        type: DealFieldType.dropdown,
        options: ['Free Money', 'Refundable'],
      ),
      DealFieldConfig(
        id: 'sharing_ratio',
        label: 'Sharing Ratio',
        hint: 'e.g. 50:50',
        icon: Icons.pie_chart_outline_rounded,
      ),
    ],
  ),
  DealTypeConfig(
    id: 'marketing',
    title: 'Marketing',
    description: 'Sales and marketing engagement for the land parcel',
    icon: Icons.campaign_rounded,
    fields: [
      DealFieldConfig(
        id: 'number_of_plots',
        label: 'Number of Plots',
        hint: 'e.g. 24',
        icon: Icons.grid_view_rounded,
        keyboardType: TextInputType.number,
      ),
      DealFieldConfig(
        id: 'total_saleable_area',
        label: 'Total Saleable Area',
        hint: 'e.g. 12,000 sq ft',
        icon: Icons.straighten_rounded,
      ),
      DealFieldConfig(
        id: 'advance_amount',
        label: 'Advance Amount',
        hint: 'e.g. ₹5,00,000',
        icon: Icons.account_balance_wallet_outlined,
        keyboardType: TextInputType.number,
      ),
      DealFieldConfig(
        id: 'time_period',
        label: 'Time Period',
        hint: 'e.g. 6 months',
        icon: Icons.date_range_outlined,
      ),
    ],
  ),
  DealTypeConfig(
    id: 'deferred_payment',
    title: 'Deferred Payment',
    description: 'Structured payment plan over time',
    icon: Icons.schedule_rounded,
    fields: [
      DealFieldConfig(
        id: 'advance_amount',
        label: 'Advance Amount',
        hint: 'e.g. ₹5,00,000',
        icon: Icons.savings_outlined,
        keyboardType: TextInputType.number,
      ),
      DealFieldConfig(
        id: 'time_period',
        label: 'Time Period',
        hint: 'e.g. 12 months',
        icon: Icons.timelapse_rounded,
      ),
      DealFieldConfig(
        id: 'rate_per_acre',
        label: 'Rate per Acre',
        hint: 'e.g. ₹50,00,000',
        icon: Icons.payments_outlined,
        keyboardType: TextInputType.number,
      ),
    ],
  ),
  // "Others" was removed as a selectable Term. Leads saved against it still
  // resolve via _kLegacyPrimaryMap below.
];

const _kFieldMotion = Duration(milliseconds: 260);

/// Maps legacy primary/subtype terms saved before this redesign to current
/// deal titles, so older records still resolve to a known Term.
const _kLegacyPrimaryMap = <String, String>{
  'Outrate': 'Outright Purchase',
  'Outright Purchase': 'Outright Purchase',
  'Joint Venture': 'Joint Venture',
  'Marketing': 'Marketing',
  'Deferred Payment': 'Deferred Payment',
  'Others': 'Others',
};

DealTypeConfig? dealConfigByTitle(String title) {
  for (final c in kDealTypeConfigs) {
    if (c.title == title) return c;
  }
  return null;
}

// ── Serialization (maps to LandLead.accessDetails) ─────────────────────────────

String serializeTermsDeal({
  required String? primaryTitle,
  required Map<String, Map<String, String>> fieldValuesByDeal,
}) {
  if (primaryTitle == null || primaryTitle.isEmpty) return '';

  final buf = StringBuffer();
  buf.writeln(primaryTitle);

  final config = dealConfigByTitle(primaryTitle);
  if (config != null) {
    final values = fieldValuesByDeal[config.id] ?? {};
    for (final field in config.fields) {
      final v = (values[field.id] ?? '').trim();
      if (v.isNotEmpty) {
        buf.writeln('${field.label}: $v');
      }
    }
  }

  return buf.toString().trim();
}

({String? primary, Map<String, Map<String, String>> fields}) parseTermsDeal(
    String? raw) {
  final fieldValues = <String, Map<String, String>>{};
  for (final c in kDealTypeConfigs) {
    fieldValues[c.id] = {};
  }

  if (raw == null || raw.trim().isEmpty) {
    return (primary: null, fields: fieldValues);
  }

  final lines = raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
  final lineList = lines.toList();
  if (lineList.isEmpty) {
    return (primary: null, fields: fieldValues);
  }

  String? primary;

  // Legacy records may have stored "Title | Subtype" or "Title > Subtype" on
  // the first line — the subtype half is discarded, only the Term survives.
  final first = lineList.first;
  if (first.contains('|')) {
    primary = first.split('|').first.trim();
  } else if (first.contains(' > ')) {
    primary = first.split(' > ').first.trim();
  } else {
    primary = first;
  }
  primary = _kLegacyPrimaryMap[primary] ?? primary;

  final config = dealConfigByTitle(primary);
  if (config != null) {
    final labelToId = {for (final f in config.fields) f.label: f.id};
    for (var i = 1; i < lineList.length; i++) {
      final line = lineList[i];
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final label = line.substring(0, colon).trim();
      final value = line.substring(colon + 1).trim();
      final id = labelToId[label];
      if (id != null) {
        fieldValues[config.id]![id] = value;
      }
    }
  }

  return (primary: primary, fields: fieldValues);
}

// ── Widget ────────────────────────────────────────────────────────────────────

class TermsDealSelector extends StatefulWidget {
  /// Serialized value stored in [LandLead.accessDetails].
  final String? value;
  final ValueChanged<String?> onChanged;

  const TermsDealSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<TermsDealSelector> createState() => _TermsDealSelectorState();
}

class _TermsDealSelectorState extends State<TermsDealSelector> {
  String? _primaryTitle;
  final Map<String, Map<String, TextEditingController>> _controllers = {};

  @override
  void initState() {
    super.initState();
    _initControllers();
    _hydrateFromValue(widget.value);
  }

  @override
  void didUpdateWidget(TermsDealSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && widget.value != _serialize()) {
      _hydrateFromValue(widget.value);
    }
  }

  void _initControllers() {
    for (final config in kDealTypeConfigs) {
      _controllers[config.id] = {
        for (final field in config.fields)
          field.id: TextEditingController(),
      };
    }
  }

  void _hydrateFromValue(String? raw) {
    final parsed = parseTermsDeal(raw);
    _primaryTitle = parsed.primary;

    for (final config in kDealTypeConfigs) {
      final values = parsed.fields[config.id] ?? {};
      for (final field in config.fields) {
        _controllers[config.id]![field.id]!.text = values[field.id] ?? '';
      }
    }
  }

  @override
  void dispose() {
    for (final dealCtrls in _controllers.values) {
      for (final c in dealCtrls.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  String _serialize() => serializeTermsDeal(
        primaryTitle: _primaryTitle,
        fieldValuesByDeal: {
          for (final config in kDealTypeConfigs)
            config.id: {
              for (final field in config.fields)
                field.id: _controllers[config.id]![field.id]!.text,
            },
        },
      );

  void _emitChange() => widget.onChanged(_serialize().isEmpty ? null : _serialize());

  DealTypeConfig? get _activeConfig =>
      _primaryTitle == null ? null : dealConfigByTitle(_primaryTitle!);

  void _selectPrimary(String? title) {
    setState(() => _primaryTitle = title);
    _emitChange();
  }

  @override
  Widget build(BuildContext context) {
    final activeConfig = _activeConfig;
    final iconColor = Theme.of(context).brightness == Brightness.dark
        ? AppColors.primaryLight
        : AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _primaryTitle,
          onChanged: _selectPrimary,
          menuMaxHeight: 320,
          borderRadius: BorderRadius.circular(AddLeadUi.fieldRadius),
          decoration: addLeadInputDecoration(
            context,
            label: 'Term',
            hint: 'Select term',
            icon: Icons.handshake_outlined,
          ),
          items: kDealTypeConfigs
              .map(
                (config) => DropdownMenuItem(
                  value: config.title,
                  child: addLeadDropdownRow(
                    icon: config.icon,
                    label: config.title,
                    iconColor: iconColor,
                  ),
                ),
              )
              .toList(),
        ),
        AnimatedSwitcher(
          duration: _kFieldMotion,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slide, child: child),
            );
          },
          child: activeConfig != null
              ? _DealFieldsPanel(
                  key: ValueKey(activeConfig.id),
                  config: activeConfig,
                  controllers: _controllers[activeConfig.id]!,
                  onFieldChanged: _emitChange,
                )
              : const SizedBox.shrink(key: ValueKey('no_fields')),
        ),
      ],
    );
  }
}

// ── Dynamic fields panel ──────────────────────────────────────────────────────

class _DealFieldsPanel extends StatelessWidget {
  final DealTypeConfig config;
  final Map<String, TextEditingController> controllers;
  final VoidCallback onFieldChanged;

  const _DealFieldsPanel({
    super.key,
    required this.config,
    required this.controllers,
    required this.onFieldChanged,
  });

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final fields = config.fields;

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 16,
                color: context.fomraTextSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Deal Details',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.fomraTextSecondary,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (wide && fields.length > 1)
            ..._pairFields(context, fields)
          else
            ...fields.map(
              (field) => Padding(
                padding: const EdgeInsets.only(bottom: AddLeadUi.fieldGap),
                child: _DealField(
                  field: field,
                  controller: controllers[field.id]!,
                  onChanged: onFieldChanged,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _pairFields(BuildContext context, List<DealFieldConfig> fields) {
    final rows = <Widget>[];
    for (var i = 0; i < fields.length; i += 2) {
      final left = fields[i];
      final right = i + 1 < fields.length ? fields[i + 1] : null;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AddLeadUi.fieldGap),
          child: addLeadFormRow(
            context,
            _DealField(
              field: left,
              controller: controllers[left.id]!,
              onChanged: onFieldChanged,
            ),
            right != null
                ? _DealField(
                    field: right,
                    controller: controllers[right.id]!,
                    onChanged: onFieldChanged,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      );
    }
    return rows;
  }
}

class _DealField extends StatelessWidget {
  final DealFieldConfig field;
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _DealField({
    required this.field,
    required this.controller,
    required this.onChanged,
  });

  /// Amounts typed as Crores + Lakhs rather than one long number.
  static const _moneyFields = {'rate_per_acre', 'advance_amount'};

  @override
  Widget build(BuildContext context) {
    if (_moneyFields.contains(field.id)) {
      return CroreLakhField(
        label: field.label,
        controller: controller,
        onChanged: onChanged,
        suffix: field.id == 'rate_per_acre' ? 'per acre' : '',
      );
    }
    if (field.type == DealFieldType.dropdown) {
      final iconColor = Theme.of(context).brightness == Brightness.dark
          ? AppColors.primaryLight
          : AppColors.primary;
      final currentValue = controller.text.isEmpty ? null : controller.text;
      return DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue:
            field.options.contains(currentValue) ? currentValue : null,
        borderRadius: BorderRadius.circular(AddLeadUi.fieldRadius),
        decoration: addLeadInputDecoration(
          context,
          label: field.label,
          hint: field.hint,
          icon: field.icon,
        ),
        items: field.options
            .map(
              (o) => DropdownMenuItem(
                value: o,
                child: addLeadDropdownRow(
                  icon: field.icon,
                  label: o,
                  iconColor: iconColor,
                ),
              ),
            )
            .toList(),
        onChanged: (v) {
          controller.text = v ?? '';
          onChanged();
        },
      );
    }

    return TextFormField(
      controller: controller,
      maxLines: field.maxLines,
      keyboardType: field.keyboardType,
      onChanged: (_) => onChanged(),
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: context.fomraTextPrimary,
      ),
      decoration: addLeadInputDecoration(
        context,
        label: field.label,
        hint: field.hint,
        icon: field.icon,
        maxLines: field.maxLines,
      ),
    );
  }
}
