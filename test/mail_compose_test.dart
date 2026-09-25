import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
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
  subject: 'Hello there',
  body: 'Hi from Alice',
  isDraft: false,
  from: MailRecipient(address: 'alice@example.com', name: 'Alice'),
  isRead: false,
  createdAt: DateTime(2026, 9, 25, 10, 30),
);

void main() {
  testWidgets('compose: compact fields, collapsed cc/bcc, full-screen body, '
      'preset styles, keyboard shortcuts', (tester) async {
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
          emailsProvider.overrideWith(
            (ref, filter) async => PaginatedResult<MailEmail>(
              items: [_email],
              totalCount: 1,
            ),
          ),
          emailProvider.overrideWith((ref, id) async => _email),
          broadsProvider.overrideWith((ref) async => const <Broad>[]),
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

    // Expanding the toggle reveals Cc/Bcc.
    await tester.tap(find.byTooltip('Cc/Bcc'));
    await tester.pumpAndSettle();
    expect(find.text('Cc'), findsOneWidget);
    expect(find.text('Bcc'), findsOneWidget);

    // Body editor fills the remaining height.
    final bodyFinder = find.byKey(const ValueKey('compose-body'));
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

    // Cmd+Enter (control in tests) with no recipients shows the guard snackbar.
    await tester.tap(bodyFinder);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('Add at least one recipient.'), findsOneWidget);

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
    final replyBody = find.byKey(const ValueKey('compose-body'));
    final replyQuill = tester.widget<QuillEditor>(replyBody).controller;
    expect(replyQuill.document.toPlainText(), contains('Hi from Alice'));
  });
}
