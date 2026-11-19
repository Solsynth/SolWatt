import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/pages/pages_provider.dart';
import 'package:solwatt/shared/widgets/glass_effects.dart';
import 'package:solwatt/shell/adaptive_workspace_shell.dart';
import 'package:solwatt/shell/contextual_sidebar.dart';
import 'package:solwatt/shell/mobile_workspace_chrome.dart';
import 'package:solwatt/shell/workspace_title_bar.dart';
import 'package:solwatt/shell/workspace_tabs.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_state.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
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
    child: const Scaffold(body: SizedBox.expand()),
  );
}

void main() {
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
          selectedIndex: 1,
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

    // The document's tab plus the lens tab the bar always anchors on.
    final state = container.read(workspaceTabsProvider);
    expect(state.tabs, hasLength(2));
    expect(
      state.activeKey,
      WorkspaceTab.keyFor(WorkspaceDomain.mail, 'thread-1'),
    );
    expect(
      state.tabs.map((tab) => tab.key),
      contains(WorkspaceTab.lensTabKey(WorkspaceLens.mail)),
    );

    // A document that leaves the screen takes its tab with it; the lens tab
    // stays, so the bar never frames empty chrome.
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

    // The bar itself stays with the lens tab; only the document goes away.
    final remaining = container.read(workspaceTabsProvider).tabs;
    expect(remaining, hasLength(1));
    expect(remaining.single.isRoot, isTrue);
    expect(find.byType(WorkspaceTitleBar), findsOneWidget);
    expect(find.byTooltip('Close tab'), findsNothing);
    expect(find.text('Q4 budget review'), findsNothing);
  });

  testWidgets('a reading pane folds into its lens tab instead of adding one', (
    tester,
  ) async {
    final container = await _container();
    addTearDown(container.dispose);

    final controller = container.read(workspaceTabsProvider.notifier);
    controller.register(
      domain: WorkspaceDomain.mail,
      entityId: 'thread-1',
      title: 'Q4 budget review',
      fullScreen: false,
    );

    final state = container.read(workspaceTabsProvider);
    // One tab: the inbox the reader is still in, labelled with what it shows.
    expect(state.tabs, hasLength(1));
    expect(state.tabs.single.isRoot, isTrue);
    expect(state.tabs.single.title, 'Q4 budget review');
    expect(state.activeKey, WorkspaceTab.lensTabKey(WorkspaceLens.mail));

    // The same conversation promoted to a full screen tab does get its own.
    controller.register(
      domain: WorkspaceDomain.mail,
      entityId: 'thread-1',
      title: 'Q4 budget review',
    );
    final promoted = container.read(workspaceTabsProvider);
    expect(promoted.tabs, hasLength(2));
    expect(
      promoted.activeKey,
      WorkspaceTab.keyFor(WorkspaceDomain.mail, 'thread-1'),
    );

    // Closing the promoted document steps back onto the inbox tab, which the
    // pane kept alive.
    controller.close(WorkspaceTab.keyFor(WorkspaceDomain.mail, 'thread-1'));
    final closed = container.read(workspaceTabsProvider);
    expect(closed.tabs, hasLength(1));
    expect(closed.tabs.single.isRoot, isTrue);
  });

  testWidgets('the rail lands the bar on a lens tab, never on nothing', (
    tester,
  ) async {
    final container = await _container();
    addTearDown(container.dispose);

    final controller = container.read(workspaceTabsProvider.notifier);
    for (final lens in [
      WorkspaceLens.mail,
      WorkspaceLens.todo,
      WorkspaceLens.drive,
    ]) {
      controller.ensureLensTab(lens);
    }
    final state = container.read(workspaceTabsProvider);
    expect(state.tabs, hasLength(3));
    expect(state.tabs.every((tab) => tab.isRoot), isTrue);

    // Asking twice does not duplicate a lens.
    controller.ensureLensTab(WorkspaceLens.mail);
    expect(container.read(workspaceTabsProvider).tabs, hasLength(3));
  });

  testWidgets('a lens tab stays, a document tab closes with its surface', (
    tester,
  ) async {
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
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: createSolWattTheme(Brightness.light),
          home: Scaffold(
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
      ),
    );
    await tester.pumpAndSettle();

    // The lens tab carries no close button: the inbox is not dismissable.
    const inbox = WorkspaceTab(
      key: 'lens:mail',
      lens: WorkspaceLens.mail,
      title: 'Inbox',
      isRoot: true,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: createSolWattTheme(Brightness.light),
          home: Scaffold(
            body: WorkspaceTitleBar(
              tabs: const WorkspaceTabState(
                tabs: [inbox, mail, board],
                activeKey: 'lens:mail',
              ),
              onSelect: (_) {},
              onClose: (tab) => closed.add(tab.key),
              onOpenOmnibox: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // One close button for the two documents; none for the lens tab.
    expect(find.byTooltip('Close tab'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Close tab').first);
    expect(closed, ['mail:t-1']);

    await tester.tap(find.byTooltip('Close all tabs'));
    expect(closed, ['mail:t-1', 'lens:mail', 'mail:t-1', 'todo:b-1']);
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
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: createSolWattTheme(Brightness.light),
          home: Scaffold(
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
          selectedIndex: 4,
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
    // Two documents (the second registered by hand) plus the drive lens tab.
    expect(container.read(workspaceTabsProvider).tabs, hasLength(3));

    // Selecting a tab activates it.
    final launch = container
        .read(workspaceTabsProvider)
        .tabs
        .firstWhere((tab) => tab.title == 'Launch board');
    await tester.tap(find.text('Launch board'));
    await tester.pumpAndSettle();
    expect(container.read(workspaceTabsProvider).activeKey, launch.key);
  });

  testWidgets('the title bar is always present and sits above every panel', (
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
            selectedIndex: 1,
            onSelected: (_) {},
            child: const SizedBox.expand(),
          ),
          size: size,
        ),
      );
      await tester.pumpAndSettle();
    }

    // Desktop: full width, flush to the top, above the sidebar and canvas.
    await pumpAt(const Size(1280, 800));
    final desktopBar = tester.getRect(find.byType(WorkspaceTitleBar));
    expect(desktopBar.top, 0);
    expect(desktopBar.width, 1280);
    final sidebar = tester.getRect(find.byType(ContextualSidebar));
    expect(sidebar.top, greaterThanOrEqualTo(desktopBar.bottom));

    // Tablet.
    await pumpAt(const Size(800, 800));
    var bar = tester.getRect(find.byType(WorkspaceTitleBar));
    expect(bar.top, 0);
    expect(bar.width, 800);

    // Phone: the lens switcher below it, never beside it.
    await pumpAt(const Size(390, 844));
    bar = tester.getRect(find.byType(WorkspaceTitleBar));
    expect(bar.top, 0);
    expect(bar.width, 390);
    final switcher = tester.getRect(find.byType(MobileContextHeader));
    expect(switcher.top, greaterThanOrEqualTo(bar.bottom));
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
          selectedIndex: 1,
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
    expect(find.byType(ContextualSidebar), findsOneWidget);
    expect(
      tester.getRect(find.byType(ContextualSidebar)).top,
      greaterThanOrEqualTo(bar.bottom),
    );
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
    await pumpLens(1);
    expect(find.byType(ContextualSidebar), findsOneWidget);

    // Today, Flywheel, Profile and Settings only list the rail's own lenses.
    for (final index in [0, 5, 6, 7]) {
      await pumpLens(index);
      expect(
        find.byType(ContextualSidebar),
        findsNothing,
        reason: 'lens $index repeats the rail and must not dock a sidebar',
      );
    }

    // Pages and Drive have their own trees and keep the sidebar.
    for (final index in [3, 4]) {
      await pumpLens(index);
      expect(find.byType(ContextualSidebar), findsOneWidget);
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
          selectedIndex: 1,
          onSelected: (_) {},
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('MAIL'), findsOneWidget);
    expect(find.textContaining('('), findsNothing);
  });

  testWidgets('sidebar padding leaves a real gutter', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = await _container();
    addTearDown(container.dispose);
    container
        .read(pinnedItemsProvider.notifier)
        .togglePin(
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
          selectedIndex: 1,
          onSelected: (_) {},
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sidebar = tester.getRect(find.byType(ContextualSidebar));
    final label = tester.getRect(find.text('Pinned'));
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
          selectedIndex: 1,
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
    expect(find.byTooltip('Todo — drop mail to create a task'), findsOneWidget);
  });

  testWidgets('the tab label follows the document title as it changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = await _container();
    addTearDown(container.dispose);
    container.read(pagesProvider.notifier).createPage(title: 'First draft');

    await tester.pumpWidget(
      _app(
        container,
        AdaptiveWorkspaceShell(
          isShown: true,
          selectedIndex: 3,
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
          selectedIndex: 3,
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

    final tabs = container
        .read(workspaceTabsProvider)
        .tabs
        .where((tab) => !tab.isRoot)
        .toList();
    expect(tabs, hasLength(1));
    expect(tabs.single.title, 'Second draft');
    expect(find.byIcon(Symbols.article_rounded), findsWidgets);
  });
}
