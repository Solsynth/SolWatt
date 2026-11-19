import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/pages/pages_provider.dart';
import 'package:solwatt/boards/boards_screen.dart';
import 'package:solwatt/pages/pages_screen.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/shell/adaptive_workspace_shell.dart';
import 'package:solwatt/workspace/workspace_models.dart';

/// Answers the broad read and records the save, so the test sees the exact
/// payload the page editor sends to Ideask.
class _RecordingBroadClient extends WattEngineClient {
  _RecordingBroadClient({required this.page})
    : super(SolarNetworkAuthenticator(const FlutterSecureStorage()));

  final Broad page;
  final List<({String id, String name, String? content})> updates = [];

  @override
  Future<Broad?> getBroad(String broadId) async => page;

  @override
  Future<Broad> updateBroad({
    required String broadId,
    required String name,
    String? description,
    String? content,
    String? workspaceId,
    String? parentId,
    bool clearParent = false,
    String? backgroundImageId,
    bool updateBackgroundImage = false,
    String? iconImageId,
    bool updateIconImage = false,
    int? visibility,
    String? taskPrefix,
    bool clearTaskPrefix = false,
  }) async {
    updates.add((id: broadId, name: name, content: content));
    return Broad(
      id: broadId,
      name: name,
      content: content,
      workspaceId: page.workspaceId,
      kind: Broad.kindPage,
    );
  }
}

const _page = Broad(
  id: 'page-1',
  name: 'Runbook',
  content: '# Deploy\n\nShip it.',
  workspaceId: 'ws-1',
  kind: Broad.kindPage,
);

const _board = Broad(
  id: 'board-1',
  name: 'Roadmap',
  workspaceId: 'ws-1',
);

Future<ProviderContainer> _container(_RecordingBroadClient client) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      broadsProvider.overrideWith((ref) async => const [_page, _board]),
      wattEngineClientProvider.overrideWithValue(client),
    ],
  );
}

/// The block types the page body currently holds.
List<String> _documentTypes(WidgetTester tester) => tester
    .widget<SolarBlockEditor>(find.byType(SolarBlockEditor, skipOffstage: false))
    .controller
    .editorState
    .document
    .root
    .children
    .map((node) => node.type)
    .toList();

Widget _app(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: createSolWattTheme(Brightness.light),
        home: child,
      ),
    );

void main() {
  test('broads split into pages and boards by kind', () async {
    final container = await _container(_RecordingBroadClient(page: _page));
    addTearDown(container.dispose);

    await container.read(broadsProvider.future);
    final pages = container.read(pagesProvider).value ?? const <Broad>[];
    final boards = container.read(taskBoardsProvider).value ?? const <Broad>[];

    expect(pages.map((broad) => broad.id), ['page-1']);
    expect(boards.map((broad) => broad.id), ['board-1']);
    // A page is still addressable as a workspace entity, under Pages.
    expect(
      broadToEntityRef(pages.single).domain,
      WorkspaceDomain.pages,
    );
  });

  testWidgets('the page editor saves its title and Markdown body', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final client = _RecordingBroadClient(page: _page);
    final container = await _container(client);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container, const BroadDocScreen(pageId: 'page-1')));
    await tester.pumpAndSettle();

    expect(find.text('Runbook'), findsWidgets);
    // The body opens in the block editor: a heading, then the paragraph.
    final editor = tester.widget<SolarBlockEditor>(
      find.byType(SolarBlockEditor, skipOffstage: false),
    );
    expect(
      editor.controller.editorState.document.root.children.first.type,
      'heading',
    );
    expect(
      editor.controller.editorState.document.root.children.first.delta
          ?.toPlainText(),
      'Deploy',
    );
    expect(_documentTypes(tester), ['heading', 'paragraph']);

    // Typing lands in the editor's document; the save reads that mirror.
    await tester.tap(find.byType(SolarBlockEditor));
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('Ship it twice.');
    await tester.pumpAndSettle();
    expect(
      editor.controller.markdown,
      contains('Ship it twice.'),
    );
    // ⌘S / Ctrl+S saves without leaving the editor.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(client.updates, hasLength(1));
    expect(client.updates.single.id, 'page-1');
    expect(client.updates.single.name, 'Runbook');
    expect(client.updates.single.content, contains('Ship it twice.'));
  });

  testWidgets('the boards tab lists boards and pages in one grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = await _container(_RecordingBroadClient(page: _page));
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(
        container,
        AdaptiveWorkspaceShell(
          isShown: true,
          selectedIndex: 2,
          onSelected: (_) {},
          child: const BoardsListPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // One list, two kinds: the page keeps its own glyph, the board its lanes.
    expect(find.text('Runbook'), findsWidgets);
    expect(find.text('Roadmap'), findsWidgets);
    expect(find.byIcon(Symbols.article_rounded), findsWidgets);
    expect(find.byIcon(Symbols.view_kanban_rounded), findsWidgets);
  });
}
