import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/ideask/ideask_page.dart';
import 'package:solwatt/ideask/ideask_providers.dart';
import 'package:solwatt/ideask/page_doc_page.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/workspace/workspace_models.dart';

/// Answers the page read and records the writes, so the test sees the exact
/// payload the editor sends to Ideask: metadata through `updatePage`, Markdown
/// through `savePageBody`.
class _RecordingPageClient extends WattEngineClient {
  _RecordingPageClient({required this.page, required this.body})
    : super(SolarNetworkAuthenticator(const FlutterSecureStorage()));

  final IdeaskPage page;
  final IdeaskPageBody body;
  final List<({String id, String? title})> pageUpdates = [];
  final List<({String id, String contentMd})> bodySaves = [];

  @override
  Future<IdeaskPage> getPage(String pageId) async => page;

  @override
  Future<IdeaskPageBody> getPageBody(String pageId) async => body;

  @override
  Future<IdeaskPage> updatePage({
    required String pageId,
    String? title,
    String? description,
    String? iconId,
    bool clearIcon = false,
    String? coverId,
    bool clearCover = false,
    List<String>? tags,
    Map<String, dynamic>? properties,
    int? visibility,
  }) async {
    pageUpdates.add((id: pageId, title: title));
    return page;
  }

  @override
  Future<IdeaskPageBody> savePageBody(String pageId, String contentMd) async {
    bodySaves.add((id: pageId, contentMd: contentMd));
    return IdeaskPageBody(pageId: pageId, contentMd: contentMd);
  }
}

const _page = IdeaskPage(
  id: 'page-1',
  title: 'Runbook',
  workspaceId: 'ws-1',
);

const _body = IdeaskPageBody(
  pageId: 'page-1',
  contentMd: '# Deploy\n\nShip it.',
);

Future<ProviderContainer> _container(_RecordingPageClient client) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      selectedWorkspaceProvider.overrideWith(
        (ref) async => const Workspace(
          id: 'ws-1',
          slug: 'ws-1',
          name: 'Test Workspace',
          isBundled: false,
        ),
      ),
      ideaskBrowserProvider.overrideWith(
        (ref) async => const IdeaskBrowserState(pages: [_page]),
      ),
      wattEngineClientProvider.overrideWithValue(client),
    ],
  );
}

/// The block types the page body currently holds.
List<String> _documentTypes(WidgetTester tester) => tester
    .widget<SolarBlockEditor>(
      find.byType(SolarBlockEditor, skipOffstage: false),
    )
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
  test('a page is addressable as a Pages workspace entity', () async {
    final container = await _container(
      _RecordingPageClient(page: _page, body: _body),
    );
    addTearDown(container.dispose);

    await container.read(ideaskBrowserProvider.future);
    final entity = ideaskEntityRefForPage(_page);

    expect(entity.id, 'page-1');
    expect(entity.title, 'Runbook');
    expect(entity.domain, WorkspaceDomain.pages);
  });

  testWidgets('the page editor saves its title and Markdown body', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final client = _RecordingPageClient(page: _page, body: _body);
    final container = await _container(client);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container, const DocPage(pageId: 'page-1')));
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
    expect(editor.controller.markdown, contains('Ship it twice.'));

    // ⌘S / Ctrl+S saves without leaving the editor.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(client.bodySaves, hasLength(1));
    expect(client.bodySaves.single.id, 'page-1');
    expect(client.bodySaves.single.contentMd, contains('Ship it twice.'));
    // The title was not edited, so no metadata write is issued.
    expect(client.pageUpdates, isEmpty);
  });

  testWidgets('the Todo browser lists folders, collections and pages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        selectedWorkspaceProvider.overrideWith(
          (ref) async => const Workspace(
            id: 'ws-1',
            slug: 'ws-1',
            name: 'Test Workspace',
            isBundled: false,
          ),
        ),
        ideaskBrowserProvider.overrideWith(
          (ref) async => const IdeaskBrowserState(
            folders: [
              IdeaskFolder(id: 'folder-1', name: 'Roadmap', workspaceId: 'ws-1'),
            ],
            collections: [
              IdeaskCollection(
                id: 'collection-1',
                name: 'Releases',
                workspaceId: 'ws-1',
              ),
            ],
            pages: [_page],
          ),
        ),
        wattEngineClientProvider.overrideWithValue(
          _RecordingPageClient(page: _page, body: _body),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(container, const IdeaskBrowserPage()),
    );
    await tester.pumpAndSettle();

    // One list, three kinds: each keeps its own glyph.
    expect(find.text('Roadmap'), findsOneWidget);
    expect(find.text('Releases'), findsOneWidget);
    expect(find.text('Runbook'), findsOneWidget);
    expect(find.byIcon(Symbols.folder), findsWidgets);
    expect(find.byIcon(Symbols.table_chart), findsWidgets);
    expect(find.byIcon(Symbols.article), findsWidgets);
  });
}
