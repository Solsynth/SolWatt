import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/drive/favorites.dart';
import 'package:solwatt/drive/widgets/file_list_view.dart' show FileListMode;
import 'package:solwatt/network.dart';
import 'package:solwatt/pages/pages_provider.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/workspace/components/workspace_header.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_state.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart'
    show formatFileSize;

/// Zone 2: Contextual Sidebar (240px on Desktop, modal left Drawer on Tablet).
///
/// Renders:
/// 1. `Favorites` — one shared list across mail, boards, pages and drive
///    files. Drive bookmarks live on the filesystem service, so they follow the
///    reader between devices; the rest are local workspace references.
/// 2. The active [WorkspaceLens]'s own tree. For Drive that tree is the pane
///    switch (cloud folders / service attachments), the storage meter, and the
///    drop targets that save mail attachments. Lenses without a tree of their
///    own (Today, Flywheel, Profile, Settings) hide this column entirely — it
///    would only repeat the rail.
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView(
              // The column is a panel, not a bare list: it keeps a real gutter
              // from its own edge so rows never sit flush against the rail's
              // rounded corner.
              padding: const EdgeInsets.fromLTRB(
                SolSpace.md,
                SolSpace.sm,
                SolSpace.md,
                SolSpace.sm,
              ),
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
                      subtitle: item.domain == WorkspaceDomain.drive &&
                              (item.subtitle?.isNotEmpty ?? false)
                          ? Text(item.subtitle!)
                          : null,
                      trailing: IconButton(
                        icon: const Icon(Symbols.star_rounded, size: 15),
                        tooltip: 'Remove from Favorites',
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            toggleFavoriteEntity(ref, item),
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
                  label: activeLens == WorkspaceLens.today ||
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
        return _BroadTree(
          onOpenEntity: onOpenEntity,
          onCloseDrawer: onCloseDrawer,
        );
      case WorkspaceLens.drive:
        final browseMode = ref.watch(driveBrowseModeProvider);
        final storage = ref.watch(driveStorageUsageProvider).value;
        final recentDriveFiles = ref
            .watch(recentEntitiesProvider)
            .where((item) => item.domain == WorkspaceDomain.drive)
            .take(5)
            .toList(growable: false);
        return Column(
          children: [
            _DrivePaneSwitch(
              mode: browseMode,
              onSelect: (mode) {
                ref.read(driveBrowseModeProvider.notifier).select(mode);
                onCloseDrawer?.call();
              },
            ),
            if (storage != null) ...[
              const SizedBox(height: SolSpace.sm),
              _StorageMeter(storage: storage),
            ],
            const SizedBox(height: SolSpace.md),
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

/// The Drive lens has two panes, not two lenses: cloud folders and service
/// attachments. Choosing one here retargets the open drive browser.
class _DrivePaneSwitch extends StatelessWidget {
  final FileListMode mode;
  final ValueChanged<FileListMode> onSelect;

  const _DrivePaneSwitch({required this.mode, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SolSpace.xs),
      child: SegmentedButton<FileListMode>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          textStyle: Theme.of(context).textTheme.labelSmall,
          selectedForegroundColor: scheme.onSecondaryContainer,
          selectedBackgroundColor: scheme.secondaryContainer,
        ),
        segments: const [
          ButtonSegment(
            value: FileListMode.normal,
            label: Text('Cloud'),
            icon: Icon(Symbols.folder_rounded, size: 15),
          ),
          ButtonSegment(
            value: FileListMode.unindexed,
            label: Text('Assets'),
            icon: Icon(Symbols.inventory_2_rounded, size: 15),
          ),
        ],
        selected: {mode},
        onSelectionChanged: (selection) => onSelect(selection.first),
      ),
    );
  }
}

/// Quiet storage readout: the meter is the headline, the numbers carry the
/// exact figures. Tapping it is the drive's own usage sheet, so the column
/// never becomes a dashboard.
class _StorageMeter extends StatelessWidget {
  final DriveStorageSnapshot storage;

  const _StorageMeter({required this.storage});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = storage.ratio;
    final tone = ratio >= 0.9
        ? scheme.error
        : ratio >= 0.75
        ? scheme.tertiary
        : scheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SolSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.cloud_rounded, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Storage',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${(ratio * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              color: tone,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${formatFileSize(storage.usedBytes)} of ${formatFileSize(storage.totalBytes)}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
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

/// The Ideask tree: boards and pages side by side, because they are the same
/// rows on the service. New pages are created from the board list's create
/// action, so this column only routes.
class _BroadTree extends ConsumerWidget {
  final ValueChanged<WorkspaceEntityRef>? onOpenEntity;
  final VoidCallback? onCloseDrawer;

  const _BroadTree({this.onOpenEntity, this.onCloseDrawer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final boards = ref.watch(broadsProvider);
    final favorites = ref.watch(favoritesProvider);

    return boards.when(
      // A still placeholder: the tree resolves once per workspace, and an
      // indeterminate bar would animate for the whole wait.
      loading: () => Padding(
        padding: const EdgeInsets.all(SolSpace.sm),
        child: Text(
          'Loading boards…',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(SolSpace.sm),
        child: Text(
          'Could not load boards.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
      data: (broads) {
        if (broads.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(SolSpace.sm),
            child: Text(
              'No boards or pages yet.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          );
        }
        return Column(
          children: [
            for (final broad in broads)
              _BroadTreeRow(
                broad: broad,
                selected: false,
                favorite: favorites.any(
                  (item) =>
                      item.domain ==
                          (broad.isPage
                              ? WorkspaceDomain.pages
                              : WorkspaceDomain.todo) &&
                      item.id == broad.id,
                ),
                onOpenEntity: onOpenEntity,
                onCloseDrawer: onCloseDrawer,
              ),
          ],
        );
      },
    );
  }
}

class _BroadTreeRow extends ConsumerWidget {
  final Broad broad;
  final bool selected;
  final bool favorite;
  final ValueChanged<WorkspaceEntityRef>? onOpenEntity;
  final VoidCallback? onCloseDrawer;

  const _BroadTreeRow({
    required this.broad,
    required this.selected,
    required this.favorite,
    this.onOpenEntity,
    this.onCloseDrawer,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entity = broadToEntityRef(broad);
    return WorkspaceListRow(
      compact: true,
      selected: selected,
      leading: Icon(
        broad.isPage ? Symbols.article_rounded : Symbols.view_kanban_rounded,
        size: 16,
      ),
      title: Text(
        broad.name.isEmpty
            ? (broad.isPage ? 'Untitled page' : 'Untitled board')
            : broad.name,
      ),
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
