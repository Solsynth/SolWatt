import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class SolWattFonts {
  static const sans = 'Nunito';
}

/// The application-wide Material theme, following Island's baseline defaults.
ThemeData createSolWattTheme(Brightness brightness) {
  const seedColor = Color(0xffd97706);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    brightness: brightness,
    fontFamily: SolWattFonts.sans,
    iconTheme: IconThemeData(
      fill: 0,
      weight: 400,
      opticalSize: 20,
      color: colorScheme.onSurface,
    ),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
    ),
    cardTheme: CardThemeData(color: colorScheme.surfaceContainer),
    inputDecorationTheme: InputDecorationThemeData(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    // Keep Island's Material 2024 component appearance during the transition.
    // ignore: deprecated_member_use
    progressIndicatorTheme: const ProgressIndicatorThemeData(year2023: false),
    // ignore: deprecated_member_use
    sliderTheme: const SliderThemeData(year2023: false),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}
