import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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
  body:
      '<p><a href="https://example.com/article">Open the article</a></p>'
      '<p>Image: [image: missing.png] and cid:missing@example.com</p>',
  contentType: 'text/html',
  isDraft: false,
  from: MailRecipient(address: 'alice@example.com', name: 'Alice'),
  isRead: false,
  createdAt: DateTime(2026, 9, 25, 10, 30),
);

void main() {
  testWidgets(
    'detail: email links launch externally; preview markers are stripped',
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

      final launched = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        (call) async {
          if (call.method == 'launch') {
            launched.add((call.arguments as Map)['url'] as String);
            return true;
          }
          if (call.method == 'canLaunch') return true;
          if (call.method == 'supportsMode') return true;
          return null;
        },
      );

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

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );

      // The link renders as tappable text in the body.
      final bodyLink = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.textContaining('Open the article', findRichText: true),
      );
      expect(bodyLink, findsWidgets);

      // Preview-generation markers with no matching attachment are dropped.
      expect(
        find.textContaining('[image:', findRichText: true),
        findsNothing,
        reason: 'unmatched [image:] markers must not render as literal text',
      );
      expect(
        find.textContaining('cid:missing', findRichText: true),
        findsNothing,
        reason: 'unmatched cid: refs must not render as literal text',
      );

      // Tapping the link launches it in the default browser (never inside
      // the reading pane), even with text selection enabled on desktop.
      final linkTopLeft = tester.getTopLeft(bodyLink);
      await tester.tapAt(linkTopLeft + const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(launched, contains('https://example.com/article'));
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
