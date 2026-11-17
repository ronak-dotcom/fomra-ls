import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';

/// Rupee amounts as typed in crores and lakhs.
abstract final class CroreLakh {
  static const _crore = 10000000;
  static const _lakh = 100000;

  /// Reads a saved amount into (crores, lakhs). Understands what the app
  /// writes ("₹7.50 Cr", "₹50 L") and clear older entries ("3.5 cr per
  /// acre", "75000000"). Returns null when it can't tell (e.g. "4.5" with no
  /// unit, or a note) — the caller then leaves the old text as it was.
  static (int, int)? parse(String raw) {
    final t = raw.trim().toLowerCase().replaceAll(',', '');
    if (t.isEmpty) return null;
    final cr = RegExp(r'([\d.]+)\s*(cr|crore)').firstMatch(t);
    final lk = RegExp(r'([\d.]+)\s*(l\b|lakh|lac)').firstMatch(t);
    if (cr != null || lk != null) {
      final rupees = (double.tryParse(cr?.group(1) ?? '') ?? 0) * _crore +
          (double.tryParse(lk?.group(1) ?? '') ?? 0) * _lakh;
      return fromRupees(rupees.round());
    }
    final plain = double.tryParse(t.replaceAll('₹', '').trim());
    if (plain != null && plain >= _lakh) return fromRupees(plain.round());
    return null;
  }

  static (int, int) fromRupees(int rupees) =>
      (rupees ~/ _crore, ((rupees % _crore) / _lakh).round());

  static int rupees(int crores, int lakhs) => crores * _crore + lakhs * _lakh;

  /// "₹7.50 Cr", "₹5 Cr", "₹50 L" — what is saved and shown.
  static String format(int crores, int lakhs) {
    if (crores == 0 && lakhs == 0) return '';
    if (crores == 0) return '₹$lakhs L';
    if (lakhs == 0) return '₹$crores Cr';
    return '₹$crores.${lakhs.toString().padLeft(2, '0')} Cr';
  }

  /// Indian digit grouping: 75000000 → "7,50,00,000".
  static String grouped(int rupees) {
    final s = rupees.toString();
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$last3';
  }
}

/// Two typed boxes — Crores and Lakhs (optional) — for a rupee amount, with
/// the total shown live ("= ₹7.50 Cr per acre (₹7,50,00,000)"). Reads and
/// writes [controller] in [CroreLakh.format] form. An older entry it can't
/// read is kept untouched and shown as "Earlier entry: …" until retyped.
class CroreLakhField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;

  /// Appended to the total, e.g. "per acre".
  final String suffix;

  const CroreLakhField({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
    this.suffix = '',
  });

  @override
  State<CroreLakhField> createState() => _CroreLakhFieldState();
}

class _CroreLakhFieldState extends State<CroreLakhField> {
  final _cr = TextEditingController();
  final _lk = TextEditingController();
  String? _earlier;

  @override
  void initState() {
    super.initState();
    _load();
    widget.controller.addListener(_onExternal);
  }

  void _load() {
    final raw = widget.controller.text.trim();
    final parsed = CroreLakh.parse(raw);
    if (parsed == null) {
      _earlier = raw.isEmpty ? null : raw;
      _cr.text = '';
      _lk.text = '';
    } else {
      _earlier = null;
      _cr.text = parsed.$1 == 0 ? '' : '${parsed.$1}';
      _lk.text = parsed.$2 == 0 ? '' : '${parsed.$2}';
    }
  }

  String get _current => CroreLakh.format(
      int.tryParse(_cr.text) ?? 0, int.tryParse(_lk.text) ?? 0);

  // The form reloaded the value (e.g. editing another lead).
  void _onExternal() {
    if (widget.controller.text == _current) return;
    if (_earlier != null && widget.controller.text == _earlier) return;
    setState(_load);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExternal);
    _cr.dispose();
    _lk.dispose();
    super.dispose();
  }

  void _changed() {
    final value = _current;
    if (value.isEmpty && _earlier != null) {
      // Boxes cleared: keep the earlier entry rather than wiping it.
      widget.controller.text = _earlier!;
    } else {
      _earlier = value.isEmpty ? _earlier : null;
      widget.controller.text = value;
    }
    setState(() {});
    widget.onChanged();
  }

  InputDecoration _dec(String label, String unit) => InputDecoration(
        labelText: label,
        isDense: true,
        suffixText: unit,
        filled: true,
        fillColor: context.fomraSurfaceVar.withValues(alpha: 0.55),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  @override
  Widget build(BuildContext context) {
    final cr = int.tryParse(_cr.text) ?? 0;
    final lk = int.tryParse(_lk.text) ?? 0;
    final total = CroreLakh.rupees(cr, lk);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.fomraTextSecondary,
            )),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _cr,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: _dec('Crores', 'Cr'),
              onChanged: (_) => _changed(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _lk,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              decoration: _dec('Lakhs (optional)', 'L'),
              onChanged: (_) => _changed(),
            ),
          ),
        ]),
        if (total > 0) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '= ${CroreLakh.format(cr, lk)}'
              '${widget.suffix.isEmpty ? '' : ' ${widget.suffix}'}  '
              '(₹${CroreLakh.grouped(total)})',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.success,
              ),
            ),
          ),
        ] else if (_earlier != null) ...[
          const SizedBox(height: 6),
          Text('Earlier entry: $_earlier — type it above to update',
              style: TextStyle(
                  fontSize: 12, color: context.fomraTextSecondary)),
        ],
      ],
    );
  }
}
