import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:solwatt/ideask/ideask_page.dart';
import 'package:solwatt/ideask/task_list_page.dart';
import 'package:solwatt/drive/files/file_detail.dart';
import 'package:solwatt/drive/files/file_list.dart';
import 'package:solwatt/gate/gate_page.dart';
import 'package:solwatt/mail/mail_screen.dart';
import 'package:solwatt/mail/mail_settings_page.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/settings/about_page.dart';
import 'package:solwatt/settings/app_settings_page.dart';
import 'package:solwatt/workspaces/workspace_detail_screen.dart';
import 'package:solwatt/workspaces/workspace_management_screen.dart';

part 'route.gr.dart';

/// Single router instance shared by the app shell and any code that needs to
/// navigate without a [BuildContext] (e.g. the drive's background uploads).
final appRouter = AppRouter();

final routerProvider = Provider<AppRouter>((ref) => appRouter);

@AutoRouterConfig(replaceInRouteName: 'Page|Screen,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: GateRoute.page, initial: true),
    AutoRoute(page: FileDetailRoute.page, path: '/files/:id'),
    // Workspace console: the registry list and the per-workspace detail.
    // Top-level (outside the shell) so either page covers the tab bar.
    AutoRoute(page: WorkspaceManagementRoute.page, path: '/workspaces'),
    AutoRoute(page: WorkspaceDetailRoute.page, path: '/workspaces/:slug'),
    AutoRoute(
      page: AppShellRoute.page,
      children: [
        AutoRoute(
          page: MailRoute.page,
          initial: true,
          children: [
            AutoRoute(page: MailListRoute.page, path: '', initial: true),
            AutoRoute(page: MailSettingsRoute.page, path: 'settings'),
            AutoRoute(page: MailComposeRoute.page, path: 'compose'),
            AutoRoute(page: MailDetailRoute.page, path: ':id'),
          ],
        ),
        // The Todo tab owns a nested stack: the Ideask browser is the root, and
        // a folder's task list or a collection is pushed on top of it. Pages
        // are documents of the workspace strip instead — the strip lists every
        // open one and the lens shows the active page — so they have no route.
        AutoRoute(
          page: IdeaskLensRoute.page,
          children: [
            AutoRoute(page: IdeaskBrowserRoute.page, path: '', initial: true),
            AutoRoute(page: TaskListRoute.page, path: 'tasks'),
            AutoRoute(
              page: CollectionRoute.page,
              path: 'collection/:collectionId',
            ),
          ],
        ),
        AutoRoute(page: FileListRoute.page),
        AutoRoute(page: ProfileRoute.page),
        // Settings is a top-level destination of its own. It used to be pushed
        // onto the profile tab, which buried an app-wide page inside the
        // account tab; About is its child now.
        AutoRoute(
          page: AppSettingsRoute.page,
          children: [
            AutoRoute(page: AppSettingsHomeRoute.page, path: '', initial: true),
            AutoRoute(page: AboutRoute.page, path: 'about'),
          ],
        ),
      ],
    ),
  ];
}
