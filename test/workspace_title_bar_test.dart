import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/route.dart';
import 'package:solwatt/pages/pages_provider.dart';
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
    // The test's stub is always a document of its own; the real pages decide
    // per surface (reading panes fold into the lens tab).
    fullScreen: true,
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

    // The reader moves elsewhere: the document keeps its tab, the way a
    // browser keeps a page, and only closing it takes it away.
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

    final remaining = container.read(workspaceTabsProvider);
    expect(remaining.tabs, hasLength(2));
    expect(find.text('Q4 budget review'), findsOneWidget);
    // Both are closable here: the document, and the lens tab it sits beside.
    expect(find.byTooltip('Close tab'), findsOneWidget);
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

  testWidgets('the rail switches to the lens tab it already pinned', (
    tester,
  ) async {
    final container = await _container();
    addTearDown(container.dispose);

    final controller = container.read(workspaceTabsProvider.notifier);
    controller.focusLens(WorkspaceLens.mail);
    expect(container.read(workspaceTabsProvider).tabs, hasLength(1));

    // A lens tab is pinned: the rail has no other road back to its lens, so
    // closing it is a no-op rather than a way to lose the destination.
    controller.close(WorkspaceTab.lensTabKey(WorkspaceLens.mail));
    expect(container.read(workspaceTabsProvider).tabs, hasLength(1));

    // Leaving and coming back reuses that tab: no pile, rail order at front.
    controller.focusLens(WorkspaceLens.todo);
    controller.focusLens(WorkspaceLens.mail);
    final state = container.read(workspaceTabsProvider);
    expect(state.tabs, hasLength(2));
    expect(state.tabs.map((tab) => tab.lens), [
      WorkspaceLens.mail,
      WorkspaceLens.todo,
    ]);
    expect(state.activeKey, WorkspaceTab.lensTabKey(WorkspaceLens.mail));
  });

  testWidgets('a reading pane never closes the full-screen tab beside it', (
    tester,
  ) async {
    final container = await _container();
    addTearDown(container.dispose);

    final controller = container.read(workspaceTabsProvider.notifier);
    const thread = 'thread-1';
    controller.register(
      domain: WorkspaceDomain.mail,
      entityId: thread,
      title: 'Q4 budget review',
    );
    expect(
      container.read(workspaceTabsProvider).tabs,
      hasLength(1),
      reason: 'the promoted conversation owns one tab',
    );

    // Reading the same conversation in the pane must not remove that tab.
    controller.register(
      domain: WorkspaceDomain.mail,
      entityId: thread,
      title: 'Q4 budget review',
      fullScreen: false,
    );
    final state = container.read(workspaceTabsProvider);
    expect(state.tabs.where((tab) => tab.key == 'mail:$thread'), hasLength(1));
    expect(
      state.tabs.map((tab) => tab.key),
      contains(WorkspaceTab.lensTabKey(WorkspaceLens.mail)),
    );
  });

  testWidgets('a rail click reuses the lens tab and never spends a new one', (
    tester,
  ) async {
    final container = await _container();
    addTearDown(container.dispose);

    final controller = container.read(workspaceTabsProvider.notifier);
    for (final lens in [
      WorkspaceLens.drive,
      WorkspaceLens.mail,
      WorkspaceLens.todo,
    ]) {
      controller.focusLens(lens);
    }
    final state = container.read(workspaceTabsProvider);
    expect(state.tabs, hasLength(3));
    expect(state.tabs.every((tab) => tab.isRoot), isTrue);
    expect(state.tabs.map((tab) => tab.lens).toList(), [
      WorkspaceLens.mail,
      WorkspaceLens.todo,
      WorkspaceLens.drive,
    ]);

    // A document opened in a lens keeps its tab, and going back to the rail
    // retitles that lens' own tab rather than adding another one beside it.
    controller.claim(
      domain: WorkspaceDomain.mail,
      entityId: 'thread-1',
      title: 'Q4 budget review',
      messageId: 'msg-1',
    );
    controller.focusLens(WorkspaceLens.todo);
    controller.focusLens(WorkspaceLens.mail, title: 'Inbox');
    final returned = container.read(workspaceTabsProvider);
    expect(returned.tabs, hasLength(4));
    expect(returned.tabs.where((tab) => tab.isRoot), hasLength(3));
    expect(
      returned.tabs
          .firstWhere(
            (tab) => tab.key == WorkspaceTab.lensTabKey(WorkspaceLens.mail),
          )
          .title,
      'Inbox',
      reason: 'the lens tab is named after the pane the rail lands on',
    );
    expect(returned.activeKey, WorkspaceTab.lensTabKey(WorkspaceLens.mail));
    // The document's tab survives the round trip untouched.
    expect(
      returned.tabs.where((tab) => tab.key == 'mail:thread-1'),
      hasLength(1),
    );
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

    // The rail moves between pinned lens tabs; it never spends a document's.
    controller.focusLens(WorkspaceLens.mail);
    expect(container.read(workspaceTabsProvider).showsDocument, isFalse);
    controller.activate(tab.key);
    expect(container.read(workspaceTabsProvider).showsDocument, isTrue);
  });

  testWidgets('documents close, pinned lens tabs stay', (tester) async {
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

    // Two documents, two close buttons: a pinned lens tab is the rail's own
    // destination and has no close affordance.
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

  testWidgets('the bar carries the workspace avatar, not its name', (
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

    // A workspace with no picture falls back to the workspace icon, sized to
    // the bar: the name itself is not spent on screen width.
    final avatar = find.byType(CloudFileAvatar);
    expect(avatar, findsWidgets);
    expect(tester.getSize(avatar.first).width, lessThanOrEqualTo(32));
    // The bar itself never prints the name; the tooltip carries it.
    expect(
      find.descendant(
        of: find.byType(WorkspaceTitleBar),
        matching: find.text('SolWatt'),
      ),
      findsNothing,
    );

    // The rail no longer duplicates the workspace picker.
    expect(find.byTooltip('Workspaces'), findsNothing);
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
