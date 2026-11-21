import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:window_manager/window_manager.dart';

import 'package:solwatt/theme.dart';

/// Desktop window frame painted with the app's own chrome.
///
/// The frame is a flat band in the same tone as the shell's navigation rail,
/// so the two read as one continuous spine down the window's edge. Flutter
/// still hides the native title bar (see `main`), so the whole frame is ours
/// to paint.
///
/// macOS keeps the system traffic lights and their 32px band; Windows and
/// Linux get the title and the window buttons on the right. On every other
/// platform the frame is a passthrough.
///
/// The frame deliberately does not wrap its title bar in a `SafeArea`: the
/// title bar is the top of the window, and on macOS the traffic lights already
/// own that strip. Reserving the system inset here would push the page's app
/// bar down and leave a band of bare background above it, when the app bar is
/// supposed to paint that strip itself.
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
      // Match the shell's navigation rail so the titlebar and the rail share
      // one surface tone instead of banding against each other.
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
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
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: SolSpace.md),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DefaultTextStyle(
                    style: Theme.of(context).textTheme.labelLarge!.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    child: widget.title ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
          _WindowButton(
            icon: Symbols.remove,
            tooltip: 'minimize'.tr(),
            onPressed: () => windowManager.minimize(),
          ),
          _WindowButton(
            icon: _isMaximized ? Symbols.fullscreen_exit : Symbols.fullscreen,
            tooltip: _isMaximized ? 'restore'.tr() : 'maximize'.tr(),
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
