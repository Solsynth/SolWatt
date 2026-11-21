import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/ideask/ideask_page.dart';
import 'package:solwatt/ideask/ideask_providers.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/shell/contextual_sidebar.dart';
import 'package:solwatt/shell/mobile_workspace_chrome.dart';
import 'package:solwatt/shell/workspace_title_bar.dart';
import 'package:solwatt/shell/workspace_tabs.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/ui/cloud_files.dart';
import 'package:solwatt/ui/page_scaffold.dart';
import 'package:solwatt/workspace/omnibox/federated_omnibox.dart';
import 'package:solwatt/workspace/peek/peek_surface.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_state.dart';

/// Ordered list of lenses matching [AppShellPage]'s `AutoTabsRouter.routes`.
const List<WorkspaceLens> kShellLenses = [
  WorkspaceLens.mail,
  WorkspaceLens.todo,
  WorkspaceLens.drive,
  WorkspaceLens.flywheel,
  WorkspaceLens.profile,
  WorkspaceLens.settings,
];

enum _ViewportClass { desktop, tablet, mobile }

_ViewportClass _classifyViewport(double width) {
  if (width > SolWorkspaceGeometry.desktopBreakpoint) {
    return _ViewportClass.desktop;
  }
  if (width >= SolWorkspaceGeometry.tabletBreakpoint) {
    return _ViewportClass.tablet;
  }
  return _ViewportClass.mobile;
}

/// Lenses whose contextual tree only mirrors the rail's own destinations.
/// Their sidebar would repeat the lens switcher one column over, so the shell
/// leaves that column to the canvas instead.
bool _lensOwnsSidebar(WorkspaceLens lens) => switch (lens) {
  WorkspaceLens.mail || WorkspaceLens.todo || WorkspaceLens.drive => true,
  WorkspaceLens.flywheel ||
  WorkspaceLens.profile ||
  WorkspaceLens.settings => false,
};

/// Root Adaptive Spatial Shell adapting across Desktop (>1024px 4-zone split),
/// Tablet (600-1024px 2-zone split + docked right sheet), and Mobile (<600px
/// single canvas + top switcher + floating bottom PillSurface omnibox/create
/// + layered DraggableScrollableSheet peek).
class AdaptiveWorkspaceShell extends ConsumerStatefulWidget {
  final bool isShown;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget child;

  const AdaptiveWorkspaceShell({
    super.key,
    required this.isShown,
    required this.selectedIndex,
    required this.onSelected,
    required this.child,
  });

  @override
  ConsumerState<AdaptiveWorkspaceShell> createState() =>
      _AdaptiveWorkspaceShellState();
}

class _AdaptiveWorkspaceShellState
    extends ConsumerState<AdaptiveWorkspaceShell> {
  WorkspaceLens get _activeLens =>
      kShellLenses[widget.selectedIndex.clamp(0, kShellLenses.length - 1)];

  /// Sends the reader to [lens]. The rail addresses a place, not a document,
  /// so arriving at a lens costs no tab: the lens comes back on its root pane
  /// and documents opened elsewhere keep the tabs they own.
  void _selectLens(WorkspaceLens lens) {
    // The drive reads a file in its own pane, not in the lens stack: leaving
    // the lens ends that reading so the browser is what the reader comes back
    // to.
    if (lens != WorkspaceLens.drive) _closeDriveDocuments();
    ref.read(workspaceTabsProvider.notifier).deactivate();
    _gotoLens(lens);
    _nestedStack(lens)?.popUntilRoot();
  }

  void _closeDriveDocuments() {
    final driveTabs = ref.read(workspaceTabsProvider).tabs.where(
      (tab) => tab.lens == WorkspaceLens.drive,
    );
    for (final tab in driveTabs) {
      ref.read(drivePendingCloseProvider.notifier).request(tab.entityId!);
    }
  }

  /// Switches the lens the canvas shows without touching the bar. Selecting a
  /// tab already decided what is on screen; this only follows it there.
  void _gotoLens(WorkspaceLens lens) {
    final idx = kShellLenses.indexOf(lens);
    if (idx >= 0) widget.onSelected(idx);
  }

  /// Opens [entity] in its domain's lens, so the title bar and the lens agree
  /// on what is on screen. The drive reads files in its own pane, so it takes
  /// a focus request; everything else is routed in the lens' nested stack.
  void _openEntityTab(WorkspaceEntityRef entity) {
    final lens = lensOfDomain(entity.domain);
    _selectLens(lens);
    switch (entity.domain) {
      case WorkspaceDomain.mail:
        // The mail lens owns the conversation routes, so it is asked to bring
        // the conversation forward rather than routed from outside: only it
        // knows which message is the newest one to open.
        ref
            .read(mailPendingFocusProvider.notifier)
            .request(entity.id, fullScreen: true);
      case WorkspaceDomain.todo:
        // Folders and collections are places in the tree: the browser opens
        // them in place rather than pushing a document above itself.
        final selection = ideaskSelectionOf(entity);
        if (selection != null) {
          ref.read(ideaskSelectionProvider.notifier).select(selection);
        }
      case WorkspaceDomain.pages:
        // A page is a document of the strip: claiming its tab is what opens
        // it, and the Todo lens shows the active page in place of the browser.
        ref
            .read(workspaceTabsProvider.notifier)
            .claim(
              domain: WorkspaceDomain.pages,
              entityId: entity.id,
              title: entity.title,
            );
      case WorkspaceDomain.drive:
        ref.read(drivePendingFocusProvider.notifier).request(entity.id);
    }
  }

  /// Brings a tab forward: the lens it belongs to, then the document itself.
  void _selectTab(WorkspaceTab tab) {
    _gotoLens(tab.lens);
    ref.read(workspaceTabsProvider.notifier).activate(tab.key);
    switch (tab.domain) {
      case WorkspaceDomain.mail:
        // The bar knows which message this conversation was showing, so
        // selecting the tab reopens exactly that message in the lens stack.
        final route = routeForTab(tab);
        if (route != null) _nestedStack(tab.lens)?.navigate(route);
      case WorkspaceDomain.todo:
        // A TODO entity the strip could carry (a folder, a collection) is a
        // place the browser shows in place; it has no route to reopen.
        break;
      case WorkspaceDomain.pages:
        // A page is a pane of the lens: activating the tab is what shows it.
        break;
      case WorkspaceDomain.drive:
        ref.read(drivePendingFocusProvider.notifier).request(tab.entityId!);
    }
  }

  /// Closes a document tab.
  ///
  /// The drive owns a reading pane and the page is a pane of the Todo lens, so
  /// those close by dropping the claim; a tab that lives on its lens' nested
  /// stack pops back to the root the reader opened it from.
  void _closeTab(WorkspaceTab tab) {
    switch (tab.domain) {
      case WorkspaceDomain.drive:
        ref.read(drivePendingCloseProvider.notifier).request(tab.entityId!);
      case WorkspaceDomain.mail:
        _nestedStack(tab.lens)?.popUntilRoot();
      case WorkspaceDomain.todo:
      case WorkspaceDomain.pages:
        // A page is a pane of the lens: the strip's active tab is what mounts
        // it, so closing the tab is the whole close.
        break;
    }
    // The strip closes in the same rebuild as the pane, so the bar never names
    // a document that is already gone.
    ref.read(workspaceTabsProvider.notifier).close(tab.key);
  }

  StackRouter? _nestedStack(WorkspaceLens lens) => lensStackRouter(lens);

  void _switchToEntity(WorkspaceEntityRef entity) {
    switch (entity.domain) {
      case WorkspaceDomain.mail:
        _selectLens(WorkspaceLens.mail);
      case WorkspaceDomain.todo:
        _selectLens(WorkspaceLens.todo);
        final selection = ideaskSelectionOf(entity);
        if (selection != null) {
          ref.read(ideaskSelectionProvider.notifier).select(selection);
        }
      case WorkspaceDomain.pages:
        _selectLens(WorkspaceLens.todo);
        ref
            .read(workspaceTabsProvider.notifier)
            .claim(
              domain: WorkspaceDomain.pages,
              entityId: entity.id,
              title: entity.title,
            );
      case WorkspaceDomain.drive:
        _selectLens(WorkspaceLens.drive);
    }
  }

  void _openOmnibox() {
    showFederatedOmnibox(context, onSwitchLens: _switchToEntity);
  }

  /// The one create action: a folder, a page, a collection or a task. Which
  /// one is the reader's choice, not the lens' — the tree holds all four.
  Future<void> _openCreateSheet() async {
    _selectLens(WorkspaceLens.todo);
    _nestedStack(WorkspaceLens.todo)?.popUntilRoot();
    await showIdeaskCreateSheet(context, ref);
  }

  Future<void> _handleConvertMailToTask(WorkspaceEntityRef mailEntity) async {
    HapticFeedback.selectionClick();
    // Tasks live in the workspace or in one of its folders. A mail sweep
    // files into the unfiled task list, which always exists.
    if (ref.read(ideaskWorkspaceIdProvider) == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('selectWorkspaceToConvertMail'.tr())),
        );
      }
      return;
    }

    try {
      final createdTask = await ref
          .read(ideaskActionsProvider)
          .createTask(
            task: WorkTaskDraft(
              name: 'followUpTaskName'.tr(
                namedArgs: {'title': mailEntity.title},
              ),
              description: mailEntity.subtitle,
            ),
          );
      final taskEntity = ideaskEntityRefForTask(
        createdTask,
        fallbackTitle: 'unfiledTasks'.tr(),
      );
      ref.read(backlinksProvider.notifier).link(mailEntity, taskEntity);
      ref.read(peekProvider.notifier).open(taskEntity);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'taskCreatedNamed'.tr(namedArgs: {'name': createdTask.name}),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('taskCreateFailed'.tr(namedArgs: {'error': '$e'})),
          ),
        );
      }
    }
  }

  void _handleSpaceKey() {
    final focused = ref.read(focusedEntityProvider);
    if (focused != null) {
      ref.read(peekProvider.notifier).toggle(focused);
    } else if (ref.read(peekProvider).isOpen) {
      ref.read(peekProvider.notifier).close();
    }
  }

  void _handleEscapeKey() {
    if (ref.read(peekProvider).isOpen) {
      ref.read(peekProvider.notifier).close();
      return;
    }
    ref.read(focusedEntityProvider.notifier).clear();
  }

  void _handleCompleteOrArchiveKey() {
    final target =
        ref.read(focusedEntityProvider) ?? ref.read(peekProvider).current;
    if (target == null || target.domain != WorkspaceDomain.todo) return;
    final updated = target.copyWith(
      isCompleted: !target.isCompleted,
      status: !target.isCompleted ? 'Completed' : 'Open',
    );
    ref.read(peekProvider.notifier).updateCurrentEntity(updated);
  }

  void _handleConvertFocusedMailKey() {
    final target =
        ref.read(focusedEntityProvider) ?? ref.read(peekProvider).current;
    if (target != null && target.domain == WorkspaceDomain.mail) {
      _handleConvertMailToTask(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final viewport = _classifyViewport(width);
    final scheme = Theme.of(context).colorScheme;
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final sidebarCollapsed = ref.watch(sidebarCollapsedProvider);
    final tabs = ref.watch(workspaceTabsProvider);
    // A document on screen is a full screen: the lens' list and its sidebar
    // step aside so the document gets the whole canvas.
    final showSidebar =
        !sidebarCollapsed &&
        _lensOwnsSidebar(_activeLens) &&
        !tabs.showsDocument;

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyK, meta: isMac, control: !isMac):
            _openOmnibox,
        const SingleActivator(LogicalKeyboardKey.space): _handleSpaceKey,
        const SingleActivator(LogicalKeyboardKey.escape): _handleEscapeKey,
        const SingleActivator(LogicalKeyboardKey.keyE):
            _handleCompleteOrArchiveKey,
        const SingleActivator(LogicalKeyboardKey.keyT):
            _handleConvertFocusedMailKey,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          key: widget.isShown ? shellScaffoldKey : null,
          backgroundColor: viewport == _ViewportClass.mobile
              ? scheme.surface
              : scheme.surfaceContainerLowest,
          drawer: viewport == _ViewportClass.tablet
              ? Drawer(
                  width: SolWorkspaceGeometry.sidebarWidth,
                  child: ContextualSidebar(
                    activeLens: _activeLens,
                    onSelectLens: _selectLens,
                    onOpenEntity: _openEntityTab,
                    onCloseDrawer: () => Navigator.of(context).pop(),
                  ),
                )
              : null,
          body: switch (viewport) {
            // The rail runs the full height of the body, flush to its top edge
            // and bottom edge: it is the workspace's spine, and the strip
            // starts beside it rather than running across its head.
            _ViewportClass.desktop || _ViewportClass.tablet => Row(
              children: [
                _SlimLensRail(
                  activeLens: _activeLens,
                  sidebarCollapsed: sidebarCollapsed,
                  // A lens with no sidebar has nothing for this button to
                  // toggle.
                  showSidebarToggle: viewport == _ViewportClass.tablet
                      ? true
                      : _lensOwnsSidebar(_activeLens),
                  onSelectLens: _selectLens,
                  onToggleSidebar: viewport == _ViewportClass.tablet
                      ? () => shellScaffoldKey.currentState?.openDrawer()
                      : () => ref
                            .read(sidebarCollapsedProvider.notifier)
                            .toggle(),
                  onOpenOmnibox: _openOmnibox,
                  onMailDroppedToTodo: _handleConvertMailToTask,
                  onOpenCreate: _openCreateSheet,
                ),
                Expanded(
                  child: Column(
                    children: [
                      // The strip is about the documents open in the
                      // workspace; it collapses to nothing while none are.
                      WorkspaceTitleBar(
                        tabs: tabs,
                        onSelect: _selectTab,
                        onClose: _closeTab,
                        onSelectHome: () => _selectLens(_activeLens),
                        onOpenOmnibox: _openOmnibox,
                      ),
                      Expanded(
                        child: viewport == _ViewportClass.desktop
                            ? _DesktopWorkspace(
                                activeLens: _activeLens,
                                showSidebar: showSidebar,
                                onSelectLens: _selectLens,
                                onOpenEntity: _openEntityTab,
                                onOpenFullView: _switchToEntity,
                                canvas: widget.child,
                              )
                            : Stack(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      right: SolSpace.sm,
                                      bottom: SolSpace.sm,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                        SolRadius.md,
                                      ),
                                      child: widget.child,
                                    ),
                                  ),
                                  TabletPeekSheet(
                                    onOpenFullView: _switchToEntity,
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _ViewportClass.mobile => Stack(
              children: [
                Column(
                  children: [
                    // On a phone the strip is the only band at the top, so it
                    // owns the status-bar inset as well.
                    WorkspaceTitleBar(
                      tabs: tabs,
                      onSelect: _selectTab,
                      onClose: _closeTab,
                      onSelectHome: () => _selectLens(_activeLens),
                      onOpenOmnibox: _openOmnibox,
                      compact: true,
                    ),
                    MobileContextHeader(
                      activeLens: _activeLens,
                      onSelectLens: _selectLens,
                    ),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final mq = MediaQuery.of(context);
                          final bottomViewReserve =
                              mq.viewPadding.bottom +
                              MobileFloatingActionPill.bottomClearance;
                          final bottomPaddingReserve = math.max(
                            mq.padding.bottom,
                            bottomViewReserve - mq.viewInsets.bottom,
                          );
                          return MediaQuery(
                            data: mq.copyWith(
                              padding: mq.padding.copyWith(
                                bottom: bottomPaddingReserve,
                              ),
                              viewPadding: mq.viewPadding.copyWith(
                                bottom: bottomViewReserve,
                              ),
                            ),
                            child: widget.child,
                          );
                        },
                      ),
                    ),
                  ],
                ),
                MobileFloatingActionPill(
                  onOpenOmnibox: _openOmnibox,
                  onSelectLens: _selectLens,
                ),
                MobilePeekSheet(onOpenFullView: _switchToEntity),
              ],
            ),
          },
        ),
      ),
    );
  }
}

/// Desktop chrome beside the rail: the contextual sidebar when the lens owns
/// one, then the canvas with the peek pane beside it.
///
/// The rail and the strip are laid out by the shell itself; this is only the
/// row they leave for the lens' own columns.
class _DesktopWorkspace extends StatelessWidget {
  final WorkspaceLens activeLens;
  final bool showSidebar;
  final ValueChanged<WorkspaceLens> onSelectLens;
  final ValueChanged<WorkspaceEntityRef> onOpenEntity;
  final ValueChanged<WorkspaceEntityRef> onOpenFullView;
  final Widget canvas;

  const _DesktopWorkspace({
    required this.activeLens,
    required this.showSidebar,
    required this.onSelectLens,
    required this.onOpenEntity,
    required this.onOpenFullView,
    required this.canvas,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        right: SolSpace.sm,
        bottom: SolSpace.sm,
      ),
      child: Row(
        children: [
          if (showSidebar) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(SolRadius.md),
              child: ContextualSidebar(
                activeLens: activeLens,
                onSelectLens: onSelectLens,
                onOpenEntity: onOpenEntity,
              ),
            ),
            const SizedBox(width: SolSpace.sm),
          ],
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(SolRadius.md),
              child: canvas,
            ),
          ),
          DesktopPeekPane(onOpenFullView: onOpenFullView),
        ],
      ),
    );
  }
}

/// Zone 1: Slim Lens Rail (56px fixed width) for Desktop and Tablet.
class _SlimLensRail extends ConsumerWidget {
  final WorkspaceLens activeLens;
  final bool sidebarCollapsed;
  final bool showSidebarToggle;
  final ValueChanged<WorkspaceLens> onSelectLens;
  final VoidCallback onToggleSidebar;
  final VoidCallback onOpenOmnibox;
  final ValueChanged<WorkspaceEntityRef> onMailDroppedToTodo;
  final VoidCallback onOpenCreate;

  const _SlimLensRail({
    required this.activeLens,
    required this.sidebarCollapsed,
    required this.showSidebarToggle,
    required this.onSelectLens,
    required this.onToggleSidebar,
    required this.onOpenOmnibox,
    required this.onMailDroppedToTodo,
    required this.onOpenCreate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    final name = workspace?.name.trim();
    final label = (name == null || name.isEmpty) ? 'SolWatt' : name;

    return Container(
      width: SolWorkspaceGeometry.railWidth,
      color: scheme.surfaceContainerLowest,
      // The rail is the topmost surface of the shell body, so on a phone it —
      // not the lens header below it — owns the status-bar strip.
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: SolSpace.sm),
            // The workspace the app is in: its avatar carries the identity and
            // its name is the tooltip, so the rail keeps one icon of width.
            Tooltip(
              message: 'switchWorkspaceHint'.tr(
                namedArgs: {'workspace': label},
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(SolRadius.sm),
                onTap: () => showWorkspaceSwitcher(context, ref),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: CloudFileAvatar(
                      file: workspace?.picture,
                      fallbackIcon: Symbols.workspaces_rounded,
                      size: 28,
                      assumeImage: true,
                      borderRadius: workspace?.isIndividual == true
                          ? SolRadius.pillRadius
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: SolSpace.sm),
            _RailIconButton(
              icon: WorkspaceLens.mail.icon,
              tooltip: WorkspaceLens.mail.label,
              selected: activeLens == WorkspaceLens.mail,
              onTap: () => onSelectLens(WorkspaceLens.mail),
            ),
            const SizedBox(height: SolSpace.xs),
            // Dragging an email row onto the Todo rail icon converts it into
            // a Task.
            DragTarget<WorkspaceEntityRef>(
              onWillAcceptWithDetails: (details) =>
                  details.data.domain == WorkspaceDomain.mail,
              onAcceptWithDetails: (details) =>
                  onMailDroppedToTodo(details.data),
              builder: (context, candidateData, rejectedData) {
                final hovered = candidateData.isNotEmpty;
                return _RailIconButton(
                  icon: WorkspaceLens.todo.icon,
                  tooltip: 'todoDropMailTooltip'.tr(),
                  selected: activeLens == WorkspaceLens.todo || hovered,
                  onTap: () => onSelectLens(WorkspaceLens.todo),
                );
              },
            ),
            const SizedBox(height: SolSpace.xs),
            _RailIconButton(
              icon: WorkspaceLens.drive.icon,
              tooltip: WorkspaceLens.drive.label,
              selected: activeLens == WorkspaceLens.drive,
              onTap: () => onSelectLens(WorkspaceLens.drive),
            ),
            const SizedBox(height: SolSpace.md),
            _RailIconButton(
              icon: Symbols.add_rounded,
              tooltip: 'newFolderPageCollection'.tr(),
              selected: false,
              onTap: onOpenCreate,
            ),
            const SizedBox(height: SolSpace.xs),
            _RailIconButton(
              icon: Symbols.search_rounded,
              tooltip: 'omniboxTooltip'.tr(),
              selected: false,
              onTap: onOpenOmnibox,
            ),
            const Spacer(),
            if (showSidebarToggle)
              _RailIconButton(
                icon: sidebarCollapsed
                    ? Symbols.left_panel_open_rounded
                    : Symbols.left_panel_close_rounded,
                tooltip: sidebarCollapsed
                    ? 'showSidebar'.tr()
                    : 'hideSidebar'.tr(),
                selected: false,
                onTap: onToggleSidebar,
              ),
            _RailIconButton(
              icon: WorkspaceLens.flywheel.icon,
              tooltip: WorkspaceLens.flywheel.label,
              selected: activeLens == WorkspaceLens.flywheel,
              onTap: () => onSelectLens(WorkspaceLens.flywheel),
            ),
            _RailIconButton(
              icon: WorkspaceLens.profile.icon,
              tooltip: WorkspaceLens.profile.label,
              selected: activeLens == WorkspaceLens.profile,
              onTap: () => onSelectLens(WorkspaceLens.profile),
            ),
            _RailIconButton(
              icon: WorkspaceLens.settings.icon,
              tooltip: WorkspaceLens.settings.label,
              selected: activeLens == WorkspaceLens.settings,
              onTap: () => onSelectLens(WorkspaceLens.settings),
            ),
            const SizedBox(height: SolSpace.sm),
          ],
        ),
      ),
    );
  }
}

class _RailIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _RailIconButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(SolRadius.sm),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: selected ? scheme.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(SolRadius.sm),
          ),
          child: Icon(
            icon,
            size: 20,
            color: selected
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
