import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/mail/mail_address_suggestion.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/realtime/realtime.dart';
import 'package:solwatt/settings/app_settings_page.dart';
import 'package:solwatt/websocket.dart';

const _active = Workspace(id: 'ws-1', slug: 'ws-1', name: 'Test Workspace');

/// Stores a non-default accent: a fork theme that ignores the preference shows
/// up as the default amber in the toast check below.
const _accent = Color(0xff0d9488);

/// Four workspaces: two personal (round avatars), two organizations. Only the
/// first few fit at a phone width, so the row has to scroll for the rest.
const _workspaces = [
  _active,
  Workspace(
    id: 'ws-2',
    slug: 'acme',
    name: 'Acme Team',
    type: WorkspaceType.organization,
  ),
  Workspace(id: 'ws-3', slug: 'studio', name: 'Studio'),
  Workspace(
    id: 'ws-4',
    slug: 'atelier',
    name: 'Atelier Nord',
    type: WorkspaceType.organization,
  ),
];

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

/// Pumps the whole app. Every step of the test gets its own shell: the router
/// and the island overlay are process-wide singletons, so a second
/// `testWidgets` would pump into a dead tree.
Future<void> _pumpShell(
  WidgetTester tester,
  Size size,
  String tag, {
  Color? accent,
}) async {
  SharedPreferences.setMockInitialValues({
    if (accent != null) 'app_accent_color': accent.toARGB32(),
  });
  FlutterSecureStorage.setMockInitialValues({
    'selected_workspace_id': _active.id,
  });
  await EasyLocalization.ensureInitialized();
  // The About page reads the app's package info; without a mock its future
  // never completes under the test binding.
  PackageInfo.setMockInitialValues(
    appName: 'SolWatt',
    packageName: 'dev.solsynth.solwatt',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
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
      key: ValueKey('drawer-$tag'),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appAccessProvider.overrideWith(
          (ref) => const AsyncValue.data(AppAccess.ready),
        ),
        secureStorageProvider.overrideWithValue(FlutterSecureStorage()),
        selectedWorkspaceProvider.overrideWith((ref) async => _active),
        workspacesProvider.overrideWith((ref) async => _workspaces),
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
        broadsProvider.overrideWith((ref) async => const <Broad>[]),
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
  // The shell only mounts once EasyLocalization's delegate has loaded its
  // bundle, which lands a frame or two after the first build.
  for (var attempt = 0; attempt < 40; attempt++) {
    if (find.byIcon(Symbols.menu).evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

Future<void> _openDrawer(WidgetTester tester) async {
  expect(find.byIcon(Symbols.menu), findsOneWidget);
  await tester.tap(find.byIcon(Symbols.menu));
  await tester.pumpAndSettle();
}

/// Taps without settling: the app's snackbars dismiss themselves after 1.5s,
/// so `pumpAndSettle` would pump past the message it is meant to show.
Future<void> _tapWithoutSettling(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<String?> _storedWorkspaceId() =>
    const FlutterSecureStorage().read(key: 'selected_workspace_id');

/// The selection ring of one workspace item: the only bordered box inside it
/// (the avatar itself paints no border).
BoxDecoration _ringOf(WidgetTester tester, String id) => tester
    .widgetList<Container>(
      find.descendant(
        of: find.byKey(ValueKey('workspace-switch-$id')),
        matching: find.byType(Container),
      ),
    )
    .map((container) => container.decoration)
    .whereType<BoxDecoration>()
    .singleWhere((decoration) => decoration.border != null);

void main() {
  testWidgets('the drawer switches workspaces from a horizontal avatar row', (
    tester,
  ) async {
    // ---- Phone: every workspace is listed, the active one is ringed ----
    await _pumpShell(tester, const Size(390, 844), 'phone', accent: _accent);
    await _openDrawer(tester);

    final drawer = find.byType(NavigationDrawer);
    for (final workspace in _workspaces) {
      expect(
        find.descendant(of: drawer, matching: find.text(workspace.name)),
        findsOneWidget,
      );
    }

    final scheme = Theme.of(
      tester.element(find.byType(NavigationDrawer)),
    ).colorScheme;
    final activeRing = _ringOf(tester, 'ws-1');
    expect(activeRing.border!.top.color, scheme.primary);
    expect(activeRing.border!.top.width, 2);

    // Every other item keeps a transparent ring, so only one reads as active.
    for (final id in const ['ws-2', 'ws-3', 'ws-4']) {
      expect(_ringOf(tester, id).border!.top.color, Colors.transparent);
    }

    // The row is a compact strip: no section header, and each item narrow
    // enough that several workspaces fit before it has to scroll.
    expect(find.descendant(of: drawer, matching: find.text('Workspaces')), findsNothing);
    final itemWidth = tester
        .getSize(find.byKey(const ValueKey('workspace-switch-ws-1')))
        .width;
    expect(itemWidth, lessThanOrEqualTo(64));

    // The drawer carries no console row of its own: the profile page owns
    // that entry.
    expect(find.byKey(const ValueKey('workspace-manage')), findsNothing);

    // ---- Picking another workspace activates it and closes the drawer ----
    await _tapWithoutSettling(
      tester,
      find.byKey(const ValueKey('workspace-switch-ws-2')),
    );

    expect(find.byType(NavigationDrawer), findsNothing);
    expect(find.text('Acme Team is now active.'), findsOneWidget);
    expect(await _storedWorkspaceId(), 'ws-2');

    // The success toast is a fork overlay entry — a *sibling* of the app entry,
    // not a descendant — so it only paints the app's colors because
    // `AppOverlayHost` keeps the fork theme above the whole overlay. Nested
    // inside the app entry instead, the toast falls back to the fork's own
    // baseline scheme and shows a purple card on a warm theme (#3). Its accent
    // also has to come from the stored preference, which is what makes the fork
    // chrome match a non-default accent at all (#1).
    final toast = find.text('Acme Team is now active.');
    expect(
      tester.widget<Text>(toast).style?.color,
      mui.ColorScheme.fromSeed(
        seedColor: _accent,
        brightness: Theme.of(tester.element(toast)).brightness,
      ).onSurfaceVariant,
    );

    // ---- Picking the active workspace just closes the drawer ----
    await _pumpShell(tester, const Size(390, 844), 'phone-again');
    await _openDrawer(tester);
    await _tapWithoutSettling(
      tester,
      find.byKey(const ValueKey('workspace-switch-ws-1')),
    );

    expect(find.byType(NavigationDrawer), findsNothing);
    expect(find.textContaining('is now active.'), findsNothing);
    expect(await _storedWorkspaceId(), 'ws-1');

    // ---- Desktop keeps the tabs in the same drawer, under the rail ----
    await _pumpShell(tester, const Size(1200, 800), 'desktop');
    await _openDrawer(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationDrawer),
        matching: find.text('Boards'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDrawer), findsNothing);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      1,
    );

    // ---- Settings is a drawer destination, not a profile child ----
    await _pumpShell(tester, const Size(390, 844), 'settings');
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ),
      findsNothing,
    );
    await _openDrawer(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationDrawer),
        matching: find.text('Settings'),
      ),
    );
    await tester.pumpAndSettle();

    // The settings list is the tab root: no Back, and — like Profile and
    // Flywheel — no bottom bar, because the bar only carries the primary tabs.
    expect(find.text('Theme mode'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    // The app bar still offers the drawer on a narrow screen.
    expect(find.byIcon(Symbols.menu), findsOneWidget);

    // About is nested under Settings and leads with Back. It sits below the
    // language and appearance sections, so scroll the settings list to it.
    final aboutTile = find.widgetWithText(ListTile, 'SolWatt');
    await tester.dragUntilVisible(
      aboutTile,
      find.descendant(
        of: find.byType(AppSettingsHomePage),
        matching: find.byType(ListView),
      ),
      const Offset(0, -120),
    );
    // `dragUntilVisible` stops as soon as the row is built, which can leave it
    // below the viewport; centre it before tapping.
    await tester.ensureVisible(aboutTile);
    await tester.pumpAndSettle();
    await tester.tap(aboutTile);
    await tester.pumpAndSettle();
    expect(find.text('App information'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Theme mode'), findsOneWidget);
  });
}
