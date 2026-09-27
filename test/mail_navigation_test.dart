import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/realtime/realtime.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/websocket.dart';
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

final _thread = MailThread(
  id: 't-1',
  mailboxId: 'mb-1',
  subject: 'Hello there',
  messageCount: 1,
  unreadCount: 1,
  participants: const ['alice@example.com'],
  latestMessage: _email,
  latestAt: DateTime(2026, 9, 25, 10, 30),
);

void main() {
  testWidgets('shell chrome: app bars, folder and tab bottom bars, drawer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'SolWatt',
      packageName: 'dev.solsynth.solarwatt',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
    );
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

    Future<void> pumpApp(
      Size size, {
      Map<String, MailAddressSuggestion> senders = const {},
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          // Riverpod only applies overrides when the scope element is fresh;
          // a reused element keeps the first pump's overrides. Key by size so
          // every pump starts from its own override set.
          key: ValueKey('mail-${size.width}x${size.height}'),
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
            mailNotificationSettingsProvider.overrideWith(
              (ref) async => const MailNotificationSettings(
                accountId: 'acc-1',
                highlight: true,
                summarize: false,
              ),
            ),
            mailboxQuotaProvider.overrideWith(
              (ref, mailboxId) async => MailboxQuota(
                workspaceId: 'ws-1',
                usedBytes: 100,
                limitBytes: 1024 * 1024 * 1024,
                remainingBytes: 1024 * 1024 * 1024 - 100,
              ),
            ),
            mailboxAliasesProvider.overrideWith(
              (ref, mailboxId) async => const <MailAlias>[],
            ),
            mailboxForwardingsProvider.overrideWith(
              (ref, mailboxId) async => const <MailForwarding>[],
            ),
            mailBlockRulesProvider.overrideWith(
              (ref) async => const <MailBlockRule>[],
            ),
            threadsProvider.overrideWith(
              (ref, query) async =>
                  PaginatedResult<MailThread>(items: [_thread], totalCount: 1),
            ),
            mailSenderIndexProvider.overrideWith(
              (ref) async => senders,
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
    // No sender-avatar data in this pump: the tile falls back to initials
    // ("Alice" -> "A") and the unread fixture gets the read-state dot.
    expect(
      find.descendant(of: find.byType(ListTile), matching: find.text('A')),
      findsOneWidget,
    );

    // Phone chrome: an app bar carries the inbox switcher and the drawer,
    // instead of a burger inside the bottom navigation bar.
    expect(find.byType(AppBar), findsOneWidget);
    final appBar = find.byType(AppBar);
    expect(
      find.descendant(of: appBar, matching: find.text('Work')),
      findsOneWidget,
    );
    expect(find.byIcon(Symbols.menu), findsOneWidget); // drawer, in the app bar

    // Bottom navigation lists the desktop rail's folders, minus the ones that
    // do not fit: Trash and Archive live behind the "more" destination.
    final navBar = find.byType(NavigationBar);
    expect(navBar, findsOneWidget);
    for (final folder in ['Inbox', 'Sent', 'Drafts', 'Spam']) {
      expect(
        find.descendant(of: navBar, matching: find.text(folder)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: navBar, matching: find.text('Trash')),
      findsNothing,
    );

    // No card pane on a phone: the list runs edge to edge, straight under the
    // app bar, and the compose FAB clears the bottom bar.
    final listRect = tester.getRect(find.byType(RefreshIndicator));
    expect(listRect.top, tester.getRect(appBar).bottom);
    expect(listRect.left, 0);
    expect(listRect.width, 400);
    expect(
      tester.getRect(find.byType(FloatingActionButton)).bottom,
      lessThanOrEqualTo(tester.getRect(navBar).top),
    );

    // A device status bar stays the page's business: its app bar takes the
    // inset into its own height and paints that strip, instead of being pushed
    // down and leaving the shell's bare background above it.
    final barWithoutInset = tester.getRect(appBar);
    tester.view.padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);
    await pumpApp(const Size(400, 800));
    final barWithInset = tester.getRect(appBar);
    // Still pinned to the top of the window's content area…
    expect(barWithInset.top, barWithoutInset.top);
    // …now taller by the inset it paints.
    expect(barWithInset.height, barWithoutInset.height + 24);
    // Hand the rest of the test back a bar-inset-free view.
    tester.view.padding = const FakeViewPadding();
    await tester.pump();

    // Switching a folder from the bar keeps the list alive.
    await tester.tap(find.descendant(of: navBar, matching: find.text('Sent')));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);

    // The folders the bar cuts off stay reachable through "more".
    await tester.tap(find.descendant(of: navBar, matching: find.text('More')));
    await tester.pumpAndSettle();
    expect(find.text('Trash'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    // SheetScaffold draws its own chrome with the material_ui fork, which
    // reads a separate theme system: the app font only reaches it through the
    // mirrored fork theme.
    expect(
      tester.widget<Text>(find.text('Folders')).style?.fontFamily,
      SolWattFonts.sans,
    );
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);

    // Search moves into the app bar and resets back to the inbox title.
    await tester.tap(find.byIcon(Symbols.search));
    await tester.pumpAndSettle();
    final searchField = find.descendant(
      of: appBar,
      matching: find.byType(TextField),
    );
    expect(searchField, findsOneWidget);
    await tester.enterText(searchField, 'hello');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    await tester.tap(find.byIcon(Symbols.close));
    await tester.pumpAndSettle();
    expect(searchField, findsNothing);

    // The mail settings page merges credentials, mailbox settings, blocked
    // senders, and import. The page is a lazy list on a phone, so scroll to
    // each section before asserting it.
    await tester.tap(find.byIcon(Symbols.settings));
    await tester.pumpAndSettle();
    expect(find.text('Mail settings'), findsOneWidget);
    expect(find.text('Notification preferences'), findsOneWidget);
    expect(find.text('Mail credentials'), findsOneWidget);
    expect(find.text('No credentials'), findsOneWidget);

    final settingsList = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('Mailbox settings'),
      120,
      scrollable: settingsList,
    );
    expect(find.text('Mailbox settings'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Mail storage usage'),
      120,
      scrollable: settingsList,
    );
    expect(find.text('Mail storage usage'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Aliases'),
      120,
      scrollable: settingsList,
    );
    expect(find.text('Aliases'), findsOneWidget);
    expect(find.text('No aliases yet'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Forwarding'),
      120,
      scrollable: settingsList,
    );
    expect(find.text('Forwarding'), findsOneWidget);
    expect(find.text('No forwarding rules'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Blocked senders'),
      120,
      scrollable: settingsList,
    );
    expect(find.text('Blocked senders'), findsOneWidget);
    expect(find.text('No blocked senders'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Import emails').first,
      120,
      scrollable: settingsList,
    );
    expect(find.text('Import emails'), findsWidgets); // section + button
    // The import section targets the selected inbox, which is still the
    // default one at this point.
    expect(find.text('work@example.com'), findsWidgets);
    // Scroll back to the header so the close button is tappable again.
    await tester.fling(settingsList, const Offset(0, 800), 2000);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Symbols.close));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);

    // The selected inbox drives the app bar, so it now reads Personal.
    await tester.tap(find.descendant(of: appBar, matching: find.text('Work')));
    await tester.pumpAndSettle();
    expect(find.text('Personal'), findsOneWidget);
    await tester.tap(find.text('Personal'));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(
      find.descendant(of: appBar, matching: find.text('Personal')),
      findsOneWidget,
    );

    // Leave the folder and inbox on their defaults: the pumps below reuse the
    // same ProviderScope, so the desktop section starts from the default inbox
    // and folder.
    await tester.tap(find.descendant(of: navBar, matching: find.text('Inbox')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: appBar, matching: find.text('Personal')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: appBar, matching: find.text('Work')),
      findsOneWidget,
    );

    // Drawer hides the rest of the app: boards/ideask, files, flywheel, and
    // the merged account entry. Settings and notifications are no longer
    // separate drawer entries.
    await tester.tap(find.byIcon(Symbols.menu));
    await tester.pumpAndSettle();
    expect(find.text('Boards'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Flywheel'), findsOneWidget);
    expect(find.text('Mail'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Notifications'), findsNothing);

    // Close the drawer via the scrim; the mail list is still there.
    await tester.tapAt(const Offset(350, 400));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);

    // ---- Other tabs on a phone ----
    // Each tab gets the same treatment: an app bar that owns the drawer, and
    // a bottom bar of top-level tabs instead of a burger.
    await tester.tap(find.byIcon(Symbols.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Boards'));
    // The tab switch rebuilds the shell while the drawer is still sliding
    // shut: the drawer has to survive that rebuild and finish its exit
    // instead of being dropped with the scaffold that owned it.
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(Drawer), findsWidgets);
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Boards')),
      findsOneWidget,
    );
    final tabBar = find.byType(NavigationBar);
    for (final tab in ['Mail', 'Boards', 'Files', 'Flywheel', 'Profile']) {
      expect(
        find.descendant(of: tabBar, matching: find.text(tab)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: tabBar, matching: find.byIcon(Symbols.menu)),
      findsNothing,
    );

    // The tab bar switches back to the mail list and its folder bar.
    await tester.tap(find.descendant(of: tabBar, matching: find.text('Mail')));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(
      find.descendant(of: navBar, matching: find.text('Inbox')),
      findsOneWidget,
    );

    // ---- Desktop (wide) ----
    await pumpApp(
      const Size(1200, 800),
      senders: const {
        'alice@example.com': MailAddressSuggestion(
          address: 'alice@example.com',
          avatarUrl: 'https://example.com/alice.png',
          avatarSource: 'bimi',
          gravatarUrl: '',
        ),
      },
    );

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
    // The senders-index avatar URL rides on the tile leading as a network
    // image (initials shown only when the image cannot load).
    expect(
      find.descendant(of: find.byType(ListTile), matching: find.byType(Image)),
      findsOneWidget,
    );

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
    // The mode switch animates: mid-transition both destination sets coexist
    // (the outgoing folders rail cross-fades into the feature rail).
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(NavigationRail), findsNWidgets(2));
    await tester.pumpAndSettle();
    // Flywheel and Profile stay behind the burger; the rail only carries
    // Mail, Boards and Files.
    for (final feature in ['Mail', 'Boards', 'Files']) {
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

    // Switching back to Mail animates the folders back in the same way.
    await tester.tap(find.text('Mail'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(NavigationRail), findsNWidgets(2));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: rail, matching: find.text('Inbox')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rail, matching: find.text('Boards')),
      findsNothing,
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

    // Profile absorbs Settings: the merged page carries the connection card,
    // the app-settings and about entries, and sign-out from the former
    // Settings page. The real session providers resolve to null in this
    // harness, so the page settles with the static content only — bounded
    // pumps keep the drawer transition honest.
    await tester.tap(find.byIcon(Symbols.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Account and workspaces'), findsOneWidget);
    expect(find.text('Your workspaces'), findsOneWidget);
    expect(find.text('App settings'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);

    // The App settings page offers language and appearance.
    await tester.tap(find.text('Settings').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Theme mode'), findsOneWidget);
    expect(find.text('Accent color'), findsOneWidget);
    expect(find.text('Display language'), findsOneWidget);

    // And the About page carries app info and legal links.
    await tester.tap(find.byType(BackButton));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    final aboutTile = find.widgetWithText(ListTile, 'About');
    await tester.ensureVisible(aboutTile);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(aboutTile);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('App information'), findsOneWidget);
    expect(find.text('Links'), findsOneWidget);
    expect(find.text('Open-source licenses'), findsOneWidget);
    expect(find.text('Developer'), findsOneWidget);
  });
}
