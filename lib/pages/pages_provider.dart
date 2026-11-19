import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/pages/page_models.dart';
import 'package:solwatt/workspace/workspace_models.dart';

const _kWorkspacePagesStorageKey = 'workspace_pages_docs_v1';

final selectedPageIdProvider =
    NotifierProvider<SelectedPageIdNotifier, String?>(
      SelectedPageIdNotifier.new,
    );

class SelectedPageIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final pagesProvider = NotifierProvider<PagesNotifier, List<WorkspacePageDoc>>(
  PagesNotifier.new,
);

class PagesNotifier extends Notifier<List<WorkspacePageDoc>> {
  String get _workspaceKey {
    final ws = ref.watch(selectedWorkspaceProvider).value;
    return ws?.slug ?? 'personal';
  }

  @override
  List<WorkspacePageDoc> build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final raw = prefs.getString(_kWorkspacePagesStorageKey);
    final all = _decodeAll(raw);
    final wsKey = _workspaceKey;
    return all.where((p) => p.workspaceKey == wsKey).toList();
  }

  List<WorkspacePageDoc> _decodeAll(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((m) => WorkspacePageDoc.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void _persistWorkspacePages(List<WorkspacePageDoc> updatedScoped) {
    final prefs = ref.read(sharedPreferencesProvider);
    final existingAll = _decodeAll(prefs.getString(_kWorkspacePagesStorageKey));
    final wsKey = _workspaceKey;
    final others = existingAll.where((p) => p.workspaceKey != wsKey);
    final combined = [...others, ...updatedScoped];
    prefs.setString(
      _kWorkspacePagesStorageKey,
      jsonEncode(combined.map((p) => p.toJson()).toList()),
    );
  }

  WorkspacePageDoc createPage({String? title, String? parentId}) {
    final id = 'page-${DateTime.now().microsecondsSinceEpoch}';
    final page = WorkspacePageDoc(
      id: id,
      workspaceKey: _workspaceKey,
      parentId: parentId,
      title: (title == null || title.trim().isEmpty)
          ? 'Untitled Page'
          : title.trim(),
      updatedAt: DateTime.now(),
      blocks: [
        PageBlock(
          id: 'b-${DateTime.now().microsecondsSinceEpoch}',
          type: PageBlockType.paragraph,
          text: '',
        ),
      ],
    );
    final next = [page, ...state];
    state = next;
    _persistWorkspacePages(next);
    ref.read(selectedPageIdProvider.notifier).select(page.id);
    return page;
  }

  void updatePage(WorkspacePageDoc updated) {
    final next = state
        .map(
          (p) => p.id == updated.id
              ? updated.copyWith(updatedAt: DateTime.now())
              : p,
        )
        .toList();
    state = next;
    _persistWorkspacePages(next);
  }

  void addMention(String pageId, WorkspaceEntityRef mention) {
    final page = state.where((p) => p.id == pageId).firstOrNull;
    if (page == null) return;
    if (page.mentions.any((m) => m.key == mention.key)) return;
    updatePage(page.copyWith(mentions: [...page.mentions, mention]));
  }

  void embedEntity(String pageId, WorkspaceEntityRef entity) {
    final page = state.where((p) => p.id == pageId).firstOrNull;
    if (page == null) return;
    final block = PageBlock(
      id: 'embed-${DateTime.now().microsecondsSinceEpoch}',
      type: PageBlockType.entityEmbed,
      text: entity.title,
      embeddedEntity: entity,
    );
    updatePage(page.copyWith(blocks: [...page.blocks, block]));
  }

  void toggleResolveComments(String pageId) {
    final page = state.where((p) => p.id == pageId).firstOrNull;
    if (page == null) return;
    updatePage(page.copyWith(commentsResolved: !page.commentsResolved));
  }

  void deletePage(String pageId) {
    final next = state.where((p) => p.id != pageId).toList();
    state = next;
    _persistWorkspacePages(next);
  }
}
