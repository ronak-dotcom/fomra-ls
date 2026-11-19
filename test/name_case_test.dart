import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/utils/name_case.dart';

void main() {
  test('every word starts with a capital; the rest stays as typed', () {
    expect(capWords('mani'), 'Mani');
    expect(capWords('dinesh kumar'), 'Dinesh Kumar');
    expect(capWords('k.mani'), 'K.Mani');
    expect(capWords('kalaiarasi(maheshwari)'), 'Kalaiarasi(Maheshwari)');
    expect(capWords('ammanambakkam-1.5 acr'), 'Ammanambakkam-1.5 Acr');
    expect(capWords('Ammāpettai 2.20 Acre - mani'), 'Ammāpettai 2.20 Acre - Mani');
    expect(capWords('NRI McArthur'), 'NRI McArthur');
    expect(capWords('30ft road'), '30ft Road');
    expect(capWords(''), '');
  });

  test('an untouched saved value is kept as it was', () {
    expect(capWordsIfChanged('mani', 'mani'), 'mani');
    expect(capWordsIfChanged('mani k', 'mani'), 'Mani K');
    expect(capWordsIfChanged('ravi', null), 'Ravi');
  });
}
