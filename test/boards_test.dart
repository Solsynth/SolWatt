import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart' as mui;

import 'boards_harness.dart';

void main() {
  testWidgets('a board opens inside the boards tab, not above the shell', (
    tester,
  ) async {
    // ---- Desktop ----
    await pumpBoardsApp(tester, const Size(1200, 800));
    await openBoardsTab(tester);

    final rail = find.byType(NavigationRail);
    expect(tester.widget<NavigationRail>(rail).selectedIndex, 1);
    expect(find.text('Roadmap'), findsOneWidget);
    expect(find.text('Chores'), findsOneWidget);

    // Open a board: it takes the tab's pane, it does not cover the shell.
    await tester.tap(find.text('Roadmap'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.widget<NavigationRail>(rail).selectedIndex, 1);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Roadmap')),
      findsOneWidget,
    );
    expect(find.text('RM'), findsOneWidget); // task prefix stamp
    expect(find.text('Ungrouped'), findsOneWidget);
    expect(find.text('Doing'), findsOneWidget);
    expect(find.text('Task 1'), findsOneWidget);
    // A bare tile (no key stamp, no meta line) hugs its single title line: the
    // floating actions must not pad it with an empty band under the title.
    final bareTile = tester.getSize(
      find
          .ancestor(of: find.text('Task 6'), matching: find.byType(Material))
          .first,
    );
    expect(bareTile.height, lessThan(52));

    // Wide screens keep the detail inline: tapping a card slides the panel in
    // beside the board instead of pushing a route.
    await tester.tap(find.text('Task 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Task details'), findsOneWidget);
    expect(find.text('Mark completed'), findsOneWidget);
    // The detail's body renders authored Markdown, not its raw markers.
    expect(find.textContaining('Bold', findRichText: true), findsWidgets);
    expect(find.textContaining('**Bold**', findRichText: true), findsNothing);
    expect(find.textContaining('emphasis', findRichText: true), findsWidgets);
    expect(find.textContaining('*emphasis*', findRichText: true), findsNothing);
    // Still the board's own route: the rail never moved.
    expect(find.byType(NavigationRail), findsOneWidget);

    // The panel's close button hands the board back.
    await tester.tap(find.byIcon(Symbols.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Task details'), findsNothing);

    // Back pops the tab's own stack: the list comes back, the rail never moved.
    await tester.tap(find.byIcon(Symbols.arrow_back));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Boards')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Roadmap')),
      findsNothing,
    );
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.widget<NavigationRail>(rail).selectedIndex, 1);

    // A board without a prefix carries no stamp.
    await tester.tap(find.text('Chores'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Chores')),
      findsOneWidget,
    );
    expect(find.text('RM'), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget);

    // A board without groups shows its tasks directly: no lane card, no group
    // header, and its cards drop the move action that has nothing to target.
    expect(find.text('Ungrouped'), findsNothing);
    expect(find.text('Task 1'), findsOneWidget);
    // A waterfall, not one column: the first two cards sit side by side.
    expect(
      tester.getTopLeft(find.text('Task 1')).dx,
      isNot(tester.getTopLeft(find.text('Task 2')).dx),
    );
    await tester.tap(find.byIcon(Symbols.more_vert).first);
    await tester.pumpAndSettle();
    expect(find.text('Open task'), findsOneWidget);
    expect(find.text('Move to group'), findsNothing);
    await tester.tap(find.byType(ModalBarrier).last);
    await tester.pumpAndSettle();
    expect(find.text('Open task'), findsNothing);

    // ---- Phone ----
    await pumpBoardsApp(tester, const Size(400, 800));
    await openBoardsTab(tester);

    // The tab's root keeps the drawer's edge swipe.
    expect(_shellScaffold(tester).drawerEnableOpenDragGesture, isTrue);

    await tester.tap(find.text('Roadmap'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    // A pushed board owns the screen: the shell's bottom bar stays behind at
    // the tab's root.
    expect(find.byType(NavigationBar), findsNothing);
    // A pushed board leads with Back, so the drawer's edge swipe is off: it
    // would otherwise slide over the page the user is trying to leave.
    expect(_shellScaffold(tester).drawerEnableOpenDragGesture, isFalse);
    expect(find.text('Task 1'), findsOneWidget);
    expect(find.byIcon(Symbols.arrow_back), findsOneWidget);

    await tester.tap(find.byIcon(Symbols.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Chores'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    // ---- Task detail on a phone: a pushed screen, not a sheet ----
    await tester.tap(find.text('Roadmap'));
    await tester.pumpAndSettle();
    // The lanes scroll sideways: bring the first card into reach before
    // tapping it.
    await tester.ensureVisible(find.text('Task 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Task 1'));
    // The container transform runs, then the detail pulls its comment thread:
    // pump the entrance instead of settling the whole tree.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 500));

    // The record is its own route over the board: title in the app bar, the
    // completion action in the body, and no sheet anywhere.
    expect(find.text('Task details'), findsOneWidget);
    expect(find.text('Mark completed'), findsOneWidget);
    expect(find.byType(mui.BottomSheet), findsNothing);

    // Back hands the board back.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Task details'), findsNothing);
    expect(find.text('Mark completed'), findsNothing);
    expect(find.text('Task 1'), findsOneWidget);

    // ---- Lanes on a phone: drag to move, drag to scroll ----
    await tester.tap(find.text('Roadmap'));
    await tester.pumpAndSettle();

    // Widen so the second lane is fully on screen: the drag below has to start
    // on a card that is actually hit-testable.
    tester.view.physicalSize = const Size(700, 800);
    await tester.pumpAndSettle();
    // Still the pushed board, so still no shell chrome over it.
    expect(find.byType(NavigationBar), findsNothing);

    // A horizontal drag still picks the card up for a lane move.
    final card = find.text('Task 1');
    expect(find.byWidgetPredicate(_isDraggingCard), findsNothing);
    final gesture = await tester.startGesture(tester.getCenter(card));
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    expect(find.byWidgetPredicate(_isDraggingCard), findsOneWidget);
    await gesture.up(); // released inside its own lane: no move, no request
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate(_isDraggingCard), findsNothing);

    // A vertical drag on a card scrolls the lane instead. Without the card's
    // `affinity` the immediate drag recognizer swallows the gesture and the
    // lane is stuck with whatever fits on screen.
    double laneOffset() => tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .firstWhere((state) => state.position.axis == Axis.vertical)
        .position
        .pixels;

    final before = laneOffset();
    await tester.drag(card, const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(laneOffset(), greaterThan(before + 30));

    // ---- A group-less board on a phone: one full-width column ----
    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Symbols.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chores'));
    await tester.pumpAndSettle();

    // One column, not the desktop waterfall: the tile spans the board width.
    final tile = tester.getSize(
      find
          .ancestor(of: find.text('Task 1'), matching: find.byType(Material))
          .first,
    );
    expect(tile.width, greaterThan(320));
    // The container transform must not paint the package's default opaque sheet
    // behind the tile.
    final container = tester.widget(
      find
          .byWidgetPredicate(
            (widget) =>
                widget.runtimeType.toString().startsWith('OpenContainer<'),
          )
          .first,
    );
    expect((container as dynamic).closedColor.a, 0);
  });
}

/// The card as it is rendered at the drag source while a drag is under way.
bool _isDraggingCard(Widget widget) =>
    widget is Opacity &&
    widget.opacity == 0.35 &&
    widget.child is IgnorePointer;

/// The app shell's scaffold: the page scaffolds around it own no drawer.
Scaffold _shellScaffold(WidgetTester tester) => tester
    .widgetList<Scaffold>(find.byType(Scaffold))
    .firstWhere((scaffold) => scaffold.drawer != null);
