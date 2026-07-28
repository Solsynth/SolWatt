import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';
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
import 'ui/page_scaffold.dart';
import 'websocket.dart';
import 'workspaces/workspace_actions.dart';

part 'main.gr.dart';

final globalOverlay = GlobalKey<OverlayState>();

/// Matches the generated [GateRoute] name for navigation outside typed routes.
const gateRouteName = 'GateRoute';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  EasyLocalization.logger.enableBuildModes = [];
  await initializeAppLogging();

  if (DesktopWindowFrame.isPlatformDesktop) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1180, 760),
      minimumSize: Size(720, 520),
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: true,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

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
      builder: (context, child) => Overlay(
        key: globalOverlay,
        initialEntries: [
          OverlayEntry(
            builder: (_) => DesktopWindowFrame(
              isDesktopPlatform: DesktopWindowFrame.isPlatformDesktop,
              title: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('appName'.tr()),
              ),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ],
      ),
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
        AutoRoute(page: HomeRoute.page, initial: true),
        AutoRoute(page: BoardsRoute.page),
        AutoRoute(page: FilesRoute.page),
        AutoRoute(page: FlywheelRoute.page),
        AutoRoute(page: MailRoute.page),
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
    final wsState = ref.watch(websocketStateProvider);

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
            HomeRoute(),
            BoardsRoute(),
            FilesRoute(),
            FlywheelRoute(),
            MailRoute(),
            ProfileRoute(),
            SettingsRoute(),
          ],
          builder: (context, child) {
            final tabs = AutoTabsRouter.of(context);
            return _NavigationShell(
              selectedIndex: tabs.activeIndex,
              onSelected: tabs.setActiveIndex,
              websocketState: wsState,
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
    required this.websocketState,
    required this.child,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final WebSocketConnectionState websocketState;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    final wide = isWideScreen(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
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
                          workspaceName: workspace?.name,
                          websocketState: websocketState,
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
          : NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelected,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Symbols.home),
                  selectedIcon: const Icon(Symbols.home, fill: 1),
                  label: 'home'.tr(),
                ),
                NavigationDestination(
                  icon: const Icon(Symbols.view_kanban),
                  selectedIcon: const Icon(Symbols.view_kanban, fill: 1),
                  label: 'boards'.tr(),
                ),
                NavigationDestination(
                  icon: const Icon(Symbols.folder),
                  selectedIcon: const Icon(Symbols.folder, fill: 1),
                  label: 'files'.tr(),
                ),
                const NavigationDestination(
                  icon: Icon(Symbols.sync),
                  selectedIcon: Icon(Symbols.sync, fill: 1),
                  label: 'Flywheel',
                ),
                NavigationDestination(
                  icon: const Icon(Symbols.mail),
                  selectedIcon: const Icon(Symbols.mail, fill: 1),
                  label: 'mail'.tr(),
                ),
                NavigationDestination(
                  icon: const Icon(Symbols.person),
                  selectedIcon: const Icon(Symbols.person, fill: 1),
                  label: 'profile'.tr(),
                ),
                NavigationDestination(
                  icon: const Icon(Symbols.settings),
                  selectedIcon: const Icon(Symbols.settings, fill: 1),
                  label: 'settings'.tr(),
                ),
              ],
            ),
    );
  }
}

const _profileTabIndex = 5;
const _settingsTabIndex = 6;

class _DesktopNavigation extends ConsumerWidget {
  const _DesktopNavigation({
    required this.selectedIndex,
    required this.onSelected,
    required this.websocketState,
    this.workspaceName,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final WebSocketConnectionState websocketState;
  final String? workspaceName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userInfoProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SizedBox(
      width: 88,
      child: NavigationRail(
        backgroundColor: Colors.transparent,
        selectedIndex: selectedIndex < _profileTabIndex ? selectedIndex : null,
        onDestinationSelected: onSelected,
        labelType: NavigationRailLabelType.all,
        groupAlignment: -1,
        leading: Padding(
          padding: const EdgeInsets.only(bottom: 16, top: 4),
          child: Tooltip(
            message: workspaceName == null
                ? 'workspaces'.tr()
                : '${'workspace'.tr()}: $workspaceName',
            child: Material(
              color: selectedIndex == _profileTabIndex
                  ? scheme.secondaryContainer
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onSelected(_profileTabIndex),
                child: SizedBox(
                  width: 64,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 10,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Symbols.workspaces,
                          size: 22,
                          fill: selectedIndex == _profileTabIndex ? 1 : 0,
                          color: selectedIndex == _profileTabIndex
                              ? scheme.onSecondaryContainer
                              : scheme.primary,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          workspaceName ?? 'workspace'.tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: text.labelSmall?.copyWith(
                            color: selectedIndex == _profileTabIndex
                                ? scheme.onSecondaryContainer
                                : scheme.onSurfaceVariant,
                            fontWeight: selectedIndex == _profileTabIndex
                                ? FontWeight.w600
                                : FontWeight.w500,
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
              _WebsocketStatusDot(state: websocketState),
              const SizedBox(height: 4),
              const NotificationBellButton(),
              const SizedBox(height: 4),
              _RailIconButton(
                tooltip: 'profile'.tr(),
                selected: selectedIndex == _profileTabIndex,
                onPressed: () => onSelected(_profileTabIndex),
                child: _RailProfileAvatar(
                  profile: profile,
                  selected: selectedIndex == _profileTabIndex,
                ),
              ),
              const SizedBox(height: 4),
              _RailIconButton(
                tooltip: 'settings'.tr(),
                selected: selectedIndex == _settingsTabIndex,
                onPressed: () => onSelected(_settingsTabIndex),
                child: Icon(
                  Symbols.settings,
                  fill: selectedIndex == _settingsTabIndex ? 1 : 0,
                  color: selectedIndex == _settingsTabIndex
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        destinations: [
          NavigationRailDestination(
            icon: const Icon(Symbols.home),
            selectedIcon: const Icon(Symbols.home, fill: 1),
            label: Text('home'.tr()),
          ),
          NavigationRailDestination(
            icon: const Icon(Symbols.view_kanban),
            selectedIcon: const Icon(Symbols.view_kanban, fill: 1),
            label: Text('boards'.tr()),
          ),
          NavigationRailDestination(
            icon: const Icon(Symbols.folder),
            selectedIcon: const Icon(Symbols.folder, fill: 1),
            label: Text('files'.tr()),
          ),
          const NavigationRailDestination(
            icon: Icon(Symbols.sync),
            selectedIcon: Icon(Symbols.sync, fill: 1),
            label: Text('Flywheel'),
          ),
          NavigationRailDestination(
            icon: const Icon(Symbols.mail),
            selectedIcon: const Icon(Symbols.mail, fill: 1),
            label: Text('mail'.tr()),
          ),
        ],
      ),
    );
  }
}

class _WebsocketStatusDot extends ConsumerWidget {
  const _WebsocketStatusDot({required this.state});

  final WebSocketConnectionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final (color, label) = switch (state) {
      WebSocketConnectionState.connected => (
        const Color(0xFF34C759),
        'Live · connected',
      ),
      WebSocketConnectionState.connecting => (
        scheme.tertiary,
        'Live · connecting…',
      ),
      WebSocketConnectionState.serverDown => (
        scheme.error,
        'Live · server unavailable (tap to retry)',
      ),
      WebSocketConnectionState.error => (
        scheme.error,
        'Live · error (tap to retry)',
      ),
      WebSocketConnectionState.disconnected => (
        scheme.outline,
        'Live · offline (tap to reconnect)',
      ),
    };

    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () =>
              ref.read(websocketStateProvider.notifier).manualReconnect(),
          child: SizedBox(
            width: 48,
            height: 28,
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: state == WebSocketConnectionState.connected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.45),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailIconButton extends StatelessWidget {
  const _RailIconButton({
    required this.tooltip,
    required this.selected,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
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

class _RailProfileAvatar extends StatelessWidget {
  const _RailProfileAvatar({required this.profile, this.selected = false});

  final AsyncValue<SnAccount?> profile;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final user = profile.value;
    final initials = _initials(user?.solWattDisplayName ?? '');
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 14,
      backgroundColor: selected
          ? scheme.primary
          : scheme.surfaceContainerHighest,
      foregroundColor: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
      foregroundImage: user?.solWattAvatarUrl == null
          ? null
          : NetworkImage(user!.solWattAvatarUrl!),
      child: user == null
          ? Icon(Symbols.person, size: 18, fill: selected ? 1 : 0)
          : Text(
              initials,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
    );
  }
}

@RoutePage()
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    final boards = ref.watch(broadsProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return PageScaffold(
      title: workspace?.name ?? 'home'.tr(),
      subtitle: workspace?.description?.isNotEmpty == true
          ? workspace!.description!
          : 'activeWorkspace'.tr(),
      actions: [
        const NotificationBellButton(),
        FilledButton.tonalIcon(
          onPressed: () =>
              AutoTabsRouter.of(context).setActiveIndex(_profileTabIndex),
          icon: const Icon(Symbols.swap_horiz, size: 18),
          label: Text('switch'.tr()),
        ),
      ],
      child: ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconBadge(
                        icon: Symbols.view_kanban,
                        selected: true,
                        size: 44,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('boards'.tr(), style: text.titleMedium),
                            const SizedBox(height: 2),
                            boards.when(
                              loading: () => Text(
                                'loading'.tr(),
                                style: text.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              error: (error, _) => Text(
                                error.toString(),
                                style: text.bodyMedium?.copyWith(
                                  color: scheme.error,
                                ),
                              ),
                              data: (items) => Text(
                                items.isEmpty
                                    ? 'noBoardsYet'.tr()
                                    : '${items.length} ${'boards'.tr()}',
                                style: text.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            AutoTabsRouter.of(context).setActiveIndex(1),
                        icon: const Icon(Symbols.view_kanban, size: 18),
                        label: Text('openBoards'.tr()),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            AutoTabsRouter.of(context).setActiveIndex(2),
                        icon: const Icon(Symbols.folder, size: 18),
                        label: Text('workspaceFiles'.tr()),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => AutoTabsRouter.of(
                          context,
                        ).setActiveIndex(_profileTabIndex),
                        icon: const Icon(Symbols.workspaces, size: 18),
                        label: Text('manageWorkspaces'.tr()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (boards case AsyncData(:final value) when value.isNotEmpty) ...[
            const SizedBox(height: 20),
            SectionHeader(
              title: 'recentBoards'.tr(),
              trailing: TextButton(
                onPressed: () => AutoTabsRouter.of(context).setActiveIndex(1),
                child: Text('viewAll'.tr()),
              ),
            ),
            for (final board in value.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: const IconBadge(icon: Symbols.view_kanban),
                    title: Text(board.name),
                    subtitle: board.description?.isNotEmpty == true
                        ? Text(
                            board.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: Icon(
                      Symbols.chevron_right,
                      color: scheme.onSurfaceVariant,
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TaskBoardPage(
                          broadId: board.id,
                          broadName: board.name,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
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
          ref.invalidate(bundledProOverviewProvider);
          ref.invalidate(workspacesProvider);
        },
        icon: const Icon(Symbols.refresh),
      ),
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
          const SizedBox(height: 16),
          const _BundledProProfileCard(),
          const SizedBox(height: 24),
          SectionHeader(
            title: 'yourWorkspaces'.tr(),
            trailing: FilledButton.tonalIcon(
              onPressed: () => createWorkspaceAction(context, ref),
              icon: const Icon(Symbols.add, size: 18),
              label: Text('new'.tr()),
            ),
          ),
          Expanded(
            child: WorkspaceList(
              manageActions: true,
              onActivate: (workspace) async {
                await activateWorkspaceAction(ref, workspace);
              },
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                await clearSelectedWorkspace(ref.read(secureStorageProvider));
                invalidateWorkspaceScope(ref);
                if (!context.mounted) return;
                context.router.replaceAll([const PageRouteInfo(gateRouteName)]);
              },
              icon: const Icon(Symbols.logout, size: 18),
              label: Text('leaveWorkspace'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}

class _BundledProProfileCard extends ConsumerWidget {
  const _BundledProProfileCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(bundledProOverviewProvider);
    final profile = ref.watch(solWattProfileProvider).value;
    final scheme = Theme.of(context).colorScheme;

    return overview.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(
            height: 48,
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ),
      ),
      error: (error, _) => Card(
        child: ListTile(
          leading: Icon(Symbols.error, color: scheme.error),
          title: Text('bundledPro'.tr()),
          subtitle: Text(wattApiErrorMessage(error)),
          trailing: IconButton(
            tooltip: 'retry'.tr(),
            onPressed: () => ref.invalidate(bundledProOverviewProvider),
            icon: const Icon(Symbols.refresh),
          ),
        ),
      ),
      data: (data) {
        if (data == null) return const SizedBox.shrink();
        final assigned = data.assignedWorkspace;
        final eligible = data.eligible;
        final caption = !eligible
            ? 'requiresStellarSupernova'.tr(
                namedArgs: {
                  'perkLevel': bundledProRequiredPerkLevel.toString(),
                  'perkTierName': profile?.perkTierName ?? 'Twinkle',
                  'level': data.perkLevel.toString(),
                },
              )
            : assigned != null
            ? 'assignedToWorkspace'.tr(namedArgs: {'name': assigned.name})
            : data.isAssigned
            ? 'assignedElsewhere'.tr()
            : 'notAssigned'.tr();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BundledSeatQuotaBar(
                  usedSeats: data.usedSeats,
                  totalSeats: data.totalSeats,
                  caption: caption,
                  locked: !eligible,
                ),
                if (eligible && assigned != null) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () =>
                          showWorkspaceQuota(context, ref, assigned),
                      child: Text('manage'.tr()),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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
