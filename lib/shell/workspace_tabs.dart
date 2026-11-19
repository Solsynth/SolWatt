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

  /// Null on a lens tab.
  final WorkspaceDomain? domain;
  final String? entityId;

  /// What a mail tab opens: the message the route reads. A conversation is one
  /// tab keyed by its thread, so the tab carries the message it shows.
  final String? messageId;
  final String title;

  /// A pinned tab that stands for a lens rather than a document. The rail
  /// switches lenses, so these tabs are the rail's own: they never close, and
  /// landing on a lens activates the tab that is already there.
  final bool isRoot;

  const WorkspaceTab({
    required this.key,
    required this.lens,
    required this.title,
    this.domain,
    this.entityId,
    this.messageId,
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

  /// The tab on screen. Null when nothing claims the active key.
  WorkspaceTab? get activeTab => tabs.where(isActive).firstOrNull;

  /// Whether a document owns the canvas. The shell strips its own chrome for
  /// it: a document is a full screen, not a lens pane.
  bool get showsDocument => activeTab?.isRoot == false;

  /// Whether the canvas is the document of [domain] rather than that lens'
  /// root pane — a mail conversation read in a tab of its own, not the inbox.
  bool showsDocumentOf(WorkspaceDomain domain) {
    final tab = activeTab;
    return tab != null && !tab.isRoot && tab.domain == domain;
  }
}

/// The route a tab opens into its lens' nested stack. Null for tabs whose
/// content is a pane of the canvas (the drive's reader, a page) rather than a
/// page in the lens' stack.
PageRouteInfo? routeForTab(WorkspaceTab tab) => switch (tab.domain) {
  WorkspaceDomain.mail =>
    tab.messageId == null ? null : MailDetailRoute(emailId: tab.messageId!),
  WorkspaceDomain.todo => TaskBoardRoute(broadId: tab.entityId!),
  WorkspaceDomain.drive || WorkspaceDomain.pages || null => null,
};

WorkspaceLens lensOfDomain(WorkspaceDomain domain) => switch (domain) {
  WorkspaceDomain.mail => WorkspaceLens.mail,
  WorkspaceDomain.todo => WorkspaceLens.todo,
  WorkspaceDomain.pages => WorkspaceLens.pages,
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
  bool isDocument(WorkspaceDomain domain, String entityId) {
    final key = WorkspaceTab.keyFor(domain, entityId);
    return state.tabs.any((tab) => tab.key == key && !tab.isRoot);
  }

  /// Registers the document on screen, adding or refreshing its tab.
  ///
  /// [fullScreen] false is a reading pane, not a tab: the lens' own tab is
  /// retitled after what the pane shows and becomes active, so reading a mail
  /// in the right column never grows a second tab beside the inbox. The tab
  /// itself is created by whoever puts the lens on screen, never here.
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
    final key = WorkspaceTab.keyFor(domain, entityId);
    final lens = lensOfDomain(domain);

    if (!fullScreen) {
      showingLensRoot(lens, title: title);
      activate(WorkspaceTab.lensTabKey(lens));
      return;
    }

    final tabs = [...state.tabs];
    final existing = tabs.indexWhere((tab) => tab.key == key);
    final tab = WorkspaceTab(
      key: key,
      lens: lens,
      domain: domain,
      entityId: entityId,
      messageId: messageId,
      title: title,
    );
    if (existing == -1) {
      tabs.add(tab);
    } else {
      tabs[existing] = tab;
    }
    state = WorkspaceTabState(tabs: tabs, activeKey: key);
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
    final key = WorkspaceTab.keyFor(domain, entityId);
    final tabs = [...state.tabs];
    final existing = tabs.indexWhere((tab) => tab.key == key);
    final tab = WorkspaceTab(
      key: key,
      lens: lensOfDomain(domain),
      domain: domain,
      entityId: entityId,
      messageId: messageId,
      title: title,
    );
    if (existing == -1) {
      tabs.add(tab);
    } else {
      tabs[existing] = tab;
    }
    state = WorkspaceTabState(tabs: tabs, activeKey: key);
  }

  /// Puts [lens] on screen, reusing the tab it already has.
  ///
  /// The rail addresses a place, not a document, so a rail click must never
  /// spend a tab: the lens' own tab is retitled to whatever its root pane is
  /// called, documents keep the tabs they own, and nothing new is added unless
  /// the reader has never been to that lens. [title] is the label the root pane
  /// wants — the folder browser's, the inbox's — falling back to the lens name.
  void focusLens(WorkspaceLens lens, {String? title}) {
    if (!ref.mounted) return;
    final key = WorkspaceTab.lensTabKey(lens);
    final current = state.tabs.where((tab) => tab.key == key).firstOrNull;
    final label = title ?? lens.label;
    if (current != null &&
        current.title == label &&
        current.lens == lens &&
        state.activeKey == key) {
      return;
    }
    final root = WorkspaceTab(
      key: key,
      lens: lens,
      title: title ?? lens.label,
      isRoot: true,
    );
    final pinned =
        [...state.tabs.where((tab) => tab.isRoot && tab.lens != lens), root]
          ..sort(
            (a, b) => kShellLenses
                .indexOf(a.lens)
                .compareTo(kShellLenses.indexOf(b.lens)),
          );
    state = WorkspaceTabState(
      tabs: [...pinned, ...state.tabs.where((tab) => !tab.isRoot)],
      activeKey: key,
    );
  }

  /// Gives [lens] its pinned tab when the bar does not carry it yet, without
  /// changing what is on screen. The shell seeds on every rebuild, so it must
  /// be a no-op once the tab exists — and it never steals the canvas from the
  /// document the reader is reading beside it.
  void seedLens(WorkspaceLens lens) {
    if (!ref.mounted) return;
    final key = WorkspaceTab.lensTabKey(lens);
    if (state.tabs.any((tab) => tab.key == key)) return;
    final pinned =
        [
          ...state.tabs.where((tab) => tab.isRoot),
          WorkspaceTab(key: key, lens: lens, title: lens.label, isRoot: true),
        ]..sort(
          (a, b) => kShellLenses
              .indexOf(a.lens)
              .compareTo(kShellLenses.indexOf(b.lens)),
        );
    state = WorkspaceTabState(
      tabs: [...pinned, ...state.tabs.where((tab) => !tab.isRoot)],
      activeKey: state.activeKey ?? key,
    );
  }

  /// Declares that [lens] is sitting on its root pane (the drive's folder
  /// browser, the inbox's list). Only the label changes: the pinned tab either
  /// exists already or joins the strip without stealing the active tab from a
  /// document open beside it.
  void showingLensRoot(WorkspaceLens lens, {required String title}) {
    if (!ref.mounted) return;
    final key = WorkspaceTab.lensTabKey(lens);
    final root = WorkspaceTab(key: key, lens: lens, title: title, isRoot: true);
    final pinned =
        [...state.tabs.where((tab) => tab.isRoot && tab.lens != lens), root]
          ..sort(
            (a, b) => kShellLenses
                .indexOf(a.lens)
                .compareTo(kShellLenses.indexOf(b.lens)),
          );
    state = WorkspaceTabState(
      tabs: [...pinned, ...state.tabs.where((tab) => !tab.isRoot)],
      activeKey: state.activeKey,
    );
  }

  /// Marks [key] as the tab on screen without touching the tab list.
  void activate(String key) {
    if (!ref.mounted || state.activeKey == key) return;
    state = WorkspaceTabState(tabs: state.tabs, activeKey: key);
  }

  /// Removes a document tab. A lens tab is pinned: the rail has no other road
  /// back to its lens, so it is not closable.
  void close(String key) {
    if (!ref.mounted) return;
    final tab = state.tabs.where((t) => t.key == key).firstOrNull;
    if (tab == null || tab.isRoot) return;
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
        oldWidget.messageId != widget.messageId ||
        oldWidget.fullScreen != widget.fullScreen) {
      _register();
    }
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
