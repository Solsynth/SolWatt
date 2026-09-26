import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/settings/app_settings_page.dart';
import 'package:solwatt/theme.dart';

void main() {
  testWidgets('theme mode and accent persist and drive the app theme', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
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
              home: const Scaffold(body: AppSettingsPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<DropdownButton<ThemeMode>>(
        find.byType(DropdownButton<ThemeMode>),
      ).value,
      ThemeMode.system,
    );
    // Switch to dark.
    await tester.tap(find.byType(DropdownButton<ThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<DropdownButton<ThemeMode>>(
        find.byType(DropdownButton<ThemeMode>),
      ).value,
      ThemeMode.dark,
    );
    expect(prefs.getString('app_theme_mode'), 'dark');

    // Accent: tap the sky dot and confirm persistence.
    final sky = kAccentColorOptions[1].toARGB32();
    final skyDot = find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      final decoration = w.decoration;
      return decoration is BoxDecoration &&
          decoration.color == kAccentColorOptions[1];
    });
    expect(skyDot, findsOneWidget);
    await tester.tap(skyDot);
    await tester.pumpAndSettle();
    expect(prefs.getInt('app_accent_color'), sky);
  });
}
