import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solar_network_sdk/solar_network_sdk.dart';
import 'package:solwatt/core/config.dart';
import 'package:solwatt/drive/files/file_list.dart';
import 'package:solwatt/drive/screens/file_list.dart';
import 'package:solwatt/drive/widgets/file_list_view.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/workspaces/workspace_management.dart';

/// The drive has no inline workspace switcher: folder tabs always browse the
/// workspace [selectedWorkspaceProvider] reports, and switching that workspace
/// retargets the open tabs instead of leaving them on the previous listing.

const _solar = Workspace(
  id: 'ws-1',
  slug: 'solar',
  name: 'Solar',
  type: WorkspaceType.organization,
);
const _lunar = Workspace(
  id: 'ws-2',
  slug: 'lunar',
  name: 'Lunar',
  type: WorkspaceType.organization,
);

/// Popup menus inside the drive tab strip. Matched by predicate because the app
/// tree builds widgets from the `material_ui` fork, whose classes are distinct
/// from `flutter/material`'s and therefore invisible to `CommonFinders.byType`.
/// The drive's source switch, the browser's remaining chrome now that the
/// documents live in the shared title bar.
final _sourceSwitch = find.byWidgetPredicate(
  (widget) => widget is mui.SegmentedButton,
);

/// Answers every drive request with an empty page so the browser renders
/// without a socket (a live request would leave Dio's timeout pending).
class _EmptyDriveAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(const <dynamic>[]),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('drive follows the globally active workspace', (tester) async {
    await EasyLocalization.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    var selected = _solar;
    final quotaSlugs = <String?>[];

    final dio = Dio(BaseOptions(baseUrl: 'https://localhost'))
      ..httpClientAdapter = _EmptyDriveAdapter();

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        solarNetworkClientProvider.overrideWith(
          (ref) => SolarNetworkClient.fromDio(dio),
        ),
        selectedWorkspaceProvider.overrideWith((ref) async => selected),
        workspaceListProvider.overrideWith(
          (ref) async => const [_solar, _lunar],
        ),
        workspaceQuotaProvider.overrideWith((ref, slug) async {
          quotaSlugs.add(slug);
          return null;
        }),
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
    // The drive resolves its usage/quota providers asynchronously; pump until
    // the seeded folder tab has rendered its browser.
    for (
      var i = 0;
      i < 10 && find.byType(FileListView).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    // The strip kept only its "add" menu: the inline workspace switcher is gone.
    expect(_sourceSwitch, findsOneWidget);
    // The seeded tab browses the globally active workspace.
    expect(find.byType(FileListView), findsOneWidget);
    expect(quotaSlugs, contains('solar'));

    // Switching the app-selected workspace retargets the open folder tab.
    selected = _lunar;
    container.invalidate(selectedWorkspaceProvider);
    for (var i = 0; i < 10 && !quotaSlugs.contains('lunar'); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.byType(FileListView), findsOneWidget);
    expect(_sourceSwitch, findsOneWidget);
    expect(quotaSlugs, contains('lunar'));

    // Settle the revived listing requests so no Dio timeout stays pending.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  });
}
