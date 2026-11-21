import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_state.dart';

/// Ideask is one tree: folders contain folders, pages and collections; tasks
/// live in a folder or unfiled in the workspace. This file is the app-side
/// projection of that tree into the shared workspace surfaces (tabs, peek,
/// favorites, search) plus the write actions every Ideask screen shares.

/// The kind of a node in [ideaskEntityRef]'s metadata.
abstract final class IdeaskKind {
  static const folder = 'folder';
  static const page = 'page';
  static const collection = 'collection';
  static const task = 'task';
}

/// What the Ideask lens is showing: the workspace root, one folder, or one
/// collection.
sealed class IdeaskSelection {
  const IdeaskSelection();

  const factory IdeaskSelection.root() = IdeaskRootSelection;
  const factory IdeaskSelection.folder(String folderId) = IdeaskFolderSelection;
  const factory IdeaskSelection.collection(String collectionId) =
      IdeaskCollectionSelection;
}

class IdeaskRootSelection extends IdeaskSelection {
  const IdeaskRootSelection();

  @override
  bool operator ==(Object other) => other is IdeaskRootSelection;

  @override
  int get hashCode => 0;
}

class IdeaskFolderSelection extends IdeaskSelection {
  const IdeaskFolderSelection(this.folderId);

  final String folderId;

  @override
  bool operator ==(Object other) =>
      other is IdeaskFolderSelection && other.folderId == folderId;

  @override
  int get hashCode => folderId.hashCode;
}

class IdeaskCollectionSelection extends IdeaskSelection {
  const IdeaskCollectionSelection(this.collectionId);

  final String collectionId;

  @override
  bool operator ==(Object other) =>
      other is IdeaskCollectionSelection && other.collectionId == collectionId;

  @override
  int get hashCode => collectionId.hashCode;
}

/// The browser pane's current location. Document routes (a page, a task list)
/// replace the canvas instead of changing it, exactly as a drive file does.
final ideaskSelectionProvider =
    NotifierProvider<IdeaskSelectionNotifier, IdeaskSelection>(
      IdeaskSelectionNotifier.new,
    );

class IdeaskSelectionNotifier extends Notifier<IdeaskSelection> {
  @override
  IdeaskSelection build() => const IdeaskSelection.root();

  void select(IdeaskSelection selection) {
    if (state == selection) return;
    state = selection;
  }

  void openRoot() => select(const IdeaskSelection.root());

  void openFolder(String folderId) => select(IdeaskSelection.folder(folderId));

  void openCollection(String collectionId) =>
      select(IdeaskSelection.collection(collectionId));
}

/// The workspace the Ideask lens browses.
///
/// Ideask has no personal namespace: folders, pages and collections belong to
/// a workspace, and an individual one is still a workspace with an id.
final ideaskWorkspaceIdProvider = Provider<String?>((ref) {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  return workspace?.id;
});

/// The folder contents the browser shows, keyed by the current selection.
final ideaskBrowserProvider = FutureProvider<IdeaskBrowserState>((ref) async {
  final workspaceId = ref.watch(ideaskWorkspaceIdProvider);
  if (workspaceId == null) return const IdeaskBrowserState();
  final selection = ref.watch(ideaskSelectionProvider);
  final client = ref.watch(wattEngineClientProvider);
  switch (selection) {
    case IdeaskRootSelection():
      final folders = await client.listFolders(
        workspaceId: workspaceId,
        root: true,
      );
      final pages = await client.listPages(workspaceId: workspaceId);
      final collections = await client.listCollections(
        workspaceId: workspaceId,
      );
      return IdeaskBrowserState(
        folders: folders,
        pages: pages
            .where(
              (page) =>
                  page.folderId == null &&
                  page.parentPageId == null &&
                  page.collectionId == null,
            )
            .toList(growable: false),
        collections: collections,
      );
    case IdeaskFolderSelection(:final folderId):
      final contents = await client.folderContents(folderId);
      return IdeaskBrowserState(
        folder: contents.folder,
        folders: contents.folders,
        pages: contents.pages,
        collections: contents.collections,
      );
    case IdeaskCollectionSelection(:final collectionId):
      final collection = await client.getCollection(collectionId);
      return IdeaskBrowserState(collection: collection);
  }
});

/// One level of the tree, whatever the current selection points at.
class IdeaskBrowserState {
  const IdeaskBrowserState({
    this.folder,
    this.collection,
    this.folders = const [],
    this.pages = const [],
    this.collections = const [],
  });

  final IdeaskFolder? folder;
  final IdeaskCollection? collection;
  final List<IdeaskFolder> folders;
  final List<IdeaskPage> pages;
  final List<IdeaskCollection> collections;

  bool get isEmpty => folders.isEmpty && pages.isEmpty && collections.isEmpty;
}

/// The breadcrumb of the current selection, root first.
final ideaskBreadcrumbProvider = FutureProvider<List<IdeaskFolder>>((
  ref,
) async {
  final selection = ref.watch(ideaskSelectionProvider);
  if (selection is! IdeaskFolderSelection) return const [];
  final client = ref.watch(wattEngineClientProvider);
  final chain = <IdeaskFolder>[];
  String? cursor = selection.folderId;
  // Folders carry their parent; walking it is one request per level and the
  // tree is shallow by construction (the server caps the depth).
  while (cursor != null && cursor.isNotEmpty) {
    final folder = await client.getFolder(cursor);
    chain.insert(0, folder);
    cursor = folder.parentId;
  }
  return chain;
});

/// What a folder or page looks like in the shared workspace surfaces.
WorkspaceEntityRef ideaskEntityRefForFolder(IdeaskFolder folder) =>
    WorkspaceEntityRef(
      id: folder.id,
      domain: WorkspaceDomain.todo,
      title: folder.name,
      subtitle: folder.description,
      badgeText: 'Folder',
      metadata: {IdeaskKind.folder: true, 'folderId': folder.id},
    );

WorkspaceEntityRef ideaskEntityRefForPage(IdeaskPage page) =>
    WorkspaceEntityRef(
      id: page.id,
      domain: WorkspaceDomain.pages,
      title: page.displayTitle,
      subtitle: page.description,
      badgeText: page.isCollectionRow ? 'Row' : 'Page',
      metadata: {IdeaskKind.page: true, 'pageId': page.id},
    );

WorkspaceEntityRef ideaskEntityRefForCollection(IdeaskCollection collection) =>
    WorkspaceEntityRef(
      id: collection.id,
      domain: WorkspaceDomain.todo,
      title: collection.name,
      subtitle: collection.description,
      badgeText: 'Collection',
      metadata: {IdeaskKind.collection: true, 'collectionId': collection.id},
    );

WorkspaceEntityRef ideaskEntityRefForTask(
  WorkTask task, {
  required String? fallbackTitle,
}) => WorkspaceEntityRef(
  id: task.id,
  domain: WorkspaceDomain.todo,
  title: task.name,
  subtitle: fallbackTitle,
  status: task.status.label,
  isCompleted: task.isCompleted,
  badgeText: 'Task',
  metadata: {IdeaskKind.task: true, 'taskId': task.id},
);

/// The node an [WorkspaceEntityRef] came from, or null for other domains.
IdeaskSelection? ideaskSelectionOf(WorkspaceEntityRef entity) {
  if (entity.metadata[IdeaskKind.folder] == true) {
    return IdeaskSelection.folder(entity.id);
  }
  if (entity.metadata[IdeaskKind.collection] == true) {
    return IdeaskSelection.collection(entity.id);
  }
  return null;
}

/// Ideask writes. Every mutation invalidates the surfaces that read the tree,
/// so the browser, the sidebar and search stay in step.
final ideaskActionsProvider = Provider<IdeaskActions>(IdeaskActions.new);

class IdeaskActions {
  IdeaskActions(this._ref);

  final Ref _ref;

  WattEngineClient get _client => _ref.read(wattEngineClientProvider);

  String _requireWorkspaceId() {
    final workspaceId = _ref.read(ideaskWorkspaceIdProvider);
    if (workspaceId == null) {
      throw StateError('Select a workspace first.');
    }
    return workspaceId;
  }

  void _invalidateTree() {
    _ref.invalidate(ideaskBrowserProvider);
    _ref.invalidate(ideaskTreeProvider);
    _ref.invalidate(ideaskBreadcrumbProvider);
    _ref.invalidate(tasksProvider);
  }

  Future<IdeaskFolder> createFolder({
    required String name,
    String? parentId,
    String? description,
  }) async {
    final workspaceId = _requireWorkspaceId();
    final folder = await _client.createFolder(
      workspaceId: workspaceId,
      name: name,
      parentId: parentId,
      description: description,
    );
    _invalidateTree();
    return folder;
  }

  Future<IdeaskFolder> updateFolder({
    required String folderId,
    String? name,
    String? description,
    String? iconId,
    bool clearIcon = false,
    String? coverId,
    bool clearCover = false,
  }) async {
    final folder = await _client.updateFolder(
      folderId: folderId,
      name: name,
      description: description,
      iconId: iconId,
      clearIcon: clearIcon,
      coverId: coverId,
      clearCover: clearCover,
    );
    _invalidateTree();
    return folder;
  }

  Future<void> deleteFolder(String folderId) async {
    await _client.deleteFolder(folderId);
    final selection = _ref.read(ideaskSelectionProvider);
    if (selection is IdeaskFolderSelection && selection.folderId == folderId) {
      _ref.read(ideaskSelectionProvider.notifier).openRoot();
    }
    _invalidateTree();
  }

  Future<IdeaskFolder> moveFolder({
    required String folderId,
    String? parentId,
  }) async {
    final folder = await _client.moveFolder(
      folderId: folderId,
      parentId: parentId,
      clearParent: parentId == null,
    );
    _invalidateTree();
    return folder;
  }

  Future<IdeaskPage> createPage({
    required String title,
    String? folderId,
    String? parentPageId,
    String? contentMd,
  }) async {
    final workspaceId = _requireWorkspaceId();
    final page = await _client.createPage(
      workspaceId: workspaceId,
      title: title,
      folderId: folderId,
      parentPageId: parentPageId,
      contentMd: contentMd,
    );
    _invalidateTree();
    return page;
  }

  Future<IdeaskPage> updatePage({
    required String pageId,
    String? title,
    String? description,
    String? iconId,
    bool clearIcon = false,
    String? coverId,
    bool clearCover = false,
    List<String>? tags,
  }) async {
    final page = await _client.updatePage(
      pageId: pageId,
      title: title,
      description: description,
      iconId: iconId,
      clearIcon: clearIcon,
      coverId: coverId,
      clearCover: clearCover,
      tags: tags,
    );
    _ref.invalidate(ideaskPageProvider(pageId));
    _invalidateTree();
    return page;
  }

  Future<IdeaskPageBody> savePageBody({
    required String pageId,
    required String contentMd,
  }) async {
    final body = await _client.savePageBody(pageId, contentMd);
    _ref.invalidate(ideaskPageBodyProvider(pageId));
    _ref.invalidate(ideaskPageProvider(pageId));
    return body;
  }

  /// Re-reads the stored body, e.g. after a title write rewrote its
  /// frontmatter block.
  Future<IdeaskPageBody> getPageBody(String pageId) =>
      _client.getPageBody(pageId);

  Future<void> deletePage(String pageId) async {
    await _client.deletePage(pageId);
    _ref.invalidate(ideaskPageProvider(pageId));
    _invalidateTree();
  }

  Future<IdeaskPage> movePage({
    required String pageId,
    String? folderId,
  }) async {
    final page = await _client.movePage(
      pageId: pageId,
      folderId: folderId,
      clearFolder: folderId == null,
    );
    _invalidateTree();
    return page;
  }

  Future<IdeaskCollection> createCollection({
    required String name,
    String? folderId,
    String? description,
  }) async {
    final workspaceId = _requireWorkspaceId();
    final collection = await _client.createCollection(
      workspaceId: workspaceId,
      name: name,
      folderId: folderId,
      description: description,
    );
    _invalidateTree();
    return collection;
  }

  Future<IdeaskCollection> addCollectionProperty({
    required String collectionId,
    required String name,
    required String type,
    List<IdeaskPropertyOption> options = const [],
    String? relationCollectionId,
  }) async {
    final collection = await _client.addCollectionProperty(
      collectionId: collectionId,
      name: name,
      type: type,
      options: options,
      relationCollectionId: relationCollectionId,
    );
    _invalidateTree();
    return collection;
  }

  Future<IdeaskCollection> updateCollection({
    required String collectionId,
    String? name,
    String? description,
  }) async {
    final collection = await _client.updateCollection(
      collectionId: collectionId,
      name: name,
      description: description,
    );
    _invalidateTree();
    return collection;
  }

  Future<void> deleteCollection(String collectionId) async {
    await _client.deleteCollection(collectionId);
    final selection = _ref.read(ideaskSelectionProvider);
    if (selection is IdeaskCollectionSelection &&
        selection.collectionId == collectionId) {
      _ref.read(ideaskSelectionProvider.notifier).openRoot();
    }
    _invalidateTree();
  }

  Future<IdeaskView> createView({
    required String collectionId,
    required String name,
    required int type,
  }) async {
    final view = await _client.createCollectionView(
      collectionId: collectionId,
      name: name,
      type: type,
    );
    _invalidateTree();
    return view;
  }

  Future<void> deleteView({
    required String collectionId,
    required String viewId,
  }) async {
    await _client.deleteCollectionView(
      collectionId: collectionId,
      viewId: viewId,
    );
    _invalidateTree();
  }

  Future<IdeaskPage> createRow({
    required String collectionId,
    required String title,
    Map<String, dynamic>? properties,
  }) async {
    final page = await _client.createCollectionRow(
      collectionId: collectionId,
      title: title,
      properties: properties,
    );
    _invalidateTree();
    return page;
  }

  Future<WorkTask> createTask({
    required WorkTaskDraft task,
    String? folderId,
    List<String> assigneeAccountIds = const [],
  }) async {
    final workspaceId = _requireWorkspaceId();
    final created = await _client.createTask(
      workspaceId: workspaceId,
      task: task,
      folderId: folderId,
    );
    if (assigneeAccountIds.isNotEmpty) {
      await _client.setTaskAssignees(created.id, assigneeAccountIds);
    }
    _invalidateTree();
    return created;
  }

  Future<WorkTask> updateTask({
    required WorkTask task,
    WorkTaskDraft? draft,
    TaskStatus? status,
    List<String>? assigneeAccountIds,
  }) async {
    final body = draft ?? task.toDraft(status: status);
    final updated = await _client.updateTask(task.id, body);
    if (assigneeAccountIds != null) {
      await _client.setTaskAssignees(task.id, assigneeAccountIds);
    }
    _invalidateTree();
    return updated;
  }

  Future<WorkTask> setTaskStatus(WorkTask task, TaskStatus status) =>
      updateTask(
        task: task,
        draft: task.toDraft(status: status),
      );

  Future<void> deleteTask(String taskId) async {
    await _client.deleteTask(taskId);
    _invalidateTree();
  }

  Future<WorkTask> moveTask(WorkTask task, String? folderId) async {
    final moved = await _client.moveTask(
      taskId: task.id,
      folderId: folderId,
      clearFolder: folderId == null,
    );
    _invalidateTree();
    return moved;
  }

  /// Bookmarks an Ideask node in the shared Favorites list.
  void toggleFavorite(WorkspaceEntityRef entity) =>
      _ref.read(favoritesProvider.notifier).toggleFavorite(entity);

  Future<List<TaskComment>> listComments(String taskId) =>
      _client.listTaskComments(taskId);

  Future<TaskComment> addComment(String taskId, String content) async {
    final comment = await _client.createTaskComment(taskId, content);
    _ref.invalidate(taskCommentsProvider(taskId));
    return comment;
  }

  Future<TaskComment> editComment(TaskComment comment, String content) async {
    final updated = await _client.updateTaskComment(comment.id, content);
    _ref.invalidate(taskCommentsProvider(comment.taskId));
    return updated;
  }

  Future<void> deleteComment(TaskComment comment) async {
    await _client.deleteTaskComment(comment.id);
    _ref.invalidate(taskCommentsProvider(comment.taskId));
  }
}
