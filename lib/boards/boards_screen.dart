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

    return PageScaffold(
      title: 'Boards',
      subtitle: workspace == null ? 'Ideask boards' : 'In ${workspace.name}',
      action: IconButton(
        icon: const Icon(Symbols.add),
        tooltip: 'New board',
        onPressed: () => _boardForm(context, ref),
      ),
      child: boards.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(broadsProvider),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Symbols.view_kanban,
                      size: 40,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No boards yet.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create a board to organize tasks in this workspace.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => _boardForm(context, ref),
                      icon: const Icon(Symbols.add),
                      label: const Text('New board'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final board = items[index];
              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                leading: const Icon(Symbols.view_kanban),
                title: Text(board.name),
                subtitle: board.description?.isNotEmpty == true
                    ? Text(board.description!)
                    : null,
                trailing: const Icon(Symbols.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        TaskBoardPage(broadId: board.id, broadName: board.name),
                  ),
                ),
              );
            },
          );
        },
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

    return Scaffold(
      appBar: AppBar(
        title: Text(broadName),
        actions: [
          IconButton(
            icon: const Icon(Symbols.add_task),
            tooltip: 'New task',
            onPressed: () => _taskForm(context, ref, broadId),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: tasks.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(error.toString())),
          data: (items) {
            if (items.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No tasks yet.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _taskForm(context, ref, broadId),
                      icon: const Icon(Symbols.add_task),
                      label: const Text('New task'),
                    ),
                  ],
                ),
              );
            }

            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final task = items[index];
                return ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  leading: Icon(
                    Symbols.radio_button_unchecked,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(task.name),
                  subtitle: Text(
                    task.description?.isNotEmpty == true
                        ? task.description!
                        : _priorityLabel(task.priority),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Symbols.delete),
                    onPressed: () async {
                      await ref
                          .read(wattEngineClientProvider)
                          .deleteTask(task.id);
                      ref.invalidate(tasksProvider(broadId));
                    },
                  ),
                  onTap: () => _taskForm(context, ref, broadId, task: task),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

String _priorityLabel(int priority) {
  return switch (priority) {
    1 => 'High priority',
    2 => 'Urgent',
    _ => 'Normal priority',
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
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SheetScaffold(
        titleText: title,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 4,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Normal')),
                  DropdownMenuItem(value: 1, child: Text('High')),
                  DropdownMenuItem(value: 2, child: Text('Urgent')),
                ],
                onChanged: (value) => setState(() => priority = value ?? 0),
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
