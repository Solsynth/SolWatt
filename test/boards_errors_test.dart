import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'boards_harness.dart';

void main() {
  testWidgets('a refused task create reports the reason the server gave', (
    tester,
  ) async {
    // Tall enough that the editor sheet's Save button sits inside the viewport.
    await pumpBoardsApp(
      tester,
      const Size(1200, 1000),
      client: RejectingTaskClient(),
    );
    await openBoardsTab(tester);
    await tester.tap(find.text('Roadmap'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Symbols.add_task));
    await tester.pumpAndSettle();
    // The sheet owns several fields and the board behind it keeps its search
    // box, so scope the name field to the sheet itself.
    await tester.enterText(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(TextField),
          )
          .first,
      'Ship the release',
    );
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    // Not pumpAndSettle: the snackbar dismisses itself after 1.5s, and settling
    // would advance the fake clock past the message.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(RejectingTaskClient.reason), findsOneWidget);
  });
}
