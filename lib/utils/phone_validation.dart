import 'package:flutter/services.dart';

/// Shared validation for the app's phone-number fields (owner, broker, contact).
/// An Indian mobile number: exactly 10 digits, starting with 6, 7, 8 or 9.
abstract final class PhoneValidation {
  /// Digits-only input, capped at 10 — blocks alphabets, symbols and spaces as
  /// they're typed. A leading 0 or +91 / 91 (as when a number is pasted from
  /// contacts) is dropped first, so the cap never cuts off the real number:
  /// "+91 98413 09113" → "9841309113", "09841309113" → "9841309113".
  static final inputFormatters = <TextInputFormatter>[
    const _IndianMobileFormatter(),
  ];

  static final _mobile = RegExp(r'^[6-9]\d{9}$');

  /// Whether [value] is a valid Indian mobile number: 10 digits starting with
  /// 6–9. A number starting with 0 is a slip (a leading 0 typed and the last
  /// digit dropped), so it is not valid.
  static bool isValid(String? value) => _mobile.hasMatch((value ?? '').trim());

  /// A form validator. A [required] field also rejects an empty value; an
  /// optional one accepts blank but still rejects a partial or wrong number.
  /// [label] names the field in the message.
  static String? Function(String?) validator(String label, {required bool required}) {
    return (value) {
      final v = (value ?? '').trim();
      if (v.isEmpty) return required ? '$label is required' : null;
      if (v.length == 10 && !RegExp(r'^[6-9]').hasMatch(v)) {
        return '$label must start with 6, 7, 8 or 9 (no leading 0)';
      }
      if (!isValid(v)) return 'Enter a valid 10-digit $label';
      return null;
    };
  }

  /// For numbers already saved: a non-empty number that isn't a valid mobile
  /// (e.g. "0917662544", a digit lost to a leading 0) — shown as a warning
  /// so someone corrects it.
  static bool looksWrong(String? value) {
    final v = (value ?? '').trim();
    return v.isNotEmpty && !isValid(v.replaceAll(RegExp(r'[\s-]'), ''));
  }
}

class _IndianMobileFormatter extends TextInputFormatter {
  const _IndianMobileFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    // Pasted "+91 9841309113" / "919841309113": drop the country code.
    if (digits.length > 10 && digits.startsWith('91')) {
      digits = digits.substring(2);
    }
    // A mobile never starts with 0: drop leading zeros as they're typed.
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
    if (digits.length > 10) digits = digits.substring(0, 10);
    if (digits == newValue.text) return newValue;
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
