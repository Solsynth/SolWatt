import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/workspace/workspace_models.dart';

// ---------------------------------------------------------------------------
// Navigation visibility
// ---------------------------------------------------------------------------

/// Whether the Ideask (Todo) lens advertises itself in workspace navigation.
///
/// Ideask is being reworked, so the rail, lens switcher, sidebar, search and
/// create actions stop offering a way in. The lens and its routes stay
/// mounted, so a document that already links to a page or a task still opens.
/// Flip this to `true` to bring the entry back.
final ideaskEntryVisibleProvider = Provider<bool>((ref) => false);

/// Domains the Ideask tree serves: folders, collections, tasks and pages.
bool isIdeaskDomain(WorkspaceDomain domain) =>
    domain == WorkspaceDomain.todo || domain == WorkspaceDomain.pages;

/// Whether [lens] belongs in the rail and the lens switcher.
bool isLensVisibleInNavigation(
  WorkspaceLens lens, {
  required bool ideaskVisible,
}) => ideaskVisible || lens != WorkspaceLens.todo;

// ---------------------------------------------------------------------------
// Peek Surface State (Non-Destructive Cross-Domain Inspection)
// ---------------------------------------------------------------------------

@immutable
class PeekState {
  final List<WorkspaceEntityRef> stack;
  final double desktopWidth;

  const PeekState({
    this.stack = const [],
    this.desktopWidth = SolWorkspaceGeometry.peekDefaultWidth,
  });

  bool get isOpen => stack.isNotEmpty;
  WorkspaceEntityRef? get current => stack.isEmpty ? null : stack.last;
  bool get canGoBack => stack.length > 1;

  PeekState copyWith({List<WorkspaceEntityRef>? stack, double? desktopWidth}) {
    return PeekState(
      stack: stack ?? this.stack,
      desktopWidth: desktopWidth ?? this.desktopWidth,
    );
  }
}

final peekProvider = NotifierProvider<PeekController, PeekState>(
  PeekController.new,
);

class PeekController extends Notifier<PeekState> {
  @override
  PeekState build() => const PeekState();

  /// Opens [entity] in the Peek Surface without disturbing Primary Canvas
  /// scroll position or open drafts.
  void open(WorkspaceEntityRef entity) {
    final current = state.current;
    if (current != null && current.key == entity.key) {
      // Update metadata if the same entity was refreshed.
      final next = [...state.stack];
      next[next.length - 1] = entity;
      state = state.copyWith(stack: next);
      return;
    }
    state = state.copyWith(stack: [...state.stack, entity]);
  }

  /// Toggles Peek for [entity]: closes if already showing [entity], otherwise
  /// opens it.
  void toggle(WorkspaceEntityRef entity) {
    if (state.current?.key == entity.key) {
      close();
    } else {
      open(entity);
    }
  }

  void back() {
    if (state.stack.length <= 1) {
      close();
      return;
    }
    state = state.copyWith(
      stack: state.stack.sublist(0, state.stack.length - 1),
    );
  }

  void close() {
    if (!state.isOpen) return;
    state = state.copyWith(stack: const []);
  }

  void setDesktopWidth(double width) {
    final clamped = width.clamp(
      SolWorkspaceGeometry.peekMinWidth,
      SolWorkspaceGeometry.peekMaxWidth,
    );
    if (clamped == state.desktopWidth) return;
    state = state.copyWith(desktopWidth: clamped);
  }

  void updateCurrentEntity(WorkspaceEntityRef updated) {
    if (state.stack.isEmpty) return;
    final next = state.stack
        .map((item) => item.key == updated.key ? updated : item)
        .toList();
    state = state.copyWith(stack: next);
  }
}

// ---------------------------------------------------------------------------
// Desktop Contextual Sidebar Collapse State
// ---------------------------------------------------------------------------

final sidebarCollapsedProvider =
    NotifierProvider<SidebarCollapsedNotifier, bool>(
      SidebarCollapsedNotifier.new,
    );

class SidebarCollapsedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void set(bool collapsed) => state = collapsed;
}

// ---------------------------------------------------------------------------
// Focused Entity (Keyboard Grammar: Space / E / T / Esc)
// ---------------------------------------------------------------------------

final focusedEntityProvider =
    NotifierProvider<FocusedEntityNotifier, WorkspaceEntityRef?>(
      FocusedEntityNotifier.new,
    );

class FocusedEntityNotifier extends Notifier<WorkspaceEntityRef?> {
  @override
  WorkspaceEntityRef? build() => null;

  void set(WorkspaceEntityRef? entity) => state = entity;
  void clear() => state = null;
}

// ---------------------------------------------------------------------------
// Favorites (Shared across Mail, Todo and Pages; Drive lives on the server)
// ---------------------------------------------------------------------------

/// Local favorites. Drive files are favorited on the filesystem service (see
/// [DriveFavoritesNotifier]); these are the workspace-domain items that have no
/// server-side bookmark of their own.
const _kFavoritesKey = 'workspace_favorites_v1';
const _kLegacyPinnedKey = 'workspace_pinned_items_v1';

final favoritesProvider =
    NotifierProvider<FavoritesNotifier, List<WorkspaceEntityRef>>(
      FavoritesNotifier.new,
    );

class FavoritesNotifier extends Notifier<List<WorkspaceEntityRef>> {
  @override
  List<WorkspaceEntityRef> build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    // Older builds stored the same list under the pinned key; read it once so
    // an upgrade does not silently drop the reader's favorites.
    final raw =
        prefs.getString(_kFavoritesKey) ?? prefs.getString(_kLegacyPinnedKey);
    if (raw == null || raw.isEmpty) {
      return _defaultFavorites;
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((m) => WorkspaceEntityRef.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return _defaultFavorites;
    }
  }

  static const List<WorkspaceEntityRef> _defaultFavorites = [];

  void _persist(List<WorkspaceEntityRef> items) {
    ref
        .read(sharedPreferencesProvider)
        .setString(
          _kFavoritesKey,
          jsonEncode(items.map((e) => e.toJson()).toList()),
        );
  }

  bool isFavorite(WorkspaceDomain domain, String id) =>
      state.any((item) => item.domain == domain && item.id == id);

  void toggleFavorite(WorkspaceEntityRef entity) {
    final exists = isFavorite(entity.domain, entity.id);
    final next = exists
        ? state
              .where(
                (item) =>
                    !(item.domain == entity.domain && item.id == entity.id),
              )
              .toList()
        : [entity, ...state];
    state = next;
    _persist(next);
  }

  /// Drops an item without re-adding it. Used when the sidebar unfavorites a
  /// drive file that also survives locally from an older build.
  void remove(WorkspaceDomain domain, String id) {
    final next = state
        .where((item) => !(item.domain == domain && item.id == id))
        .toList();
    if (next.length == state.length) return;
    state = next;
    _persist(next);
  }
}

// ---------------------------------------------------------------------------
// Cross-Domain Backlinks (RelatedItemsStrip)
// ---------------------------------------------------------------------------

const _kBacklinksKey = 'workspace_cross_domain_links_v1';

final backlinksProvider =
    NotifierProvider<BacklinksNotifier, List<CrossDomainLink>>(
      BacklinksNotifier.new,
    );

class BacklinksNotifier extends Notifier<List<CrossDomainLink>> {
  @override
  List<CrossDomainLink> build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(_kBacklinksKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((m) => CrossDomainLink.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void _persist(List<CrossDomainLink> links) {
    ref
        .read(sharedPreferencesProvider)
        .setString(
          _kBacklinksKey,
          jsonEncode(links.map((e) => e.toJson()).toList()),
        );
  }

  void link(WorkspaceEntityRef source, WorkspaceEntityRef target) {
    if (source.key == target.key) return;
    final already = state.any(
      (l) =>
          (l.source.key == source.key && l.target.key == target.key) ||
          (l.source.key == target.key && l.target.key == source.key),
    );
    if (already) return;
    final next = [...state, CrossDomainLink(source: source, target: target)];
    state = next;
    _persist(next);
  }

  void unlink(WorkspaceEntityRef a, WorkspaceEntityRef b) {
    final next = state
        .where(
          (l) =>
              !((l.source.key == a.key && l.target.key == b.key) ||
                  (l.source.key == b.key && l.target.key == a.key)),
        )
        .toList();
    state = next;
    _persist(next);
  }

  List<WorkspaceEntityRef> relatedFor(WorkspaceEntityRef entity) {
    final results = <WorkspaceEntityRef>[];
    final seen = <String>{};
    for (final link in state) {
      if (link.source.key == entity.key && seen.add(link.target.key)) {
        results.add(link.target);
      } else if (link.target.key == entity.key && seen.add(link.source.key)) {
        results.add(link.source);
      }
    }
    return results;
  }
}

// ---------------------------------------------------------------------------
// Saved Attachments Tracking (Mail Attachment -> Drive)
// ---------------------------------------------------------------------------

final savedAttachmentIdsProvider =
    NotifierProvider<SavedAttachmentIdsNotifier, Set<String>>(
      SavedAttachmentIdsNotifier.new,
    );

class SavedAttachmentIdsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void markSaved(String attachmentKey) {
    state = {...state, attachmentKey};
  }
}

// ---------------------------------------------------------------------------
// Recent Items (for Mobile Workspace Switcher & Peek)
// ---------------------------------------------------------------------------

final recentEntitiesProvider =
    NotifierProvider<RecentEntitiesNotifier, List<WorkspaceEntityRef>>(
      RecentEntitiesNotifier.new,
    );

class RecentEntitiesNotifier extends Notifier<List<WorkspaceEntityRef>> {
  @override
  List<WorkspaceEntityRef> build() => const [];

  void record(WorkspaceEntityRef entity) {
    final filtered = state.where((e) => e.key != entity.key).toList();
    state = [entity, ...filtered].take(12).toList();
  }
}
