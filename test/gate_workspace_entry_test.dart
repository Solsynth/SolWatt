import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/ideask/ideask_providers.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/realtime/realtime.dart';
import 'package:solwatt/ui/page_scaffold.dart';
import 'package:solwatt/websocket.dart';

const _workspace = Workspace(id: 'ws-1', slug: 'ws-1', name: 'Test Workspace');

const _mailbox = MailMailbox(
  id: 'mb-1',
  accountId: 'acc-1',
  workspaceId: 'ws-1',
  address: 'work@example.com',
  name: 'Work',
  isDefault: true,
  isVerified: true,
);

/// Keeps the offline live-updates pill out of the tree: the pill's message is
/// wider than a phone in the test font, and this test is about the router.
class _ConnectedWebSocket extends WebSocketStateNotifier {
  @override
  WebSocketConnectionState build() => WebSocketConnectionState.connected;
}

/// Entering the shell from the gate's workspace picker mounts exactly one
/// shell.
///
/// The picker used to swap the stack for [AppShellRoute] the moment a workspace
/// was tapped, before the selection had resolved. The AppShell mounted by that
/// swap read the stale `needsWorkspace` it was created under, sent the stack
/// back to the gate, and was entered a second time once the selection settled —
/// while the first AppShell was still transitioning out. Both shells install
/// `shellScaffoldKey`, so the frame that mounted the second one reported
/// "Multiple widgets used the same GlobalKey" and Flutter left a blank page.
void main() {
  testWidgets('the gate enters a single shell once the pick settles', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
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

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    final prefs = await SharedPreferences.getInstance();
    final storage = FlutterSecureStorage();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureStorageProvider.overrideWithValue(storage),
          // A signed-in account with no workspace yet is what puts the gate on
          // its picker; the session is overridden rather than the access state
          // so that picking one still drives the real derivation.
          authSessionProvider.overrideWith(
            (ref) async => const OAuthSession(accessToken: 'token'),
          ),
          // Mirrors the real provider: it reads the stored id, then lists the
          // workspaces over the network before it can answer.
          selectedWorkspaceProvider.overrideWith((ref) async {
            final id = await ref
                .watch(secureStorageProvider)
                .read(key: 'selected_workspace_id');
            if (id == null) return null;
            await Future<void>.delayed(const Duration(milliseconds: 300));
            return _workspace;
          }),
          workspacesProvider.overrideWith((ref) async => const [_workspace]),
          mailboxesProvider.overrideWith((ref) async => const [_mailbox]),
          mailHostProvider.overrideWith((ref) async => 'example.com'),
          mailboxUnreadCountsProvider.overrideWith((ref) async => const {}),
          mailCredentialsProvider.overrideWith(
            (ref) async => const <MailCredential>[],
          ),
          ideaskBrowserProvider.overrideWith(
            (ref) async => const IdeaskBrowserState(),
          ),
          realtimeBridgeProvider.overrideWith((ref) => RealtimeBridge(ref)),
          websocketStateProvider.overrideWith(_ConnectedWebSocket.new),
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

    // The picker only mounts once EasyLocalization has loaded its bundle.
    for (var attempt = 0; attempt < 40; attempt++) {
      if (find.text(_workspace.name).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text(_workspace.name), findsOneWidget);

    await tester.tap(find.text(_workspace.name));
    for (var frame = 0; frame < 200; frame++) {
      if (find.byKey(shellScaffoldKey).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
    // Settle the entry transition, and with it the stale state that used to
    // send the stack back to the gate and enter a second shell.
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(await storage.read(key: 'selected_workspace_id'), _workspace.id);
    expect(find.byKey(shellScaffoldKey), findsOneWidget);
    // A phone shell leads with its lens header rather than the desktop rail.
    expect(find.byKey(const ValueKey('lens-switcher')), findsOneWidget);
  });
}
