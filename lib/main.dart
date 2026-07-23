import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:window_manager/window_manager.dart';

import 'app_logging.dart';
import 'network.dart';
import 'theme.dart';

part 'main.gr.dart';

final globalOverlay = GlobalKey<OverlayState>();

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

@RoutePage()
class AppShellPage extends StatelessWidget {
  const AppShellPage({super.key});

  @override
  Widget build(BuildContext context) {
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
  }
}

class _NavigationShell extends StatelessWidget {
  const _NavigationShell({
    required this.selectedIndex,
    required this.onSelected,
    required this.child,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
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
      },
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
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userInfoProvider);
    return NavigationRail(
      backgroundColor: Colors.transparent,
      selectedIndex: selectedIndex < _destinations.length
          ? selectedIndex
          : null,
      onDestinationSelected: onSelected,
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
              color: selectedIndex == 2
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            IconButton(
              tooltip: 'Settings',
              onPressed: () => onSelected(3),
              icon: Icon(Symbols.settings, fill: selectedIndex == 3 ? 1 : 0),
              color: selectedIndex == 3
                  ? Theme.of(context).colorScheme.primary
                  : null,
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
    );
  }
}

class _RailProfileAvatar extends StatelessWidget {
  const _RailProfileAvatar({required this.profile});

  final AsyncValue<OAuthUser?> profile;

  @override
  Widget build(BuildContext context) {
    final user = profile.value;
    final initials =
        user?.displayName
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .take(2)
            .map((part) => part[0])
            .join()
            .toUpperCase() ??
        '';
    return CircleAvatar(
      radius: 14,
      foregroundImage: user?.avatarUrl == null
          ? null
          : NetworkImage(user!.avatarUrl!),
      child: user == null
          ? const Icon(Symbols.person, size: 18)
          : Text(
              initials.isEmpty ? '?' : initials,
              style: const TextStyle(fontSize: 11),
            ),
    );
  }
}

@RoutePage()
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    return session.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _AuthenticationPane(error: error.toString()),
      data: (value) => value == null
          ? const _AuthenticationPane()
          : _WorkspacePane(session: value),
    );
  }
}

@RoutePage()
class BoardsPage extends ConsumerWidget {
  const BoardsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    if (!session.hasValue || session.value == null) {
      return const _AuthenticationPane(
        title: 'Sign in to view boards',
        description: 'Your Ideask boards will appear here after authorization.',
      );
    }
    final broads = ref.watch(broadsProvider);
    return _PageScaffold(
      title: 'Boards',
      subtitle: 'Ideask project boards available to your account',
      child: broads.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _LoadError(
          message: error.toString(),
          onRetry: () => ref.invalidate(broadsProvider),
        ),
        data: (items) => items.isEmpty
            ? const Center(child: Text('No boards found.'))
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final board = items[index];
                  return ListTile(
                    leading: const Icon(Symbols.view_kanban),
                    title: Text(board.name),
                    subtitle: board.description == null
                        ? null
                        : Text(board.description!),
                  );
                },
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
    return _PageScaffold(
      title: 'Settings',
      subtitle: 'Solar Network connection',
      child: ListView(
        children: [
          ListTile(
            leading: Icon(
              session.value == null ? Symbols.lock : Symbols.verified_user,
            ),
            title: Text(
              session.value == null
                  ? 'Not signed in'
                  : 'Connected to Solar Network',
            ),
            subtitle: const Text(
              'OAuth authorization uses the Solar Network identity service.',
            ),
          ),
          if (session.value == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: () => _signIn(ref, context),
                icon: const Icon(Symbols.login),
                label: const Text('Sign in'),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(authenticatorProvider).clear();
                  ref.invalidate(authSessionProvider);
                  ref.invalidate(userInfoProvider);
                  ref.invalidate(workspacesProvider);
                  ref.invalidate(broadsProvider);
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
    final session = ref.watch(authSessionProvider);
    if (!session.hasValue || session.value == null) {
      return const _AuthenticationPane(
        title: 'Sign in to view your profile',
        description: 'Your Solar Network account details will appear here.',
      );
    }
    return _PageScaffold(
      title: 'Profile',
      subtitle: 'Your Solar Network account',
      action: IconButton(
        tooltip: 'Refresh profile',
        onPressed: () => ref.invalidate(userInfoProvider),
        icon: const Icon(Symbols.refresh),
      ),
      child: const _WorkspaceManager(),
    );
  }
}

@AutoRouterConfig(replaceInRouteName: 'Page,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      page: AppShellRoute.page,
      initial: true,
      children: [
        AutoRoute(page: HomeRoute.page, initial: true),
        AutoRoute(page: BoardsRoute.page),
        AutoRoute(page: ProfileRoute.page),
        AutoRoute(page: SettingsRoute.page),
      ],
    ),
  ];
}

class _WorkspacePane extends ConsumerWidget {
  const _WorkspacePane({required this.session});
  final OAuthSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaces = ref.watch(workspacesProvider);
    return _PageScaffold(
      title: 'Your workspaces',
      subtitle: 'Connected to Solar Network',
      action: IconButton(
        tooltip: 'Refresh',
        icon: const Icon(Symbols.refresh),
        onPressed: () => ref.invalidate(workspacesProvider),
      ),
      child: workspaces.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _LoadError(
          message: error.toString(),
          onRetry: () => ref.invalidate(workspacesProvider),
        ),
        data: (items) => items.isEmpty
            ? const Center(child: Text('No workspaces found.'))
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final workspace = items[index];
                  return ListTile(
                    leading: const Icon(Symbols.workspaces),
                    title: Text(workspace.name),
                    subtitle: Text(workspace.slug),
                  );
                },
              ),
      ),
    );
  }
}

class _AuthenticationPane extends ConsumerWidget {
  const _AuthenticationPane({
    this.title = 'Connect your Solar Network account',
    this.description =
        'Authorize SolWatt to load your workspaces and Ideask boards.',
    this.error,
  });
  final String title;
  final String description;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Symbols.solar_power,
              size: 44,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _signIn(ref, context),
              icon: const Icon(Symbols.login),
              label: const Text('Continue with Solar Network'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProfileSection extends ConsumerWidget {
  const _ProfileSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userInfoProvider);
    return profile.when(
      loading: () => const ListTile(
        leading: CircleAvatar(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        title: Text('Loading profile…'),
      ),
      error: (_, _) => const ListTile(
        leading: CircleAvatar(child: Icon(Symbols.person)),
        title: Text('Solar Network account'),
      ),
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        final initials = user.displayName
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .take(2)
            .map((part) => part[0])
            .join()
            .toUpperCase();
        final avatar = user.avatarUrl;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: CircleAvatar(
            radius: 26,
            foregroundImage: avatar == null ? null : NetworkImage(avatar),
            child: Text(initials.isEmpty ? '?' : initials),
          ),
          title: Text(user.displayName),
          subtitle: user.email == null
              ? const Text('Solar Network account')
              : Text(user.email!),
        );
      },
    );
  }
}

class _WorkspaceManager extends ConsumerWidget {
  const _WorkspaceManager();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaces = ref.watch(workspacesProvider);
    return workspaces.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _LoadError(
        message: error.toString(),
        onRetry: () => ref.invalidate(workspacesProvider),
      ),
      data: (items) => ListView(
        children: [
          const _ProfileSection(),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Workspaces',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              FilledButton.icon(
                onPressed: () => _createWorkspace(context, ref),
                icon: const Icon(Symbols.add),
                label: const Text('New workspace'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Text('No workspaces yet.')),
            ),
          for (final workspace in items)
            Card(
              child: ListTile(
                leading: const Icon(Symbols.workspaces),
                title: Text(workspace.name),
                subtitle: Text(
                  workspace.description?.isNotEmpty == true
                      ? '${workspace.slug} · ${workspace.description}'
                      : workspace.slug,
                ),
                trailing: Wrap(
                  spacing: 2,
                  children: [
                    IconButton(
                      tooltip: 'View quotas',
                      onPressed: () => _showQuota(context, ref, workspace),
                      icon: const Icon(Symbols.data_usage),
                    ),
                    IconButton(
                      tooltip: 'Edit workspace',
                      onPressed: () => _editWorkspace(context, ref, workspace),
                      icon: const Icon(Symbols.edit),
                    ),
                    IconButton(
                      tooltip: 'Delete workspace',
                      onPressed: () =>
                          _deleteWorkspace(context, ref, workspace),
                      icon: Icon(
                        Symbols.delete,
                        color: Theme.of(context).colorScheme.error,
                      ),
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

Future<void> _createWorkspace(BuildContext context, WidgetRef ref) async {
  final profile = await ref.read(userInfoProvider.future);
  if (!context.mounted) return;
  final draft = await _showWorkspaceEditor(context, profile: profile);
  if (draft == null) return;
  try {
    await ref
        .read(wattEngineClientProvider)
        .createWorkspace(
          slug: draft.slug,
          name: draft.name,
          description: draft.description,
          type: draft.type,
        );
    ref.invalidate(workspacesProvider);
    showSnackBar('Workspace created.');
  } catch (error) {
    showSnackBar(error.toString());
  }
}

Future<void> _editWorkspace(
  BuildContext context,
  WidgetRef ref,
  Workspace workspace,
) async {
  final draft = await _showWorkspaceEditor(context, workspace: workspace);
  if (draft == null) return;
  try {
    await ref
        .read(wattEngineClientProvider)
        .updateWorkspace(
          slug: workspace.slug,
          name: draft.name,
          description: draft.description,
        );
    ref.invalidate(workspacesProvider);
    showSnackBar('Workspace updated.');
  } catch (error) {
    showSnackBar(error.toString());
  }
}

Future<void> _deleteWorkspace(
  BuildContext context,
  WidgetRef ref,
  Workspace workspace,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete ${workspace.name}?'),
      content: const Text(
        'This permanently deletes the workspace and its data.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await ref.read(wattEngineClientProvider).deleteWorkspace(workspace.slug);
    ref.invalidate(workspacesProvider);
    showSnackBar('Workspace deleted.');
  } catch (error) {
    showSnackBar(error.toString());
  }
}

Future<void> _showQuota(
  BuildContext context,
  WidgetRef ref,
  Workspace workspace,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
    child: FutureBuilder(
      future: ref
          .read(wattEngineClientProvider)
          .getWorkspaceQuota(workspace.slug),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        final quota = snapshot.data!;
        return ListView(
          shrinkWrap: true,
          children: [
            Text(
              '${workspace.name} quotas',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'Plan: ${['Free', 'Pro', 'Enterprise'].elementAtOrNull(quota.plan) ?? quota.plan}',
            ),
            const SizedBox(height: 12),
            for (final entry in quota.limits.entries)
              ListTile(
                title: Text(entry.key.replaceAll('_', ' ')),
                trailing: Text(_formatQuota(entry.value)),
              ),
          ],
        );
      },
    ),
  ),
);

String _formatQuota(dynamic value) {
  if (value is num && value >= 1024 * 1024 * 1024) {
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB';
  }
  return value.toString();
}

class _WorkspaceDraft {
  const _WorkspaceDraft(this.slug, this.name, this.description, this.type);
  final String slug;
  final String name;
  final String? description;
  final int type;
}

Future<_WorkspaceDraft?> _showWorkspaceEditor(
  BuildContext context, {
  Workspace? workspace,
  OAuthUser? profile,
}) {
  final slug = TextEditingController(text: workspace?.slug ?? '');
  final name = TextEditingController(text: workspace?.name ?? '');
  final description = TextEditingController(text: workspace?.description ?? '');
  var type = 0;
  var usePersonalDetails = false;
  return showModalBottomSheet<_WorkspaceDraft>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SheetScaffold(
        titleText: workspace == null ? 'New workspace' : 'Edit workspace',
        heightFactor: 0.72,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (workspace == null) ...[
                TextField(
                  controller: slug,
                  decoration: const InputDecoration(labelText: 'Slug'),
                ),
                const SizedBox(height: 16),
                if (profile?.username?.isNotEmpty == true) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: usePersonalDetails,
                    title: const Text('Use my personal workspace details'),
                    subtitle: Text(
                      'Uses @${profile!.username} and your profile name.',
                    ),
                    onChanged: type == 0
                        ? (selected) => setState(() {
                            usePersonalDetails = selected ?? false;
                            if (usePersonalDetails) {
                              slug.text = profile.username!;
                              name.text = profile.displayName;
                              description.text =
                                  "${profile.displayName}'s personal workspace";
                            }
                          })
                        : null,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 4,
              ),
              if (workspace == null) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: type,
                  decoration: const InputDecoration(
                    labelText: 'Workspace type',
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Individual')),
                    DropdownMenuItem(value: 1, child: Text('Organization')),
                  ],
                  onChanged: (value) => setState(() {
                    type = value ?? 0;
                    if (type != 0) usePersonalDetails = false;
                  }),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _WorkspaceDraft(
                    slug.text.trim(),
                    name.text.trim(),
                    description.text.trim().isEmpty
                        ? null
                        : description.text.trim(),
                    type,
                  ),
                ),
                child: Text(
                  workspace == null ? 'Create workspace' : 'Save changes',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ).whenComplete(() {
    slug.dispose();
    name.dispose();
    description.dispose();
  });
}

class _PageScaffold extends StatelessWidget {
  const _PageScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
  });
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            if (action case final Widget action) action,
          ],
        ),
        const SizedBox(height: 24),
        Expanded(child: child),
      ],
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}

Future<void> _signIn(WidgetRef ref, BuildContext context) async {
  try {
    await ref.read(authenticatorProvider).signIn();
    ref.invalidate(authSessionProvider);
    ref.invalidate(userInfoProvider);
    ref.invalidate(workspacesProvider);
    ref.invalidate(broadsProvider);
  } catch (error) {
    if (!context.mounted) return;
    showSnackBar(error.toString());
  }
}

class _Destination {
  const _Destination(this.label, this.icon);
  final String label;
  final IconData icon;
}
