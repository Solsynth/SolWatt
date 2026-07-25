import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/tasks/app_task.dart';
import 'package:solwatt/tasks/task_overlay_state.dart';
import 'package:solwatt/tasks/tasks_notifier.dart';
import 'package:solwatt/ui/cloud_files.dart';

double taskOverlayHeight(bool isDesktop) => isDesktop ? 32 : 56;

// --- Shared helpers ---

IconData _taskStatusIcon(AppTask? task) {
  if (task == null) return Symbols.sync;
  return switch (task.status) {
    AppTaskStatus.pending => Symbols.schedule,
    AppTaskStatus.inProgress => switch (task.type) {
      AppTaskType.driveDownload => Symbols.download,
      _ => Symbols.upload,
    },
    AppTaskStatus.paused => Symbols.pause_circle,
    AppTaskStatus.completed => Symbols.check_circle,
    AppTaskStatus.failed => Symbols.error,
    AppTaskStatus.cancelled => Symbols.cancel,
    AppTaskStatus.expired => Symbols.timer_off,
  };
}

Color _taskStatusColor(ColorScheme colorScheme, AppTask? task) {
  if (task == null) return colorScheme.primary;
  return switch (task.status) {
    AppTaskStatus.completed => Colors.green,
    AppTaskStatus.failed ||
    AppTaskStatus.cancelled ||
    AppTaskStatus.expired => colorScheme.error,
    AppTaskStatus.paused => colorScheme.tertiary,
    AppTaskStatus.pending => colorScheme.secondary,
    AppTaskStatus.inProgress => colorScheme.primary,
  };
}

Color _taskStatusFillColor(ColorScheme colorScheme, AppTask? task) {
  if (task == null) return colorScheme.primary;
  return switch (task.status) {
    AppTaskStatus.completed => Colors.green,
    AppTaskStatus.failed ||
    AppTaskStatus.cancelled ||
    AppTaskStatus.expired => Colors.red,
    _ => colorScheme.primary,
  };
}

double _taskIndicatorProgress(AppTask task) {
  if (task.status == AppTaskStatus.completed || task.progress >= 1) {
    return 1;
  }
  if (task.status == AppTaskStatus.pending) return 0;
  return task.progress.clamp(0.0, 1.0);
}

String _taskStatusLabel(AppTaskStatus status) {
  return switch (status) {
    AppTaskStatus.pending => 'Pending',
    AppTaskStatus.inProgress => 'In progress',
    AppTaskStatus.paused => 'Paused',
    AppTaskStatus.completed => 'Completed',
    AppTaskStatus.failed => 'Failed',
    AppTaskStatus.cancelled => 'Cancelled',
    AppTaskStatus.expired => 'Expired',
  };
}

String _taskTypeLabel(String type) {
  return switch (type) {
    AppTaskType.driveUpload => 'Drive upload',
    AppTaskType.driveDownload => 'Drive download',
    _ => type,
  };
}

// --- Host (reserves bar height + auto-clears finished tasks) ---

class TaskOverlayHost extends ConsumerStatefulWidget {
  const TaskOverlayHost({super.key});

  @override
  ConsumerState<TaskOverlayHost> createState() => _TaskOverlayHostState();
}

class _TaskOverlayHostState extends ConsumerState<TaskOverlayHost> {
  Timer? _clearTimer;

  @override
  void dispose() {
    _clearTimer?.cancel();
    super.dispose();
  }

  void _syncAutoClear(List<AppTask> allTasks) {
    final staleCompletedIds = finishedTaskIdsToAutoClear(
      allTasks,
      now: DateTime.now(),
    );
    if (staleCompletedIds.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final notifier = ref.read(appTasksProvider.notifier);
        for (final id in staleCompletedIds) {
          notifier.removeTask(id);
        }
      });
    }

    final nextCompletedTask =
        allTasks
            .where((task) => task.isFinished)
            .where(
              (task) =>
                  DateTime.now().difference(task.updatedAt) <
                  kTaskOverlayCompletedRetention,
            )
            .toList()
          ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));

    _clearTimer?.cancel();
    if (nextCompletedTask.isNotEmpty) {
      final oldestVisibleCompleted = nextCompletedTask.first;
      final remaining =
          kTaskOverlayCompletedRetention -
          DateTime.now().difference(oldestVisibleCompleted.updatedAt);
      _clearTimer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
        if (!mounted) return;
        final notifier = ref.read(appTasksProvider.notifier);
        for (final id in finishedTaskIdsToAutoClear(
          ref.read(appTasksProvider),
          now: DateTime.now(),
        )) {
          notifier.removeTask(id);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final allTasks = ref.watch(appTasksProvider);
    final snapshot = buildTaskOverlaySnapshot(allTasks, now: DateTime.now());
    final isDesktop = DesktopWindowFrame.isPlatformDesktop;

    _syncAutoClear(allTasks);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      height: snapshot.isVisible ? taskOverlayHeight(isDesktop) : 0,
      child: ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: taskOverlayHeight(isDesktop),
            child: const _TaskOverlay(),
          ),
        ),
      ),
    );
  }
}

// --- Sliding bar ---

class _TaskOverlay extends ConsumerStatefulWidget {
  const _TaskOverlay();

  @override
  ConsumerState<_TaskOverlay> createState() => _TaskOverlayState();
}

class _TaskOverlayState extends ConsumerState<_TaskOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideController;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allTasks = ref.watch(appTasksProvider);
    final snapshot = buildTaskOverlaySnapshot(allTasks, now: DateTime.now());
    final isDesktop = DesktopWindowFrame.isPlatformDesktop;
    final overlayHeight = taskOverlayHeight(isDesktop);

    if (snapshot.isVisible) {
      _slideController.forward();
    } else {
      _slideController.reverse();
    }

    if (!snapshot.isVisible &&
        _slideController.status == AnimationStatus.dismissed) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      ignoring:
          !snapshot.isVisible &&
          _slideController.status == AnimationStatus.dismissed,
      child: AnimatedBuilder(
        animation: _slideController,
        builder: (context, child) {
          final offset =
              Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).evaluate(
                CurvedAnimation(
                  parent: _slideController,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                ),
              );
          return FractionalTranslation(translation: offset, child: child);
        },
        child: _TaskOverlayBar(
          snapshot: snapshot,
          height: overlayHeight,
          isDesktop: isDesktop,
        ),
      ),
    );
  }
}

class _TaskOverlayBar extends ConsumerWidget {
  const _TaskOverlayBar({
    required this.snapshot,
    required this.height,
    required this.isDesktop,
  });

  final TaskOverlaySnapshot snapshot;
  final double height;
  final bool isDesktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryTask = snapshot.primaryTask;
    final completedCount = snapshot.visibleTasks
        .where((task) => task.status == AppTaskStatus.completed)
        .length;
    final title = _buildTitle(primaryTask);
    final subtitle = _buildSubtitle(
      primaryTask,
      snapshot.visibleTasks.length,
      completedCount,
    );
    final fillColor = _taskStatusFillColor(colorScheme, primaryTask);
    final trackColor = colorScheme.surfaceContainerHighest;
    final label = '$title · $subtitle';
    final progress = snapshot.progress.clamp(0.0, 1.0);

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showTaskSheet(context),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: trackColor,
                      border: Border(
                        top: BorderSide(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.3,
                          ),
                        ),
                        bottom: BorderSide(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      width: constraints.maxWidth * progress,
                      color: fillColor,
                    ),
                  ),
                  _buildForeground(
                    context,
                    theme,
                    color: Colors.white,
                    text: label,
                  ),
                  ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: _buildForeground(
                          context,
                          theme,
                          color: Colors.white,
                          text: label,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildForeground(
    BuildContext context,
    ThemeData theme, {
    required Color color,
    required String text,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _contentHorizontalPadding(context),
      ),
      child: Row(
        children: [
          Container(
            width: isDesktop ? 22 : 36,
            height: isDesktop ? 22 : 36,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(isDesktop ? 7 : 12),
            ),
            child: Icon(
              _taskStatusIcon(snapshot.primaryTask),
              color: color,
              size: isDesktop ? 14 : 20,
            ),
          ),
          SizedBox(width: isDesktop ? 8 : 12),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: isDesktop ? 13 : null,
                height: 1,
              ),
            ),
          ),
          SizedBox(width: isDesktop ? 8 : 12),
          Text(
            '${(snapshot.progress * 100).round()}%',
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: isDesktop ? 12 : null,
            ),
          ),
          SizedBox(width: isDesktop ? 6 : 8),
          Icon(
            Symbols.expand_less,
            color: color.withValues(alpha: 0.9),
            size: isDesktop ? 14 : 18,
          ),
        ],
      ),
    );
  }

  double _contentHorizontalPadding(BuildContext context) {
    if (isDesktop) return 16;
    final mediaQuery = MediaQuery.of(context);
    return 16 + math.max(mediaQuery.padding.left, mediaQuery.padding.right);
  }

  String _buildTitle(AppTask? task) {
    if (task == null) return 'Tasks';
    if (task.title.isNotEmpty) return task.title;
    return task.status == AppTaskStatus.completed ? 'Completed' : 'Working…';
  }

  String _buildSubtitle(AppTask? task, int visibleCount, int completedCount) {
    final otherCount = visibleCount - 1;
    if (task == null) {
      return visibleCount == 1 ? '1 task' : '$visibleCount tasks';
    }

    if (task.status == AppTaskStatus.completed &&
        completedCount == visibleCount) {
      return completedCount == 1
          ? 'Just finished'
          : '$completedCount finished just now';
    }

    final statusText = task.statusMessage?.trim();
    if (statusText != null && statusText.isNotEmpty) {
      return otherCount > 0 ? '$statusText · +$otherCount more' : statusText;
    }

    final label = _taskStatusLabel(task.status);
    return otherCount > 0 ? '$label · +$otherCount more' : label;
  }

  void _showTaskSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) => const _TasksSheet(),
    );
  }
}

// --- Live tasks sheet ---

class _TasksSheet extends ConsumerWidget {
  const _TasksSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(appTasksProvider);
    final sortedTasks = [...tasks]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final notifier = ref.read(appTasksProvider.notifier);
    final hasFinished = tasks.any((t) => t.isFinished);

    return SheetScaffold(
      titleText: 'Background tasks',
      heightFactor: 0.65,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  sortedTasks.length == 1
                      ? '1 task'
                      : '${sortedTasks.length} tasks',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: hasFinished ? notifier.clearCompleted : null,
                  icon: const Icon(Symbols.done_all, size: 18),
                  label: const Text('Clear done'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: sortedTasks.isEmpty ? null : notifier.clearAll,
                  icon: const Icon(Symbols.delete_sweep, size: 18),
                  label: const Text('Clear all'),
                ),
              ],
            ),
          ),
          Expanded(
            child: sortedTasks.isEmpty
                ? Center(
                    child: Text(
                      'No background tasks',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: sortedTasks.length,
                    itemBuilder: (context, index) {
                      final task = sortedTasks[index];
                      return _AppTaskTile(key: ValueKey(task.id), task: task);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// --- Task tile ---

class _AppTaskTile extends StatefulWidget {
  const _AppTaskTile({super.key, required this.task});

  final AppTask task;

  @override
  State<_AppTaskTile> createState() => _AppTaskTileState();
}

class _AppTaskTileState extends State<_AppTaskTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;
  late final Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progress = _taskIndicatorProgress(task);

    return ExpansionTile(
      leading: Icon(
        _taskStatusIcon(task),
        size: 24,
        color: _taskStatusColor(colorScheme, task),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.title.isEmpty ? 'Untitled' : task.title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            _taskTypeLabel(task.type),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 2.5,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 4),
          AnimatedBuilder(
            animation: _rotationAnimation,
            builder: (context, child) {
              return Transform.rotate(
                angle: _rotationAnimation.value * math.pi,
                child: child,
              );
            },
            child: Icon(
              Symbols.expand_more,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      onExpansionChanged: (expanded) {
        if (expanded) {
          _rotationController.forward();
        } else {
          _rotationController.reverse();
        }
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: _TaskDetailsCard(task: task),
        ),
      ],
    );
  }
}

class _TaskDetailsCard extends StatelessWidget {
  const _TaskDetailsCard({required this.task});

  final AppTask task;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: task.type == AppTaskType.driveUpload
          ? _DriveUploadDetails(task: task)
          : _GenericTaskDetails(task: task),
    );
  }
}

class _DriveUploadDetails extends StatelessWidget {
  const _DriveUploadDetails({required this.task});

  final AppTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final meta = task.metadata;
    final fileSize = meta?['fileSize'] as int? ?? 0;
    final transmissionProgress =
        (meta?['transmissionProgress'] as num?)?.toDouble() ?? task.progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          task.statusMessage ?? 'Uploading…',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(task.progress * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              fileSize > 0
                  ? '${formatByteSize((transmissionProgress * fileSize).toInt())} / ${formatByteSize(fileSize)}'
                  : _taskStatusLabel(task.status),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: _taskIndicatorProgress(task),
          backgroundColor: colorScheme.surface,
        ),
        if (task.errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            task.errorMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _GenericTaskDetails extends StatelessWidget {
  const _GenericTaskDetails({required this.task});

  final AppTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Progress',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(task.progress * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              _taskStatusLabel(task.status),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: task.progress.clamp(0.0, 1.0),
          backgroundColor: colorScheme.surface,
        ),
        if (task.errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            task.errorMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
