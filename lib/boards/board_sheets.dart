part of 'boards_screen.dart';

/// Task editor, lane picker, group manager, and assignee search — the sheets
/// the board pushes above itself.
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
    ref.invalidate(tasksProvider);
    showSnackBar(task == null ? 'taskCreated'.tr() : 'taskUpdated'.tr());
  } catch (error) {
    showSnackBar(error.toString());
  }
}

/// Move a task to another lane without dragging it — the only way to do it on
/// a keyboard, and the pointer-friendly way on a phone.
class _MoveTaskSheet extends StatelessWidget {
  const _MoveTaskSheet({
    required this.task,
    required this.lanes,
    required this.currentGroupId,
  });

  final WorkTask task;
  final List<_TaskColumn> lanes;
  final String? currentGroupId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SheetScaffold(
      titleText: 'moveToGroup'.tr(),
      heightFactor: 0.6,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            task.name,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < lanes.length; index++)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: _laneColor(index),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              title: Text(lanes[index].title),
              subtitle: Text(
                'tasksCount'.plural(lanes[index].tasks.length),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              trailing: lanes[index].groupId == currentGroupId
                  ? Icon(Symbols.check, color: scheme.primary)
                  : null,
              enabled: lanes[index].groupId != currentGroupId,
              onTap: () => Navigator.pop(context, lanes[index]),
            ),
        ],
      ),
    );
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
                    : _formatDeadline(_deadline!),
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
                        backgroundColor: scheme.primaryContainer,
                        foregroundColor: scheme.onPrimaryContainer,
                        child: Text(
                          _initials(assignee.label),
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
                      onPressed: () => openCloudFile(
                        context,
                        file,
                        gallery: _attachments,
                        workspaceId: ref
                            .watch(selectedWorkspaceProvider)
                            .value
                            ?.id,
                      ),
                      onRemove: () => setState(() => _attachments.remove(file)),
                    ),
                ],
              ),
            if (task?.gitHubIssue case final issue?) ...[
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
            if (task != null) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              TaskCommentsSection(key: ValueKey(task.id), taskId: task.id),
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
                      child: Text(_initials(item.label)),
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
                          child: Text(_initials(item.label)),
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
      ref.invalidate(tasksProvider);
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
                        leading: Container(
                          width: 4,
                          height: 20,
                          decoration: BoxDecoration(
                            color: _laneColor(index + 1),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        title: Text(group.name),
                        subtitle: Text('${'position'.tr()} ${group.position}'),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'more'.tr(),
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
