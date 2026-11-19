part of 'boards_screen.dart';

/// Task editor and assignee search — the sheets the board pushes above
/// itself.
Future<void> _taskForm(
  BuildContext context,
  WidgetRef ref,
  String broadId, {
  WorkTask? task,
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
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => _TaskEditorSheet(broadId: broadId, task: editable),
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
    showSnackBar(wattApiErrorMessage(error));
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
  });

  final String broadId;
  final WorkTask? task;

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
      useRootNavigator: true,
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
          return Center(child: Text(wattApiErrorMessage(snapshot.error!)));
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

