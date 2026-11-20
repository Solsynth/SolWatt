import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/drive/favorites.dart';
import 'package:solwatt/drive/usage.dart';
import 'package:solwatt/drive/widgets/file_list_view.dart' show FileListMode;
import 'package:solwatt/network.dart';
import 'package:solwatt/shell/contextual_sidebar.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

/// The drive sidebar is the drive's own control surface: the pane switch, the
/// storage meter, and favorites that come from the filesystem service.
Future<ProviderContainer> _container({
  List<SnCloudFile> favorites = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      selectedWorkspaceProvider.overrideWith((ref) async => null),
      favoriteCloudFilesProvider.overrideWith(
        (ref, workspaceId) async => favorites,
      ),
      driveFavoritePathsProvider.overrideWith(
        (ref, workspaceId) async => {
          for (final file in favorites) file.id: '/',
        },
      ),
      driveStorageUsageProvider.overrideWith(
        (ref) async =>
            const DriveStorageSnapshot(usedBytes: 25, totalBytes: 100),
      ),
    ],
  );
}

Widget _app(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: createSolWattTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1280, 800)),
          child: Scaffold(body: child),
        ),
      ),
    );

SnCloudFile _favoriteFile(String id, String name) => SnCloudFile(
  id: id,
  accountId: 'account-1',
  description: null,
  indexed: true,
  isFolder: false,
  isMarkedRecycle: false,
  name: name,
  object: null,
  objectId: null,
  parentId: null,
  resourceIdentifier: 'file:$id',
  storageId: null,
  storageUrl: null,
  mimeType: 'application/pdf',
  applicationType: null,
  usage: null,
  permissionStatus: null,
  uploadedAt: null,
  expiredAt: null,
  updatedAt: DateTime(2026),
  createdAt: DateTime(2026),
  deletedAt: null,
);

void main() {
  testWidgets('drive sidebar owns the pane switch and storage meter', (
    tester,
  ) async {
    final container = await _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(
        container,
        const ContextualSidebar(
          activeLens: WorkspaceLens.drive,
          onSelectLens: _ignore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Cloud'), findsOneWidget);
    expect(find.text('Assets'), findsOneWidget);
    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('25 B of 100 B'), findsOneWidget);

    expect(container.read(driveBrowseModeProvider), FileListMode.normal);
    await tester.tap(find.text('Assets'));
    await tester.pumpAndSettle();
    expect(container.read(driveBrowseModeProvider), FileListMode.unindexed);
  });

  testWidgets('server favorites render in the shared Favorites section', (
    tester,
  ) async {
    final container = await _container(
      favorites: [_favoriteFile('file-1', 'Quarterly plan.pdf')],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(
        container,
        const ContextualSidebar(
          activeLens: WorkspaceLens.drive,
          onSelectLens: _ignore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Quarterly plan.pdf'), findsOneWidget);
    // The row carries the path the file lives in, not just its name.
    expect(find.text('/'), findsOneWidget);
    expect(find.byTooltip('Remove from Favorites'), findsOneWidget);
  });

  testWidgets('the drive dock stays pinned when the column scrolls', (
    tester,
  ) async {
    final container = await _container();
    addTearDown(container.dispose);

    // A phone-height column cannot fit favorites, the tree and the dock at
    // once, so the dock must sit outside the scroll view.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: createSolWattTheme(Brightness.light),
          home: const MediaQuery(
            data: MediaQueryData(size: Size(1280, 320)),
            child: Scaffold(
              body: ContextualSidebar(
                activeLens: WorkspaceLens.drive,
                onSelectLens: _ignore,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final scrollBottom = tester
        .getRect(find.byType(SingleChildScrollView))
        .bottom;
    expect(
      tester.getRect(find.text('Storage')).top,
      greaterThanOrEqualTo(scrollBottom),
    );
    expect(find.text('Cloud'), findsOneWidget);
  });
}

void _ignore(WorkspaceLens _) {}
