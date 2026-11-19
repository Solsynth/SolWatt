import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/pages/pages_provider.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/workspace/components/entity_card.dart';
import 'package:solwatt/workspace/components/related_items_strip.dart';
import 'package:solwatt/workspace/components/workspace_header.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_state.dart';

/// Shared Peek content rendered inside rounded Island color blocks:
/// - Desktop Zone 4: Resizable Right Peek Pane (380px–480px)
/// - Tablet: Docked Right Side Sheet (65% viewport width)
/// - Mobile: Layered DraggableScrollableSheet (0.62 initial, 0.95 max)
class PeekPanelContent extends ConsumerWidget {
  final WorkspaceEntityRef entity;
  final ScrollController? scrollController;
  final ValueChanged<WorkspaceEntityRef>? onOpenFullView;
  final bool showPopOut;

  const PeekPanelContent({
    super.key,
    required this.entity,
    this.scrollController,
    this.onOpenFullView,
    this.showPopOut = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final peek = ref.watch(peekProvider);
    final isPinned = ref
        .watch(pinnedItemsProvider)
        .any((p) => p.domain == entity.domain && p.id == entity.id);

    return Material(
      color: scheme.surfaceContainerLow,
      child: Column(
        children: [
          WorkspaceCanvasHeader(
            backgroundColor: scheme.surfaceContainer,
            leading: peek.canGoBack
                ? IconButton(
                    icon: const Icon(Symbols.arrow_back_rounded, size: 18),
                    tooltip: 'Back in Peek',
                    onPressed: () => ref.read(peekProvider.notifier).back(),
                  )
                : Icon(entity.domain.icon, size: 18, color: scheme.primary),
            title: Text(entity.title),
            subtitle: Text(entity.domain.label),
            actions: [
              IconButton(
                tooltip: isPinned ? 'Unpin' : 'Pin',
                icon: Icon(
                  Symbols.push_pin_rounded,
                  fill: isPinned ? 1 : 0,
                  size: 18,
                ),
                onPressed: () =>
                    ref.read(pinnedItemsProvider.notifier).togglePin(entity),
              ),
              if (showPopOut)
                IconButton(
                  tooltip: 'Pop Out',
                  icon: const Icon(Symbols.open_in_new_rounded, size: 18),
                  onPressed: () => _popOutWindow(context, entity),
                ),
              if (onOpenFullView != null)
                IconButton(
                  tooltip: 'Open in Full View',
                  icon: const Icon(Symbols.fullscreen_rounded, size: 18),
                  onPressed: () {
                    ref.read(peekProvider.notifier).close();
                    onOpenFullView!(entity);
                  },
                ),
              IconButton(
                tooltip: 'Close Peek — Esc',
                icon: const Icon(Symbols.close_rounded, size: 18),
                onPressed: () => ref.read(peekProvider.notifier).close(),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(SolSpace.lg),
              children: [
                _PeekBody(entity: entity, onOpenFullView: onOpenFullView),
                const SizedBox(height: SolSpace.xl),
                RelatedItemsStrip(entity: entity, onSwitchLens: onOpenFullView),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _popOutWindow(BuildContext context, WorkspaceEntityRef entity) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SolRadius.lg),
        ),
        child: SizedBox(
          width: 520,
          height: 620,
          child: PeekPanelContent(
            entity: entity,
            onOpenFullView: onOpenFullView,
          ),
        ),
      ),
    );
  }
}

class _PeekBody extends ConsumerWidget {
  final WorkspaceEntityRef entity;
  final ValueChanged<WorkspaceEntityRef>? onOpenFullView;

  const _PeekBody({required this.entity, this.onOpenFullView});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final pages = ref.watch(pagesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EntityCard(
          entity: entity,
          onToggleComplete:
              entity.domain == WorkspaceDomain.todo &&
                  entity.metadata['isBoard'] != true
              ? () async {
                  final nextCompleted = !entity.isCompleted;
                  final updated = entity.copyWith(
                    isCompleted: nextCompleted,
                    status: nextCompleted ? 'Completed' : 'Open',
                  );
                  ref.read(peekProvider.notifier).updateCurrentEntity(updated);
                  final broadId = entity.metadata['broadId'] as String?;
                  try {
                    await ref
                        .read(wattEngineClientProvider)
                        .updateTask(
                          entity.id,
                          WorkTaskDraft(name: entity.title),
                        );
                    if (broadId != null) {
                      ref.invalidate(
                        tasksProvider(TaskListRequest(broadId: broadId)),
                      );
                    }
                  } catch (_) {
                    // Revert optimistic state if network fails.
                    ref.read(peekProvider.notifier).updateCurrentEntity(entity);
                  }
                }
              : null,
        ),
        const SizedBox(height: SolSpace.lg),
        if (entity.domain == WorkspaceDomain.mail) ...[
          _MailThreadPreview(threadId: entity.id),
        ] else if (entity.domain == WorkspaceDomain.todo &&
            entity.metadata['isBoard'] == true) ...[
          _BoardTasksPreview(broadId: entity.id),
        ] else if (entity.domain == WorkspaceDomain.pages) ...[
          for (final page in pages.where((p) => p.id == entity.id)) ...[
            for (final block in page.blocks)
              Padding(
                padding: const EdgeInsets.only(bottom: SolSpace.sm),
                child:
                    block.type.name == 'entityEmbed' &&
                        block.embeddedEntity != null
                    ? EntityCard(entity: block.embeddedEntity!, compact: true)
                    : Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(SolSpace.md),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(SolRadius.sm),
                        ),
                        child: Text(
                          block.text.isEmpty ? ' ' : block.text,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
              ),
          ],
        ] else if (entity.subtitle != null && entity.subtitle!.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(SolSpace.md),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(SolRadius.sm),
            ),
            child: Text(
              entity.subtitle!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
        const SizedBox(height: SolSpace.md),
        if (onOpenFullView != null)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () {
                ref.read(peekProvider.notifier).close();
                onOpenFullView!(entity);
              },
              icon: const Icon(Symbols.open_in_full_rounded, size: 16),
              label: Text('Open in ${entity.domain.label}'),
            ),
          ),
      ],
    );
  }
}

class _MailThreadPreview extends ConsumerWidget {
  final String threadId;

  const _MailThreadPreview({required this.threadId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final threadAsync = ref.watch(threadProvider(threadId));
    return threadAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(SolSpace.md),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (emails) => Column(
        children: [
          for (final email in emails.take(5))
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: SolSpace.sm),
              padding: const EdgeInsets.all(SolSpace.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(SolRadius.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    email.from?.name ?? email.from?.address ?? 'Unknown sender',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: SolSpace.xs),
                  Text(
                    email.body.replaceAll(RegExp(r'<[^>]*>'), ' ').trim(),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BoardTasksPreview extends ConsumerWidget {
  final String broadId;

  const _BoardTasksPreview({required this.broadId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(
      tasksProvider(TaskListRequest(broadId: broadId)),
    );
    return tasksAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(SolSpace.md),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (tasks) => Column(
        children: [
          for (final task in tasks.take(8)) ...[
            EntityCard(
              compact: true,
              entity: WorkspaceEntityRef(
                id: task.id,
                domain: WorkspaceDomain.todo,
                title: task.name,
                subtitle: task.description,
                isCompleted: task.completedAt != null,
                status: task.completedAt != null ? 'Completed' : 'Open',
                metadata: {'broadId': broadId, 'taskId': task.id},
              ),
            ),
            const SizedBox(height: SolSpace.xs),
          ],
        ],
      ),
    );
  }
}

/// Desktop Zone 4: Resizable Right Peek Pane (380px–480px) rendered as a
/// rounded Island color block.
class DesktopPeekPane extends ConsumerWidget {
  final ValueChanged<WorkspaceEntityRef>? onOpenFullView;

  const DesktopPeekPane({super.key, this.onOpenFullView});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peek = ref.watch(peekProvider);
    final current = peek.current;
    if (current == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (details) {
              ref
                  .read(peekProvider.notifier)
                  .setDesktopWidth(peek.desktopWidth - details.delta.dx);
            },
            child: const SizedBox(width: SolSpace.sm),
          ),
        ),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => SizedBox(
            width: peek.desktopWidth * t,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: peek.desktopWidth,
                maxWidth: peek.desktopWidth,
                child: Opacity(opacity: t, child: child),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SolRadius.md),
            child: PeekPanelContent(
              key: ValueKey(current.key),
              entity: current,
              showPopOut: true,
              onOpenFullView: onOpenFullView,
            ),
          ),
        ),
      ],
    );
  }
}

/// Tablet (600px–1024px): Docked Right Side Sheet (65% viewport width) over
/// a dimmed primary canvas with rounded Island corners.
class TabletPeekSheet extends ConsumerWidget {
  final ValueChanged<WorkspaceEntityRef>? onOpenFullView;

  const TabletPeekSheet({super.key, this.onOpenFullView});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peek = ref.watch(peekProvider);
    final current = peek.current;
    if (current == null) return const SizedBox.shrink();
    final width = MediaQuery.sizeOf(context).width * 0.65;

    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => ref.read(peekProvider.notifier).close(),
            child: Container(color: Colors.black38),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.all(SolSpace.sm),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) => Transform.translate(
                  offset: Offset(width * 0.25 * (1 - t), 0),
                  child: Opacity(opacity: t, child: child),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(SolRadius.lg),
                  child: Material(
                    elevation: 12,
                    child: SizedBox(
                      width: width,
                      height: double.infinity,
                      child: PeekPanelContent(
                        key: ValueKey(current.key),
                        entity: current,
                        onOpenFullView: onOpenFullView,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mobile (< 600px): Layered DraggableScrollableSheet (initial snap 0.62,
/// max 0.95), keeping the underlying 52px header visible above the sheet.
class MobilePeekSheet extends ConsumerWidget {
  final ValueChanged<WorkspaceEntityRef>? onOpenFullView;

  const MobilePeekSheet({super.key, this.onOpenFullView});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peek = ref.watch(peekProvider);
    final current = peek.current;
    if (current == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Positioned.fill(
      top:
          MediaQuery.paddingOf(context).top + SolWorkspaceGeometry.headerHeight,
      child: NotificationListener<DraggableScrollableNotification>(
        onNotification: (notification) {
          if (notification.extent <= 0.25) {
            ref.read(peekProvider.notifier).close();
          }
          return false;
        },
        child: DraggableScrollableSheet(
          initialChildSize: 0.62,
          minChildSize: 0.2,
          maxChildSize: 0.95,
          snap: true,
          snapSizes: const [0.62, 0.95],
          builder: (context, scrollController) {
            return Material(
              elevation: 12,
              color: scheme.surfaceContainerLow,
              shape: const RoundedRectangleBorder(
                borderRadius: SolRadius.sheetRadius,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  const SizedBox(height: SolSpace.sm),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: SolRadius.pillRadius,
                    ),
                  ),
                  Expanded(
                    child: PeekPanelContent(
                      entity: current,
                      scrollController: scrollController,
                      onOpenFullView: onOpenFullView,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
