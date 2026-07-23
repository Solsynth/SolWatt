import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:window_manager/window_manager.dart';

import 'theme.dart';

part 'main.gr.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    return MaterialApp.router(
      title: 'SolWatt',
      debugShowCheckedModeBanner: false,
      theme: createSolWattTheme(Brightness.light),
      darkTheme: createSolWattTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (context, child) => DesktopWindowFrame(
        isDesktopPlatform: DesktopWindowFrame.isPlatformDesktop,
        title: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('SolWatt'),
        ),
        child: child ?? const SizedBox.shrink(),
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
      routes: const [HomeRoute(), SettingsRoute()],
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

const _destinations = [_Destination('Home', Symbols.home)];

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      backgroundColor: Colors.transparent,
      selectedIndex: selectedIndex == 0 ? 0 : null,
      onDestinationSelected: onSelected,
      trailingAtBottom: true,
      trailing: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: IconButton(
          tooltip: 'Settings',
          onPressed: () => onSelected(1),
          icon: const Icon(Symbols.settings),
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

@RoutePage()
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

@RoutePage()
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
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
        AutoRoute(page: SettingsRoute.page),
      ],
    ),
  ];
}

class _Destination {
  const _Destination(this.label, this.icon);
  final String label;
  final IconData icon;
}
