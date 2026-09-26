import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/realtime/realtime.dart';
import 'package:solwatt/websocket.dart';
import 'package:solwatt/mail/mail_address_suggestion.dart';

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

/// The mail list pages conversations by growing its request, so the page after
/// the first one has to be reachable by scrolling to the end of the list.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('reaching the end of the list grows the conversation page', (
    tester,
  ) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => switch (call.method) {
        'isMaximized' => false,
        _ => null,
      },
    );

    /// 40 conversations while the page size is 20, so the first fetch cannot
    /// cover the list and the footer has to say so.
    MailThread threadAt(int index) => MailThread(
      id: 't-$index',
      mailboxId: 'mb-1',
      subject: 'Thread $index',
      messageCount: 1,
      unreadCount: 0,
      participants: const ['alice@example.com'],
      latestMessage: MailEmail(
        id: 'e-$index',
        mailboxId: 'mb-1',
        threadId: 't-$index',
        subject: 'Thread $index',
        body: 'Body $index',
        isDraft: false,
        from: MailRecipient(address: 'alice@example.com', name: 'Alice'),
        isRead: true,
        createdAt: DateTime(2026, 9, 25, 10),
      ),
      latestAt: DateTime(2026, 9, 25, 10),
    );

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appAccessProvider.overrideWith(
            (ref) => const AsyncValue.data(AppAccess.ready),
          ),
          selectedWorkspaceProvider.overrideWith((ref) async => _workspace),
          mailboxesProvider.overrideWith((ref) async => const [_mailboxWork]),
          mailHostProvider.overrideWith((ref) async => 'example.com'),
          mailboxUnreadCountsProvider.overrideWith(
            (ref) async => const {'mb-1': 0},
          ),
          mailCredentialsProvider.overrideWith(
            (ref) async => const <MailCredential>[],
          ),
          mailSenderIndexProvider.overrideWith(
            (ref) async => const <String, MailAddressSuggestion>{},
          ),
          threadsProvider.overrideWith(
            (ref, query) async => PaginatedResult<MailThread>(
              items: [for (var i = 0; i < query.take && i < 40; i++) threadAt(i)],
              totalCount: 40,
            ),
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

    // Only the first page is on screen, so the last conversation of the
    // mailbox is not reachable yet.
    expect(find.text('Thread 0'), findsOneWidget);
    expect(find.text('Thread 39'), findsNothing);

    // Scrolling to the end grows the page instead of stopping at 20 rows.
    for (var attempt = 0; attempt < 8; attempt++) {
      if (find.text('Thread 39').evaluate().isNotEmpty) break;
      await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
      await tester.pumpAndSettle();
    }
    expect(find.text('Thread 39'), findsOneWidget);
  });
}
