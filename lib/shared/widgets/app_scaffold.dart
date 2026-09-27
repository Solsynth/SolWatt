import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Shared page scaffold: reserves the app-bar height (extendBodyBehindAppBar),
/// keeps the body scrollable under the app bar, and pops on Escape.
///
/// Ported from Solian's AppScaffold with the AppBackground wrapper removed —
/// when [isNoBackground] is false the body is wrapped in a plain Material
/// surface instead of the background-image layer.
class AppScaffold extends HookConsumerWidget {
  final Widget? body;
  final PreferredSizeWidget? bottomNavigationBar;
  final PreferredSizeWidget? bottomSheet;
  final Drawer? drawer;
  final Widget? endDrawer;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? appBar;
  final DrawerCallback? onDrawerChanged;
  final DrawerCallback? onEndDrawerChanged;
  final bool isNoBackground;
  final bool extendBody;

  const AppScaffold({
    super.key,
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.bottomSheet,
    this.drawer,
    this.endDrawer,
    this.onDrawerChanged,
    this.onEndDrawerChanged,
    this.isNoBackground = false,
    this.extendBody = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appBarHeight = appBar?.preferredSize.height ?? 0;
    final safeTop = MediaQuery.of(context).padding.top;
    final keyboardFocusNode = useFocusNode();
    final topReservedHeight = appBar != null ? appBarHeight + safeTop : 0.0;

    // Request focus to capture keyboard events
    useEffect(() {
      keyboardFocusNode.requestFocus();
      return null;
    }, []);

    final builtWidget = Focus(
      focusNode: keyboardFocusNode,
      onKeyEvent: (node, event) {
        // Check for escape key press
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          final navigator = Navigator.of(context);
          // Only pop if there are pages to pop
          if (navigator.canPop()) {
            navigator.pop();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        extendBody: extendBody,
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                height: topReservedHeight,
              ),
            ),
            if (body != null) Expanded(child: body!),
          ],
        ),
        appBar: appBar,
        bottomNavigationBar: bottomNavigationBar,
        bottomSheet: bottomSheet,
        drawer: drawer,
        endDrawer: endDrawer,
        floatingActionButton: floatingActionButton,
        onDrawerChanged: onDrawerChanged,
        onEndDrawerChanged: onEndDrawerChanged,
      ),
    );

    return isNoBackground
        ? builtWidget
        : Material(
            color: Theme.of(context).colorScheme.surface,
            child: builtWidget,
          );
  }
}
