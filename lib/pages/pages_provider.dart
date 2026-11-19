import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/workspace/workspace_models.dart';

/// Pages are Ideask broads of kind 1 — the same rows, tree and workspace as
/// task boards, only their payload is Markdown (`content`) instead of tasks.
/// There is no separate page store: [broadsProvider] is the list for both.
///
/// The split is a projection, not a fetch: it keeps the list's own async state
/// so a surface that already watches the broads can read `.value` in the same
/// frame instead of waiting on a second round trip.
final pagesProvider = Provider<AsyncValue<List<Broad>>>(
  (ref) => ref
      .watch(broadsProvider)
      .whenData(
        (broads) =>
            broads.where((broad) => broad.isPage).toList(growable: false),
      ),
);

/// The boards on the active workspace: everything that is not a page.
final taskBoardsProvider = Provider<AsyncValue<List<Broad>>>(
  (ref) => ref
      .watch(broadsProvider)
      .whenData(
        (broads) =>
            broads.where((broad) => broad.isBoard).toList(growable: false),
      ),
);

/// The page the boards tab last opened, so its sidebar can mark the row that
/// is on screen. Boards clear it: a board is not a page.
final selectedPageIdProvider =
    NotifierProvider<SelectedPageIdNotifier, String?>(
      SelectedPageIdNotifier.new,
    );

class SelectedPageIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) {
    if (state == id) return;
    state = id;
  }
}

/// One page as the editor reads it, refreshed from the server rather than from
/// the list: the list is a snapshot, and a page's body changes on every save.
final pageProvider = FutureProvider.family<Broad?, String>(
  (ref, pageId) => ref.watch(wattEngineClientProvider).getBroad(pageId),
);

/// What a broad looks like in the shared workspace surfaces (entity pills,
/// peek, favorites, search results).
WorkspaceEntityRef broadToEntityRef(Broad broad) => WorkspaceEntityRef(
  id: broad.id,
  domain: broad.isPage ? WorkspaceDomain.pages : WorkspaceDomain.todo,
  title: broad.name.isEmpty
      ? (broad.isPage ? 'Untitled page' : 'Untitled board')
      : broad.name,
  subtitle: broad.isPage ? 'Page' : 'Task Board',
  badgeText: broad.isPage ? 'Page' : 'Board',
  metadata: {'broadId': broad.id, 'isBoard': broad.isBoard},
);

/// Page writes. Pages and boards share one table, so both go through the same
/// broad endpoints; only the payload differs.
final pageActionsProvider = Provider<PageActions>(PageActions.new);

class PageActions {
  const PageActions(this._ref);

  final Ref _ref;

  /// Creates a page in the active workspace. Pages are boards without tasks,
  /// so the create call is the board create with `kind: 1`.
  Future<Broad> createPage({String? title, String? parentId}) async {
    final workspace = await _ref.read(selectedWorkspaceProvider.future);
    if (workspace == null) {
      throw StateError('Select a workspace before creating a page.');
    }
    final page = await _ref
        .read(wattEngineClientProvider)
        .createBroad(
          name: title?.trim().isNotEmpty == true
              ? title!.trim()
              : 'Untitled page',
          workspaceId: workspace.id,
          kind: Broad.kindPage,
        );
    _ref.invalidate(broadsProvider);
    return page;
  }

  /// Saves a page's title and Markdown body. The list refresh keeps every
  /// surface that names the page — the tab strip, the sidebar, favorites — in
  /// step.
  Future<Broad> savePage(
    Broad page, {
    required String name,
    required String content,
  }) async {
    final saved = await _ref
        .read(wattEngineClientProvider)
        .updateBroad(
          broadId: page.id,
          name: name.trim().isEmpty ? 'Untitled page' : name.trim(),
          content: content,
        );
    _ref.invalidate(broadsProvider);
    _ref.invalidate(pageProvider(page.id));
    return saved;
  }

  /// Deletes a page or board and its whole subtree.
  Future<void> deletePage(Broad page) async {
    await _ref.read(wattEngineClientProvider).deleteBroad(page.id);
    _ref.invalidate(broadsProvider);
  }
}
