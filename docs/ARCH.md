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
  main.dart                       # Bootstrap, app shell, window frame
  route.dart                      # AppRouter and every route declaration
  route.gr.dart                   # Generated auto_route routes; do not edit
  theme.dart                      # Island-derived Material theme and Nunito
  network.dart                    # OAuth, WattEngine client, session providers
  gate/gate_page.dart             # Sign-in + workspace selection entry
  workspaces/workspace_actions.dart  # Workspace CRUD and shared list UI
  ui/page_scaffold.dart           # Shared page chrome for shell screens
  ui/cloud_files.dart             # Cloud upload picker + link attachment
  boards/boards_screen.dart       # Boards tab shell, board list, board editor
  boards/board_detail.dart        # One board: header, lanes, cards, task detail
  boards/board_sheets.dart        # Task editor, lane picker, groups, assignees
  boards/github_integration.dart  # GitHub App link/sync UI for a board
  boards/task_comments.dart       # Task comments (local + GitHub-mirrored)
  mail/mail_screen.dart           # Mail tab: conversation list, detail pane, compose
  mail/mail_settings_page.dart    # Mail credentials + .eml/.mbox import
  mail/import/                    # EML/mbox parsing and the import service
  core/widgets/content/           # Drive viewer, image lightbox, file actions
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

`lib/boards/boards_screen.dart` is the library head and `board_detail.dart` /
`board_sheets.dart` are its `part` files: the boards surfaces share private
helpers (lane colours, date formatting, priority metadata) without widening the
library's public surface. Keep new board-internal helpers private; add a part
file rather than a second public API.


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

`island_ui_foundation` builds its chrome — sheets, snackbars, notification
overlays, `DesktopWindowFrame` — from the `material_ui` fork, which reads its
own theme system rather than Flutter's. `createSolWattForkTheme()` mirrors the
app theme (typography including the Nunito family, colors, icons, dividers,
density) into `mui.ThemeData`, and `main()` provides it as the `mui.Theme`
ancestor. Without that mirror the fork chrome renders in the fork's Roboto
default instead of the app font. Any new app-theme token the fork chrome should
honor belongs in that function.

The fork's `Material` is not Flutter's: `Material.maybeOf` looks for each
library's own private `_RenderInkFeatures` render object, so a fork `Material`
ancestor does not satisfy Flutter's `ListTile`, `InkWell`, or M2 `IconButton`
(`assert(debugCheckHasMaterial(context))` → *No Material widget found*). App
content rendered inside fork chrome — `AttentionModalScaffold`,
`SheetScaffold`, … — must therefore bring its own Flutter material surface,
either a Flutter `Card` or a `Material(type: MaterialType.transparency)`
wrapper.

## Navigation

`AppRouter` owns the root routes: `GatePage` (initial) and `AppShellPage`.
`AppShellPage` is an `AutoTabsRouter` shell over mail, boards, files, flywheel,
and profile. Wide screens get a rail that lists the mail folders while Mail is
active (with the inbox badge) and the top-level tabs otherwise, plus a drawer
for the rest.

A tab that has a list-and-detail shape owns a *nested* stack, so its detail
surfaces keep the shell chrome and Back returns to the list it came from
instead of covering the rail: the mail tab pushes compose/settings/detail above
its list, and the boards tab pushes one board (`/boards/:broadId`) above the
board list. Push through `context.router` inside such a tab, never through
`Navigator.of(context)` on the root navigator.

Once a tab's stack is deeper than its root, the shell drops the phone bottom
bar (and the drawer's edge swipe) — the pushed page owns the screen. The bar is
removed from the scaffold rather than collapsed in place, because the scaffold
gives the body's bottom inset to whichever bottom bar it is handed: the page
keeps the home-indicator inset only while the bar is absent.

Every tab page owns a top app bar (`PageScaffold`, or the page's own
`Scaffold`), and app-level navigation lives there, never in a bottom bar: on
narrow screens the app bar leads with `appBarDrawerButton` and the drawer holds
the workspace and the tabs the bar does not carry. The mail tab swaps the rail
for an app bar (drawer, inbox switcher, search, filters, settings) and a bottom
bar of mail folders — the ones that do not fit on the bar live behind its
"more" destination. The other tabs swap it for a bottom bar of all five
top-level tabs.

The shell's body claims the side and bottom insets only; the top inset belongs
to whatever chrome the page puts there. The mail panes that carry a toolbar
instead of a `Scaffold` app bar (the detail pane, the composer, mail settings)
wrap that chrome in `SafeArea(bottom: false)`, so it grows by the status bar and
their surface paints the strip behind it.

Workspace Drive uploads always pass `workspace_id` so DysonFS charges the
workspace plan quota rather than the personal account quota.

Add product screens as child routes of `AppShellPage` when their purpose is
known. Do not add placeholder pages or speculative UI content.

When changing routes:

1. Add `@RoutePage()` to the page.
2. Update `AppRouter` in `lib/route.dart`.
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
- `broadsProvider` / `tasksProvider` / `taskGroupsProvider` — Ideask data scoped to the active workspace
- `gitHubIntegrationProvider` / `taskCommentsProvider` — GitHub App board link and task comments
- `workspaceFilesProvider` / `workspaceFolderChildrenProvider` / `workspaceUnindexedFilesProvider` — workspace Drive listings (`workspace_id` query; indexed folders vs unindexed assets)
- `workspaceDriveUsageProvider` — live storage used/total for the active workspace
- `solarNetworkClientProvider` — authenticated Solar Network SDK (bearer from OAuth session)
- `solWattPushProvider` — keeps the Metoer push subscription alive; subscribes on sign-in
- `notificationUnreadCountProvider` / `notificationListProvider` — Ring inbox scoped to SolWatt’s multi-tenant app id
- `threadsProvider` / `threadProvider` — ElecPostal conversations: the active
  mailbox's thread summaries (`MailThreadsQuery` = list filter + page size) and
  one conversation's messages, oldest first. A term in the filter's `q` widens
  the query to every mailbox and folder instead
- `emailProvider` — a single message, which the detail route opens on

## Mail (ElecPostal)

ElecPostal gives every message a `thread_id` and exposes conversations
directly, so the mail tab is conversation-first:

- Every message carries a `thread_id`, and replies to a known message join its
  conversation. When the caller names a parent (`reply_to_id` in-app, or the
  RFC 5322 `In-Reply-To`/`References` chain on inbound SMTP and `.eml`/`.mbox`
  import), ElecPostal resolves the parent's `Message-ID` to its thread and
  chains the new message in — so reply → reply → reply threads automatically
  even when an external sender never saw ElecPostal's `thread_id`. Outbound
  mail carries its own `Message-ID` plus the `In-Reply-To`/`References` chain,
  so the recipient's client (and a reply coming back) threads it the same way.
  A message whose chain names nothing the account holds starts a new thread.
- The list is one row per thread (`GET /postal/mailboxes/{id}/threads`): the
  newest message's sender, subject, preview and delivery state, plus the
  conversation's message count and unread count. The counts come from the
  server and cover the whole conversation, so a row never disagrees with what
  opening it shows.
- A search is not scoped: as soon as the search field holds a term,
  `threadsProvider` drops both the mailbox and the folder from the query and
  asks `GET /postal/threads`, so a term finds the message wherever it sits —
  another mailbox, Spam, or Trash. The list says so (a "searching every
  mailbox and folder" strip) and each row carries a badge naming the mailbox it
  came from, because the selected inbox no longer describes what is on screen.
  The browse list, with no term, stays folder- and mailbox-scoped.
- Multi-select: the header's select action (or a long press on a row) turns the
  list into a selection list — rows answer taps with a checkbox, a bottom bar
  carries the count, Select All, delete, and the flag and move actions — and
  every action applies to every message of every ticked conversation, the same
  fan-out a single row's actions use. Select All means the conversations the
  list has loaded, not the whole folder.
- Paging grows the request's `take` (`threadsProvider` keyed by
  filter + take) instead of paging offsets. Each fetch supersets the previous
  listing, so the row counts stay whole and no page can go missing; the list
  stops at ElecPostal's `take` cap of 200.
- Opening a row marks the conversation read: `thread_id` has no read endpoint,
  so the unread messages of the thread are read one by one.
- The detail pane shows the message the route opened plus a strip of the whole
  conversation (`GET /postal/threads/{id}`). Only the selected message's body
  is mounted, because the HTML body is a platform web view that owns the wheel
  over its area.
- Messages ElecPostal's assistant summarized carry the text as `summary`; the
  listing reuses it as the message's `body` preview, so a row already reads as
  the summary while the detail pane holds the full body. The pane's header also
  shows it (`MailEmail.summary` → `_EmailAiSummary`), an "AI summary" block
  above the recipient metadata, so a reader gets the gist before scrolling into
  the body. Summarization is opt-in per account, and a message carrying a
  verification code or security event is never sent to the agent, so `summary`
  is null for most mail and the header leaves no gap for it.
- Text-only bodies render as `EmailPlainTextBody` (`lib/mail/mail_screen.dart`)
  rather than in the web view. `emailPlainTextRuns` recognises the two shapes a
  plain body can carry —
  `http(s)://`/`www.` URLs and bare email addresses — and the widget draws them
  in the theme's link colour with a tap target that goes through
  `openEmailLink`, the same external launcher the web view uses for a sender's
  `<a href>`. Punctuation the sentence adds after a URL stays in the copy, and
  bare hostnames (`notes.md`, `v1.2.3`) stay unlinked: plain text carries no
  markup saying which dotted word is a host.
- Sender and recipients read as chips (`EmailRecipientRow` +
  `EmailRecipientChip`): label, then one chip per contact carrying its avatar
  and display name. The full address is off the chip — in its tooltip, and in
  the menu a click opens, next to the copy action — so the header reads as
  names without hiding the address.
- Who a contact *is* comes from two sources, in order: the message payload,
  then the senders index (`mailSenderIndexProvider`, `GET
  /postal/addresses/senders`, keyed by the lowercase address the chip displays
  with the mail host appended). That second source is what names an address the
  message left anonymous — an address that is an alias of one of the account's
  own mailboxes arrives with `alias` set and carries the name the index knows —
  and it is where avatars come from (`emailAvatarUrl`): a picture the contact
  or their server chose, never Gravatar's stand-in for an address without a
  Gravatar account, which would say nothing about the contact. Failing both,
  the chip shows the address over the contact's initial.
- The reading pane's frame holds the same document everywhere, loaded
  differently: native platforms hand the markup over inline with the API base,
  and the browser loads it from a same-origin `blob:` URL — a frame built from
  a `data:` URL has an opaque origin, and neither the plugin's injected scroll
  listener nor this pane's own scroll calls can reach into it.
  `lib/mail/email_body_platform.{dart,native,web}.dart` carries those pieces:
  the font faces (the bundled faces over `appfont://` on native; the same
  family from Google Fonts in a browser, which has no custom schemes) and, on
  the web, `<base target="_blank">` — the plugin implements no
  `shouldOverrideUrlLoading` there, and a link left to the frame would replace
  the message with the page it points at. `web/index.html` loads the plugin's
  `web_support.js` bridge; without it the frame still renders but reports
  nothing back.
- HTML bodies are repaired for dark mode before they render
  (`withReadableEmailColors`, `lib/mail/email_contrast.dart`). A message with
  no stylesheet of its own renders on the reading pane, but its inline colours
  were chosen against a white page: a plain `color:#333` header measured 1.3:1
  on the dark pane — present, unreadable. The pass rewrites the colour
  declarations that fail WCAG AA against the surface they actually sit on,
  lifting them along their own hue until they reach 7:1; everything else is
  passed through byte for byte. Colours the sender paired with a background of
  their own, anything under a painted image, unparseable values, and messages
  that ship a stylesheet (whose cascade cannot be evaluated here) are left
  alone.
- The composer's header is one boxed field per row — from, to, (cc/bcc),
  subject — sharing `_CompactLabeledField`: the app's outlined input box, sized
  to one line plus the field's own padding so the caret sits centered instead of
  being squeezed against the top, with the label outside on the left. The
  cc/bcc toggle rides inside the To box as its suffix icon.
- Recipients are chips, not a comma-separated string:
  `_ComposeRecipientField` reuses `EmailRecipientChip` (with `onDeleted` for
  the composer's remove button) over an inline address field with the senders
  index behind it. Enter, a typed separator, a pasted list and a picked
  suggestion all commit a chip; backspace in the empty field takes the last one
  back; an address left uncommitted still goes out with the message. Each row
  carries its own role (`to`/`cc`/`bcc`) into the draft.
- Replies carry `reply_to_id`; ElecPostal resolves the parent's thread, which
  keeps the reply in the conversation. The quoted body arrives as Quill embeds,
  and the composer builds what it does not recognise
  (`_ComposeUnknownEmbed`): a quoted `<img>` renders as an image instead of
  failing the line that holds it.
- Row actions (read, star, move, delete) apply to every message of the
  conversation, since the API only mutates one message at a time.
- Trash is the one place a delete is permanent. Everywhere else the delete
  action files the conversation into Trash
  (`DELETE /postal/emails/{id}`) and stays recoverable — a second delete of
  the same mail records nothing. Inside Trash the delete confirmation changes
  to match: it goes through `DELETE /postal/emails/{id}/permanent`, which also
  drops ElecPostal's stored attachment bytes, and an "Empty trash" action
  sweeps the whole folder through `DELETE /postal/mailboxes/{id}/trash`. A
  multi-select follows the same rule, so a selection that is entirely Trash
  deletes for good and any other selection only moves there.
- Attachments read where they are listed: `CloudFileAttachmentList`
  (`lib/core/widgets/content/cloud_file_attachment_list.dart`) renders images
  and videos as in-place previews — the Drive thumbnail, sized by the file's
  own aspect ratio — and leaves documents and archives as chips. What counts
  as media comes from `effectiveMimeType` (`lib/core/utils/file_types.dart`):
  the declared MIME type, or the filename's extension when that type says
  nothing, because mail parts arrive as `application/octet-stream` (or as
  `text/plain` with no `Content-Type` at all) while the name still says
  `.jpg`. `EmlParser` applies the same rule at import time, so newly stored
  attachments carry the type their name implies.
- Attachments open where they read best, through `openCloudFile`. Images open
  in `CloudFileLightbox` (`lib/core/widgets/content/cloud_file_lightbox.dart`)
  — the Drive viewer's image content, made full screen with a swipeable
  gallery, tap-to-toggle chrome and swipe-down / Escape dismissal. Every other
  type opens the Drive file detail page (`/files/:id`), the only surface that
  can play, unpack or describe it. The mail footer, inline body images, board
  task attachments and the Drive actions sheet all route through it.


## Notifications (Ring)

SolWatt uses Solar Network’s **Ring** service (`/ring/notifications`) via the
SDK `NotificationsApi`. Ring is multi-tenant: every list/count/mark-read call
and push subscription must pass SolWatt’s app id so the client never mixes in
Solian (or other apps) traffic.

| Constant | Value |
| --- | --- |
| `kNotificationTenantAppId` | `dev.solsynth.solarwatt` (bundle / application id) |
| Island’s equivalent | `dev.solsynth.solian` |

UI: `lib/notifications/notifications.dart` — Island-style **attention modal**
(`showAttentionModal` + `AttentionModalScaffold` from island_ui_foundation),
unread badge, and `NotificationBellButton` on the desktop rail and Home page.
Open via `showNotificationsAttentionModal()` (id: `notifications`).

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

## Push notifications (Metoer subscription)

SolWatt reports a device push subscription to the **Metoer** notification
gateway so the server can reach the device when the websocket is not
connected. Registration mirrors Solian’s `subscribePushNotification`
(`lib/core/services/notify.universal.dart`) and MaidKit’s
`MaidCafePushService`:

```
PUT /metoer/notifications/subscription
{ "provider": 0|1, "device_token": "…", "device_name": "…", "app_id": "dev.solsynth.solarwatt" }
```

- `provider`: 0 = Apple APNs, 1 = Google FCM
  (`SnNotificationPushSubscriptionProvider`), matching Metoer wire values
- `app_id`: `kNotificationTenantAppId` — keeps the subscription scoped to
  SolWatt, same multi-tenant key as Ring/websocket

| Piece | Role |
| --- | --- |
| `lib/push/push_service.dart` | Registration, token refresh, background handler, system notifications |
| `solWattPushProvider` | Watched by `AppShellPage`; subscribes on sign-in (auth session listener) |
| `registerSolWattPushSubscription` | Wire contract: token + provider + `app_id` → SDK `NotificationsApi` |
| `tool/generate_firebase_options.dart` | Generates `lib/firebase_options.dart` from the platform Firebase configs |

Platform behavior:

- **Android**: FCM token, `provider: fcm`. Auto-init on.
- **iOS**: APNs token reported directly; `FirebaseMessagingAutoInitEnabled =
  NO` in `Info.plist` (no FCM token registration). The APNs token comes from
  the native registration.
- **macOS**: FCM-managed APNs registration like MaidKit (auto-init re-enabled
  at registration time).
- **Linux / Windows / web**: no firebase_core support — the in-app Metoer
  feed over the websocket is the only notification surface.

Foreground pushes surface through the websocket in-app feed
(`notifications.new`); the FCM handler only shows a system notification for
background/cold-start delivery (Android data messages), avoiding duplication
while the app is focused. The push service degrades gracefully when the
Firebase configs are missing (init is skipped, status `unavailable`).

## GitHub App task sync

Boards can link **one** GitHub repository via the WattEngine Ideask GitHub App
(see WattEngine `docs/GITHUB_APP_TASK_SYNC.md`). SolWatt never collects
personal access tokens; users install the app and pick a repository.

Client flow (`lib/boards/github_integration.dart`):

1. `GET /ideask/github/broads/{id}/install-url` → open in browser
2. Poll `GET …/installation` until an installation id is available
3. List `…/installations/{id}/repositories` and link with `POST …/broads/{id}`
4. Manage with status `GET`, manual `POST …/sync`, and `DELETE` unlink

Linked tasks carry the issue in their card meta line. The task editor opens the
issue URL and hosts comments (`task_comments.dart`); GitHub-authored comments
are read-only.

### Board screen conventions

A board is a lane per group (plus a leading `Ungrouped` lane) laid out
horizontally. Colour on the board is deliberate and narrow:

- **Lane colour** (`_laneColor`, rotated by lane position) marks the lane rail
  and its done/total meter. It is the only colour that identifies *where* a
  task is.
- **Card attention rail** is the only colour on a card and means the task wants
  attention: overdue (error), urgent/high (their priority tone). A card with no
  rail is a normal task — absence is information, do not fill it with a default
  chip.
- Facts that hold a default value (normal priority, no deadline, no tags) are
  omitted from the card's meta line rather than printed as "None".
- Lanes own vertical scrolling; cards are lane drag sources and must keep
  `Draggable.affinity: Axis.horizontal` so a vertical drag still reaches the
  lane's list.

## Validation

Run these before handing off changes:

```sh
dart format lib
dart run build_runner build
flutter analyze
# Run this once logic tests have been added under test/.
flutter test
```
