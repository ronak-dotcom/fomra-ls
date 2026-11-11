import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/services/report_catalog_service.dart';
import 'package:fomra_ls/screens/reports/report_viewer_screen.dart';

void main() {
  final data = ReportPreviewData(
    generatedAt: DateTime(2026, 11, 11, 10),
    summary: const [(label: 'Brokers', value: '60')],
    sections: [
      ReportPreviewSection(
        title: 'Broker Performance · Lifetime',
        headers: const ['Broker', 'Lands'],
        rows: [
          for (var i = 0; i < 60; i++) ['Broker $i', '${60 - i}'],
        ],
      ),
    ],
  );

  testWidgets('opens to view every row; download only when asked',
      (t) async {
    t.view.physicalSize = const Size(1200, 2600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: ReportViewerScreen(
        kind: ReportKind.broker,
        leads: const [],
        debugData: data,
      ),
    ));
    await t.pump();

    // Viewing first: the report is on screen, 50 rows then "Show more".
    expect(find.text('Broker Performance · Lifetime · 60'), findsOneWidget);
    expect(find.text('Broker 0'), findsOneWidget);
    expect(find.text('Show more (10 left)'), findsOneWidget);

    // Search narrows the table.
    await t.enterText(find.byType(TextField), 'Broker 59');
    await t.pump();
    expect(find.text('1 match'), findsOneWidget);

    // Download asks for the format; nothing is saved before that.
    await t.tap(find.text('Download'));
    await t.pumpAndSettle();
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('Excel'), findsOneWidget);
  });
}
