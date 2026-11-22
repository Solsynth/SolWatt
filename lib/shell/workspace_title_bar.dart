import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/workspaces/workspace_actions.dart';
import 'package:solwatt/shell/workspace_tabs.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/ui/cloud_files.dart';

/// The strip of documents open in the workspace.
///
/// It follows MaidKit's strip: the bar is the paper, and the selected tab is a
/// raised tone on it — no accent rule, no outline, no border against the
/// canvas below. The workspace itself lives on the rail, so the bar spends its
/// whole width on documents.
///
/// With nothing open the strip is not chrome at all: it collapses to nothing
/// so the canvas starts where the rail's top does. A [leading] widget — the
/// phone's lens switcher — keeps the bar up even with no documents, so narrow
/// screens stack one band instead of two.
class WorkspaceTitleBar extends ConsumerWidget {
  final WorkspaceTabState tabs;
  final ValueChanged<WorkspaceTab> onSelect;
  final ValueChanged<WorkspaceTab> onClose;
  final VoidCallback? onSelectHome;
  final VoidCallback onOpenOmnibox;

  /// Sits before the home chip: on a phone it is the lens switcher, merged
  /// into the strip so the lens header no longer costs a band of its own.
  final Widget? leading;

  /// Phones get a shorter bar.
  final bool compact;

  const WorkspaceTitleBar({
    super.key,
    required this.tabs,
    required this.onSelect,
    required this.onClose,
    this.onSelectHome,
    required this.onOpenOmnibox,
    this.leading,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final barHeight = compact ? 40.0 : 50.0;
    final documents = tabs.tabs;
    // A phone's status bar belongs to the topmost band, so an empty strip
    // still reserves that inset even though it draws nothing.
    final topInset = MediaQuery.paddingOf(context).top;
    // Even collapsed the strip keeps one step of air on desktop/tablet so the
    // canvas never sits flush against the top edge of the body. On narrow
    // screens (compact), the lens switcher leads the bar, so the bar is always
    // up and the switcher claims the status-bar inset.
    final collapsedHeight = compact ? topInset : topInset + SolSpace.sm;
    // With a leading widget the bar is the phone's only top band: it stays up
    // even when no document owns the strip.
    final showsBar = documents.isNotEmpty || leading != null;

    final barColor = compact ? scheme.surface : scheme.surfaceContainerLowest;
    final selectedTabColor = compact ? scheme.surfaceContainer : scheme.surface;

    return Material(
      color: barColor,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: !showsBar
            ? SizedBox(height: collapsedHeight, width: double.infinity)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (topInset > 0) SizedBox(height: topInset),
                  SizedBox(
                    height: barHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(width: SolSpace.sm),
                        if (leading != null) ...[
                          Center(child: leading!),
                          const SizedBox(width: SolSpace.xs),
                        ],
                        if (documents.isNotEmpty)
                          _HomeTab(
                            height: barHeight,
                            selected: !tabs.showsDocument,
                            selectedColor: selectedTabColor,
                            onSelect: onSelectHome,
                          ),
                        Expanded(
                          child: documents.isEmpty
                              ? const SizedBox.shrink()
                              : SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.only(
                                    right: SolSpace.sm,
                                  ),
                                  // Chips take the width their titles need and
                                  // no more: the strip stays scannable instead
                                  // of dividing the bar into mostly empty
                                  // slices.
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (final tab in documents)
                                        _AnimatedTabSlot(
                                          child: _TitleTab(
                                            tab: tab,
                                            height: barHeight,
                                            compact: compact,
                                            selected: tabs.isActive(tab),
                                            selectedColor: selectedTabColor,
                                            onSelect: () => onSelect(tab),
                                            onClose: () => onClose(tab),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                        ),
                        if (documents.isNotEmpty)
                          IconButton(
                            tooltip: 'closeAllTabs'.tr(),
                            iconSize: 16,
                            visualDensity: VisualDensity.compact,
                            onPressed: () => documents.forEach(onClose),
                            icon: Icon(
                              Symbols.clear_all_rounded,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        IconButton(
                          tooltip: 'omniboxTooltip'.tr(),
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
                ],
              ),
      ),
    );
  }
}

/// The workspace picker the rail's avatar opens: every workspace the account
/// can enter, with the active one ringed.
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
                'switchWorkspaceTitle'.tr(),
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

/// Pinned home tab representing the active lens's non-tabbed root contents
/// whenever the document strip is shown.
class _HomeTab extends StatelessWidget {
  final double height;
  final bool selected;
  final Color selectedColor;
  final VoidCallback? onSelect;

  const _HomeTab({
    required this.height,
    required this.selected,
    required this.selectedColor,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(SolRadius.xs);

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Tooltip(
          message: 'home'.tr(),
          child: Material(
            type: MaterialType.canvas,
            color: selected ? selectedColor : Colors.transparent,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onSelect,
              borderRadius: radius,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SolSpace.sm + 2,
                ),
                child: Center(
                  child: Icon(
                    Symbols.home_rounded,
                    size: 16,
                    fill: selected ? 1 : 0,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One tab, cut from the bar's paper: transparent until selected, when it
/// takes the raised surface tone the chips in MaidKit's strip use.
class _TitleTab extends StatelessWidget {
  final WorkspaceTab tab;
  final bool selected;
  final bool compact;
  final Color selectedColor;

  /// Height of the bar the chip sits in; the chip insets itself from it.
  final double height;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  const _TitleTab({
    required this.tab,
    required this.selected,
    required this.compact,
    required this.selectedColor,
    required this.height,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(SolRadius.xs);

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Material(
          type: MaterialType.canvas,
          color: selected ? selectedColor : Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onSelect,
            borderRadius: radius,
            // The right inset is the gap before the close button; the title
            // keeps the same air on its left so the label never sits flush
            // against the chip edge.
            child: Padding(
              padding: const EdgeInsets.only(
                left: SolSpace.sm + 2,
                right: SolSpace.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    tab.icon,
                    size: 16,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: SolSpace.sm - 2),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: compact ? 104 : 240),
                    child: Text(
                      tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: SolSpace.sm),
                  IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    iconSize: 15,
                    tooltip: 'closeTab'.tr(),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(24, 24),
                      maximumSize: const Size(24, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: scheme.onSurfaceVariant,
                      hoverColor: scheme.onSurface.withValues(alpha: 0.08),
                    ),
                    onPressed: onClose,
                    icon: const Icon(Symbols.close),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
