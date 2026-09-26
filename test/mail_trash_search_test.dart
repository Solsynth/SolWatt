import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
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

MailEmail _email({required String id, required String folder}) => MailEmail(
  id: id,
  mailboxId: 'mb-1',
  threadId: 'thread-$id',
  subject: 'Subject $id',
  body: 'Body',
  contentType: 'text/plain',
  isDraft: false,
  folder: folder,
  from: const MailRecipient(address: 'alice@example.com', name: 'Alice'),
  createdAt: DateTime(2026, 9, 25, 10),
);

MailThread _thread(MailEmail message) => MailThread(
  id: message.threadId!,
  mailboxId: 'mb-1',
  subject: message.subject,
  messageCount: 1,
  unreadCount: 0,
  participants: const ['alice@example.com'],
  latestMessage: message,
  latestAt: DateTime(2026, 9, 25, 10),
);

/// Records what the mail UI asked the server to do, and answers each folder
/// with its own conversations so switching folders changes the list.
class _FakeMailClient extends WattEngineClient {
  _FakeMailClient() : super(SolarNetworkAuthenticator(FlutterSecureStorage()));

  final deleted = <String>[];
  final permanentlyDeleted = <String>[];
  final moved = <(String, String)>[];
  final emptiedTrash = <String>[];
  final threadQueries = <({String? mailboxId, String? folder, String? q})>[];

  @override
  Future<void> deleteEmail(String emailId) async {
    deleted.add(emailId);
  }

  @override
  Future<void> deleteEmailPermanently(String emailId) async {
    permanentlyDeleted.add(emailId);
  }

  @override
  Future<void> moveEmail(String emailId, String folder) async {
    moved.add((emailId, folder));
  }

  @override
  Future<int> emptyTrash(String mailboxId) async {
    emptiedTrash.add(mailboxId);
    return 3;
  }

  @override
  Future<PaginatedResult<MailThread>> listThreads(
    String? mailboxId, {
    String? folder,
    String? q,
    String? status,
    bool? isFlagged,
    String? from,
    String? to,
    bool? hasAttachments,
    int offset = 0,
    int take = 20,
  }) async {
    threadQueries.add((mailboxId: mailboxId, folder: folder, q: q));
    return const PaginatedResult<MailThread>(items: [], totalCount: 0);
  }
}

/// The mail tab starts on [folder]; the list itself is stubbed per folder.
class _FolderNotifier extends SelectedFolderNotifier {
  _FolderNotifier(this.folder);

  final String folder;

  @override
  String build() => folder;
}

Future<MailThread> _pumpMailApp(WidgetTester tester, _FakeMailClient client) async {
  tester.binding.platformDispatcher.platformBrightnessTestValue =
      Brightness.dark;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (call) async => switch (call.method) {
      'isMaximized' => false,
      _ => null,
    },
  );

  final inbox = _thread(_email(id: 'e-1', folder: 'inbox'));
  final second = _thread(_email(id: 'e-2', folder: 'inbox'));
  final trashed = _thread(_email(id: 'e-3', folder: 'trash'));
  final messages = {
    for (final thread in [inbox, second, trashed]) thread.id: thread,
  };
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
        selectedFolderProvider.overrideWith(() => _FolderNotifier('inbox')),
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
        threadsProvider.overrideWith((ref, query) async {
          // The inbox holds two conversations, Trash holds one, and a search
          // spans both because it drops the folder scope.
          final threads = query.filter.q == null
              ? (query.filter.folder == 'trash'
                    ? [trashed]
                    : [inbox, second])
              : [inbox, trashed];
          return PaginatedResult<MailThread>(
            items: threads,
            totalCount: threads.length,
          );
        }),
        threadProvider.overrideWith(
          (ref, id) async => [messages[id]!.latestMessage],
        ),
        emailProvider.overrideWith((ref, id) async => messages.values
            .firstWhere((thread) => thread.latestMessage.id == id)
            .latestMessage),
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
  return inbox;
}

/// Deletes the ticked conversations: the selection bar's delete action, then
/// the dialog's [confirmLabel]. The pumps stay bounded so the confirmation
/// snackbar is still on screen for the caller to assert.
Future<void> _deleteSelection(WidgetTester tester, String confirmLabel) async {
  await tester.tap(find.byKey(const ValueKey('mail-selection-delete')));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, confirmLabel));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Lets the list settle again after an action's snackbar was asserted.
Future<void> _settleMail(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

/// Switches the desktop rail to [folder], which is how a wide screen reaches
/// Trash.
Future<void> _openFolder(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
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

  test('a search spans every mailbox and folder, a browse does not', () async {
    final client = _FakeMailClient();
    final container = ProviderContainer(
      overrides: [wattEngineClientProvider.overrideWith((ref) => client)],
    );
    addTearDown(container.dispose);

    await container.read(
      threadsProvider((
        filter: (
          mailboxId: 'mb-1',
          folder: 'sent',
          q: 'invoice',
          status: null,
          isFlagged: null,
          from: null,
          to: null,
          hasAttachments: null,
        ),
        take: 20,
      )).future,
    );
    expect(client.threadQueries.last.mailboxId, isNull);
    expect(client.threadQueries.last.folder, isNull);
    expect(client.threadQueries.last.q, 'invoice');

    await container.read(
      threadsProvider((
        filter: (
          mailboxId: 'mb-1',
          folder: 'sent',
          q: null,
          status: null,
          isFlagged: null,
          from: null,
          to: null,
          hasAttachments: null,
        ),
        take: 20,
      )).future,
    );
    expect(client.threadQueries.last.mailboxId, 'mb-1');
    expect(client.threadQueries.last.folder, 'sent');
  });

  testWidgets('mail list multi-selects, trashes, purges and searches wide', (
    tester,
  ) async {
    final client = _FakeMailClient();
    await _pumpMailApp(tester, client);
    expect(find.text('Subject e-1'), findsWidgets);
    expect(find.text('Subject e-2'), findsWidgets);

    // Multi-select: the header action enters the mode, rows tick instead of
    // opening, and Select all takes the whole loaded page.
    await tester.tap(find.byIcon(Symbols.select_check_box));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select All'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    // The ticked conversations leave the Inbox for Trash in one action: the
    // bar's delete plus the dialog's confirmation.
    await _deleteSelection(tester, 'Delete');
    expect(client.deleted, ['e-1', 'e-2']);
    expect(client.permanentlyDeleted, isEmpty);
    expect(find.text('Moved 2 conversations to Trash.'), findsOneWidget);

    // Trash offers the sweep, and deleting there is permanent.
    await _openFolder(tester, 'Trash');
    expect(find.byIcon(Symbols.delete_sweep), findsOneWidget);
    expect(find.text('Subject e-3'), findsWidgets);

    await tester.tap(find.byIcon(Symbols.select_check_box));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select All'));
    await tester.pumpAndSettle();
    await _deleteSelection(tester, 'Delete permanently');
    expect(client.permanentlyDeleted, ['e-3']);
    expect(client.deleted, ['e-1', 'e-2']);
    expect(find.text('Permanently deleted 1 conversations.'), findsOneWidget);
    await _settleMail(tester);

    // Emptying Trash is its own action, next to the search button.
    await tester.tap(find.byIcon(Symbols.delete_sweep));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Empty trash'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(client.emptiedTrash, ['mb-1']);
    expect(find.text('Deleted 3 messages from Trash.'), findsOneWidget);
    await _settleMail(tester);

    // A search drops the folder scope: the list says so, and each hit names
    // the mailbox and shows the row's own checkbox affordance.
    await tester.tap(find.byIcon(Symbols.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'invoice');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Searching every mailbox and folder'), findsOneWidget);
    expect(find.text('Work'), findsWidgets);
    // Trash mail is part of the result: the search dropped the folder scope.
    expect(find.text('Subject e-3'), findsWidgets);
  });
}
