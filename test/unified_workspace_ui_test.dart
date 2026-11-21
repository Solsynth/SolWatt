import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/ideask/ideask_providers.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/shared/widgets/glass_effects.dart';
import 'package:solwatt/shared/widgets/pill_surface.dart';
import 'package:solwatt/shared/widgets/text_editing_focus.dart';
import 'package:solwatt/shell/adaptive_workspace_shell.dart';
import 'package:solwatt/shell/contextual_sidebar.dart';
import 'package:solwatt/shell/mobile_workspace_chrome.dart';
import 'package:solwatt/shell/workspace_tabs.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/workspace/components/entity_card.dart';
import 'package:solwatt/workspace/components/entity_pill.dart';
import 'package:solwatt/workspace/components/related_items_strip.dart';
import 'package:solwatt/workspace/components/workspace_header.dart';
import 'package:solwatt/workspace/omnibox/federated_omnibox.dart';
import 'package:solwatt/workspace/peek/peek_surface.dart';
import 'package:solwatt/workspace/editor/solar_editor.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_state.dart';

import 'localization_harness.dart';

Future<ProviderContainer> _makeContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // Pages come from the Ideask tree now; these surfaces only need one
      // named page to search and mention.
      ideaskBrowserProvider.overrideWith(
        (ref) async => const IdeaskBrowserState(
          pages: [
            IdeaskPage(id: 'page-q3', title: 'Q3 Roadmap', workspaceId: 'ws-1'),
          ],
        ),
      ),
      selectedWorkspaceProvider.overrideWith(
        (ref) async => const Workspace(
          id: 'ws-1',
          slug: 'ws-1',
          name: 'Test Workspace',
          isBundled: false,
        ),
      ),
    ],
  );
}

Widget _wrapApp(
  ProviderContainer container,
  Widget child, {
  Size size = const Size(1280, 800),
}) {
  return UncontrolledProviderScope(
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
}

void main() {
  setUpAll(loadTestLocalization);

  testWidgets('Desktop (>1024px) renders 4-zone split and resizable Peek pane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = await _makeContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _wrapApp(
        container,
        AdaptiveWorkspaceShell(
          isShown: true,
          selectedIndex: 1, // Todo: boards and pages share the lens
          onSelected: (_) {},
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Zone 2: Contextual Sidebar with the pinned section and the lens tree
    expect(find.byType(ContextualSidebar), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('MAIL'), findsNothing);

    // Zone 4: Peek Pane closed initially, opens non-destructively when triggered
    expect(find.byType(DesktopPeekPane), findsOneWidget);
    expect(find.byType(PeekPanelContent), findsNothing);

    container
        .read(peekProvider.notifier)
        .open(
          const WorkspaceEntityRef(
            id: 'task-1',
            domain: WorkspaceDomain.todo,
            title: 'Follow up Legal',
            subtitle: 'Due: Tomorrow',
            status: 'Open',
          ),
        );
    await tester.pumpAndSettle();

    expect(find.byType(PeekPanelContent), findsOneWidget);
    expect(find.text('Follow up Legal'), findsWidgets);
    expect(find.byType(RelatedItemsStrip), findsWidgets);
  });

  testWidgets(
    'Tablet (600-1024px) renders 2-zone split and Docked Right Sheet',
    (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = await _makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrapApp(
          container,
          AdaptiveWorkspaceShell(
            isShown: true,
            selectedIndex: 1,
            onSelected: (_) {},
            child: const SizedBox.expand(),
          ),
          size: const Size(800, 900),
        ),
      );
      await tester.pumpAndSettle();

      // Sidebar is not docked inline on Tablet (opens as drawer)
      expect(find.byType(ContextualSidebar), findsNothing);

      container
          .read(peekProvider.notifier)
          .open(
            const WorkspaceEntityRef(
              id: 'mail-1',
              domain: WorkspaceDomain.mail,
              title: 'Contract Review',
            ),
          );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(TabletPeekSheet), findsOneWidget);
      expect(find.byType(PeekPanelContent), findsOneWidget);
    },
  );

  testWidgets(
    'Mobile (<600px) uses Top Switcher + PillSurface Floating Pill (no BottomNavigationBar) and DraggableScrollableSheet Peek',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = await _makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrapApp(
          container,
          AdaptiveWorkspaceShell(
            isShown: true,
            selectedIndex: 1,
            onSelected: (_) {},
            child: const SizedBox.expand(),
          ),
          size: const Size(390, 844),
        ),
      );
      await tester.pumpAndSettle();

      // Never use 4-tab BottomNavigationBar
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);

      // Top bar: the lens switcher merged into the title strip, plus the
      // Floating Bottom Action Pill (PillSurface).
      expect(find.byType(MobileLensSwitcher), findsOneWidget);
      expect(find.byType(MobileFloatingActionPill), findsOneWidget);
      expect(find.byType(PillSurface), findsWidgets);
      expect(find.text('Search mail, tasks, pages, files…'), findsOneWidget);

      // Open Peek -> MobilePeekSheet (DraggableScrollableSheet)
      container
          .read(peekProvider.notifier)
          .open(
            const WorkspaceEntityRef(
              id: 'drive-1',
              domain: WorkspaceDomain.drive,
              title: 'Architecture.pdf',
            ),
          );
      await tester.pumpAndSettle();

      expect(find.byType(MobilePeekSheet), findsOneWidget);
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    },
  );

  testWidgets(
    'Mobile (<600px) reserves bottom pill clearance so child FABs sit above MobileFloatingActionPill',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = await _makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrapApp(
          container,
          AdaptiveWorkspaceShell(
            isShown: true,
            selectedIndex: 0,
            onSelected: (_) {},
            child: Scaffold(
              body: const SizedBox.expand(),
              floatingActionButton: FloatingActionButton(
                onPressed: () {},
                child: const Icon(Icons.add),
              ),
            ),
          ),
          size: const Size(390, 844),
        ),
      );
      await tester.pumpAndSettle();

      final fabRect = tester.getRect(find.byType(FloatingActionButton));
      final pillRect = tester.getRect(find.byType(MobileFloatingActionPill));
      expect(fabRect.bottom, lessThanOrEqualTo(pillRect.top));
    },
  );

  testWidgets(
    'Mobile (<600px) hides the footer pill while a document owns the lens',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = await _makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrapApp(
          container,
          AdaptiveWorkspaceShell(
            isShown: true,
            selectedIndex: 1, // Todo: the Ideask tree owns folders and pages
            onSelected: (_) {},
            child: const SizedBox.expand(),
          ),
          size: const Size(390, 844),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MobileFloatingActionPill), findsOneWidget);

      // A page is a pane of the Todo lens: opening it takes the canvas from
      // the lens' root, so the footer omnibox steps aside.
      container
          .read(workspaceTabsProvider.notifier)
          .claim(
            domain: WorkspaceDomain.pages,
            entityId: 'page-q3',
            title: 'Q3 Roadmap',
          );
      await tester.pumpAndSettle();
      expect(find.byType(MobileFloatingActionPill), findsNothing);

      // Closing the document returns the lens to its root and the pill.
      container
          .read(workspaceTabsProvider.notifier)
          .close(WorkspaceTab.keyFor(WorkspaceDomain.pages, 'page-q3'));
      await tester.pumpAndSettle();
      expect(find.byType(MobileFloatingActionPill), findsOneWidget);
    },
  );

  testWidgets('EntityCard renders Mail Attachment with 1-tap Save to Drive', (
    tester,
  ) async {
    final container = await _makeContainer();
    addTearDown(container.dispose);

    const attachment = WorkspaceEntityRef(
      id: 'att-42',
      domain: WorkspaceDomain.drive,
      title: 'Proposal.pdf',
      mimeType: 'application/pdf',
      byteSize: 2048,
      isAttachment: true,
      isSavedToDrive: false,
    );

    await tester.pumpWidget(
      _wrapApp(
        container,
        const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: EntityCard(entity: attachment),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Attachment'), findsOneWidget);
    expect(find.text('Save to Drive'), findsOneWidget);

    await tester.tap(find.text('Save to Drive'));
    await tester.pumpAndSettle();

    expect(container.read(savedAttachmentIdsProvider), contains('att-42'));
    expect(find.text('Attachment'), findsNothing);
  });

  testWidgets(
    'EntityPill opens Peek on tap and RelatedItemsStrip shows backlinks',
    (tester) async {
      final container = await _makeContainer();
      addTearDown(container.dispose);

      const source = WorkspaceEntityRef(
        id: 'page-1',
        domain: WorkspaceDomain.pages,
        title: 'Q3 Roadmap',
      );
      const target = WorkspaceEntityRef(
        id: 'task-99',
        domain: WorkspaceDomain.todo,
        title: 'Ship Spatial Shell',
      );
      container.read(backlinksProvider.notifier).link(source, target);

      await tester.pumpWidget(
        _wrapApp(
          container,
          const Scaffold(
            body: Column(
              children: [
                EntityPill(entity: target),
                SizedBox(height: 16),
                RelatedItemsStrip(entity: source),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Related items · 1'), findsOneWidget);
      await tester.tap(find.byType(EntityPill).first);
      await tester.pumpAndSettle();

      expect(container.read(peekProvider).current?.id, 'task-99');
    },
  );

  testWidgets('Shared header uses the shell geometry token', (tester) async {
    final container = await _makeContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _wrapApp(
        container,
        const Scaffold(body: WorkspaceCanvasHeader(title: Text('Inbox'))),
      ),
    );
    await tester.pumpAndSettle();

    final headerBox = tester.getSize(find.byType(WorkspaceCanvasHeader));
    expect(headerBox.height, SolWorkspaceGeometry.headerHeight);
  });

  testWidgets(
    'solarBlockEditor mirrors edits into the markdown the pages save',
    (tester) async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final controller = SolarEditorController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrapApp(
          container,
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: solarBlockEditor(controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SolarBlockEditor));
      await tester.pumpAndSettle();
      tester.testTextInput.enterText('Ship it.');
      await tester.pumpAndSettle();

      // The page editor saves this string, so the mirror must carry the edit.
      expect(controller.markdown, contains('Ship it.'));
      expect(controller.editorState.document.root.children, isNotEmpty);
    },
  );

  testWidgets('Federated Omnibox shows filter chips and Top Hits', (
    tester,
  ) async {
    final container = await _makeContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _wrapApp(
        container,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showFederatedOmnibox(context),
                child: const Text('Open Omnibox'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Omnibox'));
    await tester.pumpAndSettle();

    expect(find.text('in:mail'), findsOneWidget);
    expect(find.text('in:tasks'), findsOneWidget);
    expect(find.text('in:pages'), findsOneWidget);
    expect(find.text('in:drive'), findsOneWidget);
    expect(find.text('TOP HITS'), findsOneWidget);
    expect(find.text('Q3 Roadmap'), findsWidgets);
  });

  testWidgets(
    'Desktop Keyboard Grammar: Space toggles Peek, Esc closes Peek first',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = await _makeContainer();
      addTearDown(container.dispose);

      const focused = WorkspaceEntityRef(
        id: 'page-roadmap',
        domain: WorkspaceDomain.pages,
        title: 'Q3 Roadmap',
      );
      container.read(focusedEntityProvider.notifier).set(focused);

      await tester.pumpWidget(
        _wrapApp(
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

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(container.read(peekProvider).isOpen, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(container.read(peekProvider).isOpen, isFalse);
      expect(container.read(focusedEntityProvider), isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(container.read(focusedEntityProvider), isNull);
    },
  );

  testWidgets('Keyboard grammar leaves text fields alone', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = await _makeContainer();
    addTearDown(container.dispose);

    container
        .read(peekProvider.notifier)
        .open(
          const WorkspaceEntityRef(
            id: 'task-1',
            domain: WorkspaceDomain.todo,
            title: 'Follow up Legal',
            status: 'Open',
          ),
        );

    await tester.pumpWidget(
      _wrapApp(
        container,
        AdaptiveWorkspaceShell(
          isShown: true,
          selectedIndex: 0,
          onSelected: (_) {},
          child: const Material(child: TextField()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pump();

    // `E` completes a task and Space toggles Peek for the shell. In a text
    // field they are just a letter and a space, and the shell must not halt
    // the event before the field sees it.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle();
    expect(container.read(peekProvider).current?.isCompleted, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(container.read(peekProvider).isOpen, isTrue);
  });

  testWidgets('TextEditingSurface marks non-EditableText editors', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: TextEditingSurface(
          child: Focus(autofocus: true, child: SizedBox()),
        ),
      ),
    );
    await tester.pump();

    expect(isTextEditingFocused(), isTrue);
  });
}
