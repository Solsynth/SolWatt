import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/network.dart';

import 'boards_harness.dart';

/// A second workspace the bulk move can target; the harness leaves the app on
/// [boardWorkspace], so this is the only entry the picker lists.
const otherWorkspace = Workspace(
  id: 'ws-2',
  slug: 'ws-2',
  name: 'Other Workspace',
  isBundled: false,
);

/// Records the board writes so the test can assert the endpoints the UI
/// reaches.
class RecordingBoardClient extends WattEngineClient {
  RecordingBoardClient()
    : super(SolarNetworkAuthenticator(const FlutterSecureStorage()));

  final List<String> deleted = [];
  final List<List<String>> batchDeleted = [];
  final List<(List<String>, String)> moved = [];

  @override
  Future<void> deleteBroad(String broadId) async => deleted.add(broadId);

  @override
  Future<int> deleteBroads(List<String> broadIds) async {
    batchDeleted.add(List.of(broadIds));
    return broadIds.length;
  }

  @override
  Future<int> moveBroads(List<String> broadIds, String workspaceId) async {
    moved.add((List.of(broadIds), workspaceId));
    return broadIds.length;
  }
}

/// Lets an action's snackbar come and go so the next assertion reads only the
/// snackbar its own action produced.
Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

void main() {
  testWidgets('boards list deletes one board, then bulk-deletes and moves', (
    tester,
  ) async {
    final client = RecordingBoardClient();
    await pumpBoardsApp(
      tester,
      const Size(1200, 800),
      client: client,
      workspaces: const [boardWorkspace, otherWorkspace],
    );
    await openBoardsTab(tester);

    expect(find.text('Roadmap'), findsOneWidget);
    expect(find.text('Chores'), findsOneWidget);
    // The list drops the shared reading-width cap, so a wide pane shows more
    // cover columns rather than a wider gutter.
    expect(tester.getSize(find.byType(GridView)).width, greaterThan(960));
    // Selection mode is off: the grid carries the per-board menus.
    expect(find.byIcon(Symbols.more_vert), findsNWidgets(2));
    expect(find.byIcon(Symbols.select_check_box), findsOneWidget);

    // ---- Delete one board from its card menu ----
    await tester.tap(find.byIcon(Symbols.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete board?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(client.deleted, ['board-a']);
    expect(client.batchDeleted, isEmpty);
    expect(find.text('Board deleted.'), findsOneWidget);
    await _settle(tester);

    // ---- Bulk delete ----
    await tester.tap(find.byIcon(Symbols.select_check_box));
    await tester.pumpAndSettle();
    // The bar replaces the create action and the app bar carries the count.
    expect(find.text('New board'), findsNothing);
    expect(find.byIcon(Symbols.more_vert), findsNothing);

    await tester.tap(find.text('Roadmap'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chores'));
    await tester.pumpAndSettle();
    expect(find.text('2 boards selected'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('board-selection-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete boards?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(client.batchDeleted, [
      ['board-a', 'board-b'],
    ]);
    expect(find.text('Deleted 2 boards.'), findsOneWidget);
    // The batch dropped the selection and the mode with it.
    expect(find.text('2 boards selected'), findsNothing);
    await _settle(tester);

    // ---- Bulk move ----
    await tester.tap(find.byIcon(Symbols.select_check_box));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roadmap'));
    await tester.pumpAndSettle();
    expect(find.text('1 boards selected'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('board-selection-move')));
    await tester.pumpAndSettle();
    expect(find.text('Move to workspace'), findsOneWidget);
    await tester.tap(find.text('Other Workspace'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(client.moved, hasLength(1));
    expect(client.moved.single.$1, ['board-a']);
    expect(client.moved.single.$2, 'ws-2');
    expect(find.text('Moved 1 boards to Other Workspace.'), findsOneWidget);
  });
}
