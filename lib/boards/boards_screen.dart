import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/boards/github_integration.dart';
import 'package:solwatt/boards/task_comments.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/ui/alert.dart';
import 'package:solwatt/ui/cloud_files.dart';
import 'package:solwatt/ui/markdown.dart';
import 'package:solwatt/ui/name_sheet.dart';
import 'package:solwatt/ui/page_scaffold.dart';
import 'package:url_launcher/url_launcher.dart';

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
      title: 'boards'.tr(),
      subtitle: workspace == null
          ? 'ideaskBoards'.tr()
          : 'inWorkspace'.tr(namedArgs: {'name': workspace.name}),
      action: FilledButton.tonalIcon(
        onPressed: () => _boardForm(context, ref),
        icon: const Icon(Symbols.add, size: 18),
        label: Text('newBoard'.tr()),
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
              title: 'noBoardsEmpty'.tr(),
              message: 'createBoardToOrganize'.tr(),
              action: FilledButton.icon(
                onPressed: () => _boardForm(context, ref),
                icon: const Icon(Symbols.add),
                label: Text('newBoard'.tr()),
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
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'open', child: Text('Open')),
                      PopupMenuItem(value: 'edit', child: Text('edit'.tr())),
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
                        tooltip: 'editBoard'.tr(),
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
  final Map<String, String?> _groupOverrides = {};
  final ValueNotifier<bool> _showTaskSidebar = ValueNotifier(false);
  WorkTask? _selectedTask;

  String get _broadId => widget.broadId;

  @override
  void dispose() {
    _showTaskSidebar.dispose();
    super.dispose();
  }

  Future<void> _openTask(WorkTask task) async {
    setState(() => _selectedTask = task);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selectedTask?.id == task.id) {
        _showTaskSidebar.value = true;
      }
    });

    try {
      final detailed = await ref
          .read(wattEngineClientProvider)
          .getTask(task.id);
      if (!mounted || _selectedTask?.id != task.id) return;
      setState(() => _selectedTask = detailed);
    } catch (_) {}
  }

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
      ref.invalidate(tasksProvider(_broadId));
      await ref.read(tasksProvider(_broadId).future);
      if (!mounted) return;
      setState(() => _groupOverrides.remove(task.id));
    } catch (error) {
      if (!mounted) return;
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
            icon: const Icon(Symbols.hub),
            tooltip: 'githubIntegration'.tr(),
            onPressed: () => showGitHubIntegrationSheet(
              context,
              ref,
              broadId: _broadId,
              broadName: widget.broadName,
            ),
          ),
          IconButton(
            icon: const Icon(Symbols.view_column),
            tooltip: 'manageGroups'.tr(),
            onPressed: () => _manageGroups(context, ref, _broadId),
          ),
          IconButton.filledTonal(
            icon: const Icon(Symbols.add_task),
            tooltip: 'newTask'.tr(),
            onPressed: () => _taskForm(context, ref, _broadId),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ResponsiveSidebar(
        showSidebar: _showTaskSidebar,
        sidebarWidth: 480,
        minWideSidebarWidth: 360,
        sidebarContent: _selectedTask == null
            ? const SizedBox.shrink()
            : _TaskDetailSidebar(
                task: _selectedTask!,
                onClose: () => _showTaskSidebar.value = false,
                onEdit: () =>
                    _taskForm(context, ref, _broadId, task: _selectedTask),
                onToggleComplete: () =>
                    _toggleTaskComplete(context, ref, _broadId, _selectedTask!),
              ),
        mainContent: tasks.when(
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
                    title: 'noTasksYet'.tr(),
                    message: 'addTaskOrCreateGroups'.tr(),
                    action: FilledButton.icon(
                      onPressed: () => _taskForm(context, ref, _broadId),
                      icon: const Icon(Symbols.add_task),
                      label: Text('newTask'.tr()),
                    ),
                  );
                }

                final columns = _buildColumns(groupItems, effective);
                if (groupItems.isEmpty) {
                  final ungrouped = columns.single;
                  return Center(
                    child: SizedBox(
                      width: 720,
                      height: double.infinity,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        itemCount: ungrouped.tasks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final task = ungrouped.tasks[index];
                          return _TaskTile(
                            task: task,
                            onOpen: () => _openTask(task),
                            onToggleComplete: () => _toggleTaskComplete(
                              context,
                              ref,
                              _broadId,
                              task,
                            ),
                            onDelete: () =>
                                _deleteTask(context, ref, _broadId, task),
                          );
                        },
                      ),
                    ),
                  );
                }

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
                      onOpenTask: _openTask,
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
    _TaskColumn(title: 'ungrouped'.tr(), tasks: ungrouped, isUngrouped: true),
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
                        tooltip: 'addTask'.tr(),
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
                                  ? 'dropTaskHere'.tr()
                                  : isUngrouped
                                  ? 'noUngroupedTasks'.tr()
                                  : 'noTasksInGroup'.tr(),
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
    showSnackBar(complete ? 'taskCompleted'.tr() : 'taskReopened'.tr());
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
  final confirmed = await showConfirmAlert(
    'deleteTaskConfirm'.tr(namedArgs: {'name': task.name}),
    'deleteTaskTitle'.tr(),
    icon: Symbols.delete,
    isDanger: true,
    confirmLabel: 'delete'.tr(),
  );
  if (!confirmed) return;
  try {
    await ref.read(wattEngineClientProvider).deleteTask(task.id);
    ref.invalidate(tasksProvider(broadId));
    showSnackBar('taskDeleted'.tr());
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
                crossAxisAlignment: hasDescription
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: task.isCompleted
                        ? 'reopenTask'.tr()
                        : 'markCompleted'.tr(),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (task.displayKey case final key?)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              key,
                              style: text.labelSmall?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        Text(
                          task.name,
                          maxLines: compact ? 2 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                        if (hasDescription) ...[
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
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'deleteTask'.tr(),
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
                          '${task.attachments.length} file${task.attachments.length == 1 ? '' : 's'}',
                      icon: Symbols.attach_file,
                      tone: StatusChipTone.neutral,
                    ),
                  if (task.assignees.isNotEmpty)
                    StatusChip(
                      label: task.assignees.length == 1
                          ? task.assignees.first.label
                          : 'assignees'.tr(
                              args: [task.assignees.length.toString()],
                            ),
                      icon: Symbols.group,
                      tone: StatusChipTone.primary,
                    ),
                  if (task.gitHubIssue != null)
                    StatusChip(
                      label: task.gitHubIssue!.label,
                      icon: task.gitHubIssue!.isPullRequest
                          ? Symbols.call_split
                          : Symbols.hub,
                      tone: StatusChipTone.secondary,
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

class _TaskDetailSidebar extends StatelessWidget {
  const _TaskDetailSidebar({
    required this.task,
    required this.onClose,
    required this.onEdit,
    required this.onToggleComplete,
  });

  final WorkTask task;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onToggleComplete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final priority = _priorityMeta(task.priority);
    final completeLabel = _completeReasonLabel(task.completeReason);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text('taskDetails'.tr(), style: text.titleMedium),
                ),
                IconButton(
                  tooltip: 'editTask'.tr(),
                  onPressed: onEdit,
                  icon: const Icon(Symbols.edit),
                ),
                IconButton(
                  tooltip: 'closeDetails'.tr(),
                  onPressed: onClose,
                  icon: const Icon(Symbols.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        tooltip: task.isCompleted
                            ? 'reopenTask'.tr()
                            : 'markCompleted'.tr(),
                        onPressed: onToggleComplete,
                        icon: Icon(
                          task.isCompleted
                              ? Symbols.check_circle
                              : Symbols.radio_button_unchecked,
                          color: task.isCompleted
                              ? scheme.tertiary
                              : scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (task.displayKey case final key?)
                              Text(
                                key,
                                style: text.labelLarge?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            Text(
                              task.name,
                              style: text.headlineSmall?.copyWith(
                                decoration: task.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
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
                      for (final tag in task.tags)
                        StatusChip(
                          label: tag,
                          icon: Symbols.label,
                          tone: StatusChipTone.neutral,
                        ),
                    ],
                  ),
                  if (task.displayDescription case final description?) ...[
                    const SizedBox(height: 24),
                    Text('description'.tr(), style: text.titleSmall),
                    const SizedBox(height: 8),
                    Text(description),
                  ],
                  if (task.displayContent case final content?) ...[
                    const SizedBox(height: 24),
                    Text('details'.tr(), style: text.titleSmall),
                    const SizedBox(height: 8),
                    MarkdownTextContent(content: content),
                  ],
                  if (task.assignees.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('assigneesLabel'.tr(), style: text.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final assignee in task.assignees)
                          Chip(
                            avatar: CircleAvatar(
                              child: Text(
                                assignee.label.isEmpty
                                    ? '?'
                                    : assignee.label[0].toUpperCase(),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            label: Text(assignee.label),
                          ),
                      ],
                    ),
                  ],
                  if (task.attachments.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('attachments'.tr(), style: text.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final file in task.attachments)
                          CloudFileChip(file: file),
                      ],
                    ),
                  ],
                  if (task.gitHubIssue != null) ...[
                    const SizedBox(height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        task.gitHubIssue!.isPullRequest
                            ? Symbols.call_split
                            : Symbols.hub,
                        color: scheme.primary,
                      ),
                      title: Text(task.gitHubIssue!.label),
                      subtitle: Text(
                        task.gitHubIssue!.htmlUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),
                  TaskCommentsSection(taskId: task.id),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

({String label, IconData icon, StatusChipTone tone}) _priorityMeta(
  int priority,
) {
  return switch (priority) {
    1 => (
      label: 'high'.tr(),
      icon: Symbols.keyboard_double_arrow_up,
      tone: StatusChipTone.tertiary,
    ),
    2 => (
      label: 'urgent'.tr(),
      icon: Symbols.priority_high,
      tone: StatusChipTone.error,
    ),
    _ => (
      label: 'normal'.tr(),
      icon: Symbols.remove,
      tone: StatusChipTone.neutral,
    ),
  };
}

String? _completeReasonLabel(int? reason) => switch (reason) {
  0 => 'completed'.tr(),
  1 => 'skipped'.tr(),
  2 => 'duplicated'.tr(),
  _ => null,
};

String _formatDeadline(DateTime deadline) {
  final local = deadline.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

Future<void> _boardForm(
  BuildContext context,
  WidgetRef ref, {
  Broad? board,
}) async {
  final workspace = await ref.read(selectedWorkspaceProvider.future);
  if (workspace == null) {
    showSnackBar('selectWorkspaceBeforeCreatingBoard'.tr());
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
        taskPrefix: draft.taskPrefix,
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
        taskPrefix: draft.taskPrefix,
        clearTaskPrefix: draft.clearTaskPrefix,
      );
    }
    ref.invalidate(broadsProvider);
    showSnackBar(board == null ? 'boardCreated'.tr() : 'boardUpdated'.tr());
  } catch (error) {
    showSnackBar(wattApiErrorMessage(error));
  }
}

class _BoardDraft {
  const _BoardDraft({
    required this.name,
    this.description,
    this.content,
    this.taskPrefix,
    this.clearTaskPrefix = false,
    this.iconImageId,
    this.updateIconImage = false,
    this.backgroundImageId,
    this.updateBackgroundImage = false,
  });

  final String name;
  final String? description;
  final String? content;
  final String? taskPrefix;
  final bool clearTaskPrefix;
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
  late final TextEditingController _taskPrefix;
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
    _taskPrefix = TextEditingController(text: board?.taskPrefix ?? '');
    _icon = board?.iconImage;
    _background = board?.backgroundImage;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _content.dispose();
    _taskPrefix.dispose();
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
      title: 'boardIcon'.tr(),
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
      title: 'backgroundImage'.tr(),
    );
    if (file == null || !mounted) return;
    setState(() {
      _background = file;
      _backgroundChanged = true;
    });
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      showSnackBar('nameIsRequired'.tr());
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
        taskPrefix: _taskPrefix.text.trim().isEmpty
            ? null
            : _taskPrefix.text.trim(),
        clearTaskPrefix:
            widget.board?.taskPrefix != null && _taskPrefix.text.trim().isEmpty,
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
      titleText: board == null ? 'newBoard'.tr() : 'editBoard'.tr(),
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
                      Text('boardIcon'.tr(), style: text.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        'boardIconDescription'.tr(),
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
                            label: Text(
                              _icon == null ? 'upload'.tr() : 'change'.tr(),
                            ),
                          ),
                          if (_icon != null)
                            TextButton(
                              onPressed: () => setState(() {
                                _icon = null;
                                _iconChanged = true;
                              }),
                              child: Text('clear'.tr()),
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
              title: Text('backgroundImage'.tr()),
              subtitle: Text(
                _background == null
                    ? 'optionalCoverImage'.tr()
                    : _background!.name,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_background != null)
                    IconButton(
                      tooltip: 'clearBackground'.tr(),
                      icon: const Icon(Symbols.close),
                      onPressed: () => setState(() {
                        _background = null;
                        _backgroundChanged = true;
                      }),
                    ),
                  IconButton(
                    tooltip: 'chooseBackground'.tr(),
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
                labelText: 'name'.tr(),
                prefixIcon: inputPrefixIcon(Symbols.title),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              decoration: InputDecoration(
                labelText: 'description'.tr(),
                alignLabelWithHint: true,
                prefixIcon: inputPrefixIcon(Symbols.notes, maxLines: 3),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _content,
              decoration: InputDecoration(
                labelText: 'content'.tr(),
                alignLabelWithHint: true,
                prefixIcon: inputPrefixIcon(Symbols.article, maxLines: 4),
                hintText: 'Optional long-form detail',
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _taskPrefix,
              decoration: InputDecoration(
                labelText: 'taskPrefix'.tr(),
                hintText: 'SN',
                helperText: 'taskPrefixDescription'.tr(),
                prefixIcon: inputPrefixIcon(Symbols.tag),
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 32,
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _submit,
              child: Text(
                board == null ? 'createBoard'.tr() : 'saveChanges'.tr(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      showSnackBar('groupNameRequired'.tr());
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(wattEngineClientProvider)
          .createTaskGroup(widget.broadId, name: name);
      _name.clear();
      ref.invalidate(taskGroupsProvider(widget.broadId));
      showSnackBar('groupCreated'.tr());
    } catch (error) {
      showSnackBar(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(TaskGroup group) async {
    final name = await showNameInputSheet(
      context,
      title: 'renameGroup'.tr(),
      label: 'name'.tr(),
      confirmLabel: 'save'.tr(),
      initialValue: group.name,
      icon: Symbols.folder,
    );
    if (name == null || name.trim().isEmpty || name.trim() == group.name) {
      return;
    }
    try {
      await ref
          .read(wattEngineClientProvider)
          .updateTaskGroup(group.id, name: name.trim());
      ref.invalidate(taskGroupsProvider(widget.broadId));
      showSnackBar('groupUpdated'.tr());
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  Future<void> _delete(TaskGroup group) async {
    final confirmed = await showConfirmAlert(
      'deleteGroupConfirm'.tr(namedArgs: {'name': group.name}),
      'deleteGroupTitle'.tr(namedArgs: {'name': group.name}),
      icon: Symbols.delete,
      isDanger: true,
      confirmLabel: 'delete'.tr(),
    );
    if (!confirmed) return;
    try {
      await ref.read(wattEngineClientProvider).deleteTaskGroup(group.id);
      ref.invalidate(taskGroupsProvider(widget.broadId));
      ref.invalidate(tasksProvider(widget.broadId));
      showSnackBar('groupDeleted'.tr());
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(taskGroupsProvider(widget.broadId));
    final scheme = Theme.of(context).colorScheme;

    return SheetScaffold(
      titleText: 'taskGroups'.tr(),
      heightFactor: 0.7,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'organizeBoardTasks'.tr(),
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
                      labelText: 'newGroup'.tr(),
                      hintText: 'inProgress'.tr(),
                      prefixIcon: inputPrefixIcon(Symbols.folder),
                    ),
                    onSubmitted: (_) => _create(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _create,
                  child: Text('add'.tr()),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: groups.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => EmptyState(
                  icon: Symbols.error,
                  title: 'couldNotLoadGroups'.tr(),
                  message: error.toString(),
                  action: FilledButton(
                    onPressed: () =>
                        ref.invalidate(taskGroupsProvider(widget.broadId)),
                    child: Text('tryAgain'.tr()),
                  ),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return EmptyState(
                      icon: Symbols.view_column,
                      title: 'noGroupsYet'.tr(),
                      message: 'createGroupToOrganize'.tr(),
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
                        subtitle: Text('${'position'.tr()} ${group.position}'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'rename') _rename(group);
                            if (value == 'delete') _delete(group);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text('rename'.tr()),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('delete'.tr()),
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
    showSnackBar(task == null ? 'taskCreated'.tr() : 'taskUpdated'.tr());
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
      title: 'attachFiles'.tr(),
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
      showSnackBar('nameIsRequired'.tr());
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
      titleText: task == null ? 'newTask'.tr() : 'editTask'.tr(),
      heightFactor: 0.92,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: 'name'.tr(),
                prefixIcon: inputPrefixIcon(Symbols.title),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            if (_showDescription) ...[
              TextField(
                controller: _description,
                decoration: InputDecoration(
                  labelText: 'description'.tr(),
                  alignLabelWithHint: true,
                  prefixIcon: inputPrefixIcon(Symbols.notes, maxLines: 3),
                  suffixIcon: IconButton(
                    tooltip: 'removeDescription'.tr(),
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
                  labelText: 'details'.tr(),
                  alignLabelWithHint: true,
                  prefixIcon: inputPrefixIcon(Symbols.article, maxLines: 4),
                  hintText: 'richDetailNotes'.tr(),
                  suffixIcon: IconButton(
                    tooltip: 'removeDetails'.tr(),
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
                      label: Text('addDescription'.tr()),
                    ),
                  if (!_showContent)
                    TextButton.icon(
                      onPressed: () => setState(() => _showContent = true),
                      icon: const Icon(Symbols.article, size: 18),
                      label: Text('addDetails'.tr()),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            groups.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text(
                'groupsUnavailable'.tr(args: [error.toString()]),
                style: text.bodySmall?.copyWith(color: scheme.error),
              ),
              data: (items) {
                final validGroupId = items.any((group) => group.id == _groupId)
                    ? _groupId
                    : null;
                return DropdownButtonFormField<String?>(
                  key: ValueKey('group-$validGroupId-${items.length}'),
                  initialValue: validGroupId,
                  decoration: InputDecoration(
                    labelText: 'group'.tr(),
                    prefixIcon: inputPrefixIcon(Symbols.folder),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('ungrouped'.tr()),
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
            Text('priority'.tr(), style: text.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(
                  value: 0,
                  label: Text('normal'.tr()),
                  icon: const Icon(Symbols.remove, size: 18),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('high'.tr()),
                  icon: const Icon(Symbols.keyboard_double_arrow_up, size: 18),
                ),
                ButtonSegment(
                  value: 2,
                  label: Text('urgent'.tr()),
                  icon: const Icon(Symbols.priority_high, size: 18),
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
              title: Text('deadline'.tr()),
              subtitle: Text(
                _deadline == null
                    ? 'noDeadline'.tr()
                    : _deadline!.toLocal().toString().split('.').first,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_deadline != null)
                    IconButton(
                      tooltip: 'clearDeadline'.tr(),
                      icon: const Icon(Symbols.clear),
                      onPressed: () => setState(() => _deadline = null),
                    ),
                  IconButton(
                    tooltip: 'setDeadline'.tr(),
                    icon: const Icon(Symbols.edit_calendar),
                    onPressed: _pickDeadline,
                  ),
                ],
              ),
            ),
            if (task != null) ...[
              const SizedBox(height: 8),
              Text('completion'.tr(), style: text.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: Text('open'.tr()),
                    selected: _completeReason == null,
                    onSelected: (_) => setState(() => _completeReason = null),
                  ),
                  FilterChip(
                    label: Text('completed'.tr()),
                    selected: _completeReason == 0,
                    onSelected: (_) => setState(() => _completeReason = 0),
                  ),
                  FilterChip(
                    label: Text('skipped'.tr()),
                    selected: _completeReason == 1,
                    onSelected: (_) => setState(() => _completeReason = 1),
                  ),
                  FilterChip(
                    label: Text('duplicated'.tr()),
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
                labelText: 'tags'.tr(),
                hintText: 'tagsHint'.tr(),
                prefixIcon: inputPrefixIcon(Symbols.label),
                helperText: 'commaSeparatedTags'.tr(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('assigneesLabel'.tr(), style: text.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addAssignee,
                  icon: const Icon(Symbols.person_add, size: 18),
                  label: Text('add'.tr()),
                ),
              ],
            ),
            if (_assignees.isEmpty)
              Text(
                'noAssigneesYet'.tr(),
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
                Text('attachments'.tr(), style: text.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addAttachments,
                  icon: const Icon(Symbols.attach_file, size: 18),
                  label: Text('add'.tr()),
                ),
              ],
            ),
            if (_attachments.isEmpty)
              Text(
                'noFilesAttached'.tr(),
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
            if (task?.gitHubIssue != null) ...[
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  task!.gitHubIssue!.isPullRequest
                      ? Symbols.call_split
                      : Symbols.hub,
                  color: scheme.primary,
                ),
                title: Text(task.gitHubIssue!.label),
                subtitle: Text(
                  task.gitHubIssue!.htmlUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Symbols.open_in_new),
                onTap: () async {
                  final url = task.gitHubIssue!.htmlUrl;
                  if (url.isEmpty) return;
                  final uri = Uri.tryParse(url);
                  if (uri == null) return;
                  try {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } catch (_) {
                    showSnackBar('couldNotOpenGitHubIssue'.tr());
                  }
                },
              ),
            ],
            if (task != null) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              TaskCommentsSection(taskId: task.id),
            ],
            const SizedBox(height: 28),
            FilledButton(onPressed: _submit, child: Text('save'.tr())),
          ],
        ),
      ),
    );
  }
}

class _AssigneeChoice {
  const _AssigneeChoice({
    required this.accountId,
    required this.label,
    this.subtitle,
    this.avatarUrl,
    this.picture,
  });

  final String accountId;
  final String label;
  final String? subtitle;
  final String? avatarUrl;
  final SnCloudFileReference? picture;
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
            .map(
              (m) => _AssigneeChoice(
                accountId: m.accountId,
                label: m.label,
                subtitle: m.subtitleHandle,
                avatarUrl: m.avatarUrl,
                picture: m.picture,
              ),
            )
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
                  subtitle: '@${a.name}',
                  avatarUrl: a.solWattAvatarUrl,
                  picture: a.profilePicture,
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
    final scheme = Theme.of(context).colorScheme;
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
            final initial = item.label.isEmpty
                ? '?'
                : item.label[0].toUpperCase();
            final url =
                item.avatarUrl ??
                (item.picture == null
                    ? null
                    : cloudFileDisplayUrl(item.picture!));
            return ListTile(
              leading: url == null
                  ? CircleAvatar(
                      backgroundColor: scheme.primaryContainer,
                      foregroundColor: scheme.onPrimaryContainer,
                      child: Text(initial),
                    )
                  : ClipOval(
                      child: Image.network(
                        url,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => CircleAvatar(
                          backgroundColor: scheme.primaryContainer,
                          foregroundColor: scheme.onPrimaryContainer,
                          child: Text(initial),
                        ),
                      ),
                    ),
              title: Text(item.label),
              subtitle: Text(item.subtitle ?? item.accountId),
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
      titleText: 'addAssignee'.tr(),
      heightFactor: 0.7,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          children: [
            SearchBar(
              controller: _controller,
              hintText: 'searchAccounts'.tr(),
              leading: const Icon(Symbols.search),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: searching
                  ? _list(_results, empty: 'noAccountsFound'.tr())
                  : _list(
                      _members,
                      empty: widget.workspaceSlug == null
                          ? 'searchAccountToAssign'.tr()
                          : 'noWorkspaceMembersAvailable'.tr(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
