import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:material_ui/material_ui.dart' as mui;

abstract final class SolWattFonts {
  static const sans = 'Nunito';
}

/// MD3 shape tokens used across component themes.
abstract final class SolWattShapes {
  static const extraSmall = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(4)),
  );
  static const small = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );
  static const medium = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );
  static const large = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );
  static const extraLarge = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(28)),
  );
  static const full = StadiumBorder();
}

/// The application-wide Material theme, following Island's baseline defaults
/// and Material Design 3 component guidance.
const kSolWattSeedColor = Color(0xffd97706);

/// Selectable accent seed colors for the settings page. The first entry is the
/// app default; tapping the active dot restores it (stores no override).
const kAccentColorOptions = <Color>[
  Color(0xffd97706), // amber (default)
  Color(0xff0ea5e9), // sky
  Color(0xff6366f1), // indigo
  Color(0xff16a34a), // green
  Color(0xffe11d48), // rose
  Color(0xff7c3aed), // violet
  Color(0xff0d9488), // teal
  Color(0xfff43f5e), // crimson
];

ThemeData createSolWattTheme(Brightness brightness, {Color seedColor = kSolWattSeedColor}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  );

  final textTheme = _solWattTextTheme(
    ThemeData(brightness: brightness).textTheme.apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
      fontFamily: SolWattFonts.sans,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    brightness: brightness,
    fontFamily: SolWattFonts.sans,
    textTheme: textTheme,
    scaffoldBackgroundColor: colorScheme.surface,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    splashFactory: InkSparkle.splashFactory,
    iconTheme: IconThemeData(
      fill: 0,
      weight: 400,
      opticalSize: 24,
      color: colorScheme.onSurfaceVariant,
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      surfaceTintColor: colorScheme.surfaceTint,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
      actionsIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
    ),
    cardTheme: CardThemeData(
      color: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: SolWattShapes.medium,
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colorScheme.onSurfaceVariant,
      textColor: colorScheme.onSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: SolWattShapes.medium,
      minVerticalPadding: 10,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      // Loose height so multi-line fields inside scroll views stay finite.
      // Top alignment is handled by [inputPrefixIcon].
      prefixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 0),
      suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 0),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.error, width: 2),
      ),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      floatingLabelStyle: TextStyle(color: colorScheme.primary),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: SolWattShapes.full,
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 1,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: SolWattShapes.full,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: SolWattShapes.full,
        side: BorderSide(color: colorScheme.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: SolWattShapes.full,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colorScheme.onSurfaceVariant,
        shape: SolWattShapes.full,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colorScheme.primaryContainer,
      foregroundColor: colorScheme.onPrimaryContainer,
      elevation: 3,
      focusElevation: 3,
      hoverElevation: 4,
      highlightElevation: 2,
      shape: SolWattShapes.large,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerHighest,
      selectedColor: colorScheme.secondaryContainer,
      disabledColor: colorScheme.onSurface.withValues(alpha: 0.12),
      labelStyle: textTheme.labelLarge!,
      secondaryLabelStyle: textTheme.labelLarge!.copyWith(
        color: colorScheme.onSecondaryContainer,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      shape: SolWattShapes.small,
      side: BorderSide.none,
      showCheckmark: true,
      checkmarkColor: colorScheme.onSecondaryContainer,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      elevation: 0,
      backgroundColor: colorScheme.surfaceContainer,
      indicatorColor: colorScheme.secondaryContainer,
      surfaceTintColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          fill: selected ? 1 : 0,
          color: selected
              ? colorScheme.onSecondaryContainer
              : colorScheme.onSurfaceVariant,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelMedium?.copyWith(
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected
              ? colorScheme.onSurface
              : colorScheme.onSurfaceVariant,
        );
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      indicatorColor: colorScheme.secondaryContainer,
      selectedIconTheme: IconThemeData(
        color: colorScheme.onSecondaryContainer,
        fill: 1,
        size: 24,
      ),
      unselectedIconTheme: IconThemeData(
        color: colorScheme.onSurfaceVariant,
        fill: 0,
        size: 24,
      ),
      selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
      minWidth: 80,
      minExtendedWidth: 220,
      useIndicator: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: SolWattShapes.extraLarge,
      titleTextStyle: textTheme.headlineSmall?.copyWith(
        color: colorScheme.onSurface,
      ),
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      modalElevation: 1,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colorScheme.inverseSurface,
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onInverseSurface,
      ),
      shape: SolWattShapes.small,
      elevation: 2,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colorScheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: SolWattShapes.medium,
      textStyle: textTheme.bodyLarge,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colorScheme.surfaceContainer),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(3),
        shape: const WidgetStatePropertyAll(SolWattShapes.medium),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary;
        }
        return null;
      }),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colorScheme.surfaceContainer),
        shape: const WidgetStatePropertyAll(SolWattShapes.medium),
      ),
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

/// Prefix field icon. For multi-line fields pass [maxLines] so the icon sits
/// near the top (InputDecorator centers the icon box; a tall box offsets it).
///
/// Do not use infinite height constraints — scrollable sheets provide
/// unbounded max height and will assert.
Widget inputPrefixIcon(
  IconData icon, {
  double top = 12,
  double size = 24,
  int maxLines = 1,
}) {
  final glyph = Icon(icon, size: size);

  if (maxLines <= 1) {
    return glyph;
  }

  // InputDecorator vertically centers the prefix box. Match multi-line height
  // so a top-aligned icon inside that box lands near the first text line.
  final estimatedHeight = top + size + (maxLines - 1) * 22.0 + 16;
  return SizedBox(
    width: 48,
    height: estimatedHeight,
    child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: glyph,
      ),
    ),
  );
}

TextTheme _solWattTextTheme(TextTheme base) {
  return base.copyWith(
    displayLarge: base.displayLarge?.copyWith(fontWeight: FontWeight.w700),
    displayMedium: base.displayMedium?.copyWith(fontWeight: FontWeight.w700),
    displaySmall: base.displaySmall?.copyWith(fontWeight: FontWeight.w700),
    headlineLarge: base.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
    headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
    headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
    titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w500),
    labelSmall: base.labelSmall?.copyWith(fontWeight: FontWeight.w500),
  );
}

/// Theme for the `material_ui` fork, which `island_ui_foundation` builds its
/// chrome from — bottom sheets, snackbars, notification overlays and the
/// desktop window frame. The fork keeps its own theme system ([mui.Theme],
/// [mui.ThemeData]) separate from Flutter's, so those widgets read this theme
/// and not [createSolWattTheme].
///
/// [seedColor] is the same seed [app] was built from: the fork runs its own
/// copy of the Material algorithm, so mirroring the seed reproduces the app's
/// scheme instead of pinning the fork chrome to the default amber. The whole
/// drive page and the fork overlays are fork widgets — without the accent they
/// ignore the user's accent choice.
///
/// Mirror the app's typography, icon settings, dividers and density into it:
/// without the mirror the fork chrome falls back to its own defaults and
/// renders in the platform font instead of the app font.
mui.ThemeData createSolWattForkTheme(ThemeData app, Color seedColor) {
  final brightness = app.brightness;
  final scheme = app.colorScheme;
  // The window frame paints the app surface behind the routed app, so the
  // chrome surface has to match the app's rather than the seed's.
  final forkScheme = mui.ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  ).copyWith(surfaceContainer: scheme.surface);

  return mui.ThemeData(
    brightness: brightness,
    // Covers fork widgets that build a bare TextStyle, without pulling a slot
    // out of the text theme.
    fontFamily: SolWattFonts.sans,
    colorScheme: forkScheme,
    textTheme: _forkTextTheme(app.textTheme),
    primaryTextTheme: _forkTextTheme(app.primaryTextTheme),
    iconTheme: app.iconTheme,
    primaryIconTheme: app.primaryIconTheme,
    dividerTheme: mui.DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    visualDensity: mui.VisualDensity(
      horizontal: app.visualDensity.horizontal,
      vertical: app.visualDensity.vertical,
    ),
  );
}

/// The fork declares its own [mui.TextTheme] over the shared Flutter
/// [TextStyle], so the app's slots carry over as they are.
mui.TextTheme _forkTextTheme(TextTheme source) => mui.TextTheme(
  displayLarge: source.displayLarge,
  displayMedium: source.displayMedium,
  displaySmall: source.displaySmall,
  headlineLarge: source.headlineLarge,
  headlineMedium: source.headlineMedium,
  headlineSmall: source.headlineSmall,
  titleLarge: source.titleLarge,
  titleMedium: source.titleMedium,
  titleSmall: source.titleSmall,
  bodyLarge: source.bodyLarge,
  bodyMedium: source.bodyMedium,
  bodySmall: source.bodySmall,
  labelLarge: source.labelLarge,
  labelMedium: source.labelMedium,
  labelSmall: source.labelSmall,
);
