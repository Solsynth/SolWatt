import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/ui/cloud_files.dart';
import 'package:solwatt/ui/page_scaffold.dart';

@RoutePage()
class BoardsPage extends ConsumerWidget {
  const BoardsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boards = ref.watch(broadsProvider);
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return PageScaffold(
      title: 'Boards',
      subtitle: workspace == null ? 'Ideask boards' : 'In ${workspace.name}',
      action: FilledButton.tonalIcon(
        onPressed: () => _boardForm(context, ref),
        icon: const Icon(Symbols.add, size: 18),
        label: const Text('New board'),
      ),
      child: boards.when(
        loading: () => const PageLoading(),
        error: (error, _) => PageError(
          message: error.toString(),
          onRetry: () => ref.invalidate(broadsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Symbols.view_kanban,
              title: 'No boards yet',
              message: 'Create a board to organize tasks in this workspace.',
              action: FilledButton.icon(
                onPressed: () => _boardForm(context, ref),
                icon: const Icon(Symbols.add),
                label: const Text('New board'),
              ),
            );
          }

          if (wide) {
            return GridView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.55,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final board = items[index];
                return _BoardCard(
                  board: board,
                  onOpen: () => _openBoard(context, board),
                  onEdit: () => _boardForm(context, ref, board: board),
                );
              },
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final board = items[index];
              return Card(
                child: ListTile(
                  leading: CloudFileAvatar(
                    file: board.iconImage,
                    fallbackIcon: Symbols.view_kanban,
                    size: 40,
                  ),
                  title: Text(board.name),
                  subtitle: board.description?.isNotEmpty == true
                      ? Text(
                          board.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  trailing: PopupMenuButton<String>(
                    icon: Icon(
                      Symbols.more_vert,
                      color: scheme.onSurfaceVariant,
                    ),
                    onSelected: (value) {
                      if (value == 'open') _openBoard(context, board);
                      if (value == 'edit') {
                        _boardForm(context, ref, board: board);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'open', child: Text('Open')),
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                    ],
                  ),
                  onTap: () => _openBoard(context, board),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _openBoard(BuildContext context, Broad board) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskBoardPage(broadId: board.id, broadName: board.name),
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.board,
    required this.onOpen,
    required this.onEdit,
  });

  final Broad board;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final backgroundUrl = board.backgroundImage == null
        ? null
        : cloudFileDisplayUrl(board.backgroundImage!);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onEdit,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (backgroundUrl != null)
              Image.network(
                backgroundUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            if (backgroundUrl != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      scheme.surface.withValues(alpha: 0.15),
                      scheme.surface.withValues(alpha: 0.92),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CloudFileAvatar(
                        file: board.iconImage,
                        fallbackIcon: Symbols.view_kanban,
                        size: 40,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Edit board',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Symbols.edit,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                        onPressed: onEdit,
                      ),
                      Icon(
                        Symbols.arrow_outward,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    board.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium,
                  ),
                  if (board.description?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      board.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

@RoutePage()
class TaskBoardPage extends ConsumerStatefulWidget {
  const TaskBoardPage({
    super.key,
    @PathParam('broadId') required this.broadId,
    required this.broadName,
  });

  final String broadId;
  final String broadName;

  @override
  ConsumerState<TaskBoardPage> createState() => _TaskBoardPageState();
}

class _TaskBoardPageState extends ConsumerState<TaskBoardPage> {
  /// Optimistic group placement while a move API request is in flight.
  /// Key: task id, value: target group id (`null` = Ungrouped).
  final Map<String, String?> _groupOverrides = {};

  String get _broadId => widget.broadId;

  List<WorkTask> _effectiveTasks(List<WorkTask> serverTasks) {
    if (_groupOverrides.isEmpty) return serverTasks;
    return [
      for (final task in serverTasks)
        if (_groupOverrides.containsKey(task.id))
          task.withGroupId(_groupOverrides[task.id])
        else
          task,
    ];
  }

  Future<void> _onMoveTask(WorkTask task, String? targetGroupId) async {
    final alreadyThere = targetGroupId == null
        ? task.groupId == null
        : task.groupId == targetGroupId;
    if (alreadyThere) return;

    // Paint the new column immediately; do not wait for the network.
    setState(() => _groupOverrides[task.id] = targetGroupId);

    try {
      await ref
          .read(wattEngineClientProvider)
          .updateTask(
            task.id,
            WorkTaskDraft(
              name: task.name,
              description: task.displayDescription,
              content: task.displayContent,
              priority: task.priority,
              attachmentIds: task.attachments.map((file) => file.id).toList(),
              tags: task.tags,
              deadlineAt: task.deadlineAt,
              completeReason: task.completeReason,
              groupId: targetGroupId,
              ungroup: targetGroupId == null ? true : null,
            ),
          );
      // Refresh server data, then drop the override once it matches.
      ref.invalidate(tasksProvider(_broadId));
      await ref.read(tasksProvider(_broadId).future);
      if (!mounted) return;
      setState(() => _groupOverrides.remove(task.id));
    } catch (error) {
      if (!mounted) return;
      // Drop the optimistic override so the card returns to server state.
      setState(() => _groupOverrides.remove(task.id));
      showSnackBar(error.toString());
      ref.invalidate(tasksProvider(_broadId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider(_broadId));
    final groups = ref.watch(taskGroupsProvider(_broadId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(widget.broadName),
        actions: [
          IconButton(
            icon: const Icon(Symbols.view_column),
            tooltip: 'Manage groups',
            onPressed: () => _manageGroups(context, ref, _broadId),
          ),
          IconButton.filledTonal(
            icon: const Icon(Symbols.add_task),
            tooltip: 'New task',
            onPressed: () => _taskForm(context, ref, _broadId),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: tasks.when(
        loading: () => const PageLoading(),
        error: (error, _) => PageError(
          message: error.toString(),
          onRetry: () {
            ref.invalidate(tasksProvider(_broadId));
            ref.invalidate(taskGroupsProvider(_broadId));
          },
        ),
        data: (taskItems) {
          return groups.when(
            loading: () => const PageLoading(),
            error: (error, _) => PageError(
              message: error.toString(),
              onRetry: () => ref.invalidate(taskGroupsProvider(_broadId)),
            ),
            data: (groupItems) {
              final effective = _effectiveTasks(taskItems);
              if (effective.isEmpty && groupItems.isEmpty) {
                return EmptyState(
                  icon: Symbols.task_alt,
                  title: 'No tasks yet',
                  message: 'Add a task or create groups for this board.',
                  action: FilledButton.icon(
                    onPressed: () => _taskForm(context, ref, _broadId),
                    icon: const Icon(Symbols.add_task),
                    label: const Text('New task'),
                  ),
                );
              }

              final columns = _buildColumns(groupItems, effective);
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                itemCount: columns.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final column = columns[index];
                  return _TaskGroupColumn(
                    title: column.title,
                    groupId: column.groupId,
                    isUngrouped: column.isUngrouped,
                    tasks: column.tasks,
                    onOpenTask: (task) =>
                        _taskForm(context, ref, _broadId, task: task),
                    onToggleComplete: (task) =>
                        _toggleTaskComplete(context, ref, _broadId, task),
                    onDeleteTask: (task) =>
                        _deleteTask(context, ref, _broadId, task),
                    onMoveTask: (task) => _onMoveTask(task, column.groupId),
                    onAddTask: () => _taskForm(
                      context,
                      ref,
                      _broadId,
                      initialGroupId: column.groupId,
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _TaskColumn {
  const _TaskColumn({
    required this.title,
    required this.tasks,
    this.groupId,
    this.isUngrouped = false,
  });

  final String title;
  final List<WorkTask> tasks;
  final String? groupId;
  final bool isUngrouped;
}

/// Ungrouped first (leftmost), then groups in position order.
List<_TaskColumn> _buildColumns(List<TaskGroup> groups, List<WorkTask> tasks) {
  final groupIds = {for (final group in groups) group.id};
  final byGroup = <String, List<WorkTask>>{};
  final ungrouped = <WorkTask>[];

  for (final task in tasks) {
    final groupId = task.groupId;
    if (groupId == null || !groupIds.contains(groupId)) {
      ungrouped.add(task);
    } else {
      byGroup.putIfAbsent(groupId, () => []).add(task);
    }
  }

  return [
    _TaskColumn(title: 'Ungrouped', tasks: ungrouped, isUngrouped: true),
    for (final group in groups)
      _TaskColumn(
        title: group.name,
        groupId: group.id,
        tasks: byGroup[group.id] ?? const [],
      ),
  ];
}

class _TaskGroupColumn extends StatelessWidget {
  const _TaskGroupColumn({
    required this.title,
    required this.groupId,
    required this.tasks,
    required this.isUngrouped,
    required this.onOpenTask,
    required this.onToggleComplete,
    required this.onDeleteTask,
    required this.onMoveTask,
    required this.onAddTask,
  });

  final String title;
  final String? groupId;
  final List<WorkTask> tasks;
  final bool isUngrouped;
  final ValueChanged<WorkTask> onOpenTask;
  final ValueChanged<WorkTask> onToggleComplete;
  final ValueChanged<WorkTask> onDeleteTask;
  final ValueChanged<WorkTask> onMoveTask;
  final VoidCallback onAddTask;

  static const double _width = 320;

  bool _accepts(WorkTask task) {
    if (isUngrouped) return task.groupId != null;
    return task.groupId != groupId;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return DragTarget<WorkTask>(
      onWillAcceptWithDetails: (details) => _accepts(details.data),
      onAcceptWithDetails: (details) => onMoveTask(details.data),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return SizedBox(
          width: _width,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: hovering
                  ? scheme.primaryContainer.withValues(alpha: 0.45)
                  : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hovering
                    ? scheme.primary.withValues(alpha: 0.55)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                  child: Row(
                    children: [
                      Icon(
                        isUngrouped ? Symbols.inbox : Symbols.folder,
                        size: 18,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${tasks.length}',
                          style: text.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Add task',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Symbols.add, size: 20),
                        onPressed: onAddTask,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: tasks.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              hovering
                                  ? 'Drop task here'
                                  : isUngrouped
                                  ? 'No ungrouped tasks'
                                  : 'No tasks in this group',
                              textAlign: TextAlign.center,
                              style: text.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                          itemCount: tasks.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final task = tasks[index];
                            return _DraggableTaskCard(
                              task: task,
                              onOpen: () => onOpenTask(task),
                              onToggleComplete: () => onToggleComplete(task),
                              onDelete: () => onDeleteTask(task),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DraggableTaskCard extends StatelessWidget {
  const _DraggableTaskCard({
    required this.task,
    required this.onOpen,
    required this.onToggleComplete,
    required this.onDelete,
  });

  final WorkTask task;
  final VoidCallback onOpen;
  final VoidCallback onToggleComplete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tile = _TaskTile(
      task: task,
      compact: true,
      onOpen: onOpen,
      onToggleComplete: onToggleComplete,
      onDelete: onDelete,
    );

    // Immediate drag (desktop-first). Long-press still works via the same path.
    return Draggable<WorkTask>(
      data: task,
      maxSimultaneousDrags: 1,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: Colors.transparent,
        child: SizedBox(
          width: _TaskGroupColumn._width - 20,
          child: Opacity(opacity: 0.92, child: tile),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: IgnorePointer(child: tile),
      ),
      child: tile,
    );
  }
}

Future<void> _toggleTaskComplete(
  BuildContext context,
  WidgetRef ref,
  String broadId,
  WorkTask task,
) async {
  final complete = !task.isCompleted;
  try {
    // completeReason 0 = Completed. Null (omitted in JSON) reopens the task.
    await ref
        .read(wattEngineClientProvider)
        .updateTask(
          task.id,
          WorkTaskDraft(
            name: task.name,
            description: task.displayDescription,
            content: task.displayContent,
            priority: task.priority,
            attachmentIds: task.attachments.map((file) => file.id).toList(),
            tags: task.tags,
            deadlineAt: task.deadlineAt,
            completeReason: complete ? 0 : null,
            groupId: task.groupId,
          ),
        );
    ref.invalidate(tasksProvider(broadId));
    showSnackBar(complete ? 'Task completed.' : 'Task reopened.');
  } catch (error) {
    showSnackBar(error.toString());
  }
}

Future<void> _deleteTask(
  BuildContext context,
  WidgetRef ref,
  String broadId,
  WorkTask task,
) async {
  final scheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Symbols.delete, color: scheme.error),
      title: const Text('Delete task?'),
      content: Text('“${task.name}” will be permanently removed.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await ref.read(wattEngineClientProvider).deleteTask(task.id);
    ref.invalidate(tasksProvider(broadId));
    showSnackBar('Task deleted.');
  } catch (error) {
    showSnackBar(error.toString());
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.onOpen,
    required this.onToggleComplete,
    required this.onDelete,
    this.compact = false,
  });

  final WorkTask task;
  final VoidCallback onOpen;
  final VoidCallback onToggleComplete;
  final VoidCallback onDelete;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final priority = _priorityMeta(task.priority);
    final completeLabel = _completeReasonLabel(task.completeReason);
    final hasDescription = task.hasDescription;
    final titleStyle = (compact ? text.titleSmall : text.titleMedium)?.copyWith(
      decoration: task.isCompleted ? TextDecoration.lineThrough : null,
    );

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 8 : 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                // Title-only cards: center with action buttons (no dead space).
                // With description: top-align so text stacks under the title.
                crossAxisAlignment: hasDescription
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: task.isCompleted
                        ? 'Reopen task'
                        : 'Mark completed',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: onToggleComplete,
                    icon: Icon(
                      task.isCompleted
                          ? Symbols.check_circle
                          : Symbols.radio_button_unchecked,
                      size: compact ? 20 : 24,
                      color: task.isCompleted
                          ? scheme.tertiary
                          : scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: hasDescription
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                task.name,
                                maxLines: compact ? 2 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: titleStyle,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                task.displayDescription!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            task.name,
                            maxLines: compact ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                  ),
                  IconButton(
                    tooltip: 'Delete task',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Symbols.delete,
                      size: compact ? 18 : 22,
                      color: scheme.onSurfaceVariant,
                    ),
                    onPressed: onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatusChip(
                    label: priority.label,
                    icon: priority.icon,
                    tone: priority.tone,
                  ),
                  if (completeLabel != null)
                    StatusChip(
                      label: completeLabel,
                      icon: Symbols.done_all,
                      tone: StatusChipTone.secondary,
                    ),
                  if (task.deadlineAt != null)
                    StatusChip(
                      label: _formatDeadline(task.deadlineAt!),
                      icon: Symbols.event,
                      tone:
                          task.deadlineAt!.isBefore(DateTime.now()) &&
                              !task.isCompleted
                          ? StatusChipTone.error
                          : StatusChipTone.neutral,
                    ),
                  for (final tag in task.tags.take(compact ? 2 : 4))
                    StatusChip(
                      label: tag,
                      icon: Symbols.label,
                      tone: StatusChipTone.neutral,
                    ),
                  if (task.attachments.isNotEmpty)
                    StatusChip(
                      label:
                          '${task.attachments.length} file'
                          '${task.attachments.length == 1 ? '' : 's'}',
                      icon: Symbols.attach_file,
                      tone: StatusChipTone.neutral,
                    ),
                  if (task.assignees.isNotEmpty)
                    StatusChip(
                      label: task.assignees.length == 1
                          ? task.assignees.first.label
                          : '${task.assignees.length} assignees',
                      icon: Symbols.group,
                      tone: StatusChipTone.primary,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

({String label, IconData icon, StatusChipTone tone}) _priorityMeta(
  int priority,
) {
  return switch (priority) {
    1 => (
      label: 'High',
      icon: Symbols.keyboard_double_arrow_up,
      tone: StatusChipTone.tertiary,
    ),
    2 => (
      label: 'Urgent',
      icon: Symbols.priority_high,
      tone: StatusChipTone.error,
    ),
    _ => (label: 'Normal', icon: Symbols.remove, tone: StatusChipTone.neutral),
  };
}

String? _completeReasonLabel(int? reason) => switch (reason) {
  0 => 'Completed',
  1 => 'Skipped',
  2 => 'Duplicated',
  _ => null,
};

String _formatDeadline(DateTime deadline) {
  final local = deadline.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

// --- Board editor ----------------------------------------------------------------

Future<void> _boardForm(
  BuildContext context,
  WidgetRef ref, {
  Broad? board,
}) async {
  final workspace = await ref.read(selectedWorkspaceProvider.future);
  if (workspace == null) {
    showSnackBar('Select a workspace before creating a board.');
    return;
  }
  if (!context.mounted) return;
  final draft = await showModalBottomSheet<_BoardDraft>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BoardEditorSheet(board: board),
  );
  if (draft == null) return;
  try {
    final client = ref.read(wattEngineClientProvider);
    if (board == null) {
      await client.createBroad(
        name: draft.name,
        description: draft.description,
        content: draft.content,
        workspaceId: workspace.id,
        iconImageId: draft.updateIconImage ? draft.iconImageId : null,
        backgroundImageId: draft.updateBackgroundImage
            ? draft.backgroundImageId
            : null,
      );
    } else {
      await client.updateBroad(
        broadId: board.id,
        name: draft.name,
        description: draft.description,
        content: draft.content,
        workspaceId: workspace.id,
        iconImageId: draft.iconImageId,
        updateIconImage: draft.updateIconImage,
        backgroundImageId: draft.backgroundImageId,
        updateBackgroundImage: draft.updateBackgroundImage,
      );
    }
    ref.invalidate(broadsProvider);
    showSnackBar(board == null ? 'Board created.' : 'Board updated.');
  } catch (error) {
    showSnackBar(error.toString());
  }
}

class _BoardDraft {
  const _BoardDraft({
    required this.name,
    this.description,
    this.content,
    this.iconImageId,
    this.updateIconImage = false,
    this.backgroundImageId,
    this.updateBackgroundImage = false,
  });

  final String name;
  final String? description;
  final String? content;
  final String? iconImageId;
  final bool updateIconImage;
  final String? backgroundImageId;
  final bool updateBackgroundImage;
}

class _BoardEditorSheet extends ConsumerStatefulWidget {
  const _BoardEditorSheet({this.board});

  final Broad? board;

  @override
  ConsumerState<_BoardEditorSheet> createState() => _BoardEditorSheetState();
}

class _BoardEditorSheetState extends ConsumerState<_BoardEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _content;
  SnCloudFileReference? _icon;
  SnCloudFileReference? _background;
  var _iconChanged = false;
  var _backgroundChanged = false;

  @override
  void initState() {
    super.initState();
    final board = widget.board;
    _name = TextEditingController(text: board?.name ?? '');
    _description = TextEditingController(text: board?.description ?? '');
    _content = TextEditingController(text: board?.content ?? '');
    _icon = board?.iconImage;
    _background = board?.backgroundImage;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    final workspace = await ref.read(selectedWorkspaceProvider.future);
    if (!mounted) return;
    final file = await pickCloudImageReference(
      context,
      ref,
      usage: 'board.icon',
      workspaceId: workspace?.id,
      title: 'Board icon',
    );
    if (file == null || !mounted) return;
    setState(() {
      _icon = file;
      _iconChanged = true;
    });
  }

  Future<void> _pickBackground() async {
    final workspace = await ref.read(selectedWorkspaceProvider.future);
    if (!mounted) return;
    final file = await pickCloudImageReference(
      context,
      ref,
      usage: 'board.background',
      workspaceId: workspace?.id,
      title: 'Board background',
    );
    if (file == null || !mounted) return;
    setState(() {
      _background = file;
      _backgroundChanged = true;
    });
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      showSnackBar('Name is required.');
      return;
    }
    Navigator.pop(
      context,
      _BoardDraft(
        name: _name.text.trim(),
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        content: _content.text.trim().isEmpty ? null : _content.text.trim(),
        iconImageId: _icon?.id,
        updateIconImage: _iconChanged,
        backgroundImageId: _background?.id,
        updateBackgroundImage: _backgroundChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final board = widget.board;

    return SheetScaffold(
      titleText: board == null ? 'New board' : 'Edit board',
      heightFactor: 0.8,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: _pickIcon,
                  borderRadius: BorderRadius.circular(16),
                  child: CloudFileAvatar(
                    file: _icon,
                    fallbackIcon: Symbols.view_kanban,
                    size: 64,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Board icon', style: text.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        'Displayed on the boards grid and list.',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: _pickIcon,
                            icon: const Icon(Symbols.upload, size: 18),
                            label: Text(_icon == null ? 'Upload' : 'Change'),
                          ),
                          if (_icon != null)
                            TextButton(
                              onPressed: () => setState(() {
                                _icon = null;
                                _iconChanged = true;
                              }),
                              child: const Text('Clear'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CloudFileAvatar(
                file: _background,
                fallbackIcon: Symbols.wallpaper,
                size: 40,
              ),
              title: const Text('Background image'),
              subtitle: Text(
                _background == null
                    ? 'Optional cover image'
                    : _background!.name,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_background != null)
                    IconButton(
                      tooltip: 'Clear background',
                      icon: const Icon(Symbols.close),
                      onPressed: () => setState(() {
                        _background = null;
                        _backgroundChanged = true;
                      }),
                    ),
                  IconButton(
                    tooltip: 'Choose background',
                    icon: const Icon(Symbols.upload),
                    onPressed: _pickBackground,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: 'Name',
                prefixIcon: inputPrefixIcon(Symbols.title),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              decoration: InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
                prefixIcon: inputPrefixIcon(Symbols.notes, maxLines: 3),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _content,
              decoration: InputDecoration(
                labelText: 'Content',
                alignLabelWithHint: true,
                prefixIcon: inputPrefixIcon(Symbols.article, maxLines: 4),
                hintText: 'Optional long-form detail',
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _submit,
              child: Text(board == null ? 'Create board' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Task groups -----------------------------------------------------------------

Future<void> _manageGroups(
  BuildContext context,
  WidgetRef ref,
  String broadId,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TaskGroupsSheet(broadId: broadId),
  );
}

class _TaskGroupsSheet extends ConsumerStatefulWidget {
  const _TaskGroupsSheet({required this.broadId});

  final String broadId;

  @override
  ConsumerState<_TaskGroupsSheet> createState() => _TaskGroupsSheetState();
}

class _TaskGroupsSheetState extends ConsumerState<_TaskGroupsSheet> {
  final _name = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnackBar('Group name is required.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(wattEngineClientProvider)
          .createTaskGroup(widget.broadId, name: name);
      _name.clear();
      ref.invalidate(taskGroupsProvider(widget.broadId));
      showSnackBar('Group created.');
    } catch (error) {
      showSnackBar(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(TaskGroup group) async {
    final controller = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == group.name) return;
    try {
      await ref
          .read(wattEngineClientProvider)
          .updateTaskGroup(group.id, name: name);
      ref.invalidate(taskGroupsProvider(widget.broadId));
      showSnackBar('Group updated.');
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  Future<void> _delete(TaskGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${group.name}?'),
        content: const Text(
          'Tasks in this group stay on the board and become ungrouped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(wattEngineClientProvider).deleteTaskGroup(group.id);
      ref.invalidate(taskGroupsProvider(widget.broadId));
      ref.invalidate(tasksProvider(widget.broadId));
      showSnackBar('Group deleted.');
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(taskGroupsProvider(widget.broadId));
    final scheme = Theme.of(context).colorScheme;

    return SheetScaffold(
      titleText: 'Task groups',
      heightFactor: 0.7,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Organize board tasks into columns or swimlanes.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: 'New group',
                      hintText: 'In Progress',
                      prefixIcon: inputPrefixIcon(Symbols.folder),
                    ),
                    onSubmitted: (_) => _create(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _create,
                  child: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: groups.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => EmptyState(
                  icon: Symbols.error,
                  title: 'Could not load groups',
                  message: error.toString(),
                  action: FilledButton(
                    onPressed: () =>
                        ref.invalidate(taskGroupsProvider(widget.broadId)),
                    child: const Text('Try again'),
                  ),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return const EmptyState(
                      icon: Symbols.view_column,
                      title: 'No groups yet',
                      message: 'Create a group to organize tasks.',
                    );
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final group = items[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Symbols.folder),
                        title: Text(group.name),
                        subtitle: Text('Position ${group.position}'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'rename') _rename(group);
                            if (value == 'delete') _delete(group);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text('Rename'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Task editor -----------------------------------------------------------------

Future<void> _taskForm(
  BuildContext context,
  WidgetRef ref,
  String broadId, {
  WorkTask? task,
  String? initialGroupId,
}) async {
  WorkTask? editable = task;
  if (task != null) {
    try {
      // List endpoints may omit assignees; load full task for edit.
      editable = await ref.read(wattEngineClientProvider).getTask(task.id);
    } catch (_) {
      editable = task;
    }
  }
  if (!context.mounted) return;

  final result = await showModalBottomSheet<_TaskFormResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TaskEditorSheet(
      broadId: broadId,
      task: editable,
      initialGroupId: task == null ? initialGroupId : null,
    ),
  );
  if (result == null) return;
  try {
    final client = ref.read(wattEngineClientProvider);
    if (task == null) {
      final created = await client.createTask(broadId, result.draft);
      if (result.assigneeAccountIds.isNotEmpty &&
          created.assigneeAccountIds.toSet() !=
              result.assigneeAccountIds.toSet()) {
        await client.setTaskAssignees(created.id, result.assigneeAccountIds);
      }
    } else {
      await client.updateTask(task.id, result.draft);
      final previous = {
        for (final id in (editable ?? task).assigneeAccountIds) id,
      };
      final next = result.assigneeAccountIds.toSet();
      if (previous != next) {
        await client.setTaskAssignees(task.id, result.assigneeAccountIds);
      }
    }
    ref.invalidate(tasksProvider(broadId));
    showSnackBar(task == null ? 'Task created.' : 'Task updated.');
  } catch (error) {
    showSnackBar(error.toString());
  }
}

class _TaskFormResult {
  const _TaskFormResult({
    required this.draft,
    required this.assigneeAccountIds,
  });

  final WorkTaskDraft draft;
  final List<String> assigneeAccountIds;
}

class _TaskEditorSheet extends ConsumerStatefulWidget {
  const _TaskEditorSheet({
    required this.broadId,
    this.task,
    this.initialGroupId,
  });

  final String broadId;
  final WorkTask? task;
  final String? initialGroupId;

  @override
  ConsumerState<_TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends ConsumerState<_TaskEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _content;
  late final TextEditingController _tags;
  var _priority = 0;
  DateTime? _deadline;
  int? _completeReason;
  String? _groupId;
  late bool _showDescription;
  late bool _showContent;
  final List<SnCloudFileReference> _attachments = [];
  final List<_AssigneeChoice> _assignees = [];

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _name = TextEditingController(text: task?.name ?? '');
    _description = TextEditingController(text: task?.displayDescription ?? '');
    _content = TextEditingController(text: task?.displayContent ?? '');
    _tags = TextEditingController(text: task?.tags.join(', ') ?? '');
    _priority = task?.priority ?? 0;
    _deadline = task?.deadlineAt;
    _completeReason = task?.completeReason;
    _groupId = task?.groupId ?? widget.initialGroupId;
    // Keep empty optional fields collapsed until the user adds them.
    _showDescription = task?.hasDescription == true;
    _showContent = task?.hasContent == true;
    if (task != null) {
      _attachments.addAll(task.attachments);
      _assignees.addAll(
        task.assignees.map(
          (item) =>
              _AssigneeChoice(accountId: item.accountId, label: item.label),
        ),
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _content.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final initial = _deadline ?? now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() {
      _deadline = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _addAttachments() async {
    final workspace = await ref.read(selectedWorkspaceProvider.future);
    if (!mounted) return;
    final files = await showCloudFilePicker<List<SnCloudFile>>(
      context: context,
      ref: ref,
      allowMultiple: true,
      usage: 'task.attachment',
      workspaceId: workspace?.id,
      title: 'Attach files',
    );
    if (files == null || files.isEmpty || !mounted) return;
    setState(() {
      for (final file in files) {
        if (_attachments.any((item) => item.id == file.id)) continue;
        _attachments.add(cloudFileToReference(file));
      }
    });
  }

  Future<void> _addAssignee() async {
    final workspace = await ref.read(selectedWorkspaceProvider.future);
    if (!mounted) return;
    final choice = await showModalBottomSheet<_AssigneeChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AssigneePickerSheet(
        client: ref.read(wattEngineClientProvider),
        workspaceSlug: workspace?.slug,
        excludeAccountIds: {for (final item in _assignees) item.accountId},
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _assignees.add(choice));
  }

  List<String>? _parseTags() {
    final raw = _tags.text.trim();
    if (raw.isEmpty) {
      return widget.task == null ? null : <String>[];
    }
    return raw
        .split(RegExp(r'[,，]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      showSnackBar('Name is required.');
      return;
    }
    final hadGroup = widget.task?.groupId != null;
    final ungroup = hadGroup && _groupId == null;
    Navigator.pop(
      context,
      _TaskFormResult(
        draft: WorkTaskDraft(
          name: _name.text.trim(),
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          content: _content.text.trim().isEmpty ? null : _content.text.trim(),
          priority: _priority,
          attachmentIds: _attachments.map((file) => file.id).toList(),
          tags: _parseTags(),
          deadlineAt: _deadline,
          completeReason: _completeReason,
          groupId: _groupId,
          ungroup: ungroup ? true : null,
          assigneeAccountIds: _assignees.map((item) => item.accountId).toList(),
        ),
        assigneeAccountIds: _assignees.map((item) => item.accountId).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final task = widget.task;
    final groups = ref.watch(taskGroupsProvider(widget.broadId));

    return SheetScaffold(
      titleText: task == null ? 'New task' : 'Edit task',
      heightFactor: 0.92,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: 'Name',
                prefixIcon: inputPrefixIcon(Symbols.title),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            if (_showDescription) ...[
              TextField(
                controller: _description,
                decoration: InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                  prefixIcon: inputPrefixIcon(Symbols.notes, maxLines: 3),
                  suffixIcon: IconButton(
                    tooltip: 'Remove description',
                    icon: const Icon(Symbols.close, size: 18),
                    onPressed: () => setState(() {
                      _description.clear();
                      _showDescription = false;
                    }),
                  ),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
            ],
            if (_showContent) ...[
              TextField(
                controller: _content,
                decoration: InputDecoration(
                  labelText: 'Details',
                  alignLabelWithHint: true,
                  prefixIcon: inputPrefixIcon(Symbols.article, maxLines: 4),
                  hintText: 'Rich detail / notes',
                  suffixIcon: IconButton(
                    tooltip: 'Remove details',
                    icon: const Icon(Symbols.close, size: 18),
                    onPressed: () => setState(() {
                      _content.clear();
                      _showContent = false;
                    }),
                  ),
                ),
                maxLines: 4,
              ),
              const SizedBox(height: 12),
            ],
            if (!_showDescription || !_showContent) ...[
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (!_showDescription)
                    TextButton.icon(
                      onPressed: () => setState(() => _showDescription = true),
                      icon: const Icon(Symbols.notes, size: 18),
                      label: const Text('Add description'),
                    ),
                  if (!_showContent)
                    TextButton.icon(
                      onPressed: () => setState(() => _showContent = true),
                      icon: const Icon(Symbols.article, size: 18),
                      label: const Text('Add details'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            groups.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text(
                'Groups unavailable: $error',
                style: text.bodySmall?.copyWith(color: scheme.error),
              ),
              data: (items) {
                // Drop stale selection if the group was deleted.
                final validGroupId = items.any((group) => group.id == _groupId)
                    ? _groupId
                    : null;
                return DropdownButtonFormField<String?>(
                  key: ValueKey('group-$validGroupId-${items.length}'),
                  initialValue: validGroupId,
                  decoration: InputDecoration(
                    labelText: 'Group',
                    prefixIcon: inputPrefixIcon(Symbols.folder),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Ungrouped'),
                    ),
                    for (final group in items)
                      DropdownMenuItem<String?>(
                        value: group.id,
                        child: Text(group.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _groupId = value),
                );
              },
            ),
            const SizedBox(height: 16),
            Text('Priority', style: text.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Normal'),
                  icon: Icon(Symbols.remove, size: 18),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('High'),
                  icon: Icon(Symbols.keyboard_double_arrow_up, size: 18),
                ),
                ButtonSegment(
                  value: 2,
                  label: Text('Urgent'),
                  icon: Icon(Symbols.priority_high, size: 18),
                ),
              ],
              selected: {_priority},
              onSelectionChanged: (values) =>
                  setState(() => _priority = values.first),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Symbols.event, color: scheme.primary),
              title: const Text('Deadline'),
              subtitle: Text(
                _deadline == null
                    ? 'No deadline'
                    : _deadline!.toLocal().toString().split('.').first,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_deadline != null)
                    IconButton(
                      tooltip: 'Clear deadline',
                      icon: const Icon(Symbols.clear),
                      onPressed: () => setState(() => _deadline = null),
                    ),
                  IconButton(
                    tooltip: 'Set deadline',
                    icon: const Icon(Symbols.edit_calendar),
                    onPressed: _pickDeadline,
                  ),
                ],
              ),
            ),
            if (task != null) ...[
              const SizedBox(height: 8),
              Text('Completion', style: text.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Open'),
                    selected: _completeReason == null,
                    onSelected: (_) => setState(() => _completeReason = null),
                  ),
                  FilterChip(
                    label: const Text('Completed'),
                    selected: _completeReason == 0,
                    onSelected: (_) => setState(() => _completeReason = 0),
                  ),
                  FilterChip(
                    label: const Text('Skipped'),
                    selected: _completeReason == 1,
                    onSelected: (_) => setState(() => _completeReason = 1),
                  ),
                  FilterChip(
                    label: const Text('Duplicated'),
                    selected: _completeReason == 2,
                    onSelected: (_) => setState(() => _completeReason = 2),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _tags,
              decoration: InputDecoration(
                labelText: 'Tags',
                hintText: 'backend, urgent',
                prefixIcon: inputPrefixIcon(Symbols.label),
                helperText: 'Comma-separated tags',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Assignees', style: text.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addAssignee,
                  icon: const Icon(Symbols.person_add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (_assignees.isEmpty)
              Text(
                'No assignees yet.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final assignee in _assignees)
                    InputChip(
                      avatar: CircleAvatar(
                        child: Text(
                          assignee.label.isEmpty
                              ? '?'
                              : assignee.label[0].toUpperCase(),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      label: Text(assignee.label),
                      onDeleted: () =>
                          setState(() => _assignees.remove(assignee)),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Attachments', style: text.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addAttachments,
                  icon: const Icon(Symbols.attach_file, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (_attachments.isEmpty)
              Text(
                'No files attached.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final file in _attachments)
                    CloudFileChip(
                      file: file,
                      onRemove: () => setState(() => _attachments.remove(file)),
                    ),
                ],
              ),
            const SizedBox(height: 28),
            FilledButton(onPressed: _submit, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}

class _AssigneeChoice {
  const _AssigneeChoice({required this.accountId, required this.label});

  final String accountId;
  final String label;
}

class _AssigneePickerSheet extends StatefulWidget {
  const _AssigneePickerSheet({
    required this.client,
    required this.workspaceSlug,
    required this.excludeAccountIds,
  });

  final WattEngineClient client;
  final String? workspaceSlug;
  final Set<String> excludeAccountIds;

  @override
  State<_AssigneePickerSheet> createState() => _AssigneePickerSheetState();
}

class _AssigneePickerSheetState extends State<_AssigneePickerSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  Future<List<_AssigneeChoice>>? _results;
  Future<List<_AssigneeChoice>>? _members;

  @override
  void initState() {
    super.initState();
    final slug = widget.workspaceSlug;
    if (slug != null) {
      _members = widget.client.listWorkspaceMembers(slug).then((members) {
        return members
            .where((m) => !widget.excludeAccountIds.contains(m.accountId))
            .map((m) => _AssigneeChoice(accountId: m.accountId, label: m.label))
            .toList();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _results = widget.client.searchAccounts(query).then((accounts) {
          return accounts
              .where((a) => !widget.excludeAccountIds.contains(a.id))
              .map(
                (a) => _AssigneeChoice(
                  accountId: a.id,
                  label: a.solWattDisplayName,
                ),
              )
              .toList();
        });
      });
    });
  }

  Widget _list(Future<List<_AssigneeChoice>>? future, {required String empty}) {
    if (future == null) {
      return Center(child: Text(empty));
    }
    return FutureBuilder<List<_AssigneeChoice>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return Center(child: Text(empty));
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              leading: CircleAvatar(
                child: Text(
                  item.label.isEmpty ? '?' : item.label[0].toUpperCase(),
                ),
              ),
              title: Text(item.label),
              subtitle: Text(item.accountId),
              onTap: () => Navigator.pop(context, item),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final searching = _controller.text.trim().isNotEmpty;

    return SheetScaffold(
      titleText: 'Add assignee',
      heightFactor: 0.7,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          children: [
            SearchBar(
              controller: _controller,
              hintText: 'Search accounts',
              leading: const Icon(Symbols.search),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: searching
                  ? _list(_results, empty: 'No accounts found.')
                  : _list(
                      _members,
                      empty: widget.workspaceSlug == null
                          ? 'Search for an account to assign.'
                          : 'No workspace members available.',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
