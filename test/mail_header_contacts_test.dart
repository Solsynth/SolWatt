import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/mail/mail_address_suggestion.dart';
import 'package:solwatt/mail/mail_screen.dart';
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
  subject: 'Weekly sync',
  body: 'Notes are in the doc.',
  contentType: 'text/plain',
  isDraft: false,
  isRead: true,
  from: const MailRecipient(address: 'alice', name: 'Alice'),
  to: const [
    MailRecipient(address: 'bob@example.com', name: 'Bob'),
    MailRecipient(address: 'carol@example.com'),
    // One of the account's own aliases, stored the way the server stores a
    // local-only address: no name in the message, no domain either.
    MailRecipient(address: 'personal'),
  ],
  cc: const [MailRecipient(address: 'dan@example.com', name: 'Dan')],
  createdAt: DateTime(2026, 9, 25, 10, 30),
);

final _thread = MailThread(
  id: 't-1',
  mailboxId: 'mb-1',
  subject: 'Weekly sync',
  messageCount: 1,
  unreadCount: 0,
  participants: const ['alice@example.com'],
  latestMessage: _email,
  latestAt: DateTime(2026, 9, 25, 10, 30),
);

void main() {
  testWidgets('the message header lists sender and recipients as chips', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => switch (call.method) {
        'isMaximized' => false,
        _ => null,
      },
    );
    final writes = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          writes.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );

    tester.view.physicalSize = const Size(400, 800);
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
          // Alice is a known sender and `personal` is one of the account's
          // own aliases; the rest of the recipients are strangers.
          mailSenderIndexProvider.overrideWith(
            (ref) async => const {
              'alice@example.com': MailAddressSuggestion(
                address: 'alice@example.com',
                avatarUrl: 'https://example.com/alice.png',
                avatarSource: 'bimi',
                gravatarUrl: '',
              ),
              'personal@example.com': MailAddressSuggestion(
                address: 'personal@example.com',
                name: 'Personal',
                avatarUrl: '',
                avatarSource: '',
                gravatarUrl: '',
                alias: true,
              ),
            },
          ),
          threadsProvider.overrideWith(
            (ref, query) async =>
                PaginatedResult<MailThread>(items: [_thread], totalCount: 1),
          ),
          threadProvider.overrideWith((ref, id) async => [_email]),
          emailProvider.overrideWith((ref, id) async => _email),
          realtimeBridgeProvider.overrideWith((ref) => RealtimeBridge(ref)),
          websocketStateProvider.overrideWith(WebSocketStateNotifier.new),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en', 'US')],
          path: 'assets/i18n',
          fallbackLocale: const Locale('en', 'US'),
          useFallbackTranslations: true,
          child: const SolWattApp(),
        ),
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );

    // Open the conversation: the header belongs to the message pane.
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );

    // From, To (three) and Cc (one): a chip each, names where there is one and
    // the address where there is not. No row spells out "Name <address>".
    expect(find.byType(EmailRecipientChip), findsNWidgets(5));
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Dan'), findsOneWidget);
    expect(find.text('carol@example.com'), findsOneWidget);
    // The alias the message left unnamed reads as the mailbox the index knows,
    // not as a stranger's address.
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('personal@example.com'), findsNothing);
    expect(find.textContaining('<'), findsNothing);
    // The senders index avatar reaches the chip, keyed by the address the chip
    // maps a local-only sender onto its mail host for.
    expect(
      find.descendant(
        of: find.byType(EmailRecipientChip),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    while (tester.takeException() != null) {}

    // The sender's chip answers a tap with the address and a copy action.
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.text('alice@example.com'), findsOneWidget);
    await tester.tap(find.byIcon(Symbols.content_copy));
    await tester.pumpAndSettle();
    expect(writes, ['alice@example.com']);
  });
}
