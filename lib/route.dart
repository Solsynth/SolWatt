import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:solwatt/boards/boards_screen.dart';
import 'package:solwatt/drive/files/file_detail.dart';
import 'package:solwatt/drive/files/file_list.dart';
import 'package:solwatt/flywheel/flywheel_page.dart';
import 'package:solwatt/gate/gate_page.dart';
import 'package:solwatt/mail/mail_screen.dart';
import 'package:solwatt/mail/mail_settings_page.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/settings/about_page.dart';
import 'package:solwatt/settings/app_settings_page.dart';

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
        // The boards tab owns a nested stack: the board list is the root and
        // a single board is pushed on top of it, so opening a board keeps the
        // app shell (navigation rail / bottom bar) in place and returns to the
        // list it came from.
        AutoRoute(
          page: BoardsRoute.page,
          children: [
            AutoRoute(page: BoardsListRoute.page, path: '', initial: true),
            AutoRoute(page: TaskBoardRoute.page, path: ':broadId'),
          ],
        ),
        AutoRoute(page: FileListRoute.page),
        AutoRoute(page: FlywheelRoute.page),
        AutoRoute(
          page: ProfileRoute.page,
          children: [
            AutoRoute(page: ProfileHomeRoute.page, path: '', initial: true),
            AutoRoute(page: AppSettingsRoute.page, path: 'settings'),
            AutoRoute(page: AboutRoute.page, path: 'about'),
          ],
        ),
      ],
    ),
  ];
}
