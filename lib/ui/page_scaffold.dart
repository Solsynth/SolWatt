import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Global key of the shell's root scaffold, used by pages that bring their own
/// chrome (the drive file list's app bar) to open the navigation drawer.
///
/// The shell scaffold is a Flutter `Scaffold` — not the `material_ui` fork's —
/// so this key is typed against Flutter's `ScaffoldState` and must stay that
/// way: a key typed against the fork's `ScaffoldState` resolves to `null` for
/// the shell even while the shell is on screen.
final shellScaffoldKey = GlobalKey<ScaffoldState>();

/// Leading app-bar button for a page inside the tab's nested stack: Back once
/// the page sits above the tab's root (mail settings, the profile's settings),
/// the shell's drawer button at the root, or null where the app bar should
/// carry neither.
///
/// Must be called from a context *above* the page's own [Scaffold], so the
/// drawer lookup finds the shell's drawer rather than the page's drawer-less
/// scaffold. Wide screens return null: the rail already owns the drawer and
/// the app bar needs the room for its title.
Widget? appBarDrawerButton(BuildContext context) {
  if (isWideScreen(context)) return null;
  // Only this stack counts: a parent that could pop (the tabs or the root
  // router) is not what Back would pop, and the shell's root page has to keep
  // offering the drawer.
  if (context.router.canPop(ignoreParentRoutes: true)) {
    return BackButton(onPressed: () => context.router.maybePop());
  }
  final scaffold = Scaffold.maybeOf(context);
  if (scaffold == null || !scaffold.hasDrawer) return null;
  return IconButton(
    tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
    onPressed: scaffold.openDrawer,
    icon: const Icon(Symbols.menu),
  );
}

/// Shared page chrome: an app bar with the optional subtitle/actions, and a
/// constrained body.
///
/// Pages are rendered inside the shell's scaffold, so the app bar carries the
/// drawer button on narrow screens; app-level navigation never lives in the
/// bottom bar.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
    this.actions = const [],
    this.maxContentWidth = 960,
    this.padding = const EdgeInsets.fromLTRB(24, 16, 24, 24),
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;
  final List<Widget> actions;
  final double maxContentWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final trailing = <Widget>[?action, ...actions];

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        leading: appBarDrawerButton(context),
        // A subtitle needs a second line, which the default toolbar cannot
        // hold.
        toolbarHeight: subtitle == null ? null : 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (subtitle case final String subtitle)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
        actions: [
          for (final widget in trailing) ...[widget, const SizedBox(width: 4)],
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Centered empty/error state with optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.maxWidth = 360,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: scheme.onSecondaryContainer),
              ),
              const SizedBox(height: 20),
              Text(title, textAlign: TextAlign.center, style: text.titleMedium),
              if (message case final String message) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact section header for lists and grouped content.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: 12),
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Status / priority chip using MD3 tonal surfaces.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.icon,
    this.tone = StatusChipTone.neutral,
  });

  final String label;
  final IconData? icon;
  final StatusChipTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (tone) {
      StatusChipTone.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      StatusChipTone.primary => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      StatusChipTone.secondary => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      StatusChipTone.tertiary => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      StatusChipTone.error => (scheme.errorContainer, scheme.onErrorContainer),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

enum StatusChipTone { neutral, primary, secondary, tertiary, error }

/// Leading icon badge used on list rows and cards.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.selected = false,
    this.size = 40,
  });

  final IconData icon;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        size: size * 0.5,
        color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        fill: selected ? 1 : 0,
      ),
    );
  }
}

/// Shared loading indicator for full-pane async states.
class PageLoading extends StatelessWidget {
  const PageLoading({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

/// Shared error pane with retry.
class PageError extends StatelessWidget {
  const PageError({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Symbols.error,
      title: 'Something went wrong',
      message: message,
      action: onRetry == null
          ? null
          : OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Symbols.refresh, size: 18),
              label: const Text('Try again'),
            ),
    );
  }
}
