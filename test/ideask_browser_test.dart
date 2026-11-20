import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'boards_harness.dart';

/// The Todo lens is the Ideask browser: one tree of folders, pages and
/// collections, with a folder's task list and a page opened above it. The
/// shell (rail / bottom bar) never leaves; Back walks the stack the reader
/// built.
void main() {
  testWidgets('the Ideask browser keeps its documents inside the Todo lens', (
    tester,
  ) async {
    // ---- Desktop ----
    await pumpBoardsApp(tester, const Size(1200, 800));
    await openBoardsTab(tester);

    // The slim rail marks the active lens by tooltip, not by index.
    expect(find.byType(NavigationRail), findsNothing);
    // The sidebar tree and the browser list both name the nodes.
    expect(find.text('Roadmap'), findsWidgets);
    expect(find.text('Chores'), findsWidgets);
    expect(find.text('Runbook'), findsWidgets);

    // Opening a folder happens in place: the browser shows its contents and a
    // breadcrumb, and the rail never moves.
    await tester.tap(find.text('Roadmap').last);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsNothing);
    // Inside the browser the empty folder replaces the sibling list; the
    // sidebar still names the workspace's folders.
    expect(find.text('No folders or pages here yet.'), findsOneWidget);
    // The breadcrumb carries the way back up.
    expect(find.text('Up one level'), findsNothing);

    // Back to the root through the breadcrumb.
    await tester.tap(find.text('Todo').first);
    await tester.pumpAndSettle();
    expect(find.text('Chores'), findsWidgets);

    // A folder's tasks are a pushed document: the browser stays below it.
    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Roadmap').last,
          matching: find.byType(ListTile),
        ),
        matching: find.byIcon(Symbols.task_alt),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Roadmap')),
      findsOneWidget,
    );
    expect(find.text('Task 1'), findsOneWidget);
    // A bare tile (no key stamp, no meta line) hugs its single title line.
    final bareTile = tester.getSize(
      find
          .ancestor(of: find.text('Task 6'), matching: find.byType(Material))
          .first,
    );
    expect(bareTile.height, lessThan(52));

    // A task's detail is a sheet: the list stays behind it.
    await tester.tap(find.text('Task 1'));
    await tester.pumpAndSettle();
    expect(find.text('Task details'), findsOneWidget);
    expect(find.text('Mark completed'), findsOneWidget);
    // The detail renders authored Markdown, not its raw markers.
    expect(find.textContaining('Bold', findRichText: true), findsWidgets);
    expect(find.textContaining('**Bold**', findRichText: true), findsNothing);
    expect(find.textContaining('emphasis', findRichText: true), findsWidgets);
    expect(find.textContaining('*emphasis*', findRichText: true), findsNothing);

    // The sheet carries its own close action.
    await tester.tap(find.byIcon(Symbols.close).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Task details'), findsNothing);

    // Back pops the lens' own stack: the browser comes back.
    await tester.tap(find.byIcon(Symbols.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Chores'), findsOneWidget);

    // A page is its own document, pushed above the browser.
    await tester.tap(find.text('Runbook').last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Runbook')),
      findsWidgets,
    );
    await tester.tap(find.byIcon(Symbols.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Roadmap'), findsWidgets);

    // ---- Phone ----
    await pumpBoardsApp(tester, const Size(400, 800));
    await openBoardsTab(tester);

    // The lens root keeps the shell's drawer.
    expect(_shellScaffold(tester).drawerEnableOpenDragGesture, isTrue);
    expect(find.text('Roadmap'), findsWidgets);

    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Roadmap').last,
          matching: find.byType(ListTile),
        ),
        matching: find.byIcon(Symbols.task_alt),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    // A pushed document owns the screen: the shell's bottom bar stays behind at
    // the lens root.
    expect(find.byType(NavigationBar), findsNothing);
    // It leads with Back so the reader can leave it.
    expect(find.byIcon(Symbols.arrow_back), findsOneWidget);
    expect(find.text('Task 1'), findsOneWidget);

    await tester.tap(find.byIcon(Symbols.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Chores'), findsWidgets);
    expect(find.byIcon(Symbols.arrow_back), findsNothing);
  });
}

Scaffold _shellScaffold(WidgetTester tester) =>
    tester.widget<Scaffold>(find.byType(Scaffold).first);
