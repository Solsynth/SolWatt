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
  ui/cloud_files.dart             # Cloud upload picker + link attachment
  boards/boards_screen.dart       # Ideask boards and tasks
  files/files_screen.dart         # Workspace Drive tabs (folders, assets, quota, views)
  tasks/                          # Background task overlay (uploads, etc.)
  notifications/                  # Ring multi-tenant inbox + unread badge
  realtime/realtime.dart          # Gateway packet routing (notify + Ideask)
  websocket.dart                  # Solar Network /ws client
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
`AppShellPage` is an `AutoTabsRouter` shell with home, boards, files, profile,
and settings. Its desktop rail follows the MaidKit pattern: primary destinations
are top-aligned and profile/settings trail at the bottom. The narrow layout
exposes the same routes in a compact `NavigationBar`.

Workspace Drive uploads always pass `workspace_id` so DysonFS charges the
workspace plan quota rather than the personal account quota.

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
- `workspaceFilesProvider` / `workspaceFolderChildrenProvider` / `workspaceUnindexedFilesProvider` — workspace Drive listings (`workspace_id` query; indexed folders vs unindexed assets)
- `workspaceDriveUsageProvider` — live storage used/total for the active workspace
- `solarNetworkClientProvider` — authenticated Solar Network SDK (bearer from OAuth session)
- `notificationUnreadCountProvider` / `notificationListProvider` — Ring inbox scoped to SolWatt’s multi-tenant app id

## Notifications (Ring)

SolWatt uses Solar Network’s **Ring** service (`/ring/notifications`) via the
SDK `NotificationsApi`. Ring is multi-tenant: every list/count/mark-read call
and push subscription must pass SolWatt’s app id so the client never mixes in
Solian (or other apps) traffic.

| Constant | Value |
| --- | --- |
| `kNotificationTenantAppId` | `dev.solsynth.solarwatt` (bundle / application id) |
| Island’s equivalent | `dev.solsynth.solian` |

UI: `lib/notifications/notifications.dart` — inbox dialog, unread badge, and
`NotificationBellButton` on the desktop rail and Home page.

## Realtime (websocket gateway)

While signed in with an active workspace, SolWatt keeps a connection to the
Solar Network gateway at `wss://api.solian.app/ws` (same host as REST, `http` →
`ws`). Auth uses the OAuth bearer (Authorization header on native; `tk` query
on web).

### Multi-tenant namespace isolation

Blade’s wsgateway scopes connections, presence, and pushes by **namespace**
(see `Blade/docs/WEBSOCKET_GATEWAY.md`). SolWatt connects with:

```
GET /ws?namespace=dev.solsynth.solarwatt
```

That value is `kWebsocketNamespace` / `kProductTenantId` — the **same** reverse-DNS
id used as Ring’s multi-tenant `app` / `app_id`. Empty namespace would use the
gateway default (`_default`) and mix traffic with Solian.

| Layer | Isolation key | SolWatt value |
| --- | --- | --- |
| Ring notifications | `app` query / `app_id` | `dev.solsynth.solarwatt` |
| Websocket gateway | `namespace` query | `dev.solsynth.solarwatt` |
| Island (for comparison) | same pair | `dev.solsynth.solian` |

Server-side: Ring WS pushes use `notification.AppId` as the NATS push
namespace; Ideask task packets use `Realtime:WebsocketNamespace` (default
`dev.solsynth.solarwatt`).

| Piece | Role |
| --- | --- |
| `lib/websocket.dart` | Client, heartbeats (`ping`/`pong`), reconnect backoff, namespace |
| `lib/realtime/realtime.dart` | Session-bound bridge; packet routing |
| `realtimeBridgeProvider` | Watched by `AppShellPage`; connects/disconnects with auth |

Packet handling:

- `notifications.new` — refresh SolWatt-tenant unread count + inbox (ignores
  other apps’ `app_id`)
- `ideask.task_*` — debounced invalidate of `tasksProvider` /
  `taskGroupsProvider` for the board id in the payload
- `ideask.broad_*` — invalidate `broadsProvider`

A small status dot on the desktop rail shows connection state; tap retries.

## Validation

Run these before handing off changes:

```sh
dart format lib
dart run build_runner build
flutter analyze
# Run this once logic tests have been added under test/.
flutter test
```
