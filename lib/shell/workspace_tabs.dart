import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:solwatt/route.dart';
import 'package:solwatt/shell/adaptive_workspace_shell.dart';
import 'package:solwatt/workspace/workspace_models.dart';

/// One open document in the workspace strip: a mail conversation, a board, a
/// drive file. The lenses belong to the rail; the strip only holds what the
/// reader opened in a tab of its own.
@immutable
class WorkspaceTab {
  /// Stable identity: `domain:id`, or [lensTabKey] for a lens tab.
  final String key;

  /// Lens the document is read inside; closing it returns that lens to root.
  final WorkspaceLens lens;

  /// Null on the lens tab itself.
  final WorkspaceDomain? domain;
  final String? entityId;
  final String title;

  /// A tab that stands for the lens root rather than a document: it cannot be
  /// closed, and Back from its documents lands here.
  final bool isRoot;

  const WorkspaceTab({
    required this.key,
    required this.lens,
    required this.title,
    this.domain,
    this.entityId,
    this.isRoot = false,
  });

  static String keyFor(WorkspaceDomain domain, String entityId) =>
      '${domain.name}:$entityId';

  static String lensTabKey(WorkspaceLens lens) => 'lens:${lens.name}';

  IconData get icon => domain?.icon ?? lens.icon;

  @override
  bool operator ==(Object other) => other is WorkspaceTab && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// The strip's state: open documents in opening order and the one on screen.
@immutable
class WorkspaceTabState {
  final List<WorkspaceTab> tabs;

  /// [WorkspaceTab.key] of the tab on screen, or null when the lens root is
  /// showing without a lens tab (e.g. a peek surface owns the pane).
  final String? activeKey;

  const WorkspaceTabState({required this.tabs, this.activeKey});

  bool isActive(WorkspaceTab tab) => tab.key == activeKey;
}

/// The route a document opens into its lens' nested stack.
PageRouteInfo? routeForDocument(WorkspaceDomain domain, String entityId) =>
    switch (domain) {
      WorkspaceDomain.mail => MailDetailRoute(emailId: entityId),
      WorkspaceDomain.todo => TaskBoardRoute(broadId: entityId),
      // The drive and the pages lens open documents in their own panes rather
      // than by routing: their readers are panes in the canvas, not pages.
      WorkspaceDomain.drive || WorkspaceDomain.pages => null,
    };

WorkspaceLens lensOfDomain(WorkspaceDomain domain) => switch (domain) {
  WorkspaceDomain.mail => WorkspaceLens.mail,
  WorkspaceDomain.todo => WorkspaceLens.todo,
  WorkspaceDomain.pages => WorkspaceLens.pages,
  WorkspaceDomain.drive => WorkspaceLens.drive,
};

/// Lens index a domain's documents are read inside.
int lensIndexOfDomain(WorkspaceDomain domain) =>
    kShellLenses.indexOf(lensOfDomain(domain));

/// A drive file the strip asked to close. The drive owns the reading pane, so
/// the strip hands the id over and the drive closes what it actually shows.
final drivePendingCloseProvider = NotifierProvider<DrivePendingClose, String?>(
  DrivePendingClose.new,
);

class DrivePendingClose extends Notifier<String?> {
  @override
  String? build() => null;

  void request(String fileId) => state = fileId;

  void clear() => state = null;
}

/// A drive file the strip asked to bring forward.
final drivePendingFocusProvider = NotifierProvider<DrivePendingFocus, String?>(
  DrivePendingFocus.new,
);

class DrivePendingFocus extends Notifier<String?> {
  @override
  String? build() => null;

  void request(String fileId) => state = fileId;

  void clear() => state = null;
}

/// A mail conversation the strip asked to bring forward, and whether it should
/// take the whole canvas (a double-clicked row opens its own tab) or stay in
/// the reading pane beside the list.
typedef MailFocusRequest = ({String threadId, bool fullScreen});

final mailPendingFocusProvider =
    NotifierProvider<MailPendingFocus, MailFocusRequest?>(MailPendingFocus.new);

class MailPendingFocus extends Notifier<MailFocusRequest?> {
  @override
  MailFocusRequest? build() => null;

  void request(String threadId, {required bool fullScreen}) =>
      state = (threadId: threadId, fullScreen: fullScreen);

  void clear() => state = null;
}

class WorkspaceTabsController extends Notifier<WorkspaceTabState> {
  /// How many live surfaces show each document. A route swap briefly mounts
  /// the new surface before the old one disposes, so a tab is dropped only
  /// when the last surface for it goes away.
  final Map<String, int> _mounted = {};

  /// Registers the document on screen, adding or refreshing its tab.
  ///
  /// [fullScreen] false is a reading pane, not a tab: the lens' own tab stays
  /// on the strip and becomes active, so reading a mail in the right column
  /// never grows a second tab beside the inbox.
  void register({
    required WorkspaceDomain domain,
    required String entityId,
    required String title,
    bool fullScreen = true,
  }) {
    if (!ref.mounted) return;
    final key = WorkspaceTab.keyFor(domain, entityId);
    _mounted[key] = (_mounted[key] ?? 0) + 1;
    final lens = lensOfDomain(domain);

    if (!fullScreen) {
      _showLensRoot(lens, domain: domain, entityId: entityId, title: title);
      return;
    }

    final tabs = [...state.tabs];
    final existing = tabs.indexWhere((tab) => tab.key == key);
    final tab = WorkspaceTab(
      key: key,
      lens: lens,
      domain: domain,
      entityId: entityId,
      title: title,
    );
    if (existing == -1) {
      tabs.add(tab);
    } else {
      tabs[existing] = tab;
    }
    state = WorkspaceTabState(tabs: tabs, activeKey: key);
  }

  /// Makes the lens' tab the active one, creating that lens tab when the strip
  /// does not carry it yet. Its title follows the open document so the reader
  /// still sees what they are reading.
  void _showLensRoot(
    WorkspaceLens lens, {
    required WorkspaceDomain domain,
    required String entityId,
    required String title,
  }) {
    final lensKey = WorkspaceTab.lensTabKey(lens);
    final tabs = [...state.tabs];
    // Documents of other lenses keep their tabs; this lens' documents fold
    // into the lens tab while the reader is in its root pane.
    tabs.removeWhere((tab) => tab.lens == lens && !tab.isRoot);
    final existing = tabs.indexWhere((tab) => tab.key == lensKey);
    final lensTab = WorkspaceTab(
      key: lensKey,
      lens: lens,
      title: title,
      domain: domain,
      entityId: entityId,
      isRoot: true,
    );
    if (existing == -1) {
      tabs.add(lensTab);
    } else {
      tabs[existing] = lensTab;
    }
    state = WorkspaceTabState(tabs: tabs, activeKey: lensKey);
  }

  /// Declares that [lens] is sitting on its root pane (the drive's folder
  /// browser, the inbox's list). The lens tab joins the bar without stealing
  /// the active tab from a document that is still open beside it.
  void showingLensRoot(WorkspaceLens lens, {required String title}) {
    if (!ref.mounted) return;
    final lensKey = WorkspaceTab.lensTabKey(lens);
    final tabs = [...state.tabs];
    final existing = tabs.indexWhere((tab) => tab.key == lensKey);
    final lensTab = WorkspaceTab(
      key: lensKey,
      lens: lens,
      title: title,
      isRoot: true,
    );
    if (existing == -1) {
      tabs.insert(0, lensTab);
    } else {
      tabs[existing] = lensTab;
    }
    final active = state.activeKey;
    final activeIsDocument = state.tabs
        .where((tab) => tab.key == active)
        .any((tab) => !tab.isRoot);
    state = WorkspaceTabState(
      tabs: tabs,
      activeKey: activeIsDocument ? active : lensKey,
    );
  }

  /// Makes sure [lens] has a tab on the bar. Switching lenses never leaves the
  /// bar empty: the lens the reader is on is always one of its tabs.
  void ensureLensTab(WorkspaceLens lens) {
    if (!ref.mounted) return;
    final key = WorkspaceTab.lensTabKey(lens);
    if (state.tabs.any((tab) => tab.key == key)) return;
    final tabs = [
      ...state.tabs,
      WorkspaceTab(key: key, lens: lens, title: lens.label, isRoot: true),
    ];
    state = WorkspaceTabState(tabs: tabs, activeKey: state.activeKey ?? key);
  }

  /// Drops one surface for [key]; a document tab goes away with its last
  /// surface, a lens tab never does.
  void release(String key) {
    if (!ref.mounted) return;
    final count = (_mounted[key] ?? 1) - 1;
    if (count > 0) {
      _mounted[key] = count;
      return;
    }
    _mounted.remove(key);
    final closing = state.tabs.where((tab) => tab.key == key).firstOrNull;
    // A lens tab is the lens' home: it outlives the pane that showed it.
    if (closing == null || closing.isRoot) return;
    final tabs = state.tabs.where((tab) => tab.key != key).toList();
    state = WorkspaceTabState(
      tabs: tabs,
      activeKey: state.activeKey == key ? null : state.activeKey,
    );
  }

  /// Marks [key] as the tab on screen without touching the tab list.
  void activate(String key) {
    if (!ref.mounted || state.activeKey == key) return;
    state = WorkspaceTabState(tabs: state.tabs, activeKey: key);
  }

  /// The reader moved to a lens root (rail click, Back out of a document).
  void clearActive() {
    if (!ref.mounted || state.activeKey == null) return;
    state = WorkspaceTabState(tabs: state.tabs);
  }

  /// Removes a document tab without touching any pane: the pane already closed
  /// itself and is reporting that.
  void close(String key) {
    if (!ref.mounted) return;
    final tab = state.tabs.where((t) => t.key == key).firstOrNull;
    if (tab == null || tab.isRoot) return;
    _mounted.remove(key);
    state = WorkspaceTabState(
      tabs: state.tabs.where((t) => t.key != key).toList(),
      activeKey: state.activeKey == key ? null : state.activeKey,
    );
  }

  @override
  WorkspaceTabState build() => const WorkspaceTabState(tabs: []);
}

final workspaceTabsProvider =
    NotifierProvider<WorkspaceTabsController, WorkspaceTabState>(
      WorkspaceTabsController.new,
    );

/// Declares the document a detail surface shows, so the strip names its tab
/// after what the reader opened whatever road they took in — list row,
/// omnibox, peek, deep link.
///
/// Registration is deferred one frame: a page may not mutate providers while
/// the tree that watches them is building.
class WorkspaceDocumentScope extends ConsumerStatefulWidget {
  final WorkspaceDomain domain;
  final String entityId;
  final String title;

  /// Whether the document owns the canvas (its own tab) or only the reading
  /// pane beside the lens' list. A reading pane keeps the lens tab active.
  final bool fullScreen;

  final Widget child;

  const WorkspaceDocumentScope({
    super.key,
    required this.domain,
    required this.entityId,
    required this.title,
    this.fullScreen = true,
    required this.child,
  });

  @override
  ConsumerState<WorkspaceDocumentScope> createState() =>
      _WorkspaceDocumentScopeState();
}

class _WorkspaceDocumentScopeState
    extends ConsumerState<WorkspaceDocumentScope> {
  /// The controller this scope registered with. Kept as a field because a
  /// widget's `ref` is unsafe to touch once it is unmounting, while the
  /// controller outlives the widget.
  WorkspaceTabsController? _tabs;

  String get _key => WorkspaceTab.keyFor(widget.domain, widget.entityId);

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(WorkspaceDocumentScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entityId != widget.entityId ||
        oldWidget.title != widget.title ||
        oldWidget.fullScreen != widget.fullScreen) {
      _register();
    }
  }

  void _register() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tabs = ref.read(workspaceTabsProvider.notifier);
      _tabs = tabs;
      tabs.register(
        domain: widget.domain,
        entityId: widget.entityId,
        title: widget.title,
        fullScreen: widget.fullScreen,
      );
    });
  }

  @override
  void dispose() {
    final key = _key;
    final tabs = _tabs;
    if (tabs != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => tabs.release(key));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
