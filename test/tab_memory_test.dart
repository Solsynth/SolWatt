import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/boards/boards_screen.dart';
import 'package:solwatt/core/config.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/mail/mail_address_suggestion.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/realtime/realtime.dart';
import 'package:solwatt/websocket.dart';

const _active = Workspace(id: 'ws-1', slug: 'ws-1', name: 'Test Workspace');

const _mailbox = MailMailbox(
  id: 'mb-1',
  accountId: 'acc-1',
  workspaceId: 'ws-1',
  address: 'work@example.com',
  name: 'Work',
  isDefault: true,
  isVerified: true,
);

/// Pumps the whole app at [size] with [prefs] as the initial store, so a
/// second call can simulate a relaunch. Each shell needs its own tag: the
/// router and the island overlay are process-wide singletons, so the
/// [ProviderScope] key must change or the old tree is reused.
Future<void> _pumpShell(
  WidgetTester tester,
  Size size,
  String tag, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  FlutterSecureStorage.setMockInitialValues({
    'selected_workspace_id': _active.id,
  });
  await EasyLocalization.ensureInitialized();
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
  final instance = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      key: ValueKey('tab-memory-$tag'),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(instance),
        appAccessProvider.overrideWith(
          (ref) => const AsyncValue.data(AppAccess.ready),
        ),
        secureStorageProvider.overrideWithValue(FlutterSecureStorage()),
        selectedWorkspaceProvider.overrideWith((ref) async => _active),
        workspacesProvider.overrideWith((ref) async => const [_active]),
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

Future<void> _tapInDrawer(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationDrawer),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

int? _railSelected(WidgetTester tester) =>
    tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex;

Future<int?> _storedTabIndex() async =>
    (await SharedPreferences.getInstance()).getInt('app_last_tab_index');

void main() {
  testWidgets('the shell reopens on the last tab but not the mail folder', (
    tester,
  ) async {
    // Fresh install: Mail is the initial tab, the rail lists its folders and
    // Inbox is selected. Nothing is stored until the user actually moves.
    await _pumpShell(tester, const Size(1200, 800), 'fresh');
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(_railSelected(tester), 0);
    expect(await _storedTabIndex(), isNull);

    // Pick the Sent folder: the rail follows, and the tab is still Mail.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Sent'),
      ),
    );
    await tester.pumpAndSettle();
    expect(_railSelected(tester), 1);

    // Switch to Boards through the drawer: the tab index is what is stored.
    await _openDrawer(tester);
    await _tapInDrawer(tester, 'Boards');
    expect(find.byType(BoardsListPage), findsOneWidget);
    expect(_railSelected(tester), 1);
    expect(await _storedTabIndex(), 1);

    // Relaunch into the stored tab…
    await _pumpShell(
      tester,
      const Size(1200, 800),
      'relaunch',
      prefs: const {'app_last_tab_index': 1},
    );
    expect(find.byType(BoardsListPage), findsOneWidget);
    expect(_railSelected(tester), 1);

    // …and mail still restarts on Inbox, not the folder last opened.
    await _openDrawer(tester);
    await _tapInDrawer(tester, 'Mail');
    expect(_railSelected(tester), 0);
  });
}
