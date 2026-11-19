import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/shell/workspace_tabs.dart';
import 'package:solwatt/theme.dart';

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
    final name = ref.watch(selectedWorkspaceProvider).value?.name.trim();
    final workspace = (name == null || name.isEmpty) ? 'SolWatt' : name;
    final barHeight = compact ? 40.0 : 42.0;
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
                Padding(
                  padding: const EdgeInsets.only(
                    left: SolSpace.lg,
                    right: SolSpace.md,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.workspaces_rounded,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: SolSpace.sm),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Text(
                          workspace,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.55),
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
                                onClose: () => onClose(tab),
                              ),
                            );
                          },
                        ),
                ),
                if (documents.isNotEmpty)
                  IconButton(
                    tooltip: 'Close all tabs',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => documents.forEach(onClose),
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
  final VoidCallback onClose;

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
                if (!tab.isRoot)
                  SizedBox(
                    width: 26,
                    height: 26,
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
    );
  }
}
