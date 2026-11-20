/// Task surfaces shared by the folder task list, the workspace and Peek: the
/// card, the editor sheet, the filter sheet, and the detail body.
///
/// A task is a whole record on the wire: PATCH replaces name, description,
/// content, attachments, priority, deadline, tags and `complete_reason`, and an
/// omitted `complete_reason` reopens the task. Every write here therefore
/// starts from the current task and changes only what the reader edited.
library;

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/accounts/widgets/account/account_picker.dart';
import 'package:solwatt/core/widgets/content/cloud_file_attachment_list.dart';
import 'package:solwatt/ideask/ideask_providers.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/shared/widgets/alert.dart';
import 'package:solwatt/shared/widgets/layouts/sheet_scaffold.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/ui/cloud_files.dart';
import 'package:solwatt/ui/markdown.dart';
import 'package:solwatt/ui/name_sheet.dart';
import 'package:solwatt/ui/page_scaffold.dart';

/// One task as a ticket: key, title, and one dense meta line. The complete
/// toggle floats over the tile, where it does not pad the title row.
class TaskCard extends ConsumerWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.folderId,
    required this.onChanged,
  });

  final WorkTask task;
  final String? folderId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final attention = _attentionColor(scheme, task);

    return Material(
      color: _raisedSurface(scheme, scheme.brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SolRadius.sm),
        side: BorderSide(
          color: attention?.withValues(alpha: 0.35) ?? scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InkWell(
            onTap: () => showTaskDetailSheet(context, ref, task, folderId),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(46, 12, 36, 12),
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
                      color: task.isCompleted ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                  if (_cardMeta(context, task).isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: _cardMeta(context, task),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            top: 6,
            left: 6,
            child: _TileAction(
              tooltip: task.isCompleted
                  ? 'reopenTask'.tr()
                  : 'markCompleted'.tr(),
              onPressed: () async {
                final target = task.isCompleted
                    ? TaskStatus.open
                    : TaskStatus.completed;
                try {
                  await ref
                      .read(ideaskActionsProvider)
                      .setTaskStatus(task, target);
                  onChanged();
                } catch (error) {
                  showSnackBar(wattApiErrorMessage(error));
                }
              },
              icon: task.isCompleted
                  ? Symbols.check_circle
                  : Symbols.radio_button_unchecked,
              color: task.isCompleted
                  ? scheme.tertiary
                  : scheme.onSurfaceVariant,
            ),
          ),
          Positioned(
            top: 6,
            right: 2,
            child: _TaskMenu(
              task: task,
              folderId: folderId,
              onChanged: onChanged,
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
}

class _TaskMenu extends ConsumerWidget {
  const _TaskMenu({
    required this.task,
    required this.folderId,
    required this.onChanged,
  });

  final WorkTask task;
  final String? folderId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'more'.tr(),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      icon: Icon(
        Symbols.more_vert,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onSelected: (value) async {
        switch (value) {
          case 'open':
            showTaskDetailSheet(context, ref, task, folderId);
          case 'edit':
            final draft = await showTaskEditorSheet(
              context,
              ref,
              folderId: folderId,
              task: task,
            );
            if (draft == null) return;
            try {
              await ref
                  .read(ideaskActionsProvider)
                  .updateTask(
                    task: task,
                    draft: draft.draft,
                    assigneeAccountIds: draft.assigneeAccountIds,
                  );
              onChanged();
              showSnackBar('taskUpdated'.tr());
            } catch (error) {
              showSnackBar(wattApiErrorMessage(error));
            }
          case 'move':
            await _moveTask(context, ref, task);
            onChanged();
          case 'delete':
            final confirmed = await showConfirmAlert(
              'deleteTaskConfirm'.tr(namedArgs: {'name': task.name}),
              'deleteTaskTitle'.tr(),
              icon: Symbols.delete,
              isDanger: true,
              confirmLabel: 'delete'.tr(),
            );
            if (!confirmed) return;
            try {
              await ref.read(ideaskActionsProvider).deleteTask(task.id);
              onChanged();
              showSnackBar('taskDeleted'.tr());
            } catch (error) {
              showSnackBar(wattApiErrorMessage(error));
            }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'open', child: Text('openTask'.tr())),
        PopupMenuItem(value: 'edit', child: Text('editTask'.tr())),
        PopupMenuItem(value: 'move', child: Text('moveToFolder'.tr())),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Text(
            'deleteTask'.tr(),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
  }
}

/// The task detail: a bar-styled sheet on every width. A task is one record,
/// not a reading surface, so it does not claim a tab.
Future<void> showTaskDetailSheet(
  BuildContext context,
  WidgetRef ref,
  WorkTask task,
  String? folderId,
) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => _TaskDetailSheet(task: task, folderId: folderId),
  );
}

class _TaskDetailSheet extends ConsumerStatefulWidget {
  const _TaskDetailSheet({required this.task, required this.folderId});

  final WorkTask task;
  final String? folderId;

  @override
  ConsumerState<_TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends ConsumerState<_TaskDetailSheet> {
  late WorkTask _task = widget.task;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  /// Cards carry the list payload; the detail wants the whole record. Keep the
  /// card's copy when the fetch fails.
  Future<void> _refresh() async {
    try {
      final fresh = await ref.read(wattEngineClientProvider).getTask(_task.id);
      if (!mounted) return;
      setState(() => _task = fresh);
    } catch (_) {}
  }

  Future<void> _toggleComplete() async {
    final target = _task.isCompleted ? TaskStatus.open : TaskStatus.completed;
    final before = _task;
    setState(() => _task = _task.withCompletion(target != TaskStatus.open));
    try {
      final updated = await ref
          .read(ideaskActionsProvider)
          .setTaskStatus(before, target);
      if (!mounted) return;
      setState(() => _task = updated);
      ref.invalidate(tasksProvider);
      showSnackBar(
        target == TaskStatus.open ? 'taskReopened'.tr() : 'taskCompleted'.tr(),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _task = before);
      showSnackBar(wattApiErrorMessage(error));
    }
  }

  Future<void> _edit() async {
    final draft = await showTaskEditorSheet(
      context,
      ref,
      folderId: widget.folderId,
      task: _task,
    );
    if (draft == null) return;
    try {
      final updated = await ref
          .read(ideaskActionsProvider)
          .updateTask(
            task: _task,
            draft: draft.draft,
            assigneeAccountIds: draft.assigneeAccountIds,
          );
      if (!mounted) return;
      setState(() => _task = updated);
      ref.invalidate(tasksProvider);
      showSnackBar('taskUpdated'.tr());
    } catch (error) {
      showSnackBar(wattApiErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SheetScaffold(
      titleText: 'taskDetails'.tr(),
      heightFactor: 0.88,
      actions: [
        IconButton(
          tooltip: 'editTask'.tr(),
          onPressed: _edit,
          icon: const Icon(Symbols.edit),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (_task.displayKey case final key?)
            Align(
              alignment: Alignment.centerLeft,
              child: _KeyStamp(key, style: text.labelLarge),
            ),
          const SizedBox(height: 8),
          Text(
            _task.name,
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              decoration: _task.isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: _toggleComplete,
            icon: Icon(
              _task.isCompleted
                  ? Symbols.radio_button_unchecked
                  : Symbols.check_circle,
              size: 20,
            ),
            label: Text(
              _task.isCompleted ? 'reopenTask'.tr() : 'markCompleted'.tr(),
            ),
          ),
          const SizedBox(height: 20),
          _PropertyRow(
            icon: Symbols.hub,
            label: 'status'.tr(),
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusChip(
                label: _task.status.label.tr(),
                icon: _task.isCompleted ? Symbols.done_all : Symbols.pending,
                tone: _task.isCompleted
                    ? StatusChipTone.secondary
                    : StatusChipTone.neutral,
              ),
            ),
          ),
          _PropertyRow(
            icon: _priorityMeta(_task.priority).icon,
            label: 'priority'.tr(),
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusChip(
                label: _priorityMeta(_task.priority).label.tr(),
                icon: _priorityMeta(_task.priority).icon,
                tone: _priorityMeta(_task.priority).tone,
              ),
            ),
          ),
          if (_task.deadlineAt case final deadline?)
            _PropertyRow(
              icon: Symbols.event,
              label: 'deadline'.tr(),
              child: Text(
                _formatDeadline(deadline),
                style: text.bodyMedium?.copyWith(
                  color: _isOverdue(_task) ? scheme.error : scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (_task.folderId case final folderId?)
            _PropertyRow(
              icon: Symbols.folder,
              label: 'folder'.tr(),
              child: Text(
                ref
                        .watch(ideaskFolderContentsProvider(folderId))
                        .value
                        ?.folder
                        .name ??
                    folderId,
                style: text.bodyMedium,
              ),
            ),
          if (_task.displayDescription case final description?) ...[
            const SizedBox(height: 12),
            Text('description'.tr(), style: text.titleSmall),
            const SizedBox(height: 8),
            MarkdownTextContent(content: description),
          ],
          if (_task.displayContent case final content?) ...[
            const SizedBox(height: 24),
            Text('details'.tr(), style: text.titleSmall),
            const SizedBox(height: 8),
            MarkdownTextContent(content: content),
          ],
          if (_task.tags.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('tags'.tr(), style: text.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final tag in _task.tags)
                  Chip(
                    label: Text(tag),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
          if (_task.attachments.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('attachments'.tr(), style: text.titleSmall),
            const SizedBox(height: 8),
            CloudFileAttachmentList(
              files: _task.attachments,
              workspaceId: ref.watch(selectedWorkspaceProvider).value?.id,
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          // Keyed by task id: the composer is per-task state and must not carry
          // a draft from the previously opened task.
          TaskCommentsSection(key: ValueKey(_task.id), taskId: _task.id),
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

/// The task editor's result: the record to send, plus the assignees to set.
///
/// The wire carries no assignees, so a task opened for editing starts with an
/// empty list. [assigneeAccountIds] is therefore non-null only when the reader
/// actually added or removed someone: sending an empty list would clear the
/// task's assignees.
class TaskEditorResult {
  const TaskEditorResult({
    required this.draft,
    required this.assigneeAccountIds,
  });

  final WorkTaskDraft draft;
  final List<String>? assigneeAccountIds;
}

/// Opens the task editor. Returns null when the reader backs out.
Future<TaskEditorResult?> showTaskEditorSheet(
  BuildContext context,
  WidgetRef ref, {
  String? folderId,
  WorkTask? task,
}) {
  return showModalBottomSheet<TaskEditorResult>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => _TaskEditorSheet(folderId: folderId, task: task),
  );
}

class _TaskEditorSheet extends ConsumerStatefulWidget {
  const _TaskEditorSheet({this.folderId, this.task});

  final String? folderId;
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
  late TaskStatus _status;
  late bool _showDescription;
  late bool _showContent;
  final List<SnCloudFileReference> _attachments = [];
  final List<({String accountId, String label})> _assignees = [];

  /// Whether the reader touched the assignee chips in this sheet.
  bool _assigneesDirty = false;

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
    _status = task?.status ?? TaskStatus.open;
    _showDescription = task?.hasDescription == true;
    _showContent = task?.hasContent == true;
    if (task != null) _attachments.addAll(task.attachments);
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
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    setState(() => _deadline = DateTime(date.year, date.month, date.day, 18));
  }

  Future<void> _addAssignee() async {
    final account = await showModalBottomSheet<SnAccount>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => const AccountPickerSheet(),
    );
    if (account == null || !mounted) return;
    if (_assignees.any((item) => item.accountId == account.id)) return;
    setState(() {
      _assignees.add((
        accountId: account.id,
        label: account.solWattDisplayName,
      ));
      _assigneesDirty = true;
    });
  }

  Future<void> _pickAttachment() async {
    final file = await showCloudFilePicker<SnCloudFile>(
      context: context,
      ref: ref,
      allowMultiple: false,
      workspaceId: ref.read(ideaskWorkspaceIdProvider),
      title: 'attachments'.tr(),
    );
    if (file == null || !mounted) return;
    setState(() => _attachments.add(cloudFileToReference(file)));
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnackBar('nameIsRequired'.tr());
      return;
    }
    final editing = widget.task != null;
    final tags = _tags.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    Navigator.pop(
      context,
      TaskEditorResult(
        draft: WorkTaskDraft(
          name: name,
          description: _description.text.trim(),
          content: _content.text.trim(),
          priority: _priority,
          attachmentIds: _attachments.map((file) => file.id).toList(),
          tags: tags,
          deadlineAt: _deadline,
          completeReason: _status.completeReason,
          parentTaskId: widget.task?.parentTaskId,
          assigneeAccountIds: _assignees
              .map((item) => item.accountId)
              .toList(growable: false),
        ),
        assigneeAccountIds: (!editing || _assigneesDirty)
            ? _assignees.map((item) => item.accountId).toList(growable: false)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final editing = widget.task != null;
    return SheetScaffold(
      titleText: editing ? 'editTask'.tr() : 'newTask'.tr(),
      heightFactor: 0.92,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          TextField(
            controller: _name,
            autofocus: !editing,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'name'.tr(),
              prefixIcon: inputPrefixIcon(Symbols.title),
            ),
          ),
          const SizedBox(height: 16),
          if (!_showDescription)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showDescription = true),
                icon: const Icon(Symbols.notes, size: 18),
                label: Text('addDescription'.tr()),
              ),
            )
          else
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'description'.tr(),
                alignLabelWithHint: true,
                prefixIcon: inputPrefixIcon(Symbols.notes, maxLines: 3),
              ),
            ),
          const SizedBox(height: 16),
          if (!_showContent)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showContent = true),
                icon: const Icon(Symbols.article, size: 18),
                label: Text('addDetails'.tr()),
              ),
            )
          else
            TextField(
              controller: _content,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: 'details'.tr(),
                alignLabelWithHint: true,
                prefixIcon: inputPrefixIcon(Symbols.article, maxLines: 6),
              ),
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<TaskStatus>(
            initialValue: _status,
            decoration: InputDecoration(
              labelText: 'status'.tr(),
              prefixIcon: inputPrefixIcon(Symbols.hub),
            ),
            items: [
              for (final status in TaskStatus.values)
                DropdownMenuItem(value: status, child: Text(status.label.tr())),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _status = value);
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _priority,
            decoration: InputDecoration(
              labelText: 'priority'.tr(),
              prefixIcon: inputPrefixIcon(Symbols.priority_high),
            ),
            items: [
              for (final priority in const [0, 1, 2])
                DropdownMenuItem(
                  value: priority,
                  child: Text(_priorityMeta(priority).label.tr()),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _priority = value);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tags,
            decoration: InputDecoration(
              labelText: 'tags'.tr(),
              hintText: 'design, urgent',
              prefixIcon: inputPrefixIcon(Symbols.label),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDeadline,
                  icon: const Icon(Symbols.event, size: 18),
                  label: Text(
                    _deadline == null
                        ? 'deadline'.tr()
                        : _formatDeadline(_deadline!),
                  ),
                ),
              ),
              if (_deadline != null)
                IconButton(
                  tooltip: 'clear'.tr(),
                  onPressed: () => setState(() => _deadline = null),
                  icon: const Icon(Symbols.close),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_assignees.isNotEmpty) ...[
            Text('assigneesLabel'.tr(), style: text.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final assignee in _assignees)
                  InputChip(
                    label: Text(assignee.label),
                    onDeleted: () =>
                        setState(() => _assignees.remove(assignee)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addAssignee,
              icon: const Icon(Symbols.person_add, size: 18),
              label: Text('addAssignee'.tr()),
            ),
          ),
          if (_attachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final attachment in _attachments)
                  InputChip(
                    avatar: const Icon(Symbols.attach_file, size: 16),
                    label: Text(
                      attachment.name.isEmpty ? 'file'.tr() : attachment.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onDeleted: () =>
                        setState(() => _attachments.remove(attachment)),
                  ),
              ],
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _pickAttachment,
              icon: const Icon(Symbols.attach_file, size: 18),
              label: Text('attachFile'.tr()),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _submit,
            child: Text(editing ? 'saveChanges'.tr() : 'createTask'.tr()),
          ),
        ],
      ),
    );
  }
}

/// The task list filters, as a sheet.
class TaskFiltersSheet extends StatefulWidget {
  const TaskFiltersSheet({super.key, required this.filters});

  final TaskListFilters filters;

  @override
  State<TaskFiltersSheet> createState() => _TaskFiltersSheetState();
}

class _TaskFiltersSheetState extends State<TaskFiltersSheet> {
  late final TextEditingController _tag;
  late final TextEditingController _assigneeAccountId;
  late TaskStatus? _status;
  late int? _priority;
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
                    child: Text(status.label.tr()),
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
                    child: Text(_priorityMeta(priority).label.tr()),
                  ),
              ],
              onChanged: (value) => setState(() => _priority = value),
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

/// Comments on one task. The composer is per-task state.
class TaskCommentsSection extends ConsumerStatefulWidget {
  const TaskCommentsSection({super.key, required this.taskId});

  final String taskId;

  @override
  ConsumerState<TaskCommentsSection> createState() =>
      _TaskCommentsSectionState();
}

class _TaskCommentsSectionState extends ConsumerState<TaskCommentsSection> {
  final _composer = TextEditingController();
  var _sending = false;

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final content = _composer.text.trim();
    if (content.isEmpty) {
      showSnackBar('commentCannotBeEmpty'.tr());
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(ideaskActionsProvider).addComment(widget.taskId, content);
      _composer.clear();
    } catch (error) {
      showSnackBar(wattApiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _edit(TaskComment comment) async {
    final next = await showNameInputSheet(
      context,
      title: 'editComment'.tr(),
      label: 'comment'.tr(),
      confirmLabel: 'save'.tr(),
      initialValue: comment.content,
      icon: Symbols.edit,
    );
    if (next == null || next.trim().isEmpty || next.trim() == comment.content) {
      return;
    }
    try {
      await ref.read(ideaskActionsProvider).editComment(comment, next.trim());
      showSnackBar('commentUpdated'.tr());
    } catch (error) {
      showSnackBar(wattApiErrorMessage(error));
    }
  }

  Future<void> _delete(TaskComment comment) async {
    final confirmed = await showConfirmAlert(
      'deleteCommentConfirm'.tr(),
      'deleteCommentTitle'.tr(),
      icon: Symbols.delete,
      isDanger: true,
      confirmLabel: 'delete'.tr(),
    );
    if (!confirmed) return;
    try {
      await ref.read(ideaskActionsProvider).deleteComment(comment);
      showSnackBar('commentDeleted'.tr());
    } catch (error) {
      showSnackBar(wattApiErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final comments = ref.watch(taskCommentsProvider(widget.taskId));
    final accountId = ref.watch(userInfoProvider).value?.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('comments'.tr(), style: text.titleSmall),
        const SizedBox(height: 8),
        comments.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text(
            wattApiErrorMessage(error),
            style: text.bodySmall?.copyWith(color: scheme.error),
          ),
          data: (items) {
            if (items.isEmpty) {
              return Text(
                'noCommentsYet'.tr(),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              );
            }
            return Column(
              children: [
                for (final comment in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      comment.authorLabel(currentAccountId: accountId),
                    ),
                    subtitle: Text(comment.content),
                    trailing: comment.canEditOrDelete(accountId)
                        ? PopupMenuButton<String>(
                            tooltip: 'more'.tr(),
                            onSelected: (value) {
                              if (value == 'edit') _edit(comment);
                              if (value == 'delete') _delete(comment);
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('edit'.tr()),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('delete'.tr()),
                              ),
                            ],
                          )
                        : null,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _composer,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'writeComment'.tr(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'send'.tr(),
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Symbols.send),
            ),
          ],
        ),
      ],
    );
  }
}

/// Moves a task to another folder of the same workspace, or unfiles it.
Future<void> _moveTask(
  BuildContext context,
  WidgetRef ref,
  WorkTask task,
) async {
  final workspaceId = task.workspaceId ?? ref.read(ideaskWorkspaceIdProvider);
  if (workspaceId == null) return;
  final folders = await ref
      .read(wattEngineClientProvider)
      .listFolders(workspaceId: workspaceId, root: true);
  if (!context.mounted) return;
  final choice = await showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => SheetScaffold(
      titleText: 'moveToFolder'.tr(),
      heightFactor: 0.6,
      child: ListView(
        children: [
          ListTile(
            leading: const Icon(Symbols.folder_off),
            title: Text('unfiledTasks'.tr()),
            onTap: () => Navigator.pop(context, ''),
          ),
          for (final folder in folders)
            ListTile(
              leading: const Icon(Symbols.folder),
              title: Text(folder.name),
              trailing: folder.id == task.folderId
                  ? const Icon(Symbols.check)
                  : null,
              onTap: () => Navigator.pop(context, folder.id),
            ),
        ],
      ),
    ),
  );
  if (choice == null) return;
  try {
    await ref
        .read(ideaskActionsProvider)
        .moveTask(task, choice.isEmpty ? null : choice);
    showSnackBar('taskMoved'.tr());
  } catch (error) {
    showSnackBar(wattApiErrorMessage(error));
  }
}

/// A square, chromeless action for a tile's floating corner buttons.
class _TileAction extends StatelessWidget {
  const _TileAction({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.color,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      icon: Icon(icon, color: color),
    );
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

/// Deadline, priority, tags and files for a card, as icon+text items. A
/// default value shows nothing: an absent item is information, not a gap.
List<Widget> _cardMeta(BuildContext context, WorkTask task) {
  final scheme = Theme.of(context).colorScheme;
  final items = <Widget>[];
  if (task.deadlineAt case final deadline?) {
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
        label: priority.label.tr(),
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
  return items;
}

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
      label: 'high',
      icon: Symbols.keyboard_double_arrow_up,
      tone: StatusChipTone.tertiary,
    ),
    2 => (
      label: 'urgent',
      icon: Symbols.priority_high,
      tone: StatusChipTone.error,
    ),
    _ => (label: 'normal', icon: Symbols.remove, tone: StatusChipTone.neutral),
  };
}

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

/// Surfaces that read as raised above the page background in both
/// brightnesses (`surfaceContainerLow`/`High` are *darker* than the page in
/// light mode, but *lighter* in dark mode, so the token has to flip).
Color _raisedSurface(ColorScheme scheme, Brightness brightness) =>
    brightness == Brightness.dark
    ? scheme.surfaceContainerHigh
    : scheme.surfaceContainerLowest;
