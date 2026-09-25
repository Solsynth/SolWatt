import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/ui/alert.dart';
import 'package:solwatt/ui/cloud_files.dart';
import 'package:solwatt/ui/name_sheet.dart';
import 'package:solwatt/ui/page_scaffold.dart';
import 'package:solwatt/workspaces/workspace_actions.dart';

enum WorkspaceFileMode { indexed, unindexed }

enum WorkspaceFileViewMode { list, grid }

enum WorkspaceFileKindFilter { all, folders, files }

enum WorkspaceMediaFilter { all, image, video, audio, document }

enum WorkspaceFileSort { name, size, date }

class _DriveTab {
  _DriveTab({required this.id, required this.mode, this.file});

  final String id;
  final WorkspaceFileMode mode;
  final DriveFileEntry? file;

  final List<({String id, String name})> path = [];
  WorkspaceFileViewMode viewMode = WorkspaceFileViewMode.list;
  WorkspaceFileKindFilter kindFilter = WorkspaceFileKindFilter.all;
  WorkspaceMediaFilter mediaFilter = WorkspaceMediaFilter.all;
  WorkspaceFileSort sort = WorkspaceFileSort.name;
  bool sortDesc = false;
  String? query;

  bool showFilters = true;
  final searchController = TextEditingController();

  bool get isUnindexed => mode == WorkspaceFileMode.unindexed;

  bool get isFileDetail => file != null;

  String get parentId => path.isEmpty ? '' : path.last.id;

  String get title {
    if (file != null) {
      return file!.name.isEmpty ? 'fileDetails'.tr() : file!.name;
    }
    if (isUnindexed) return 'assets'.tr();
    if (path.isEmpty) return 'folders'.tr();
    return path.last.name;
  }

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

  void _notifyTabsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _clearTabSearch(_DriveTab tab) {
    tab.query = null;
    if (tab.searchController.text.isNotEmpty) {
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
    tab.path
      ..addAll(from.path)
      ..add((id: folder.id, name: folder.name));
    tab.viewMode = from.viewMode;
    setState(() {
      _tabs.add(tab);
      _activeTabId = tab.id;
    });
  }

  void _openFileDetailTab(DriveFileEntry entry, _DriveTab from) {
    if (entry.isFolder) return;
    final existing = _tabs.where((tab) => tab.file?.id == entry.id).firstOrNull;
    if (existing != null) {
      _selectTab(existing.id);
      return;
    }

    final tab = _DriveTab(id: _newTabId(), mode: from.mode, file: entry);
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      closing.dispose();
    });
  }

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
      showSnackBar('selectAWorkspaceFirst'.tr());
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
          ? 'uploadedFile'.tr(namedArgs: {'name': files.first.name})
          : 'uploadedCountFiles'.tr(args: [files.length.toString()]),
    );
  }

  Future<void> _createFolder(_DriveTab tab) async {
    if (tab.isUnindexed) return;
    final workspace = await ref.read(selectedWorkspaceProvider.future);
    if (workspace == null) {
      showSnackBar('selectAWorkspaceFirst'.tr());
      return;
    }
    if (!mounted) return;
    final name = await showNameInputSheet(
      context,
      title: 'newFolder'.tr(),
      label: 'folderName'.tr(),
      confirmLabel: 'create'.tr(),
      icon: Symbols.folder,
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
      showSnackBar('folderCreated'.tr());
    } catch (error) {
      showSnackBar(driveApiErrorMessage(error));
    }
  }

  Future<void> _rename(DriveFileEntry entry) async {
    final name = await showNameInputSheet(
      context,
      title: entry.isFolder ? 'renameFolder'.tr() : 'renameFile'.tr(),
      label: 'name'.tr(),
      confirmLabel: 'save'.tr(),
      initialValue: entry.name,
      icon: entry.isFolder ? Symbols.folder : Symbols.draft,
    );
    if (name == null || name.trim().isEmpty || name.trim() == entry.name) {
      return;
    }
    try {
      await ref
          .read(wattEngineClientProvider)
          .renameCloudFile(entry.id, name.trim());
      _invalidateDrive();
      showSnackBar('renamed'.tr());
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  Future<void> _delete(DriveFileEntry entry) async {
    final confirmed = await showConfirmAlert(
      'permanentlyDelete'.tr(
        namedArgs: {'name': entry.name.isEmpty ? entry.id : entry.name},
      ),
      entry.isFolder ? 'deleteFolder'.tr() : 'deleteFile'.tr(),
      icon: Symbols.delete,
      isDanger: true,
      confirmLabel: 'delete'.tr(),
    );
    if (!confirmed) return;
    try {
      await ref.read(wattEngineClientProvider).deleteCloudFile(entry.id);
      _invalidateDrive();
      showSnackBar('deleted'.tr());
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
          onNewFolder:
              tab == null ||
                  tab.isFileDetail ||
                  tab.isUnindexed ||
                  workspace == null
              ? null
              : () => _createFolder(tab),
          onUpload: tab == null || tab.isFileDetail || workspace == null
              ? null
              : () => _uploadFiles(tab),
          uploadIsAsset: tab?.isUnindexed == true,
        ),
        Expanded(
          child: ColoredBox(
            color: scheme.surface,
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: tab?.isFileDetail == true ? double.infinity : null,
                height: tab?.isFileDetail == true ? double.infinity : null,
                child: ConstrainedBox(
                  constraints: tab?.isFileDetail == true
                      ? const BoxConstraints()
                      : const BoxConstraints(maxWidth: 1100),
                  child: Padding(
                    padding: tab?.isFileDetail == true
                        ? EdgeInsets.zero
                        : const EdgeInsets.fromLTRB(24, 12, 24, 0),
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
                                if (t.isFileDetail)
                                  _FileDetailTab(
                                    key: ValueKey(t.id),
                                    entry: t.file!,
                                    unindexed: t.isUnindexed,
                                    onRename: () => _rename(t.file!),
                                    onDelete: () => _delete(t.file!),
                                  )
                                else
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
                                    onOpenFile: (entry) =>
                                        _openFileDetailTab(entry, t),
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
        ),
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
                            'noOpenTabs'.tr(),
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
                              icon: tab.isFileDetail
                                  ? Symbols.description
                                  : tab.isUnindexed
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
                tooltip: 'newTab'.tr(),
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
                  PopupMenuItem(
                    value: 'indexed',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Symbols.folder, size: 20),
                      title: Text('folders'.tr()),
                      subtitle: Text('indexedWorkspaceTree'.tr()),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'unindexed',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Symbols.inventory_2, size: 20),
                      title: Text('assets'.tr()),
                      subtitle: Text('logosAndBackgrounds'.tr()),
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
                tooltip: 'refresh'.tr(),
                icon: Symbols.refresh,
                onPressed: onRefresh,
              ),
              toolButton(
                tooltip: 'newFolder'.tr(),
                icon: Symbols.create_new_folder,
                onPressed: onNewFolder,
              ),
              toolButton(
                tooltip: uploadIsAsset ? 'uploadAsset'.tr() : 'upload'.tr(),
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
                        tooltip: 'closeTab'.tr(),
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
      title: 'noTabsOpen'.tr(),
      message: 'openFoldersDescription'.tr(),
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: onOpenIndexed,
            icon: const Icon(Symbols.folder),
            label: Text('openFoldersTab'.tr()),
          ),
          OutlinedButton.icon(
            onPressed: onOpenUnindexed,
            icon: const Icon(Symbols.inventory_2),
            label: Text('openAssetsTab'.tr()),
          ),
        ],
      ),
    );
  }
}

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
    required this.onOpenFile,
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
  final ValueChanged<int> onNavigatePath;
  final ValueChanged<DriveFileEntry> onOpenFolder;
  final ValueChanged<DriveFileEntry> onOpenFolderInNewTab;
  final ValueChanged<DriveFileEntry> onOpenFile;
  final ValueChanged<DriveFileEntry> onInspect;
  final ValueChanged<DriveFileEntry> onRename;
  final ValueChanged<DriveFileEntry> onDelete;
  final List<DriveFileEntry> Function(List<DriveFileEntry>) applyFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
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
                SizedBox(
                  height: 36,
                  child: Row(
                    children: [
                      Expanded(
                        child: tab.isUnindexed
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'unindexedAssets'.tr(),
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
                                      label: Text('root'.tr()),
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
                            ? 'hideFilters'.tr()
                            : 'showFilters'.tr(),
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
                            tooltip: 'listView',
                          ),
                          ButtonSegment(
                            value: WorkspaceFileViewMode.grid,
                            icon: Icon(Symbols.grid_view, size: 18),
                            tooltip: 'gridView',
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
                        key: ValueKey('search-${tab.id}-${tab.path.length}'),
                        controller: tab.searchController,
                        decoration: InputDecoration(
                          hintText: tab.isUnindexed
                              ? 'filterAssets'.tr()
                              : 'filterInThisFolder'.tr(),
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
                                WorkspaceFileKindFilter.all => 'all'.tr(),
                                WorkspaceFileKindFilter.folders =>
                                  'folders'.tr(),
                                WorkspaceFileKindFilter.files => 'files'.tr(),
                              },
                              active:
                                  tab.kindFilter != WorkspaceFileKindFilter.all,
                              items: [
                                (WorkspaceFileKindFilter.all, 'all'.tr()),
                                (
                                  WorkspaceFileKindFilter.folders,
                                  'folders'.tr(),
                                ),
                                (WorkspaceFileKindFilter.files, 'files'.tr()),
                              ],
                              onSelected: (v) {
                                tab.kindFilter = v;
                                onChanged();
                              },
                            ),
                          _FilterMenuButton<WorkspaceMediaFilter>(
                            icon: Symbols.perm_media,
                            label: switch (tab.mediaFilter) {
                              WorkspaceMediaFilter.all => 'type'.tr(),
                              WorkspaceMediaFilter.image => 'images'.tr(),
                              WorkspaceMediaFilter.video => 'videos'.tr(),
                              WorkspaceMediaFilter.audio => 'audio'.tr(),
                              WorkspaceMediaFilter.document => 'documents'.tr(),
                            },
                            active: tab.mediaFilter != WorkspaceMediaFilter.all,
                            items: [
                              (WorkspaceMediaFilter.all, 'allTypes'.tr()),
                              (WorkspaceMediaFilter.image, 'images'.tr()),
                              (WorkspaceMediaFilter.video, 'videos'.tr()),
                              (WorkspaceMediaFilter.audio, 'audio'.tr()),
                              (WorkspaceMediaFilter.document, 'documents'.tr()),
                            ],
                            onSelected: (v) {
                              tab.mediaFilter = v;
                              onChanged();
                            },
                          ),
                          _FilterMenuButton<WorkspaceFileSort>(
                            icon: Symbols.sort,
                            label: switch (tab.sort) {
                              WorkspaceFileSort.name => 'name'.tr(),
                              WorkspaceFileSort.size => 'size'.tr(),
                              WorkspaceFileSort.date => 'date'.tr(),
                            },
                            active:
                                tab.sort != WorkspaceFileSort.name ||
                                tab.sortDesc,
                            items: [
                              (WorkspaceFileSort.name, 'name'.tr()),
                              (WorkspaceFileSort.size, 'size'.tr()),
                              (WorkspaceFileSort.date, 'date'.tr()),
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
                            label: Text(
                              tab.sortDesc ? 'desc'.tr() : 'asc'.tr(),
                            ),
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
          child: children.when(
            loading: () => const PageLoading(),
            error: (error, _) => PageError(
              message: driveApiErrorMessage(error),
              onRetry: onInvalidate,
            ),
            data: (items) {
              final sorted = applyFilters(items);

              if (workspace == null) {
                return EmptyState(
                  icon: Symbols.folder_off,
                  title: 'noWorkspaceSelected'.tr(),
                  message: 'chooseWorkspaceToBrowse'.tr(),
                );
              }

              if (sorted.isEmpty) {
                return EmptyState(
                  icon: tab.isUnindexed
                      ? Symbols.inventory_2
                      : Symbols.folder_open,
                  title: tab.isUnindexed
                      ? 'noUnindexedAssetsYet'.tr()
                      : tab.path.isEmpty
                      ? 'noWorkspaceFilesYet'.tr()
                      : 'folderIsEmpty'.tr(),
                  message: tab.isUnindexed
                      ? 'uploadLogosAndBackgrounds'.tr()
                      : 'uploadFilesOrCreateFolder'.tr(),
                  action: FilledButton.icon(
                    onPressed: onUpload,
                    icon: const Icon(Symbols.upload),
                    label: Text(
                      tab.isUnindexed ? 'uploadAsset'.tr() : 'uploadFiles'.tr(),
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
                                onOpenFile(entry);
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
                                onOpenFile(entry);
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
                    'storageUnavailable'.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
                ),
                if (onRetry != null)
                  IconButton(
                    onPressed: onRetry,
                    tooltip: 'retry'.tr(),
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
                      'selectWorkspaceToSeeStorage'.tr(),
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
                        tooltip: 'planAndQuotas'.tr(),
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
        ? 'folder'.tr()
        : [
            formatByteSize(entry.size),
            if (unindexed) 'asset'.tr(),
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
        entry.name.isEmpty ? 'untitled'.tr() : entry.name,
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
            child: Text(
              entry.isFolder && !unindexed ? 'open'.tr() : 'view'.tr(),
            ),
          ),
          if (onOpenInNewTab != null)
            const PopupMenuItem(
              value: 'newTab',
              child: Text('Open in new tab'),
            ),
          PopupMenuItem(value: 'inspect', child: Text('details'.tr())),
          PopupMenuItem(value: 'rename', child: Text('rename'.tr())),
          PopupMenuItem(value: 'delete', child: Text('delete'.tr())),
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
                              entry.isFolder && !unindexed
                                  ? 'open'.tr()
                                  : 'view'.tr(),
                            ),
                          ),
                          if (onOpenInNewTab != null)
                            const PopupMenuItem(
                              value: 'newTab',
                              child: Text('Open in new tab'),
                            ),
                          PopupMenuItem(
                            value: 'inspect',
                            child: Text('details'.tr()),
                          ),
                          PopupMenuItem(
                            value: 'rename',
                            child: Text('rename'.tr()),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('delete'.tr()),
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
                    entry.name.isEmpty ? 'untitled'.tr() : entry.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.isFolder ? 'folder'.tr() : formatByteSize(entry.size),
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

/// A persistent file viewer, modeled after Island's dedicated file detail
/// screen, but kept inside the workspace Drive tab strip.
class _FileDetailTab extends StatefulWidget {
  const _FileDetailTab({
    super.key,
    required this.entry,
    required this.unindexed,
    required this.onRename,
    required this.onDelete,
  });

  final DriveFileEntry entry;
  final bool unindexed;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  State<_FileDetailTab> createState() => _FileDetailTabState();
}

class _FileDetailTabState extends State<_FileDetailTab> {
  final _showSidebar = ValueNotifier(false);

  @override
  void dispose() {
    _showSidebar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entry = widget.entry;
    final url = cloudFileDisplayUrl(entry.file);
    final isImage = entry.mimeType.startsWith('image/');
    final isMedia =
        isImage ||
        entry.mimeType.startsWith('video/') ||
        entry.mimeType.startsWith('audio/');

    Future<void> openExternally() async {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) showSnackBar('Could not open this file.');
    }

    final preview = isImage
        ? InteractiveViewer(
            minScale: 0.8,
            maxScale: 8,
            boundaryMargin: const EdgeInsets.all(96),
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _FilePreviewPlaceholder(
                entry: entry,
                unindexed: widget.unindexed,
              ),
            ),
          )
        : _FilePreviewPlaceholder(entry: entry, unindexed: widget.unindexed);

    return ResponsiveSidebar(
      showSidebar: _showSidebar,
      sidebarWidth: 360,
      minWideSidebarWidth: 320,
      maxWideSidebarWidth: 480,
      sidebarBackgroundColor: scheme.surfaceContainerLow,
      drawerBuilder: (_) => SafeArea(
        child: _FileDetailInspector(
          entry: entry,
          unindexed: widget.unindexed,
          url: url,
          onClose: () => _showSidebar.value = false,
          onRename: widget.onRename,
          onDelete: widget.onDelete,
        ),
      ),
      sidebarContent: _FileDetailInspector(
        entry: entry,
        unindexed: widget.unindexed,
        url: url,
        onClose: () => _showSidebar.value = false,
        onRename: widget.onRename,
        onDelete: widget.onDelete,
      ),
      mainContent: Column(
        children: [
          Material(
            color: isMedia ? Colors.black : scheme.surfaceContainerLow,
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      entry.name.isEmpty ? 'fileDetails'.tr() : entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: isMedia ? Colors.white : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: isMedia ? 'view'.tr() : 'open'.tr(),
                    onPressed: openExternally,
                    color: isMedia ? Colors.white : null,
                    icon: Icon(
                      isMedia ? Symbols.open_in_new : Symbols.download,
                    ),
                  ),
                  IconButton(
                    tooltip: 'details'.tr(),
                    onPressed: () => _showSidebar.value = !_showSidebar.value,
                    color: isMedia ? Colors.white : null,
                    icon: const Icon(Symbols.info),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: ColoredBox(
                color: isMedia ? Colors.black : scheme.surfaceContainerHighest,
                child: preview,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileDetailInspector extends StatelessWidget {
  const _FileDetailInspector({
    required this.entry,
    required this.unindexed,
    required this.url,
    required this.onClose,
    required this.onRename,
    required this.onDelete,
  });

  final DriveFileEntry entry;
  final bool unindexed;
  final String url;
  final VoidCallback onClose;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  'fileDetails'.tr(),
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'close'.tr(),
                onPressed: onClose,
                icon: const Icon(Symbols.close),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              _DetailRow(label: 'id'.tr(), value: entry.id, copyable: true),
              _DetailRow(
                label: 'type'.tr(),
                value: unindexed
                    ? '${entry.mimeType} · unindexed'
                    : entry.mimeType,
              ),
              _DetailRow(label: 'size'.tr(), value: formatByteSize(entry.size)),
              if (entry.workspaceId != null)
                _DetailRow(label: 'workspace'.tr(), value: entry.workspaceId!),
              _DetailRow(
                label: 'indexed'.tr(),
                value: entry.file.indexed ? 'yes'.tr() : 'no'.tr(),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url));
                  showSnackBar('linkCopied'.tr());
                },
                icon: const Icon(Symbols.link, size: 18),
                label: Text('copyLink'.tr()),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onRename,
                icon: const Icon(Symbols.edit, size: 18),
                label: Text('rename'.tr()),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onDelete,
                icon: Icon(Symbols.delete, size: 18, color: scheme.error),
                label: Text(
                  'delete'.tr(),
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilePreviewPlaceholder extends StatelessWidget {
  const _FilePreviewPlaceholder({required this.entry, required this.unindexed});

  final DriveFileEntry entry;
  final bool unindexed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            entry.isFolder
                ? Symbols.folder
                : unindexed
                ? Symbols.inventory_2
                : Symbols.description,
            size: 72,
            color: scheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            entry.mimeType.isEmpty ? 'fileDetails'.tr() : entry.mimeType,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
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
      titleText: entry.name.isEmpty ? 'fileDetails'.tr() : entry.name,
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
          _DetailRow(label: 'id'.tr(), value: entry.id, copyable: true),
          _DetailRow(
            label: 'type'.tr(),
            value: entry.isFolder
                ? 'folder'.tr()
                : unindexed
                ? '${entry.mimeType} · unindexed'
                : entry.mimeType,
          ),
          if (!entry.isFolder)
            _DetailRow(label: 'size'.tr(), value: formatByteSize(entry.size)),
          if (entry.workspaceId != null)
            _DetailRow(label: 'workspace'.tr(), value: entry.workspaceId!),
          _DetailRow(
            label: 'indexed'.tr(),
            value: entry.file.indexed ? 'yes'.tr() : 'no'.tr(),
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
                  label: Text('openInNewTab'.tr()),
                ),
              if (!entry.isFolder)
                FilledButton.tonalIcon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    showSnackBar('linkCopied'.tr());
                  },
                  icon: const Icon(Symbols.link, size: 18),
                  label: Text('copyLink'.tr()),
                ),
              OutlinedButton.icon(
                onPressed: onRename,
                icon: const Icon(Symbols.edit, size: 18),
                label: Text('rename'.tr()),
              ),
              OutlinedButton.icon(
                onPressed: onDelete,
                icon: Icon(Symbols.delete, size: 18, color: scheme.error),
                label: Text(
                  'delete'.tr(),
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            unindexed
                ? 'unindexedAssetsDescription'.tr()
                : 'workspaceFilesDescription'.tr(),
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
              tooltip: 'copy'.tr(),
              icon: const Icon(Symbols.content_copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                showSnackBar('copied'.tr());
              },
            ),
        ],
      ),
    );
  }
}
