import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/realtime/realtime.dart';
import 'package:solwatt/websocket.dart';
import 'package:solwatt/mail/mail_address_suggestion.dart';

const _workspace = Workspace(
  id: 'ws-1',
  slug: 'ws-1',
  name: 'Test Workspace',
  isBundled: false,
);

const _roadmap = Broad(
  id: 'board-a',
  name: 'Roadmap',
  description: 'What ships next',
  workspaceId: 'ws-1',
  taskPrefix: 'RM',
);

const _chores = Broad(id: 'board-b', name: 'Chores', workspaceId: 'ws-1');

const _doing = TaskGroup(id: 'group-1', name: 'Doing', broadId: 'board-a');

/// The Mail tab is where the shell opens, so the harness has to keep it
/// rendering; its content is irrelevant here.
const _mailbox = MailMailbox(
  id: 'mb-1',
  accountId: 'acc-1',
  workspaceId: 'ws-1',
  address: 'work@example.com',
  name: 'Work',
  isDefault: true,
  isVerified: true,
);

final _tasks = [
  for (var index = 1; index <= 24; index++)
    WorkTask(
      id: 'task-$index',
      name: 'Task $index',
      broadId: 'board-a',
      taskKey: 'RM-$index',
      groupId: 'group-1',
    ),
];

Future<void> _pumpApp(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (call) async => switch (call.method) {
      'isMaximized' => false,
      _ => null,
    },
  );

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      key: ValueKey('boards-${size.width}x${size.height}'),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appAccessProvider.overrideWith(
          (ref) => const AsyncValue.data(AppAccess.ready),
        ),
        selectedWorkspaceProvider.overrideWith((ref) async => _workspace),
        mailboxesProvider.overrideWith((ref) async => const [_mailbox]),
        mailHostProvider.overrideWith((ref) async => 'example.com'),
        mailboxUnreadCountsProvider.overrideWith((ref) async => const {}),
        mailCredentialsProvider.overrideWith(
          (ref) async => const <MailCredential>[],
        ),
        threadsProvider.overrideWith(
          (ref, query) async =>
              const PaginatedResult<MailThread>(items: [], totalCount: 0),
        ),
        mailSenderIndexProvider.overrideWith(
          (ref) async => const <String, MailAddressSuggestion>{},
        ),
        broadsProvider.overrideWith((ref) async => const [_roadmap, _chores]),
        tasksProvider.overrideWith((ref, request) async => _tasks),
        taskGroupsProvider.overrideWith(
          (ref, broadId) async =>
              broadId == _roadmap.id ? const [_doing] : const [],
        ),
        realtimeBridgeProvider.overrideWith((ref) => RealtimeBridge(ref)),
        websocketStateProvider.overrideWith(WebSocketStateNotifier.new),
      ],
      child: EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/i18n',
        fallbackLocale: const Locale('en', 'US'),
        useFallbackTranslations: true,
        child: SolWattApp(),
      ),
    ),
  );
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

/// The board tabs live behind the burger on every width (the rail shows mail
/// folders while Mail is active).
Future<void> _openBoardsTab(WidgetTester tester) async {
  await tester.tap(find.byIcon(Symbols.menu));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationDrawer),
      matching: find.text('Boards'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a board opens inside the boards tab, not above the shell', (
    tester,
  ) async {
    // ---- Desktop ----
    await _pumpApp(tester, const Size(1200, 800));
    await _openBoardsTab(tester);

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

    // ---- Phone ----
    await _pumpApp(tester, const Size(400, 800));
    await _openBoardsTab(tester);

    // The tab's root keeps the drawer's edge swipe.
    expect(_shellScaffold(tester).drawerEnableOpenDragGesture, isTrue);

    await tester.tap(find.text('Roadmap'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    // The shell's bottom bar still owns navigation under the board.
    expect(find.byType(NavigationBar), findsOneWidget);
    // A pushed board leads with Back, so the drawer's edge swipe is off: it
    // would otherwise slide over the page the user is trying to leave.
    expect(_shellScaffold(tester).drawerEnableOpenDragGesture, isFalse);
    expect(find.text('Task 1'), findsOneWidget);
    expect(find.byIcon(Symbols.arrow_back), findsOneWidget);

    await tester.tap(find.byIcon(Symbols.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Chores'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    // ---- Task detail on a phone: a sheet, not an empty backdrop ----
    await tester.tap(find.text('Roadmap'));
    await tester.pumpAndSettle();
    // The lanes scroll sideways: bring the first card into reach before
    // tapping it.
    await tester.ensureVisible(find.text('Task 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Task 1'));
    // The detail pulls its comment thread, so its body keeps an indicator
    // turning: pump the sheet's entrance instead of settling the tree.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // The record itself is on screen, and it took the bottom of the window:
    // the sheet rides the root navigator, so it covers the shell's bottom bar
    // rather than stopping above it.
    expect(find.text('Task details'), findsOneWidget);
    expect(find.text('Mark completed'), findsOneWidget);
    final sheetRect = tester.getRect(find.byType(mui.BottomSheet));
    expect(sheetRect.bottom, 800);
    expect(
      sheetRect.bottom,
      greaterThan(tester.getRect(find.byType(NavigationBar)).top),
    );

    // Dismissing it hands the board back.
    await tester.tapAt(const Offset(20, 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(mui.BottomSheet), findsNothing);
    expect(find.text('Mark completed'), findsNothing);

    // ---- Lanes on a phone: drag to move, drag to scroll ----
    await tester.tap(find.text('Roadmap'));
    await tester.pumpAndSettle();

    // Widen so the second lane is fully on screen: the drag below has to start
    // on a card that is actually hit-testable.
    tester.view.physicalSize = const Size(700, 800);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);

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
