import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:window_manager/window_manager.dart';

import 'package:solwatt/shared/widgets/pill_surface.dart';
import 'package:solwatt/theme.dart';

/// Desktop window frame with the new island chrome.
///
/// Replaces the flat band `island_ui_foundation` renders: the title and the
/// window controls sit in the app's glass material, so the bar belongs to the
/// same family as the pill headers and the tab bar. Flutter still hides the
/// native title bar (see `main`), so the whole frame is ours to paint.
///
/// macOS keeps the system traffic lights and their 32px band; Windows and
/// Linux get the glass capsule and the window buttons on the right. On every
/// other platform the frame is a passthrough.
class AppWindowFrame extends StatefulWidget {
  final Widget child;
  final Widget? title;
  final bool isDesktopPlatform;

  const AppWindowFrame({
    super.key,
    required this.child,
    this.title,
    this.isDesktopPlatform = false,
  });

  static bool get isPlatformDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  @override
  State<AppWindowFrame> createState() => _AppWindowFrameState();
}

class _AppWindowFrameState extends State<AppWindowFrame> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isDesktopPlatform) return;
    windowManager.addListener(this);
    windowManager.isMaximized().then((value) {
      if (mounted) setState(() => _isMaximized = value);
    });
  }

  @override
  void dispose() {
    if (widget.isDesktopPlatform) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isDesktopPlatform) return widget.child;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          _buildTitleBar(context),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    if (Platform.isMacOS) {
      return DragToMoveArea(
        child: SizedBox(
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [?widget.title],
          ),
        ),
      );
    }

    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SolSpace.sm,
          SolSpace.sm,
          SolSpace.xs,
          0,
        ),
        child: Row(
          children: [
            Expanded(
              child: DragToMoveArea(
                child: SizedBox.expand(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: PillSurface(
                      t: 1,
                      margin: EdgeInsets.zero,
                      radius: SolRadius.pillRadius,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: SolSpace.lg,
                      ),
                      child: SizedBox(
                        height: 36,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: DefaultTextStyle(
                            style: Theme.of(context).textTheme.labelLarge!
                                .copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                            child: widget.title ?? const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: SolSpace.xs),
            _WindowButton(
              icon: Symbols.remove,
              tooltip: 'Minimize',
              onPressed: () => windowManager.minimize(),
            ),
            _WindowButton(
              icon: _isMaximized ? Symbols.fullscreen_exit : Symbols.fullscreen,
              tooltip: _isMaximized ? 'Restore' : 'Maximize',
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            ),
            _WindowButton(
              icon: Symbols.close,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        color: scheme.onSurfaceVariant,
        style: IconButton.styleFrom(
          minimumSize: const Size(40, 40),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SolRadius.md),
          ),
        ),
      ),
    );
  }
}
