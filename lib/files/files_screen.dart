import 'package:auto_route/auto_route.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/ui/cloud_files.dart';
import 'package:solwatt/ui/page_scaffold.dart';
import 'package:solwatt/workspaces/workspace_actions.dart';

/// Browser mode: folder tree (indexed) vs flat assets (unindexed).
///
/// Unindexed holds logos, board backgrounds, and other decoration files that
/// should not appear in the folder hierarchy (same idea as Island Drive).
enum WorkspaceFileMode { indexed, unindexed }

/// Layout for the current file list.
enum WorkspaceFileViewMode { list, grid }

/// Kind chip: all / folders only / files only (indexed mode).
enum WorkspaceFileKindFilter { all, folders, files }

/// Media kind filter (mime prefix).
enum WorkspaceMediaFilter { all, image, video, audio, document }

enum WorkspaceFileSort { name, size, date }

/// Per-tab browser state (Island-style multi-tab Drive).
class _DriveTab {
  _DriveTab({required this.id, required this.mode});

  final String id;
  final WorkspaceFileMode mode;

  /// Empty = workspace root. Indexed tabs only.
  final List<({String id, String name})> path = [];
  WorkspaceFileViewMode viewMode = WorkspaceFileViewMode.list;
  WorkspaceFileKindFilter kindFilter = WorkspaceFileKindFilter.all;
  WorkspaceMediaFilter mediaFilter = WorkspaceMediaFilter.all;
  WorkspaceFileSort sort = WorkspaceFileSort.name;
  bool sortDesc = false;
  String? query;

  /// Island-style collapsible filter panel (search + chips).
  bool showFilters = true;
  final searchController = TextEditingController();

  bool get isUnindexed => mode == WorkspaceFileMode.unindexed;

  String get parentId => path.isEmpty ? '' : path.last.id;

  String get title {
    if (isUnindexed) return 'Assets';
    if (path.isEmpty) return 'Folders';
    return path.last.name;
  }

  /// Non-default filters that warrant a badge when the panel is collapsed.
  int get activeFilterCount {
    var count = 0;
    if (!isUnindexed && kindFilter != WorkspaceFileKindFilter.all) count++;
    if (mediaFilter != WorkspaceMediaFilter.all) count++;
    if (sort != WorkspaceFileSort.name || sortDesc) count++;
    if (query != null && query!.isNotEmpty) count++;
    return count;
  }

  void dispose() {
    searchController.dispose();
  }
}

/// Workspace-scoped Drive browser with Island-style tabs.
///
/// - Multiple tabs (indexed folders and/or unindexed assets)
/// - Per-tab path, view mode, and filters
/// - Open folder in a new tab
/// - Storage quota from DysonFS workspace billing
///
/// Uploads and folders always send `workspace_id` so storage is charged to the
/// workspace plan (see FileSystem `WORKSPACE_FILES.md`).
@RoutePage()
class FilesPage extends ConsumerStatefulWidget {
  const FilesPage({super.key});

  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage> {
  final List<_DriveTab> _tabs = [];
  String? _activeTabId;

  @override
  void initState() {
    super.initState();
    // Start with one folders tab, like opening Island Drive.
    _createTab(WorkspaceFileMode.indexed);
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.dispose();
    }
    super.dispose();
  }

  _DriveTab? get _activeTab {
    if (_activeTabId == null) return null;
    return _tabs.where((t) => t.id == _activeTabId).firstOrNull;
  }

  int get _activeTabIndex {
    if (_activeTabId == null || _tabs.isEmpty) return 0;
    final index = _tabs.indexWhere((t) => t.id == _activeTabId);
    return index < 0 ? 0 : index;
  }

  /// Parent rebuild after tab state mutates (filters, path, view mode).
  ///
  /// Never dispose [TextEditingController]s or call [setState] from a child
  /// build — that triggers “dirty widget in the wrong build scope”.
  void _notifyTabsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _clearTabSearch(_DriveTab tab) {
    tab.query = null;
    if (tab.searchController.text.isNotEmpty) {
      // Assigning value is safer mid-tree than clear()+parent setState races.
      tab.searchController.value = TextEditingValue.empty;
    }
  }

  void _invalidateDrive() {
    invalidateWorkspaceDrive(ref);
  }

  String _newTabId() => DateTime.now().microsecondsSinceEpoch.toString();

  void _createTab(WorkspaceFileMode mode) {
    final tab = _DriveTab(id: _newTabId(), mode: mode);
    setState(() {
      _tabs.add(tab);
      _activeTabId = tab.id;
    });
  }

  void _openFolderInNewTab(DriveFileEntry folder, _DriveTab from) {
    if (!folder.isFolder || from.isUnindexed) return;
    final existing = _tabs.where((t) {
      if (t.isUnindexed) return false;
      if (t.path.isEmpty) return false;
      return t.path.last.id == folder.id;
    }).firstOrNull;
    if (existing != null) {
      if (_activeTabId != existing.id) {
        setState(() => _activeTabId = existing.id);
      }
      return;
    }

    final tab = _DriveTab(id: _newTabId(), mode: WorkspaceFileMode.indexed);
    // Copy path up to current location, then append the folder.
    tab.path
      ..addAll(from.path)
      ..add((id: folder.id, name: folder.name));
    tab.viewMode = from.viewMode;
    setState(() {
      _tabs.add(tab);
      _activeTabId = tab.id;
    });
  }

  void _selectTab(String id) {
    if (_activeTabId == id) return;
    setState(() => _activeTabId = id);
  }

  void _closeTab(String id) {
    final index = _tabs.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final closing = _tabs[index];
    setState(() {
      _tabs.removeAt(index);
      if (_activeTabId == id) {
        if (_tabs.isEmpty) {
          _activeTabId = null;
        } else {
          final next = index >= _tabs.length ? _tabs.length - 1 : index;
          _activeTabId = _tabs[next].id;
        }
      }
    });
    // Dispose after the tab body element is deactivated (avoids build-scope
    // errors when a TextField still held the controller this frame).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      closing.dispose();
    });
  }

  /// Uses [ReorderableListView.onReorderItem], which already adjusts [newIndex]
  /// for the removed item (no manual `newIndex -= 1`).
  void _reorderTab(int oldIndex, int newIndex) {
    setState(() {
      final tab = _tabs.removeAt(oldIndex);
      _tabs.insert(newIndex, tab);
    });
  }

  void _openFolderInPlace(_DriveTab tab, DriveFileEntry entry) {
    tab.path.add((id: entry.id, name: entry.name));
    _clearTabSearch(tab);
    _notifyTabsChanged();
  }

  void _navigatePath(_DriveTab tab, int keepThroughIndex) {
    // keepThroughIndex == -1 means root.
    if (keepThroughIndex < 0) {
      tab.path.clear();
    } else if (keepThroughIndex < tab.path.length - 1) {
      tab.path.removeRange(keepThroughIndex + 1, tab.path.length);
    } else {
      return;
    }
    _clearTabSearch(tab);
    _notifyTabsChanged();
  }

  Future<void> _uploadFiles(_DriveTab tab) async {
    final workspace = await ref.read(selectedWorkspaceProvider.future);
    if (workspace == null) {
      showSnackBar('Select a workspace first.');
      return;
    }
    if (!mounted) return;

    final files = await uploadLocalCloudFiles(
      ref,
      allowMultiple: true,
      workspaceId: workspace.id,
      parentId: tab.isUnindexed
          ? null
          : (tab.parentId.isEmpty ? null : tab.parentId),
      indexed: !tab.isUnindexed,
    );
    if (files == null || files.isEmpty || !mounted) return;
    _invalidateDrive();
    showSnackBar(
      files.length == 1
          ? 'Uploaded ${files.first.name}.'
          : 'Uploaded ${files.length} files.',
    );
  }

  Future<void> _createFolder(_DriveTab tab) async {
    if (tab.isUnindexed) return;
    final workspace = await ref.read(selectedWorkspaceProvider.future);
    if (workspace == null) {
      showSnackBar('Select a workspace first.');
      return;
    }
    if (!mounted) return;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _NameDialog(
        title: 'New folder',
        label: 'Folder name',
        confirmLabel: 'Create',
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await ref
          .read(wattEngineClientProvider)
          .createCloudFolder(
            name: name.trim(),
            workspaceId: workspace.id,
            parentId: tab.parentId.isEmpty ? null : tab.parentId,
          );
      _invalidateDrive();
      showSnackBar('Folder created.');
    } catch (error) {
      showSnackBar(driveApiErrorMessage(error));
    }
  }

  Future<void> _rename(DriveFileEntry entry) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(
        title: entry.isFolder ? 'Rename folder' : 'Rename file',
        label: 'Name',
        confirmLabel: 'Save',
        initialValue: entry.name,
      ),
    );
    if (name == null || name.trim().isEmpty || name.trim() == entry.name) {
      return;
    }
    try {
      await ref
          .read(wattEngineClientProvider)
          .renameCloudFile(entry.id, name.trim());
      _invalidateDrive();
      showSnackBar('Renamed.');
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  Future<void> _delete(DriveFileEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry.isFolder ? 'Delete folder?' : 'Delete file?'),
        content: Text(
          'Permanently delete “${entry.name.isEmpty ? entry.id : entry.name}”? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(wattEngineClientProvider).deleteCloudFile(entry.id);
      _invalidateDrive();
      showSnackBar('Deleted.');
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  Future<void> _inspect(_DriveTab tab, DriveFileEntry entry) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FileDetailSheet(
        entry: entry,
        unindexed: tab.isUnindexed,
        onRename: () {
          Navigator.pop(context);
          _rename(entry);
        },
        onDelete: () {
          Navigator.pop(context);
          _delete(entry);
        },
        onOpenInNewTab: entry.isFolder && !tab.isUnindexed
            ? () {
                Navigator.pop(context);
                _openFolderInNewTab(entry, tab);
              }
            : null,
      ),
    );
  }

  List<DriveFileEntry> _applyFilters(
    _DriveTab tab,
    List<DriveFileEntry> items,
  ) {
    var visible = items;

    if (tab.query != null && tab.query!.isNotEmpty) {
      final q = tab.query!.toLowerCase();
      visible = visible
          .where((e) => e.name.toLowerCase().contains(q))
          .toList(growable: false);
    }

    if (!tab.isUnindexed) {
      visible = switch (tab.kindFilter) {
        WorkspaceFileKindFilter.all => visible,
        WorkspaceFileKindFilter.folders =>
          visible.where((e) => e.isFolder).toList(growable: false),
        WorkspaceFileKindFilter.files =>
          visible.where((e) => !e.isFolder).toList(growable: false),
      };
    }

    if (tab.mediaFilter != WorkspaceMediaFilter.all) {
      visible = visible
          .where((e) {
            if (e.isFolder) {
              return tab.kindFilter != WorkspaceFileKindFilter.files;
            }
            final mime = e.mimeType.toLowerCase();
            return switch (tab.mediaFilter) {
              WorkspaceMediaFilter.image => mime.startsWith('image/'),
              WorkspaceMediaFilter.video => mime.startsWith('video/'),
              WorkspaceMediaFilter.audio => mime.startsWith('audio/'),
              WorkspaceMediaFilter.document =>
                mime.startsWith('application/') || mime.startsWith('text/'),
              WorkspaceMediaFilter.all => true,
            };
          })
          .toList(growable: false);
    }

    final sorted = [...visible]
      ..sort((a, b) {
        if (!tab.isUnindexed && a.isFolder != b.isFolder) {
          return a.isFolder ? -1 : 1;
        }
        final cmp = switch (tab.sort) {
          WorkspaceFileSort.name => a.name.toLowerCase().compareTo(
            b.name.toLowerCase(),
          ),
          WorkspaceFileSort.size => a.size.compareTo(b.size),
          WorkspaceFileSort.date => a.file.createdAt.compareTo(
            b.file.createdAt,
          ),
        };
        return tab.sortDesc ? -cmp : cmp;
      });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    final usageAsync = ref.watch(workspaceDriveUsageProvider);
    final tab = _activeTab;
    final scheme = Theme.of(context).colorScheme;

    // No page title — shell already labels this destination. Chrome is just
    // tab strip (with actions) → content → edge-snapped status bar.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DriveTabStrip(
          tabs: _tabs,
          activeTabId: _activeTabId,
          onSelectTab: _selectTab,
          onCloseTab: _closeTab,
          onReorderTab: _reorderTab,
          onAddIndexedTab: () => _createTab(WorkspaceFileMode.indexed),
          onAddUnindexedTab: () => _createTab(WorkspaceFileMode.unindexed),
          onRefresh: tab == null ? null : _invalidateDrive,
          onNewFolder: tab == null || tab.isUnindexed || workspace == null
              ? null
              : () => _createFolder(tab),
          onUpload: tab == null || workspace == null
              ? null
              : () => _uploadFiles(tab),
          uploadIsAsset: tab?.isUnindexed == true,
        ),
        Expanded(
          child: ColoredBox(
            color: scheme.surface,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  // IndexedStack keeps each tab body mounted so Riverpod watches
                  // are not disposed mid-rebuild when switching tabs.
                  child: _tabs.isEmpty
                      ? _EmptyTabsState(
                          onOpenIndexed: () =>
                              _createTab(WorkspaceFileMode.indexed),
                          onOpenUnindexed: () =>
                              _createTab(WorkspaceFileMode.unindexed),
                        )
                      : IndexedStack(
                          index: _activeTabIndex,
                          sizing: StackFit.expand,
                          children: [
                            for (final t in _tabs)
                              _TabBrowserBody(
                                key: ValueKey(t.id),
                                tab: t,
                                workspace: workspace,
                                onChanged: _notifyTabsChanged,
                                onInvalidate: _invalidateDrive,
                                onUpload: () => _uploadFiles(t),
                                onNavigatePath: (keepThrough) =>
                                    _navigatePath(t, keepThrough),
                                onOpenFolder: (entry) =>
                                    _openFolderInPlace(t, entry),
                                onOpenFolderInNewTab: (entry) =>
                                    _openFolderInNewTab(entry, t),
                                onInspect: (entry) => _inspect(t, entry),
                                onRename: _rename,
                                onDelete: _delete,
                                applyFilters: (items) =>
                                    _applyFilters(t, items),
                              ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
        // Full-bleed bottom status bar (Island-style, snapped to edges).
        _DriveStorageStatusBar(
          usageAsync: usageAsync,
          onTapDetails: workspace == null
              ? null
              : () => showWorkspaceQuota(context, ref, workspace),
          onRetry: () => ref.invalidate(workspaceDriveUsageProvider),
        ),
      ],
    );
  }
}

// ── Browser-style tab strip ─────────────────────────────────────────────────

class _DriveTabStrip extends StatelessWidget {
  const _DriveTabStrip({
    required this.tabs,
    required this.activeTabId,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onReorderTab,
    required this.onAddIndexedTab,
    required this.onAddUnindexedTab,
    this.onRefresh,
    this.onNewFolder,
    this.onUpload,
    this.uploadIsAsset = false,
  });

  final List<_DriveTab> tabs;
  final String? activeTabId;
  final ValueChanged<String> onSelectTab;
  final ValueChanged<String> onCloseTab;
  final void Function(int oldIndex, int newIndex) onReorderTab;
  final VoidCallback onAddIndexedTab;
  final VoidCallback onAddUnindexedTab;
  final VoidCallback? onRefresh;
  final VoidCallback? onNewFolder;
  final VoidCallback? onUpload;
  final bool uploadIsAsset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = scheme.outlineVariant.withValues(alpha: 0.55);

    Widget toolButton({
      required String tooltip,
      required IconData icon,
      required VoidCallback? onPressed,
    }) {
      return SizedBox(
        width: 36,
        height: 40,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          style: IconButton.styleFrom(
            foregroundColor: scheme.onSurfaceVariant,
            disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.28),
          ),
          icon: Icon(icon),
        ),
      );
    }

    return Material(
      color: scheme.surfaceContainerLow,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: border)),
        ),
        child: SizedBox(
          height: 40,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: tabs.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'No open tabs',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        scrollDirection: Axis.horizontal,
                        itemCount: tabs.length,
                        onReorderItem: onReorderTab,
                        proxyDecorator: (child, index, animation) {
                          return AnimatedBuilder(
                            animation: animation,
                            builder: (context, child) {
                              return Material(
                                elevation: 3,
                                color: scheme.surface,
                                shadowColor: scheme.shadow.withValues(
                                  alpha: 0.25,
                                ),
                                child: child,
                              );
                            },
                            child: child,
                          );
                        },
                        itemBuilder: (context, index) {
                          final tab = tabs[index];
                          final selected = tab.id == activeTabId;
                          return ReorderableDragStartListener(
                            key: ValueKey(tab.id),
                            index: index,
                            child: _DriveTabItem(
                              title: tab.title,
                              icon: tab.isUnindexed
                                  ? Symbols.inventory_2
                                  : Symbols.folder,
                              isSelected: selected,
                              showDivider:
                                  index > 0 &&
                                  tabs[index - 1].id != activeTabId &&
                                  !selected,
                              onTap: () => onSelectTab(tab.id),
                              onClose: () => onCloseTab(tab.id),
                            ),
                          );
                        },
                      ),
              ),
              VerticalDivider(width: 1, thickness: 1, color: border),
              PopupMenuButton<String>(
                tooltip: 'New tab',
                padding: EdgeInsets.zero,
                onSelected: (value) {
                  switch (value) {
                    case 'indexed':
                      onAddIndexedTab();
                    case 'unindexed':
                      onAddUnindexedTab();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'indexed',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Symbols.folder, size: 20),
                      title: Text('Folders'),
                      subtitle: Text('Indexed workspace tree'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'unindexed',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Symbols.inventory_2, size: 20),
                      title: Text('Assets'),
                      subtitle: Text('Logos & backgrounds'),
                    ),
                  ),
                ],
                child: SizedBox(
                  width: 36,
                  height: 40,
                  child: Icon(
                    Symbols.add,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              VerticalDivider(width: 1, thickness: 1, color: border),
              toolButton(
                tooltip: 'Refresh',
                icon: Symbols.refresh,
                onPressed: onRefresh,
              ),
              toolButton(
                tooltip: 'New folder',
                icon: Symbols.create_new_folder,
                onPressed: onNewFolder,
              ),
              toolButton(
                tooltip: uploadIsAsset ? 'Upload asset' : 'Upload',
                icon: Symbols.upload,
                onPressed: onUpload,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single document tab — flat browser chrome, not a floating chip.
class _DriveTabItem extends StatelessWidget {
  const _DriveTabItem({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.showDivider,
    required this.onTap,
    required this.onClose,
  });

  final String title;
  final IconData icon;
  final bool isSelected;
  final bool showDivider;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = scheme.outlineVariant.withValues(alpha: 0.55);

    return Listener(
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons == kMiddleMouseButton) {
          onClose();
        }
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 120, maxWidth: 200),
        child: Material(
          color: isSelected ? scheme.surface : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            hoverColor: scheme.onSurface.withValues(alpha: 0.04),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: showDivider
                      ? BorderSide(color: border)
                      : BorderSide.none,
                  // Selected tab sits on the content surface: hide bar bottom
                  // edge and draw a thin top accent.
                  top: isSelected
                      ? BorderSide(color: scheme.primary, width: 2)
                      : BorderSide.none,
                  right: isSelected
                      ? BorderSide(color: border)
                      : BorderSide.none,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: isSelected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: isSelected
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        iconSize: 15,
                        tooltip: 'Close tab',
                        onPressed: onClose,
                        style: IconButton.styleFrom(
                          foregroundColor: scheme.onSurfaceVariant,
                          hoverColor: scheme.onSurface.withValues(alpha: 0.08),
                        ),
                        icon: const Icon(Symbols.close),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyTabsState extends StatelessWidget {
  const _EmptyTabsState({
    required this.onOpenIndexed,
    required this.onOpenUnindexed,
  });

  final VoidCallback onOpenIndexed;
  final VoidCallback onOpenUnindexed;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Symbols.tab,
      title: 'No tabs open',
      message:
          'Open a Folders tab to browse the workspace tree, or an Assets tab '
          'for unindexed logos and backgrounds.',
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: onOpenIndexed,
            icon: const Icon(Symbols.folder),
            label: const Text('Open folders'),
          ),
          OutlinedButton.icon(
            onPressed: onOpenUnindexed,
            icon: const Icon(Symbols.inventory_2),
            label: const Text('Open assets'),
          ),
        ],
      ),
    );
  }
}

// ── Active tab body ─────────────────────────────────────────────────────────

class _TabBrowserBody extends ConsumerWidget {
  const _TabBrowserBody({
    super.key,
    required this.tab,
    required this.workspace,
    required this.onChanged,
    required this.onInvalidate,
    required this.onUpload,
    required this.onNavigatePath,
    required this.onOpenFolder,
    required this.onOpenFolderInNewTab,
    required this.onInspect,
    required this.onRename,
    required this.onDelete,
    required this.applyFilters,
  });

  final _DriveTab tab;
  final Workspace? workspace;
  final VoidCallback onChanged;
  final VoidCallback onInvalidate;
  final VoidCallback onUpload;

  /// `-1` = root; otherwise keep breadcrumbs through this index.
  final ValueChanged<int> onNavigatePath;
  final ValueChanged<DriveFileEntry> onOpenFolder;
  final ValueChanged<DriveFileEntry> onOpenFolderInNewTab;
  final ValueChanged<DriveFileEntry> onInspect;
  final ValueChanged<DriveFileEntry> onRename;
  final ValueChanged<DriveFileEntry> onDelete;
  final List<DriveFileEntry> Function(List<DriveFileEntry>) applyFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // Safe with IndexedStack: inactive tabs stay mounted, so Riverpod listeners
    // are not torn down mid-frame when switching tabs.
    final children = tab.isUnindexed
        ? ref.watch(workspaceUnindexedFilesProvider)
        : ref.watch(workspaceFolderChildrenProvider(tab.parentId));

    final denseButtonStyle = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 32),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Fixed-height path / title row — same for indexed & unindexed.
                SizedBox(
                  height: 36,
                  child: Row(
                    children: [
                      Expanded(
                        child: tab.isUnindexed
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Unindexed assets',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    TextButton.icon(
                                      style: denseButtonStyle,
                                      onPressed: tab.path.isEmpty
                                          ? null
                                          : () => onNavigatePath(-1),
                                      icon: const Icon(Symbols.home, size: 18),
                                      label: const Text('Root'),
                                    ),
                                    for (
                                      var i = 0;
                                      i < tab.path.length;
                                      i++
                                    ) ...[
                                      Icon(
                                        Symbols.chevron_right,
                                        size: 16,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                      TextButton(
                                        style: denseButtonStyle,
                                        onPressed: i == tab.path.length - 1
                                            ? null
                                            : () => onNavigatePath(i),
                                        child: Text(tab.path[i].name),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: tab.showFilters
                            ? 'Hide filters'
                            : 'Show filters',
                        onPressed: () {
                          tab.showFilters = !tab.showFilters;
                          onChanged();
                        },
                        visualDensity: VisualDensity.compact,
                        iconSize: 20,
                        style: IconButton.styleFrom(
                          foregroundColor:
                              tab.showFilters || tab.activeFilterCount > 0
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        icon: Badge(
                          isLabelVisible:
                              !tab.showFilters && tab.activeFilterCount > 0,
                          smallSize: 8,
                          child: Icon(
                            tab.showFilters
                                ? Symbols.filter_list_off
                                : Symbols.filter_list,
                          ),
                        ),
                      ),
                      SegmentedButton<WorkspaceFileViewMode>(
                        segments: const [
                          ButtonSegment(
                            value: WorkspaceFileViewMode.list,
                            icon: Icon(Symbols.list, size: 18),
                            tooltip: 'List view',
                          ),
                          ButtonSegment(
                            value: WorkspaceFileViewMode.grid,
                            icon: Icon(Symbols.grid_view, size: 18),
                            tooltip: 'Grid view',
                          ),
                        ],
                        selected: {tab.viewMode},
                        onSelectionChanged: (next) {
                          tab.viewMode = next.first;
                          onChanged();
                        },
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
                // Island-style collapsible filter panel (search + chips).
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 220),
                  sizeCurve: Curves.easeInOutCubic,
                  firstCurve: Curves.easeOut,
                  secondCurve: Curves.easeIn,
                  crossFadeState: tab.showFilters
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  alignment: Alignment.topCenter,
                  firstChild: Column(
                    key: ValueKey('filters-visible-${tab.id}'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      TextField(
                        // Remount when folder depth changes so we never fight
                        // a live TextEditingController mid-rebuild.
                        key: ValueKey('search-${tab.id}-${tab.path.length}'),
                        controller: tab.searchController,
                        decoration: InputDecoration(
                          hintText: tab.isUnindexed
                              ? 'Filter assets'
                              : 'Filter in this folder',
                          prefixIcon: const Icon(Symbols.search),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          suffixIcon: tab.query == null || tab.query!.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Symbols.close, size: 18),
                                  onPressed: () {
                                    tab.query = null;
                                    tab.searchController.value =
                                        TextEditingValue.empty;
                                    onChanged();
                                  },
                                ),
                        ),
                        onChanged: (value) {
                          tab.query = value.trim().isEmpty
                              ? null
                              : value.trim();
                          onChanged();
                        },
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (!tab.isUnindexed)
                            _FilterMenuButton<WorkspaceFileKindFilter>(
                              icon: Symbols.category,
                              label: switch (tab.kindFilter) {
                                WorkspaceFileKindFilter.all => 'All',
                                WorkspaceFileKindFilter.folders => 'Folders',
                                WorkspaceFileKindFilter.files => 'Files',
                              },
                              active:
                                  tab.kindFilter != WorkspaceFileKindFilter.all,
                              items: const [
                                (WorkspaceFileKindFilter.all, 'All'),
                                (WorkspaceFileKindFilter.folders, 'Folders'),
                                (WorkspaceFileKindFilter.files, 'Files'),
                              ],
                              onSelected: (v) {
                                tab.kindFilter = v;
                                onChanged();
                              },
                            ),
                          _FilterMenuButton<WorkspaceMediaFilter>(
                            icon: Symbols.perm_media,
                            label: switch (tab.mediaFilter) {
                              WorkspaceMediaFilter.all => 'Type',
                              WorkspaceMediaFilter.image => 'Images',
                              WorkspaceMediaFilter.video => 'Videos',
                              WorkspaceMediaFilter.audio => 'Audio',
                              WorkspaceMediaFilter.document => 'Documents',
                            },
                            active: tab.mediaFilter != WorkspaceMediaFilter.all,
                            items: const [
                              (WorkspaceMediaFilter.all, 'All types'),
                              (WorkspaceMediaFilter.image, 'Images'),
                              (WorkspaceMediaFilter.video, 'Videos'),
                              (WorkspaceMediaFilter.audio, 'Audio'),
                              (WorkspaceMediaFilter.document, 'Documents'),
                            ],
                            onSelected: (v) {
                              tab.mediaFilter = v;
                              onChanged();
                            },
                          ),
                          _FilterMenuButton<WorkspaceFileSort>(
                            icon: Symbols.sort,
                            label: switch (tab.sort) {
                              WorkspaceFileSort.name => 'Name',
                              WorkspaceFileSort.size => 'Size',
                              WorkspaceFileSort.date => 'Date',
                            },
                            active:
                                tab.sort != WorkspaceFileSort.name ||
                                tab.sortDesc,
                            items: const [
                              (WorkspaceFileSort.name, 'Name'),
                              (WorkspaceFileSort.size, 'Size'),
                              (WorkspaceFileSort.date, 'Date'),
                            ],
                            onSelected: (v) {
                              if (tab.sort == v) {
                                tab.sortDesc = !tab.sortDesc;
                              } else {
                                tab.sort = v;
                                tab.sortDesc = v == WorkspaceFileSort.date;
                              }
                              onChanged();
                            },
                          ),
                          ActionChip(
                            avatar: Icon(
                              tab.sortDesc
                                  ? Symbols.arrow_downward
                                  : Symbols.arrow_upward,
                              size: 16,
                            ),
                            label: Text(tab.sortDesc ? 'Desc' : 'Asc'),
                            onPressed: () {
                              tab.sortDesc = !tab.sortDesc;
                              onChanged();
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ],
                  ),
                  secondChild: const SizedBox(
                    key: ValueKey('filters-hidden'),
                    width: double.infinity,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          // Offstage inactive tabs still build (for state) but skip paint cost
          // when many tabs are open. IndexedStack already hides non-active.
          child: children.when(
            loading: () => const PageLoading(),
            error: (error, _) => PageError(
              message: driveApiErrorMessage(error),
              onRetry: onInvalidate,
            ),
            data: (items) {
              final sorted = applyFilters(items);

              if (workspace == null) {
                return const EmptyState(
                  icon: Symbols.folder_off,
                  title: 'No workspace selected',
                  message: 'Choose a workspace to browse its files.',
                );
              }

              if (sorted.isEmpty) {
                return EmptyState(
                  icon: tab.isUnindexed
                      ? Symbols.inventory_2
                      : Symbols.folder_open,
                  title: tab.isUnindexed
                      ? 'No unindexed assets yet'
                      : tab.path.isEmpty
                      ? 'No workspace files yet'
                      : 'This folder is empty',
                  message: tab.isUnindexed
                      ? 'Upload logos, board icons, or backgrounds here. '
                            'They stay out of the folder tree.'
                      : 'Upload files or create a folder. Storage uses the '
                            'workspace plan quota, not your personal Drive.',
                  action: FilledButton.icon(
                    onPressed: onUpload,
                    icon: const Icon(Symbols.upload),
                    label: Text(
                      tab.isUnindexed ? 'Upload asset' : 'Upload files',
                    ),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async => onInvalidate(),
                child: tab.viewMode == WorkspaceFileViewMode.list
                    ? ListView.separated(
                        itemCount: sorted.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = sorted[index];
                          return _FileListTile(
                            entry: entry,
                            unindexed: tab.isUnindexed,
                            onOpen: () {
                              if (!tab.isUnindexed && entry.isFolder) {
                                onOpenFolder(entry);
                              } else {
                                onInspect(entry);
                              }
                            },
                            onOpenInNewTab: !tab.isUnindexed && entry.isFolder
                                ? () => onOpenFolderInNewTab(entry)
                                : null,
                            onRename: () => onRename(entry),
                            onDelete: () => onDelete(entry),
                            onInspect: () => onInspect(entry),
                          );
                        },
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.only(bottom: 8),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 200,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.88,
                            ),
                        itemCount: sorted.length,
                        itemBuilder: (context, index) {
                          final entry = sorted[index];
                          return _FileGridTile(
                            entry: entry,
                            unindexed: tab.isUnindexed,
                            onOpen: () {
                              if (!tab.isUnindexed && entry.isFolder) {
                                onOpenFolder(entry);
                              } else {
                                onInspect(entry);
                              }
                            },
                            onOpenInNewTab: !tab.isUnindexed && entry.isFolder
                                ? () => onOpenFolderInNewTab(entry)
                                : null,
                            onRename: () => onRename(entry),
                            onDelete: () => onDelete(entry),
                            onInspect: () => onInspect(entry),
                          );
                        },
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Shared widgets ──────────────────────────────────────────────────────────

/// Compact bottom storage strip — full-bleed, mirrors Island status bar.
class _DriveStorageStatusBar extends StatelessWidget {
  const _DriveStorageStatusBar({
    required this.usageAsync,
    this.onTapDetails,
    this.onRetry,
  });

  final AsyncValue<WorkspaceDriveUsage?> usageAsync;
  final VoidCallback? onTapDetails;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final border = scheme.outlineVariant.withValues(alpha: 0.55);

    return Material(
      color: scheme.surfaceContainerLow,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: border)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 2, 8, 2 + bottomInset),
          child: usageAsync.when(
            loading: () => const SizedBox(
              height: 36,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(minHeight: 4),
                ),
              ),
            ),
            error: (error, _) => Row(
              children: [
                Icon(Symbols.error, size: 18, color: scheme.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Storage unavailable',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
                ),
                if (onRetry != null)
                  IconButton(
                    onPressed: onRetry,
                    tooltip: 'Retry',
                    icon: const Icon(Symbols.refresh, size: 20),
                  ),
              ],
            ),
            data: (usage) {
              if (usage == null) {
                return SizedBox(
                  height: 36,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Select a workspace to see storage',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }

              final ratio = usage.usageRatio;
              final fileLabel = usage.totalFileCount == 1
                  ? '1 file'
                  : '${usage.totalFileCount} files';

              return LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 520;
                  return Row(
                    children: [
                      Icon(Symbols.storage, size: 18, color: scheme.primary),
                      const SizedBox(width: 12),
                      if (!isCompact) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: SizedBox(
                            width: 120,
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            fileLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: text.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ] else
                        const Spacer(),
                      Text(
                        '${formatByteSize(usage.usedBytes)} / '
                        '${formatByteSize(usage.totalBytes)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium,
                      ),
                      if (!isCompact) ...[
                        const SizedBox(width: 12),
                        Text(
                          '${(ratio * 100).toStringAsFixed(1)}%',
                          style: text.bodySmall,
                        ),
                      ],
                      IconButton(
                        onPressed: onTapDetails,
                        tooltip: 'Plan & quotas',
                        icon: const Icon(Symbols.bar_chart),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FilterMenuButton<T> extends StatelessWidget {
  const _FilterMenuButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.items,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final bool active;
  final List<(T, String)> items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<T>(
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem(value: item.$1, child: Text(item.$2)),
      ],
      child: Material(
        color: active ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: active
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: active
                      ? scheme.onSecondaryContainer
                      : scheme.onSurface,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Symbols.expand_more,
                size: 16,
                color: active
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileListTile extends StatelessWidget {
  const _FileListTile({
    required this.entry,
    required this.unindexed,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.onInspect,
    this.onOpenInNewTab,
  });

  final DriveFileEntry entry;
  final bool unindexed;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onInspect;
  final VoidCallback? onOpenInNewTab;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = entry.isFolder
        ? 'Folder'
        : [
            formatByteSize(entry.size),
            if (unindexed) 'Asset',
            if (entry.mimeType.isNotEmpty) entry.mimeType,
          ].join(' · ');

    return ListTile(
      leading: CloudFileAvatar(
        file: entry.file,
        fallbackIcon: entry.isFolder
            ? Symbols.folder
            : unindexed
            ? Symbols.inventory_2
            : Symbols.description,
        size: 44,
      ),
      title: Text(
        entry.name.isEmpty ? 'Untitled' : entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'open':
              onOpen();
            case 'newTab':
              onOpenInNewTab?.call();
            case 'inspect':
              onInspect();
            case 'rename':
              onRename();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'open',
            child: Text(entry.isFolder && !unindexed ? 'Open' : 'View'),
          ),
          if (onOpenInNewTab != null)
            const PopupMenuItem(
              value: 'newTab',
              child: Text('Open in new tab'),
            ),
          const PopupMenuItem(value: 'inspect', child: Text('Details')),
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: onOpen,
      onLongPress: onInspect,
    );
  }
}

class _FileGridTile extends StatelessWidget {
  const _FileGridTile({
    required this.entry,
    required this.unindexed,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.onInspect,
    this.onOpenInNewTab,
  });

  final DriveFileEntry entry;
  final bool unindexed;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onInspect;
  final VoidCallback? onOpenInNewTab;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isImage = entry.mimeType.startsWith('image/');
    final url = cloudFileDisplayUrl(entry.file);

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onInspect,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (isImage && !entry.isFolder)
                    Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(
                          Symbols.broken_image,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(
                        entry.isFolder
                            ? Symbols.folder
                            : unindexed
                            ? Symbols.inventory_2
                            : Symbols.description,
                        size: 40,
                        color: scheme.primary,
                      ),
                    ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: scheme.surface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                      child: PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onSelected: (value) {
                          switch (value) {
                            case 'open':
                              onOpen();
                            case 'newTab':
                              onOpenInNewTab?.call();
                            case 'inspect':
                              onInspect();
                            case 'rename':
                              onRename();
                            case 'delete':
                              onDelete();
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'open',
                            child: Text(
                              entry.isFolder && !unindexed ? 'Open' : 'View',
                            ),
                          ),
                          if (onOpenInNewTab != null)
                            const PopupMenuItem(
                              value: 'newTab',
                              child: Text('Open in new tab'),
                            ),
                          const PopupMenuItem(
                            value: 'inspect',
                            child: Text('Details'),
                          ),
                          const PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                        icon: const Icon(Symbols.more_vert, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name.isEmpty ? 'Untitled' : entry.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.isFolder ? 'Folder' : formatByteSize(entry.size),
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileDetailSheet extends StatelessWidget {
  const _FileDetailSheet({
    required this.entry,
    required this.unindexed,
    required this.onRename,
    required this.onDelete,
    this.onOpenInNewTab,
  });

  final DriveFileEntry entry;
  final bool unindexed;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback? onOpenInNewTab;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isImage = entry.mimeType.startsWith('image/');
    final url = cloudFileDisplayUrl(entry.file);

    return SheetScaffold(
      titleText: entry.name.isEmpty ? 'File details' : entry.name,
      heightFactor: 0.65,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          if (isImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: entry.file.ratio ?? 16 / 9,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: const Center(child: Icon(Symbols.broken_image)),
                  ),
                ),
              ),
            )
          else
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(
                  entry.isFolder
                      ? Symbols.folder
                      : unindexed
                      ? Symbols.inventory_2
                      : Symbols.description,
                  size: 48,
                  color: scheme.primary,
                ),
              ),
            ),
          const SizedBox(height: 16),
          _DetailRow(label: 'ID', value: entry.id, copyable: true),
          _DetailRow(
            label: 'Type',
            value: entry.isFolder
                ? 'Folder'
                : unindexed
                ? '${entry.mimeType} · unindexed'
                : entry.mimeType,
          ),
          if (!entry.isFolder)
            _DetailRow(label: 'Size', value: formatByteSize(entry.size)),
          if (entry.workspaceId != null)
            _DetailRow(label: 'Workspace', value: entry.workspaceId!),
          _DetailRow(
            label: 'Indexed',
            value: entry.file.indexed ? 'Yes' : 'No',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onOpenInNewTab != null)
                FilledButton.tonalIcon(
                  onPressed: onOpenInNewTab,
                  icon: const Icon(Symbols.tab, size: 18),
                  label: const Text('Open in new tab'),
                ),
              if (!entry.isFolder)
                FilledButton.tonalIcon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    showSnackBar('Link copied.');
                  },
                  icon: const Icon(Symbols.link, size: 18),
                  label: const Text('Copy link'),
                ),
              OutlinedButton.icon(
                onPressed: onRename,
                icon: const Icon(Symbols.edit, size: 18),
                label: const Text('Rename'),
              ),
              OutlinedButton.icon(
                onPressed: onDelete,
                icon: Icon(Symbols.delete, size: 18, color: scheme.error),
                label: Text('Delete', style: TextStyle(color: scheme.error)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            unindexed
                ? 'Unindexed workspace assets are ideal for logos and '
                      'backgrounds. They still bill to the workspace plan.'
                : 'Workspace-owned files retain the uploader account for audit '
                      'while storage is billed to the workspace plan.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: SelectableText(value, style: text.bodyMedium)),
          if (copyable)
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Symbols.content_copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                showSnackBar('Copied.');
              },
            ),
        ],
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.confirmLabel,
    this.initialValue,
  });

  final String title;
  final String label;
  final String confirmLabel;
  final String? initialValue;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
