/// The Todo lens: one Ideask tree over folders, pages, collections and tasks.
///
/// The lens is a browser over one tree. A document (a page, a folder's task
/// list, a collection) is pushed on the lens' nested stack, so Back walks the
/// way the reader walked and the app shell stays put.
library;

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/ideask/ideask_providers.dart';
import 'package:solwatt/ideask/task_surfaces.dart';
import 'package:solwatt/drive/favorites.dart' show isFavoriteEntity;
import 'package:solwatt/network.dart';
import 'package:solwatt/route.dart';
import 'package:solwatt/shared/widgets/alert.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/ui/cloud_files.dart';
import 'package:solwatt/ui/name_sheet.dart';
import 'package:solwatt/ui/page_scaffold.dart';

/// The Todo lens' route: a nested stack whose root is the browser, so a page,
/// a task list or a collection can be pushed above it without covering the
/// app shell.
@RoutePage()
class IdeaskLensPage extends StatelessWidget {
  const IdeaskLensPage({super.key});

  @override
  Widget build(BuildContext context) => const AutoRouter();
}

/// The Ideask browser. Everything the workspace holds is one tree; the browser
/// shows one level at a time and pushes documents above itself.
@RoutePage()
class IdeaskBrowserPage extends ConsumerWidget {
  const IdeaskBrowserPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceId = ref.watch(ideaskWorkspaceIdProvider);
    final selection = ref.watch(ideaskSelectionProvider);
    final browser = ref.watch(ideaskBrowserProvider);
    final breadcrumb = ref.watch(ideaskBreadcrumbProvider).value ?? const [];

    if (workspaceId == null) {
      return PageScaffold(
        title: 'todo'.tr(),
        child: EmptyState(
          icon: Symbols.workspaces,
          title: 'selectWorkspaceTitle'.tr(),
          message: 'selectWorkspaceFirst'.tr(),
        ),
      );
    }

    final title = switch (selection) {
      IdeaskRootSelection() => 'todo'.tr(),
      IdeaskFolderSelection() =>
        breadcrumb.isEmpty ? 'folder'.tr() : breadcrumb.last.name,
      IdeaskCollectionSelection() =>
        browser.value?.collection?.name ?? 'collection'.tr(),
    };

    return PageScaffold(
      title: title,
      subtitle: selection is IdeaskRootSelection ? 'ideaskTree'.tr() : null,
      maxContentWidth: double.infinity,
      action: IconButton.filledTonal(
        tooltip: 'create'.tr(),
        onPressed: () => showIdeaskCreateSheet(context, ref),
        icon: const Icon(Symbols.add),
      ),
      bottom: selection is IdeaskRootSelection
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: _IdeaskBreadcrumb(breadcrumb: breadcrumb),
            ),
      // The lens owns its own column of documents, so the root is a pane.
      floatingActionButton: null,
      actions: [
        IconButton(
          tooltip: 'unfiledTasks'.tr(),
          onPressed: () => context.router.push(TaskListRoute(unfiled: true)),
          icon: const Icon(Symbols.inbox),
        ),
      ],
      child: browser.when(
        loading: () => const PageLoading(),
        error: (error, _) => PageError(
          message: wattApiErrorMessage(error),
          onRetry: () => ref.invalidate(ideaskBrowserProvider),
        ),
        data: (state) {
          // A collection is a document of its own: its rows are a table, not
          // the folder browser's tiles.
          if (state.collection case final collection?) {
            return _CollectionOverview(collection: collection);
          }
          if (state.isEmpty) {
            return EmptyState(
              icon: Symbols.folder_open,
              title: 'noTreeNodes'.tr(),
              message: 'createSomethingToOrganize'.tr(),
              action: FilledButton.icon(
                onPressed: () => showIdeaskCreateSheet(context, ref),
                icon: const Icon(Symbols.add),
                label: Text('create'.tr()),
              ),
            );
          }
          final entries = <_IdeaskEntry>[
            for (final folder in state.folders) _IdeaskEntry.folder(folder),
            for (final collection in state.collections)
              _IdeaskEntry.collection(collection),
            for (final page in state.pages) _IdeaskEntry.page(page),
          ];
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _IdeaskRow(entry: entries[index]),
          );
        },
      ),
    );
  }
}

/// One browser row: a folder, a collection, or a page.
class _IdeaskEntry {
  const _IdeaskEntry.folder(IdeaskFolder this.folder)
    : collection = null,
      page = null;
  const _IdeaskEntry.collection(IdeaskCollection this.collection)
    : folder = null,
      page = null;
  const _IdeaskEntry.page(IdeaskPage this.page)
    : folder = null,
      collection = null;

  final IdeaskFolder? folder;
  final IdeaskCollection? collection;
  final IdeaskPage? page;

  String get id => folder?.id ?? collection?.id ?? page?.id ?? '';
  String get title =>
      folder?.name ?? collection?.name ?? page?.displayTitle ?? '';
  String? get subtitle =>
      folder?.description ?? collection?.description ?? page?.description;
  IconData get icon => switch ((folder, collection)) {
    (final IdeaskFolder _, _) => Symbols.folder,
    (_, final IdeaskCollection _) => Symbols.table_chart,
    _ => Symbols.article,
  };
  IconData get trailingIcon => switch ((folder, collection)) {
    (final IdeaskFolder _, _) => Symbols.chevron_right,
    (_, final IdeaskCollection _) => Symbols.chevron_right,
    _ => Symbols.chevron_right,
  };
}

class _IdeaskRow extends ConsumerWidget {
  const _IdeaskRow({required this.entry});

  final _IdeaskEntry entry;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    if (entry.folder case final folder?) {
      ref.read(ideaskSelectionProvider.notifier).openFolder(folder.id);
      return;
    }
    if (entry.collection case final collection?) {
      await context.router.push(CollectionRoute(collectionId: collection.id));
      return;
    }
    if (entry.page case final page?) {
      await context.router.push(DocRoute(pageId: page.id));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final subtitle = entry.subtitle?.trim();
    final entity = switch ((entry.folder, entry.collection, entry.page)) {
      (final IdeaskFolder folder?, _, _) => ideaskEntityRefForFolder(folder),
      (_, final IdeaskCollection collection?, _) =>
        ideaskEntityRefForCollection(collection),
      (_, _, final IdeaskPage page?) => ideaskEntityRefForPage(page),
      _ => null,
    };
    final favorite = entity == null ? false : isFavoriteEntity(ref, entity);
    final icon =
        entry.page?.icon ?? entry.collection?.icon ?? entry.folder?.icon;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(SolRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        leading: CloudFileAvatar(
          file: icon,
          fallbackIcon: entry.icon,
          size: 40,
        ),
        title: Text(
          entry.title.isEmpty ? 'untitled'.tr() : entry.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: subtitle == null || subtitle.isEmpty
            ? null
            : Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (entry.folder case final folder?)
              IconButton(
                tooltip: 'tasks'.tr(),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Symbols.task_alt, size: 18),
                onPressed: () => context.router.push(
                  TaskListRoute(folderId: folder.id),
                ),
              ),
            if (entity != null)
              IconButton(
                tooltip: favorite ? 'removeFromFavorites' : 'addToFavorites',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  favorite ? Symbols.star_rounded : Symbols.star_border_rounded,
                  size: 18,
                  color: favorite ? scheme.primary : scheme.onSurfaceVariant,
                ),
                onPressed: () =>
                    ref.read(ideaskActionsProvider).toggleFavorite(entity),
              ),
            Icon(entry.trailingIcon, size: 18),
          ],
        ),
        onTap: () => _open(context, ref),
      ),
    );
  }
}

/// A collection's metadata and rows, opened as its own route.
@RoutePage()
class CollectionPage extends ConsumerWidget {
  const CollectionPage({
    super.key,
    @PathParam('collectionId') required this.collectionId,
  });

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = ref.watch(ideaskCollectionProvider(collectionId));
    return collection.when(
      loading: () => const PageLoading(),
      error: (error, _) => PageError(
        message: wattApiErrorMessage(error),
        onRetry: () => ref.invalidate(ideaskCollectionProvider(collectionId)),
      ),
      data: (collection) => CollectionView(collection: collection),
    );
  }
}

/// A collection inside the browser (the lens root's selection).
class _CollectionOverview extends StatelessWidget {
  const _CollectionOverview({required this.collection});

  final IdeaskCollection collection;

  @override
  Widget build(BuildContext context) => CollectionView(collection: collection);
}

/// A collection's saved views over its rows. Rows are pages: opening one
/// pushes the page editor.
class CollectionView extends ConsumerStatefulWidget {
  const CollectionView({super.key, required this.collection});

  final IdeaskCollection collection;

  @override
  ConsumerState<CollectionView> createState() => _CollectionViewState();
}

class _CollectionViewState extends ConsumerState<CollectionView> {
  String? _viewId;

  Future<void> _addRow() async {
    final title = await showNameInputSheet(
      context,
      title: 'newRow'.tr(),
      label: 'title'.tr(),
      confirmLabel: 'create'.tr(),
      icon: Symbols.table_rows,
    );
    if (title == null || title.trim().isEmpty) return;
    try {
      await ref
          .read(ideaskActionsProvider)
          .createRow(collectionId: widget.collection.id, title: title.trim());
      showSnackBar('rowCreated'.tr());
    } catch (error) {
      showSnackBar(wattApiErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = widget.collection;
    final views = collection.views;
    final viewId = views.any((view) => view.id == _viewId)
        ? _viewId
        : views.firstOrNull?.id;
    final rows = ref.watch(
      ideaskCollectionQueryProvider((
        collectionId: collection.id,
        viewId: viewId,
      )),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                collection.description ?? '',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _addRow,
              icon: const Icon(Symbols.add, size: 18),
              label: Text('newRow'.tr()),
            ),
          ],
        ),
        if (views.length > 1) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final view in views)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(view.name),
                      selected: view.id == viewId,
                      onSelected: (_) => setState(() => _viewId = view.id),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: rows.when(
            loading: () => const PageLoading(),
            error: (error, _) => PageError(
              message: wattApiErrorMessage(error),
              onRetry: () => ref.invalidate(
                ideaskCollectionQueryProvider((
                  collectionId: collection.id,
                  viewId: viewId,
                )),
              ),
            ),
            data: (result) {
              if (result.rows.isEmpty) {
                return EmptyState(
                  icon: Symbols.table_rows,
                  title: 'noRowsYet'.tr(),
                  message: 'collectionNeedsRows'.tr(),
                  action: FilledButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Symbols.add),
                    label: Text('newRow'.tr()),
                  ),
                );
              }
              return ListView.separated(
                itemCount: result.rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final row = result.rows[index];
                  final values = <String>[
                    for (final property in collection.properties)
                      if (row.properties[property.id] case final value?)
                        if (value.toString().trim().isNotEmpty)
                          '${property.name}: $value',
                  ];
                  return ListTile(
                    leading: const Icon(Symbols.table_rows, size: 20),
                    title: Text(
                      row.title.isEmpty ? 'untitledRow'.tr() : row.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: values.isEmpty
                        ? null
                        : Text(
                            values.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    trailing: const Icon(Symbols.chevron_right, size: 18),
                    onTap: () => context.router.push(DocRoute(pageId: row.id)),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The path back up the tree, shown under the title while inside a folder.
class _IdeaskBreadcrumb extends ConsumerWidget {
  const _IdeaskBreadcrumb({required this.breadcrumb});

  final List<IdeaskFolder> breadcrumb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final path = ['todo'.tr(), ...breadcrumb.map((folder) => folder.name)];
    return SizedBox(
      height: 40,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              for (var index = 0; index < path.length; index++) ...[
                if (index > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Symbols.chevron_right,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                InkWell(
                  borderRadius: BorderRadius.circular(SolRadius.xs),
                  onTap: index == path.length - 1
                      ? null
                      : () {
                          final notifier = ref.read(
                            ideaskSelectionProvider.notifier,
                          );
                          if (index == 0) {
                            notifier.openRoot();
                          } else {
                            notifier.openFolder(breadcrumb[index - 1].id);
                          }
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      path[index],
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: index == path.length - 1
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                        fontWeight: index == path.length - 1
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One create action for the whole tree: a folder, a page, a collection or a
/// task in the folder currently open.
Future<void> showIdeaskCreateSheet(BuildContext context, WidgetRef ref) async {
  final workspaceId = ref.read(ideaskWorkspaceIdProvider);
  if (workspaceId == null) {
    showSnackBar('selectWorkspaceFirst'.tr());
    return;
  }
  final selection = ref.read(ideaskSelectionProvider);
  final folderId = selection is IdeaskFolderSelection
      ? selection.folderId
      : null;

  final choice = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (folderId != null)
            ListTile(
              leading: const Icon(Symbols.add_task),
              title: Text('newTask'.tr()),
              onTap: () => Navigator.of(ctx).pop('task'),
            ),
          ListTile(
            leading: const Icon(Symbols.folder),
            title: Text('newFolder'.tr()),
            onTap: () => Navigator.of(ctx).pop('folder'),
          ),
          ListTile(
            leading: const Icon(Symbols.article),
            title: Text('newPage'.tr()),
            onTap: () => Navigator.of(ctx).pop('page'),
          ),
          ListTile(
            leading: const Icon(Symbols.table_chart),
            title: Text('newCollection'.tr()),
            onTap: () => Navigator.of(ctx).pop('collection'),
          ),
          const SizedBox(height: SolSpace.sm),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  if (choice == 'task') {
    await showTaskEditorSheet(context, ref, folderId: folderId);
    return;
  }

  final name = await showNameInputSheet(
    context,
    title: switch (choice) {
      'folder' => 'newFolder'.tr(),
      'collection' => 'newCollection'.tr(),
      _ => 'newPage'.tr(),
    },
    label: 'name'.tr(),
    confirmLabel: 'create'.tr(),
    icon: switch (choice) {
      'folder' => Symbols.folder,
      'collection' => Symbols.table_chart,
      _ => Symbols.article,
    },
  );
  if (name == null || name.trim().isEmpty) return;

  final actions = ref.read(ideaskActionsProvider);
  try {
    switch (choice) {
      case 'folder':
        await actions.createFolder(name: name.trim(), parentId: folderId);
      case 'collection':
        await actions.createCollection(name: name.trim(), folderId: folderId);
      default:
        final page = await actions.createPage(
          title: name.trim(),
          folderId: folderId,
        );
        if (context.mounted) {
          await context.router.push(DocRoute(pageId: page.id));
        }
    }
  } catch (error) {
    showSnackBar(wattApiErrorMessage(error));
  }
}
