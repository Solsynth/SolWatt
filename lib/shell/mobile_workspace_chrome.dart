import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/ideask/ideask_page.dart';
import 'package:solwatt/drive/favorites.dart';
import 'package:solwatt/drive/usage.dart';
import 'package:solwatt/drive/widgets/drive_pane_switch.dart';
import 'package:solwatt/drive/widgets/storage_meter.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/route.dart';
import 'package:solwatt/shared/widgets/pill_surface.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/workspace/components/workspace_header.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_state.dart';

/// The lens switcher pill a phone's title bar leads with: the active lens'
/// name, with the workspace/favorites/lens sheet behind it.
class MobileLensSwitcher extends ConsumerWidget {
  final WorkspaceLens activeLens;
  final ValueChanged<WorkspaceLens> onSelectLens;

  const MobileLensSwitcher({
    super.key,
    required this.activeLens,
    required this.onSelectLens,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      key: const ValueKey('lens-switcher'),
      borderRadius: SolRadius.pillRadius,
      onTap: () => _showWorkspaceSwitcherSheet(context, ref),
      child: PillSurface(
        t: 0.85,
        radius: SolRadius.pillRadius,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SolSpace.md,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(activeLens.icon, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            // The strip keeps the tabs' room: a longer lens name truncates
            // rather than pushing the open documents off screen.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 88),
              child: Text(
                activeLens.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Symbols.arrow_drop_down_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  void _showWorkspaceSwitcherSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => _WorkspaceSwitcherSheet(
        activeLens: activeLens,
        onSelectLens: (lens) {
          Navigator.of(ctx).pop();
          onSelectLens(lens);
        },
      ),
    );
  }
}

class _WorkspaceSwitcherSheet extends ConsumerWidget {
  final WorkspaceLens activeLens;
  final ValueChanged<WorkspaceLens> onSelectLens;

  const _WorkspaceSwitcherSheet({
    required this.activeLens,
    required this.onSelectLens,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final localFavorites = ref.watch(favoritesProvider);
    final driveFavorites =
        ref.watch(driveFavoriteEntitiesProvider).value ?? const [];
    final favorites = [
      ...localFavorites.where((item) => item.domain != WorkspaceDomain.drive),
      ...driveFavorites,
    ];
    final recent = ref.watch(recentEntitiesProvider);
    final workspace = ref.watch(selectedWorkspaceProvider).value;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.45,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(
          SolSpace.lg,
          0,
          SolSpace.lg,
          SolSpace.xxl,
        ),
        children: [
          Row(
            children: [
              Text(
                workspace?.name ?? 'workspace'.tr(),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.router.push(const WorkspaceManagementRoute());
                },
                icon: const Icon(Symbols.swap_horiz_rounded, size: 16),
                label: Text('switch'.tr()),
              ),
            ],
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: SolSpace.md),
            Text(
              'recent'.tr().toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: SolSpace.xs),
            for (final item in recent.take(4))
              WorkspaceListRow(
                leading: Icon(item.domain.icon, size: 18),
                title: Text(item.title),
                subtitle: Text(item.domain.label),
                onTap: () {
                  Navigator.of(context).pop();
                  ref.read(peekProvider.notifier).open(item);
                },
              ),
          ],
          const SizedBox(height: SolSpace.md),
          Text(
            'favorites'.tr(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: SolSpace.xs),
          if (favorites.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SolSpace.sm),
              child: Text(
                'noFavoritesHint'.tr(),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          else
            for (final item in favorites)
              WorkspaceListRow(
                leading: Icon(
                  item.domain.icon,
                  size: 18,
                  color: scheme.primary,
                ),
                title: Text(item.title),
                subtitle: Text(item.domain.label),
                onTap: () {
                  Navigator.of(context).pop();
                  ref.read(peekProvider.notifier).open(item);
                },
              ),
          const SizedBox(height: SolSpace.md),
          Text(
            'lenses'.tr().toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: SolSpace.xs),
          for (final lens in [
            WorkspaceLens.mail,
            WorkspaceLens.todo,
            WorkspaceLens.drive,
          ])
            WorkspaceListRow(
              selected: activeLens == lens,
              leading: Icon(lens.icon, size: 20),
              title: Text(lens.label),
              onTap: () => onSelectLens(lens),
            ),
          if (activeLens == WorkspaceLens.drive) ...[
            const SizedBox(height: SolSpace.md),
            const _DriveSheetControls(),
          ],
          const SizedBox(height: SolSpace.lg),
          for (final lens in [
            WorkspaceLens.flywheel,
            WorkspaceLens.profile,
            WorkspaceLens.settings,
          ])
            WorkspaceListRow(
              selected: activeLens == lens,
              leading: Icon(lens.icon, size: 20),
              title: Text(lens.label),
              onTap: () => onSelectLens(lens),
            ),
        ],
      ),
    );
  }
}

/// Mobile (< 600px) Floating Bottom Action Pill (Omnibox 75% + Create 25%)
/// positioned 16px above the bottom safe area using Solian's [PillSurface].
class MobileFloatingActionPill extends ConsumerWidget {
  /// Vertical space from the bottom safe area to the top edge of the pill
  /// (`16px` bottom margin + `56px` pill height).
  static const double bottomClearance = 72;

  final VoidCallback onOpenOmnibox;
  final ValueChanged<WorkspaceLens> onSelectLens;

  const MobileFloatingActionPill({
    super.key,
    required this.onOpenOmnibox,
    required this.onSelectLens,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;

    return Positioned(
      left: SolSpace.lg,
      right: SolSpace.lg,
      bottom: bottomSafe + 16,
      child: PillSurface(
        t: 1.0,
        radius: SolRadius.pillRadius,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SolSpace.sm,
          vertical: 6,
        ),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              // Left (75%): Search mail, tasks, pages, files...
              Expanded(
                flex: 3,
                child: InkWell(
                  borderRadius: SolRadius.pillRadius,
                  onTap: onOpenOmnibox,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SolSpace.md,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Symbols.search_rounded,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: SolSpace.sm),
                        Expanded(
                          child: Text(
                            'searchPlaceholder'.tr(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: SolSpace.xs),
              // Right (25%): Primary + button
              Expanded(
                flex: 1,
                child: FilledButton.icon(
                  onPressed: () => _showQuickCreateSheet(context, ref),
                  icon: const Icon(Symbols.add_rounded, size: 18),
                  label: Text('new'.tr()),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 40),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuickCreateSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.add_rounded),
              title: Text('newFolderPageCollection'.tr()),
              onTap: () {
                Navigator.of(ctx).pop();
                onSelectLens(WorkspaceLens.todo);
                showIdeaskCreateSheet(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Symbols.mail_rounded),
              title: Text('composeEmail'.tr()),
              onTap: () {
                Navigator.of(ctx).pop();
                onSelectLens(WorkspaceLens.mail);
                context.router.push(MailComposeRoute());
              },
            ),
            ListTile(
              leading: const Icon(Symbols.check_box_rounded),
              title: Text('openTodo'.tr()),
              onTap: () {
                Navigator.of(ctx).pop();
                onSelectLens(WorkspaceLens.todo);
              },
            ),
            ListTile(
              leading: const Icon(Symbols.cloud_upload_rounded),
              title: Text('openDrive'.tr()),
              onTap: () {
                Navigator.of(ctx).pop();
                onSelectLens(WorkspaceLens.drive);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The drive controls the desktop sidebar carries, for the phone switcher
/// sheet: the pane switch and the storage meter. The drawer closes after a
/// pane choice so the browser underneath is what the reader sees.
class _DriveSheetControls extends ConsumerWidget {
  const _DriveSheetControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(driveBrowseModeProvider);
    final storage = ref.watch(driveStorageUsageProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DrivePaneSwitch(
          mode: mode,
          onSelect: (mode) {
            ref.read(driveBrowseModeProvider.notifier).select(mode);
            Navigator.of(context).pop();
          },
        ),
        if (storage != null) ...[
          const SizedBox(height: SolSpace.md),
          InkWell(
            borderRadius: BorderRadius.circular(SolRadius.xs),
            onTap: () => showDriveUsageSheet(context, storage),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SolSpace.xs,
                vertical: SolSpace.xs,
              ),
              child: DriveStorageMeter(storage: storage),
            ),
          ),
        ],
      ],
    );
  }
}
