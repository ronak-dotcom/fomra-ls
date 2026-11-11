import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/screens/land_lead/add_lead_screen.dart';
import 'package:fomra_ls/services/broker_directory.dart';

void main() {
  setUp(() => BrokerDirectory.instance.debugSeed(const [
        BrokerEntry(
          phone: '9841309113',
          displayName: 'Sebastin',
          aliases: ['sebastin', 'sabestin'],
        ),
      ]));

  Future<(TextEditingController, TextEditingController)> pump(
      WidgetTester t) async {
    final name = TextEditingController();
    final number = TextEditingController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BrokerSourceFields(nameCtrl: name, numberCtrl: number),
        ),
      ),
    ));
    return (name, number);
  }

  testWidgets('a known number fills and locks the broker name', (t) async {
    final (name, _) = await pump(t);
    await t.enterText(
        find.byKey(const ValueKey('broker-number')), '9841309113');
    await t.pump();
    expect(name.text, 'Sebastin');
    expect(find.textContaining('Known broker · Sebastin'), findsOneWidget);
    final field = t.widget<EditableText>(find.descendant(
        of: find.byKey(const ValueKey('broker-name')),
        matching: find.byType(EditableText)));
    expect(field.readOnly, isTrue);
  });

  testWidgets('typing a misspelt name suggests the known broker', (t) async {
    final (name, number) = await pump(t);
    await t.tap(find.byKey(const ValueKey('broker-name')));
    await t.enterText(find.byKey(const ValueKey('broker-name')), 'sabastin');
    await t.pump();
    final tile = find.byKey(const ValueKey('broker-suggestion-9841309113'));
    expect(tile, findsOneWidget);
    await t.tap(tile);
    await t.pump();
    expect(name.text, 'Sebastin');
    expect(number.text, '9841309113');
  });
}
