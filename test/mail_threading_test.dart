import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

/// Conversation of three messages, oldest first. Two of them are unread, so a
/// thread that was read on open must issue exactly those two reads.
final _conversation = <MailEmail>[
  MailEmail(
    id: 'e-1',
    mailboxId: 'mb-1',
    threadId: 't-1',
    subject: 'Release plan',
    body: 'Oldest message body',
    contentType: 'text/plain',
    isDraft: false,
    from: MailRecipient(address: 'alice@example.com', name: 'Alice'),
    isRead: true,
    createdAt: DateTime(2026, 9, 24, 9),
  ),
  MailEmail(
    id: 'e-2',
    mailboxId: 'mb-1',
    threadId: 't-1',
    subject: 'Re: Release plan',
    body: 'Middle message body',
    contentType: 'text/plain',
    isDraft: false,
    from: MailRecipient(address: 'bob@example.com', name: 'Bob'),
    isRead: false,
    createdAt: DateTime(2026, 9, 25, 9),
  ),
  MailEmail(
    id: 'e-3',
    mailboxId: 'mb-1',
    threadId: 't-1',
    subject: 'Re: Release plan',
    body: 'Newest message body',
    contentType: 'text/plain',
    isDraft: false,
    from: MailRecipient(address: 'carol@example.com', name: 'Carol'),
    isRead: false,
    createdAt: DateTime(2026, 9, 25, 10),
  ),
];

final _thread = MailThread(
  id: 't-1',
  mailboxId: 'mb-1',
  subject: 'Release plan',
  messageCount: 3,
  unreadCount: 2,
  participants: const [
    'carol@example.com',
    'bob@example.com',
    'alice@example.com',
  ],
  latestMessage: _conversation.last,
  latestAt: DateTime(2026, 9, 25, 10),
);

/// Records the per-message writes so conversation-wide actions can be pinned
/// without a live ElecPostal.
class _FakeMailClient extends WattEngineClient {
  _FakeMailClient() : super(SolarNetworkAuthenticator(FlutterSecureStorage()));

  final readMessages = <String>[];
  final deletedMessages = <String>[];
  final movedMessages = <(String, String)>[];

  @override
  Future<void> markEmailRead(String emailId) async {
    readMessages.add(emailId);
  }

  @override
  Future<void> deleteEmail(String emailId) async {
    deletedMessages.add(emailId);
  }

  @override
  Future<void> moveEmail(String emailId, String folder) async {
    movedMessages.add((emailId, folder));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  test('thread payload carries counts, participants and the latest message', () {
    final thread = MailThread.fromJson({
      'id': 't-9',
      'mailbox_id': 'mb-1',
      'subject': 'Release plan',
      'message_count': 4,
      'unread_count': 1,
      'participants': ['carol@example.com', 'bob@example.com'],
      'latest_at': '2026-09-25T10:00:00Z',
      'latest_message': {
        'id': 'e-9',
        'mailbox_id': 'mb-1',
        'thread_id': 't-9',
        'subject': 'Re: Release plan',
        'body': 'Newest body',
        'is_read': false,
        'from': {'address': 'carol@example.com', 'name': 'Carol'},
        'recipients': [
          {'address': 'me@example.com', 'kind': 'to'},
        ],
      },
    });

    expect(thread.id, 't-9');
    expect(thread.messageCount, 4);
    expect(thread.unreadCount, 1);
    expect(thread.isRead, isFalse);
    expect(thread.isMultiMessage, isTrue);
    expect(thread.participants, ['carol@example.com', 'bob@example.com']);
    expect(thread.latestMessage.id, 'e-9');
    expect(thread.latestMessage.threadKey, 't-9');
    expect(thread.latestAt?.toUtc(), DateTime.utc(2026, 9, 25, 10));
  });

  testWidgets(
    'list groups messages into conversations, reads them on open and '
    'switches the pane between messages',
    (tester) async {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async => switch (call.method) {
          'isMaximized' => false,
          _ => null,
        },
      );

      final client = _FakeMailClient();
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appAccessProvider.overrideWith(
              (ref) => const AsyncValue.data(AppAccess.ready),
            ),
            selectedWorkspaceProvider.overrideWith((ref) async => _workspace),
            mailboxesProvider.overrideWith((ref) async => const [_mailboxWork]),
            mailHostProvider.overrideWith((ref) async => 'example.com'),
            mailboxUnreadCountsProvider.overrideWith(
              (ref) async => const {'mb-1': 2},
            ),
            mailCredentialsProvider.overrideWith(
              (ref) async => const <MailCredential>[],
            ),
            mailSenderAvatarUrlsProvider.overrideWith(
              (ref) async => const <String, String>{},
            ),
            threadsProvider.overrideWith(
              (ref, query) async =>
                  PaginatedResult<MailThread>(items: [_thread], totalCount: 1),
            ),
            threadProvider.overrideWith((ref, id) async => _conversation),
            emailProvider.overrideWith((ref, id) async => _conversation.last),
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

      // One row for the conversation, newest sender first, carrying the
      // message count instead of one row per message.
      final row = find.ancestor(
        of: find.text('Carol'),
        matching: find.byType(ListTile),
      );
      expect(row, findsOneWidget);
      expect(find.text('Release plan'), findsWidgets);
      expect(
        find.descendant(of: row, matching: find.text('3')),
        findsOneWidget,
      );

      // Opening the conversation reads it in full: the two unread messages,
      // not the one that was already read.
      await tester.tap(row);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(client.readMessages, ['e-2', 'e-3']);
      // The row previews the newest message's body, so before the pane
      // switches away that text is on screen twice: row and body.
      expect(find.text('Newest message body'), findsNWidgets(2));

      // The pane lists the whole conversation; switching a chip swaps the body
      // to that message.
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      await tester.tap(
        find.descendant(
          of: find.byType(ChoiceChip),
          matching: find.textContaining('Alice'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Oldest message body'), findsOneWidget);
      // Only the row preview is left of the newest message.
      expect(find.text('Newest message body'), findsOneWidget);
    },
  );
}
