import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solwatt/mail/mail_address_suggestion.dart';
import 'package:solwatt/mail/mail_screen.dart';
import 'package:solwatt/network.dart';

/// A local-only address: the mail host is what makes it sendable.
const _alice = MailRecipient(address: 'alice', name: 'Alice Chen');
const _bob = MailRecipient(address: 'bob@example.com');

/// What the senders index holds for `alice@example.com`.
const _aliceSuggestion = MailAddressSuggestion(
  address: 'alice@example.com',
  avatarUrl: 'https://example.com/alice.png',
  avatarSource: 'bimi',
  gravatarUrl: '',
);

Widget _host(Widget child) => EasyLocalization(
  supportedLocales: const [Locale('en', 'US')],
  path: 'assets/i18n',
  fallbackLocale: const Locale('en', 'US'),
  useFallbackTranslations: true,
  child: MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ),
);

/// The clipboard is a platform channel: capture the writes instead of reading
/// the host clipboard.
List<String> _captureClipboard(WidgetTester tester) {
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
  return writes;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  group('EmailRecipientChip', () {
    testWidgets('shows the name and keeps the address behind a tap', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const EmailRecipientChip(recipient: _alice, mailHost: 'example.com'),
        ),
      );

      expect(find.text('Alice Chen'), findsOneWidget);
      // The header reads as names; the address is not on screen yet.
      expect(find.text('alice@example.com'), findsNothing);
      // ...but a pointer landing on the chip already gets it.
      expect(
        tester
            .widget<Tooltip>(
              find.ancestor(
                of: find.text('Alice Chen'),
                matching: find.byType(Tooltip),
              ),
            )
            .message,
        'alice@example.com',
      );
    });

    testWidgets('falls back to the full address when there is no name', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const EmailRecipientChip(recipient: _bob, mailHost: 'example.com'),
        ),
      );

      expect(find.text('bob@example.com'), findsOneWidget);
    });

    testWidgets('falls back to the initial when the address has no avatar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const EmailRecipientChip(recipient: _alice, mailHost: 'example.com'),
        ),
      );

      expect(find.text('A'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('wears the senders-index avatar when there is one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const EmailRecipientChip(
            recipient: _alice,
            mailHost: 'example.com',
            sender: _aliceSuggestion,
          ),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        image.image,
        isA<NetworkImage>().having(
          (network) => network.url,
          'url',
          'https://example.com/alice.png',
        ),
      );
      expect(find.text('A'), findsNothing);
      // The harness refuses the request; the chip falls back to initials.
      while (tester.takeException() != null) {}
    });

    testWidgets('a tap reveals the address and copies it', (tester) async {
      final writes = _captureClipboard(tester);
      await tester.pumpWidget(
        _host(
          const EmailRecipientChip(recipient: _alice, mailHost: 'example.com'),
        ),
      );
      // The catalogue loads from the asset bundle; the menu's label comes from
      // it, so wait for the delegate before opening the menu.
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice Chen'));
      await tester.pumpAndSettle();
      expect(find.text('alice@example.com'), findsOneWidget);

      await tester.tap(find.byIcon(Symbols.content_copy));
      await tester.pumpAndSettle();
      expect(writes, ['alice@example.com']);
      // The menu closes on the action it was opened for.
      expect(find.text('alice@example.com'), findsNothing);
    });
  });

  group('EmailRecipientRow', () {
    testWidgets('gives every contact its own chip under the label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const EmailRecipientRow(
            label: 'To',
            recipients: [_alice, _bob],
            mailHost: 'example.com',
          ),
        ),
      );

      expect(find.text('To'), findsOneWidget);
      expect(find.byType(EmailRecipientChip), findsNWidgets(2));
      expect(find.text('Alice Chen'), findsOneWidget);
      expect(find.text('bob@example.com'), findsOneWidget);
    });

    testWidgets('matches avatars by the address the chip displays', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const EmailRecipientRow(
            label: 'From',
            recipients: [_alice],
            mailHost: 'example.com',
            // Keyed the way the senders index keys it: full, lowercase address.
            senders: {'alice@example.com': _aliceSuggestion},
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
      while (tester.takeException() != null) {}
    });

    testWidgets('names a recipient the message left unnamed', (tester) async {
      // The reported case: a To address that is one of the account's own
      // aliases. The payload says "work", the index knows the mailbox name.
      await tester.pumpWidget(
        _host(
          const EmailRecipientChip(
            recipient: MailRecipient(address: 'work'),
            mailHost: 'example.com',
            sender: MailAddressSuggestion(
              address: 'work@example.com',
              name: 'Work',
              avatarUrl: '',
              avatarSource: '',
              gravatarUrl: '',
              alias: true,
            ),
          ),
        ),
      );

      expect(find.text('Work'), findsOneWidget);
      expect(find.text('work@example.com'), findsNothing);
    });

    testWidgets('keeps the name the message itself carries', (tester) async {
      await tester.pumpWidget(
        _host(
          const EmailRecipientChip(
            recipient: _alice,
            mailHost: 'example.com',
            sender: MailAddressSuggestion(
              address: 'alice@example.com',
              name: 'Index Alice',
              avatarUrl: '',
              avatarSource: '',
              gravatarUrl: '',
            ),
          ),
        ),
      );

      expect(find.text('Alice Chen'), findsOneWidget);
      expect(find.text('Index Alice'), findsNothing);
    });

    testWidgets('prefers the initial over a Gravatar stand-in', (tester) async {
      // Gravatar answers for any address; its stand-in is not a picture of
      // this contact, so the chip keeps its own fallback.
      await tester.pumpWidget(
        _host(
          const EmailRecipientChip(
            recipient: _alice,
            mailHost: 'example.com',
            sender: MailAddressSuggestion(
              address: 'alice@example.com',
              name: 'Alice Chen',
              avatarUrl: 'https://gravatar.example/avatar/abc?d=mp',
              avatarSource: 'gravatar',
              gravatarUrl: 'https://gravatar.example/avatar/abc?d=mp',
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('A'), findsOneWidget);
    });
  });
}
