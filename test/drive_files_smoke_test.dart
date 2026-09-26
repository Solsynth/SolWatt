import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solar_network_foundation/solar_network_foundation.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/core/drive_wiring.dart';
import 'package:solwatt/route.dart';
import 'package:solwatt/tasks/app_task.dart';
import 'package:solwatt/tasks/tasks_notifier.dart';
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

    var selected = workspace;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          selectedWorkspaceProvider.overrideWith((ref) async => selected),
          workspaceListProvider.overrideWith(
            (ref) async => [
              const Workspace(id: 'ws-1', slug: 'solar', name: 'Solar'),
              const Workspace(id: 'ws-2', slug: 'lunar', name: 'Lunar'),
            ],
          ),
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
    // The seeded tab's content replaced the workspace placeholder.
    expect(find.text('driveIndexedEntryLabel'.tr()), findsNothing);
  });

  testWidgets('switching the selected workspace re-binds the drive tab', (
    tester,
  ) async {
    await EasyLocalization.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    const first = Workspace(id: 'ws-1', slug: 'solar', name: 'Solar');
    const second = Workspace(id: 'ws-2', slug: 'lunar', name: 'Lunar');
    var selected = first;

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        selectedWorkspaceProvider.overrideWith((ref) async => selected),
        workspaceListProvider.overrideWith(
          (ref) async => const [first, second],
        ),
        billingUsageProvider.overrideWith((ref) async => null),
        billingQuotaProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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

    // Switch workspaces while the tab is mounted: the bootstrap effect re-runs
    // against the new selection on a later frame.
    selected = second;
    container.invalidate(selectedWorkspaceProvider);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('driveNoOpenTabs'.tr()), findsNothing);
  });

  test('drive host wiring binds SolWatt state to the shared drive seam', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...driveHostOverrides(),
      ],
    );
    addTearDown(container.dispose);

    // Settings flow through from the host's own settings store.
    expect(container.read(driveSettingsProvider).imageCompressionQuality, 80);

    // The client and navigator come from the host's own providers.
    expect(container.read(driveClientProvider), isNotNull);
    expect(
      container.read(driveNavigatorKeyProvider),
      same(appRouter.navigatorKey),
    );

    // Task lifecycle round-trips through the host's task list, translating
    // the shared status enum onto SolWatt's.
    final sink = container.read(driveTaskSinkProvider);
    final id = sink.addTask(
      title: 'Uploading',
      type: DriveTaskTypes.upload,
      status: DriveTaskStatus.inProgress,
      metadata: const {'fileSize': 42},
    );
    expect(container.read(appTasksProvider).single.status, AppTaskStatus.inProgress);
    expect(sink.getTask(id)?.metadata?['fileSize'], 42);

    container.read(appTasksProvider.notifier).updateTask(id, progress: 0.5);
    expect(sink.getTask(id)?.progress, 0.5);
  });
}
