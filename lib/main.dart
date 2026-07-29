import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
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
          OverlayEntry(builder: (_) => const _WebSocketIndicator()),
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
        AutoRoute(page: BoardsRoute.page, initial: true),
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
    final mobileSelectedIndex = switch (selectedIndex) {
      0 => 1,
      1 => 2,
      3 => 3,
      _settingsTabIndex => 4,
      _ => 0,
    };

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: scheme.surfaceContainer,
      drawer: wide
          ? null
          : Drawer(
              child: _MobileNavigationDrawer(
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
              selectedIndex: mobileSelectedIndex,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
              onDestinationSelected: (index) {
                if (index == 0) {
                  _scaffoldKey.currentState?.openDrawer();
                  return;
                }
                onSelected(switch (index) {
                  1 => 0,
                  2 => 1,
                  3 => 3,
                  4 => _settingsTabIndex,
                  _ => selectedIndex,
                });
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(Symbols.menu),
                  label: MaterialLocalizations.of(context).openAppDrawerTooltip,
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
                NavigationDestination(
                  icon: const Icon(Symbols.mail),
                  selectedIcon: const Icon(Symbols.mail, fill: 1),
                  label: 'mail'.tr(),
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

class _MobileNavigationDrawer extends StatelessWidget {
  const _MobileNavigationDrawer({
    required this.workspace,
    required this.selectedIndex,
    required this.onSelected,
  });

  final Workspace? workspace;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const drawerRoutes = [0, 1, 2, 3, _profileTabIndex, _settingsTabIndex];
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
                        borderRadius: BorderRadius.circular(8),
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
            icon: const Icon(Symbols.view_kanban),
            selectedIcon: const Icon(Symbols.view_kanban, fill: 1),
            label: Text('boards'.tr()),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Symbols.folder),
            selectedIcon: const Icon(Symbols.folder, fill: 1),
            label: Text('files'.tr()),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Symbols.sync),
            selectedIcon: Icon(Symbols.sync, fill: 1),
            label: Text('Flywheel'),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Symbols.mail),
            selectedIcon: const Icon(Symbols.mail, fill: 1),
            label: Text('mail'.tr()),
          ),
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

const _profileTabIndex = 4;
const _settingsTabIndex = 5;

class _DesktopNavigation extends ConsumerWidget {
  const _DesktopNavigation({
    required this.selectedIndex,
    required this.onSelected,
    this.workspace,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Workspace? workspace;

  String? get workspaceName => workspace?.name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SizedBox(
      width: 88,
      child: NavigationRail(
        backgroundColor: Colors.transparent,
        selectedIndex: selectedIndex < _profileTabIndex ? selectedIndex : null,
        onDestinationSelected: onSelected,
        labelType: NavigationRailLabelType.all,
        groupAlignment: 0,
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
                        CloudFileAvatar(
                          file: workspace?.picture,
                          workspaceId: workspace?.id,
                          fallbackIcon: Symbols.workspaces,
                          size: 22,
                          selected: selectedIndex == _profileTabIndex,
                          borderRadius: BorderRadius.circular(6),
                          assumeImage: true,
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
              const NotificationBellButton(),
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
          const _PersonalWorkspacePlanCard(),
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

class _PersonalWorkspacePlanCard extends ConsumerWidget {
  const _PersonalWorkspacePlanCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaces = ref.watch(workspacesProvider);
    final profile = ref.watch(solWattProfileProvider).value;
    final scheme = Theme.of(context).colorScheme;

    return workspaces.when(
      loading: () => Card(child: ListTile(title: Text('loading'.tr()))),
      error: (error, _) => Card(
        child: ListTile(
          leading: Icon(Symbols.error, color: scheme.error),
          title: Text('personalWorkspace'.tr()),
          subtitle: Text(wattApiErrorMessage(error)),
        ),
      ),
      data: (items) {
        final personal = items.where((item) => item.isIndividual).firstOrNull;
        final eligible = profile?.canAssignBundledPro ?? false;
        return Card(
          child: ListTile(
            leading: Icon(Symbols.person, color: scheme.primary),
            title: Text('personalWorkspace'.tr()),
            subtitle: Text(
              personal == null
                  ? 'personalWorkspaceProvisioning'.tr()
                  : eligible && personal.isBundled
                  ? 'bundledProAutomatic'.tr(namedArgs: {'name': personal.name})
                  : 'bundledProPersonalEligibility'.tr(),
            ),
            trailing: personal == null
                ? null
                : TextButton(
                    onPressed: () => showWorkspaceQuota(context, ref, personal),
                    child: Text('viewPlan'.tr()),
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
