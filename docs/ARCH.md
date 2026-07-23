# SolWatt architecture

SolWatt is a desktop-first Flutter application scaffold. Its product domain is
intentionally not defined yet; this document describes the shared application
foundation that future features should build on.

## Stack

- **Flutter + Material 3** for the application UI.
- **Nunito** as the bundled application typeface.
- **Riverpod** and **flutter_hooks** for state, lifecycle-aware UI state, and
  dependency wiring.
- **auto_route** for declarative, nested navigation. Generated route files
  live beside their router and must not be edited manually.
- **freezed** for immutable domain and state models when product models are
  introduced.
- **island_ui_foundation** from the Solian Git repository for the desktop
  window frame and responsive UI utilities.
- **window_manager** for native desktop window setup.
- **material_symbols_icons** for the application icon set.

## Source layout

Keep the initial application shell small. Add feature folders only when the
product domain is known; a feature may start flat at `lib/<feature>/` and gain
`data`, `domain`, or `presentation` subfolders only when it has enough code to
justify them.

```
lib/
  main.dart                       # Bootstrap, window setup, routes, app shell
  main.gr.dart                    # Generated auto_route routes; do not edit
  theme.dart                      # Island-derived Material theme and Nunito
  <feature>/                      # Future product features
docs/
  ARCH.md                         # This document
assets/fonts/                     # Bundled Nunito font files
```

## Application shell

`main()` initializes the Flutter binding and configures a hidden native title
bar on desktop. `DesktopWindowFrame` wraps the routed app once and supplies the
draggable desktop title bar and platform window controls.

`createSolWattTheme()` is the shared light/dark Material 3 theme. It follows
Island's baseline component and platform-transition settings, but uses
SolWatt's fixed seed color rather than Island's settings-driven theme
customization.

## Navigation

`AppRouter` owns the root route. `AppShellPage` is an `AutoTabsRouter` shell
with a generic home route and a settings route. Its desktop rail follows the
MaidKit pattern: primary destinations are top-aligned and settings is a
bottom-trailing action. The narrow layout exposes the same routes in a compact
`NavigationBar`.

Add product workspaces as child routes of `AppShellPage` when their purpose is
known. Do not add placeholder pages or speculative UI content.

When changing routes:

1. Add `@RoutePage()` to the page.
2. Update `AppRouter` in `lib/main.dart`.
3. Run `dart run build_runner build`.
4. Never hand-edit `*.gr.dart` files.

## State and models

Use Riverpod providers for application state, service construction, and
feature dependencies. Use `flutter_hooks` inside UI widgets only for local,
lifecycle-bound behaviour. Use Freezed for immutable value/state types once
they are backed by a real feature; generated `*.freezed.dart` files must not
be edited manually.

## Validation

Run these before handing off changes:

```sh
dart format lib
dart run build_runner build
flutter analyze
# Run this once logic tests have been added under test/.
flutter test
```
