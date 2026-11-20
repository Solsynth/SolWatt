import 'package:easy_localization/easy_localization.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/gate/gate_page.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/ideask/ideask_providers.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/realtime/realtime.dart';
import 'package:solwatt/route.dart';
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

/// Keeps the offline live-updates pill out of the tree: its message is wider
/// than the test font expects, and this test is about the router.
class _ConnectedWebSocket extends WebSocketStateNotifier {
  @override
  WebSocketConnectionState build() => WebSocketConnectionState.connected;
}

/// The gate and the shell must hand the process-wide shell keys over without a
/// frame in which both claim them.
///
/// Leaving a workspace keeps the shell in the tree until its exit transition
/// ends. Picking one again in that window used to mount a second AppShell next
/// to it; the two `_NavigationShell` widgets both installed `shellScaffoldKey`,
/// which Flutter reports as "Multiple widgets used the same GlobalKey" before
/// it replaces the tree with a blank page. The same key is claimed by the rail
/// (`_desktopNavigationKey`).
void main() {
  testWidgets('a shell left behind hands its keys to its replacement', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': 'token',
      'selected_workspace_id': _workspace.id,
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

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    final prefs = await SharedPreferences.getInstance();
    final storage = FlutterSecureStorage();

    Future<void> pumpFrames([int frames = 60]) async {
      for (var frame = 0; frame < frames; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureStorageProvider.overrideWithValue(storage),
          // Both session and workspace come from storage, so the test can take
          // either away the way the app does.
          authSessionProvider.overrideWith((ref) async {
            final token = await ref
                .watch(secureStorageProvider)
                .read(key: 'auth_token');
            return token == null
                ? null
                : const OAuthSession(accessToken: 'token');
          }),
          // Mirrors the real provider: it reads the stored id, then lists the
          // workspaces over the network before it can answer.
          selectedWorkspaceProvider.overrideWith((ref) async {
            final id = await ref
                .watch(secureStorageProvider)
                .read(key: 'selected_workspace_id');
            await Future<void>.delayed(const Duration(milliseconds: 100));
            return id == null ? null : _workspace;
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

    // The shell for the stored workspace.
    for (var frame = 0; frame < 200; frame++) {
      if (find.byKey(shellScaffoldKey).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byKey(shellScaffoldKey), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(shellScaffoldKey)),
    );
    // Let the gate that entered the shell finish leaving the screen, so the
    // leave below is one navigation and not two overlapping ones.
    await pumpFrames(30);

    // Leaving the active workspace: what `leaveWorkspaceAction` does, without
    // the console screen in front of it.
    await storage.delete(key: 'selected_workspace_id');
    container.invalidate(selectedWorkspaceProvider);
    appRouter.replaceAll([const PageRouteInfo('GateRoute')]);

    // Long enough for the picker to appear, far short of the shell's exit
    // transition: the gate must not bounce back into the shell it just left.
    await pumpFrames(8);
    expect(find.byType(GatePage), findsOneWidget);
    expect(find.byKey(shellScaffoldKey), findsNothing);

    // Picking the workspace again while the old shell is still animating out.
    await tester.tap(
      find.descendant(
        of: find.byType(GatePage),
        matching: find.text(_workspace.name),
      ),
    );
    await pumpFrames(120);

    expect(find.byKey(shellScaffoldKey), findsOneWidget);

    // The session going away still reaches the gate: the guards above only
    // stop a shell the router has already left behind.
    await storage.delete(key: 'auth_token');
    container.invalidate(authSessionProvider);
    await pumpFrames(120);

    expect(find.byKey(shellScaffoldKey), findsNothing);
    expect(find.byType(GatePage), findsOneWidget);
  });
}
