import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart'
    as foundation;
import 'package:window_manager/window_manager.dart';

import 'package:solwatt/app_logging.dart';
import 'package:solwatt/core/config.dart';
import 'package:solwatt/core/drive_wiring.dart';
import 'package:solwatt/firebase_options.dart';
import 'package:solwatt/mail/mail_screen.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/notifications/notifications.dart';
import 'package:solwatt/push/push_service.dart';
import 'package:solwatt/realtime/realtime.dart';
import 'package:solwatt/route.dart';
import 'package:solwatt/tasks/task_overlay.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/ui/cloud_files.dart';
import 'package:solwatt/ui/page_scaffold.dart';
import 'package:solwatt/websocket.dart';
import 'package:solwatt/workspaces/workspace_actions.dart';


final globalOverlay = GlobalKey<OverlayState>();

/// Matches the generated [GateRoute] name for navigation outside typed routes.
const gateRouteName = 'GateRoute';

BorderRadius? _workspaceAvatarBorderRadius(Workspace? workspace) =>
    workspace?.isIndividual == true ? BorderRadius.circular(999) : null;

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await EasyLocalization.ensureInitialized();
  EasyLocalization.logger.enableBuildModes = [];
  await initializeAppLogging();

  // Firebase for Metoer push notifications (Android/iOS/macOS only;
  // firebase_core has no Linux/Windows/web support here). The background
  // handler must be registered before any message can be received in a
  // terminated app. Initialization is skipped (push unavailable) when the
  // platform Firebase configs are missing.
  if (firebaseSupported()) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(
        solWattFirebaseMessagingBackgroundHandler,
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[SolWatt] Firebase init skipped; push unavailable: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  if (DesktopWindowFrame.isPlatformDesktop) {
    await windowManager.ensureInitialized();
    const minimumWindowSize = Size(360, 640);
    const options = WindowOptions(
      size: Size(1180, 760),
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: true,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setMinimumSize(minimumWindowSize);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  FlutterNativeSplash.remove();

  final preferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        ...driveHostOverrides(),
      ],
      child: EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/i18n',
        fallbackLocale: const Locale('en', 'US'),
        useFallbackTranslations: true,
        child: SolWattApp(),
      ),
    ),
  );
}

class SolWattApp extends ConsumerWidget {
  const SolWattApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);
    final accentSeed =
        Color(ref.watch(appAccentColorProvider) ?? kSolWattSeedColor.toARGB32());
    IslandUIFoundation.configureOverlay(globalOverlay);
    IslandUIFoundation.configureNavigator(appRouter.navigatorKey);

    return MaterialApp.router(
      title: 'SolWatt',
      debugShowCheckedModeBanner: false,
      theme: createSolWattTheme(Brightness.light, seedColor: accentSeed),
      darkTheme: createSolWattTheme(Brightness.dark, seedColor: accentSeed),
      themeMode: themeMode,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: [
        ...context.localizationDelegates,
        // The drive renders `material_ui` fork widgets (AppBar, PopupMenuButton,
        // …) whose MaterialLocalizations is a *distinct* type from Flutter's;
        // the fork's delegates must be registered or those widgets assert.
        ...mui.GlobalMaterialLocalizations.delegates,
        FlutterQuillLocalizations.delegate,
      ],
      locale: context.locale,
      builder: (context, child) {
        // DesktopWindowFrame and the other `island_ui_foundation` chrome
        // (bottom sheets, snackbars, notification overlays) paint with the
        // `material_ui` fork, which reads a *separate* theme system from
        // Flutter's. Mirror the app theme into it — colors, typography, icons,
        // density — or that chrome falls back to the fork's defaults (wrong
        // font, always-light scheme).
        //
        // The mirroring must happen inside the OverlayEntry builder: Overlay
        // only reads `initialEntries` once, so a closure capturing builder-
        // scope values would freeze the chrome at launch theme values. Reading
        // Theme.of(context) here re-runs on every app theme change.
        return Overlay(
          key: globalOverlay,
          initialEntries: [
            OverlayEntry(
              builder: (context) {
                final scheme = Theme.of(context).colorScheme;
                return mui.Theme(
                  data: createSolWattForkTheme(Theme.of(context)),
                  child: DesktopWindowFrame(
                    isDesktopPlatform: DesktopWindowFrame.isPlatformDesktop,
                    title: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'appName'.tr(),
                        // The titlebar sits outside any Scaffold, so the
                        // default text style would fall back to a light-mode
                        // color; pin it to the active scheme explicitly.
                        style: TextStyle(color: scheme.onSurface),
                      ),
                    ),
                    child: child ?? const SizedBox.shrink(),
                  ),
                );
              },
            ),
            OverlayEntry(builder: (_) => const _WebSocketIndicator()),
          ],
        );
      },
      routerConfig: appRouter.config(),
    );
  }
}

@RoutePage()
class AppShellPage extends ConsumerWidget {
  const AppShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(appAccessProvider);
    ref.watch(realtimeBridgeProvider);
    // Keeps the Metoer push subscription alive (and subscribing on sign-in)
    // for the whole app session.
    ref.watch(solWattPushProvider);

    ref.listen(appAccessProvider, (previous, next) {
      next.whenData((state) {
        if (state != AppAccess.ready && context.mounted) {
          context.router.replaceAll([const PageRouteInfo(gateRouteName)]);
        }
      });
    });

    void returnToGate() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        context.router.replaceAll([const PageRouteInfo(gateRouteName)]);
      });
    }

    return access.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: EmptyState(
              icon: Symbols.error,
              title: 'couldNotOpenSolWatt'.tr(),
              message: error.toString(),
              action: FilledButton(
                onPressed: () => context.router.replaceAll([
                  const PageRouteInfo(gateRouteName),
                ]),
                child: Text('backToSignIn'.tr()),
              ),
            ),
          ),
        ),
      ),
      data: (state) {
        if (state != AppAccess.ready) {
          returnToGate();
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return AutoTabsRouter(
          routes: const [
            MailRoute(),
            BoardsRoute(),
            FileListRoute(),
            FlywheelRoute(),
            ProfileRoute(),
          ],
          builder: (context, child) {
            final tabs = AutoTabsRouter.of(context);
            return _NavigationShell(
              selectedIndex: tabs.activeIndex,
              onSelected: tabs.setActiveIndex,
              child: child,
            );
          },
        );
      },
    );
  }
}

class _NavigationShell extends ConsumerWidget {
  const _NavigationShell({
    required this.selectedIndex,
    required this.onSelected,
    required this.child,
  });

  static final _desktopNavigationKey = GlobalKey(
    debugLabel: 'desktop-navigation',
  );
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    final wide = isWideScreen(context);
    final scheme = Theme.of(context).colorScheme;
    final isMail = selectedIndex == _mailTabIndex;
    // A page pushed inside the active tab's stack (a board, mail settings, the
    // profile's settings) leads with Back, so the drawer's edge swipe must not
    // reach over it: the shell only offers it at the tab's root. The tabs
    // router rebuilds this shell on every nested push, so the flag stays
    // current.
    final nestedPage = AutoTabsRouter.of(context).activeRouterCanPop();

    return Scaffold(
      drawerEnableOpenDragGesture: !nestedPage,
      // Switching tabs rebuilds this shell, and the drawer is still sliding
      // shut while it does. A `GlobalKey()` field would hand the scaffold a
      // new key on every rebuild, remounting it and dropping the drawer
      // mid-transition; `shellScaffoldKey` is stable for the app's lifetime and
      // is also what pages without their own scaffold (the drive file list)
      // use to open the drawer.
      key: shellScaffoldKey,
      backgroundColor: scheme.surface,
      drawer: Drawer(
        child: _GlobalNavigationDrawer(
          workspace: workspace,
          selectedIndex: selectedIndex,
          onSelected: onSelected,
        ),
      ),
      body: SafeArea(
        // The top inset belongs to the page's app bar: the page's own scaffold
        // adds it to the bar's height and paints the strip behind the status
        // bar. Claiming it here would leave that strip showing the shell's
        // bare background instead of the bar's color. Bottom and side insets
        // stay here, because the bars around the body are the shell's.
        top: false,
        child: Column(
          children: [
            Expanded(
              child: wide
                  ? Row(
                      children: [
                        // The rail is the one child with no app bar above it,
                        // so it claims the top inset for itself.
                        SafeArea(
                          bottom: false,
                          child: _DesktopNavigation(
                            // Switching tabs re-keys the shell route's page
                            // (auto_route keys AutoRoutePage by the route
                            // matchId), which remounts this whole subtree. The
                            // rail keeps a stable GlobalKey so the
                            // AnimatedSwitcher below survives the remount and
                            // can cross-fade the destination sets.
                            key: _desktopNavigationKey,
                            selectedIndex: selectedIndex,
                            onSelected: onSelected,
                            workspace: workspace,
                            onOpenDrawer: () =>
                                shellScaffoldKey.currentState?.openDrawer(),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 0, 8, 8),
                            child: Material(
                              color: scheme.surface,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(16),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: child,
                            ),
                          ),
                        ),
                      ],
                    )
                  : ColoredBox(color: scheme.surface, child: child),
            ),
            const TaskOverlayHost(),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : isMail
          ? const _MailFolderNavigationBar()
          : _TabNavigationBar(
              selectedIndex: selectedIndex,
              onSelected: onSelected,
            ),
    );
  }
}

class _GlobalNavigationDrawer extends StatelessWidget {
  const _GlobalNavigationDrawer({
    required this.workspace,
    required this.selectedIndex,
    required this.onSelected,
  });

  final Workspace? workspace;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final selectedTab = _appTabs.indexWhere(
      (tab) => tab.index == selectedIndex,
    );
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // The header shows the workspace background as a cover image (Island
    // style); the info row then needs light text over the dark gradient.
    final background = workspace?.background;
    final backgroundImage = background == null
        ? null
        : foundation.cloudFileImageProvider(
            serverUrl: kSolarNetworkApiBase,
            id: background.id,
            storageUrl: background.storageUrl,
            workspaceId: workspace?.id,
          );
    final onHeader = backgroundImage == null ? null : Colors.white;
    final onHeaderMuted = backgroundImage == null ? null : Colors.white70;

    void select(int index) {
      Navigator.of(context).pop();
      onSelected(index);
    }

    return SafeArea(
      child: NavigationDrawer(
        selectedIndex: selectedTab < 0 ? null : selectedTab,
        onDestinationSelected: (index) => select(_appTabs[index].index),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Material(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => select(_profileTabIndex),
                child: SizedBox(
                  height: 96,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (backgroundImage != null)
                        Image(
                          image: backgroundImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      if (backgroundImage != null)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.12),
                                Colors.black.withValues(alpha: 0.48),
                              ],
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CloudFileAvatar(
                              file: workspace?.picture,
                              workspaceId: workspace?.id,
                              fallbackIcon: Symbols.workspaces,
                              size: 28,
                              selected: true,
                              borderRadius: _workspaceAvatarBorderRadius(
                                workspace,
                              ),
                              assumeImage: true,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    workspace?.name ?? 'workspace'.tr(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.titleSmall?.copyWith(
                                      color: onHeader,
                                    ),
                                  ),
                                  Text(
                                    'manageWorkspaces'.tr(),
                                    style: text.bodySmall?.copyWith(
                                      color: onHeaderMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Symbols.chevron_right,
                              color: onHeader,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          for (final tab in _appTabs) ...[
            // Profile opens its own group: generous spacing around the divider
            // (height grows, the 1px line stays thin) so the account entry
            // reads as a separate group.
            if (tab.index == _profileTabIndex)
              const Divider(height: 32, thickness: 1),
            NavigationDrawerDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.icon, fill: 1),
              label: Text(tab.label.tr()),
            ),
          ],
        ],
      ),
    );
  }
}

const _mailTabIndex = 0;
const _boardsTabIndex = 1;
const _filesTabIndex = 2;
const _flywheelTabIndex = 3;
const _profileTabIndex = 4;

/// Top-level tabs in tab-index order, shared by the drawer, the desktop rail
/// and the phone bottom bar.
const _appTabs = [
  (index: _mailTabIndex, icon: Symbols.mail, label: 'mail'),
  (index: _boardsTabIndex, icon: Symbols.view_kanban, label: 'boards'),
  (index: _filesTabIndex, icon: Symbols.folder, label: 'files'),
  (index: _flywheelTabIndex, icon: Symbols.sync, label: 'flywheel'),
  (index: _profileTabIndex, icon: Symbols.person, label: 'profile'),
];

/// Tabs the desktop rail carries directly; Flywheel and Profile stay in the
/// drawer there, which the rail's trailing button opens.
const _railTabIndexes = {_mailTabIndex, _boardsTabIndex, _filesTabIndex};

/// Mail folders in navigation order, shared by the desktop rail and the mobile
/// bottom bar so both surfaces list the same destinations.
const _mailFolders = ['inbox', 'sent', 'drafts', 'spam', 'trash', 'archive'];

/// Unread count of the inbox of the mailbox the user is currently reading.
int _inboxUnreadFor(
  List<MailMailbox> mailboxes,
  String? selectedMailboxId,
  Map<String, int> unreadCounts,
) {
  final mailbox =
      mailboxes.where((m) => m.id == selectedMailboxId).firstOrNull ??
      mailboxes.where((m) => m.isDefault).firstOrNull ??
      (mailboxes.isEmpty ? null : mailboxes.first);
  return mailbox == null ? 0 : (unreadCounts[mailbox.id] ?? 0);
}

/// Folder icon for a navigation destination, badged on the inbox.
Widget _folderDestinationIcon(
  String folder, {
  required bool selected,
  required int unread,
}) {
  final icon = Icon(_folderIcon(folder), fill: selected ? 1 : 0);
  if (folder != 'inbox' || unread <= 0) return icon;
  return Badge(label: Text(unread > 99 ? '99+' : '$unread'), child: icon);
}

/// Lists every folder so the ones the bottom bar cuts off stay reachable, and
/// applies the chosen folder.
Future<void> _showFolderSheet(
  BuildContext context,
  WidgetRef ref,
  String selected,
) async {
  final scheme = Theme.of(context).colorScheme;
  final folder = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) => SheetScaffold(
      titleText: 'folders'.tr(),
      heightFactor: 0.7,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          for (final folder in _mailFolders)
            ListTile(
              leading: Icon(
                _folderIcon(folder),
                color: folder == selected
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
                fill: folder == selected ? 1 : 0,
              ),
              title: Text(mailFolderLabel(folder)),
              trailing: folder == selected
                  ? Icon(Symbols.check, color: scheme.primary)
                  : null,
              onTap: () => Navigator.of(sheetContext).pop(folder),
            ),
        ],
      ),
    ),
  );
  if (folder == null) return;
  ref.read(selectedFolderProvider.notifier).select(folder);
}

/// Bottom navigation shown on mail pages: the mail folders, mirroring the
/// desktop rail. A phone fits only four folders, so the rest move behind the
/// trailing "more" destination.
class _MailFolderNavigationBar extends ConsumerWidget {
  const _MailFolderNavigationBar();

  static const _maxVisible = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedFolderProvider);
    final unread = _inboxUnreadFor(
      ref.watch(mailboxesProvider).value ?? const <MailMailbox>[],
      ref.watch(selectedMailboxIdProvider),
      ref.watch(mailboxUnreadCountsProvider).value ?? const <String, int>{},
    );

    final visible = _mailFolders.take(_maxVisible).toList();
    final hasOverflow = _mailFolders.length > _maxVisible;
    final visibleIndex = visible.indexOf(selected);

    return _BottomNavigationBar(
      // A folder outside the visible set keeps the "more" entry highlighted,
      // so the bar still shows where the current folder came from.
      selectedIndex: visibleIndex < 0 ? visible.length : visibleIndex,
      onDestinationSelected: (index) {
        if (index == visible.length) {
          _showFolderSheet(context, ref, selected);
          return;
        }
        ref.read(selectedFolderProvider.notifier).select(visible[index]);
      },
      destinations: [
        for (final folder in visible)
          NavigationDestination(
            icon: _folderDestinationIcon(
              folder,
              selected: false,
              unread: unread,
            ),
            selectedIcon: _folderDestinationIcon(
              folder,
              selected: true,
              unread: unread,
            ),
            label: mailFolderLabel(folder),
          ),
        if (hasOverflow)
          NavigationDestination(
            icon: const Icon(Symbols.all_inbox),
            label: 'more'.tr(),
          ),
      ],
    );
  }
}

/// Bottom navigation shown on non-mail pages: every top-level tab, mirroring
/// the drawer. The mail tab swaps it for the mail folders.
class _TabNavigationBar extends ConsumerWidget {
  const _TabNavigationBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = _inboxUnreadFor(
      ref.watch(mailboxesProvider).value ?? const <MailMailbox>[],
      ref.watch(selectedMailboxIdProvider),
      ref.watch(mailboxUnreadCountsProvider).value ?? const <String, int>{},
    );

    return _BottomNavigationBar(
      // Tab index and destination index are the same: _appTabs is in tab
      // order.
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      destinations: [
        for (final tab in _appTabs)
          NavigationDestination(
            icon: tab.index == _mailTabIndex
                ? _InboxRailIcon(unread: unread)
                : Icon(tab.icon),
            selectedIcon: tab.index == _mailTabIndex
                ? _InboxRailIcon(unread: unread, selected: true)
                : Icon(tab.icon, fill: 1),
            label: tab.label.tr(),
          ),
      ],
    );
  }
}

/// Shared chrome for the phone bottom bars — both the mail folder bar and the
/// tab bar render through it, so their surface, insets and label behavior
/// cannot drift apart. The tonal surface is painted across the full width, the
/// destinations sit inset from the edges, and only the active destination
/// keeps its label.
class _BottomNavigationBar extends StatelessWidget {
  const _BottomNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> destinations;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: .symmetric(horizontal: 8, vertical: 4),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          labelBehavior: .onlyShowSelected,
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: destinations,
        ),
      ),
    );
  }
}

class _DesktopNavigation extends ConsumerWidget {
  const _DesktopNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.onOpenDrawer,
    this.workspace,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onOpenDrawer;
  final Workspace? workspace;

  String? get workspaceName => workspace?.name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final selectedFolder = ref.watch(selectedFolderProvider);
    final mailboxes =
        ref.watch(mailboxesProvider).value ?? const <MailMailbox>[];
    final selectedMailboxId = ref.watch(selectedMailboxIdProvider);
    final unreadCounts =
        ref.watch(mailboxUnreadCountsProvider).value ?? const <String, int>{};

    // Unread badge on the Inbox folder for the effective mailbox.
    final inboxUnread = _inboxUnreadFor(
      mailboxes,
      selectedMailboxId,
      unreadCounts,
    );

    final isMail = selectedIndex == _mailTabIndex;
    final folderIndex = _mailFolders.indexOf(selectedFolder);
    // Flywheel and the merged Profile/Settings entry stay behind the drawer,
    // so only the rail's own tabs are destinations here.
    final railTabs = [
      for (final tab in _appTabs)
        if (_railTabIndexes.contains(tab.index)) tab,
    ];
    final tabIndex = railTabs.indexWhere((tab) => tab.index == selectedIndex);

    // Leading/trailing chrome is identical for both destination sets and is
    // hoisted out of the animated rails so it never flickers during the
    // cross-fade below.
    final leading = Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 4),
      child: Tooltip(
        message: workspaceName == null
            ? 'workspaces'.tr()
            : '${'workspace'.tr()}: $workspaceName',
        child: Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onOpenDrawer,
            child: SizedBox(
              width: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 10,
                ),
                child: Column(
                  children: [
                    CloudFileAvatar(
                      file: workspace?.picture,
                      workspaceId: workspace?.id,
                      fallbackIcon: Symbols.workspaces,
                      size: 22,
                      borderRadius: _workspaceAvatarBorderRadius(workspace),
                      assumeImage: true,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      workspaceName ?? 'workspace'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final trailing = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const NotificationBellButton(),
          const SizedBox(height: 4),
          _RailIconButton(
            tooltip: 'more'.tr(),
            onPressed: onOpenDrawer,
            child: const Icon(Symbols.menu),
          ),
        ],
      ),
    );

    return SizedBox(
      width: 88,
      child: Column(
        children: [
          const SizedBox(height: 8),
          leading,
          const SizedBox(height: 8),
          // The rail hosts two destination sets — the mail folders while in
          // Mail, the feature destinations otherwise. AnimatedSwitcher
          // cross-fades between them; the outgoing rail is ignored so it
          // cannot steal taps mid-transition.
          Expanded(
            child: AnimatedSwitcher(
              key: const ValueKey('rail-switcher'),
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.02),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              layoutBuilder: (currentChild, previousChildren) => Stack(
                fit: StackFit.expand,
                children: [
                  for (final child in previousChildren)
                    IgnorePointer(ignoring: true, child: child),
                  ?currentChild,
                ],
              ),
              child: isMail
                  ? _buildRail(
                      key: const ValueKey('mail-folders'),
                      selectedIndex: folderIndex >= 0 ? folderIndex : null,
                      destinations: [
                        for (final folder in _mailFolders)
                          NavigationRailDestination(
                            icon: folder == 'inbox'
                                ? _InboxRailIcon(unread: inboxUnread)
                                : Icon(_folderIcon(folder)),
                            selectedIcon: folder == 'inbox'
                                ? _InboxRailIcon(
                                    unread: inboxUnread,
                                    selected: true,
                                  )
                                : Icon(_folderIcon(folder), fill: 1),
                            label: Text(mailFolderLabel(folder)),
                          ),
                      ],
                      onDestinationSelected: (index) {
                        ref
                            .read(selectedFolderProvider.notifier)
                            .select(_mailFolders[index]);
                        onSelected(_mailTabIndex);
                      },
                    )
                  : _buildRail(
                      key: const ValueKey('feature-destinations'),
                      selectedIndex: tabIndex >= 0 ? tabIndex : null,
                      destinations: [
                        for (final tab in railTabs)
                          NavigationRailDestination(
                            icon: tab.index == _mailTabIndex
                                ? _InboxRailIcon(unread: inboxUnread)
                                : Icon(tab.icon),
                            selectedIcon: tab.index == _mailTabIndex
                                ? _InboxRailIcon(
                                    unread: inboxUnread,
                                    selected: true,
                                  )
                                : Icon(tab.icon, fill: 1),
                            label: Text(tab.label.tr()),
                          ),
                      ],
                      onDestinationSelected: (index) =>
                          onSelected(railTabs[index].index),
                    ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _buildRail({
    required Key key,
    required int? selectedIndex,
    required List<NavigationRailDestination> destinations,
    required ValueChanged<int> onDestinationSelected,
  }) {
    return Transform.translate(
      key: key,
      // NavigationRail always reserves an 8px spacer above its destination
      // group, so a rail stripped of `leading`/`trailing` centers the group
      // 4px lower than one that owns them. Shift back up to keep the group
      // vertically centered in the rail.
      offset: const Offset(0, -4),
      child: NavigationRail(
        backgroundColor: Colors.transparent,
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        labelType: NavigationRailLabelType.all,
        groupAlignment: 0,
        destinations: destinations,
      ),
    );
  }
}

IconData _folderIcon(String folder) => switch (folder) {
  'sent' => Symbols.send,
  'drafts' => Symbols.drafts,
  'spam' => Symbols.report,
  'trash' => Symbols.delete,
  'archive' => Symbols.archive,
  _ => Symbols.inbox,
};

/// Mail icon with an optional unread-count badge for rail/bottom-bar inboxes.
class _InboxRailIcon extends StatelessWidget {
  const _InboxRailIcon({required this.unread, this.selected = false});

  final int unread;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      selected ? Symbols.mail : Symbols.mail_outline,
      fill: selected ? 1 : 0,
    );
    if (unread <= 0) return icon;
    return Badge(label: Text(unread > 99 ? '99+' : '$unread'), child: icon);
  }
}

class _RailIconButton extends StatelessWidget {
  const _RailIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(width: 48, height: 48, child: Center(child: child)),
        ),
      ),
    );
  }
}

class _WebSocketIndicator extends ConsumerWidget {
  const _WebSocketIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider).value;
    final state = ref.watch(websocketStateProvider);
    if (session == null || state == WebSocketConnectionState.connected) {
      return const SizedBox.shrink();
    }

    final (color, message, icon, canReconnect) = switch (state) {
      WebSocketConnectionState.connecting => (
        Colors.teal,
        'Reconnecting…',
        const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        ),
        false,
      ),
      WebSocketConnectionState.serverDown => (
        Theme.of(context).colorScheme.error,
        'Live updates are unavailable. Tap to retry.',
        const Icon(Symbols.power_off, color: Colors.white, size: 16),
        true,
      ),
      WebSocketConnectionState.error => (
        Theme.of(context).colorScheme.error,
        'Connection error. Tap to retry.',
        const Icon(Symbols.power_off, color: Colors.white, size: 16),
        true,
      ),
      WebSocketConnectionState.disconnected => (
        Theme.of(context).colorScheme.error,
        'Live updates are offline. Tap to reconnect.',
        const Icon(Symbols.power_off, color: Colors.white, size: 16),
        true,
      ),
      WebSocketConnectionState.connected => throw StateError('unreachable'),
    };

    return Positioned(
      top: MediaQuery.paddingOf(context).top + 36,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !canReconnect,
        child: Align(
          alignment: Alignment.topCenter,
          child: Material(
            elevation: 4,
            color: color,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: canReconnect
                  ? () => ref
                        .read(websocketStateProvider.notifier)
                        .manualReconnect()
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(width: 8),
                    Text(message, style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@RoutePage()
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Nested stack host: settings and about push onto the profile tab instead
    // of replacing the whole shell (mirrors MailPage hosting its children).
    return const AutoRouter();
  }
}

@RoutePage()
class ProfileHomePage extends ConsumerWidget {
  const ProfileHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userInfoProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return PageScaffold(
      title: 'profile'.tr(),
      subtitle: 'accountAndWorkspaces'.tr(),
      action: IconButton.filledTonal(
        tooltip: 'refresh'.tr(),
        onPressed: () {
          ref.invalidate(solWattProfileProvider);
          ref.invalidate(userInfoProvider);
          ref.invalidate(workspacesProvider);
        },
        icon: const Icon(Symbols.refresh),
      ),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: profile.when(
                    loading: () => ListTile(
                      leading: const SizedBox.square(
                        dimension: 48,
                        child: Center(
                          child: SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                      title: Text('loadingProfile'.tr()),
                    ),
                    error: (_, _) => ListTile(
                      leading: const IconBadge(icon: Symbols.person, size: 48),
                      title: Text('solarNetworkAccount'.tr()),
                    ),
                    data: (user) {
                      if (user == null) return const SizedBox.shrink();
                      final solWatt = ref.watch(solWattProfileProvider).value;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          radius: 26,
                          backgroundColor: scheme.primaryContainer,
                          foregroundColor: scheme.onPrimaryContainer,
                          foregroundImage: user.solWattAvatarUrl == null
                              ? null
                              : NetworkImage(user.solWattAvatarUrl!),
                          child: Text(
                            _initials(user.solWattDisplayName),
                            style: text.titleMedium?.copyWith(
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        title: Text(user.solWattDisplayName),
                        subtitle: Text(
                          solWatt == null
                              ? '@${user.name}'
                              : '@${user.name} · ${solWatt.perkTierName} '
                                    '(perk ${solWatt.perkLevel})',
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                SectionHeader(title: 'appSettingsGroup'.tr()),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const IconBadge(icon: Symbols.settings),
                        title: Text('settings'.tr()),
                        subtitle: Text('settingsSubtitle'.tr()),
                        trailing: const Icon(Symbols.chevron_right),
                        onTap: () =>
                            context.router.push(const AppSettingsRoute()),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const IconBadge(icon: Symbols.info),
                        title: Text('about'.tr()),
                        subtitle: Text('aboutSubtitle'.tr()),
                        trailing: const Icon(Symbols.chevron_right),
                        onTap: () => context.router.push(const AboutRoute()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Sign-out, merged in from the former Settings page.
                Card(
                  child: ListTile(
                    leading: const IconBadge(icon: Symbols.logout),
                    title: Text('signOutAction'.tr()),
                    subtitle: Text('signOutDescription'.tr()),
                    onTap: () async {
                      await ref.read(authenticatorProvider).clear();
                      await clearSelectedWorkspace(
                        ref.read(secureStorageProvider),
                      );
                      invalidateSessionScope(ref);
                      if (!context.mounted) return;
                      context.router.replaceAll([
                        const PageRouteInfo(gateRouteName),
                      ]);
                    },
                  ),
                ),
                const SizedBox(height: 24),
                SectionHeader(
                  title: 'yourWorkspaces'.tr(),
                  trailing: FilledButton.tonalIcon(
                    onPressed: () => createWorkspaceAction(context, ref),
                    icon: const Icon(Symbols.add, size: 18),
                    label: Text('new'.tr()),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: WorkspaceList(
              manageActions: true,
              scrollable: false,
              onActivate: (workspace) async {
                await activateWorkspaceAction(ref, workspace);
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _initials(String name) {
  final parts = name
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0])
      .join()
      .toUpperCase();
  return parts.isEmpty ? '?' : parts;
}
