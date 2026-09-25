import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/main.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/realtime/realtime.dart';
import 'package:solwatt/theme.dart';
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

const _mailboxPersonal = MailMailbox(
  id: 'mb-2',
  accountId: 'acc-1',
  workspaceId: 'ws-1',
  address: 'personal@example.com',
  name: 'Personal',
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
  testWidgets('email-first shell: inbox bottom nav, folder tabs, drawer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    // Start dark so the initial chrome assertion below runs in dark mode;
    // a later section flips the brightness to prove the titlebar follows.
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => switch (call.method) {
        'isMaximized' => false,
        _ => null,
      },
    );

    Future<void> pumpApp(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
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
            emailsProvider.overrideWith(
              (ref, filter) async =>
                  PaginatedResult<MailEmail>(items: [_email], totalCount: 1),
            ),
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
    }

    // ---- Mobile (narrow) ----
    await pumpApp(const Size(400, 800));

    // Email-first: the mail list is the initial surface after sign-in.
    expect(find.text('Alice'), findsOneWidget); // sender on the email tile
    expect(find.byIcon(Symbols.star_outline), findsOneWidget); // star toggle

    // Folder tabs (proper email client navigation).
    for (final folder in ['Inbox', 'Sent', 'Drafts', 'Spam']) {
      expect(find.text(folder), findsOneWidget);
    }

    // Switching a folder keeps the list alive.
    await tester.tap(find.text('Sent'));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);

    // Trash/Archive sit beyond the viewport of the horizontal chip list.
    await tester.drag(find.byType(ChoiceChip).first, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Trash'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);

    // Bottom nav shows the inboxes (mailboxes) plus the drawer entry.
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Work'), findsWidgets); // mailbox destination label
    expect(find.text('Personal'), findsOneWidget);
    expect(find.byIcon(Symbols.menu), findsOneWidget);

    // The mail settings page merges credentials and import.
    await tester.tap(find.byIcon(Symbols.settings));
    await tester.pumpAndSettle();
    expect(find.text('Mail settings'), findsOneWidget);
    expect(find.text('Mail credentials'), findsOneWidget);
    expect(find.text('No credentials'), findsOneWidget);
    expect(find.text('Import emails'), findsWidgets); // section + button
    expect(find.text('work@example.com'), findsWidgets); // import mailbox
    await tester.tap(find.byIcon(Symbols.close));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);

    // Drawer hides the rest of the app: boards/ideask, files, flywheel.
    await tester.tap(find.byIcon(Symbols.menu));
    await tester.pumpAndSettle();
    expect(find.text('Boards'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Flywheel'), findsOneWidget);
    expect(find.text('Mail'), findsOneWidget);

    // Close the drawer via the scrim; the mail list is still there.
    await tester.tapAt(const Offset(350, 400));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);

    // ---- Desktop (wide) ----
    await pumpApp(const Size(1200, 800));

    // Rail is email-first: the mail folders live in the rail; the burger
    // (below the notification bell) opens the drawer with everything else.
    expect(find.byType(NavigationRail), findsOneWidget);
    final rail = find.byType(NavigationRail);
    for (final folder in [
      'Inbox',
      'Sent',
      'Drafts',
      'Spam',
      'Trash',
      'Archive',
    ]) {
      expect(
        find.descendant(of: rail, matching: find.text(folder)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: rail, matching: find.text('Work')),
      findsNothing,
    );
    expect(find.byIcon(Symbols.menu), findsOneWidget); // burger → drawer
    expect(find.byIcon(Symbols.notifications), findsOneWidget);

    // Mail page: mailbox dropdown + email tile. The folder chips are hidden
    // because the rail already owns the folders on wide screens.
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('work@example.com'), findsOneWidget); // dropdown value
    expect(find.byType(ChoiceChip), findsNothing);

    // No bottom nav on desktop.
    expect(find.byType(NavigationBar), findsNothing);

    // The burger opens the drawer on desktop too.
    await tester.tap(find.byIcon(Symbols.menu));
    await tester.pumpAndSettle();
    expect(find.text('Flywheel'), findsOneWidget);
    await tester.tapAt(const Offset(1100, 400)); // close the drawer
    await tester.pumpAndSettle();

    // Outside Mail the rail swaps the folders for the feature destinations.
    await tester.tap(find.byIcon(Symbols.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Boards'));
    await tester.pumpAndSettle();
    for (final feature in [
      'Mail',
      'Boards',
      'Files',
      'Flywheel',
      'Profile',
      'Settings',
    ]) {
      expect(
        find.descendant(of: rail, matching: find.text(feature)),
        findsOneWidget,
      );
    }
    for (final folder in [
      'Inbox',
      'Sent',
      'Drafts',
      'Spam',
      'Trash',
      'Archive',
    ]) {
      expect(
        find.descendant(of: rail, matching: find.text(folder)),
        findsNothing,
      );
    }
    expect(tester.widget<NavigationRail>(rail).selectedIndex, 1); // Boards
    // The unread badge rides on the Mail destination in feature mode.
    expect(
      find.descendant(of: rail, matching: find.byType(Badge)),
      findsOneWidget,
    );

    // ---- Titlebar follows the active (dark) theme ----
    await pumpApp(const Size(1200, 800));

    final darkScheme = createSolWattTheme(Brightness.dark).colorScheme;
    // The frame renders with the material_ui fork's Material (see main.dart);
    // its chrome background must be the app's surface, not the fork default.
    final frameMaterial = tester.widget<mui.Material>(
      find
          .descendant(
            of: find.byType(DesktopWindowFrame),
            matching: find.byType(mui.Material),
          )
          .first,
    );
    expect(frameMaterial.color, darkScheme.surface);

    // Title text is pinned to the dark theme's onSurface so it stays visible.
    final titleText = tester.widget<Text>(find.text('appName'.tr()));
    expect(titleText.style?.color, darkScheme.onSurface);

    // ---- The titlebar follows the app brightness at runtime ----
    // Flip the platform brightness on the *same* widget tree: the chrome
    // theme must be rebuilt (main.dart mirrors it inside the OverlayEntry),
    // not frozen at the brightness from launch.
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    await tester.pumpAndSettle();

    final lightScheme = createSolWattTheme(Brightness.light).colorScheme;
    final lightFrameMaterial = tester.widget<mui.Material>(
      find
          .descendant(
            of: find.byType(DesktopWindowFrame),
            matching: find.byType(mui.Material),
          )
          .first,
    );
    expect(lightFrameMaterial.color, lightScheme.surface);
    final lightTitleText = tester.widget<Text>(find.text('appName'.tr()));
    expect(lightTitleText.style?.color, lightScheme.onSurface);
  });
}
