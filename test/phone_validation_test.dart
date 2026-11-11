import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fomra_ls/utils/phone_validation.dart';

void main() {
  group('isValid — exactly 10 digits', () {
    test('accepts a 10-digit number', () {
      expect(PhoneValidation.isValid('9876543210'), isTrue);
    });

    test('rejects fewer than 10 digits', () {
      expect(PhoneValidation.isValid('98765'), isFalse);
      expect(PhoneValidation.isValid('123456789'), isFalse);
    });

    test('rejects more than 10 digits', () {
      expect(PhoneValidation.isValid('98765432101'), isFalse);
    });

    test('rejects alphabets', () {
      expect(PhoneValidation.isValid('98765abcde'), isFalse);
    });

    test('rejects symbols', () {
      expect(PhoneValidation.isValid('98765-4321'), isFalse);
      expect(PhoneValidation.isValid('+919876543'), isFalse);
    });

    test('rejects spaces', () {
      expect(PhoneValidation.isValid('98765 4321'), isFalse);
      expect(PhoneValidation.isValid('9876543210 '), isTrue,
          reason: 'trailing/leading space is trimmed, then 10 digits remain');
    });

    test('rejects empty', () {
      expect(PhoneValidation.isValid(''), isFalse);
      expect(PhoneValidation.isValid(null), isFalse);
    });
  });

  group('validator — inline messages', () {
    test('a required field rejects empty with a required message', () {
      final v = PhoneValidation.validator('Owner Number', required: true);
      expect(v(''), 'Owner Number is required');
      expect(v(null), 'Owner Number is required');
    });

    test('an optional field accepts empty', () {
      final v = PhoneValidation.validator('Broker Number', required: false);
      expect(v(''), isNull);
    });

    test('an optional field still rejects a partial number', () {
      final v = PhoneValidation.validator('Broker Number', required: false);
      expect(v('98765'), 'Enter a valid 10-digit Broker Number');
    });

    test('a full 10-digit number passes', () {
      final v = PhoneValidation.validator('Contact Number', required: true);
      expect(v('9876543210'), isNull);
    });

    test('the message names the field', () {
      expect(
        PhoneValidation.validator('Contact Number', required: true)('123'),
        'Enter a valid 10-digit Contact Number',
      );
      expect(
        PhoneValidation.validator('Broker Number', required: true)('123'),
        'Enter a valid 10-digit Broker Number',
      );
    });
  });

  group('mobile numbers start with 6-9 (no leading 0)', () {
    test('a leading 0 is not a valid mobile', () {
      expect(PhoneValidation.isValid('0917662544'), isFalse);
      expect(PhoneValidation.isValid('1234567890'), isFalse);
    });

    test('the message says why', () {
      expect(
        PhoneValidation.validator('Broker Number', required: true)('0917662544'),
        'Broker Number must start with 6, 7, 8 or 9 (no leading 0)',
      );
    });

    test('saved numbers that look wrong are flagged', () {
      expect(PhoneValidation.looksWrong('0917662544'), isTrue);
      expect(PhoneValidation.looksWrong('98413 09113'), isFalse);
      expect(PhoneValidation.looksWrong(''), isFalse);
    });
  });

  group('input formatter cleans as typed / pasted', () {
    String fmt(String typed) => PhoneValidation.inputFormatters.fold(
          TextEditingValue(text: typed),
          (v, f) => f.formatEditUpdate(TextEditingValue.empty, v),
        ).text;

    test('drops a leading 0', () {
      expect(fmt('0917662544'), '917662544');
      expect(fmt('09841309113'), '9841309113');
    });

    test('drops +91 from a pasted number', () {
      expect(fmt('+91 98413 09113'), '9841309113');
      expect(fmt('919841309113'), '9841309113');
    });

    test('blocks letters and symbols, caps at 10', () {
      expect(fmt('98a41-30 911399'), '9841309113');
    });
  });
}
