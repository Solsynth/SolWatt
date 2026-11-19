import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/pages/pages_provider.dart';
import 'package:solwatt/workspace/workspace_models.dart';

/// Searches across all four domains (Mail, Todo/Ideask, Pages, Drive)
/// simultaneously using live LightBeam/WattEngine API providers.
List<WorkspaceEntityRef> searchWorkspaceEntities(
  WidgetRef ref,
  String query, {
  WorkspaceDomain? domainFilter,
  int limitPerDomain = 8,
}) {
  final q = query.trim().toLowerCase();
  final results = <WorkspaceEntityRef>[];

  bool matches(String title, [String? subtitle]) {
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) ||
        (subtitle?.toLowerCase().contains(q) ?? false);
  }

  // 1. Pages (user-created)
  if (domainFilter == null || domainFilter == WorkspaceDomain.pages) {
    final pages = ref.watch(pagesProvider);
    var count = 0;
    for (final page in pages) {
      if (count >= limitPerDomain) break;
      final entity = page.toEntityRef();
      if (matches(entity.title, entity.subtitle)) {
        results.add(entity);
        count++;
      }
    }
  }

  // 2. Mail Threads (ElecPostal real API)
  if (domainFilter == null || domainFilter == WorkspaceDomain.mail) {
    final mailboxId = ref.watch(selectedMailboxIdProvider);
    final folder = ref.watch(selectedFolderProvider);
    final threadsAsync = ref.watch(
      threadsProvider((
        filter: (
          mailboxId: mailboxId,
          folder: folder,
          q: q.isEmpty ? null : q,
          status: null,
          isFlagged: null,
          from: null,
          to: null,
          hasAttachments: null,
        ),
        take: 25,
      )),
    );
    final threads = threadsAsync.value?.items ?? const <MailThread>[];
    var count = 0;
    for (final thread in threads) {
      if (count >= limitPerDomain) break;
      final subject = thread.subject.isEmpty
          ? 'noSubject'.tr()
          : thread.subject;
      final subtitle =
          thread.latestMessage.from?.name ??
          thread.latestMessage.from?.address ??
          thread.participants.firstOrNull;
      if (matches(subject, subtitle)) {
        results.add(
          WorkspaceEntityRef(
            id: thread.id,
            domain: WorkspaceDomain.mail,
            title: subject,
            subtitle: subtitle,
            status: thread.unreadCount > 0
                ? '${thread.unreadCount} unread'
                : null,
            metadata: {'threadId': thread.id},
          ),
        );
        count++;
      }
    }
  }

  // 3. Todo / Ideask Tasks & Boards (real Ideask API)
  if (domainFilter == null || domainFilter == WorkspaceDomain.todo) {
    final boards = ref.watch(broadsProvider).value ?? const <Broad>[];
    var count = 0;
    for (final board in boards) {
      if (count >= limitPerDomain) break;
      final tasks =
          ref.watch(tasksProvider(TaskListRequest(broadId: board.id))).value ??
          const <WorkTask>[];
      for (final task in tasks) {
        if (count >= limitPerDomain) break;
        if (matches(task.name, task.description)) {
          results.add(
            WorkspaceEntityRef(
              id: task.id,
              domain: WorkspaceDomain.todo,
              title: task.name,
              subtitle: task.description ?? board.name,
              status: task.completedAt != null ? 'Completed' : 'Open',
              isCompleted: task.completedAt != null,
              metadata: {'broadId': board.id, 'taskId': task.id},
            ),
          );
          count++;
        }
      }
      if (count < limitPerDomain && matches(board.name, board.description)) {
        results.add(
          WorkspaceEntityRef(
            id: board.id,
            domain: WorkspaceDomain.todo,
            title: board.name,
            subtitle: board.description ?? 'Task Board',
            badgeText: 'Board',
            metadata: {'broadId': board.id, 'isBoard': true},
          ),
        );
        count++;
      }
    }
  }

  // 4. Drive Files (real workspace Drive API)
  if (domainFilter == null || domainFilter == WorkspaceDomain.drive) {
    final driveFiles =
        ref.watch(workspaceFilesProvider).value ?? const <DriveFileEntry>[];
    var count = 0;
    for (final file in driveFiles) {
      if (count >= limitPerDomain) break;
      if (matches(file.name, file.mimeType)) {
        results.add(
          WorkspaceEntityRef(
            id: file.id,
            domain: WorkspaceDomain.drive,
            title: file.name,
            subtitle: file.mimeType,
            byteSize: file.size,
            mimeType: file.mimeType,
            isSavedToDrive: true,
          ),
        );
        count++;
      }
    }
  }

  return results;
}
