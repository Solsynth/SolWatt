import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/drive/files/file_list.dart';
import 'package:solwatt/drive/screens/file_list.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/workspaces/workspace_management.dart';

/// Smoke test for the ported drive Files tab: it must mount and render its
/// workspace-empty state without hitting the network or throwing.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('drive Files tab mounts and renders', (tester) async {
    await EasyLocalization.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          selectedWorkspaceProvider.overrideWith((ref) async => null),
          workspaceListProvider.overrideWith((ref) async => const []),
          billingUsageProvider.overrideWith((ref) async => null),
          billingQuotaProvider.overrideWith((ref) async => null),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en', 'US')],
          path: 'assets/i18n',
          fallbackLocale: const Locale('en', 'US'),
          useFallbackTranslations: true,
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: [
                ...context.localizationDelegates,
                ...mui.GlobalMaterialLocalizations.delegates,
              ],
              home: const FileListScreen(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    // The workspace-empty state offers the indexed/unindexed entry points.
    expect(find.text('driveIndexedEntryLabel'.tr()), findsWidgets);
  });

  testWidgets('drive Files tab auto-opens a tab for the selected workspace', (
    tester,
  ) async {
    await EasyLocalization.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    const workspace = Workspace(id: 'ws-1', slug: 'solar', name: 'Solar');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          selectedWorkspaceProvider.overrideWith((ref) async => workspace),
          workspaceListProvider.overrideWith((ref) async => const [workspace]),
          billingUsageProvider.overrideWith((ref) async => null),
          billingQuotaProvider.overrideWith((ref) async => null),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en', 'US')],
          path: 'assets/i18n',
          fallbackLocale: const Locale('en', 'US'),
          useFallbackTranslations: true,
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: [
                ...context.localizationDelegates,
                ...mui.GlobalMaterialLocalizations.delegates,
              ],
              home: const FileListScreen(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    // The bootstrap replaced the empty state with a drive tab.
    expect(find.text('driveNoOpenTabs'.tr()), findsNothing);
  });
}
