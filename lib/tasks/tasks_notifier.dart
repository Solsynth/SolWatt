import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:solwatt/tasks/app_task.dart';

/// In-memory list of background app tasks (Island `tasksProvider` equivalent).
final appTasksProvider = NotifierProvider<AppTasksNotifier, List<AppTask>>(
  AppTasksNotifier.new,
);

class AppTasksNotifier extends Notifier<List<AppTask>> {
  @override
  List<AppTask> build() => const [];

  String addTask({
    required String title,
    required String type,
    AppTaskStatus status = AppTaskStatus.pending,
    Map<String, dynamic>? metadata,
  }) {
    final id = 'task-${DateTime.now().microsecondsSinceEpoch}-${state.length}';
    final now = DateTime.now();
    final task = AppTask(
      id: id,
      title: title,
      status: status,
      createdAt: now,
      updatedAt: now,
      type: type,
      metadata: metadata,
    );
    state = [...state, task];
    return id;
  }

  void updateTask(
    String id, {
    AppTaskStatus? status,
    double? progress,
    String? statusMessage,
    String? errorMessage,
    Map<String, dynamic>? result,
    Map<String, dynamic>? metadata,
  }) {
    state = [
      for (final task in state)
        if (task.id == id)
          task.copyWith(
            status: status,
            progress: progress,
            statusMessage: statusMessage,
            errorMessage: errorMessage,
            result: result,
            metadata: metadata,
            updatedAt: DateTime.now(),
          )
        else
          task,
    ];
  }

  void removeTask(String id) {
    state = [
      for (final task in state)
        if (task.id != id) task,
    ];
  }

  void clearCompleted() {
    state = [
      for (final task in state)
        if (!task.isFinished) task,
    ];
  }

  void clearAll() {
    state = const [];
  }

  AppTask? getTask(String id) {
    for (final task in state) {
      if (task.id == id) return task;
    }
    return null;
  }
}
