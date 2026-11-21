import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/route.dart';
import 'package:solwatt/shared/widgets/glass_effects.dart';
import 'package:solwatt/shell/adaptive_workspace_shell.dart';
import 'package:solwatt/shell/contextual_sidebar.dart';
import 'package:solwatt/shell/mobile_workspace_chrome.dart';
import 'package:solwatt/shell/workspace_title_bar.dart';
import 'package:solwatt/shell/workspace_tabs.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/ui/cloud_files.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_state.dart';

import 'localization_harness.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // The shell's rail tests expect every lens, including Ideask.
      ideaskEntryVisibleProvider.overrideWithValue(true),
    ],
  );
}

Widget _app(
  ProviderContainer container,
  Widget child, {
  Size size = const Size(1280, 800),
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: createSolWattTheme(Brightness.light),
    home: GlassEffects(
      enabled: false,
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: child,
      ),
    ),
  ),
);

/// A detail surface only exists to declare its document; the test's own stub
/// stands in for the real page so the shell can be driven without the network.
class _DocumentSurface extends StatelessWidget {
  final WorkspaceDomain domain;
  final String id;
  final String title;

  const _DocumentSurface({
    required this.domain,
    required this.id,
    required this.title,
  });

  @override
  Widget build(BuildContext context) => WorkspaceDocumentScope(
    domain: domain,
    entityId: id,
    title: title,
    // The test's stub is always a document of its own; the real pages decide
    // per surface (reading panes fold into the lens tab).
    fullScreen: true,
    child: const Scaffold(body: SizedBox.expand()),
  );
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    loadTestLocalization();
  });
  testWidgets('title bar lists open documents and tracks the active one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = await _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(
        container,
        AdaptiveWorkspaceShell(
          isShown: true,
          selectedIndex: 0,
          onSelected: (_) {},
          child: const _DocumentSurface(
            domain: WorkspaceDomain.mail,
            id: 'thread-1',
            title: 'Q4 budget review',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The title bar names the document that is on screen, not the lens.
    expect(find.byType(WorkspaceTitleBar), findsOneWidget);
    expect(find.text('Q4 budget review'), findsOneWidget);

    // The strip holds the document and nothing else: the lens the rail picked
    // is the rail's own state, not a tab.
    final state = container.read(workspaceTabsProvider);
    expect(state.tabs, hasLength(1));
    expect(
      state.activeKey,
      WorkspaceTab.keyFor(WorkspaceDomain.mail, 'thread-1'),
    );

    // The reader moves elsewhere: the document keeps its tab, the way a
    // browser keeps a page, and only closing it takes it away.
    await tester.pumpWidget(
      _app(
        container,
        AdaptiveWorkspaceShell(
          isShown: true,
          selectedIndex: 0,
          onSelected: (_) {},
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final remaining = container.read(workspaceTabsProvider);
    expect(remaining.tabs, hasLength(1));
    expect(remaining.activeKey, isNull);
    expect(find.text('Q4 budget review'), findsOneWidget);
    expect(find.byTooltip('Close tab'), findsOneWidget);
  });

  testWidgets('a reading pane never spends a tab', (tester) async {
    final container = await _container();
    addTearDown(container.dispose);

    final controller = container.read(workspaceTabsProvider.notifier);
    controller.register(
      domain: WorkspaceDomain.mail,
      entityId: 'thread-1',
      title: 'Q4 budget review',
      fullScreen: false,
    );

    // Reading a conversation beside the list is not opening a document: the
    // strip stays empty and the lens' own root keeps the canvas.
    final state = container.read(workspaceTabsProvider);
    expect(state.tabs, isEmpty);
    expect(state.activeKey, isNull);
    expect(state.showsDocument, isFalse);

    // The same conversation promoted to a full screen does get its own tab.
    controller.register(
      domain: WorkspaceDomain.mail,
      entityId: 'thread-1',
      title: 'Q4 budget review',
    );
    final promoted = container.read(workspaceTabsProvider);
    expect(promoted.tabs, hasLength(1));
    expect(
      promoted.activeKey,
      WorkspaceTab.keyFor(WorkspaceDomain.mail, 'thread-1'),
    );

    // Demoting it folds the pane back beside the list: the document is no
    // longer a full screen, so it stops being a tab.
    controller.register(
      domain: WorkspaceDomain.mail,
      entityId: 'thread-1',
      title: 'Q4 budget review',
      fullScreen: false,
    );
    expect(container.read(workspaceTabsProvider).tabs, isEmpty);
  });

  testWidgets('a rail click never spends a tab and keeps the open ones', (
    tester,
  ) async {
    final container = await _container();
    addTearDown(container.dispose);

    final controller = container.read(workspaceTabsProvider.notifier);
    controller.claim(
      domain: WorkspaceDomain.mail,
      entityId: 'thread-1',
      title: 'Q4 budget review',
      messageId: 'msg-1',
    );

    // The rail addresses a place: arriving at a lens shows its root pane, and
    // nothing on the strip claims the canvas.
    controller.deactivate();
    final state = container.read(workspaceTabsProvider);
    expect(state.activeKey, isNull);
    expect(state.showsDocument, isFalse);
    expect(state.tabs.map((tab) => tab.key), [
      'mail:thread-1',
    ], reason: 'the document keeps the tab the reader opened it in');
  });

  testWidgets('a conversation tab remembers the message it opens', (
    tester,
  ) async {
    final container = await _container();
    addTearDown(container.dispose);

    final controller = container.read(workspaceTabsProvider.notifier);
    controller.claim(
      domain: WorkspaceDomain.mail,
      entityId: 'thread-1',
      title: 'Q4 budget review',
      messageId: 'msg-7',
    );

    // The tab is keyed by the conversation and carries the message: selecting
    // it later reopens that message, not the newest one and not a new tab.
    final tab = container.read(workspaceTabsProvider).activeTab!;
    expect(tab.key, 'mail:thread-1');
    expect(tab.messageId, 'msg-7');
    expect(
      (routeForTab(tab) as MailDetailRoute).args?.emailId,
      'msg-7',
      reason: 'the tab reopens the message it was created for',
    );

    // The rail shows the inbox; the tab is still there and comes back whole.
    controller.deactivate();
    expect(container.read(workspaceTabsProvider).showsDocument, isFalse);
    controller.activate(tab.key);
    expect(container.read(workspaceTabsProvider).showsDocument, isTrue);
  });

  testWidgets('every tab on the strip closes', (tester) async {
    const mail = WorkspaceTab(
      key: 'mail:t-1',
      lens: WorkspaceLens.mail,
      domain: WorkspaceDomain.mail,
      entityId: 't-1',
      title: 'Q4 budget review',
    );
    const board = WorkspaceTab(
      key: 'todo:b-1',
      lens: WorkspaceLens.todo,
      domain: WorkspaceDomain.todo,
      entityId: 'b-1',
      title: 'Launch board',
    );
    final closed = <String>[];
    final container = await _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(
        container,
        Scaffold(
          body: WorkspaceTitleBar(
            tabs: const WorkspaceTabState(
              tabs: [mail, board],
              activeKey: 'mail:t-1',
            ),
            onSelect: (_) {},
            onClose: (tab) => closed.add(tab.key),
            onOpenOmnibox: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The strip only ever holds documents, so each one has a close button.
    expect(find.byTooltip('Close tab'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Close tab').first);
    expect(closed, ['mail:t-1']);

    await tester.tap(find.byTooltip('Close all document tabs'));
    expect(closed, ['mail:t-1', 'mail:t-1', 'todo:b-1']);
  });

  testWidgets('selecting a document tab hands it to the shell', (tester) async {
    const mail = WorkspaceTab(
      key: 'mail:t-1',
      lens: WorkspaceLens.mail,
      domain: WorkspaceDomain.mail,
      entityId: 't-1',
      title: 'Q4 budget review',
    );
    const board = WorkspaceTab(
      key: 'todo:b-1',
      lens: WorkspaceLens.todo,
      domain: WorkspaceDomain.todo,
      entityId: 'b-1',
      title: 'Launch board',
    );
    final selected = <String>[];
    final container = await _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(
        container,
        Scaffold(
          body: WorkspaceTitleBar(
            tabs: const WorkspaceTabState(
              tabs: [mail, board],
              activeKey: 'todo:b-1',
            ),
            onSelect: (tab) => selected.add(tab.key),
            onClose: (_) {},
            onOpenOmnibox: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Q4 budget review'));
    expect(selected, ['mail:t-1']);
  });

  testWidgets('a second kind of document joins the same bar', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = await _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(
        container,
        AdaptiveWorkspaceShell(
          isShown: true,
          selectedIndex: 3,
          onSelected: (_) {},
          child: const _DocumentSurface(
            domain: WorkspaceDomain.drive,
            id: 'file-9',
            title: 'Architecture.pdf',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A drive file and a board share one bar: the bar is about what is open,
    // the rail stays about which part of the app.
    container
        .read(workspaceTabsProvider.notifier)
        .register(
          domain: WorkspaceDomain.todo,
          entityId: 'board-3',
          title: 'Launch board',
        );
    await tester.pumpAndSettle();

    expect(find.text('Architecture.pdf'), findsOneWidget);
    expect(find.text('Launch board'), findsOneWidget);
    // Two documents: the drive file and the board registered by hand.
    expect(container.read(workspaceTabsProvider).tabs, hasLength(2));

    // Selecting a tab activates it.
    final launch = container
        .read(workspaceTabsProvider)
        .tabs
        .firstWhere((tab) => tab.title == 'Launch board');
    await tester.tap(find.text('Launch board'));
    await tester.pumpAndSettle();
    expect(container.read(workspaceTabsProvider).activeKey, launch.key);
  });

  testWidgets('the workspace avatar lives on the rail, not the strip', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = await _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(
        container,
        AdaptiveWorkspaceShell(
          isShown: true,
          selectedIndex: 0,
          onSelected: (_) {},
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A workspace with no picture falls back to the workspace icon, sized to
    // the rail: the name itself is not spent on screen width.
    final avatar = find.byType(CloudFileAvatar);
    expect(avatar, findsWidgets);
    expect(tester.getSize(avatar.first).width, lessThanOrEqualTo(32));
    expect(
      find.descendant(of: find.byType(WorkspaceTitleBar), matching: avatar),
      findsNothing,
      reason: 'the workspace belongs to the rail',
    );
    expect(
      find.descendant(
        of: find.byType(WorkspaceTitleBar),
        matching: find.text('SolWatt'),
      ),
      findsNothing,
    );
  });

  testWidgets('the strip is there for documents and gone without them', (
    tester,
  ) async {
    Future<void> pumpAt(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      final container = await _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _app(
          container,
          AdaptiveWorkspaceShell(
            isShown: true,
            selectedIndex: 0,
            onSelected: (_) {},
            child: const SizedBox.expand(),
          ),
          size: size,
        ),
      );
      await tester.pumpAndSettle();
    }

    // Nothing open: the strip collapses to one step of air, so the canvas
    // keeps a gap from the top edge instead of starting flush against it.
    await pumpAt(const Size(1280, 800));
    final collapsed = tester.getRect(find.byType(WorkspaceTitleBar));
    expect(collapsed.top, 0);
    expect(collapsed.height, SolSpace.sm);
    // The rail is flush to the top of the body: its first row — the workspace
    // avatar — sits where the rail's own inset puts it, with no strip above.
    final avatar = tester.getRect(find.byType(CloudFileAvatar).first);
    expect(avatar.top, lessThan(SolSpace.md + SolSpace.sm));

    // A document brings the strip back, above rail and canvas alike.
    final withBoard = await _container();
    addTearDown(withBoard.dispose);
    withBoard
        .read(workspaceTabsProvider.notifier)
        .claim(
          domain: WorkspaceDomain.todo,
          entityId: 'b-1',
          title: 'Launch board',
        );
    await tester.pumpWidget(
      _app(
        withBoard,
        AdaptiveWorkspaceShell(
          isShown: true,
          selectedIndex: 1,
          onSelected: (_) {},
          child: const SizedBox.expand(),
        ),
        size: const Size(1280, 800),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(WorkspaceTitleBar)).height,
      greaterThan(0),
    );

    // Phone: the lens switcher leads the strip itself, so the shell has one
    // top band instead of a strip with a lens header under it.
    await pumpAt(const Size(390, 844));
    final phoneBar = tester.getRect(find.byType(WorkspaceTitleBar));
    expect(phoneBar.top, 0);
    expect(phoneBar.height, 40);
    expect(phoneBar.width, 390);
    final switcher = tester.getRect(find.byType(MobileLensSwitcher));
    expect(switcher.top, greaterThanOrEqualTo(phoneBar.top));
    expect(switcher.bottom, lessThanOrEqualTo(phoneBar.bottom));
  });

  testWidgets('the title bar keeps its place with documents open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = await _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(
        container,
        AdaptiveWorkspaceShell(
          isShown: true,
          selectedIndex: 0,
          onSelected: (_) {},
          child: const _DocumentSurface(
            domain: WorkspaceDomain.mail,
            id: 'thread-1',
            title: 'Q4 budget review',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.byType(WorkspaceTitleBar));
    expect(bar.top, 0);
    // The document lives in the bar, above the canvas rather than inside it.
    final tab = tester.getRect(find.text('Q4 budget review'));
    expect(tab.center.dy, inInclusiveRange(bar.top, bar.bottom));
    // A document is a full screen: the lens' own sidebar steps aside so the
    // document gets the whole canvas.
    expect(find.byType(ContextualSidebar), findsNothing);
  });

  testWidgets('lenses that duplicate the rail hide the docked sidebar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = await _container();
    addTearDown(container.dispose);

    Future<void> pumpLens(int index) async {
      await tester.pumpWidget(
        _app(
          container,
          AdaptiveWorkspaceShell(
            isShown: true,
            selectedIndex: index,
            onSelected: (_) {},
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // Mail owns a real tree (folders), so its sidebar stays.
    await pumpLens(0);
    expect(find.byType(ContextualSidebar), findsOneWidget);

    // Profile and Settings only list the rail's own lenses.
    for (final index in [3, 4]) {
      await pumpLens(index);
      expect(
        find.byType(ContextualSidebar),
        findsNothing,
        reason: 'lens $index repeats the rail and must not dock a sidebar',
      );
    }

    // Todo lists boards and pages; Drive has its own tree. Both keep the
    // sidebar.
    for (final index in [0, 1, 2]) {
      await pumpLens(index);
      expect(
        find.byType(ContextualSidebar),
        findsOneWidget,
        reason: 'lens $index owns a tree and must dock a sidebar',
      );
    }
  });

  testWidgets('sidebar reads its sections without parentheses', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = await _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(
        container,
        AdaptiveWorkspaceShell(
          isShown: true,
          selectedIndex: 0,
          onSelected: (_) {},
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('MAIL'), findsOneWidget);
    expect(find.textContaining('('), findsNothing);
  });

  testWidgets('the docked sidebar folds away instead of vanishing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = await _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(
        container,
        AdaptiveWorkspaceShell(
          isShown: true,
          selectedIndex: 0,
          onSelected: (_) {},
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dock = find.byKey(workspaceSidebarDockKey);
    const openWidth = SolWorkspaceGeometry.sidebarWidth + SolSpace.sm;
    expect(tester.getSize(dock).width, openWidth);

    await tester.tap(find.byTooltip('Hide sidebar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Mid-fold the panel is still mounted and the dock is only part-way shut,
    // so the canvas grows into the space rather than jumping into it.
    expect(find.byType(ContextualSidebar), findsOneWidget);
    final folding = tester.getSize(dock).width;
    expect(folding, greaterThan(0));
    expect(folding, lessThan(openWidth));

    await tester.pumpAndSettle();
    expect(find.byType(ContextualSidebar), findsNothing);
    expect(tester.getSize(dock).width, 0);

    await tester.tap(find.byTooltip('Show sidebar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ContextualSidebar), findsOneWidget);
    final unfolding = tester.getSize(dock).width;
    expect(unfolding, greaterThan(0));
    expect(unfolding, lessThan(openWidth));

    await tester.pumpAndSettle();
    expect(tester.getSize(dock).width, openWidth);
  });

  testWidgets('sidebar padding leaves a real gutter', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = await _container();
    addTearDown(container.dispose);
    container
        .read(favoritesProvider.notifier)
        .toggleFavorite(
          const WorkspaceEntityRef(
            id: 'page-1',
            domain: WorkspaceDomain.pages,
            title: 'Roadmap',
          ),
        );

    await tester.pumpWidget(
      _app(
        container,
        AdaptiveWorkspaceShell(
          isShown: true,
          selectedIndex: 0,
          onSelected: (_) {},
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sidebar = tester.getRect(find.byType(ContextualSidebar));
    final label = tester.getRect(find.text('Favorites'));
    // 16px gutter: the label starts one lg inset inside the column.
    expect(label.left - sidebar.left, greaterThanOrEqualTo(SolSpace.lg - 0.5));

    final row = tester.getRect(find.text('Inbox'));
    expect(row.left - sidebar.left, greaterThanOrEqualTo(SolSpace.lg - 0.5));
  });

  testWidgets('rail tooltips state their shortcut without parentheses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = await _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(
        container,
        AdaptiveWorkspaceShell(
          isShown: true,
          selectedIndex: 0,
          onSelected: (_) {},
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tooltips = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.message ?? '')
        .where((m) => m.isNotEmpty);
    for (final message in tooltips) {
      expect(message.contains('('), isFalse, reason: 'tooltip: $message');
    }
    // The rails still name their shortcuts.
    expect(find.byTooltip('Omnibox — Cmd K or Ctrl K'), findsOneWidget);
    expect(
      find.byTooltip('Ideask — drop mail to create a task'),
      findsOneWidget,
    );
  });

  testWidgets('the tab label follows the document title as it changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = await _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(
        container,
        AdaptiveWorkspaceShell(
          isShown: true,
          selectedIndex: 1,
          onSelected: (_) {},
          child: const _DocumentSurface(
            domain: WorkspaceDomain.pages,
            id: 'page-1',
            title: 'First draft',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('First draft'), findsWidgets);

    await tester.pumpWidget(
      _app(
        container,
        AdaptiveWorkspaceShell(
          isShown: true,
          selectedIndex: 1,
          onSelected: (_) {},
          child: const _DocumentSurface(
            domain: WorkspaceDomain.pages,
            id: 'page-1',
            title: 'Second draft',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tabs = container.read(workspaceTabsProvider).tabs;
    expect(tabs, hasLength(1));
    expect(tabs.single.title, 'Second draft');
    expect(find.byIcon(Symbols.article_rounded), findsWidgets);
  });

  testWidgets(
    'home icon appears when tabbar is shown and selects non-tabbed contents',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = await _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _app(
          container,
          AdaptiveWorkspaceShell(
            isShown: true,
            selectedIndex: 1,
            onSelected: (_) {},
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Collapsed strip: no home icon.
      expect(find.byIcon(Symbols.home_rounded), findsNothing);

      // Opening a tab shows the strip along with the home icon.
      container
          .read(workspaceTabsProvider.notifier)
          .claim(
            domain: WorkspaceDomain.pages,
            entityId: 'page-1',
            title: 'Runbook',
          );
      await tester.pumpAndSettle();

      final homeIcon = find.descendant(
        of: find.byType(WorkspaceTitleBar),
        matching: find.byIcon(Symbols.home_rounded),
      );
      expect(homeIcon, findsOneWidget);

      Material homeChipMaterial() => tester.widget<Material>(
        find.ancestor(of: homeIcon, matching: find.byType(Material)).first,
      );

      // A document tab is active, so the home chip is unselected.
      expect(homeChipMaterial().color, Colors.transparent);

      // Tapping home returns to non-tabbed contents while keeping the tab open.
      await tester.tap(homeIcon);
      await tester.pumpAndSettle();

      final state = container.read(workspaceTabsProvider);
      expect(state.tabs, hasLength(1));
      expect(state.activeKey, isNull);
      expect(
        homeChipMaterial().color,
        Theme.of(tester.element(homeIcon)).colorScheme.surface,
      );
    },
  );
}
