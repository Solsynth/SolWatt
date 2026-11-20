import 'package:flutter/material.dart';

import 'package:solwatt/theme.dart';

/// Fixed 52px workspace canvas header shared across Mail, Todo, Pages, Drive,
/// and the Peek Pane so switching lenses produces zero visual jarring.
class WorkspaceCanvasHeader extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final List<Widget> actions;
  final Color? backgroundColor;

  /// Inset around the title block. A header that heads a panel lines its title
  /// up with the rows below it; one that heads a canvas keeps the default.
  final EdgeInsetsGeometry? titlePadding;

  const WorkspaceCanvasHeader({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.backgroundColor,
    this.titlePadding,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: backgroundColor ?? scheme.surfaceContainerLow,
      child: SizedBox(
        height: SolWorkspaceGeometry.headerHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SolSpace.md),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: SolSpace.sm),
              ],
              Expanded(
                child: Padding(
                  padding:
                      titlePadding ?? const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DefaultTextStyle(
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ) ??
                            const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        child: title,
                      ),
                      if (subtitle != null)
                        DefaultTextStyle(
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ) ??
                              TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          child: subtitle!,
                        ),
                    ],
                  ),
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: SolSpace.sm),
                Row(mainAxisSize: MainAxisSize.min, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared list row enforcing identical density across all four lenses:
/// 40px compact / 52px two-line on desktop, 48px minimum touch target on
/// mobile.
class WorkspaceListRow extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const WorkspaceListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.selected = false,
    this.compact = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile =
        MediaQuery.sizeOf(context).width <
        SolWorkspaceGeometry.tabletBreakpoint;
    final minHeight = isMobile
        ? SolWorkspaceGeometry.mobileMinTouchTarget
        : (compact
              ? SolWorkspaceGeometry.desktopRowCompact
              : SolWorkspaceGeometry.desktopRowTwoLine);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(SolRadius.xs),
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: SolSpace.md,
          vertical: SolSpace.xs,
        ),
        decoration: BoxDecoration(
          color: selected
              ? scheme.secondaryContainer.withValues(alpha: 0.65)
              : null,
          borderRadius: BorderRadius.circular(SolRadius.xs),
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: SolSpace.md),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle(
                    style:
                        Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ) ??
                        const TextStyle(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: title,
                  ),
                  if (subtitle != null)
                    DefaultTextStyle(
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ) ??
                          TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: subtitle!,
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: SolSpace.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
