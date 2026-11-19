import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fomra_ls/models/lead_drop_reason.dart';
import 'package:fomra_ls/services/lead_drop_reason_catalog_service.dart';

final _catalog = LeadDropReasonCatalogService.instance;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await _catalog.setItems(const [
      LeadDropReason(id: 'a', label: 'Alpha'),
      LeadDropReason(id: 'b', label: 'Bravo'),
      LeadDropReason(id: 'c', label: 'Charlie'),
    ]);
  });

  test('a hidden reason leaves the drop form but still names old leads',
      () async {
    await _catalog.setActive('b', false);
    expect(_catalog.current.map((r) => r.label), ['Alpha', 'Charlie']);
    expect(_catalog.all.length, 3);
    expect(_catalog.displayLabelForRaw('Bravo'), 'Bravo');
    expect(_catalog.findByRaw('Bravo')?.id, 'b');
    await _catalog.setActive('b', true);
    expect(_catalog.current.length, 3);
  });

  test('reordering moves only offered reasons; hidden ones stay last',
      () async {
    await _catalog.setActive('a', false);
    await _catalog.reorder(1, 0); // Charlie above Bravo
    expect(_catalog.current.map((r) => r.label), ['Charlie', 'Bravo']);
    expect(_catalog.all.last.label, 'Alpha');
  });

  test('adding a reason that already exists is refused', () async {
    expect(() => _catalog.addReason('bravo'), throwsStateError);
    await _catalog.addReason('Road access blocked');
    expect(_catalog.current.last.label, 'Road access blocked');
    expect(_catalog.current.last.id, 'road_access_blocked');
  });
}
