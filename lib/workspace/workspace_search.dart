import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/ideask/ideask_providers.dart';
import 'package:solwatt/workspace/workspace_models.dart';

/// Searches across all four domains (Mail, Todo/Ideask, Pages, Drive)
/// simultaneously using live LightBeam/WattEngine API providers.
///
/// Ideask is one tree: folders, collections and tasks answer under Todo and
/// pages under Pages, so a reader who does not know which node holds what
/// still finds it.
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

  final tree = ref.watch(ideaskBrowserProvider).value;

  // 1. Pages of the workspace root, plus the one folder currently open.
  if (domainFilter == null || domainFilter == WorkspaceDomain.pages) {
    final pages = tree?.pages ?? const <IdeaskPage>[];
    var count = 0;
    for (final page in pages) {
      if (count >= limitPerDomain) break;
      final entity = ideaskEntityRefForPage(page);
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

  // 3. Todo / Ideask: folders and collections of the level on screen, plus
  //    the tasks of the folder the reader is in (or the workspace's unfiled
  //    tasks when the browser is at the root).
  if (domainFilter == null || domainFilter == WorkspaceDomain.todo) {
    var count = 0;
    for (final folder in [...?tree?.folders]) {
      if (count >= limitPerDomain) break;
      final entity = ideaskEntityRefForFolder(folder);
      if (matches(entity.title, entity.subtitle)) {
        results.add(entity);
        count++;
      }
    }
    for (final collection in [...?tree?.collections]) {
      if (count >= limitPerDomain) break;
      final entity = ideaskEntityRefForCollection(collection);
      if (matches(entity.title, entity.subtitle)) {
        results.add(entity);
        count++;
      }
    }
    final selection = ref.watch(ideaskSelectionProvider);
    final folderId = selection is IdeaskFolderSelection
        ? selection.folderId
        : null;
    final workspaceId = ref.watch(ideaskWorkspaceIdProvider);
    final tasks = ref
        .watch(
          tasksProvider(
            TaskListRequest(
              workspaceId: folderId == null ? workspaceId : null,
              folderId: folderId,
              unfiled: folderId == null,
            ),
          ),
        )
        .value;
    for (final task in tasks ?? const <WorkTask>[]) {
      if (count >= limitPerDomain) break;
      if (matches(task.name, task.description)) {
        results.add(ideaskEntityRefForTask(task, fallbackTitle: null));
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
