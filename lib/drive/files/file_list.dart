import 'dart:async';
import 'dart:io';

import 'package:animations/animations.dart';
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:solwatt/drive/favorites.dart';
import 'package:solwatt/drive/screens/file_list.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart';
import 'package:solwatt/core/config.dart';
import 'package:solwatt/core/network.dart';
import 'package:solwatt/shared/widgets/alert.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/shared/widgets/app_scaffold.dart';
import 'package:solwatt/shell/workspace_tabs.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/core/widgets/content/file_viewer_contents.dart';
import 'package:solwatt/shared/widgets/responsive_sidebar.dart';
import 'package:solwatt/drive/widgets/file_list_view.dart';
import 'package:solwatt/core/widgets/content/file_info_sheet.dart';
import 'package:solwatt/drive/file_permissions.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

/// One folder browser. Files are not tabs of it: reading a file swaps the
/// canvas to the viewer and the shared title bar carries it.
class _DriveFileTab {
  final String id;
  final FileListMode mode;
  final String? workspaceId;

  const _DriveFileTab({required this.id, required this.mode, this.workspaceId});
}

@RoutePage()
class FileListScreen extends HookConsumerWidget {
  const FileListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = useState<List<_DriveFileTab>>([]);
    final activeTabId = useState<String?>(null);
    // The file the drive is reading. A viewed file is a workspace document, so
    // it shows as a tab in the shared title bar rather than the drive growing a
    // tab strip of its own.
    final viewingFile = useState<SnCloudFile?>(null);
    final viewingFileId = useState<String?>(null);
    // Latches after the first tab is seeded so closing every tab leaves the
    // empty state instead of re-opening the workspace root.
    final seededWorkspaceTab = useState(false);
    final showSidebar = useState<bool>(false);
    final showFilters = useState(false);
    final dragging = useState(false);
    final searchDebounceTimer = useRef<Timer?>(null);

    final pathStates = useMemoized(() => <String, ValueNotifier<String>>{});
    final modeStates = useMemoized(
      () => <String, ValueNotifier<FileListMode>>{},
    );
    final poolStates = useMemoized(
      () => <String, ValueNotifier<SnFilePool?>>{},
    );
    final viewModeStates = useMemoized(
      () => <String, ValueNotifier<FileListViewMode>>{},
    );
    final selectionModeStates = useMemoized(
      () => <String, ValueNotifier<bool>>{},
    );
    final selectedFileIdsStates = useMemoized(
      () => <String, ValueNotifier<Set<String>>>{},
    );
    final visibleFileIdsStates = useMemoized(
      () => <String, ValueNotifier<Set<String>>>{},
    );
    final recycledStates = useMemoized(() => <String, ValueNotifier<bool>>{});
    final queryStates = useMemoized(() => <String, ValueNotifier<String?>>{});
    final fallbackPath = useMemoized(() => ValueNotifier('/'));
    final fallbackMode = useMemoized(() => ValueNotifier(FileListMode.normal));
    final fallbackPool = useMemoized(() => ValueNotifier<SnFilePool?>(null));
    final fallbackSelectionMode = useMemoized(() => ValueNotifier(false));
    final fallbackSelectedFileIds = useMemoized(
      () => ValueNotifier(<String>{}),
    );
    final fallbackVisibleFileIds = useMemoized(() => ValueNotifier(<String>{}));
    final fallbackRecycled = useMemoized(() => ValueNotifier(false));
    final fallbackQuery = useMemoized(() => ValueNotifier<String?>(null));

    // The drive has no inline workspace switcher: folder tabs always browse the
    // app-selected workspace. Personal (individual) workspaces hold no drive
    // files, so they map to the personal-files root (a null workspace id).
    final selectedWorkspace = ref.watch(selectedWorkspaceProvider).value;
    final hasSelectedWorkspace = selectedWorkspace != null;
    final globalWorkspaceId =
        selectedWorkspace == null || selectedWorkspace.isIndividual
        ? null
        : selectedWorkspace.id;

    /// One browser per workspace. Opening the drive seeds it, and switching
    /// between cloud folders and service attachments reuses the same pane
    /// instead of growing a second tab.
    void openBrowser({FileListMode? mode}) {
      final wanted = mode ?? FileListMode.normal;
      final existing = tabs.value
          .where(
            (tab) => tab.mode == wanted && tab.workspaceId == globalWorkspaceId,
          )
          .firstOrNull;
      if (existing != null) {
        activeTabId.value = existing.id;
        viewingFile.value = null;
        ref.read(driveBrowseModeProvider.notifier).select(wanted);
        return;
      }

      final id = DateTime.now().microsecondsSinceEpoch.toString();
      tabs.value = [
        ...tabs.value,
        _DriveFileTab(id: id, mode: wanted, workspaceId: globalWorkspaceId),
      ];
      activeTabId.value = id;
      viewingFile.value = null;
      // The sidebar switch mirrors the pane; a tab opened from elsewhere (an
      // empty-state button, a workspace reseed) carries the same pane.
      ref.read(driveBrowseModeProvider.notifier).select(wanted);
      pathStates[id] = ValueNotifier('/');
      modeStates[id] = ValueNotifier(wanted);
      poolStates[id] = ValueNotifier(null);
      viewModeStates[id] = ValueNotifier(
        wanted == FileListMode.normal
            ? FileListViewMode.columns
            : FileListViewMode.list,
      );
      selectionModeStates[id] = ValueNotifier(false);
      selectedFileIdsStates[id] = ValueNotifier(<String>{});
      visibleFileIdsStates[id] = ValueNotifier(<String>{});
      recycledStates[id] = ValueNotifier(false);
      queryStates[id] = ValueNotifier(null);
    }

    /// Reads [file] in the canvas. A file is a workspace document, so it joins
    /// the shared title bar as a tab instead of spawning a drive tab.
    void openFileTab(SnCloudFile file) {
      viewingFile.value = file;
      ref
          .read(workspaceTabsProvider.notifier)
          .register(
            domain: WorkspaceDomain.drive,
            entityId: file.id,
            title: file.name,
          );
    }

    /// Leaves the viewer and returns to the folder browser it was opened from.
    void closeViewedFile() {
      final file = viewingFile.value;
      if (file == null) return;
      viewingFile.value = null;
      ref
          .read(workspaceTabsProvider.notifier)
          .close(WorkspaceTab.keyFor(WorkspaceDomain.drive, file.id));
    }

    /// Browses a folder path in the browser, without leaving the pane.
    void openFolderTab(String path) {
      final normalizedPath = path.trim().isEmpty ? '/' : path;
      final browser = tabs.value
          .where((tab) => tab.workspaceId == globalWorkspaceId)
          .firstOrNull;
      if (browser == null) {
        openBrowser();
        return;
      }
      activeTabId.value = browser.id;
      viewingFile.value = null;
      pathStates[browser.id]?.value = normalizedPath;
      modeStates[browser.id]?.value = FileListMode.normal;
      ref.read(driveBrowseModeProvider.notifier).select(FileListMode.normal);
    }

    void updateFileTab(SnCloudFile file) {
      if (viewingFile.value?.id == file.id) viewingFile.value = file;
      ref
          .read(workspaceTabsProvider.notifier)
          .register(
            domain: WorkspaceDomain.drive,
            entityId: file.id,
            title: file.name,
          );
    }

    /// Applies refreshed metadata after an in-place edit: the open tab and, when
    /// it is showing that file, the inspector both hold their own copy.
    void handleFileSaved(SnCloudFile file) {
      updateFileTab(file);
      final inspector = ref.read(driveInspectorFileProvider);
      if (inspector?.id == file.id) {
        ref.read(driveInspectorFileProvider.notifier).setFile(file);
      }
    }

    // The workspace strip speaks to the drive through one-shot signals: bring
    // a file forward, or close the viewer. Both land back in the browser tab.
    ref.listen(drivePendingFocusProvider, (_, fileId) {
      if (fileId == null) return;
      final current = viewingFile.value;
      if (current?.id != fileId) {
        viewingFile.value = null;
        viewingFileId.value = fileId;
      }
      ref.read(drivePendingFocusProvider.notifier).clear();
    });

    // A viewer opened from outside the drive has no file object yet: fetch it
    // and keep the tab label honest once the name arrives.
    final pendingFileAsync = viewingFileId.value == null
        ? null
        : ref.watch(driveFileInfoProvider(viewingFileId.value!));
    final pendingFile = pendingFileAsync?.asData?.value;
    useEffect(() {
      if (pendingFile == null) return null;
      viewingFile.value = pendingFile;
      viewingFileId.value = null;
      ref
          .read(workspaceTabsProvider.notifier)
          .register(
            domain: WorkspaceDomain.drive,
            entityId: pendingFile.id,
            title: pendingFile.name,
          );
      return null;
    }, [pendingFile]);
    ref.listen(drivePendingCloseProvider, (_, fileId) {
      if (fileId == null) return;
      if (viewingFile.value?.id == fileId) closeViewedFile();
      ref.read(drivePendingCloseProvider.notifier).clear();
    });

    useEffect(() {
      return () {
        for (final notifier in pathStates.values) {
          notifier.dispose();
        }
        for (final notifier in modeStates.values) {
          notifier.dispose();
        }
        for (final notifier in poolStates.values) {
          notifier.dispose();
        }
        for (final notifier in viewModeStates.values) {
          notifier.dispose();
        }
        for (final notifier in selectionModeStates.values) {
          notifier.dispose();
        }
        for (final notifier in selectedFileIdsStates.values) {
          notifier.dispose();
        }
        for (final notifier in visibleFileIdsStates.values) {
          notifier.dispose();
        }
        for (final notifier in recycledStates.values) {
          notifier.dispose();
        }
        for (final notifier in queryStates.values) {
          notifier.dispose();
        }
      };
    }, const []);

    final activeTab = activeTabId.value == null
        ? null
        : tabs.value.where((tab) => tab.id == activeTabId.value).firstOrNull;
    final currentPath = activeTab == null ? null : pathStates[activeTab.id];
    final mode = activeTab == null ? null : modeStates[activeTab.id];
    // Folder tabs browse the globally active workspace; file preview tabs stay
    // pinned to the workspace their file was opened from.
    final activeWorkspaceId = globalWorkspaceId;
    final selectedPool = activeTab == null ? null : poolStates[activeTab.id];
    final viewMode = activeTab == null ? null : viewModeStates[activeTab.id];
    final isSelectionMode = activeTab == null
        ? null
        : selectionModeStates[activeTab.id];
    final selectedFileIds = activeTab == null
        ? null
        : selectedFileIdsStates[activeTab.id];
    final visibleFileIds = activeTab == null
        ? null
        : visibleFileIdsStates[activeTab.id];
    final recycled = activeTab == null ? null : recycledStates[activeTab.id];
    final query = activeTab == null ? null : queryStates[activeTab.id];
    final currentPathValue = useValueListenable(currentPath ?? fallbackPath);
    final modeValue = useValueListenable(mode ?? fallbackMode);
    final selectedPoolValue = useValueListenable(selectedPool ?? fallbackPool);
    final isSelectionModeValue = useValueListenable(
      isSelectionMode ?? fallbackSelectionMode,
    );
    final selectedFileIdsValue = useValueListenable(
      selectedFileIds ?? fallbackSelectedFileIds,
    );
    final visibleFileIdsValue = useValueListenable(
      visibleFileIds ?? fallbackVisibleFileIds,
    );
    final recycledValue = useValueListenable(recycled ?? fallbackRecycled);
    final queryValue = useValueListenable(query ?? fallbackQuery);
    final searchController = useTextEditingController(text: queryValue ?? '');

    useEffect(() {
      final nextText = queryValue ?? '';
      if (searchController.text == nextText) return null;
      searchController.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      );
      return null;
    }, [queryValue]);

    useEffect(() {
      return () {
        searchDebounceTimer.value?.cancel();
      };
    }, const []);

    // SolWatt: the drive follows the app-selected workspace. The first indexed
    // tab opens once [selectedWorkspaceProvider] resolves, and every later
    // workspace switch retargets the open folder tabs to the new root so they
    // never keep browsing the previous workspace's caches.
    final browseMode = ref.watch(driveBrowseModeProvider);

    // SolWatt: the drive follows the app-selected workspace. The first indexed
    // tab opens once [selectedWorkspaceProvider] resolves, and every later
    // workspace switch retargets the open folder tabs to the new root so they
    // never keep browsing the previous workspace's caches.
    useEffect(() {
      if (!hasSelectedWorkspace) return null;

      // Hooks run inside build: mutating tab state there is dropped (the
      // element's dirty flag clears when the build ends) and riverpod rejects
      // provider writes mid-build. Apply tab changes after the frame instead.
      if (!seededWorkspaceTab.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          if (seededWorkspaceTab.value || tabs.value.isNotEmpty) return;
          seededWorkspaceTab.value = true;
          openBrowser();
        });
        return null;
      }

      final staleTabs = tabs.value
          .where((tab) => tab.workspaceId != globalWorkspaceId)
          .map((tab) => tab.id)
          .toList();
      if (staleTabs.isEmpty) return null;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final stale = staleTabs.toSet();
        tabs.value = tabs.value
            .map(
              (tab) => stale.contains(tab.id)
                  ? _DriveFileTab(
                      id: tab.id,
                      mode: tab.mode,
                      workspaceId: globalWorkspaceId,
                    )
                  : tab,
            )
            .toList();
        for (final tabId in stale) {
          pathStates[tabId]?.value = '/';
          poolStates[tabId]?.value = null;
          selectionModeStates[tabId]?.value = false;
          selectedFileIdsStates[tabId]?.value = <String>{};
          visibleFileIdsStates[tabId]?.value = <String>{};
          queryStates[tabId]?.value = null;
          recycledStates[tabId]?.value = false;
          invalidateIndexedDriveViews(ref, tabId);
          ref.invalidate(unindexedFileListFamilyProvider(tabId));
        }
      });
      return null;
    }, [globalWorkspaceId, hasSelectedWorkspace]);

    // The drive is a two-pane surface and the sidebar owns which pane is on
    // screen. A switch that finds no browser of that mode opens one, so the
    // sidebar alone moves the reader between cloud folders and attachments.
    useEffect(() {
      // The bootstrap seeds the first browser; until a workspace resolves there
      // is nothing to retarget, and the empty state stays on screen.
      if (!hasSelectedWorkspace || !seededWorkspaceTab.value) return null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final open = tabs.value
            .where(
              (tab) =>
                  tab.mode == browseMode &&
                  tab.workspaceId == globalWorkspaceId,
            )
            .firstOrNull;
        if (open == null) {
          openBrowser(mode: browseMode);
          return;
        }
        // A file being read is its own document; switching panes leaves it and
        // shows the folder browser of the chosen pane.
        if (viewingFile.value != null) closeViewedFile();
        if (activeTabId.value != open.id) activeTabId.value = open.id;
      });
      return null;
    }, [browseMode]);

    // "All files" in the sidebar is the cloud pane's root. Reset the open
    // browser there once a switch has left the reader in a nested folder.
    final rootRequest = ref.watch(driveRootRequestProvider);
    useEffect(() {
      if (rootRequest == 0) return null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final browser = tabs.value
            .where(
              (tab) =>
                  tab.mode == FileListMode.normal &&
                  tab.workspaceId == globalWorkspaceId,
            )
            .firstOrNull;
        if (browser == null) return;
        if (viewingFile.value != null) closeViewedFile();
        activeTabId.value = browser.id;
        pathStates[browser.id]?.value = '/';
        poolStates[browser.id]?.value = null;
        selectedFileIdsStates[browser.id]?.value = <String>{};
        queryStates[browser.id]?.value = null;
      });
      return null;
    }, [rootRequest]);

    // Notifiers should be read fresh each time to avoid disposal issues

    // Sidebar content widget
    final inspectorFile = ref.watch(driveInspectorFileProvider);

    final sidebarContent = inspectorFile == null
        ? const SizedBox.shrink()
        : FileInfoSheet(
            item: inspectorFile,
            key: ValueKey(inspectorFile.id),
            onClose: () {
              ref.read(driveInspectorFileProvider.notifier).setFile(null);
              showSidebar.value = false;
            },
          );

    // Drawer builder for narrow screens - uses builder to access providers
    Consumer drawerBuilder(BuildContext sheetContext) {
      return Consumer(
        builder: (context, ref, _) {
          final inspector = ref.watch(driveInspectorFileProvider);
          if (inspector != null) {
            return FileInfoSheet(
              item: inspector,
              onClose: () {
                ref.read(driveInspectorFileProvider.notifier).setFile(null);
                Navigator.of(sheetContext).pop();
              },
            );
          }
          return const SizedBox.shrink();
        },
      );
    }

    Future<void> refreshBrowser() async {
      final tab = activeTab;
      if (tab == null) return;
      if (modeValue == FileListMode.unindexed) {
        await ref
            .read(unindexedFileListFamilyProvider(tab.id).notifier)
            .refresh();
      } else {
        await ref
            .read(indexedCloudFileListFamilyProvider(tab.id).notifier)
            .refresh();
        bumpDriveBrowserEpoch(ref, tab.id);
      }
    }

    // Create/upload need a folder to land in; the phone bar drops them and
    // leaves the actions to the drive's own add button and the list.
    final activeBrowserTab = activeTab;
    final showBrowserTools =
        MediaQuery.sizeOf(context).width >
        SolWorkspaceGeometry.tabletBreakpoint;
    final canCreateOrUpload =
        activeBrowserTab != null &&
        modeValue == FileListMode.normal &&
        currentPath != null &&
        selectedPool != null;

    final bodyContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: PageTransitionSwitcher(
            reverse: false,
            transitionBuilder:
                (
                  Widget child,
                  Animation<double> primaryAnimation,
                  Animation<double> secondaryAnimation,
                ) {
                  return SharedAxisTransition(
                    animation: primaryAnimation,
                    secondaryAnimation: secondaryAnimation,
                    transitionType: SharedAxisTransitionType.horizontal,
                    child: child,
                  );
                },
            // Reading a file is a pane of its own: it replaces the
            // browser while its tab is active, and closing that tab
            // brings the folder back.
            child: viewingFile.value != null
                ? WorkspaceDocumentScope(
                    key: ValueKey(viewingFile.value!.id),
                    domain: WorkspaceDomain.drive,
                    entityId: viewingFile.value!.id,
                    title: viewingFile.value!.name,
                    // Reading a file is its own tab, not a pane of
                    // the browser's.
                    fullScreen: true,
                    child: _DriveFileContentTab(
                      file: viewingFile.value!,
                      workspaceId: activeWorkspaceId,
                      onFileSaved: handleFileSaved,
                      onInspectFile: (file) {
                        ref
                            .read(driveInspectorFileProvider.notifier)
                            .setFile(file);
                        showSidebar.value = true;
                      },
                    ),
                  )
                : activeTab == null
                ? _DriveWorkspaceEmptyState(
                    key: const ValueKey('empty'),
                    onOpenIndexed: () => openBrowser(),
                    onOpenUnindexed: () =>
                        openBrowser(mode: FileListMode.unindexed),
                  )
                : currentPath == null ||
                      selectedPool == null ||
                      mode == null ||
                      viewMode == null ||
                      isSelectionMode == null ||
                      query == null
                ? _DriveWorkspaceEmptyState(
                    key: const ValueKey('empty'),
                    onOpenIndexed: () => openBrowser(),
                    onOpenUnindexed: () =>
                        openBrowser(mode: FileListMode.unindexed),
                  )
                : FileListView(
                    key: ValueKey(activeTab.id),
                    tabId: activeTab.id,
                    workspaceId: activeWorkspaceId,
                    currentPath: currentPath,
                    selectedPool: selectedPool,
                    onOpenFolderInNewTab: openFolderTab,
                    showFilters: showFilters.value,
                    onPickAndUpload: () => _pickAndUploadFile(
                      ref,
                      activeTab.id,
                      currentPathValue,
                      selectedPoolValue?.id,
                      activeWorkspaceId,
                    ),
                    onShowCreateFolder: () => _showCreateFolderDialog(
                      context,
                      ref,
                      activeTab.id,
                      currentPathValue,
                      selectedPoolValue?.id,
                      activeWorkspaceId,
                    ),
                    onInspectFile: (file) {
                      ref
                          .read(driveInspectorFileProvider.notifier)
                          .setFile(file);
                      showSidebar.value = true;
                    },
                    onOpenFile: openFileTab,
                    selectedFileIds: selectedFileIds,
                    currentVisibleFileIds: visibleFileIds,
                    mode: mode,
                    viewMode: viewMode,
                    isSelectionMode: isSelectionMode,
                    query: query,
                  ),
          ),
        ),
        if (isSelectionModeValue)
          _DriveSelectionStatusBar(
            selectionCount: selectedFileIdsValue.length,
            allVisibleSelected:
                visibleFileIdsValue.isNotEmpty &&
                visibleFileIdsValue.difference(selectedFileIdsValue).isEmpty,
            onCancel: () {
              selectedFileIds?.value = <String>{};
              isSelectionMode?.value = false;
            },
            onToggleSelectAll: () {
              if (visibleFileIds == null || selectedFileIds == null) {
                return;
              }
              if (visibleFileIdsValue.isEmpty) return;
              final allSelected = visibleFileIdsValue
                  .difference(selectedFileIdsValue)
                  .isEmpty;
              if (allSelected) {
                selectedFileIds.value = selectedFileIdsValue.difference(
                  visibleFileIdsValue,
                );
              } else {
                selectedFileIds.value = {
                  ...selectedFileIdsValue,
                  ...visibleFileIdsValue,
                };
              }
            },
            onDownload: selectedFileIdsValue.isEmpty
                ? null
                : () async {
                    final files = await _resolveSelectedFiles(
                      ref,
                      selectedFileIdsValue,
                    );
                    if (files.isEmpty) return;
                    await ref
                        .read(driveFileDownloaderProvider)
                        .downloadFiles(
                          files,
                          useDownloadsFolder:
                              HardwareKeyboard.instance.isShiftPressed,
                        );
                  },
            onDelete: selectedFileIdsValue.isEmpty
                ? null
                : () async {
                    final confirmed = await showConfirmAlert(
                      'confirmDeleteSelectedFiles'.tr(),
                      'deleteSelectedFiles'.tr(),
                      isDanger: true,
                    );
                    if (!confirmed) return;
                    if (context.mounted) {
                      showLoadingModal(context);
                    }
                    try {
                      final uploader = ref.read(driveFileUploaderProvider);
                      final count = await uploader.batchDeleteFiles(
                        selectedFileIdsValue.toList(),
                      );
                      selectedFileIds?.value = <String>{};
                      visibleFileIds?.value = <String>{};
                      isSelectionMode?.value = false;
                      if (modeValue == FileListMode.normal) {
                        invalidateIndexedDriveViews(ref, activeTab!.id);
                      } else {
                        ref.invalidate(
                          unindexedFileListFamilyProvider(activeTab!.id),
                        );
                      }
                      showSnackBar(
                        'deletedFilesCount'.tr(args: [count.toString()]),
                      );
                    } catch (e) {
                      showSnackBar('failedToDeleteSelectedFiles'.tr());
                    } finally {
                      if (context.mounted) {
                        hideLoadingModal(context);
                      }
                    }
                  },
          ),
      ],
    );

    // Accept desktop file/folder drops on folder browser tabs (not file preview).
    final canAcceptDrops =
        viewingFile.value == null &&
        activeTab != null &&
        modeValue == FileListMode.normal;

    final droppableBody = canAcceptDrops
        ? DropTarget(
            onDragEntered: (_) => dragging.value = true,
            onDragExited: (_) => dragging.value = false,
            onDragDone: (details) async {
              dragging.value = false;
              if (details.files.isEmpty ||
                  currentPath == null ||
                  selectedPool == null) {
                return;
              }
              await _uploadDroppedFiles(
                ref,
                activeTab.id,
                currentPath.value,
                selectedPool.value?.id,
                activeWorkspaceId,
                details.files,
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                bodyContent,
                if (dragging.value)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withOpacity(0.9),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Symbols.upload_file,
                                size: 64,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const Gap(16),
                              Text(
                                'dropFilesHere'.tr(),
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const Gap(8),
                              Text(
                                'dragAndDropToAttach'.tr(),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          )
        : bodyContent;

    final mainContent = AppScaffold(
      appBar: AppBar(
        title: SearchBar(
          controller: searchController,
          constraints: const BoxConstraints(maxWidth: 400, minHeight: 32),
          hintText: 'searchFiles'.tr(),
          hintStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 14)),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 14)),
          enabled: query != null,
          onChanged: (value) {
            if (query == null) return;
            searchDebounceTimer.value?.cancel();
            searchDebounceTimer.value = Timer(
              const Duration(milliseconds: 300),
              () {
                query.value = value.isEmpty ? null : value;
              },
            );
          },
          leading: Icon(
            Symbols.search,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        actions: [
          // The browser's own tools live in the bar: the drive has no second
          // chrome row between its title and the folder list.
          IconButton(
            icon: const Icon(Symbols.refresh),
            onPressed: activeBrowserTab == null || viewingFile.value != null
                ? null
                : refreshBrowser,
            tooltip: 'refresh'.tr(),
          ),
          if (showBrowserTools && modeValue == FileListMode.normal) ...[
            IconButton(
              icon: const Icon(Symbols.create_new_folder),
              onPressed: canCreateOrUpload
                  ? () => _showCreateFolderDialog(
                      context,
                      ref,
                      activeBrowserTab.id,
                      currentPathValue,
                      selectedPoolValue?.id,
                      activeWorkspaceId,
                    )
                  : null,
              tooltip: 'createDirectory'.tr(),
            ),
            IconButton(
              icon: const Icon(Symbols.upload),
              onPressed: canCreateOrUpload
                  ? () => _pickAndUploadFile(
                      ref,
                      activeBrowserTab.id,
                      currentPathValue,
                      selectedPoolValue?.id,
                      activeWorkspaceId,
                    )
                  : null,
              tooltip: 'uploadFile'.tr(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SolSpace.sm),
              child: SizedBox(
                width: 1,
                height: 20,
                child: ColoredBox(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
            ),
          ],
          IconButton(
            icon: Icon(
              showFilters.value ? Symbols.filter_list_off : Symbols.filter_list,
            ),
            onPressed: activeTab == null || viewingFile.value != null
                ? null
                : () => showFilters.value = !showFilters.value,
            tooltip: showFilters.value
                ? 'hideFilters'.tr()
                : 'showFilters'.tr(),
          ),
          IconButton(
            icon: Icon(
              isSelectionModeValue ? Symbols.close : Symbols.select_check_box,
            ),
            onPressed: isSelectionMode == null
                ? null
                : () => isSelectionMode.value = !isSelectionMode.value,
            tooltip: isSelectionModeValue
                ? 'exitSelectionMode'.tr()
                : 'enterSelectionMode'.tr(),
          ),
          if (modeValue == FileListMode.unindexed)
            IconButton(
              icon: Icon(
                recycledValue
                    ? Symbols.delete_forever
                    : Symbols.restore_from_trash,
              ),
              onPressed: () {
                if (recycled == null || activeTab == null) return;
                recycled.value = !recycled.value;
                ref
                    .read(
                      unindexedFileListFamilyProvider(activeTab.id).notifier,
                    )
                    .setRecycled(recycled.value);
              },
              tooltip: recycledValue
                  ? 'showActiveFiles'.tr()
                  : 'showRecycleBin'.tr(),
            ),
          const Gap(8),
        ],
      ),
      floatingActionButton:
          modeValue == FileListMode.normal &&
              activeTab != null &&
              currentPath != null &&
              selectedPool != null
          ? FloatingActionButton(
              onPressed: () => _showActionBottomSheet(
                context,
                ref,
                activeTab.id,
                currentPath,
                selectedPool,
                activeWorkspaceId,
              ),
              tooltip: 'addFilesOrCreateDirectory'.tr(),
              child: const Icon(Symbols.add),
            )
          : null,
      body: droppableBody,
    );

    return ResponsiveSidebar(
      showSidebar: showSidebar,
      sidebarWidth: 320,
      minWideSidebarWidth: 280,
      maxWideSidebarWidth: 400,
      sidebarContent: sidebarContent,
      drawerBuilder: drawerBuilder,
      mainContent: mainContent,
    );
  }

  Future<void> _pickAndUploadFile(
    WidgetRef ref,
    String tabId,
    String currentPath,
    String? poolId,
    String? workspaceId,
  ) async {
    try {
      final result = await FilePicker.pickFiles();

      if (result.isNotEmpty) {
        await _uploadDroppedFiles(
          ref,
          tabId,
          currentPath,
          poolId,
          workspaceId,
          result
              .where((file) => file.path != null)
              .map((file) => XFile(file.path!, name: file.name))
              .toList(),
        );
      }
    } catch (e) {
      showSnackBar('errorPickingFile'.tr(args: [e.toString()]));
    }
  }

  Future<void> _pickAndUploadFolder(
    WidgetRef ref,
    String tabId,
    String currentPath,
    String? poolId,
    String? workspaceId,
  ) async {
    try {
      final folderPath = await FilePicker.getDirectoryPath(
        dialogTitle: 'uploadFolder'.tr(),
      );
      if (folderPath == null || folderPath.isEmpty) return;
      await _uploadLocalDirectory(
        ref,
        tabId,
        currentPath,
        poolId,
        workspaceId,
        folderPath,
      );
    } catch (e) {
      showSnackBar('failedToUploadFolder'.tr(args: [e.toString()]));
    }
  }

  Future<void> _ensureDriveDirectoryPath(
    WidgetRef ref,
    String drivePath,
    String? poolId,
    String? workspaceId,
  ) async {
    final normalizedPath = drivePath.trim();
    if (normalizedPath.isEmpty || normalizedPath == '/') return;

    final uploader = ref.read(driveFileUploaderProvider);
    final driveApi = ref.read(solarNetworkClientProvider).drive;
    final segments = normalizedPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();

    var currentPath = '';
    for (final segment in segments) {
      final nextPath = '$currentPath/$segment';
      try {
        await uploader.resolveParentIdFromPath(
          path: nextPath,
          poolId: poolId,
          workspaceId: workspaceId,
        );
      } catch (_) {
        final parentId = currentPath.isEmpty
            ? null
            : await uploader.resolveParentIdFromPath(
                path: currentPath,
                poolId: poolId,
                workspaceId: workspaceId,
              );
        await driveApi.createFolder(
          name: segment,
          parentId: parentId,
          workspaceId: workspaceId,
        );
      }
      currentPath = nextPath;
    }
  }

  Future<void> _uploadLocalDirectory(
    WidgetRef ref,
    String tabId,
    String currentPath,
    String? poolId,
    String? workspaceId,
    String rootDirectoryPath,
  ) async {
    final rootDirectory = Directory(rootDirectoryPath);
    if (!await rootDirectory.exists()) return;

    final entities = await rootDirectory
        .list(recursive: true, followLinks: false)
        .toList();
    final files = entities.whereType<File>().toList();
    if (files.isEmpty) return;

    final rootName = rootDirectory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .lastOrNull;
    final baseDrivePath = rootName == null || rootName.isEmpty
        ? currentPath
        : (currentPath == '/' ? '/$rootName' : '$currentPath/$rootName');

    await _ensureDriveDirectoryPath(ref, baseDrivePath, poolId, workspaceId);

    for (final file in files) {
      final relativePath = file.path.substring(rootDirectory.path.length);
      final normalizedRelative = relativePath
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'^/+'), '');
      final parts = normalizedRelative
          .split('/')
          .where((part) => part.isNotEmpty)
          .toList();
      if (parts.isEmpty) continue;

      final fileName = parts.last;
      final nestedFolders = parts.take(parts.length - 1).toList();
      final targetPath = nestedFolders.isEmpty
          ? baseDrivePath
          : '$baseDrivePath/${nestedFolders.join('/')}';

      await _ensureDriveDirectoryPath(ref, targetPath, poolId, workspaceId);

      final completer = ref
          .read(driveFileUploaderProvider)
          .createCloudFile(
            fileData: UniversalFile(
              data: XFile(file.path, name: fileName),
              type: UniversalFileType.file,
              displayName: fileName,
            ),
            path: targetPath,
            poolId: poolId,
            workspaceId: workspaceId,
            onProgress: (progress, _) {
              if (progress != null) {
                debugPrint('Upload progress: ${(progress * 100).toInt()}%');
              }
            },
          );

      completer.future.catchError((error) {
        showSnackBar('failedToUploadFile'.tr(args: [error.toString()]));
        return null;
      });
    }

    invalidateIndexedDriveViews(ref, tabId);
  }

  Future<void> _uploadDroppedFiles(
    WidgetRef ref,
    String tabId,
    String currentPath,
    String? poolId,
    String? workspaceId,
    List<XFile> files,
  ) async {
    if (files.isEmpty) return;

    for (final file in files) {
      if (!kIsWeb && file.path.isNotEmpty) {
        final stat = await FileSystemEntity.type(file.path);
        if (stat == FileSystemEntityType.directory) {
          await _uploadLocalDirectory(
            ref,
            tabId,
            currentPath,
            poolId,
            workspaceId,
            file.path,
          );
          continue;
        }
      }

      final displayName = file.name.isNotEmpty ? file.name : null;
      final universalFile = UniversalFile(
        data: file,
        type: UniversalFileType.file,
        displayName: displayName,
      );

      final completer = ref
          .read(driveFileUploaderProvider)
          .createCloudFile(
            fileData: universalFile,
            path: currentPath,
            poolId: poolId,
            workspaceId: workspaceId,
            onProgress: (progress, _) {
              if (progress != null) {
                debugPrint('Upload progress: ${(progress * 100).toInt()}%');
              }
            },
          );

      completer.future
          .then((uploadedFile) {
            if (uploadedFile != null) {
              invalidateIndexedDriveViews(ref, tabId);
            }
          })
          .catchError((error) {
            showSnackBar('failedToUploadFile'.tr(args: [error.toString()]));
          });
    }
  }

  Future<List<SnCloudFile>> _resolveSelectedFiles(
    WidgetRef ref,
    Set<String> selectedIds,
  ) async {
    final files = <SnCloudFile>[];
    for (final id in selectedIds) {
      try {
        files.add(await ref.read(driveFileInfoProvider(id).future));
      } catch (_) {
        // Skip files that can no longer be resolved.
      }
    }
    return files;
  }

  Future<void> _showCreateFolderDialog(
    BuildContext context,
    WidgetRef ref,
    String tabId,
    String currentPath,
    String? poolId,
    String? workspaceId,
  ) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    bool isCreating = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('createNewFolder').tr(),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'folderName'.tr(),
                hintText: 'folderNameHint'.tr(),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              autofocus: true,
              enabled: !isCreating,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'folderNameRequired'.tr();
                }
                if (value.contains(RegExp(r'[/\\:*?"<>|]'))) {
                  return 'folderNameInvalid'.tr();
                }
                if (value.length > 255) {
                  return 'folderNameTooLong'.tr();
                }
                return null;
              },
              onFieldSubmitted: (_) async {
                if (formKey.currentState!.validate()) {
                  setState(() => isCreating = true);
                  try {
                    final driveApi = ref.read(solarNetworkClientProvider).drive;
                    final uploader = ref.read(driveFileUploaderProvider);
                    final parentId = await uploader.resolveParentIdFromPath(
                      path: currentPath,
                      poolId: poolId,
                      workspaceId: workspaceId,
                    );
                    await driveApi.createFolder(
                      name: nameController.text.trim(),
                      parentId: parentId,
                      workspaceId: workspaceId,
                    );
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    invalidateIndexedDriveViews(ref, tabId);
                    showSnackBar('folderCreated'.tr());
                  } catch (e) {
                    if (context.mounted) {
                      setState(() => isCreating = false);
                      showSnackBar(
                        'folderCreationFailed'.tr(args: [e.toString()]),
                      );
                    }
                  }
                }
              },
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isCreating ? null : () => Navigator.of(context).pop(),
              child: Text('cancel').tr(),
            ),
            TextButton.icon(
              onPressed: isCreating
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setState(() => isCreating = true);
                      try {
                        final driveApi = ref
                            .read(solarNetworkClientProvider)
                            .drive;
                        final uploader = ref.read(driveFileUploaderProvider);
                        final parentId = await uploader.resolveParentIdFromPath(
                          path: currentPath,
                          poolId: poolId,
                          workspaceId: workspaceId,
                        );
                        await driveApi.createFolder(
                          name: nameController.text.trim(),
                          parentId: parentId,
                          workspaceId: workspaceId,
                        );
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                        invalidateIndexedDriveViews(ref, tabId);
                        showSnackBar('folderCreated'.tr());
                      } catch (e) {
                        if (context.mounted) {
                          setState(() => isCreating = false);
                          showSnackBar(
                            'folderCreationFailed'.tr(args: [e.toString()]),
                          );
                        }
                      }
                    },
              label: isCreating
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('createDirectory').tr(),
              icon: const Icon(Symbols.create_new_folder),
            ),
          ],
        ),
      ),
    );
  }

  void _showActionBottomSheet(
    BuildContext context,
    WidgetRef ref,
    String tabId,
    ValueNotifier<String> currentPath,
    ValueNotifier<SnFilePool?> selectedPool,
    String? workspaceId,
  ) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.create_new_folder),
              title: Text('createDirectory').tr(),
              onTap: () {
                Navigator.of(context).pop();
                _showCreateFolderDialog(
                  context,
                  ref,
                  tabId,
                  currentPath.value,
                  selectedPool.value?.id,
                  workspaceId,
                );
              },
            ),
            ListTile(
              leading: const Icon(Symbols.upload_file),
              title: Text('uploadFile').tr(),
              onTap: () {
                Navigator.of(context).pop();
                _pickAndUploadFile(
                  ref,
                  tabId,
                  currentPath.value,
                  selectedPool.value?.id,
                  workspaceId,
                );
              },
            ),
            ListTile(
              leading: const Icon(Symbols.drive_folder_upload),
              title: Text('uploadFolder').tr(),
              onTap: () {
                Navigator.of(context).pop();
                _pickAndUploadFolder(
                  ref,
                  tabId,
                  currentPath.value,
                  selectedPool.value?.id,
                  workspaceId,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DriveWorkspaceEmptyState extends StatelessWidget {
  final VoidCallback onOpenIndexed;
  final VoidCallback onOpenUnindexed;

  const _DriveWorkspaceEmptyState({
    super.key,
    required this.onOpenIndexed,
    required this.onOpenUnindexed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 560;
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(
                      Symbols.cloud_done,
                      size: 36,
                      color: colorScheme.primary,
                    ),
                  ),
                  const Gap(20),
                  Text(
                    'driveWorkspaceEmptyTitle'.tr(),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Gap(8),
                  Text(
                    'driveWorkspaceEmptyDescription'.tr(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const Gap(28),
                  if (isCompact) ...[
                    _DriveEntryCard(
                      icon: Symbols.folder,
                      title: 'driveIndexedEntryLabel'.tr(),
                      description: 'driveIndexedEntryDescription'.tr(),
                      onTap: onOpenIndexed,
                    ),
                    const Gap(12),
                    _DriveEntryCard(
                      icon: Symbols.inventory_2,
                      title: 'driveUnindexedEntryLabel'.tr(),
                      description: 'driveUnindexedEntryDescription'.tr(),
                      onTap: onOpenUnindexed,
                    ),
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _DriveEntryCard(
                            icon: Symbols.folder,
                            title: 'driveIndexedEntryLabel'.tr(),
                            description: 'driveIndexedEntryDescription'.tr(),
                            onTap: onOpenIndexed,
                          ),
                        ),
                        const Gap(16),
                        Expanded(
                          child: _DriveEntryCard(
                            icon: Symbols.inventory_2,
                            title: 'driveUnindexedEntryLabel'.tr(),
                            description: 'driveUnindexedEntryDescription'.tr(),
                            onTap: onOpenUnindexed,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DriveEntryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _DriveEntryCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: colorScheme.primary),
              ),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Gap(4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(8),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Icon(
                  Symbols.chevron_right,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriveSelectionStatusBar extends StatelessWidget {
  final int selectionCount;
  final bool allVisibleSelected;
  final VoidCallback onCancel;
  final VoidCallback onToggleSelectAll;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;

  const _DriveSelectionStatusBar({
    required this.selectionCount,
    required this.allVisibleSelected,
    required this.onCancel,
    required this.onToggleSelectAll,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = scheme.outlineVariant.withValues(alpha: 0.55);

    return Material(
      color: scheme.surfaceContainerLow,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: border)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            8,
            8 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Row(
            children: [
              Icon(Symbols.select_check_box, size: 18, color: scheme.primary),
              const Gap(12),
              Expanded(
                child: Text(
                  selectionCount == 1
                      ? 'fileSelected'.tr(args: [selectionCount.toString()])
                      : 'filesSelected'.tr(args: [selectionCount.toString()]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: onToggleSelectAll,
                child: Text(
                  allVisibleSelected ? 'deselectAll'.tr() : 'selectAll'.tr(),
                ),
              ),
              IconButton(
                onPressed: onDownload,
                tooltip: 'download'.tr(),
                icon: const Icon(Symbols.download),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: 'delete'.tr(),
                icon: const Icon(Symbols.delete),
              ),
              IconButton(
                onPressed: onCancel,
                tooltip: 'cancel'.tr(),
                icon: const Icon(Symbols.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriveFileContentTab extends ConsumerWidget {
  final SnCloudFile file;
  final String? workspaceId;
  final void Function(SnCloudFile file) onInspectFile;
  final void Function(SnCloudFile file) onFileSaved;

  const _DriveFileContentTab({
    required this.file,
    this.workspaceId,
    required this.onInspectFile,
    required this.onFileSaved,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverUrl = ref.watch(serverUrlProvider);
    final uri = Uri.parse('$serverUrl/drive/files/${file.id}')
        .replace(
          queryParameters: {
            if (workspaceId != null && workspaceId!.isNotEmpty)
              'workspace_id': workspaceId!,
          },
        )
        .toString();

    return SizedBox.expand(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => onInspectFile(file),
        onSecondaryTap: () => onInspectFile(file),
        child: ClipRect(
          child: switch (file.mimeType.split('/').firstOrNull) {
            'image' => ImageFileContent(item: file),
            'video' => VideoFileContent(item: file, uri: uri),
            'audio' => AudioFileContent(item: file, uri: uri),
            _ when file.mimeType.startsWith('text/') => TextFileContent(
              item: file,
              workspaceId: workspaceId,
              onSaved: onFileSaved,
            ),
            _ => GenericFileContent(item: file),
          },
        ),
      ),
    );
  }
}
