import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/mail/mail_screen.dart';
import 'package:solwatt/network.dart';
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
  latestMessage: email,
  latestAt: DateTime(2026, 9, 25, 10, 30),
);

/// Pumps the mail list with [email] as its only thread.
Future<void> _pumpMailList(WidgetTester tester, MailEmail email) async {
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
        broadsProvider.overrideWith((ref) async => const <Broad>[]),
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

void main() {
  testWidgets('compose: compact fields, collapsed cc/bcc, full-screen body, '
      'preset styles, keyboard shortcuts', (tester) async {
    await _pumpMailList(tester, _email);

    // Open compose from the mail list FAB.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Compose'), findsOneWidget);

    // To/Subject visible; Cc/Bcc collapsed by default (toggle on To suffix).
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Subject'), findsOneWidget);
    expect(find.byTooltip('Cc/Bcc'), findsOneWidget);
    expect(find.text('Cc'), findsNothing);
    expect(find.text('Bcc'), findsNothing);

    // The from picker wears the same box as the text fields, and still
    // switches the mailbox it sends from. (A field's decoration hangs below
    // it, and the list pane keeps a picker of its own: take the last of each.)
    final fromBox = find.descendant(
      of: find.byType(DropdownButtonFormField<String>).last,
      matching: find.byType(InputDecorator),
    );
    final subjectBox = find.descendant(
      of: find.byType(TextField).last,
      matching: find.byType(InputDecorator),
    );
    final fromDecoration = tester
        .widget<InputDecorator>(fromBox.first)
        .decoration;
    final subjectDecoration = tester
        .widget<InputDecorator>(subjectBox.first)
        .decoration;
    expect(fromDecoration.filled, isTrue);
    expect(fromDecoration.fillColor, subjectDecoration.fillColor);
    expect(fromDecoration.border, subjectDecoration.border);
    expect(
      tester.getRect(fromBox.first).height,
      tester.getRect(subjectBox.first).height,
    );

    await tester.tap(fromBox.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personal').last);
    await tester.pumpAndSettle();
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Work'), findsNothing);

    // Expanding the toggle reveals Cc/Bcc.
    await tester.tap(find.byTooltip('Cc/Bcc'));
    await tester.pumpAndSettle();
    expect(find.text('Cc'), findsOneWidget);
    expect(find.text('Bcc'), findsOneWidget);
    final bodyFinder = find.byKey(const ValueKey('compose-body'));
    final toField = find.byType(TextField).first;
    final toBox = find.ancestor(
      of: toField,
      matching: find.byType(InputDecorator),
    );

    // The field's text box sits centered in its box — the caret had been
    // squeezed against the top by padding the box could not fit.
    final toFrame = tester.getRect(toBox.first);
    final toText = tester.getRect(
      find.descendant(of: toBox.first, matching: find.byType(EditableText)),
    );
    expect(
      toText.top - toFrame.top,
      moreOrLessEquals(toFrame.bottom - toText.bottom, epsilon: 0.5),
    );

    // The Cc/Bcc toggle lives inside the To field, not beside it.
    final toggle = tester.getRect(find.byTooltip('Cc/Bcc'));
    expect(toFrame.left, lessThan(toggle.left));
    expect(toFrame.right, greaterThanOrEqualTo(toggle.right));
    expect(toFrame.top, lessThan(toggle.top));
    expect(toFrame.bottom, greaterThan(toggle.bottom));

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

    // Cc carries chips the same way (its field follows To's, then Bcc).
    final ccField = find.byType(TextField).at(1);
    await tester.enterText(ccField, 'erin@example.com');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(ccField).controller!.text, isEmpty);
    expect(find.text('erin@example.com'), findsOneWidget);

    QuillController quill() =>
        tester.widget<QuillEditor>(bodyFinder).controller;
    expect(tester.getSize(bodyFinder).height, greaterThan(200));

    // Preset style buttons are on the toolbar; H1 formats the selected line.
    expect(find.text('H1'), findsOneWidget);
    expect(find.text('H2'), findsOneWidget);
    expect(find.text('H3'), findsOneWidget);
    quill().document.insert(0, 'Hello world');
    quill().updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 11),
      ChangeSource.local,
    );
    await tester.tap(find.text('H1'));
    await tester.pump();
    expect(quill().getSelectionStyle().attributes.keys, contains('header'));

    // Body sits in a rounded card that highlights while focused.
    await tester.tap(bodyFinder);
    await tester.pump();
    final card = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('compose-body-card')),
    );
    final cardDecoration = card.decoration! as BoxDecoration;
    expect(cardDecoration.borderRadius, BorderRadius.circular(12));

    // Emptying the row takes its chips back, and then a draft has no one to
    // go to.
    await tester.enterText(toField, '');
    while (find.byTooltip('Remove recipient').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('Remove recipient').first);
      await tester.pumpAndSettle();
    }
    expect(find.byType(EmailRecipientChip), findsNothing);
    await tester.tap(find.byTooltip('Save draft'));
    await tester.pump();
    expect(find.text('Add at least one recipient.'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.enterText(toField, 'alice@example.net');
    await tester.pumpAndSettle();

    // Escape closes the compose sheet (works while the editor is focused).
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Compose'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // Replying loads the quoted HTML into the editor via HTML→Delta.
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(find.text('Compose'), findsOneWidget);
    expect(find.text('Re: Hello there'), findsOneWidget);
    // The sender the message is going back to arrives as a chip.
    expect(
      find.descendant(
        of: find.byType(EmailRecipientChip),
        matching: find.text('Alice'),
      ),
      findsOneWidget,
    );
    final replyBody = find.byKey(const ValueKey('compose-body'));
    final replyQuill = tester.widget<QuillEditor>(replyBody).controller;
    expect(replyQuill.document.toPlainText(), contains('Hi from Alice'));
    // The quoted image renders as an embed instead of failing the line that
    // holds it: the editor builds what it does not recognise.
    expect(tester.takeException(), isNull);
    final quotedImage = tester.widget<Image>(
      find.descendant(of: replyBody, matching: find.byType(Image)),
    );
    expect(
      quotedImage.image,
      isA<NetworkImage>().having(
        (network) => network.url,
        'url',
        'https://example.com/pic.png',
      ),
    );
  });
}
