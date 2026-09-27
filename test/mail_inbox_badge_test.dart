import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/mail/mail_address_suggestion.dart';
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

/// Answers the Inbox unread count from its own state, so the rail badge can
/// only move when the UI asks the server again after a write.
class _FakeMailClient extends WattEngineClient {
  _FakeMailClient() : super(SolarNetworkAuthenticator(FlutterSecureStorage()));

  final markedRead = <String>[];
  int inboxUnread = 1;

  @override
  Future<int> listUnreadInboxCount(String mailboxId) async => inboxUnread;

  @override
  Future<void> markEmailRead(String emailId) async {
    markedRead.add(emailId);
    inboxUnread = 0;
  }
}

/// The one conversation in the fixture, read or unread to match the server.
MailThread _thread({required bool unread}) => MailThread(
  id: 't-1',
  mailboxId: 'mb-1',
  subject: 'Invoice for September',
  messageCount: 1,
  unreadCount: unread ? 1 : 0,
  participants: const ['alice@example.com'],
  latestMessage: MailEmail(
    id: 'e-1',
    mailboxId: 'mb-1',
    threadId: 't-1',
    subject: 'Invoice for September',
    body: 'Here is the invoice.',
    contentType: 'text/plain',
    isDraft: false,
    folder: 'inbox',
    from: const MailRecipient(address: 'alice@example.com', name: 'Alice'),
    isRead: !unread,
    createdAt: DateTime(2026, 9, 25, 10),
  ),
  latestAt: DateTime(2026, 9, 25, 10),
);

Future<void> _pumpMailApp(WidgetTester tester, _FakeMailClient client) async {
  tester.binding.platformDispatcher.platformBrightnessTestValue =
      Brightness.dark;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (call) async => switch (call.method) {
      'isMaximized' => false,
      _ => null,
    },
  );

  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
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
        mailCredentialsProvider.overrideWith(
          (ref) async => const <MailCredential>[],
        ),
        mailSenderIndexProvider.overrideWith(
          (ref) async => const <String, MailAddressSuggestion>{},
        ),
        // Rebuilt on every invalidation, straight off the client's state: the
        // list and the badge have to agree again after a write.
        threadsProvider.overrideWith((ref, query) async {
          final thread = _thread(unread: client.inboxUnread > 0);
          return PaginatedResult<MailThread>(items: [thread], totalCount: 1);
        }),
        threadProvider.overrideWith(
          (ref, id) async => [
            _thread(unread: client.inboxUnread > 0).latestMessage,
          ],
        ),
        emailProvider.overrideWith(
          (ref, id) async =>
              _thread(unread: client.inboxUnread > 0).latestMessage,
        ),
        wattEngineClientProvider.overrideWith((ref) => client),
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

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('reading a conversation clears the Inbox badge on the rail', (
    tester,
  ) async {
    final client = _FakeMailClient();
    await _pumpMailApp(tester, client);

    // The rail's Inbox destination carries the unread count the server
    // reported at launch.
    expect(find.text('Invoice for September'), findsWidgets);
    final rail = find.byType(NavigationRail);
    final badge = find.descendant(of: rail, matching: find.byType(Badge));
    expect(badge, findsOneWidget);
    expect(
      find.descendant(of: badge, matching: find.text('1')),
      findsOneWidget,
    );

    // Opening the conversation marks it read, so the badge has to follow the
    // list instead of freezing at the count from launch.
    await tester.tap(find.text('Invoice for September').first);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );

    expect(client.markedRead, ['e-1']);
    expect(
      find.descendant(of: rail, matching: find.byType(Badge)),
      findsNothing,
    );
  });
}
