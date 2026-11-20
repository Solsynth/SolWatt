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

import 'package:solwatt/ideask/ideask_page.dart';
import 'package:solwatt/core/config.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/mail/mail_screen.dart';
import 'package:solwatt/mail/mail_address_suggestion.dart';
import 'package:solwatt/ideask/ideask_providers.dart';
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
        ideaskBrowserProvider.overrideWith(
            (ref) async => const IdeaskBrowserState(),
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

Future<void> _openTodoLens(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Todo — drop mail to create a task'));
  await tester.pumpAndSettle();
}

Future<void> _openMailLens(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Mail'));
  await tester.pumpAndSettle();
}

Future<int?> _storedTabIndex() async =>
    (await SharedPreferences.getInstance()).getInt('app_last_lens_index');

void main() {
  testWidgets('the shell reopens on the last lens but not the mail folder', (
    tester,
  ) async {
    // Fresh install: Mail is the initial lens and nothing is stored until the
    // reader actually moves.
    await _pumpShell(tester, const Size(1200, 800), 'fresh');
    expect(find.byType(MailPage), findsOneWidget);
    expect(await _storedTabIndex(), isNull);

    // Switch to Todo through the rail: the lens index is what is stored.
    await _openTodoLens(tester);
    expect(find.byType(IdeaskBrowserPage), findsOneWidget);
    // The Todo lens is index 1 in kShellLenses (mail, todo, drive, …).
    expect(await _storedTabIndex(), 1);

    // Relaunch into the stored lens…
    await _pumpShell(
      tester,
      const Size(1200, 800),
      'relaunch',
      prefs: const {'app_last_lens_index': 1},
    );
    expect(find.byType(IdeaskBrowserPage), findsOneWidget);

    // …and the Mail lens is reachable again without disturbing the stored
    // lens until the reader moves.
    await _openMailLens(tester);
    expect(find.byType(IdeaskBrowserPage), findsNothing);
  });
}
