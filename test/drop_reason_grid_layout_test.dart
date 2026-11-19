import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fomra_ls/models/lead_drop_reason.dart';
import 'package:fomra_ls/widgets/drop_reason_catalog_grid.dart';

const _reasons = [
  LeadDropReason(id: 'a', label: 'Alpha'),
  LeadDropReason(id: 'b', label: 'Bravo'),
  LeadDropReason(id: 'c', label: 'Charlie'),
];

Future<void> _pumpAt(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: DropReasonCatalogGrid(
        reasons: _reasons,
        onReorder: (_, __) {},
        onEdit: (_) {},
        onDelete: (_) {},
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Cards sharing a top edge are on the same row.
int _columns(WidgetTester tester) {
  final tops = tester
      .widgetList<SizedBox>(find.descendant(
        of: find.byType(Wrap),
        matching: find.byType(SizedBox),
      ))
      .toList();
  // Count how many cards sit on the first row by comparing their y offsets.
  final cards = find.byType(DragTarget<int>);
  final firstTop = tester.getTopLeft(cards.first).dy;
  var count = 0;
  for (var i = 0; i < tops.length && i < _reasons.length; i++) {
    if (tester.getTopLeft(cards.at(i)).dy == firstTop) count++;
  }
  return count;
}

void main() {
  testWidgets('desktop shows 3 columns', (tester) async {
    await _pumpAt(tester, 1200);
    expect(_columns(tester), 3);
  });

  testWidgets('tablet shows 2 columns', (tester) async {
    await _pumpAt(tester, 800);
    expect(_columns(tester), 2);
  });

  testWidgets('mobile shows 1 column', (tester) async {
    await _pumpAt(tester, 420);
    expect(_columns(tester), 1);
  });

  testWidgets('each card shows title, slug, edit, hide and a drag handle',
      (tester) async {
    await _pumpAt(tester, 1200);

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('a'), findsOneWidget); // slug
    expect(find.byIcon(Icons.label_off_outlined), findsNWidgets(3));
    expect(find.byIcon(Icons.edit_outlined), findsNWidgets(3));
    expect(find.byIcon(Icons.visibility_off_outlined), findsNWidgets(3));
    expect(find.byIcon(Icons.drag_indicator_rounded), findsNWidgets(3));
  });
}
