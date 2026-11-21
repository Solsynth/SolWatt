import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/ideask/ideask_providers.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/network.dart';

const _mailbox = MailMailbox(
  id: 'mb-1',
  accountId: 'acc-1',
  workspaceId: 'ws-1',
  address: 'work@example.com',
  name: 'Work',
  isDefault: true,
  isVerified: true,
);

const _workspace = Workspace(id: 'ws-1', slug: 'ws-1', name: 'Test Workspace');

final _draft = MailEmail(
  id: 'draft-1',
  mailboxId: 'mb-1',
  threadId: 'thread-draft-1',
  subject: 'Solar plan',
  body: '<p>Half written</p>',
  isDraft: true,
  contentType: 'text/html',
  folder: 'drafts',
  to: const [MailRecipient(address: 'bob@example.com', name: 'Bob')],
);

final _draftThread = MailThread(
  id: 'thread-draft-1',
  mailboxId: 'mb-1',
  subject: 'Solar plan',
  messageCount: 1,
  unreadCount: 0,
  participants: const ['bob@example.com'],
  latestAt: DateTime(2026, 9, 25, 10, 30),
  latestMessage: _draft,
);

class _FakeMailClient extends WattEngineClient {
  _FakeMailClient() : super(SolarNetworkAuthenticator(FlutterSecureStorage()));

  final sent =
      <
        ({
          bool isDraft,
          List<MailRecipient> to,
          String subject,
          String body,
          String? threadId,
        })
      >[];
  final deleted = <String>[];
  final read = <String>[];
  var _nextId = 0;

  @override
  Future<MailEmail> sendEmail({
    required String mailboxId,
    required List<MailRecipient> to,
    List<MailRecipient> cc = const [],
    List<MailRecipient> bcc = const [],
    required String subject,
    required String body,
    List<String> attachmentIds = const [],
    bool isDraft = false,
    String contentType = 'text/plain',
    String? replyToId,
    String? threadId,
  }) async {
    sent.add((
      isDraft: isDraft,
      to: to,
      subject: subject,
      body: body,
      threadId: threadId,
    ));
    return MailEmail(
      id: 'saved-${++_nextId}',
      mailboxId: mailboxId,
      subject: subject,
      body: body,
      isDraft: isDraft,
      contentType: contentType,
      folder: isDraft ? 'drafts' : 'sent',
      threadId: threadId ?? 'thread-draft-1',
    );
  }

  @override
  Future<void> deleteEmailPermanently(String emailId) async =>
      deleted.add(emailId);

  @override
  Future<void> markEmailRead(String emailId) async => read.add(emailId);
}

Future<void> _pumpMail(WidgetTester tester, _FakeMailClient client) async {
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();
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
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appAccessProvider.overrideWith(
          (ref) => const AsyncValue.data(AppAccess.ready),
        ),
        selectedWorkspaceProvider.overrideWith((ref) async => _workspace),
        mailboxesProvider.overrideWith((ref) async => const [_mailbox]),
        mailHostProvider.overrideWith((ref) async => 'example.com'),
        mailboxUnreadCountsProvider.overrideWith(
          (ref) async => const {'mb-1': 0},
        ),
        mailCredentialsProvider.overrideWith(
          (ref) async => const <MailCredential>[],
        ),
        threadsProvider.overrideWith(
          (ref, query) async =>
              PaginatedResult<MailThread>(items: [_draftThread], totalCount: 1),
        ),
        threadProvider.overrideWith((ref, id) async => [_draft]),
        emailProvider.overrideWith((ref, id) async => _draft),
        ideaskBrowserProvider.overrideWith(
          (ref) async => const IdeaskBrowserState(),
        ),
        wattEngineClientProvider.overrideWith((ref) => client),
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

Finder _composer() => find
    .ancestor(
      of: find.byKey(const ValueKey('compose-body')),
      matching: find.byType(KeyboardListener),
    )
    .first;

String _bodyText(WidgetTester tester) => tester
    .widget<SolarBlockEditor>(
      find.byType(SolarBlockEditor, skipOffstage: false),
    )
    .controller
    .editorState
    .document
    .root
    .children
    .map((node) => node.delta?.toPlainText() ?? '')
    .join('\n');

Future<void> _settleComposer(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('drafts: opening a draft resumes the writing, and saving it '
      'supersedes the stored row instead of adding another', (tester) async {
    final client = _FakeMailClient();
    await _pumpMail(tester, client);

    // The draft row is a message being written, not one to read: tapping it
    // opens the composer seeded from the stored draft.
    await tester.tap(find.text('Solar plan'));
    await tester.pumpAndSettle();
    final composer = _composer();
    expect(
      find.descendant(of: composer, matching: find.text('Edit draft')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: composer, matching: find.text('Solar plan')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: composer, matching: find.text('Bob')),
      findsOneWidget,
    );
    expect(_bodyText(tester), contains('Half written'));
    // Opening a draft is not reading it, so it never goes through mark-read.
    expect(client.read, isEmpty);

    // Sending writes a real message, then retires the draft row it replaced.
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await _settleComposer(tester);
    expect(client.sent.single.isDraft, isFalse);
    expect(client.sent.single.to.single.address, 'bob@example.com');
    expect(client.sent.single.subject, 'Solar plan');
    // A resumed reply draft stays in the conversation it was written for.
    expect(client.sent.single.threadId, 'thread-draft-1');
    expect(client.deleted, contains('draft-1'));
    expect(find.byKey(const ValueKey('compose-body')), findsNothing);

    // Reopening and saving keeps the writing a draft, with the same
    // replace-not-duplicate rule.
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solar plan'));
    await tester.pumpAndSettle();
    final reopened = _composer();
    final subjectField = find
        .descendant(of: reopened, matching: find.byType(TextField))
        .at(1);
    await tester.enterText(subjectField, 'Solar plan revised');
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: reopened, matching: find.byTooltip('Save draft')),
    );
    await _settleComposer(tester);

    expect(client.sent.length, 2);
    expect(client.sent.last.isDraft, isTrue);
    expect(client.sent.last.subject, 'Solar plan revised');
    expect(client.deleted, ['draft-1', 'draft-1']);
    expect(find.byKey(const ValueKey('compose-body')), findsNothing);
  });
}
