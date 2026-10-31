import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:solwatt/shared/widgets/pill_surface.dart';
import 'package:solwatt/theme.dart';

/// Scroll distance over which a pill header finishes fading its surface in.
///
/// Tied to roughly one header height: by the time the content has meaningfully
/// slid under the bar, the pill is fully surfaced and can carry its controls.
const double kPillFadeDistance = 96.0;

/// Total height of a pill bar, excluding the status-bar inset.
///
/// A bar reserves `statusTop + kPillAppBarHeight`: the capsule's top margin
/// plus [kPillBarContentHeight].
const double kPillAppBarHeight = kPillBarContentHeight + SolSpace.md;

/// Feeds a pill's fade ramp (0..1) from a scroll notification.
///
/// The ramp is read off the scroll offset itself so the surface tracks the
/// drag instead of snapping at the first pixel. Only the outermost scrollable
/// counts: inside a [NestedScrollView] the inner list reports `depth` 1 and
/// restarts at offset 0 whenever the header re-expands, which would slam the
/// pill back to invisible while content is still under it.
///
/// Returns false so the notification keeps bubbling to other listeners.
bool updatePillFade(
  ScrollNotification notification,
  ValueNotifier<double> fade, {
  double threshold = 0,
}) {
  final metrics = notification.metrics;
  if (notification.depth != 0 || metrics.axis != Axis.vertical) return false;
  final ramp = ((metrics.pixels - threshold) / kPillFadeDistance).clamp(
    0.0,
    1.0,
  );
  if (fade.value != ramp) fade.value = ramp;
  return false;
}

/// [PillSurface] for a header: the capsule sits [SolSpace.md] in from each
/// side and below the status bar, and carries [SolSpace.lg] of inner inset —
/// one step wider than the side gutter, so the first control clears the end
/// cap's curve instead of crowding it.
///
/// [loading] is forwarded to the [PillSurface], which laps the capsule's own
/// outline as a spinner while it is set.
class PillBarSurface extends StatelessWidget {
  /// Fade position, 0..1. Drives the glass and shadow together.
  final double t;

  /// Status-bar inset, reserved inside the bar's own box.
  final double statusTop;

  /// Lap the capsule's outline as a spinner.
  final bool loading;

  final Widget child;

  const PillBarSurface({
    super.key,
    required this.t,
    required this.statusTop,
    required this.child,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return PillSurface(
      t: t,
      loading: loading,
      margin: EdgeInsets.fromLTRB(
        kPillSideGutter,
        statusTop + kPillSideGutter,
        kPillSideGutter,
        0,
      ),
      radius: SolRadius.pillRadius,
      contentPadding: const EdgeInsets.symmetric(horizontal: SolSpace.lg),
      // The capsule is always exactly `kPillBarContentHeight` tall so every
      // pill lands on the same band and a child that fills its constraints
      // cannot stretch the glass over the content the page reserved.
      child: SizedBox(height: kPillBarContentHeight, child: child),
    );
  }
}

/// The header used by every page: a floating glass capsule carrying a leading
/// control, the page title and its actions, with an optional strip beneath it
/// (a tab bar or a selection bar).
///
/// Unlike a header that fades in when content slides under it, this bar is
/// always surfaced: the pages using it reserve the band in their scaffold, so
/// nothing ever runs beneath the capsule and hiding its fill would leave bare
/// controls floating on the page.
class PillPageBar extends StatelessWidget implements PreferredSizeWidget {
  /// Status-bar inset, measured by the caller so the bar's height matches.
  final double statusTop;

  /// Leading control: back, drawer, or nothing.
  final Widget? leading;

  /// The page title. A [Text] gets the bar's title style applied.
  final Widget title;

  final List<Widget> actions;

  /// Optional strip below the capsule (a [TabBar], a selection bar).
  final PreferredSizeWidget? bottom;

  /// Surface fade, 0..1. Null keeps the capsule surfaced.
  final ValueListenable<double>? fade;

  /// Lap the capsule's outline as a spinner.
  final bool loading;

  const PillPageBar({
    super.key,
    required this.statusTop,
    required this.title,
    this.leading,
    this.actions = const [],
    this.bottom,
    this.fade,
    this.loading = false,
  });

  // The status-bar inset is *not* part of this height: a `Scaffold` adds
  // `MediaQuery.padding.top` on top of an app bar's preferred size, and
  // [PillBarSurface] spends exactly that inset above the capsule.
  @override
  Size get preferredSize => Size.fromHeight(
    kPillAppBarHeight + (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    final fade = this.fade;
    Widget header(double t) => PillBarSurface(
      t: t,
      statusTop: statusTop,
      loading: loading,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: SolSpace.sm)],
          Expanded(child: title),
          for (final action in actions) ...[
            const SizedBox(width: SolSpace.xs),
            action,
          ],
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (fade == null)
          header(1)
        else
          ValueListenableBuilder<double>(
            valueListenable: fade,
            builder: (context, t, _) => header(t),
          ),
        if (bottom case final PreferredSizeWidget bottom) bottom,
      ],
    );
  }
}

/// A header with a single arbitrary row of controls, for pages that own their
/// title chrome (the file browser's search field).
class PillAppBar extends StatelessWidget implements PreferredSizeWidget {
  final double statusTop;
  final Widget child;
  final bool loading;
  final ValueListenable<double>? fade;

  const PillAppBar({
    super.key,
    required this.statusTop,
    required this.child,
    this.loading = false,
    this.fade,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kPillAppBarHeight);

  @override
  Widget build(BuildContext context) {
    Widget surface(double t) => PillBarSurface(
      t: t,
      statusTop: statusTop,
      loading: loading,
      child: Material(color: Colors.transparent, child: child),
    );

    final fade = this.fade;
    if (fade == null) return surface(1);
    return ValueListenableBuilder<double>(
      valueListenable: fade,
      builder: (context, t, _) => surface(t),
    );
  }
}
