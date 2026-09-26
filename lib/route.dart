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
        AutoRoute(page: BoardsRoute.page),
        AutoRoute(page: FileListRoute.page),
        AutoRoute(page: FlywheelRoute.page),
        AutoRoute(page: TaskBoardRoute.page),
        AutoRoute(page: ProfileRoute.page),
      ],
    ),
  ];
}
