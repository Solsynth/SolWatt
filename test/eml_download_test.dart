import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/main.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/realtime/realtime.dart';
import 'package:solwatt/websocket.dart';

const _mailboxWork = MailMailbox(
  id: 'mb-1',
  accountId: 'acc-1',
  workspaceId: 'ws-1',
  address: 'work@example.com',
  name: 'Work',
  isDefault: true,
  isVerified: true,
);

const _workspace = Workspace(
  id: 'ws-1',
  slug: 'ws-1',
  name: 'Test Workspace',
  isBundled: false,
);

final _email = MailEmail(
  id: 'e-1',
  mailboxId: 'mb-1',
  subject: 'MiMo-V2.6 preview',
  // Plain text so the detail pane renders without a webview (webviews can't
  // run under the widget-test harness); the download flow is webview-agnostic.
  body: 'Hello from the test message.',
  contentType: 'text/plain',
  isDraft: false,
  from: MailRecipient(address: 'alice@example.com', name: 'Alice'),
  isRead: false,
  createdAt: DateTime(2026, 9, 25, 10, 30),
);

/// Captures the client-side half of the EML download: the endpoint call must
/// happen before the save dialog is offered.
class _FakeMailClient extends WattEngineClient {
  _FakeMailClient() : super(SolarNetworkAuthenticator(FlutterSecureStorage()));

  bool emlDownloaded = false;

  @override
  Future<Uint8List> downloadEmailEml(String emailId) async {
    emlDownloaded = true;
    return Uint8List.fromList(
      utf8.encode('From: alice@example.com\r\nSubject: $emailId\r\n\r\nbody'),
    );
  }
}

void main() {
  testWidgets(
    'detail: more menu downloads the .eml stream from /emails/{id}/eml',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async => switch (call.method) {
          'isMaximized' => false,
          _ => null,
        },
      );

      final fakeClient = _FakeMailClient();

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appAccessProvider.overrideWith(
              (ref) => const AsyncValue.data(AppAccess.ready),
            ),
            selectedWorkspaceProvider.overrideWith((ref) async => _workspace),
            mailboxesProvider.overrideWith(
              (ref) async => const [_mailboxWork],
            ),
            mailHostProvider.overrideWith((ref) async => 'example.com'),
            mailboxUnreadCountsProvider.overrideWith(
              (ref) async => const {'mb-1': 1},
            ),
            emailsProvider.overrideWith(
              (ref, filter) async =>
                  PaginatedResult<MailEmail>(items: [_email], totalCount: 1),
            ),
            emailProvider.overrideWith((ref, id) async => _email),
            wattEngineClientProvider.overrideWith((ref) => fakeClient),
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

      // Open the detail pane.
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );

      // The "more" menu carries the download action.
      await tester.tap(find.byIcon(Symbols.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Download .eml file'), findsOneWidget);

      // Selecting it hits the client's EML endpoint. The save dialog itself
      // is a platform channel that does not exist under the test harness, so
      // the save step fails into the error snackbar — the endpoint call is
      // what this test pins.
      await tester.tap(find.text('Download .eml file'));
      await tester.pumpAndSettle();
      expect(fakeClient.emlDownloaded, isTrue);
      expect(tester.takeException(), isNull);

      debugDefaultTargetPlatformOverride = null;
    },
  );
}
