import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart' as mui;

abstract final class SolWattFonts {
  static const sans = 'Nunito';
}

// ---------------------------------------------------------------------------
// Design tokens
//
// The same coarse scales Solian builds its new island UI from: if a spacing or
// radius is not on this list it is a one-off, not a system decision. Keeping
// the scales small is what makes every screen read as one app.
// ---------------------------------------------------------------------------

/// Spacing scale, in logical pixels.
abstract final class SolSpace {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;

  /// Horizontal gutter for phone layouts.
  static const double page = xl;

  /// Horizontal gutter for tablet / desktop layouts.
  static const double pageWide = xxxl;

  /// Gap between major sections of a page.
  static const double section = xxl;

  /// Inset inside cards and other primary content surfaces.
  static const double card = xl;

  /// Minimum height of a comfortable primary control.
  static const double control = 48;
}

/// Shared spatial geometry & density tokens for the unified workspace shell.
///
/// Enforces identical header heights, list row density, and breakpoint widths
/// across Mail, Todo, Pages, Drive, and Today/Focus so switching lenses
/// produces zero visual jarring.
abstract final class SolWorkspaceGeometry {
  static const double headerHeight = 60;
  static const double desktopRowCompact = 40;
  static const double desktopRowTwoLine = 52;
  static const double mobileMinTouchTarget = 48;

  static const double railWidth = 56;
  static const double sidebarWidth = 240;
  static const double peekMinWidth = 380;
  static const double peekDefaultWidth = 420;
  static const double peekMaxWidth = 480;

  static const double desktopBreakpoint = 1024;
  static const double tabletBreakpoint = 600;
}

/// Corner-radius scale, in logical pixels.
abstract final class SolRadius {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 28;
  static const double pill = 999;

  static const double control = xl;
  static const double card = lg;
  static const double input = lg;
  static const double chip = sm;
  static const double menu = lg;
  static const double sheet = xxl;
  static const double dialog = xxl;

  static const BorderRadius controlRadius = BorderRadius.all(
    Radius.circular(control),
  );
  static const BorderRadius cardRadius = BorderRadius.all(
    Radius.circular(card),
  );
  static const BorderRadius inputRadius = BorderRadius.all(
    Radius.circular(input),
  );
  static const BorderRadius menuRadius = BorderRadius.all(
    Radius.circular(menu),
  );
  static const BorderRadius sheetRadius = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
  static const BorderRadius dialogRadius = BorderRadius.all(
    Radius.circular(dialog),
  );

  /// Fully rounded capsule: any height collapses to a pill, never a squircle.
  static const BorderRadius pillRadius = BorderRadius.all(
    Radius.circular(pill),
  );
}

/// Reusable insets built from [SolSpace].
abstract final class SolInsets {
  static const page = EdgeInsets.symmetric(horizontal: SolSpace.page);
  static const pageVertical = EdgeInsets.symmetric(vertical: SolSpace.page);
  static const card = EdgeInsets.all(SolSpace.card);
  static const control = EdgeInsets.symmetric(
    horizontal: SolSpace.xxl,
    vertical: SolSpace.md,
  );
  static const input = EdgeInsets.symmetric(
    horizontal: SolSpace.lg,
    vertical: SolSpace.lg,
  );
}

/// Page gutter for the current width: 20 on phones, 32 from tablet up.
EdgeInsets solPagePadding(BuildContext context) => EdgeInsets.symmetric(
  horizontal: MediaQuery.sizeOf(context).width >= 600
      ? SolSpace.pageWide
      : SolSpace.page,
);

/// Radius of every menu surface: `PopupMenuButton` popups and `MenuAnchor`
/// menus (the 20px primary-shape token used by buttons, cards and inputs).
/// The framework default is 4px, so this is applied globally here; a caller
/// that needs another radius must override it on the widget itself.
const kMenuBorderRadius = SolRadius.menu;

const _menuShape = RoundedRectangleBorder(borderRadius: SolRadius.menuRadius);

const _cardShape = RoundedRectangleBorder(borderRadius: SolRadius.cardRadius);

/// Shape tokens kept for call sites that still name them. New code should use
/// the [SolRadius] tokens directly.
abstract final class SolWattShapes {
  static const extraSmall = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(SolRadius.xs)),
  );
  static const small = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(SolRadius.sm)),
  );
  static const medium = RoundedRectangleBorder(borderRadius: SolRadius.cardRadius);
  static const large = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(SolRadius.xl)),
  );
  static const extraLarge = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(SolRadius.xxl)),
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

ThemeData createSolWattTheme(
  Brightness brightness, {
  Color seedColor = kSolWattSeedColor,
}) {
  var colorScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  );

  // Replace the seed-generated neutral ramp with a paper ramp built from the
  // seed's own hue. Tones control the warmth (soft, low-contrast steps); the
  // hue comes from the seed, so the ground moves with the accent instead of
  // sitting on a fixed beige. This is the same ground Solian renders on.
  colorScheme = _seedPaper(colorScheme, seedColor, brightness);

  final baseTheme = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    brightness: brightness,
    fontFamily: SolWattFonts.sans,
    scaffoldBackgroundColor: colorScheme.surface,
    canvasColor: colorScheme.surface,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    splashFactory: InkSparkle.splashFactory,
    iconTheme: IconThemeData(
      fill: 0,
      weight: 400,
      opticalSize: 20,
      color: colorScheme.onSurface,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colorScheme.primary,
      selectionColor: colorScheme.primary.withValues(alpha: 0.24),
      selectionHandleColor: colorScheme.primary,
    ),
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
    // Material 2024 component appearance; the 2023 defaults look dated next
    // to the app's own chrome.
    // ignore: deprecated_member_use
    progressIndicatorTheme: const ProgressIndicatorThemeData(year2023: false),
    // ignore: deprecated_member_use
    sliderTheme: const SliderThemeData(year2023: false),
  );

  final textTheme = _solWattTextTheme(baseTheme.textTheme);
  final onSurface = colorScheme.onSurface;
  final onSurfaceVariant = colorScheme.onSurfaceVariant;

  final buttonShape = RoundedRectangleBorder(
    borderRadius: SolRadius.controlRadius,
  );

  // Inputs are tonal first: a soft filled shape defines the field, and only
  // the focused/error states draw an outline. The resting border is an
  // `OutlineInputBorder` with no side so the fill keeps its rounded shape
  // instead of collapsing into a sharp rectangle.
  final inputBorder = OutlineInputBorder(
    borderRadius: SolRadius.inputRadius,
    borderSide: BorderSide.none,
  );
  final focusedInputBorder = OutlineInputBorder(
    borderRadius: SolRadius.inputRadius,
    borderSide: BorderSide.none,
  );
  final errorInputBorder = OutlineInputBorder(
    borderRadius: SolRadius.inputRadius,
    borderSide: BorderSide(color: colorScheme.error),
  );

  final appBarForeground = colorScheme.onSurface;

  return baseTheme.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      // Titles read left aligned, like a document: the leading icon occupies
      // the left edge and the title starts right of it.
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: colorScheme.surfaceTint,
      backgroundColor: colorScheme.surface,
      foregroundColor: appBarForeground,
      iconTheme: IconThemeData(color: appBarForeground),
      actionsIconTheme: IconThemeData(color: appBarForeground),
      toolbarHeight: 60,
      titleSpacing: SolSpace.md,
      actionsPadding: const EdgeInsets.only(right: SolSpace.sm),
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: appBarForeground,
      ),
    ),
    cardTheme: CardThemeData(
      // A card is a slightly deeper sheet of the same warm paper. Separation
      // comes from tone, not from a shadow.
      color: colorScheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.12),
      elevation: 0,
      margin: const EdgeInsets.all(SolSpace.xs),
      shape: _cardShape,
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: ListTileThemeData(
      minLeadingWidth: 40,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SolRadius.sm),
      ),
      selectedTileColor: colorScheme.secondaryContainer.withValues(alpha: 0.55),
      iconColor: onSurfaceVariant,
      textColor: onSurface,
      titleTextStyle: textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: onSurface,
      ),
      subtitleTextStyle: textTheme.bodySmall?.copyWith(
        color: onSurfaceVariant,
        height: 1.4,
      ),
      leadingAndTrailingTextStyle: textTheme.labelMedium?.copyWith(
        color: onSurfaceVariant,
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: colorScheme.surfaceContainerHigh.withValues(alpha: 0.7),
      contentPadding: SolInsets.input,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: focusedInputBorder,
      errorBorder: errorInputBorder,
      focusedErrorBorder: focusedInputBorder.copyWith(
        borderSide: BorderSide(color: colorScheme.error, width: 1.5),
      ),
      disabledBorder: inputBorder,
      // Kept finite so multi-line fields inside scroll views stay bounded.
      prefixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 0),
      suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 0),
      hintStyle: textTheme.bodyMedium?.copyWith(
        color: onSurfaceVariant.withValues(alpha: 0.72),
      ),
      labelStyle: textTheme.bodyMedium?.copyWith(color: onSurfaceVariant),
      floatingLabelStyle: textTheme.bodyMedium?.copyWith(
        color: colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
      helperStyle: textTheme.bodySmall?.copyWith(color: onSurfaceVariant),
      errorStyle: textTheme.bodySmall?.copyWith(color: colorScheme.error),
      iconColor: onSurfaceVariant,
      prefixIconColor: onSurfaceVariant,
      suffixIconColor: onSurfaceVariant,
      prefixStyle: textTheme.bodyMedium?.copyWith(color: onSurface),
      suffixStyle: textTheme.bodyMedium?.copyWith(color: onSurfaceVariant),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // One step tighter horizontally than the other buttons: the composer
        // rail packs Send beside its tools and must survive a 2x text scale.
        padding: const EdgeInsets.symmetric(
          horizontal: SolSpace.lg,
          vertical: SolSpace.md,
        ),
        minimumSize: const Size(64, SolSpace.control),
        shape: buttonShape,
        animationDuration: const Duration(milliseconds: 180),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding: SolInsets.control,
        minimumSize: const Size(64, SolSpace.control),
        shape: buttonShape,
        animationDuration: const Duration(milliseconds: 180),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: SolInsets.control,
        minimumSize: const Size(64, SolSpace.control),
        shape: buttonShape,
        side: BorderSide(color: colorScheme.outlineVariant),
        animationDuration: const Duration(milliseconds: 180),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: SolSpace.lg,
          vertical: SolSpace.md,
        ),
        minimumSize: const Size(48, 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SolRadius.md),
        ),
        animationDuration: const Duration(milliseconds: 180),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: onSurfaceVariant,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(SolRadius.md)),
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: SolSpace.lg, vertical: SolSpace.md),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(64, 44)),
        textStyle: WidgetStatePropertyAll(
          textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: buttonShape,
      // Flat like the rest of the surfaces; elevation only appears as a
      // hover/press affordance.
      elevation: 0,
      focusElevation: 1,
      hoverElevation: 2,
      highlightElevation: 1,
      extendedPadding: const EdgeInsets.symmetric(
        horizontal: SolSpace.xxl,
        vertical: SolSpace.lg,
      ),
      extendedIconLabelSpacing: SolSpace.md,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.18),
      elevation: 3,
      shape: const RoundedRectangleBorder(borderRadius: SolRadius.dialogRadius),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: SolSpace.xxl,
        vertical: SolSpace.xxl,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        SolSpace.xl,
        0,
        SolSpace.xl,
        SolSpace.lg,
      ),
      titleTextStyle: textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: onSurface,
      ),
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: onSurfaceVariant,
        height: 1.5,
      ),
      iconColor: colorScheme.primary,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      modalBackgroundColor: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(borderRadius: SolRadius.sheetRadius),
      dragHandleColor: onSurfaceVariant.withValues(alpha: 0.4),
      clipBehavior: Clip.antiAlias,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colorScheme.inverseSurface,
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onInverseSurface,
      ),
      actionTextColor: colorScheme.inversePrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SolRadius.md),
      ),
      insetPadding: const EdgeInsets.fromLTRB(
        SolSpace.xl,
        0,
        SolSpace.xl,
        SolSpace.lg,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.18),
      elevation: 3,
      shape: _menuShape,
      menuPadding: const EdgeInsets.symmetric(vertical: SolSpace.sm),
      textStyle: textTheme.bodyMedium?.copyWith(color: onSurface),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          colorScheme.surfaceContainerLow,
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(3),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(_menuShape),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: SolSpace.sm),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      selectedColor: colorScheme.secondaryContainer,
      secondarySelectedColor: colorScheme.secondaryContainer,
      // Tonal chips: the fill carries the shape, no outline.
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SolRadius.chip),
      ),
      labelPadding: const EdgeInsets.symmetric(horizontal: SolSpace.sm),
      labelStyle: textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
        color: onSurface,
      ),
      secondaryLabelStyle: textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
        color: colorScheme.onSecondaryContainer,
      ),
      iconTheme: IconThemeData(size: 18, color: onSurfaceVariant),
      checkmarkColor: colorScheme.onSecondaryContainer,
    ),
    expansionTileTheme: ExpansionTileThemeData(
      tilePadding: const EdgeInsets.symmetric(
        horizontal: SolSpace.xl,
        vertical: SolSpace.xs,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SolRadius.sm),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SolRadius.sm),
      ),
      iconColor: onSurfaceVariant,
      collapsedIconColor: onSurfaceVariant,
      textColor: onSurface,
      collapsedTextColor: onSurface,
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: colorScheme.outlineVariant.withValues(alpha: 0.5),
      splashBorderRadius: BorderRadius.circular(SolRadius.sm),
      labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      unselectedLabelStyle: textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      elevation: 0,
      backgroundColor: colorScheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      indicatorColor: colorScheme.secondaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SolRadius.md),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelMedium?.copyWith(
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? colorScheme.onSurface : onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          fill: selected ? 1 : 0,
          color: selected ? colorScheme.onSecondaryContainer : onSurfaceVariant,
        );
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      indicatorColor: colorScheme.secondaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SolRadius.md),
      ),
      selectedIconTheme: IconThemeData(
        color: colorScheme.onSecondaryContainer,
        fill: 1,
        size: 24,
      ),
      unselectedIconTheme: IconThemeData(
        color: onSurfaceVariant,
        fill: 0,
        size: 24,
      ),
      selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w500,
        color: onSurfaceVariant,
      ),
      minWidth: 80,
      minExtendedWidth: 220,
      useIndicator: true,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          right: Radius.circular(SolRadius.xl),
        ),
      ),
      endShape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(SolRadius.xl),
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide(color: colorScheme.outline, width: 1.2),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.transparent;
        return colorScheme.outline;
      }),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant.withValues(alpha: 0.7),
      thickness: 1,
      space: SolSpace.lg,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered) ? 8 : 4,
      ),
      radius: const Radius.circular(SolRadius.pill),
      thumbColor: WidgetStatePropertyAll(
        onSurfaceVariant.withValues(alpha: 0.35),
      ),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(SolRadius.sm),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: SolSpace.sm,
        vertical: SolSpace.xs,
      ),
      textStyle: textTheme.labelSmall?.copyWith(
        color: colorScheme.onInverseSurface,
      ),
      waitDuration: const Duration(milliseconds: 400),
      exitDuration: const Duration(milliseconds: 100),
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

/// Builds the neutral ramp for the app's paper look from the seed.
///
/// Only the *ground* is rebuilt here: accent roles (primary, secondary,
/// tertiary, error) are left exactly as the seed produced them. The difference
/// from a stock `ColorScheme.fromSeed` is that tones are fixed to a soft,
/// paper-like ramp while the hue and a trace of the seed's chroma are kept, so
/// an amber seed reads as warm paper and an indigo seed as cool paper. A
/// near-gray seed stays neutral instead of picking up an unrelated hue.
ColorScheme _seedPaper(
  ColorScheme scheme,
  Color seedColor,
  Brightness brightness,
) {
  final seed = Hct.fromInt(seedColor.toARGB32());
  // A near-gray seed is a deliberate choice: do not invent a hue for it.
  final hasHue = seed.chroma >= 5;
  final hue = hasHue ? seed.hue : 0.0;
  // Cap the tint so vivid seeds stay paper, not pastel; muted seeds get less.
  final tint = hasHue ? (seed.chroma / 16).clamp(1.5, 4.0) : 0.0;

  Color shade(double tone, [double tintScale = 1]) =>
      Color(Hct.from(hue, tint * tintScale, tone).toInt());

  final isDark = brightness == Brightness.dark;
  return scheme.copyWith(
    surface: shade(isDark ? 7.5 : 97.5, 0.7),
    surfaceDim: shade(isDark ? 5 : 87),
    surfaceBright: shade(isDark ? 25 : 99, 0.5),
    surfaceContainerLowest: shade(isDark ? 4 : 100, 0.3),
    surfaceContainerLow: shade(isDark ? 11 : 96),
    surfaceContainer: shade(isDark ? 14 : 93),
    surfaceContainerHigh: shade(isDark ? 19 : 90),
    surfaceContainerHighest: shade(isDark ? 24 : 87),
    onSurface: shade(isDark ? 93 : 12, 1.1),
    onSurfaceVariant: shade(isDark ? 80 : 32, 1.25),
    outline: shade(isDark ? 62 : 52, 1.4),
    outlineVariant: shade(isDark ? 32 : 84, 1.2),
    inverseSurface: shade(isDark ? 92 : 22),
    onInverseSurface: shade(isDark ? 18 : 96, 0.8),
    shadow: shade(isDark ? 2 : 14, 1.5),
    scrim: shade(isDark ? 2 : 8, 1.5),
  );
}

/// Softens the generated type ramp without changing its sizes.
///
/// Nunito already carries most of the warmth; the extra tracking on headings
/// and the taller body leading make long lists and settings pages easier to
/// scan without making them feel loose.
TextTheme _solWattTextTheme(TextTheme base) {
  return base.copyWith(
    displayLarge: base.displayLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -1,
    ),
    displayMedium: base.displayMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.8,
    ),
    displaySmall: base.displaySmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
    ),
    headlineLarge: base.headlineLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    headlineMedium: base.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    ),
    headlineSmall: base.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    ),
    titleLarge: base.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.25,
      height: 1.25,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      height: 1.3,
    ),
    titleSmall: base.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      height: 1.3,
    ),
    bodyLarge: base.bodyLarge?.copyWith(height: 1.5),
    bodyMedium: base.bodyMedium?.copyWith(height: 1.5),
    bodySmall: base.bodySmall?.copyWith(height: 1.45),
    labelLarge: base.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w500),
    labelSmall: base.labelSmall?.copyWith(fontWeight: FontWeight.w500),
  );
}

/// Theme for the `material_ui` fork, which `island_ui_foundation` builds its
/// chrome from — bottom sheets, snackbars, notification overlays. The fork
/// keeps its own theme system ([mui.Theme], [mui.ThemeData]) separate from
/// Flutter's, so those widgets read this theme and not [createSolWattTheme].
///
/// [seedColor] is the same seed the app was built from: the fork runs its own
/// copy of the Material algorithm, so mirroring the seed reproduces the app's
/// scheme instead of pinning the fork chrome to the default amber. The drive
/// page and the fork overlays are fork widgets — without the accent they
/// ignore the user's accent choice.
///
/// Mirror the app's typography, icon settings, dividers and density into it:
/// without the mirror the fork chrome falls back to its own defaults and
/// renders in the platform font instead of the app font.
mui.ThemeData createSolWattForkTheme(ThemeData app, Color seedColor) {
  final brightness = app.brightness;
  final scheme = app.colorScheme;
  final forkScheme = mui.ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  ).copyWith(
    surface: scheme.surface,
    surfaceDim: scheme.surfaceDim,
    surfaceBright: scheme.surfaceBright,
    surfaceContainerLowest: scheme.surfaceContainerLowest,
    surfaceContainer: scheme.surfaceContainer,
    surfaceContainerLow: scheme.surfaceContainerLow,
    surfaceContainerHigh: scheme.surfaceContainerHigh,
    surfaceContainerHighest: scheme.surfaceContainerHighest,
    onSurface: scheme.onSurface,
    onSurfaceVariant: scheme.onSurfaceVariant,
    outline: scheme.outline,
    outlineVariant: scheme.outlineVariant,
    inverseSurface: scheme.inverseSurface,
    onInverseSurface: scheme.onInverseSurface,
    surfaceTint: scheme.surfaceTint,
    shadow: scheme.shadow,
    scrim: scheme.scrim,
  );

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
