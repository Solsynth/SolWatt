import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/pages/pages_provider.dart';
import 'package:solwatt/route.dart';
import 'package:solwatt/shell/contextual_sidebar.dart';
import 'package:solwatt/shell/mobile_workspace_chrome.dart';
import 'package:solwatt/shell/workspace_title_bar.dart';
import 'package:solwatt/shell/workspace_tabs.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/ui/page_scaffold.dart';
import 'package:solwatt/workspace/omnibox/federated_omnibox.dart';
import 'package:solwatt/workspace/peek/peek_surface.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_state.dart';

/// Ordered list of lenses matching [AppShellPage]'s `AutoTabsRouter.routes`.
const List<WorkspaceLens> kShellLenses = [
  WorkspaceLens.today,
  WorkspaceLens.mail,
  WorkspaceLens.todo,
  WorkspaceLens.pages,
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
  WorkspaceLens.mail ||
  WorkspaceLens.todo ||
  WorkspaceLens.pages ||
  WorkspaceLens.drive => true,
  WorkspaceLens.today ||
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

  void _selectLens(WorkspaceLens lens) {
    final idx = kShellLenses.indexOf(lens);
    if (idx >= 0) {
      widget.onSelected(idx);
    }
  }

  /// Opens [entity] in its domain's lens, so the title bar and the lens agree
  /// on what is on screen. The drive reads files in its own pane, so it takes
  /// a focus request; everything else is routed in the lens' nested stack.
  void _openEntityTab(WorkspaceEntityRef entity) {
    final lens = lensOfDomain(entity.domain);
    _selectLens(lens);
    final route = routeForDocument(entity.domain, entity.id);
    if (route != null) _nestedStack(lens)?.navigate(route);
    if (entity.domain == WorkspaceDomain.drive) {
      ref.read(drivePendingFocusProvider.notifier).request(entity.id);
    }
  }

  /// Brings a tab forward. A document tab activates itself; the lens tab only
  /// brings its lens forward, leaving the pane it already shows in place.
  void _selectTab(WorkspaceTab tab) {
    final tabs = ref.read(workspaceTabsProvider.notifier);
    tabs.activate(tab.key);
    _selectLens(tab.lens);
    if (tab.isRoot) {
      _nestedStack(tab.lens)?.popUntilRoot();
      // The drive shows whatever file its pane was reading; returning to its
      // folder browser means closing that file's tab too.
      if (tab.lens == WorkspaceLens.drive) {
        for (final document in ref.read(workspaceTabsProvider).tabs) {
          if (document.lens == WorkspaceLens.drive && !document.isRoot) {
            ref
                .read(drivePendingCloseProvider.notifier)
                .request(document.entityId!);
          }
        }
      }
      return;
    }
    if (tab.domain == WorkspaceDomain.drive) {
      ref.read(drivePendingFocusProvider.notifier).request(tab.entityId!);
    } else {
      _nestedStack(
        tab.lens,
      )?.navigate(routeForDocument(tab.domain!, tab.entityId!)!);
    }
  }

  /// Closes a document tab: its pane closes itself and its lens pops back to
  /// the root page. The lens tab (the inbox, the folder browser) never closes.
  void _closeTab(WorkspaceTab tab) {
    if (tab.isRoot) return;
    final tabs = ref.read(workspaceTabsProvider.notifier);
    if (tab.domain == WorkspaceDomain.drive) {
      ref.read(drivePendingCloseProvider.notifier).request(tab.entityId!);
    } else {
      _nestedStack(tab.lens)?.popUntilRoot();
    }
    tabs.close(tab.key);
    // The lens tab steps back in, so the bar always says where the reader is.
    _activateLensRoot(tab.lens);
  }

  /// Activates the lens' own tab, if the bar carries one.
  void _activateLensRoot(WorkspaceLens lens) {
    final key = WorkspaceTab.lensTabKey(lens);
    final root = ref
        .read(workspaceTabsProvider)
        .tabs
        .where((tab) => tab.key == key)
        .firstOrNull;
    if (root != null) ref.read(workspaceTabsProvider.notifier).activate(key);
  }

  StackRouter? _nestedStack(WorkspaceLens lens) =>
      appRouter.innerRouterOf<StackRouter>(lens.routeName);

  void _switchToEntity(WorkspaceEntityRef entity) {
    switch (entity.domain) {
      case WorkspaceDomain.mail:
        _selectLens(WorkspaceLens.mail);
      case WorkspaceDomain.todo:
        _selectLens(WorkspaceLens.todo);
      case WorkspaceDomain.pages:
        ref.read(selectedPageIdProvider.notifier).select(entity.id);
        _selectLens(WorkspaceLens.pages);
      case WorkspaceDomain.drive:
        _selectLens(WorkspaceLens.drive);
    }
  }

  void _openOmnibox() {
    showFederatedOmnibox(context, onSwitchLens: _switchToEntity);
  }

  Future<void> _handleConvertMailToTask(WorkspaceEntityRef mailEntity) async {
    HapticFeedback.selectionClick();
    final boards = ref.read(broadsProvider).value ?? const <Broad>[];
    final firstBoard = boards.firstOrNull;
    if (firstBoard == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Create a Todo board first to convert mail into a task.',
            ),
          ),
        );
      }
      return;
    }

    try {
      final createdTask = await ref
          .read(wattEngineClientProvider)
          .createTask(
            firstBoard.id,
            WorkTaskDraft(
              name: 'Follow up: ${mailEntity.title}',
              description: mailEntity.subtitle,
            ),
          );
      ref.invalidate(tasksProvider(TaskListRequest(broadId: firstBoard.id)));
      final taskEntity = WorkspaceEntityRef(
        id: createdTask.id,
        domain: WorkspaceDomain.todo,
        title: createdTask.name,
        subtitle: firstBoard.name,
        status: 'Open',
        metadata: {'broadId': firstBoard.id, 'taskId': createdTask.id},
      );
      ref.read(backlinksProvider.notifier).link(mailEntity, taskEntity);
      ref.read(peekProvider.notifier).open(taskEntity);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created task "${createdTask.name}"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not create task: $e')));
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
    if (target == null) return;
    if (target.domain == WorkspaceDomain.pages) {
      ref.read(pagesProvider.notifier).toggleResolveComments(target.id);
    } else if (target.domain == WorkspaceDomain.todo) {
      final updated = target.copyWith(
        isCompleted: !target.isCompleted,
        status: !target.isCompleted ? 'Completed' : 'Open',
      );
      ref.read(peekProvider.notifier).updateCurrentEntity(updated);
    }
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
    final showSidebar = !sidebarCollapsed && _lensOwnsSidebar(_activeLens);
    // Every lens the reader lands on gets its tab, so the bar can always say
    // where they are even before they open a document.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(workspaceTabsProvider.notifier).ensureLensTab(_activeLens);
    });

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
          body: Column(
            children: [
              // The workspace title bar sits directly under the app's own
              // title bar and above every other surface — rail, sidebar,
              // canvas and peek alike — on every width.
              WorkspaceTitleBar(
                tabs: tabs,
                onSelect: _selectTab,
                onClose: _closeTab,
                onOpenOmnibox: _openOmnibox,
                compact: viewport == _ViewportClass.mobile,
              ),
              Expanded(
                child: switch (viewport) {
                  _ViewportClass.desktop => _DesktopWorkspace(
                    activeLens: _activeLens,
                    sidebarCollapsed: sidebarCollapsed,
                    showSidebar: showSidebar,
                    onSelectLens: _selectLens,
                    onToggleSidebar: () =>
                        ref.read(sidebarCollapsedProvider.notifier).toggle(),
                    onOpenOmnibox: _openOmnibox,
                    onMailDroppedToTodo: _handleConvertMailToTask,
                    onOpenEntity: _openEntityTab,
                    onOpenFullView: _switchToEntity,
                    canvas: widget.child,
                  ),
                  _ViewportClass.tablet => Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          right: SolSpace.sm,
                          top: SolSpace.sm,
                          bottom: SolSpace.sm,
                        ),
                        child: Row(
                          children: [
                            _SlimLensRail(
                              activeLens: _activeLens,
                              sidebarCollapsed: true,
                              showSidebarToggle: true,
                              onSelectLens: _selectLens,
                              onToggleSidebar: () =>
                                  shellScaffoldKey.currentState?.openDrawer(),
                              onOpenOmnibox: _openOmnibox,
                              onMailDroppedToTodo: _handleConvertMailToTask,
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  SolRadius.md,
                                ),
                                child: widget.child,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TabletPeekSheet(onOpenFullView: _switchToEntity),
                    ],
                  ),
                  _ViewportClass.mobile => Stack(
                    children: [
                      Column(
                        children: [
                          MobileContextHeader(
                            activeLens: _activeLens,
                            onSelectLens: _selectLens,
                          ),
                          Expanded(child: widget.child),
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Desktop chrome: the lens rail, the contextual sidebar when the lens owns
/// one, then the canvas with its tab strip above it and the peek pane beside.
class _DesktopWorkspace extends StatelessWidget {
  final WorkspaceLens activeLens;
  final bool sidebarCollapsed;
  final bool showSidebar;
  final ValueChanged<WorkspaceLens> onSelectLens;
  final VoidCallback onToggleSidebar;
  final VoidCallback onOpenOmnibox;
  final ValueChanged<WorkspaceEntityRef> onMailDroppedToTodo;
  final ValueChanged<WorkspaceEntityRef> onOpenEntity;
  final ValueChanged<WorkspaceEntityRef> onOpenFullView;
  final Widget canvas;

  const _DesktopWorkspace({
    required this.activeLens,
    required this.sidebarCollapsed,
    required this.showSidebar,
    required this.onSelectLens,
    required this.onToggleSidebar,
    required this.onOpenOmnibox,
    required this.onMailDroppedToTodo,
    required this.onOpenEntity,
    required this.onOpenFullView,
    required this.canvas,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        right: SolSpace.sm,
        top: SolSpace.sm,
        bottom: SolSpace.sm,
      ),
      child: Row(
        children: [
          _SlimLensRail(
            activeLens: activeLens,
            sidebarCollapsed: sidebarCollapsed,
            // A lens with no sidebar has nothing for this button to toggle.
            showSidebarToggle: _lensOwnsSidebar(activeLens),
            onSelectLens: onSelectLens,
            onToggleSidebar: onToggleSidebar,
            onOpenOmnibox: onOpenOmnibox,
            onMailDroppedToTodo: onMailDroppedToTodo,
          ),
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

  const _SlimLensRail({
    required this.activeLens,
    required this.sidebarCollapsed,
    required this.showSidebarToggle,
    required this.onSelectLens,
    required this.onToggleSidebar,
    required this.onOpenOmnibox,
    required this.onMailDroppedToTodo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: SolWorkspaceGeometry.railWidth,
      color: scheme.surfaceContainerLowest,
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: SolSpace.sm),
            _RailIconButton(
              icon: WorkspaceLens.today.icon,
              tooltip: 'Today / Focus',
              selected: activeLens == WorkspaceLens.today,
              onTap: () => onSelectLens(WorkspaceLens.today),
            ),
            const SizedBox(height: SolSpace.md),
            _RailIconButton(
              icon: WorkspaceLens.mail.icon,
              tooltip: 'Mail',
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
                  tooltip: 'Todo — drop mail to create a task',
                  selected: activeLens == WorkspaceLens.todo || hovered,
                  onTap: () => onSelectLens(WorkspaceLens.todo),
                );
              },
            ),
            const SizedBox(height: SolSpace.xs),
            _RailIconButton(
              icon: WorkspaceLens.pages.icon,
              tooltip: 'Pages',
              selected: activeLens == WorkspaceLens.pages,
              onTap: () => onSelectLens(WorkspaceLens.pages),
            ),
            const SizedBox(height: SolSpace.xs),
            _RailIconButton(
              icon: WorkspaceLens.drive.icon,
              tooltip: 'Drive',
              selected: activeLens == WorkspaceLens.drive,
              onTap: () => onSelectLens(WorkspaceLens.drive),
            ),
            const SizedBox(height: SolSpace.md),
            _RailIconButton(
              icon: Symbols.add_rounded,
              tooltip: 'New Page',
              selected: false,
              onTap: () {
                ref.read(pagesProvider.notifier).createPage();
                onSelectLens(WorkspaceLens.pages);
              },
            ),
            const SizedBox(height: SolSpace.xs),
            _RailIconButton(
              icon: Symbols.search_rounded,
              tooltip: 'Omnibox — Cmd K or Ctrl K',
              selected: false,
              onTap: onOpenOmnibox,
            ),
            const Spacer(),
            if (showSidebarToggle)
              _RailIconButton(
                icon: sidebarCollapsed
                    ? Symbols.left_panel_open_rounded
                    : Symbols.left_panel_close_rounded,
                tooltip: sidebarCollapsed ? 'Show Sidebar' : 'Hide Sidebar',
                selected: false,
                onTap: onToggleSidebar,
              ),
            _RailIconButton(
              icon: WorkspaceLens.flywheel.icon,
              tooltip: 'Flywheel',
              selected: activeLens == WorkspaceLens.flywheel,
              onTap: () => onSelectLens(WorkspaceLens.flywheel),
            ),
            _RailIconButton(
              icon: WorkspaceLens.profile.icon,
              tooltip: 'Profile',
              selected: activeLens == WorkspaceLens.profile,
              onTap: () => onSelectLens(WorkspaceLens.profile),
            ),
            _RailIconButton(
              icon: WorkspaceLens.settings.icon,
              tooltip: 'Settings',
              selected: activeLens == WorkspaceLens.settings,
              onTap: () => onSelectLens(WorkspaceLens.settings),
            ),
            _RailIconButton(
              icon: Symbols.workspaces_rounded,
              tooltip: 'Workspaces',
              selected: false,
              onTap: () =>
                  context.router.push(const WorkspaceManagementRoute()),
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
