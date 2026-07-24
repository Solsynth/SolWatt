import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';
import 'package:window_manager/window_manager.dart';

import 'app_logging.dart';
import 'boards/boards_screen.dart';
import 'gate/gate_page.dart';
import 'network.dart';
import 'theme.dart';
import 'ui/page_scaffold.dart';
import 'workspaces/workspace_actions.dart';

part 'main.gr.dart';

final globalOverlay = GlobalKey<OverlayState>();

/// Matches the generated [GateRoute] name for navigation outside typed routes.
const gateRouteName = 'GateRoute';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  runApp(ProviderScope(child: SolWattApp()));
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
      builder: (context, child) => Overlay(
        key: globalOverlay,
        initialEntries: [
          OverlayEntry(
            builder: (_) => DesktopWindowFrame(
              isDesktopPlatform: DesktopWindowFrame.isPlatformDesktop,
              title: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('SolWatt'),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.router.replaceAll([
                    const PageRouteInfo(gateRouteName),
                  ]),
                  child: const Text('Back to sign in'),
                ),
              ],
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
  const _NavigationShell({
    required this.selectedIndex,
    required this.onSelected,
    required this.child,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    final wide = isWideScreen(context);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  _DesktopNavigation(
                    selectedIndex: selectedIndex,
                    onSelected: onSelected,
                    workspaceName: workspace?.name,
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                      ),
                      child: ColoredBox(
                        color: Theme.of(context).colorScheme.surface,
                        child: child,
                      ),
                    ),
                  ),
                ],
              )
            : child,
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              height: 56,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelected,
              destinations: [
                for (final destination in _destinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.icon, fill: 1),
                    label: destination.label,
                  ),
                const NavigationDestination(
                  icon: Icon(Symbols.person),
                  selectedIcon: Icon(Symbols.person, fill: 1),
                  label: 'Profile',
                ),
                const NavigationDestination(
                  icon: Icon(Symbols.settings),
                  selectedIcon: Icon(Symbols.settings, fill: 1),
                  label: 'Settings',
                ),
              ],
            ),
    );
  }
}

const _destinations = [
  _Destination('Home', Symbols.home),
  _Destination('Boards', Symbols.view_kanban),
];

class _DesktopNavigation extends ConsumerWidget {
  const _DesktopNavigation({
    required this.selectedIndex,
    required this.onSelected,
    this.workspaceName,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String? workspaceName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userInfoProvider);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 88,
      child: NavigationRail(
        backgroundColor: Colors.transparent,
        selectedIndex: selectedIndex < _destinations.length
            ? selectedIndex
            : null,
        onDestinationSelected: onSelected,
        labelType: NavigationRailLabelType.all,
        leading: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Tooltip(
            message: workspaceName ?? 'Workspace',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onSelected(2),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  children: [
                    Icon(Symbols.workspaces, size: 22, color: scheme.primary),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 64,
                      child: Text(
                        workspaceName ?? 'Workspace',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        trailingAtBottom: true,
        trailing: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Profile',
                onPressed: () => onSelected(2),
                icon: _RailProfileAvatar(profile: profile),
                color: selectedIndex == 2 ? scheme.primary : null,
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () => onSelected(3),
                icon: Icon(Symbols.settings, fill: selectedIndex == 3 ? 1 : 0),
                color: selectedIndex == 3 ? scheme.primary : null,
              ),
            ],
          ),
        ),
        destinations: [
          for (final destination in _destinations)
            NavigationRailDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.icon, fill: 1),
              label: Text(destination.label),
            ),
        ],
      ),
    );
  }
}

class _RailProfileAvatar extends StatelessWidget {
  const _RailProfileAvatar({required this.profile});

  final AsyncValue<SnAccount?> profile;

  @override
  Widget build(BuildContext context) {
    final user = profile.value;
    final initials = _initials(user?.solWattDisplayName ?? '');
    return CircleAvatar(
      radius: 14,
      foregroundImage: user?.solWattAvatarUrl == null
          ? null
          : NetworkImage(user!.solWattAvatarUrl!),
      child: user == null
          ? const Icon(Symbols.person, size: 18)
          : Text(initials, style: const TextStyle(fontSize: 11)),
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

    return PageScaffold(
      title: workspace?.name ?? 'Home',
      subtitle: workspace?.description?.isNotEmpty == true
          ? workspace!.description!
          : 'Active workspace',
      action: TextButton.icon(
        onPressed: () => AutoTabsRouter.of(context).setActiveIndex(2),
        icon: const Icon(Symbols.swap_horiz, size: 18),
        label: const Text('Switch'),
      ),
      child: ListView(
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Boards',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  boards.when(
                    loading: () => const LinearProgressIndicator(minHeight: 2),
                    error: (error, _) => Text(
                      error.toString(),
                      style: TextStyle(color: scheme.error),
                    ),
                    data: (items) => Text(
                      items.isEmpty
                          ? 'No boards yet. Create one from the Boards tab.'
                          : '${items.length} board${items.length == 1 ? '' : 's'} in this workspace.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            AutoTabsRouter.of(context).setActiveIndex(1),
                        icon: const Icon(Symbols.view_kanban, size: 18),
                        label: const Text('Open boards'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            AutoTabsRouter.of(context).setActiveIndex(2),
                        icon: const Icon(Symbols.workspaces, size: 18),
                        label: const Text('Manage workspaces'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
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

    return PageScaffold(
      title: 'Settings',
      subtitle: 'Account and connection',
      child: ListView(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              session.value == null ? Symbols.lock : Symbols.verified_user,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(
              session.value == null
                  ? 'Not signed in'
                  : 'Connected to Solar Network',
            ),
            subtitle: Text(
              user == null
                  ? 'OAuth authorization uses the Solar Network identity service.'
                  : '@${user.name}',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () async {
                await ref.read(authenticatorProvider).clear();
                await clearSelectedWorkspace(ref.read(secureStorageProvider));
                invalidateSessionScope(ref);
                if (!context.mounted) return;
                context.router.replaceAll([const PageRouteInfo(gateRouteName)]);
              },
              icon: const Icon(Symbols.logout),
              label: const Text('Sign out'),
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
    final selected = ref.watch(selectedWorkspaceProvider).value;

    return PageScaffold(
      title: 'Profile',
      subtitle: 'Account and workspaces',
      action: IconButton(
        tooltip: 'Refresh',
        onPressed: () {
          ref.invalidate(userInfoProvider);
          ref.invalidate(workspacesProvider);
        },
        icon: const Icon(Symbols.refresh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          profile.when(
            loading: () => const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              title: Text('Loading profile…'),
            ),
            error: (_, _) => const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Icon(Symbols.person)),
              title: Text('Solar Network account'),
            ),
            data: (user) {
              if (user == null) return const SizedBox.shrink();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 26,
                  foregroundImage: user.solWattAvatarUrl == null
                      ? null
                      : NetworkImage(user.solWattAvatarUrl!),
                  child: Text(_initials(user.solWattDisplayName)),
                ),
                title: Text(user.solWattDisplayName),
                subtitle: Text('@${user.name}'),
              );
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Workspaces',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              FilledButton.icon(
                onPressed: () => createWorkspaceAction(context, ref),
                icon: const Icon(Symbols.add, size: 18),
                label: const Text('New'),
              ),
            ],
          ),
          if (selected != null) ...[
            const SizedBox(height: 8),
            Text(
              'Active: ${selected.name}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: WorkspaceList(
              manageActions: true,
              onActivate: (workspace) async {
                await activateWorkspaceAction(ref, workspace);
              },
            ),
          ),
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
              label: const Text('Leave workspace'),
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

class _Destination {
  const _Destination(this.label, this.icon);
  final String label;
  final IconData icon;
}
