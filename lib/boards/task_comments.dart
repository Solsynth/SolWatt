import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/ui/alert.dart';
import 'package:solwatt/ui/name_sheet.dart';
import 'package:solwatt/ui/page_scaffold.dart';

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
      await ref
          .read(wattEngineClientProvider)
          .createTaskComment(widget.taskId, content);
      _composer.clear();
      ref.invalidate(taskCommentsProvider(widget.taskId));
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
      await ref
          .read(wattEngineClientProvider)
          .updateTaskComment(comment.id, next.trim());
      ref.invalidate(taskCommentsProvider(widget.taskId));
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
      await ref.read(wattEngineClientProvider).deleteTaskComment(comment.id);
      ref.invalidate(taskCommentsProvider(widget.taskId));
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
        Row(
          children: [
            Text('comments'.tr(), style: text.titleSmall),
            const Spacer(),
            IconButton(
              tooltip: 'refreshComments'.tr(),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Symbols.refresh, size: 18),
              onPressed: () =>
                  ref.invalidate(taskCommentsProvider(widget.taskId)),
            ),
          ],
        ),
        comments.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              wattApiErrorMessage(error),
              style: text.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'noCommentsYet'.tr(),
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final comment in items)
                  _CommentTile(
                    comment: comment,
                    currentAccountId: accountId,
                    onEdit: comment.canEditOrDelete(accountId)
                        ? () => _edit(comment)
                        : null,
                    onDelete: comment.canEditOrDelete(accountId)
                        ? () => _delete(comment)
                        : null,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _composer,
          enabled: !_sending,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: 'addAComment'.tr(),
            alignLabelWithHint: true,
            prefixIcon: inputPrefixIcon(Symbols.chat_bubble, maxLines: 3),
            suffixIcon: IconButton(
              tooltip: 'send'.tr(),
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Symbols.send),
            ),
          ),
          textInputAction: TextInputAction.newline,
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.currentAccountId,
    this.onEdit,
    this.onDelete,
  });

  final TaskComment comment;
  final String? currentAccountId;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final label = comment.authorLabel(currentAccountId: currentAccountId);
    final when = comment.createdAt?.toLocal().toString().split('.').first;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage: comment.externalAuthorAvatarUrl != null
                  ? NetworkImage(comment.externalAuthorAvatarUrl!)
                  : null,
              child: comment.externalAuthorAvatarUrl == null
                  ? Text(
                      label.isEmpty ? '?' : label[0].toUpperCase(),
                      style: const TextStyle(fontSize: 12),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        label,
                        style: text.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (comment.isFromGitHub)
                        StatusChip(
                          label: 'githubComment'.tr(),
                          icon: Symbols.hub,
                          tone: StatusChipTone.neutral,
                        ),
                      if (when != null)
                        Text(
                          when,
                          style: text.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(comment.content, style: text.bodyMedium),
                ],
              ),
            ),
            if (onEdit != null || onDelete != null)
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit?.call();
                  if (value == 'delete') onDelete?.call();
                },
                itemBuilder: (_) => [
                  if (onEdit != null)
                    PopupMenuItem(value: 'edit', child: Text('edit'.tr())),
                  if (onDelete != null)
                    PopupMenuItem(value: 'delete', child: Text('delete'.tr())),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
