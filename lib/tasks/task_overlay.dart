import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
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

double _taskIndicatorProgress(AppTask task) {
  if (task.status == AppTaskStatus.completed || task.progress >= 1) {
    return 1;
  }
  if (task.status == AppTaskStatus.pending) return 0;
  return task.progress.clamp(0.0, 1.0);
}

String _taskStatusLabel(AppTaskStatus status) {
  return switch (status) {
    AppTaskStatus.pending => 'taskStatusPending'.tr(),
    AppTaskStatus.inProgress => 'taskStatusInProgress'.tr(),
    AppTaskStatus.paused => 'taskStatusPaused'.tr(),
    AppTaskStatus.completed => 'taskStatusCompleted'.tr(),
    AppTaskStatus.failed => 'taskStatusFailed'.tr(),
    AppTaskStatus.cancelled => 'taskStatusCancelled'.tr(),
    AppTaskStatus.expired => 'taskStatusExpired'.tr(),
  };
}

String _taskTypeLabel(String type) {
  return switch (type) {
    AppTaskType.driveUpload => 'taskTypeDriveUpload'.tr(),
    AppTaskType.driveDownload => 'taskTypeDriveDownload'.tr(),
    AppTaskType.mailImport => 'taskTypeMailImport'.tr(),
    _ => type,
  };
}

// --- Overlay (slides in above the content, one per shell) ---

class TaskOverlay extends HookConsumerWidget {
  const TaskOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTasks = ref.watch(appTasksProvider);
    final snapshot = buildTaskOverlaySnapshot(allTasks, now: DateTime.now());
    final isDesktop = DesktopWindowFrame.isPlatformDesktop;
    final overlayHeight = taskOverlayHeight(isDesktop);
    final slideController = useAnimationController(
      duration: const Duration(milliseconds: 320),
    );

    useEffect(() {
      if (snapshot.isVisible) {
        slideController.forward();
      } else {
        slideController.reverse();
      }
      return null;
    }, [snapshot.isVisible]);

    if (!snapshot.isVisible &&
        slideController.status == AnimationStatus.dismissed) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      ignoring:
          !snapshot.isVisible &&
          slideController.status == AnimationStatus.dismissed,
      child: AnimatedBuilder(
        animation: slideController,
        builder: (context, child) {
          final offset =
              Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).evaluate(
                CurvedAnimation(
                  parent: slideController,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                ),
              );
          return FractionalTranslation(translation: offset, child: child);
        },
        child: _TaskOverlayBar(height: overlayHeight, isDesktop: isDesktop),
      ),
    );
  }
}

/// Reserves the bar height and auto-clears finished tasks after their
/// retention window.
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
            child: const TaskOverlay(),
          ),
        ),
      ),
    );
  }
}

class _TaskOverlayBar extends ConsumerWidget {
  final double height;
  final bool isDesktop;

  const _TaskOverlayBar({required this.height, required this.isDesktop});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTasks = ref.watch(appTasksProvider);
    final snapshot = buildTaskOverlaySnapshot(allTasks, now: DateTime.now());

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
    final progress = snapshot.progress.clamp(0.0, 1.0);
    final statusColor = _taskStatusColor(colorScheme, primaryTask);
    final progressText = '${(progress * 100).round()}%';
    final label = '$title, $subtitle, $progressText ${'taskProgress'.tr()}';
    final progressIndicator = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return LinearProgressIndicator(
          value: value,
          valueColor: AlwaysStoppedAnimation<Color>(statusColor),
        );
      },
    );
    final backgroundProgress = SizedBox(
      height: 3,
      width: double.infinity,
      child: progressIndicator,
    );

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: colorScheme.surfaceContainerLow,
        child: InkWell(
          onTap: () => _showTaskSheet(context),
          child: SizedBox(
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Align(alignment: Alignment.topLeft, child: backgroundProgress),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    _contentHorizontalPadding(context),
                    3,
                    _contentHorizontalPadding(context),
                    0,
                  ),
                  child: Row(
                    children: [
                      _StatusIcon(
                        icon: _taskStatusIcon(primaryTask),
                        color: statusColor,
                        size: isDesktop ? 22 : 34,
                      ),
                      SizedBox(width: isDesktop ? 9 : 12),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: isDesktop ? 13 : null,
                          ),
                        ),
                      ),
                      SizedBox(width: isDesktop ? 10 : 12),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isDesktop ? 180 : 140,
                        ),
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: isDesktop ? 11 : null,
                          ),
                        ),
                      ),
                      SizedBox(width: isDesktop ? 10 : 12),
                      Text(
                        progressText,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Symbols.expand_less,
                        size: isDesktop ? 16 : 19,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _contentHorizontalPadding(BuildContext context) {
    if (isDesktop) return 16;
    final mediaQuery = MediaQuery.of(context);
    return 16 + math.max(mediaQuery.padding.left, mediaQuery.padding.right);
  }

  String _buildTitle(AppTask? task) {
    if (task == null) return 'tasks'.tr();
    if (task.title.isNotEmpty) return task.title;
    return task.status == AppTaskStatus.completed
        ? 'taskStatusCompleted'.tr()
        : 'taskWorking'.tr();
  }

  String _buildSubtitle(AppTask? task, int visibleCount, int completedCount) {
    final otherCount = visibleCount - 1;
    if (task == null) return 'tasksCount'.plural(visibleCount);

    if (task.status == AppTaskStatus.completed &&
        completedCount == visibleCount) {
      return completedCount == 1
          ? 'taskCompletedJustNow'.tr()
          : 'taskFinishedJustNow'.plural(completedCount);
    }

    final statusText = task.statusMessage?.trim();
    if (statusText != null && statusText.isNotEmpty) {
      return otherCount > 0
          ? '$statusText · ${'taskMoreCount'.tr(args: ['$otherCount'])}'
          : statusText;
    }

    final label = _taskStatusLabel(task.status);
    return otherCount > 0
        ? '$label · ${'taskMoreCount'.tr(args: ['$otherCount'])}'
        : label;
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

class _StatusIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _StatusIcon({
    required this.icon,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(icon, color: color, size: size * 0.68),
      ),
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
    final scheme = Theme.of(context).colorScheme;

    return SheetScaffold(
      titleText: 'tasks'.tr(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'taskTotalCount'.tr(args: ['${sortedTasks.length}']),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'clearCompleted'.tr(),
                  onPressed: hasFinished ? notifier.clearCompleted : null,
                  icon: const Icon(Symbols.done_all),
                ),
                IconButton(
                  tooltip: 'clearAll'.tr(),
                  onPressed: sortedTasks.isEmpty ? null : notifier.clearAll,
                  icon: const Icon(Symbols.delete_sweep),
                ),
              ],
            ),
          ),
          Expanded(
            child: sortedTasks.isEmpty
                ? _EmptyTasksState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    itemCount: sortedTasks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
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

class _EmptyTasksState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.inbox, size: 32, color: scheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            'taskNoTasks'.tr(),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// --- Task tile ---

class _AppTaskTile extends StatelessWidget {
  final AppTask task;

  const _AppTaskTile({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = _taskStatusColor(scheme, task);
    final progress = _taskIndicatorProgress(task);

    return Semantics(
      container: true,
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: _StatusIcon(
              icon: _taskStatusIcon(task),
              color: statusColor,
              size: 38,
            ),
            title: Text(
              task.title.isEmpty ? 'untitled'.tr() : task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              task.statusMessage?.trim().isNotEmpty == true
                  ? task.statusMessage!
                  : _taskTypeLabel(task.type),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TaskProgressIndicator(progress: progress, color: statusColor),
                const SizedBox(width: 4),
                Icon(
                  Symbols.expand_more,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            shape: const RoundedRectangleBorder(),
            collapsedShape: const RoundedRectangleBorder(),
            children: [_TaskDetailsCard(task: task)],
          ),
        ),
      ),
    );
  }
}

class _TaskProgressIndicator extends StatelessWidget {
  final double progress;
  final Color color;

  const _TaskProgressIndicator({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: value,
                strokeWidth: 3,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
              Text(
                '${(value * 100).round()}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TaskProgressBar extends StatelessWidget {
  final double progress;
  final Color color;

  const _TaskProgressBar({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    final indicator = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return LinearProgressIndicator(
          value: value,
          minHeight: 7,
          backgroundColor: Theme.of(context).colorScheme.surface,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        );
      },
    );
    return ClipRRect(borderRadius: BorderRadius.circular(6), child: indicator);
  }
}

class _TaskDetailsCard extends StatelessWidget {
  final AppTask task;

  const _TaskDetailsCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: switch (task.type) {
        AppTaskType.driveUpload => _DriveUploadDetails(task: task),
        AppTaskType.mailImport => _MailImportDetails(task: task),
        _ => _GenericTaskDetails(task: task),
      },
    );
  }
}

class _DriveUploadDetails extends StatelessWidget {
  final AppTask task;

  const _DriveUploadDetails({required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = task.metadata;
    final fileSize = (meta?['fileSize'] as num?)?.toInt() ?? 0;
    final transmissionProgress =
        (meta?['transmissionProgress'] as num?)?.toDouble() ?? task.progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailSectionHeader(
          label: task.statusMessage ?? 'taskProcessing'.tr(),
          color: scheme.primary,
        ),
        const SizedBox(height: 7),
        _ProgressRow(
          left: '${(transmissionProgress * 100).toStringAsFixed(1)}%',
          right:
              '${formatByteSize((transmissionProgress * fileSize).toInt())} / ${formatByteSize(fileSize)}',
        ),
        const SizedBox(height: 5),
        _TaskProgressBar(progress: task.progress, color: scheme.primary),
        if (task.errorMessage != null) ...[
          const SizedBox(height: 12),
          _ErrorText(message: task.errorMessage!),
        ],
      ],
    );
  }
}

/// Live import summary for a mail-import background task: the progress bar
/// plus running imported / duplicate / failed counters from [AppTask.metadata].
class _MailImportDetails extends StatelessWidget {
  final AppTask task;

  const _MailImportDetails({required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = task.metadata;
    final imported = meta?['imported'] as int? ?? 0;
    final duplicates = meta?['duplicates'] as int? ?? 0;
    final failed = meta?['failed'] as int? ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailSectionHeader(
          label: task.statusMessage ?? 'taskImporting'.tr(),
          color: scheme.primary,
        ),
        const SizedBox(height: 7),
        _ProgressRow(
          left: '${(task.progress * 100).toStringAsFixed(1)}%',
          right: _taskStatusLabel(task.status),
        ),
        const SizedBox(height: 5),
        _TaskProgressBar(progress: task.progress, color: scheme.primary),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _ImportCount(
              label: 'importImported'.tr(),
              value: imported,
              color: Colors.green,
            ),
            _ImportCount(
              label: 'importDuplicates'.tr(),
              value: duplicates,
              color: scheme.tertiary,
            ),
            _ImportCount(
              label: 'importFailed'.tr(),
              value: failed,
              color: scheme.error,
            ),
          ],
        ),
        if (task.errorMessage != null) ...[
          const SizedBox(height: 12),
          _ErrorText(message: task.errorMessage!),
        ],
      ],
    );
  }
}

class _ImportCount extends StatelessWidget {
  const _ImportCount({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          '$value',
          style: theme.textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _GenericTaskDetails extends StatelessWidget {
  final AppTask task;

  const _GenericTaskDetails({required this.task});

  @override
  Widget build(BuildContext context) {
    return _ProgressDetails(
      label: 'taskProgress'.tr(),
      progress: task.progress,
      right: _taskStatusLabel(task.status),
      errorMessage: task.errorMessage,
    );
  }
}

class _ProgressDetails extends StatelessWidget {
  final String label;
  final double progress;
  final String right;
  final String? errorMessage;

  const _ProgressDetails({
    required this.label,
    required this.progress,
    required this.right,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailSectionHeader(label: label, color: scheme.primary),
        const SizedBox(height: 7),
        _ProgressRow(
          left: '${(progress * 100).toStringAsFixed(1)}%',
          right: right,
        ),
        const SizedBox(height: 5),
        _TaskProgressBar(progress: progress, color: scheme.primary),
        if (errorMessage != null) ...[
          const SizedBox(height: 12),
          _ErrorText(message: errorMessage!),
        ],
      ],
    );
  }
}

class _DetailSectionHeader extends StatelessWidget {
  final String label;
  final Color color;

  const _DetailSectionHeader({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String left;
  final String right;

  const _ProgressRow({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        Expanded(
          child: Text(
            left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: style?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  final String message;

  const _ErrorText({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Symbols.error, size: 16, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
