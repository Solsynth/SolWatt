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
  main.dart                       # Bootstrap, routes, app shell, shared pages
  main.gr.dart                    # Generated auto_route routes; do not edit
  theme.dart                      # Island-derived Material theme and Nunito
  network.dart                    # OAuth, WattEngine client, session providers
  gate/gate_page.dart             # Sign-in + workspace selection entry
  workspaces/workspace_actions.dart  # Workspace CRUD and shared list UI
  ui/page_scaffold.dart           # Shared page chrome for shell screens
  boards/boards_screen.dart       # Ideask boards and tasks
  <feature>/                      # Future product features
docs/
  ARCH.md                         # This document
assets/fonts/                     # Bundled Nunito font files
```

## Access gate

Users must complete both steps before product features are available:

1. **Sign in** with Solar Network OAuth (PKCE).
2. **Select or create** an active workspace.

`GatePage` is the initial route. It shows sign-in when there is no session,
workspace selection/creation when signed in without an active workspace, and
replaces itself with `AppShellPage` once `appAccessProvider` reports `ready`.

`AppShellPage` re-checks access and returns to the gate on sign-out, workspace
clear, or session loss. Feature routes under the shell assume a valid session
and selected workspace.

Session and workspace selection are persisted with secure storage. Prefer
`invalidateSessionScope` / `invalidateWorkspaceScope` after auth or workspace
changes so dependent providers refresh consistently.

## Application shell

`main()` initializes the Flutter binding and configures a hidden native title
bar on desktop. `DesktopWindowFrame` wraps the routed app once and supplies the
draggable desktop title bar and platform window controls.

`createSolWattTheme()` is the shared light/dark Material 3 theme. It follows
Island's baseline component and platform-transition settings, but uses
SolWatt's fixed seed color rather than Island's settings-driven theme
customization.

## Navigation

`AppRouter` owns the root routes: `GatePage` (initial) and `AppShellPage`.
`AppShellPage` is an `AutoTabsRouter` shell with home, boards, profile, and
settings. Its desktop rail follows the MaidKit pattern: primary destinations
are top-aligned and profile/settings trail at the bottom. The narrow layout
exposes the same routes in a compact `NavigationBar`.

Add product screens as child routes of `AppShellPage` when their purpose is
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

Key providers:

- `authSessionProvider` / `userInfoProvider` — Solar Network identity
- `workspacesProvider` / `selectedWorkspaceProvider` — workspace list and active selection
- `appAccessProvider` — combined gate state (`needsSignIn` | `needsWorkspace` | `ready`)
- `broadsProvider` / `tasksProvider` — Ideask data scoped to the active workspace

## Validation

Run these before handing off changes:

```sh
dart format lib
dart run build_runner build
flutter analyze
# Run this once logic tests have been added under test/.
flutter test
```
