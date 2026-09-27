import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/notifications/notifications.dart';

SnNotification _notification({
  required String id,
  required String title,
  required DateTime createdAt,
  bool unread = true,
}) => SnNotification(
  id: id,
  appId: 'solwatt',
  topic: 'board.update',
  title: title,
  subtitle: 'Subtitle',
  body: 'Body',
  meta: const {},
  createdAt: createdAt,
  viewedAt: unread ? null : createdAt.add(const Duration(minutes: 1)),
  accountId: 'account-1',
);

/// The attention-modal route page paints its chrome with the `material_ui`
/// fork's `Material` (see `_AttentionModalRoutePage` in
/// `island_ui_foundation`), so the modal's own content sees no Flutter
/// `Material` ancestor unless it brings one.
Widget _forkChrome(Widget child) =>
    mui.Material(type: mui.MaterialType.transparency, child: child);

DateTime _ago(Duration duration) => DateTime.now().subtract(duration);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('notification modal renders tiles and relative timestamps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationListProvider.overrideWith(
            (ref) async => [
              _notification(
                id: 'n-1',
                title: 'Board updated',
                createdAt: _ago(const Duration(hours: 3, minutes: 30)),
              ),
              _notification(
                id: 'n-2',
                title: 'Task assigned',
                createdAt: _ago(const Duration(minutes: 5)),
                unread: false,
              ),
            ],
          ),
        ],
        // The modal reads translations through the library's context-less
        // `.tr()`, which resolves against the global `Localization.instance`
        // filled in by the `EasyLocalization` delegate, so the delegates have
        // to be in the tree.
        child: EasyLocalization(
          supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
          path: 'assets/i18n',
          fallbackLocale: const Locale('en', 'US'),
          useFallbackTranslations: true,
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: _forkChrome(NotificationModal(onDismiss: () {})),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Regression: Flutter's `ListTile` asserts "No Material widget found" when
    // the modal content is not given a Flutter `Material` ancestor.
    expect(tester.takeException(), isNull);
    expect(find.byType(NotificationTile), findsNWidgets(2));
    expect(find.text('Board updated'), findsOneWidget);

    // Regression: the catalogs use `{count}` placeholders, which only
    // `namedArgs` fills — positional `args` left the raw key/placeholder on
    // screen ("{count}h ago", "{count} 小时前").
    expect(find.text('3h ago'), findsOneWidget);
    expect(find.text('5m ago'), findsOneWidget);

    tester
        .element(find.byType(NotificationModal))
        .setLocale(const Locale('zh', 'CN'));
    await tester.pumpAndSettle();

    expect(find.text('3 小时前'), findsOneWidget);
    expect(find.text('5 分钟前'), findsOneWidget);
    expect(find.textContaining('{count}'), findsNothing);
  });
}
