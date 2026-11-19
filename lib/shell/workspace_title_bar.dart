import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/route.dart';
import 'package:solwatt/workspaces/workspace_actions.dart';
import 'package:solwatt/shell/workspace_tabs.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/ui/cloud_files.dart';

/// The workspace title bar: the workspace it belongs to and the documents open
/// in it, always present between the app's own title bar and every other piece
/// of chrome.
///
/// The tabs are the drive's browser-style chrome: flat, square-cornered, the
/// selected one sitting on the content surface under a primary accent line.
/// Nothing here is a pill.
class WorkspaceTitleBar extends ConsumerWidget {
  final WorkspaceTabState tabs;
  final ValueChanged<WorkspaceTab> onSelect;
  final ValueChanged<WorkspaceTab> onClose;
  final VoidCallback onOpenOmnibox;

  /// Phones get a shorter bar: the lens switcher already sits below it.
  final bool compact;

  const WorkspaceTitleBar({
    super.key,
    required this.tabs,
    required this.onSelect,
    required this.onClose,
    required this.onOpenOmnibox,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    final name = workspace?.name.trim();
    final label = (name == null || name.isEmpty) ? 'SolWatt' : name;
    final barHeight = compact ? 40.0 : 50.0;
    final documents = tabs.tabs;

    return Material(
      color: scheme.surfaceContainerLow,
      // The bar is the topmost surface of the shell body, so on a phone it —
      // not the lens header below it — owns the status-bar strip.
      child: SafeArea(
        bottom: false,
        left: false,
        right: false,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Container(
            height: barHeight,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The workspace the app is in. Its avatar carries the identity
                // and its name is the tooltip, so the bar spends its width on
                // the documents instead of repeating a long string.
                Tooltip(
                  message: workspace == null
                      ? label
                      : '$label — tap to switch workspace',
                  child: InkWell(
                    onTap: () => showWorkspaceSwitcher(context, ref),
                    child: SizedBox(
                      width: 56,
                      height: 48,
                      child: Center(
                        child: CloudFileAvatar(
                          file: workspace?.picture,
                          fallbackIcon: Symbols.workspaces_rounded,
                          size: 32,
                          assumeImage: true,
                          borderRadius: workspace?.isIndividual == true
                              ? SolRadius.pillRadius
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: documents.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SolSpace.md,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'No open tabs',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: documents.length,
                          itemBuilder: (context, index) {
                            final tab = documents[index];
                            return _AnimatedTabSlot(
                              child: _TitleTab(
                                tab: tab,
                                selected: tabs.isActive(tab),
                                showDivider:
                                    index > 0 &&
                                    !tabs.isActive(documents[index - 1]) &&
                                    !tabs.isActive(tab),
                                onSelect: () => onSelect(tab),
                                // Pinned tabs are the lens destinations the
                                // rail switches between; only documents close.
                                onClose: tab.isRoot ? null : () => onClose(tab),
                              ),
                            );
                          },
                        ),
                ),
                if (documents.any((tab) => !tab.isRoot))
                  IconButton(
                    tooltip: 'Close all document tabs',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        documents.where((tab) => !tab.isRoot).forEach(onClose),
                    icon: Icon(
                      Symbols.clear_all_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                IconButton(
                  tooltip: 'Search — Cmd K or Ctrl K',
                  iconSize: 17,
                  visualDensity: VisualDensity.compact,
                  onPressed: onOpenOmnibox,
                  icon: Icon(
                    Symbols.search_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: SolSpace.xs),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The workspace picker the title bar's avatar opens: every workspace the
/// account can enter, with the active one ringed.
Future<void> showWorkspaceSwitcher(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _WorkspaceSwitcherSheet(),
  );
}

class _WorkspaceSwitcherSheet extends ConsumerWidget {
  const _WorkspaceSwitcherSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final workspaces = ref.watch(workspacesProvider).value ?? const [];
    final activeId = ref.watch(selectedWorkspaceProvider).value?.id;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SolSpace.xl,
                SolSpace.sm,
                SolSpace.xl,
                SolSpace.md,
              ),
              child: Text(
                'Switch workspace',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: workspaces.length,
                itemBuilder: (context, index) {
                  final workspace = workspaces[index];
                  final active = workspace.id == activeId;
                  return ListTile(
                    leading: CloudFileAvatar(
                      file: workspace.picture,
                      fallbackIcon: Symbols.workspaces_rounded,
                      size: 36,
                      assumeImage: true,
                      selected: active,
                      borderRadius: workspace.isIndividual
                          ? SolRadius.pillRadius
                          : null,
                    ),
                    title: Text(
                      workspace.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? scheme.primary : scheme.onSurface,
                      ),
                    ),
                    subtitle: Text(
                      workspace.slug,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: active
                        ? Icon(Symbols.check_rounded, color: scheme.primary)
                        : null,
                    onTap: active
                        ? () => Navigator.of(context).pop()
                        : () async {
                            Navigator.of(context).pop();
                            await activateWorkspaceAction(ref, workspace);
                          },
                  );
                },
              ),
            ),
            ListTile(
              leading: const Icon(Symbols.workspaces_rounded),
              title: const Text('Manage workspaces'),
              trailing: const Icon(Symbols.chevron_right),
              onTap: () {
                Navigator.of(context).pop();
                context.router.push(const WorkspaceManagementRoute());
              },
            ),
            const SizedBox(height: SolSpace.sm),
          ],
        ),
      ),
    );
  }
}

/// A tab slides and fades into the bar when it opens, and out again when it
/// closes, so a new document never just blinks into place beside the others.
class _AnimatedTabSlot extends StatelessWidget {
  final Widget child;

  const _AnimatedTabSlot({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(-10 * (1 - t), 0),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// One tab, painted like the drive's browser tabs: square, flat, selected tab
/// on the content surface with a primary accent on top.
class _TitleTab extends StatelessWidget {
  final WorkspaceTab tab;
  final bool selected;
  final bool showDivider;
  final VoidCallback onSelect;

  /// Null on a pinned lens tab: the rail owns that destination, so the bar
  /// does not offer to close it.
  final VoidCallback? onClose;

  const _TitleTab({
    required this.tab,
    required this.selected,
    required this.showDivider,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = scheme.outlineVariant.withValues(alpha: 0.55);

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 236),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onSelect,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: selected ? scheme.surface : Colors.transparent,
              border: Border(
                left: showDivider ? BorderSide(color: border) : BorderSide.none,
                top: selected
                    ? BorderSide(color: scheme.primary, width: 2)
                    : BorderSide.none,
                right: selected ? BorderSide(color: border) : BorderSide.none,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(SolSpace.md, 0, SolSpace.xs, 0),
            child: Row(
              children: [
                Icon(
                  tab.icon,
                  size: 16,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: SolSpace.sm),
                Expanded(
                  child: Text(
                    tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (onClose case final close?)
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      iconSize: 15,
                      tooltip: 'Close tab',
                      onPressed: close,
                      style: IconButton.styleFrom(
                        foregroundColor: scheme.onSurfaceVariant,
                        hoverColor: scheme.onSurface.withValues(alpha: 0.08),
                      ),
                      icon: const Icon(Symbols.close),
                    ),
                  )
                else
                  // A pinned tab keeps the button's width so every label sits
                  // on the same rhythm as the documents beside it.
                  const SizedBox(width: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
