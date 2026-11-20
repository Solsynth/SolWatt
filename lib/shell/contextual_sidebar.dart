import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/drive/favorites.dart';
import 'package:solwatt/drive/usage.dart';
import 'package:solwatt/drive/widgets/drive_pane_switch.dart';
import 'package:solwatt/drive/widgets/file_list_view.dart' show FileListMode;
import 'package:solwatt/drive/widgets/storage_meter.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/ideask/ideask_providers.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/workspace/components/workspace_header.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_state.dart';

/// Zone 2: Contextual Sidebar (240px on Desktop, modal left Drawer on Tablet).
///
/// Renders:
/// 1. `Favorites` — one shared list across mail, folders, pages and drive
///    files. Drive bookmarks live on the filesystem service, so they follow the
///    reader between devices; the rest are local workspace references.
/// 2. The active [WorkspaceLens]'s own tree. For Drive that tree is the drop
///    target that saves mail attachments and the recent files; the pane switch
///    and the storage meter dock to the column's bottom edge instead, where
///    they stay reachable. Lenses without a tree of their own (Today, Flywheel,
///    Profile, Settings) hide this column entirely — it would only repeat the
///    rail.
class ContextualSidebar extends ConsumerWidget {
  final WorkspaceLens activeLens;
  final ValueChanged<WorkspaceLens> onSelectLens;
  final ValueChanged<WorkspaceEntityRef>? onOpenEntity;
  final VoidCallback? onCloseDrawer;

  const ContextualSidebar({
    super.key,
    required this.activeLens,
    required this.onSelectLens,
    this.onOpenEntity,
    this.onCloseDrawer,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final localFavorites = ref.watch(favoritesProvider);
    final driveFavorites =
        ref.watch(driveFavoriteEntitiesProvider).value ?? const [];

    // Drive bookmarks come from the service, so a stale local entry for the
    // same file must not produce a second row.
    final localOnly = localFavorites
        .where((item) => item.domain != WorkspaceDomain.drive)
        .toList(growable: false);
    final favorites = [...localOnly, ...driveFavorites];

    return Container(
      width: SolWorkspaceGeometry.sidebarWidth,
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              // The column is a panel, not a bare list: it keeps a real gutter
              // from its own edge so rows never sit flush against the rail's
              // rounded corner.
              padding: const EdgeInsets.fromLTRB(
                SolSpace.md,
                SolSpace.sm,
                SolSpace.md,
                SolSpace.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionLabel(label: 'Favorites'),
                  if (favorites.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SolSpace.xs,
                        vertical: SolSpace.xs,
                      ),
                      child: Text(
                        'Star a file, folder, page, thread, or board to keep it here.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (final item in favorites)
                      WorkspaceListRow(
                        compact: true,
                        leading: Icon(
                          item.domain.icon,
                          size: 16,
                          color: scheme.primary,
                        ),
                        title: Text(item.title),
                        subtitle:
                            item.domain == WorkspaceDomain.drive &&
                                (item.subtitle?.isNotEmpty ?? false)
                            ? Text(item.subtitle!)
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Symbols.star_rounded, size: 15),
                          tooltip: 'Remove from Favorites',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => toggleFavoriteEntity(ref, item),
                        ),
                        onTap: () {
                          onCloseDrawer?.call();
                          if (onOpenEntity != null) {
                            onOpenEntity!(item);
                          } else {
                            ref.read(peekProvider.notifier).open(item);
                          }
                        },
                      ),
                  const SizedBox(height: SolSpace.lg),
                  _SectionLabel(
                    label:
                        activeLens == WorkspaceLens.today ||
                            activeLens == WorkspaceLens.flywheel ||
                            activeLens == WorkspaceLens.profile ||
                            activeLens == WorkspaceLens.settings
                        ? 'BROWSE'
                        : activeLens.label.toUpperCase(),
                  ),
                  const SizedBox(height: SolSpace.xs),
                  _buildLensTree(context, ref, scheme),
                ],
              ),
            ),
          ),
          // The drive dock sits outside the scroll view so the pane switch and
          // the meter stay reachable no matter how long Favorites grows.
          if (activeLens == WorkspaceLens.drive)
            _DriveDock(onCloseDrawer: onCloseDrawer),
        ],
      ),
    );
  }

  Widget _buildLensTree(
    BuildContext context,
    WidgetRef ref,
    ColorScheme scheme,
  ) {
    switch (activeLens) {
      case WorkspaceLens.mail:
        final selectedFolder = ref.watch(selectedFolderProvider);
        const folders = [
          ('inbox', 'Inbox', Symbols.inbox_rounded),
          ('sent', 'Sent', Symbols.send_rounded),
          ('drafts', 'Drafts', Symbols.drafts_rounded),
          ('archive', 'Archive', Symbols.archive_rounded),
          ('trash', 'Trash', Symbols.delete_rounded),
        ];
        return Column(
          children: [
            for (final (id, label, icon) in folders)
              WorkspaceListRow(
                compact: true,
                selected: selectedFolder == id,
                leading: Icon(icon, size: 16),
                title: Text(label),
                onTap: () {
                  ref.read(selectedFolderProvider.notifier).select(id);
                  onCloseDrawer?.call();
                },
              ),
          ],
        );

      case WorkspaceLens.todo:
        return _IdeaskTree(
          onOpenEntity: onOpenEntity,
          onCloseDrawer: onCloseDrawer,
        );
      case WorkspaceLens.drive:
        final recentDriveFiles = ref
            .watch(recentEntitiesProvider)
            .where((item) => item.domain == WorkspaceDomain.drive)
            .take(5)
            .toList(growable: false);
        return Column(
          crossAxisAlignment: .stretch,
          children: [
            // Saving a mail attachment into Drive is a drop, so the drop
            // target is the row itself.
            _DriveDropRow(
              label: 'All Files',
              icon: Symbols.folder_rounded,
              onTap: () {
                ref
                    .read(driveBrowseModeProvider.notifier)
                    .select(FileListMode.normal);
                onCloseDrawer?.call();
              },
            ),
            if (recentDriveFiles.isNotEmpty) ...[
              const SizedBox(height: SolSpace.md),
              _SectionLabel(label: 'RECENT'),
              for (final item in recentDriveFiles)
                WorkspaceListRow(
                  compact: true,
                  leading: Icon(item.domain.icon, size: 16),
                  title: Text(item.title),
                  onTap: () {
                    onCloseDrawer?.call();
                    if (onOpenEntity != null) {
                      onOpenEntity!(item);
                    } else {
                      ref.read(peekProvider.notifier).open(item);
                    }
                  },
                ),
            ],
          ],
        );

      case WorkspaceLens.today:
      case WorkspaceLens.flywheel:
      case WorkspaceLens.profile:
      case WorkspaceLens.settings:
        final recent = ref.watch(recentEntitiesProvider);
        return Column(
          children: [
            for (final lens in [
              WorkspaceLens.mail,
              WorkspaceLens.todo,
              WorkspaceLens.drive,
            ])
              WorkspaceListRow(
                compact: true,
                leading: Icon(lens.icon, size: 16),
                title: Text(lens.label),
                onTap: () {
                  onSelectLens(lens);
                  onCloseDrawer?.call();
                },
              ),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: SolSpace.md),
              _SectionLabel(label: 'RECENT'),
              for (final item in recent.take(5))
                WorkspaceListRow(
                  compact: true,
                  leading: Icon(item.domain.icon, size: 16),
                  title: Text(item.title),
                  onTap: () {
                    onCloseDrawer?.call();
                    if (onOpenEntity != null) {
                      onOpenEntity!(item);
                    } else {
                      ref.read(peekProvider.notifier).open(item);
                    }
                  },
                ),
            ],
          ],
        );
    }
  }
}

/// The Drive lens' control dock, pinned below the scrolling column: the pane
/// switch on top, then the storage meter. The meter is the drive's usage
/// sheet trigger, so the exact figures stay one tap from the column without
/// growing it into a dashboard.
class _DriveDock extends ConsumerWidget {
  final VoidCallback? onCloseDrawer;

  const _DriveDock({this.onCloseDrawer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final mode = ref.watch(driveBrowseModeProvider);
    final storage = ref.watch(driveStorageUsageProvider).value;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SolSpace.md,
          vertical: SolSpace.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DrivePaneSwitch(
              mode: mode,
              onSelect: (mode) {
                ref.read(driveBrowseModeProvider.notifier).select(mode);
                onCloseDrawer?.call();
              },
            ),
            if (storage != null) ...[
              const SizedBox(height: SolSpace.md),
              InkWell(
                borderRadius: BorderRadius.circular(SolRadius.xs),
                onTap: () => showDriveUsageSheet(context, storage),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SolSpace.xs,
                    vertical: SolSpace.xs,
                  ),
                  child: DriveStorageMeter(storage: storage),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A Drive destination row. Saving a mail attachment is a drop, so the row
/// carries the drop target itself rather than a "save" dialog.
class _DriveDropRow extends ConsumerWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _DriveDropRow({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final row = WorkspaceListRow(
      compact: true,
      leading: Icon(icon, size: 16),
      title: Text(label),
      onTap: onTap,
    );

    return DragTarget<WorkspaceEntityRef>(
      onWillAcceptWithDetails: (details) =>
          details.data.isAttachment ||
          details.data.domain == WorkspaceDomain.mail,
      onAcceptWithDetails: (details) {
        HapticFeedback.selectionClick();
        ref
            .read(savedAttachmentIdsProvider.notifier)
            .markSaved(details.data.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved "${details.data.title}" to Drive')),
        );
      },
      builder: (context, candidateData, rejectedData) {
        final hovered = candidateData.isNotEmpty;
        return Container(
          decoration: hovered
              ? BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(SolRadius.xs),
                )
              : null,
          child: row,
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SolSpace.xs,
        vertical: SolSpace.xs,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

/// The Ideask tree, top level: folders, top-level pages and collections, the
/// same rows the Todo lens browses. Selecting one routes through the lens.
class _IdeaskTree extends ConsumerWidget {
  final ValueChanged<WorkspaceEntityRef>? onOpenEntity;
  final VoidCallback? onCloseDrawer;

  const _IdeaskTree({this.onOpenEntity, this.onCloseDrawer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final workspaceId = ref.watch(ideaskWorkspaceIdProvider);
    if (workspaceId == null) {
      return Padding(
        padding: const EdgeInsets.all(SolSpace.sm),
        child: Text(
          'Select a workspace to see its folders.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }
    final folderId = switch (ref.watch(ideaskSelectionProvider)) {
      IdeaskFolderSelection(:final folderId) => folderId,
      _ => null,
    };
    final contents = folderId == null
        ? ref.watch(ideaskBrowserProvider)
        : ref.watch(ideaskFolderContentsProvider(folderId));

    return contents.when(
      // A still placeholder: the tree resolves once per workspace, and an
      // indeterminate bar would animate for the whole wait.
      loading: () => Padding(
        padding: const EdgeInsets.all(SolSpace.sm),
        child: Text(
          'Loading folders…',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(SolSpace.sm),
        child: Text(
          'Could not load the tree.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
      data: (state) {
        final folders = state is IdeaskBrowserState
            ? state.folders
            : (state as IdeaskFolderContents).folders;
        final pages = state is IdeaskBrowserState
            ? state.pages
            : (state as IdeaskFolderContents).pages;
        final collections = state is IdeaskBrowserState
            ? state.collections
            : (state as IdeaskFolderContents).collections;
        if (folders.isEmpty && pages.isEmpty && collections.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(SolSpace.sm),
            child: Text(
              'No folders or pages here yet.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (folderId != null)
              WorkspaceListRow(
                compact: true,
                leading: const Icon(Symbols.arrow_upward, size: 16),
                title: const Text('Up one level'),
                onTap: () {
                  onCloseDrawer?.call();
                  ref.read(ideaskSelectionProvider.notifier).openRoot();
                },
              ),
            for (final folder in folders)
              _IdeaskTreeRow(
                entity: ideaskEntityRefForFolder(folder),
                icon: Symbols.folder_rounded,
                onOpenEntity: onOpenEntity,
                onCloseDrawer: onCloseDrawer,
              ),
            for (final collection in collections)
              _IdeaskTreeRow(
                entity: ideaskEntityRefForCollection(collection),
                icon: Symbols.table_chart_rounded,
                onOpenEntity: onOpenEntity,
                onCloseDrawer: onCloseDrawer,
              ),
            for (final page in pages)
              _IdeaskTreeRow(
                entity: ideaskEntityRefForPage(page),
                icon: Symbols.article_rounded,
                onOpenEntity: onOpenEntity,
                onCloseDrawer: onCloseDrawer,
              ),
          ],
        );
      },
    );
  }
}

class _IdeaskTreeRow extends ConsumerWidget {
  final WorkspaceEntityRef entity;
  final IconData icon;
  final ValueChanged<WorkspaceEntityRef>? onOpenEntity;
  final VoidCallback? onCloseDrawer;

  const _IdeaskTreeRow({
    required this.entity,
    required this.icon,
    this.onOpenEntity,
    this.onCloseDrawer,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final favorite = favorites.any(
      (item) => item.domain == entity.domain && item.id == entity.id,
    );
    return WorkspaceListRow(
      compact: true,
      leading: Icon(icon, size: 16),
      title: Text(entity.title),
      onTap: () {
        onCloseDrawer?.call();
        if (onOpenEntity != null) {
          onOpenEntity!(entity);
        } else {
          ref.read(peekProvider.notifier).open(entity);
        }
      },
      onLongPress: () =>
          ref.read(favoritesProvider.notifier).toggleFavorite(entity),
      trailing: IconButton(
        tooltip: favorite ? 'Remove from Favorites' : 'Add to Favorites',
        visualDensity: VisualDensity.compact,
        icon: Icon(
          favorite ? Symbols.star_rounded : Symbols.star_border_rounded,
          size: 15,
        ),
        onPressed: () =>
            ref.read(favoritesProvider.notifier).toggleFavorite(entity),
      ),
    );
  }
}
