import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/mail/mail_address_suggestion.dart';
import 'package:solwatt/ideask/ideask_providers.dart';
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

const _workspace = Workspace(id: 'ws-1', slug: 'ws-1', name: 'Test Workspace');

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

/// Pumps the app on a phone-sized window with one conversation in the list.
///
/// The shell pumps once: its router is a singleton, so a second pump in the
/// same file would mount a second router over the first.
Future<void> _pumpPhone(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  PackageInfo.setMockInitialValues(
    appName: 'SolWatt',
    packageName: 'dev.solsynth.solarwatt',
    version: '1.2.3',
    buildNumber: '45',
    buildSignature: '',
  );
  await EasyLocalization.ensureInitialized();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (call) async => switch (call.method) {
      'isMaximized' => false,
      _ => null,
    },
  );

  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
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
        mailboxUnreadCountsProvider.overrideWith((ref) async => const {}),
        mailCredentialsProvider.overrideWith(
          (ref) async => const <MailCredential>[],
        ),
        mailSenderIndexProvider.overrideWith(
          (ref) async => const <String, MailAddressSuggestion>{},
        ),
        threadsProvider.overrideWith(
          (ref, query) async => PaginatedResult<MailThread>(
            items: [
              MailThread(
                id: 't-1',
                mailboxId: 'mb-1',
                subject: _email.subject,
                messageCount: 1,
                unreadCount: 1,
                participants: const ['alice@example.com'],
                latestAt: DateTime(2026, 9, 25, 10, 30),
                latestMessage: _email,
              ),
            ],
            totalCount: 1,
          ),
        ),
        threadProvider.overrideWith((ref, id) async => [_email]),
        emailProvider.overrideWith((ref, id) async => _email),
        ideaskBrowserProvider.overrideWith(
            (ref) async => const IdeaskBrowserState(),
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
}

void main() {
  testWidgets('compose on a phone: every action stays on screen, and the '
      'keyboard never covers the rail', (tester) async {
    await _pumpPhone(tester);
    // A phone's shell has no per-lens FAB: the floating pill's "New" opens the
    // quick-create sheet, whose "Compose Email" pushes the composer route. The
    // pill lives on the mail lens, so switch to it through the header first —
    // the route belongs to that tab's nested stack.
    // The header's pill names the active lens; open its switcher sheet and
    // pick Mail.
    await tester.tap(find.text('Today').first);
    await tester.pumpAndSettle();
    // The switcher lists the lenses below the drawer's own header; drag the
    // sheet up until the Mail row is on screen.
    for (var i = 0; i < 6 && find.text('Mail').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -200));
      await tester.pumpAndSettle();
    }
    expect(find.text('Mail'), findsWidgets);
    await tester.tap(find.text('Mail').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compose Email'));
    await tester.pumpAndSettle();

    final sheet = tester.getRect(
      find
          .ancestor(
            of: find.byKey(const ValueKey('compose-body')),
            matching: find.byType(KeyboardListener),
          )
          .first,
    );
    expect(sheet.left, 0);
    expect(sheet.right, 400);

    final body = find.byKey(const ValueKey('compose-body'));
    final bodyRect = tester.getRect(body);
    // The writing surface keeps the room: the chrome above it is a header and
    // one envelope frame, not a toolbar parked between them.
    expect(bodyRect.height, greaterThan(400));

    // Every writing action fits the rail. As a ribbon of fourteen buttons they
    // ran off the right edge — "Insert link" and "Add attachment" sat at x 443
    // and x 483 of a 400pt window, reachable only by a scroll nothing
    // advertised.
    Rect inRail(Finder finder) {
      final rect = tester.getRect(finder);
      expect(rect.left, greaterThanOrEqualTo(sheet.left));
      expect(rect.right, lessThanOrEqualTo(sheet.right));
      expect(rect.top, greaterThan(bodyRect.bottom));
      return rect;
    }

    final send = inRail(find.widgetWithText(FilledButton, 'Send'));
    final format = inRail(find.byTooltip('Formatting'));
    final link = inRail(find.byTooltip('Insert link'));
    final attach = inRail(find.byTooltip('Add attachment'));
    final discard = inRail(find.byTooltip('Discard changes'));
    // Reading order: send, then the writer's tools, then the way to throw the
    // message away, at the far end.
    expect(send.left, lessThan(format.left));
    expect(format.left, lessThan(link.left));
    expect(link.left, lessThan(attach.left));
    expect(attach.right, lessThan(discard.left));

    // A phone keyboard shrinks the shell instead of hiding the rail behind it,
    // so the message can be sent without dismissing the keyboard first.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final raised = tester.getRect(find.widgetWithText(FilledButton, 'Send'));
    expect(raised.bottom, lessThanOrEqualTo(500));
    expect(raised.height, send.height);
    // The keyboard took the room from the body, not from the rail.
    final squeezed = tester.getRect(body).height;
    // ignore: avoid_print
    expect(squeezed, lessThan(bodyRect.height));
    // The keyboard leaves the body whatever the chrome does not take: the
    // header, one envelope frame and the rail. A few lines is what a 400pt
    // phone has left, and the rail must still be fully on screen.
    expect(squeezed, greaterThan(100));
    expect(raised.bottom, lessThanOrEqualTo(500));

    // A large text scale grows the rail with its buttons instead of clipping
    // the label out of a fixed strip.
    tester.view.viewInsets = const FakeViewPadding();
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final scaled = tester.getRect(find.widgetWithText(FilledButton, 'Send'));
    expect(scaled.height, greaterThan(send.height));
    expect(scaled.bottom, lessThanOrEqualTo(800));
  });
}
