import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:material_symbols_icons/symbols.dart';
import 'package:window_manager/window_manager.dart';

import 'app_logging.dart';
import 'boards/boards_screen.dart';
import 'files/files_screen.dart';
import 'flywheel/flywheel_page.dart';
import 'gate/gate_page.dart';
import 'mail/mail_screen.dart';
import 'network.dart';
import 'notifications/notifications.dart';
import 'realtime/realtime.dart';
import 'tasks/task_overlay.dart';
import 'theme.dart';
import 'ui/cloud_files.dart';
import 'ui/page_scaffold.dart';
import 'websocket.dart';
import 'workspaces/workspace_actions.dart';

part 'main.gr.dart';

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

  runApp(
    ProviderScope(
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

class SolWattApp extends StatelessWidget {
  SolWattApp({super.key});

  final _router = AppRouter();

  @override
  Widget build(BuildContext context) {
    IslandUIFoundation.configureOverlay(globalOverlay);
    IslandUIFoundation.configureNavigator(_router.navigatorKey);

    return MaterialApp.router(
      title: 'SolWatt',
      debugShowCheckedModeBanner: false,
      theme: createSolWattTheme(Brightness.light),
      darkTheme: createSolWattTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      locale: context.locale,
      builder: (context, child) {
        final scheme = Theme.of(context).colorScheme;
        final brightness = Theme.of(context).brightness;
        // DesktopWindowFrame (island_ui_foundation) paints with the
        // `material_ui` fork's Material, which reads a *separate* theme
        // system from Flutter's. Without a material_ui Theme in scope it
        // falls back to the fork's default (always-light) scheme, so the
        // titlebar never followed the app theme. Mirror the app scheme in a
        // material_ui theme; the window chrome (titlebar) uses the main
        // surface color.
        final chromeScheme = mui.ColorScheme.fromSeed(
          seedColor: kSolWattSeedColor,
          brightness: brightness,
        ).copyWith(surfaceContainer: scheme.surface);
        final chromeTheme = (brightness == Brightness.dark
                ? mui.ThemeData.dark()
                : mui.ThemeData.light())
            .copyWith(colorScheme: chromeScheme);
        return Overlay(
          key: globalOverlay,
          initialEntries: [
            OverlayEntry(
              builder: (_) => mui.Theme(
                data: chromeTheme,
                child: DesktopWindowFrame(
                  isDesktopPlatform: DesktopWindowFrame.isPlatformDesktop,
                  title: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'appName'.tr(),
                      // The titlebar sits outside any Scaffold, so the default
                      // text style would fall back to a light-mode color; pin
                      // it to the active scheme explicitly.
                      style: TextStyle(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
            OverlayEntry(builder: (_) => const _WebSocketIndicator()),
          ],
        );
      },
      routerConfig: _router.config(),
    );
  }
}

@AutoRouterConfig(replaceInRouteName: 'Page,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: GateRoute.page, initial: true),
    AutoRoute(
      page: AppShellRoute.page,
      children: [
        AutoRoute(
          page: MailRoute.page,
          initial: true,
          children: [
            AutoRoute(page: MailListRoute.page, path: '', initial: true),
            AutoRoute(page: MailComposeRoute.page, path: 'compose'),
            AutoRoute(page: MailDetailRoute.page, path: ':id'),
          ],
        ),
        AutoRoute(page: BoardsRoute.page),
        AutoRoute(page: FilesRoute.page),
        AutoRoute(page: FlywheelRoute.page),
        AutoRoute(page: TaskBoardRoute.page),
        AutoRoute(page: ProfileRoute.page),
        AutoRoute(page: SettingsRoute.page),
      ],
    ),
  ];
}

@RoutePage()
class AppShellPage extends ConsumerWidget {
  const AppShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(appAccessProvider);
    ref.watch(realtimeBridgeProvider);

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
            FilesRoute(),
            FlywheelRoute(),
            ProfileRoute(),
            SettingsRoute(),
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
  _NavigationShell({
    required this.selectedIndex,
    required this.onSelected,
    required this.child,
  });

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    final wide = isWideScreen(context);
    final scheme = Theme.of(context).colorScheme;
    final isMail = selectedIndex == _mailTabIndex;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: scheme.surface,
      drawer: Drawer(
        child: _GlobalNavigationDrawer(
          workspace: workspace,
          selectedIndex: selectedIndex,
          onSelected: onSelected,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: wide
                  ? Row(
                      children: [
                        _DesktopNavigation(
                          selectedIndex: selectedIndex,
                          onSelected: onSelected,
                          workspace: workspace,
                          onOpenDrawer: () =>
                              _scaffoldKey.currentState?.openDrawer(),
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
              ? _MailInboxNavigationBar(
                  onOpenDrawer: () =>
                      _scaffoldKey.currentState?.openDrawer(),
                )
              : _FeatureNavigationBar(
                  onOpenDrawer: () =>
                      _scaffoldKey.currentState?.openDrawer(),
                  onGoToMail: () => onSelected(_mailTabIndex),
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
    const drawerRoutes = [
      _mailTabIndex,
      _boardsTabIndex,
      _filesTabIndex,
      _flywheelTabIndex,
      _profileTabIndex,
      _settingsTabIndex,
    ];
    final selectedDrawerIndex = drawerRoutes.indexOf(selectedIndex);
    final scheme = Theme.of(context).colorScheme;

    void select(int index) {
      Navigator.of(context).pop();
      onSelected(index);
    }

    return SafeArea(
      child: NavigationDrawer(
        selectedIndex: selectedDrawerIndex < 0 ? null : selectedDrawerIndex,
        onDestinationSelected: (index) => select(drawerRoutes[index]),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Material(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => select(_profileTabIndex),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CloudFileAvatar(
                        file: workspace?.picture,
                        workspaceId: workspace?.id,
                        fallbackIcon: Symbols.workspaces,
                        size: 28,
                        selected: true,
                        borderRadius: _workspaceAvatarBorderRadius(workspace),
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
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              'manageWorkspaces'.tr(),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Symbols.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Symbols.mail),
            selectedIcon: const Icon(Symbols.mail, fill: 1),
            label: Text('mail'.tr()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 16, 4),
            child: Text(
              'more'.tr(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Symbols.view_kanban),
            selectedIcon: const Icon(Symbols.view_kanban, fill: 1),
            label: Text('boards'.tr()),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Symbols.folder),
            selectedIcon: const Icon(Symbols.folder, fill: 1),
            label: Text('files'.tr()),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Symbols.sync),
            selectedIcon: const Icon(Symbols.sync, fill: 1),
            label: Text('flywheel'.tr()),
          ),
          const Divider(),
          NavigationDrawerDestination(
            icon: const Icon(Symbols.person),
            selectedIcon: const Icon(Symbols.person, fill: 1),
            label: Text('profile'.tr()),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Symbols.settings),
            selectedIcon: const Icon(Symbols.settings, fill: 1),
            label: Text('settings'.tr()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Symbols.notifications),
            title: Text('notifications'.tr()),
            contentPadding: const EdgeInsets.symmetric(horizontal: 28),
            onTap: () {
              Navigator.of(context).pop();
              showNotificationsAttentionModal();
            },
          ),
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
const _settingsTabIndex = 5;

void _selectMailbox(WidgetRef ref, String id) {
  if (ref.read(selectedMailboxIdProvider) == id) return;
  ref.read(selectedMailboxIdProvider.notifier).select(id);
  ref.invalidate(emailsProvider);
}

/// Opens the "all inboxes" picker sheet and applies the result. Used by the
/// mobile bottom navigation bar and the desktop rail when inboxes overflow.
Future<void> _openMailboxPicker(
  BuildContext context,
  WidgetRef ref, {
  required List<MailMailbox> mailboxes,
  required String? mailHost,
  required String? selectedId,
  VoidCallback? onSelectedMailbox,
}) async {
  final result = await showMailboxPickerSheet(
    context,
    mailboxes: mailboxes,
    mailHost: mailHost,
    selectedId: selectedId,
  );
  if (result == null || !context.mounted) return;
  if (result.createNew) {
    await createMailboxAction(context, ref);
  } else if (result.mailboxId != null) {
    _selectMailbox(ref, result.mailboxId!);
    onSelectedMailbox?.call();
  }
}

/// Bottom navigation shown on mail pages: the app drawer plus one destination
/// per inbox. When more inboxes exist than fit, the last destination opens a
/// picker sheet listing them all.
class _MailInboxNavigationBar extends ConsumerWidget {
  const _MailInboxNavigationBar({required this.onOpenDrawer});

  static const _maxVisibleMailboxes = 3;

  final VoidCallback onOpenDrawer;

  Future<void> _openPicker(
    BuildContext context,
    WidgetRef ref, {
    required List<MailMailbox> mailboxes,
    required String? mailHost,
    required String? selectedId,
  }) =>
      _openMailboxPicker(
        context,
        ref,
        mailboxes: mailboxes,
        mailHost: mailHost,
        selectedId: selectedId,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mailboxes =
        ref.watch(mailboxesProvider).value ?? const <MailMailbox>[];
    // While inboxes are loading (or none exist yet) fall back to the simple
    // drawer + Mail bar; NavigationBar requires at least two destinations.
    if (mailboxes.isEmpty) {
      return _FeatureNavigationBar(
        onOpenDrawer: onOpenDrawer,
        onGoToMail: () {},
      );
    }
    final selectedId = ref.watch(selectedMailboxIdProvider);
    final mailHost = ref.watch(mailHostProvider).value;

    final selected =
        mailboxes.where((m) => m.id == selectedId).firstOrNull ??
        mailboxes.firstWhere((m) => m.isDefault, orElse: () => mailboxes.first);
    final ordered = [
      selected,
      ...mailboxes.where((m) => m != selected),
    ];
    final visible = ordered.take(_maxVisibleMailboxes).toList();
    final hasOverflow = ordered.length > _maxVisibleMailboxes;

    final index = ordered.indexOf(selected);
    final current = index < _maxVisibleMailboxes
        ? index + 1 // +1 for the leading drawer destination
        : _maxVisibleMailboxes + 1; // overflow destination

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: NavigationBar(
        selectedIndex: current,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          if (index == 0) {
            onOpenDrawer();
            return;
          }
          if (hasOverflow && index == _maxVisibleMailboxes + 1) {
            _openPicker(
              context,
              ref,
              mailboxes: mailboxes,
              mailHost: mailHost,
              selectedId: selectedId,
            );
            return;
          }
          final mailbox = visible[index - 1];
          _selectMailbox(ref, mailbox.id);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Symbols.menu),
            label: MaterialLocalizations.of(context).openAppDrawerTooltip,
          ),
          for (final mailbox in visible)
            NavigationDestination(
              icon: const Icon(Symbols.mail),
              selectedIcon: const Icon(Symbols.mail, fill: 1),
              label: mailbox.displayName,
              tooltip: mailbox.fullAddress(mailHost),
            ),
          if (hasOverflow)
            NavigationDestination(
              icon: const Icon(Symbols.more_horiz),
              label: 'allInboxes'.tr(),
            ),
        ],
      ),
    );
  }
}

/// Bottom navigation shown on non-mail pages: back to Mail plus the app drawer
/// that holds every other feature.
class _FeatureNavigationBar extends StatelessWidget {
  const _FeatureNavigationBar({
    required this.onOpenDrawer,
    required this.onGoToMail,
  });

  final VoidCallback onOpenDrawer;
  final VoidCallback onGoToMail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(
                  context,
                ).openAppDrawerTooltip,
                onPressed: onOpenDrawer,
                icon: const Icon(Symbols.menu),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onGoToMail,
                icon: const Icon(Symbols.mail),
                label: Text('mail'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopNavigation extends ConsumerWidget {
  const _DesktopNavigation({
    required this.selectedIndex,
    required this.onSelected,
    required this.onOpenDrawer,
    this.workspace,
  });

  static const _folders = [
    'inbox',
    'sent',
    'drafts',
    'spam',
    'trash',
    'archive',
  ];

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
    final effectiveMailbox =
        mailboxes.where((m) => m.id == selectedMailboxId).firstOrNull ??
        mailboxes.where((m) => m.isDefault).firstOrNull ??
        (mailboxes.isEmpty ? null : mailboxes.first);
    final inboxUnread =
        effectiveMailbox == null ? 0 : (unreadCounts[effectiveMailbox.id] ?? 0);

    final folderIndex = _folders.indexOf(selectedFolder);
    final current =
        selectedIndex == _mailTabIndex && folderIndex >= 0 ? folderIndex : null;

    return SizedBox(
      width: 88,
      child: NavigationRail(
        backgroundColor: Colors.transparent,
        selectedIndex: current,
        onDestinationSelected: (index) {
          ref.read(selectedFolderProvider.notifier).select(_folders[index]);
          onSelected(_mailTabIndex);
        },
        labelType: NavigationRailLabelType.all,
        groupAlignment: 0,
        leading: Padding(
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
        ),
        trailingAtBottom: true,
        trailing: Padding(
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
        ),
        destinations: [
          for (final folder in _folders)
            NavigationRailDestination(
              icon: folder == 'inbox'
                  ? _InboxRailIcon(unread: inboxUnread)
                  : Icon(_folderIcon(folder)),
              selectedIcon: folder == 'inbox'
                  ? _InboxRailIcon(unread: inboxUnread, selected: true)
                  : Icon(_folderIcon(folder), fill: 1),
              label: Text(mailFolderLabel(folder)),
            ),
        ],
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
    return Badge(
      label: Text(unread > 99 ? '99+' : '$unread'),
      child: icon,
    );
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
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    final user = ref.watch(userInfoProvider).value;
    final scheme = Theme.of(context).colorScheme;

    return PageScaffold(
      title: 'settings'.tr(),
      subtitle: 'accountAndConnection'.tr(),
      child: ListView(
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: IconBadge(
                    icon: session.value == null
                        ? Symbols.lock
                        : Symbols.verified_user,
                    selected: session.value != null,
                  ),
                  title: Text(
                    session.value == null
                        ? 'notSignedIn'.tr()
                        : 'connectedToSolarNetwork'.tr(),
                  ),
                  subtitle: Text(
                    user == null ? 'oauthDescription'.tr() : '@${user.name}',
                  ),
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: scheme.outlineVariant,
                ),
                ListTile(
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

@RoutePage()
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    await clearSelectedWorkspace(
                      ref.read(secureStorageProvider),
                    );
                    invalidateWorkspaceScope(ref);
                    if (!context.mounted) return;
                    context.router.replaceAll([
                      const PageRouteInfo(gateRouteName),
                    ]);
                  },
                  icon: const Icon(Symbols.logout, size: 18),
                  label: Text('leaveWorkspace'.tr()),
                ),
              ),
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
