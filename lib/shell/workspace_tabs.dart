import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:solwatt/route.dart';
import 'package:solwatt/workspace/workspace_models.dart';

/// One open document in the workspace strip: a mail conversation, a board, a
/// drive file. The lenses belong to the rail; the strip only holds what the
/// reader opened in a tab of its own.
@immutable
class WorkspaceTab {
  /// Stable identity: `domain:id`.
  final String key;

  /// Lens the document is read inside; closing it returns that lens to its
  /// root pane.
  final WorkspaceLens lens;

  final WorkspaceDomain domain;
  final String? entityId;

  /// What a mail tab opens: the message the route reads. A conversation is one
  /// tab keyed by its thread, so the tab carries the message it shows.
  final String? messageId;
  final String title;

  const WorkspaceTab({
    required this.key,
    required this.lens,
    required this.domain,
    required this.title,
    this.entityId,
    this.messageId,
  });

  static String keyFor(WorkspaceDomain domain, String entityId) =>
      '${domain.name}:$entityId';

  IconData get icon => domain.icon;

  @override
  bool operator ==(Object other) => other is WorkspaceTab && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// The strip's state: open documents in opening order and the one on screen.
///
/// The strip holds documents only. Which lens is on screen is the rail's own
/// state, so switching lenses never spends a tab: a lens with nothing open in
/// it has an empty strip and no [activeKey].
@immutable
class WorkspaceTabState {
  final List<WorkspaceTab> tabs;

  /// [WorkspaceTab.key] of the tab on screen, or null when the active lens is
  /// showing its own root pane (the inbox list, the folder browser).
  final String? activeKey;

  const WorkspaceTabState({required this.tabs, this.activeKey});

  bool isActive(WorkspaceTab tab) => tab.key == activeKey;

  /// The tab on screen. Null when nothing claims the active key.
  WorkspaceTab? get activeTab => tabs.where(isActive).firstOrNull;

  /// Whether a document owns the canvas. The shell strips its own chrome for
  /// it: a document is a full screen, not a lens pane.
  bool get showsDocument => activeTab != null;

  /// Whether the canvas is the document of [domain] rather than that lens'
  /// root pane — a mail conversation read in a tab of its own, not the inbox.
  bool showsDocumentOf(WorkspaceDomain domain) => activeTab?.domain == domain;
}

/// The route a tab opens into its lens' nested stack. Null for tabs whose
/// content is a pane of the canvas (the drive's reader) rather than a page in
/// the lens' stack.
///
/// Pages open in the Todo tab's stack because folders and pages share the
/// service: one stack holds the browser and the pages opened above it, and
/// Back walks them in the order the reader opened them.
PageRouteInfo? routeForTab(WorkspaceTab tab) => switch (tab.domain) {
  WorkspaceDomain.mail =>
    tab.messageId == null ? null : MailDetailRoute(emailId: tab.messageId!),
  // A task is a record inside a list, not a document: only pages open in the
  // lens' stack. Todo entities are folders and collections, which the browser
  // shows in place instead of pushing a route.
  WorkspaceDomain.todo => null,
  WorkspaceDomain.pages => DocRoute(pageId: tab.entityId!),
  WorkspaceDomain.drive => null,
};

/// Ideask serves folders, pages and collections from one tree, so all three
/// open in the Todo lens.
WorkspaceLens lensOfDomain(WorkspaceDomain domain) => switch (domain) {
  WorkspaceDomain.mail => WorkspaceLens.mail,
  WorkspaceDomain.todo || WorkspaceDomain.pages => WorkspaceLens.todo,
  WorkspaceDomain.drive => WorkspaceLens.drive,
};

/// The stack a lens' documents live in.
///
/// The lens routes are children of the shell's [AutoTabsRouter], not of the
/// app's root stack, so [appRouter] knows nothing about them: the lookup has to
/// start at the tabs controller of the shell route. Asking the root router for
/// `MailRoute` returns null, which silently turns every navigate into a no-op.
StackRouter? lensStackRouter(WorkspaceLens lens) {
  final tabs = appRouter.innerRouterOf<TabsRouter>(AppShellRoute.name);
  return (tabs ?? appRouter).innerRouterOf<StackRouter>(lens.routeName);
}

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
  /// Whether [entity] currently owns a tab of its own.
  bool isDocument(WorkspaceDomain domain, String entityId) =>
      state.tabs.any((tab) => tab.key == WorkspaceTab.keyFor(domain, entityId));

  /// Registers the document on screen, adding or refreshing its tab.
  ///
  /// [fullScreen] false is a reading pane, not a tab: the lens shows the
  /// document in its own column and the strip stays empty, so reading a mail
  /// beside the inbox never grows a tab. The surface that promotes the
  /// document to a full screen calls [claim] or registers it again.
  ///
  /// [messageId] is what a mail tab opens. A conversation is keyed by its
  /// thread — one tab per conversation, however many messages it holds — while
  /// the route reads one message, so the tab remembers which.
  void register({
    required WorkspaceDomain domain,
    required String entityId,
    required String title,
    String? messageId,
    bool fullScreen = true,
  }) {
    if (!ref.mounted) return;
    if (!fullScreen) {
      final key = WorkspaceTab.keyFor(domain, entityId);
      // Demoting a tab that already exists folds the reading pane back beside
      // the list: the document is no longer a full screen, so it stops being
      // a tab. A surface that never had one leaves the strip untouched.
      if (isDocument(domain, entityId)) close(key);
      return;
    }
    _put(
      WorkspaceTab(
        key: WorkspaceTab.keyFor(domain, entityId),
        lens: lensOfDomain(domain),
        domain: domain,
        entityId: entityId,
        messageId: messageId,
        title: title,
      ),
    );
  }

  /// Puts a document's tab on the bar before its surface has mounted, so the
  /// surface's own [register] sees a document and does not fold into the lens
  /// root. It does not count a surface: the pane that mounts next does, and
  /// the tab goes away when that pane does.
  void claim({
    required WorkspaceDomain domain,
    required String entityId,
    required String title,
    String? messageId,
  }) {
    if (!ref.mounted) return;
    _put(
      WorkspaceTab(
        key: WorkspaceTab.keyFor(domain, entityId),
        lens: lensOfDomain(domain),
        domain: domain,
        entityId: entityId,
        messageId: messageId,
        title: title,
      ),
    );
  }

  /// Adds [tab] at the end of the strip, or refreshes the tab it replaces in
  /// place, and brings it on screen.
  void _put(WorkspaceTab tab) {
    final tabs = [...state.tabs];
    final existing = tabs.indexWhere((open) => open.key == tab.key);
    if (existing == -1) {
      tabs.add(tab);
    } else {
      tabs[existing] = tab;
    }
    state = WorkspaceTabState(tabs: tabs, activeKey: tab.key);
  }

  /// Shows [lens]' root pane: nothing from the strip claims the canvas.
  ///
  /// The rail addresses a place, not a document, so arriving at a lens never
  /// spends a tab and never drops one: documents opened elsewhere keep the
  /// tabs they own and stay closable.
  void deactivate() {
    if (!ref.mounted || state.activeKey == null) return;
    state = WorkspaceTabState(tabs: state.tabs);
  }

  /// Marks [key] as the tab on screen without touching the tab list.
  void activate(String key) {
    if (!ref.mounted || state.activeKey == key) return;
    state = WorkspaceTabState(tabs: state.tabs, activeKey: key);
  }

  /// Takes the canvas back from [key] without closing its tab. A surface that
  /// leaves the canvas — a document popped off its lens stack — stops claiming
  /// it, while the tab the reader opened stays on the strip.
  void release(String key) {
    if (!ref.mounted || state.activeKey != key) return;
    state = WorkspaceTabState(tabs: state.tabs);
  }

  /// Removes a document tab. Closing the tab on screen leaves its lens on the
  /// root pane: nothing else claims the canvas.
  void close(String key) {
    if (!ref.mounted) return;
    if (!state.tabs.any((tab) => tab.key == key)) return;
    state = WorkspaceTabState(
      tabs: state.tabs.where((tab) => tab.key != key).toList(),
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
/// the tree that watches them is building. A tab outlives the surface that
/// opened it — it closes when the reader closes it, like a browser tab — so a
/// route swap behind it never silently drops the document.
class WorkspaceDocumentScope extends ConsumerStatefulWidget {
  final WorkspaceDomain domain;
  final String entityId;
  final String title;

  /// What a mail tab opens: the message the route reads. A conversation is one
  /// tab keyed by its thread, so the tab has to carry the message itself.
  final String? messageId;

  /// Whether the document owns the canvas (its own tab) or only the reading
  /// pane beside the lens' list. Null means "ask the bar": a surface that the
  /// bar already holds as a document is a full screen, and one it does not is
  /// a pane.
  final bool? fullScreen;

  final Widget child;

  const WorkspaceDocumentScope({
    super.key,
    required this.domain,
    required this.entityId,
    required this.title,
    this.messageId,
    this.fullScreen,
    required this.child,
  });

  @override
  ConsumerState<WorkspaceDocumentScope> createState() =>
      _WorkspaceDocumentScopeState();
}

class _WorkspaceDocumentScopeState
    extends ConsumerState<WorkspaceDocumentScope> {
  /// The strip's controller, held from the first build: `ref` is unusable in
  /// [dispose], where the surface hands the canvas back.
  late final WorkspaceTabsController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = ref.read(workspaceTabsProvider.notifier);
    _register();
  }

  @override
  void didUpdateWidget(WorkspaceDocumentScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entityId != widget.entityId ||
        oldWidget.title != widget.title ||
        oldWidget.messageId != widget.messageId ||
        oldWidget.fullScreen != widget.fullScreen) {
      _register();
    }
  }

  @override
  void dispose() {
    // The surface leaving the canvas hands it back: its tab stays on the strip
    // — a tab closes when the reader closes it — but nothing claims the pane
    // any more, so the lens shows its root again. The write is deferred past
    // the tree being finalized, where a provider may not be modified.
    final key = WorkspaceTab.keyFor(widget.domain, widget.entityId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tabs.release(key));
    super.dispose();
  }

  void _register() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tabs = ref.read(workspaceTabsProvider.notifier);
      tabs.register(
        domain: widget.domain,
        entityId: widget.entityId,
        title: widget.title,
        messageId: widget.messageId,
        fullScreen:
            widget.fullScreen ??
            tabs.isDocument(widget.domain, widget.entityId),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
