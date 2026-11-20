/// One folder's tasks, or the workspace's unfiled tasks.
///
/// A folder holds sub-folders, pages, collections and tasks; the browser shows
/// them, and this page is the folder's task list. Its cards and detail come
/// from `task_surfaces.dart`, shared with every other task list.
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/ideask/ideask_providers.dart';
import 'package:solwatt/ideask/page_doc_page.dart';
import 'package:solwatt/ideask/task_surfaces.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/shared/widgets/alert.dart';
import 'package:solwatt/ui/page_scaffold.dart';
import 'package:solwatt/shell/workspace_tabs.dart';
import 'package:solwatt/workspace/workspace_models.dart';

/// A folder's tasks, or the workspace's unfiled tasks.
@RoutePage()
class TaskListPage extends ConsumerWidget {
  const TaskListPage({
    super.key,
    @QueryParam('folderId') this.folderId,
    @QueryParam('unfiled') this.unfiled = false,
  });

  final String? folderId;
  final bool unfiled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceId = ref.watch(ideaskWorkspaceIdProvider);
    if (folderId == null && !unfiled) {
      return const EmptyState(
        icon: Symbols.folder_off,
        title: 'Nothing selected',
        message: 'Open a folder from the browser to see its tasks.',
      );
    }
    return _TaskListView(
      workspaceId: workspaceId,
      folderId: folderId,
      unfiled: unfiled,
      showHeader: true,
    );
  }
}

/// The task list of one folder, or the workspace's unfiled tasks.
class _TaskListView extends ConsumerStatefulWidget {
  const _TaskListView({
    required this.workspaceId,
    required this.folderId,
    required this.unfiled,
    this.showHeader = false,
  });

  final String? workspaceId;
  final String? folderId;
  final bool unfiled;
  final bool showHeader;

  @override
  ConsumerState<_TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends ConsumerState<_TaskListView> {
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  TaskListFilters _filters = const TaskListFilters();

  TaskListRequest get _request => TaskListRequest(
    workspaceId: widget.folderId == null ? widget.workspaceId : null,
    folderId: widget.folderId,
    unfiled: widget.unfiled,
    filters: _filters,
  );

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
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

  Future<void> _newTask() async {
    final draft = await showTaskEditorSheet(
      context,
      ref,
      folderId: widget.folderId,
    );
    if (draft == null) return;
    try {
      await ref
          .read(ideaskActionsProvider)
          .createTask(
            task: draft.draft,
            folderId: widget.folderId,
            assigneeAccountIds: draft.assigneeAccountIds ?? const [],
          );
      showSnackBar('taskCreated'.tr());
    } catch (error) {
      showSnackBar(wattApiErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tasks = ref.watch(tasksProvider(_request));
    final title = _titleFor(context, ref);

    final body = Column(
      children: [
        _TaskToolbar(
          controller: _search,
          onSearchChanged: _onSearchChanged,
          onSearchCleared: () {
            _search.clear();
            _onSearchChanged('');
          },
          filters: _filters,
          taskCount: tasks.asData?.value.length,
          onFiltersChanged: _setFilters,
        ),
        Expanded(
          child: tasks.when(
            loading: () => const PageLoading(),
            error: (error, _) => PageError(
              message: wattApiErrorMessage(error),
              onRetry: () => ref.invalidate(tasksProvider(_request)),
            ),
            data: (items) {
              if (items.isEmpty) {
                return EmptyState(
                  icon: _filters.isEmpty
                      ? Symbols.task_alt
                      : Symbols.filter_alt_off,
                  title: _filters.isEmpty
                      ? 'noTasksYet'.tr()
                      : 'noMatchingTasks'.tr(),
                  message: _filters.isEmpty
                      ? 'addFirstTask'.tr()
                      : 'noMatchingTasksDetail'.tr(),
                  action: _filters.isEmpty
                      ? FilledButton.icon(
                          onPressed: _newTask,
                          icon: const Icon(Symbols.add_task),
                          label: Text('newTask'.tr()),
                        )
                      : FilledButton.icon(
                          onPressed: () => _setFilters(const TaskListFilters()),
                          icon: const Icon(Symbols.filter_alt_off),
                          label: Text('clearFilters'.tr()),
                        ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) => TaskCard(
                  task: items[index],
                  folderId: widget.folderId,
                  onChanged: () => ref.invalidate(tasksProvider(_request)),
                ),
              );
            },
          ),
        ),
      ],
    );

    return WorkspaceDocumentScope(
      domain: WorkspaceDomain.todo,
      entityId: _documentId,
      title: title,
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          titleSpacing: 0,
          leading: const IdeaskBackButton(),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'newTask'.tr(),
              icon: const Icon(Symbols.add_task),
              onPressed: _newTask,
            ),
          ],
        ),
        body: body,
      ),
    );
  }

  String get _documentId => widget.folderId ?? 'unfiled';

  String _titleFor(BuildContext context, WidgetRef ref) {
    if (widget.unfiled) return 'unfiledTasks'.tr();
    final folderId = widget.folderId;
    if (folderId == null) return 'todo'.tr();
    final contents = ref.watch(ideaskFolderContentsProvider(folderId)).value;
    return contents?.folder.name ?? 'folder'.tr();
  }
}

/// Search, the number of tasks on screen, and the filter sheet's trigger.
class _TaskToolbar extends StatelessWidget {
  const _TaskToolbar({
    required this.controller,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.filters,
    required this.taskCount,
    required this.onFiltersChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final TaskListFilters filters;
  final int? taskCount;
  final ValueChanged<TaskListFilters> onFiltersChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
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
            onPressed: () async {
              final next = await showModalBottomSheet<TaskListFilters>(
                context: context,
                isScrollControlled: true,
                builder: (_) => TaskFiltersSheet(filters: filters),
              );
              if (next != null) onFiltersChanged(next);
            },
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
