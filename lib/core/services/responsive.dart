export 'package:island_ui_foundation/island_ui_foundation.dart'
    show isWideScreen, isWiderScreen, isWidestScreen, kWideScreenWidth;

import 'package:flutter/widgets.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart'
    show kWideScreenWidth;

/// Compact-screen helpers used by the ported drive UI.
extension ResponsiveLayoutContext on BuildContext {
  bool get isCompactScreen => MediaQuery.sizeOf(this).width <= kWideScreenWidth;
}
