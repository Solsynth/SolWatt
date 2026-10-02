// Regression smoke for the profile page:
// - no "Connected to Solar Network" tile, no divider
// - "Leave workspace" lives in the active workspace's actions menu only
// - tapping it clears the selection and returns to the gate chooser
import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/route.dart';

class _TestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: ProfileRoute.page, initial: true),
    AutoRoute(
      page: AppSettingsRoute.page,
      children: [
        AutoRoute(page: AppSettingsHomeRoute.page, path: '', initial: true),
        AutoRoute(page: AboutRoute.page, path: 'about'),
      ],
    ),
    AutoRoute(page: GateRoute.page),
  ];
}

SnAccount _account() => SnAccount(
  id: 'u1',
  name: 'Test User',
  nick: 'tester',
  language: 'en',
  isSuperuser: false,
  automatedId: null,
  profile: SnAccountProfile(
    id: 'p1',
    experience: 1,
    level: 1,
    levelingProgress: 0.5,
    picture: null,
    background: null,
    verification: null,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
    deletedAt: null,
  ),
  perkSubscription: null,
  activatedAt: DateTime(2024),
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  deletedAt: null,
);

void main() {
  SharedPreferences.setMockInitialValues({});

  testWidgets('profile page: no connection tile, no divider, leave in menu', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'selected_workspace_id': 'ws-active',
    });
    await EasyLocalization.ensureInitialized();

    // The profile page grew an app-settings card, so give the harness a
    // viewport tall enough that the workspace list (and its menus) stay on
    // screen without scrolling.
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1.0;

    final account = _account();
    const active = Workspace(id: 'ws-active', slug: 'ws-active', name: 'Active');
    const inactive = Workspace(
      id: 'ws-inactive',
      slug: 'ws-inactive',
      name: 'Inactive',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          secureStorageProvider.overrideWithValue(FlutterSecureStorage()),
          authSessionProvider.overrideWith(
            (ref) async => const OAuthSession(accessToken: 'tok'),
          ),
          solWattProfileProvider.overrideWith(
            (ref) async => SolWattProfile(account: account, perkLevel: 1),
          ),
          userInfoProvider.overrideWith((ref) async => account),
          workspacesProvider.overrideWith((ref) async => [active, inactive]),
          selectedWorkspaceProvider.overrideWith((ref) async {
            final id = await ref
                .read(secureStorageProvider)
                .read(key: 'selected_workspace_id');
            return id == active.id ? active : null;
          }),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en', 'US')],
          path: 'assets/i18n',
          fallbackLocale: const Locale('en', 'US'),
          useFallbackTranslations: true,
          child: Builder(
            builder: (context) => MaterialApp.router(
              routerConfig: _TestRouter().config(),
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No connection tile, no bottom leave button. Settings and About are their
    // own destinations now, so the account page carries neither row — and with
    // the settings card gone, no divider remains either.
    expect(find.text('Connected to Solar Network'), findsNothing);
    expect(find.text('Not signed in'), findsNothing);
    expect(find.byType(Divider), findsNothing);
    expect(find.text('Leave workspace'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('About'), findsNothing);
    // Profile card renders (title = nick, subtitle = @name).
    expect(find.text('tester'), findsWidgets);
    expect(find.textContaining('@Test User'), findsWidgets);

    // Active workspace menu carries Leave workspace.
    await tester.tap(find.byIcon(Symbols.more_vert).first);
    await tester.pumpAndSettle();
    expect(find.text('Leave workspace'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    // Dismiss.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Inactive workspace menu has no Leave workspace.
    await tester.tap(find.byIcon(Symbols.more_vert).last);
    await tester.pumpAndSettle();
    expect(find.text('Leave workspace'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Leave from the active workspace -> gate chooser.
    await tester.tap(find.byIcon(Symbols.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave workspace'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a workspace'), findsOneWidget);
    expect(find.text('Account and workspaces'), findsNothing);
    // Selection was cleared: active badge gone (no check-circle icon).
    expect(find.byIcon(Symbols.check_circle), findsNothing);
  });
}
