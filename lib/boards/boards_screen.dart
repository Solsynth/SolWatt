import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../network.dart';
import '../ui/page_scaffold.dart';

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
                  leading: const IconBadge(icon: Symbols.view_kanban),
                  title: Text(board.name),
                  subtitle: board.description?.isNotEmpty == true
                      ? Text(
                          board.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  trailing: Icon(
                    Symbols.chevron_right,
                    color: scheme.onSurfaceVariant,
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
  const _BoardCard({required this.board, required this.onOpen});

  final Broad board;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const IconBadge(icon: Symbols.view_kanban),
                  const Spacer(),
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
      ),
    );
  }
}

@RoutePage()
class TaskBoardPage extends ConsumerWidget {
  const TaskBoardPage({
    super.key,
    @PathParam('broadId') required this.broadId,
    required this.broadName,
  });

  final String broadId;
  final String broadName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider(broadId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(broadName),
        actions: [
          IconButton.filledTonal(
            icon: const Icon(Symbols.add_task),
            tooltip: 'New task',
            onPressed: () => _taskForm(context, ref, broadId),
          ),
          const SizedBox(width: 12),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _taskForm(context, ref, broadId),
        icon: const Icon(Symbols.add_task),
        label: const Text('New task'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 88),
            child: tasks.when(
              loading: () => const PageLoading(),
              error: (error, _) => PageError(
                message: error.toString(),
                onRetry: () => ref.invalidate(tasksProvider(broadId)),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Symbols.task_alt,
                    title: 'No tasks yet',
                    message: 'Add a task to get started on this board.',
                    action: FilledButton.icon(
                      onPressed: () => _taskForm(context, ref, broadId),
                      icon: const Icon(Symbols.add_task),
                      label: const Text('New task'),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final task = items[index];
                    return _TaskTile(
                      task: task,
                      onOpen: () =>
                          _taskForm(context, ref, broadId, task: task),
                      onDelete: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            icon: Icon(Symbols.delete, color: scheme.error),
                            title: const Text('Delete task?'),
                            content: Text(
                              '“${task.name}” will be permanently removed.',
                            ),
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
                          await ref
                              .read(wattEngineClientProvider)
                              .deleteTask(task.id);
                          ref.invalidate(tasksProvider(broadId));
                          showSnackBar('Task deleted.');
                        } catch (error) {
                          showSnackBar(error.toString());
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.onOpen,
    required this.onDelete,
  });

  final WorkTask task;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final priority = _priorityMeta(task.priority);

    return Card(
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Symbols.radio_button_unchecked,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.name, style: text.titleMedium),
                    if (task.description?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        task.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    StatusChip(
                      label: priority.label,
                      icon: priority.icon,
                      tone: priority.tone,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete task',
                icon: Icon(Symbols.delete, color: scheme.onSurfaceVariant),
                onPressed: onDelete,
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

Future<void> _boardForm(BuildContext context, WidgetRef ref) async {
  final workspace = await ref.read(selectedWorkspaceProvider.future);
  if (workspace == null) {
    showSnackBar('Select a workspace before creating a board.');
    return;
  }
  if (!context.mounted) return;
  final result = await _form(context, title: 'New board');
  if (result == null) return;
  try {
    await ref
        .read(wattEngineClientProvider)
        .createBroad(result.name, result.description, workspace.id);
    ref.invalidate(broadsProvider);
    showSnackBar('Board created.');
  } catch (error) {
    showSnackBar(error.toString());
  }
}

Future<void> _taskForm(
  BuildContext context,
  WidgetRef ref,
  String broadId, {
  WorkTask? task,
}) async {
  final result = await _form(
    context,
    title: task == null ? 'New task' : 'Edit task',
    task: task,
  );
  if (result == null) return;
  try {
    final client = ref.read(wattEngineClientProvider);
    if (task == null) {
      await client.createTask(broadId, result);
    } else {
      await client.updateTask(task.id, result);
    }
    ref.invalidate(tasksProvider(broadId));
    showSnackBar(task == null ? 'Task created.' : 'Task updated.');
  } catch (error) {
    showSnackBar(error.toString());
  }
}

Future<WorkTaskDraft?> _form(
  BuildContext context, {
  required String title,
  WorkTask? task,
}) {
  final name = TextEditingController(text: task?.name ?? '');
  final description = TextEditingController(text: task?.description ?? '');
  var priority = task?.priority ?? 0;
  return showModalBottomSheet<WorkTaskDraft>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SheetScaffold(
        titleText: title,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Symbols.title),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: description,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Symbols.notes),
                ),
                maxLines: 4,
              ),
              const SizedBox(height: 16),
              Text('Priority', style: Theme.of(context).textTheme.titleSmall),
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
                selected: {priority},
                onSelectionChanged: (values) =>
                    setState(() => priority = values.first),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () {
                  if (name.text.trim().isEmpty) {
                    showSnackBar('Name is required.');
                    return;
                  }
                  Navigator.pop(
                    context,
                    WorkTaskDraft(
                      name: name.text.trim(),
                      description: description.text.trim().isEmpty
                          ? null
                          : description.text.trim(),
                      priority: priority,
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    ),
  ).whenComplete(() {
    name.dispose();
    description.dispose();
  });
}
