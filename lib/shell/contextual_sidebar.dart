import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/pages/pages_provider.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/workspace/components/workspace_header.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_state.dart';

/// Zone 2: Contextual Sidebar (240px on Desktop, modal left Drawer on Tablet).
///
/// Renders:
/// 1. `Pinned` — shared favorites across all four domains.
/// 2. The active [WorkspaceLens]'s own tree: mail folders, Todo boards, the
///    pages tree, or Drive filters. Lenses without a tree of their own (Today,
///    Flywheel, Profile, Settings) hide this column entirely — it would only
///    repeat the rail.
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
    final pinned = ref.watch(pinnedItemsProvider);

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
                _SectionLabel(label: 'Pinned'),
                if (pinned.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SolSpace.xs,
                      vertical: SolSpace.xs,
                    ),
                    child: Text(
                      'Pin any folder, page, thread, or board.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  for (final item in pinned)
                    WorkspaceListRow(
                      compact: true,
                      leading: Icon(
                        item.domain.icon,
                        size: 16,
                        color: scheme.primary,
                      ),
                      title: Text(item.title),
                      trailing: IconButton(
                        icon: const Icon(Symbols.close_rounded, size: 14),
                        tooltip: 'Unpin',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => ref
                            .read(pinnedItemsProvider.notifier)
                            .togglePin(item),
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
                _SectionLabel(label: activeLens.label.toUpperCase()),
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
        final boards = ref.watch(broadsProvider).value ?? const [];
        return Column(
          children: [
            if (boards.isEmpty)
              Padding(
                padding: const EdgeInsets.all(SolSpace.sm),
                child: Text(
                  'No boards loaded yet.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final board in boards)
                WorkspaceListRow(
                  compact: true,
                  leading: const Icon(Symbols.view_kanban_rounded, size: 16),
                  title: Text(board.name),
                  selected: false,
                  onTap: () {
                    onCloseDrawer?.call();
                    final entity = WorkspaceEntityRef(
                      id: board.id,
                      domain: WorkspaceDomain.todo,
                      title: board.name,
                      subtitle: board.description ?? 'Task Board',
                      badgeText: 'Board',
                      metadata: {'broadId': board.id, 'isBoard': true},
                    );
                    if (onOpenEntity != null) {
                      onOpenEntity!(entity);
                    } else {
                      ref.read(peekProvider.notifier).open(entity);
                    }
                  },
                ),
          ],
        );

      case WorkspaceLens.pages:
        final pages = ref.watch(pagesProvider);
        final selectedPageId = ref.watch(selectedPageIdProvider);
        return Column(
          children: [
            for (final page in pages)
              WorkspaceListRow(
                compact: true,
                selected:
                    selectedPageId == page.id ||
                    (selectedPageId == null && pages.first.id == page.id),
                leading: Text(page.icon, style: const TextStyle(fontSize: 14)),
                title: Text(page.title.isEmpty ? 'Untitled Page' : page.title),
                onTap: () {
                  ref.read(selectedPageIdProvider.notifier).select(page.id);
                  onCloseDrawer?.call();
                  onOpenEntity?.call(page.toEntityRef());
                },
              ),
            const SizedBox(height: SolSpace.xs),
            WorkspaceListRow(
              compact: true,
              leading: Icon(
                Symbols.add_rounded,
                size: 16,
                color: scheme.primary,
              ),
              title: Text('New Page', style: TextStyle(color: scheme.primary)),
              onTap: () {
                ref.read(pagesProvider.notifier).createPage();
                onCloseDrawer?.call();
              },
            ),
          ],
        );

      case WorkspaceLens.drive:
        const driveSections = [
          ('all', 'All Files', Symbols.folder_rounded),
          ('recent', 'Recent Uploads', Symbols.schedule_rounded),
          ('shared', 'Shared', Symbols.group_rounded),
        ];
        return Column(
          children: [
            for (final (_, label, icon) in driveSections)
              DragTarget<WorkspaceEntityRef>(
                onWillAcceptWithDetails: (details) =>
                    details.data.isAttachment ||
                    details.data.domain == WorkspaceDomain.mail,
                onAcceptWithDetails: (details) {
                  HapticFeedback.selectionClick();
                  ref
                      .read(savedAttachmentIdsProvider.notifier)
                      .markSaved(details.data.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Saved "${details.data.title}" to Drive, $label',
                      ),
                    ),
                  );
                },
                builder: (context, candidateData, rejectedData) {
                  final hovered = candidateData.isNotEmpty;
                  return Container(
                    decoration: hovered
                        ? BoxDecoration(
                            color: scheme.primaryContainer.withValues(
                              alpha: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(SolRadius.xs),
                          )
                        : null,
                    child: WorkspaceListRow(
                      compact: true,
                      leading: Icon(icon, size: 16),
                      title: Text(label),
                      onTap: () => onCloseDrawer?.call(),
                    ),
                  );
                },
              ),
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
              WorkspaceLens.pages,
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
