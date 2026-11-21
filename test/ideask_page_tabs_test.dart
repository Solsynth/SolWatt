import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/shell/workspace_tabs.dart';
import 'package:solwatt/shell/workspace_title_bar.dart';

import 'boards_harness.dart';

/// A page is a document of the workspace strip, not a route pushed onto the
/// Todo lens: opening one grows a chip, the chip is the selected one, and
/// closing it returns the reader to the browser.
Finder _chip(String title) => find.descendant(
  of: find.byType(WorkspaceTitleBar),
  matching: find.text(title),
);

void main() {
  testWidgets('a page opens as a highlighted tab and closes back to the browser',
      (tester) async {
    await pumpBoardsApp(tester, const Size(1200, 800));
    await openBoardsTab(tester);

    final ctx = tester.element(find.byType(WorkspaceTitleBar));
    final container = ProviderScope.containerOf(ctx);
    WorkspaceTabState state() => container.read(workspaceTabsProvider);

    // Nothing open: the strip is not chrome.
    expect(state().tabs, isEmpty);

    await tester.tap(find.text('Runbook').last);
    await tester.pumpAndSettle();

    expect(state().tabs.map((t) => t.key), ['pages:page-1']);
    expect(state().activeKey, 'pages:page-1');
    expect(_chip('Runbook'), findsOneWidget);
    // The chip is the selected one: the raised surface, not the bare bar.
    expect(
      tester
          .widget<Material>(
            find.ancestor(
              of: _chip('Runbook'),
              matching: find.byType(Material),
            ).first,
          )
          .color,
      Theme.of(ctx).colorScheme.surface,
    );
    expect(find.byIcon(Symbols.arrow_back), findsOneWidget);
    // The page is a pane: the browser is gone while the page owns the canvas.
    expect(find.text('Roadmap'), findsNothing);

    // Back is the tab close: the browser comes back and the strip empties.
    await tester.tap(find.byIcon(Symbols.arrow_back));
    await tester.pumpAndSettle();
    expect(state().tabs, isEmpty);
    expect(find.text('Roadmap'), findsWidgets);

    // Selecting the tab again re-opens the same document: one tab, not a second.
    await tester.tap(find.text('Runbook').last);
    await tester.pumpAndSettle();
    expect(state().tabs, hasLength(1));

    await tester.tap(find.byTooltip('Close tab'));
    await tester.pumpAndSettle();
    expect(state().tabs, isEmpty);
    expect(find.text('Roadmap'), findsWidgets);
  });
}
