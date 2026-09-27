part of 'boards_screen.dart';

/// One board: a header that names it, a toolbar that narrows it, the lanes,
/// and the task detail sidebar.
///
/// Reached through the boards tab's nested stack, so the app shell (navigation
/// rail / bottom bar) stays visible and Back returns to the board list.
@RoutePage()
class TaskBoardPage extends ConsumerStatefulWidget {
  const TaskBoardPage({super.key, @PathParam('broadId') required this.broadId});

  final String broadId;

  @override
  ConsumerState<TaskBoardPage> createState() => _TaskBoardPageState();
}

class _TaskBoardPageState extends ConsumerState<TaskBoardPage> {
  /// Lane moves that the server has not confirmed yet, keyed by task id. Lets
  /// a card show up in the lane it was dropped into before the round trip.
  final Map<String, String?> _groupOverrides = {};
  final ValueNotifier<bool> _showTaskDetail = ValueNotifier(false);

  /// The task the detail surface is showing, or null when none is open. A
  /// notifier because the phone sheet and the wide panel are both built once
  /// and then have to follow the detail fetch and lane moves.
  final ValueNotifier<WorkTask?> _selectedTask = ValueNotifier(null);
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  TaskListFilters _filters = const TaskListFilters();

  String get _broadId => widget.broadId;
  TaskListRequest get _taskRequest =>
      TaskListRequest(broadId: _broadId, filters: _filters);

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    _showTaskDetail.dispose();
    _selectedTask.dispose();
    super.dispose();
  }

  void _setFilters(TaskListFilters filters) =>
      setState(() => _filters = filters);

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _setFilters(
        _filters.copyWith(search: value, clearSearch: value.trim().isEmpty),
      );
    });
  }

  /// Opens the task detail: a resizable panel beside the board on wide
  /// screens, a sheet over it on phones. `ResponsiveSidebar` picks the form
  /// factor; [_taskDetailSheet] supplies the phone sheet's chrome.
  Future<void> _openTask(WorkTask task) async {
    _selectedTask.value = task;
    _showTaskDetail.value = true;

    // Cards carry what the list endpoint returns; the detail view wants the
    // full record. Keep the card's copy if the fetch fails.
    try {
      final detailed = await ref
          .read(wattEngineClientProvider)
          .getTask(task.id);
      if (!mounted || _selectedTask.value?.id != task.id) return;
      _selectedTask.value = detailed;
    } catch (_) {}
  }

  /// The phone detail sheet. Taller than the panel convention because a task
  /// record is long, and sized here rather than in the shared sidebar so the
  /// board controls how much of the board stays visible behind it.
  Widget _taskDetailSheet(BuildContext sheetContext) {
    return SheetScaffold(
      showHeader: false,
      heightFactor: 0.85,
      // The shared sidebar opens this sheet through the `material_ui` fork's
      // `showModalBottomSheet`, so the sheet's own Material is the fork's. The
      // detail body is built from Flutter widgets that assert a Flutter
      // `Material` ancestor (the group dropdown, the comment field), so it
      // brings its own.
      child: Material(
        color: Colors.transparent,
        child: _taskDetail(onClose: () => Navigator.of(sheetContext).pop()),
      ),
    );
  }

  /// The detail body, shared by the wide panel and the phone sheet. It follows
  /// [_selectedTask] so the detail fetch and lane moves land on screen without
  /// reopening the surface; [onClose] closes whichever one is showing it.
  Widget _taskDetail({required VoidCallback onClose}) {
    return ValueListenableBuilder<WorkTask?>(
      valueListenable: _selectedTask,
      builder: (context, task, _) => task == null
          ? const SizedBox.shrink()
          : _TaskDetailSidebar(
              task: task,
              broadId: _broadId,
              onClose: onClose,
              onEdit: () => _taskForm(context, ref, _broadId, task: task),
              onToggleComplete: () =>
                  _toggleTaskComplete(context, ref, _broadId, task),
              onMoveTask: (groupId) => _onMoveTask(task, groupId),
            ),
    );
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

    setState(() {
      _groupOverrides[task.id] = targetGroupId;
      if (_selectedTask.value?.id == task.id) {
        _selectedTask.value = _selectedTask.value!.withGroupId(targetGroupId);
      }
    });

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
      ref.invalidate(tasksProvider(_taskRequest));
      await ref.read(tasksProvider(_taskRequest).future);
      if (!mounted) return;
      setState(() => _groupOverrides.remove(task.id));
    } catch (error) {
      if (!mounted) return;
      setState(() => _groupOverrides.remove(task.id));
      showSnackBar(error.toString());
      ref.invalidate(tasksProvider(_taskRequest));
    }
  }

  @override
  Widget build(BuildContext context) {
    final broads = ref.watch(broadsProvider);
    final broad = broads.value?.firstWhereOrNull((item) => item.id == _broadId);
    final scheme = Theme.of(context).colorScheme;
    final wide = isWideScreen(context);

    if (broad == null) {
      return Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(titleSpacing: 0, leading: const _BoardBackButton()),
        body: broads.isLoading
            ? const PageLoading()
            : EmptyState(
                icon: Symbols.view_kanban,
                title: 'boardUnavailable'.tr(),
                message: 'boardUnavailableDetail'.tr(),
                action: FilledButton(
                  onPressed: () => _popBoard(context),
                  child: Text('boards'.tr()),
                ),
              ),
      );
    }

    final tasks = ref.watch(tasksProvider(_taskRequest));
    final groups = ref.watch(taskGroupsProvider(_broadId));
    final groupItems = groups.asData?.value ?? const <TaskGroup>[];
    final taskCount = tasks.asData?.value.length;

    void openFilters() =>
        _showTaskFilters(context, groupItems, _filters, _setFilters);
    void openGitHub() => showGitHubIntegrationSheet(
      context,
      ref,
      broadId: _broadId,
      broadName: broad.name,
    );
    void openGroups() => _manageGroups(context, ref, _broadId);
    void newTask({String? groupId}) =>
        _taskForm(context, ref, _broadId, initialGroupId: groupId);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        // The board list is the previous route of the tab's nested stack, so
        // Back always has somewhere to go.
        leading: const _BoardBackButton(),
        titleSpacing: 0,
        toolbarHeight: wide ? 68 : null,
        title: _BoardHeading(board: broad, showDescription: wide),
        actions: [
          if (wide) ...[
            IconButton(
              icon: const Icon(Symbols.hub),
              tooltip: 'githubIntegration'.tr(),
              onPressed: openGitHub,
            ),
            IconButton(
              icon: const Icon(Symbols.view_column),
              tooltip: 'manageGroups'.tr(),
              onPressed: openGroups,
            ),
            IconButton(
              icon: Badge(
                isLabelVisible: !_filters.isEmpty,
                child: const Icon(Symbols.filter_list),
              ),
              tooltip: 'taskFilters'.tr(),
              onPressed: openFilters,
            ),
            IconButton.filledTonal(
              icon: const Icon(Symbols.add_task),
              tooltip: 'newTask'.tr(),
              onPressed: newTask,
            ),
            const SizedBox(width: 8),
          ] else ...[
            IconButton.filledTonal(
              icon: const Icon(Symbols.add_task),
              tooltip: 'newTask'.tr(),
              onPressed: newTask,
            ),
            _BoardOverflowMenu(
              onGitHub: openGitHub,
              onGroups: openGroups,
              onFilters: openFilters,
              hasFilters: !_filters.isEmpty,
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
      body: ResponsiveSidebar(
        showSidebar: _showTaskDetail,
        sidebarWidth: 460,
        minWideSidebarWidth: 360,
        minMainContentWidth: 320,
        drawerBuilder: _taskDetailSheet,
        sidebarContent: _taskDetail(
          onClose: () => _showTaskDetail.value = false,
        ),
        mainContent: Column(
          children: [
            _BoardToolbar(
              controller: _search,
              onSearchChanged: _onSearchChanged,
              onSearchCleared: () {
                _search.clear();
                _onSearchChanged('');
              },
              filters: _filters,
              groups: groupItems,
              taskCount: taskCount,
              onFiltersChanged: _setFilters,
              onOpenFilters: openFilters,
            ),
            Expanded(
              child: tasks.when(
                loading: () => const PageLoading(),
                error: (error, _) => PageError(
                  message: error.toString(),
                  onRetry: () {
                    ref.invalidate(tasksProvider(_taskRequest));
                    ref.invalidate(taskGroupsProvider(_broadId));
                  },
                ),
                data: (taskItems) => groups.when(
                  loading: () => const PageLoading(),
                  error: (error, _) => PageError(
                    message: error.toString(),
                    onRetry: () => ref.invalidate(taskGroupsProvider(_broadId)),
                  ),
                  data: (groupItems) {
                    final columns = _buildColumns(
                      groupItems,
                      _effectiveTasks(taskItems),
                    );
                    if (columns.every((column) => column.tasks.isEmpty) &&
                        _filters.isEmpty) {
                      return EmptyState(
                        icon: Symbols.task_alt,
                        title: 'noTasksYet'.tr(),
                        message: 'addTaskOrCreateGroups'.tr(),
                        action: FilledButton.icon(
                          onPressed: newTask,
                          icon: const Icon(Symbols.add_task),
                          label: Text('newTask'.tr()),
                        ),
                      );
                    }
                    // An empty board lands here only when a filter is what
                    // emptied it: an unfiltered board always shows its lanes
                    // so a task can be created straight into one.
                    if (columns.every((column) => column.tasks.isEmpty)) {
                      return EmptyState(
                        icon: Symbols.filter_alt_off,
                        title: 'noMatchingTasks'.tr(),
                        message: 'noMatchingTasksDetail'.tr(),
                        action: FilledButton.icon(
                          onPressed: () => _setFilters(const TaskListFilters()),
                          icon: const Icon(Symbols.filter_alt_off),
                          label: Text('clearFilters'.tr()),
                        ),
                      );
                    }

                    if (groupItems.isEmpty) {
                      final only = columns.single;
                      return Center(
                        child: SizedBox(
                          width: _TaskLane.width,
                          child: _TaskLane(
                            column: only,
                            color: _laneColor(0),
                            onOpenTask: _openTask,
                            onToggleComplete: (task) => _toggleTaskComplete(
                              context,
                              ref,
                              _broadId,
                              task,
                            ),
                            onDeleteTask: (task) =>
                                _deleteTask(context, ref, _broadId, task),
                            onMoveTask: (task, groupId) =>
                                _onMoveTask(task, groupId),
                            onAddTask: () => newTask(groupId: only.groupId),
                            laneOptions: columns,
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: columns.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final column = columns[index];
                        return _TaskLane(
                          column: column,
                          color: _laneColor(index),
                          onOpenTask: _openTask,
                          onToggleComplete: (task) =>
                              _toggleTaskComplete(context, ref, _broadId, task),
                          onDeleteTask: (task) =>
                              _deleteTask(context, ref, _broadId, task),
                          onMoveTask: (task, groupId) =>
                              _onMoveTask(task, groupId),
                          onAddTask: () => newTask(groupId: column.groupId),
                          laneOptions: columns,
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Back into the board list. The nested stack normally holds it; a deep link
/// straight to one board replaces the stack root with the list.
void _popBoard(BuildContext context) {
  final router = context.router;
  unawaited(
    router.maybePop().then((popped) {
      if (!popped && context.mounted) router.replace(const BoardsListRoute());
    }),
  );
}

class _BoardBackButton extends StatelessWidget {
  const _BoardBackButton();

  @override
  Widget build(BuildContext context) {
    // The board list is the previous route of the tab's nested stack; a deep
    // link straight to one board falls back to the list.
    return IconButton(
      tooltip: 'back'.tr(),
      onPressed: () => _popBoard(context),
      icon: const Icon(Symbols.arrow_back),
    );
  }
}

/// Board identity in the app bar: cover-derived icon, name, its task prefix and
/// (on wide screens) the one-line description.
class _BoardHeading extends StatelessWidget {
  const _BoardHeading({required this.board, required this.showDescription});

  final Broad board;
  final bool showDescription;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final prefix = board.taskPrefix?.trim();
    final description = board.description?.trim();
    final showSubtitle = showDescription && description?.isNotEmpty == true;

    return Row(
      children: [
        CloudFileAvatar(
          file: board.iconImage,
          fallbackIcon: Symbols.view_kanban,
          size: 32,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      board.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (prefix?.isNotEmpty == true) ...[
                    const SizedBox(width: 8),
                    _PrefixStamp(prefix!),
                  ],
                ],
              ),
              if (showSubtitle)
                Text(
                  description!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Phone app-bar actions that do not earn a slot of their own.
class _BoardOverflowMenu extends StatelessWidget {
  const _BoardOverflowMenu({
    required this.onGitHub,
    required this.onGroups,
    required this.onFilters,
    required this.hasFilters,
  });

  final VoidCallback onGitHub;
  final VoidCallback onGroups;
  final VoidCallback onFilters;
  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'more'.tr(),
      icon: Badge(
        isLabelVisible: hasFilters,
        child: const Icon(Symbols.more_vert),
      ),
      onSelected: (value) => switch (value) {
        'github' => onGitHub(),
        'groups' => onGroups(),
        _ => onFilters(),
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'github',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Symbols.hub),
            title: Text('githubIntegration'.tr()),
          ),
        ),
        PopupMenuItem(
          value: 'groups',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Symbols.view_column),
            title: Text('manageGroups'.tr()),
          ),
        ),
        PopupMenuItem(
          value: 'filters',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Symbols.filter_list),
            title: Text('taskFilters'.tr()),
          ),
        ),
      ],
    );
  }
}

/// Search, the count of what is on screen, and the filters currently applied.
class _BoardToolbar extends StatelessWidget {
  const _BoardToolbar({
    required this.controller,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.filters,
    required this.groups,
    required this.taskCount,
    required this.onFiltersChanged,
    required this.onOpenFilters,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final TaskListFilters filters;
  final List<TaskGroup> groups;
  final int? taskCount;
  final ValueChanged<TaskListFilters> onFiltersChanged;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            // A board-wide search field reads as a caption bar; capped at a
            // field's width it stays a control.
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SizedBox(
                width: 380,
                child: TextField(
                  controller: controller,
                  onChanged: onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'searchTasks'.tr(),
                    prefixIcon: const Icon(Symbols.search, size: 20),
                    suffixIcon: ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => controller.text.isEmpty
                          ? const SizedBox.shrink()
                          : IconButton(
                              tooltip: 'clearSearch'.tr(),
                              icon: const Icon(Symbols.close, size: 18),
                              onPressed: onSearchCleared,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (taskCount case final int count) ...[
            const SizedBox(width: 12),
            Text(
              'tasksCount'.plural(count),
              style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'taskFilters'.tr(),
            onPressed: onOpenFilters,
            icon: Badge(
              isLabelVisible: !filters.isEmpty,
              child: const Icon(Symbols.filter_list, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

/// One lane: its identity rail, how much of it is done, and its tasks.
class _TaskLane extends StatelessWidget {
  const _TaskLane({
    required this.column,
    required this.color,
    required this.onOpenTask,
    required this.onToggleComplete,
    required this.onDeleteTask,
    required this.onMoveTask,
    required this.onAddTask,
    required this.laneOptions,
  });

  final _TaskColumn column;
  final Color color;
  final ValueChanged<WorkTask> onOpenTask;
  final ValueChanged<WorkTask> onToggleComplete;
  final ValueChanged<WorkTask> onDeleteTask;
  final void Function(WorkTask task, String? groupId) onMoveTask;
  final VoidCallback onAddTask;
  final List<_TaskColumn> laneOptions;

  static const double width = 300;
  static const double _bodyPadding = 10;

  bool _accepts(WorkTask task) => column.isUngrouped
      ? task.groupId != null
      : task.groupId != column.groupId;

  Future<void> _pickLane(BuildContext context, WorkTask task) async {
    final target = await showModalBottomSheet<_TaskColumn>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MoveTaskSheet(
        task: task,
        lanes: laneOptions,
        currentGroupId: column.groupId,
      ),
    );
    if (target == null) return;
    onMoveTask(task, target.groupId);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final laneSurface = scheme.surfaceContainerLow;

    return DragTarget<WorkTask>(
      onWillAcceptWithDetails: (details) => _accepts(details.data),
      onAcceptWithDetails: (details) =>
          onMoveTask(details.data, column.groupId),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return SizedBox(
          width: width,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: hovering
                  ? Color.alphaBlend(color.withValues(alpha: 0.07), laneSurface)
                  : laneSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hovering
                    ? color.withValues(alpha: 0.6)
                    : scheme.outlineVariant,
                width: hovering ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 4, 6),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 16,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          column.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
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
                  child: column.tasks.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              hovering
                                  ? 'dropTaskHere'.tr()
                                  : column.isUngrouped
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
                          padding: const EdgeInsets.fromLTRB(
                            _bodyPadding,
                            0,
                            _bodyPadding,
                            12,
                          ),
                          itemCount: column.tasks.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final task = column.tasks[index];
                            return _DraggableTaskCard(
                              width: width - _bodyPadding * 2,
                              task: task,
                              onOpen: () => onOpenTask(task),
                              onToggleComplete: () => onToggleComplete(task),
                              onDelete: () => onDeleteTask(task),
                              onMove: () => _pickLane(context, task),
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

class _DraggableTaskCard extends StatelessWidget {
  const _DraggableTaskCard({
    required this.width,
    required this.task,
    required this.onOpen,
    required this.onToggleComplete,
    required this.onDelete,
    required this.onMove,
  });

  final double width;
  final WorkTask task;
  final VoidCallback onOpen;
  final VoidCallback onToggleComplete;
  final VoidCallback onDelete;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context) {
    final card = _TaskCard(
      task: task,
      onOpen: onOpen,
      onToggleComplete: onToggleComplete,
      onDelete: onDelete,
      onMove: onMove,
    );

    // `affinity` (not `axis`) is what keeps the lane scrollable: it makes the
    // card compete for horizontal drags only, so a vertical drag inside the
    // lane still reaches its list.
    return Draggable<WorkTask>(
      data: task,
      affinity: Axis.horizontal,
      maxSimultaneousDrags: 1,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: Colors.transparent,
        child: SizedBox(
          width: width,
          child: Opacity(opacity: 0.92, child: card),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: IgnorePointer(child: card),
      ),
      child: card,
    );
  }
}

/// A task, as a ticket: identity stamp, title, and one dense meta line. The
/// card's left rail is the only colour on it and it is only there when the task
/// asks for attention (overdue, urgent, high) — a silent rail means "normal".
class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.onOpen,
    required this.onToggleComplete,
    required this.onDelete,
    required this.onMove,
  });

  final WorkTask task;
  final VoidCallback onOpen;
  final VoidCallback onToggleComplete;
  final VoidCallback onDelete;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final attention = _attentionColor(scheme, task);
    final meta = _cardMeta(context, task);

    return Material(
      color: _raisedSurface(scheme, scheme.brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: attention?.withValues(alpha: 0.35) ?? scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: IconButton(
                          tooltip: task.isCompleted
                              ? 'reopenTask'.tr()
                              : 'markCompleted'.tr(),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          onPressed: onToggleComplete,
                          icon: Icon(
                            task.isCompleted
                                ? Symbols.check_circle
                                : Symbols.radio_button_unchecked,
                            size: 20,
                            color: task.isCompleted
                                ? scheme.tertiary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (task.displayKey case final key?) ...[
                              _KeyStamp(key),
                              const SizedBox(height: 2),
                            ],
                            Text(
                              task.name,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                                decoration: task.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: task.isCompleted
                                    ? scheme.onSurfaceVariant
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'more'.tr(),
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Symbols.more_vert,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                        onPressed: () => _showCardMenu(context),
                      ),
                    ],
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 34, right: 8),
                      child: Wrap(spacing: 10, runSpacing: 4, children: meta),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (attention != null)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: ColoredBox(color: attention),
            ),
        ],
      ),
    );
  }

  Future<void> _showCardMenu(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.open_in_new),
              title: Text('openTask'.tr()),
              onTap: () => Navigator.pop(context, 'open'),
            ),
            ListTile(
              leading: const Icon(Symbols.swap_horiz),
              title: Text('moveToGroup'.tr()),
              onTap: () => Navigator.pop(context, 'move'),
            ),
            ListTile(
              leading: const Icon(Symbols.delete),
              title: Text('deleteTask'.tr()),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'open':
        onOpen();
      case 'move':
        onMove();
      case 'delete':
        onDelete();
    }
  }
}

class _KeyStamp extends StatelessWidget {
  const _KeyStamp(this.value, {this.style});

  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        value,
        style: (style ?? Theme.of(context).textTheme.labelSmall)?.copyWith(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? scheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: tint),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: tint,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Deadline, priority, tags, files, assignees and the GitHub link for a card,
/// as order-preserving icon+text items. Nothing is shown for a default value:
/// an absent item is information, not a gap.
List<Widget> _cardMeta(BuildContext context, WorkTask task) {
  final scheme = Theme.of(context).colorScheme;
  final text = Theme.of(context).textTheme;
  final items = <Widget>[];
  final deadline = task.deadlineAt;

  if (deadline != null) {
    final overdue = _isOverdue(task);
    items.add(
      _MetaItem(
        icon: Symbols.event,
        label: _dueLabel(deadline),
        color: overdue
            ? scheme.error
            : _isDueToday(deadline)
            ? scheme.tertiary
            : null,
      ),
    );
  }
  if (task.priority > 0) {
    final priority = _priorityMeta(task.priority);
    items.add(
      _MetaItem(
        icon: priority.icon,
        label: priority.label,
        color: _toneColor(scheme, priority.tone),
      ),
    );
  }
  for (final tag in task.tags.take(2)) {
    items.add(_MetaItem(icon: Symbols.label, label: tag));
  }
  if (task.tags.length > 2) {
    items.add(
      _MetaItem(icon: Symbols.label, label: '+${task.tags.length - 2}'),
    );
  }
  if (task.attachments.isNotEmpty) {
    items.add(
      _MetaItem(icon: Symbols.attach_file, label: '${task.attachments.length}'),
    );
  }
  if (task.assignees.isNotEmpty) {
    items.add(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AssigneeStack(assignees: task.assignees),
          if (task.assignees.length > 1) ...[
            const SizedBox(width: 4),
            Text(
              '${task.assignees.length}',
              style: text.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
  if (task.gitHubIssue case final issue?) {
    items.add(
      _MetaItem(
        icon: issue.isPullRequest ? Symbols.call_split : Symbols.hub,
        label: issue.label,
        color: scheme.primary,
      ),
    );
  }
  return items;
}

/// Overlapping initials for a card's assignees; the sidebar lists them in full.
class _AssigneeStack extends StatelessWidget {
  const _AssigneeStack({required this.assignees});

  final List<TaskAssignee> assignees;

  @override
  Widget build(BuildContext context) {
    const size = 18.0;
    final scheme = Theme.of(context).colorScheme;
    final shown = assignees.take(3).toList();
    return SizedBox(
      width: size + (shown.length - 1) * (size - 6),
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var index = 0; index < shown.length; index++)
            Positioned(
              left: index * (size - 6),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _raisedSurface(scheme, scheme.brightness),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(shown[index].label),
                  style: TextStyle(
                    fontSize: size * 0.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _initials(String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.characters.first.toUpperCase();
}

class _TaskDetailSidebar extends ConsumerWidget {
  const _TaskDetailSidebar({
    required this.task,
    required this.broadId,
    required this.onClose,
    required this.onEdit,
    required this.onToggleComplete,
    required this.onMoveTask,
  });

  final WorkTask task;

  /// The board the task belongs to: the list endpoint may omit it on the task.
  final String broadId;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onToggleComplete;
  final ValueChanged<String?> onMoveTask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final groups =
        ref.watch(taskGroupsProvider(broadId)).asData?.value ??
        const <TaskGroup>[];
    final completeLabel = _completeReasonLabel(task.completeReason);
    final priority = _priorityMeta(task.priority);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
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
                  if (task.displayKey case final key?)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _KeyStamp(key, style: text.labelLarge),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    task.name,
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      decoration: task.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    onPressed: onToggleComplete,
                    icon: Icon(
                      task.isCompleted
                          ? Symbols.radio_button_unchecked
                          : Symbols.check_circle,
                      size: 20,
                    ),
                    label: Text(
                      task.isCompleted
                          ? 'reopenTask'.tr()
                          : 'markCompleted'.tr(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _PropertyRow(
                    icon: Symbols.hub,
                    label: 'status'.tr(),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: StatusChip(
                        label: completeLabel ?? 'open'.tr(),
                        icon: task.isCompleted
                            ? Symbols.done_all
                            : Symbols.pending,
                        tone: task.isCompleted
                            ? StatusChipTone.secondary
                            : StatusChipTone.neutral,
                      ),
                    ),
                  ),
                  _PropertyRow(
                    icon: priority.icon,
                    label: 'priority'.tr(),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: StatusChip(
                        label: priority.label,
                        icon: priority.icon,
                        tone: priority.tone,
                      ),
                    ),
                  ),
                  _PropertyRow(
                    icon: Symbols.view_column,
                    label: 'group'.tr(),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        isDense: true,
                        isExpanded: true,
                        value: groups.any((group) => group.id == task.groupId)
                            ? task.groupId
                            : null,
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('ungrouped'.tr()),
                          ),
                          for (final group in groups)
                            DropdownMenuItem<String?>(
                              value: group.id,
                              child: Text(group.name),
                            ),
                        ],
                        onChanged: onMoveTask,
                      ),
                    ),
                  ),
                  if (task.deadlineAt case final deadline?)
                    _PropertyRow(
                      icon: Symbols.event,
                      label: 'deadline'.tr(),
                      child: Text(
                        _formatDeadline(deadline),
                        style: text.bodyMedium?.copyWith(
                          color: _isOverdue(task)
                              ? scheme.error
                              : scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (task.displayDescription case final description?) ...[
                    const SizedBox(height: 12),
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final assignee in task.assignees)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: scheme.primaryContainer,
                                  foregroundColor: scheme.onPrimaryContainer,
                                  child: Text(
                                    _initials(assignee.label),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    assignee.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (task.attachments.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('attachments'.tr(), style: text.titleSmall),
                    const SizedBox(height: 8),
                    CloudFileAttachmentList(
                      files: task.attachments,
                      workspaceId: ref
                          .watch(selectedWorkspaceProvider)
                          .value
                          ?.id,
                    ),
                  ],
                  if (task.gitHubIssue case final issue?) ...[
                    const SizedBox(height: 20),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        issue.isPullRequest ? Symbols.call_split : Symbols.hub,
                        color: scheme.primary,
                      ),
                      title: Text(issue.label),
                      subtitle: Text(
                        issue.htmlUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Symbols.open_in_new),
                      onTap: () => _openExternalUrl(issue.htmlUrl),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),
                  // Keyed by task id: the comment composer is per-task state and
                  // must not carry a draft from the previously opened task.
                  TaskCommentsSection(key: ValueKey(task.id), taskId: task.id),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PropertyRow extends StatelessWidget {
  const _PropertyRow({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: child),
        ],
      ),
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
    ref.invalidate(tasksProvider);
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
    ref.invalidate(tasksProvider);
    showSnackBar('taskDeleted'.tr());
  } catch (error) {
    showSnackBar(error.toString());
  }
}

/// Lane identity colours. Mid tones so the rail and the meter stay legible on
/// both the light and the dark lane surface; hues picked to stay clear of the
/// amber primary and of the semantic error/tertiary tones.
const List<Color> _laneColors = [
  Color(0xFF3E6C9E),
  Color(0xFF2A7F72),
  Color(0xFF7A5BA8),
  Color(0xFFA85A79),
  Color(0xFF5E7F42),
  Color(0xFFA8703A),
];

Color _laneColor(int index) => _laneColors[index % _laneColors.length];

Color _toneColor(ColorScheme scheme, StatusChipTone tone) => switch (tone) {
  StatusChipTone.primary => scheme.primary,
  StatusChipTone.secondary => scheme.secondary,
  StatusChipTone.tertiary => scheme.tertiary,
  StatusChipTone.error => scheme.error,
  StatusChipTone.neutral => scheme.onSurfaceVariant,
};

/// The card's left rail: `null` when the task asks for nothing in particular.
Color? _attentionColor(ColorScheme scheme, WorkTask task) {
  if (task.isCompleted) return null;
  if (_isOverdue(task)) return scheme.error;
  if (task.priority <= 0) return null;
  return _toneColor(scheme, _priorityMeta(task.priority).tone);
}

bool _isOverdue(WorkTask task) {
  final deadline = task.deadlineAt;
  if (deadline == null || task.isCompleted) return false;
  return deadline.isBefore(DateTime.now());
}

bool _isDueToday(DateTime deadline) => _daysUntil(deadline) == 0;

int _daysUntil(DateTime deadline) {
  final now = DateTime.now();
  final local = deadline.toLocal();
  return DateTime(
    local.year,
    local.month,
    local.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
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

String _statusLabel(TaskStatus status) => switch (status) {
  TaskStatus.open => 'open'.tr(),
  TaskStatus.completed => 'completed'.tr(),
  TaskStatus.skipped => 'skipped'.tr(),
  TaskStatus.duplicated => 'duplicated'.tr(),
};

/// `yyyy-MM-dd` in the viewer's time zone: the form the filter sheet and the
/// API speak, and the only form that reads the same in every locale.
String _formatDeadline(DateTime deadline) {
  final local = deadline.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _dueLabel(DateTime deadline) {
  final days = _daysUntil(deadline);
  if (days < 0) return 'overdue'.tr();
  if (days == 0) return 'dueToday'.tr();
  if (days == 1) return 'dueTomorrow'.tr();
  return _formatDeadline(deadline);
}

Future<void> _openExternalUrl(String url) async {
  if (url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    showSnackBar('couldNotOpenGitHubIssue'.tr());
  }
}

/// The task list filters, as a sheet. Kept separate from the toolbar so the
/// board keeps its width; the toolbar shows what the sheet produced.
Future<void> _showTaskFilters(
  BuildContext context,
  List<TaskGroup> groups,
  TaskListFilters filters,
  ValueChanged<TaskListFilters> onApply,
) async {
  final next = await showModalBottomSheet<TaskListFilters>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TaskFiltersSheet(filters: filters, groups: groups),
  );
  if (next != null) onApply(next);
}

class _TaskFiltersSheet extends StatefulWidget {
  const _TaskFiltersSheet({required this.filters, required this.groups});

  final TaskListFilters filters;
  final List<TaskGroup> groups;

  @override
  State<_TaskFiltersSheet> createState() => _TaskFiltersSheetState();
}

class _TaskFiltersSheetState extends State<_TaskFiltersSheet> {
  static const _anyGroup = '__any_group__';
  static const _ungrouped = '__ungrouped__';

  late final TextEditingController _tag;
  late final TextEditingController _assigneeAccountId;
  late TaskStatus? _status;
  late int? _priority;
  late String _group;
  late DateTime? _deadlineFrom;
  late DateTime? _deadlineTo;

  @override
  void initState() {
    super.initState();
    final filters = widget.filters;
    _tag = TextEditingController(text: filters.tag ?? '');
    _assigneeAccountId = TextEditingController(
      text: filters.assigneeAccountId ?? '',
    );
    _status = filters.status;
    _priority = filters.priority;
    _group = filters.ungrouped == true
        ? _ungrouped
        : filters.groupId ?? _anyGroup;
    _deadlineFrom = filters.deadlineFrom;
    _deadlineTo = filters.deadlineTo;
  }

  @override
  void dispose() {
    _tag.dispose();
    _assigneeAccountId.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool from}) async {
    final initial = (from ? _deadlineFrom : _deadlineTo) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    setState(() {
      if (from) {
        _deadlineFrom = DateTime(date.year, date.month, date.day);
      } else {
        _deadlineTo = DateTime(date.year, date.month, date.day, 23, 59, 59);
      }
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      TaskListFilters(
        search: widget.filters.search,
        status: _status,
        priority: _priority,
        groupId: _group == _anyGroup || _group == _ungrouped ? null : _group,
        ungrouped: _group == _ungrouped ? true : null,
        assigneeAccountId: _assigneeAccountId.text.trim().isEmpty
            ? null
            : _assigneeAccountId.text.trim(),
        tag: _tag.text.trim().isEmpty ? null : _tag.text.trim(),
        deadlineFrom: _deadlineFrom,
        deadlineTo: _deadlineTo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SheetScaffold(
      titleText: 'filterTasks'.tr(),
      heightFactor: 0.78,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<TaskStatus?>(
              initialValue: _status,
              decoration: InputDecoration(labelText: 'status'.tr()),
              items: [
                DropdownMenuItem(value: null, child: Text('anyStatus'.tr())),
                for (final status in TaskStatus.values)
                  DropdownMenuItem(
                    value: status,
                    child: Text(_statusLabel(status)),
                  ),
              ],
              onChanged: (value) => setState(() => _status = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _priority,
              decoration: InputDecoration(labelText: 'priority'.tr()),
              items: [
                DropdownMenuItem(value: null, child: Text('anyPriority'.tr())),
                for (final priority in const [0, 1, 2])
                  DropdownMenuItem(
                    value: priority,
                    child: Text(_priorityMeta(priority).label),
                  ),
              ],
              onChanged: (value) => setState(() => _priority = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _group,
              decoration: InputDecoration(labelText: 'group'.tr()),
              items: [
                DropdownMenuItem(
                  value: _anyGroup,
                  child: Text('anyGroup'.tr()),
                ),
                DropdownMenuItem(
                  value: _ungrouped,
                  child: Text('ungrouped'.tr()),
                ),
                for (final group in widget.groups)
                  DropdownMenuItem(value: group.id, child: Text(group.name)),
              ],
              onChanged: (value) => setState(() => _group = value ?? _anyGroup),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _assigneeAccountId,
              decoration: InputDecoration(
                labelText: 'assigneeAccountId'.tr(),
                prefixIcon: const Icon(Symbols.person),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tag,
              decoration: InputDecoration(
                labelText: 'tags'.tr(),
                prefixIcon: const Icon(Symbols.label),
              ),
            ),
            const SizedBox(height: 16),
            Text('deadline'.tr(), style: text.titleSmall),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(from: true),
                    icon: const Icon(Symbols.calendar_today, size: 18),
                    label: Text(
                      _deadlineFrom == null
                          ? 'deadlineFrom'.tr()
                          : _formatDeadline(_deadlineFrom!),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(from: false),
                    icon: const Icon(Symbols.calendar_today, size: 18),
                    label: Text(
                      _deadlineTo == null
                          ? 'deadlineTo'.tr()
                          : _formatDeadline(_deadlineTo!),
                    ),
                  ),
                ),
              ],
            ),
            if (_deadlineFrom != null || _deadlineTo != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() {
                    _deadlineFrom = null;
                    _deadlineTo = null;
                  }),
                  child: Text('clearDates'.tr()),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(context, const TaskListFilters()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                    ),
                    child: Text('clearFilters'.tr()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    child: Text('applyFilters'.tr()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
