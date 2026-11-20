import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/mail/mail_screen.dart';
import 'package:solwatt/ideask/ideask_providers.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/mail/mail_address_suggestion.dart';
import 'package:solwatt/theme.dart';

const _mailboxWork = MailMailbox(
  id: 'mb-1',
  accountId: 'acc-1',
  workspaceId: 'ws-1',
  address: 'work@example.com',
  name: 'Work',
  isDefault: true,
  isVerified: true,
);

const _mailboxPersonal = MailMailbox(
  id: 'mb-2',
  accountId: 'acc-1',
  workspaceId: 'ws-1',
  address: 'me@example.com',
  name: 'Personal',
  isVerified: true,
);

const _workspace = Workspace(id: 'ws-1', slug: 'ws-1', name: 'Test Workspace');

final _email = MailEmail(
  id: 'e-1',
  mailboxId: 'mb-1',
  subject: 'Hello there',
  body: 'Hi from Alice<br><img src="https://example.com/pic.png">',
  isDraft: false,
  from: MailRecipient(address: 'alice@example.com', name: 'Alice'),
  isRead: false,
  createdAt: DateTime(2026, 9, 25, 10, 30),
);

MailThread _threadFor(MailEmail email) => MailThread(
  id: 't-1',
  mailboxId: 'mb-1',
  subject: email.subject,
  messageCount: 1,
  unreadCount: 1,
  participants: const ['alice@example.com'],
  latestAt: DateTime(2026, 9, 25, 10, 30),
  latestMessage: email,
);

/// Records what the composer hands the server, so the test can tell a send from
/// a draft and read what went with it.
class _FakeMailClient extends WattEngineClient {
  _FakeMailClient() : super(SolarNetworkAuthenticator(FlutterSecureStorage()));

  final sent =
      <({bool isDraft, List<MailRecipient> to, String subject, String body})>[];

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
  }) async {
    sent.add((isDraft: isDraft, to: to, subject: subject, body: body));
    return _email;
  }
}

/// Pumps the mail list with [email] as its only thread.
///
/// The whole app is pumped once per file: the shell's router is a singleton, so
/// a second pump would mount a second router over the first.
Future<void> _pumpMailList(
  WidgetTester tester,
  MailEmail email,
  _FakeMailClient client,
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
        mailboxesProvider.overrideWith(
          (ref) async => const [_mailboxWork, _mailboxPersonal],
        ),
        mailHostProvider.overrideWith((ref) async => 'example.com'),
        mailboxUnreadCountsProvider.overrideWith(
          (ref) async => const {'mb-1': 2},
        ),
        mailCredentialsProvider.overrideWith(
          (ref) async => const <MailCredential>[],
        ),
        threadsProvider.overrideWith(
          (ref, query) async => PaginatedResult<MailThread>(
            items: [_threadFor(email)],
            totalCount: 1,
          ),
        ),
        threadProvider.overrideWith((ref, id) async => [email]),
        emailProvider.overrideWith((ref, id) async => email),
        ideaskBrowserProvider.overrideWith(
            (ref) async => const IdeaskBrowserState(),
          ),
        wattEngineClientProvider.overrideWith((ref) => client),
        mailAddressSuggestionsProvider.overrideWith((ref, request) async {
          if (request.query.toLowerCase() != 'alice') return const [];
          return const [
            MailAddressSuggestion(
              address: 'alice@example.net',
              name: 'Alice Contact',
              avatarUrl: '',
              avatarSource: 'gravatar',
              gravatarUrl: '',
            ),
          ];
        }),
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

/// The composer's own subtree. On a wide window the mail list stays on screen
/// beside the composer, and it carries labels of its own.
Finder _composer() => find
    .ancestor(
      of: find.byKey(const ValueKey('compose-body')),
      matching: find.byType(KeyboardListener),
    )
    .first;

/// The composer's header row for [label].
Rect _rowOf(WidgetTester tester, String label, Finder composer) =>
    tester.getRect(
      find
          .ancestor(
            of: find.descendant(of: composer, matching: find.text(label)),
            matching: find.byType(Row),
          )
          .first,
    );

/// The composer's header button wearing [tooltip].
Finder _headerButtonFinder(String tooltip, Finder composer) => find
    .ancestor(
      of: find.descendant(of: composer, matching: find.byTooltip(tooltip)),
      matching: find.byType(IconButton),
    )
    .first;

/// The composer's header button wearing [tooltip].
IconButton _headerButton(
  WidgetTester tester,
  String tooltip,
  Finder composer,
) => tester.widget<IconButton>(_headerButtonFinder(tooltip, composer));

Future<void> _tapHeaderButton(
  WidgetTester tester,
  String tooltip,
  Finder composer,
) => tester.tap(_headerButtonFinder(tooltip, composer));

/// The tooltip the composer's close button wears right now.
String _closeTooltip(WidgetTester tester, Finder composer) => tester
    .widget<Tooltip>(
      find.descendant(of: composer, matching: find.byType(Tooltip)).first,
    )
    .message!;

const _body = ValueKey('compose-body');

/// The text the editor paints, read from the document it is editing.
String _bodyText(WidgetTester tester) => tester
    .widget<SolarBlockEditor>(find.byType(SolarBlockEditor, skipOffstage: false))
    .controller
    .editorState
    .document
    .root
    .children
    .map((node) => node.delta?.toPlainText() ?? '')
    .join('\n');

Future<void> _openComposer(WidgetTester tester) async {
  // The shell starts on the Mail lens, so its compose FAB is already there;
  // the check keeps the helper usable from any starting lens.
  if (find.byType(FloatingActionButton).evaluate().isEmpty) {
    await tester.tap(find.byTooltip('Mail').first);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
}

/// Advances past a submit's animations without running its snackbar out: a
/// settled pump would wait the toast away before the caller can read it.
Future<void> _settleComposer(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

/// Lets the list settle again after an action's snackbar was asserted.
Future<void> _settleMail(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

void main() {
  testWidgets('compose: one envelope frame, writing at the bottom, and no way '
      'out that loses the message', (tester) async {
    final client = _FakeMailClient();
    await _pumpMailList(tester, _email, client);

    // ---- The composer's frame ----
    await _openComposer(tester);
    final composer = _composer();
    // The header names what the sheet is doing, not the screen it is on.
    expect(
      find.descendant(of: composer, matching: find.text('New message')),
      findsOneWidget,
    );
    expect(find.text('Compose'), findsNothing);
    // Nothing written is nothing to save: an empty composer would only add a
    // blank row to Drafts, so the control is not offered.
    expect(_headerButton(tester, 'Save draft', composer).onPressed, isNull);
    expect(_closeTooltip(tester, composer), 'Close');

    // To/Subject visible; Cc/Bcc collapsed by default (toggle on To suffix).
    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Subject'), findsOneWidget);
    expect(find.byTooltip('Cc/Bcc'), findsOneWidget);
    expect(find.text('Cc'), findsNothing);
    expect(find.text('Bcc'), findsNothing);

    // The header rows are one frame parted by hairlines: they abut instead of
    // floating apart as separate boxes, which is what keeps the surface above
    // the body quiet and gives the body the room.
    final fromRow = _rowOf(tester, 'From', composer);
    final toRow = _rowOf(tester, 'To', composer);
    final subjectRow = _rowOf(tester, 'Subject', composer);
    expect(fromRow.height, toRow.height);
    expect(toRow.height, subjectRow.height);
    expect(toRow.top - fromRow.bottom, 1);
    expect(subjectRow.top - toRow.bottom, 1);

    // The from picker wears the same row as the text fields, and still
    // switches the mailbox it sends from.
    final fromBox = find.descendant(
      of: find.descendant(
        of: composer,
        matching: find.byType(DropdownButtonFormField<String>),
      ),
      matching: find.byType(InputDecorator),
    );
    expect(tester.getRect(fromBox).height, fromRow.height);
    await tester.tap(fromBox.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personal').last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: composer, matching: find.text('Personal')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: composer, matching: find.text('Work')),
      findsNothing,
    );

    final toField = find
        .descendant(of: composer, matching: find.byType(TextField))
        .first;
    final toBox = find.ancestor(
      of: toField,
      matching: find.byType(InputDecorator),
    );

    // The field's text box sits centered in its row — the caret had been
    // squeezed against the top by padding the row could not fit.
    final toFrame = tester.getRect(toBox.first);
    final toText = tester.getRect(
      find.descendant(of: toBox.first, matching: find.byType(EditableText)),
    );
    expect(
      toText.top - toFrame.top,
      moreOrLessEquals(toFrame.bottom - toText.bottom, epsilon: 0.5),
    );

    // The Cc/Bcc toggle lives inside the To row, not beside it.
    final toggle = tester.getRect(find.byTooltip('Cc/Bcc'));
    expect(toFrame.left, lessThan(toggle.left));
    expect(toFrame.right, greaterThanOrEqualTo(toggle.right));
    expect(toFrame.top, lessThan(toggle.top));
    expect(toFrame.bottom, greaterThan(toggle.bottom));

    // Expanding the toggle adds the two rows to the same frame, between the
    // addresses and the subject line.
    await tester.tap(find.byTooltip('Cc/Bcc'));
    await tester.pumpAndSettle();
    expect(find.text('Cc'), findsOneWidget);
    expect(find.text('Bcc'), findsOneWidget);
    final ccRow = _rowOf(tester, 'Cc', composer);
    final expandedSubject = _rowOf(tester, 'Subject', composer);
    expect(ccRow.top, greaterThan(toRow.bottom));
    expect(ccRow.top, lessThan(expandedSubject.top));
    expect(_rowOf(tester, 'Bcc', composer).bottom, expandedSubject.top - 1);
    await tester.tap(find.byTooltip('Cc/Bcc'));
    await tester.pumpAndSettle();
    expect(find.text('Cc'), findsNothing);

    // A picked suggestion becomes a chip and clears the field.
    await tester.enterText(toField, 'alice');
    await tester.pumpAndSettle();
    expect(find.text('Alice Contact'), findsOneWidget);
    expect(find.text('alice@example.net'), findsOneWidget);
    await tester.tap(find.text('Alice Contact'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(toField).controller!.text, isEmpty);
    expect(find.byType(EmailRecipientChip), findsOneWidget);
    expect(find.text('Alice Contact'), findsOneWidget);

    // Enter and a pasted list both commit chips.
    await tester.enterText(toField, 'bob@example.com');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('bob@example.com'), findsOneWidget);
    await tester.enterText(toField, 'carol@example.com, dave@example.com');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(toField).controller!.text, isEmpty);
    expect(find.text('carol@example.com'), findsOneWidget);
    expect(find.text('dave@example.com'), findsOneWidget);

    // Backspace in the empty field takes the last chip back.
    await tester.enterText(toField, '');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(find.text('dave@example.com'), findsNothing);

    // ---- The body is the hero, and the rail closes the flow ----
    final bodyFinder = find.byKey(_body);
    expect(tester.getSize(bodyFinder).height, greaterThan(240));
    final bodyBottom = tester.getRect(bodyFinder).bottom;
    final rail = tester.getRect(find.widgetWithText(FilledButton, 'Send'));
    expect(rail.top, greaterThan(bodyBottom));
    for (final tooltip in ['Formatting', 'Insert link', 'Add attachment']) {
      expect(
        tester.getRect(find.byTooltip(tooltip)).top,
        greaterThan(bodyBottom),
      );
    }

    // Body sits in a rounded card that highlights while focused.
    await tester.tap(bodyFinder);
    await tester.pump();
    final card = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('compose-body-card')),
    );
    expect(
      (card.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(SolRadius.lg),
    );

    // Formatting lives behind Aa and still formats the selected line. The menu
    // opens over the editor, so the selection it applies to has to survive the
    // trip.
    final editor = tester.widget<SolarBlockEditor>(
      find.byType(SolarBlockEditor, skipOffstage: false),
    );
    await tester.tap(bodyFinder);
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('Hello world');
    await tester.pumpAndSettle();
    expect(editor.controller.editorState.selection, isNotNull);
    await tester.tap(find.byTooltip('Formatting'));
    await tester.pumpAndSettle();
    expect(find.text('Heading 1'), findsOneWidget);
    expect(find.text('Bold'), findsOneWidget);
    await tester.tap(find.text('Heading 1'));
    await tester.pumpAndSettle();
    expect(
      editor.controller.editorState.document.root.children.first.type,
      'heading',
    );

    // Something written is something to save, so the control comes back.
    expect(_headerButton(tester, 'Save draft', composer).onPressed, isNotNull);
    expect(_closeTooltip(tester, composer), 'Close and save draft');

    // Escape is a close, not a discard: what was written becomes a draft
    // instead of disappearing with the sheet.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settleComposer(tester);
    expect(find.byKey(_body), findsNothing);
    expect(client.sent.single.isDraft, isTrue);
    expect(client.sent.single.body, contains('Hello world'));
    await _settleMail(tester);

    // ---- Sending needs somewhere to go, a draft does not ----
    await _openComposer(tester);
    final subjectField = find
        .descendant(of: composer, matching: find.byType(TextField))
        .at(1);
    TextField subject() => tester.widget<TextField>(subjectField);
    await tester.enterText(subjectField, 'Solar farm maintenance');
    await tester.pumpAndSettle();
    expect(subject().controller!.text, 'Solar farm maintenance');

    // Sending is refused, and says why without leaving.
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pump();
    expect(find.text('Add at least one recipient.'), findsOneWidget);
    expect(client.sent.length, 1);

    // A draft needs somewhere to live, not somewhere to go: it saves with no
    // recipient at all, which is the only way a half-addressed message can
    // survive being closed.
    await _tapHeaderButton(tester, 'Save draft', composer);
    await _settleComposer(tester);
    expect(client.sent.length, 2);
    expect(client.sent.last.isDraft, isTrue);
    expect(client.sent.last.to, isEmpty);
    expect(client.sent.last.subject, 'Solar farm maintenance');
    expect(find.text('Draft saved.'), findsOneWidget);
    expect(find.byKey(_body), findsNothing);
    await _settleMail(tester);

    // ---- Closing keeps what was written; only discard throws it away ----
    await _openComposer(tester);
    await tester.enterText(subjectField, 'Panel cleaning');
    await tester.pumpAndSettle();
    await _tapHeaderButton(tester, 'Close and save draft', composer);
    await _settleComposer(tester);
    expect(client.sent.length, 3);
    expect(client.sent.last.isDraft, isTrue);
    expect(client.sent.last.subject, 'Panel cleaning');
    expect(find.text('Draft saved.'), findsOneWidget);
    expect(find.byKey(_body), findsNothing);
    await _settleMail(tester);

    // Discarding asks first, and cancelling keeps the writer where they were.
    await _openComposer(tester);
    await tester.enterText(subjectField, 'Scrap this');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(_body), findsOneWidget);
    expect(subject().controller!.text, 'Scrap this');

    await tester.tap(find.byTooltip('Discard changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Discard changes'));
    await _settleComposer(tester);
    expect(client.sent.length, 3);
    expect(find.byKey(_body), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // ---- A reply names itself, quotes the message, and invents no draft ----
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    final reply = _composer();
    expect(
      find.descendant(of: reply, matching: find.text('Reply')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: reply, matching: find.text('New message')),
      findsNothing,
    );
    expect(find.text('Re: Hello there'), findsOneWidget);
    // The sender the message is going back to arrives as a chip.
    expect(
      find.descendant(
        of: find.byType(EmailRecipientChip),
        matching: find.text('Alice'),
      ),
      findsOneWidget,
    );
    final replyBody = find.byKey(_body);
    expect(
      _bodyText(tester),
      contains('Hi from Alice'),
    );
    // The quoted image renders as an embed instead of failing the line that
    // holds it: the editor builds what it does not recognise.
    expect(tester.takeException(), isNull);
    // The quoted image arrives as an image block, not as text: a paragraph or
    // quote paints only its own delta, so the composer lifts embedded images
    // to top-level blocks where the editor renders them.
    final replyEditor = tester.widget<SolarBlockEditor>(
      find.byType(SolarBlockEditor, skipOffstage: false),
    );
    final quotedImage = replyEditor.controller.editorState.document.root.children
        .firstWhere((node) => node.type == 'image');
    expect(quotedImage.attributes['url'], 'https://example.com/pic.png');
    expect(replyBody, findsOneWidget);

    // A reply opens already addressed and already quoting, and none of that is
    // the writer's doing: closing it untouched leaves no draft behind.
    await _tapHeaderButton(tester, 'Close', reply);
    await tester.pumpAndSettle();
    expect(client.sent.length, 3);
    expect(find.byKey(_body), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
