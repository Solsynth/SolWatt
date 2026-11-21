import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:solwatt/core/network.dart';
import 'package:solwatt/drive/widgets/file_list_view.dart' show FileListMode;
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_state.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

/// Which Drive pane the reader is browsing: the indexed cloud hierarchy or the
/// unindexed service attachments. It lives above the drive screen because the
/// contextual sidebar and the browser both drive it.
final driveBrowseModeProvider =
    NotifierProvider<DriveBrowseModeNotifier, FileListMode>(
      DriveBrowseModeNotifier.new,
    );

class DriveBrowseModeNotifier extends Notifier<FileListMode> {
  @override
  FileListMode build() => FileListMode.normal;

  void select(FileListMode mode) {
    if (state == mode) return;
    state = mode;
  }
}

/// Bumped when the sidebar's "All files" row is tapped. The drive browser
/// watches it and returns the cloud pane to the root, the way a files-app
/// sidebar entry behaves; the pane choice itself lives in
/// [driveBrowseModeProvider].
final driveRootRequestProvider =
    NotifierProvider<DriveRootRequestNotifier, int>(
      DriveRootRequestNotifier.new,
    );

class DriveRootRequestNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

/// The workspace whose drive is on screen: null means the personal files root,
/// which is what an individual workspace maps to.
final activeDriveWorkspaceIdProvider = Provider<String?>((ref) {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  return workspace == null || workspace.isIndividual ? null : workspace.id;
});

/// Favorited drive files for a workspace, newest bookmark first.
final favoriteCloudFilesProvider = FutureProvider.autoDispose
    .family<List<SnCloudFile>, String?>((ref, workspaceId) async {
      return ref
          .read(wattEngineClientProvider)
          .listFavoriteCloudFiles(workspaceId: workspaceId);
    });

/// Folder path (e.g. `/Design/Logos`) for each favorited drive file. Root-level
/// files map to `/`; a failed lookup also degrades to the root rather than
/// hiding the favorite.
final driveFavoritePathsProvider =
    FutureProvider.autoDispose.family<Map<String, String>, String?>(
      (ref, workspaceId) async {
        final files = await ref.watch(
          favoriteCloudFilesProvider(workspaceId).future,
        );
        final client = ref.read(wattEngineClientProvider);
        final paths = <String, String>{};
        for (final file in files) {
          paths[file.id] = await driveFolderPathOf(client, file);
        }
        return paths;
      },
    );

/// The folder path a drive file lives in. Fields the sidebar needs only.
Future<String> driveFolderPathOf(
  WattEngineClient client,
  SnCloudFile file,
) async {
  if (file.parentId == null || file.parentId!.isEmpty) return '/';
  try {
    final crumbs = await client.getCloudFileBreadcrumb(file.id);
    // The breadcrumb ends with the file itself; its folder chain precedes it.
    final folders = crumbs
        .where((item) => item.isFolder && item.id != file.id)
        .toList(growable: false);
    if (folders.isEmpty) return '/';
    return '/${folders.map((item) => item.name).join('/')}';
  } catch (_) {
    return '/';
  }
}

/// Favorited drive files as workspace entities, so the shared Favorites section
/// can render them beside mail threads, pages and folders.
final driveFavoriteEntitiesProvider =
    FutureProvider.autoDispose<List<WorkspaceEntityRef>>((ref) async {
      final workspaceId = ref.watch(activeDriveWorkspaceIdProvider);
      final files = await ref.watch(
        favoriteCloudFilesProvider(workspaceId).future,
      );
      final paths = await ref.watch(
        driveFavoritePathsProvider(workspaceId).future,
      );
      return [
        for (final file in files)
          WorkspaceEntityRef(
            id: file.id,
            domain: WorkspaceDomain.drive,
            title: file.name.isEmpty ? 'Untitled' : file.name,
            subtitle: paths[file.id] ?? '/',
            mimeType: file.mimeType,
            byteSize: file.size,
            metadata: {'isFolder': file.isFolder},
          ),
      ];
    });

/// On/off bookmark state for the active workspace, so menus can label their
/// action and the sidebar can mark rows without a second round trip.
final driveFavoriteIdsProvider =
    AsyncNotifierProvider<DriveFavoriteIdsNotifier, Set<String>>(
      DriveFavoriteIdsNotifier.new,
    );

class DriveFavoriteIdsNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final workspaceId = ref.watch(activeDriveWorkspaceIdProvider);
    final files = await ref.watch(
      favoriteCloudFilesProvider(workspaceId).future,
    );
    return {for (final file in files) file.id};
  }

  /// Flips the bookmark and returns whether the file is favorited afterwards.
  Future<bool> toggle(String fileId) async {
    final client = ref.read(wattEngineClientProvider);
    final workspaceId = ref.read(activeDriveWorkspaceIdProvider);
    final wasFavorite = state.value?.contains(fileId) ?? false;
    if (wasFavorite) {
      await client.unfavoriteCloudFile(fileId);
    } else {
      await client.favoriteCloudFile(fileId);
    }
    ref.invalidate(favoriteCloudFilesProvider(workspaceId));
    final next = wasFavorite
        ? (Set<String>.from(state.value ?? const {})..remove(fileId))
        : {...state.value ?? const <String>{}, fileId};
    state = AsyncData(next);
    return !wasFavorite;
  }
}

/// Bookmark or unbookmark [file]; drive files live on the filesystem service.
Future<void> toggleDriveFavorite(WidgetRef ref, SnCloudFile file) =>
    ref.read(driveFavoriteIdsProvider.notifier).toggle(file.id);

/// Whether [entity] is a favorite, reading the local list or the drive's
/// server bookmarks as its domain requires.
bool isFavoriteEntity(WidgetRef ref, WorkspaceEntityRef entity) {
  if (entity.domain == WorkspaceDomain.drive) {
    return ref.watch(driveFavoriteIdsProvider).value?.contains(entity.id) ??
        false;
  }
  return ref
      .watch(favoritesProvider)
      .any((item) => item.domain == entity.domain && item.id == entity.id);
}

/// Toggles [entity] in the list its domain keeps its favorites in.
Future<void> toggleFavoriteEntity(
  WidgetRef ref,
  WorkspaceEntityRef entity,
) async {
  if (entity.domain == WorkspaceDomain.drive) {
    await ref.read(driveFavoriteIdsProvider.notifier).toggle(entity.id);
    // A drive favorite may survive locally from a build that kept every domain
    // in preferences; drop that copy so the two lists cannot disagree.
    ref
        .read(favoritesProvider.notifier)
        .remove(WorkspaceDomain.drive, entity.id);
    return;
  }
  ref.read(favoritesProvider.notifier).toggleFavorite(entity);
}
