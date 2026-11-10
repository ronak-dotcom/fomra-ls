import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/widgets/land_workspace_ui.dart';

Future<void> _openPanel(WidgetTester t, {required bool showReviewStatus}) async {
  t.view.physicalSize = const Size(1200, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showLandWorkspaceFilterPanel(
              context: context,
              initial: LandWorkspaceFilters(),
              showReviewStatus: showReviewStatus,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('review section is offered as compact chips on normal lists',
      (t) async {
    await _openPanel(t, showReviewStatus: true);
    await t.scrollUntilVisible(find.text('Property Review'), 300,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Property Review'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Overdue'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Upcoming'), findsOneWidget);
  });

  testWidgets('review section is hidden on review-status lists', (t) async {
    await _openPanel(t, showReviewStatus: false);
    expect(find.text('Property Review'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Upcoming'), findsNothing);
    // The rest of the panel is still there.
    expect(find.text('Lead Status'), findsOneWidget);
  });
}
