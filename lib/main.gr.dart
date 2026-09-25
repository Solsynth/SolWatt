// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

part of 'main.dart';

/// generated route for
/// [AppShellPage]
class AppShellRoute extends PageRouteInfo<void> {
  const AppShellRoute({List<PageRouteInfo>? children})
    : super(AppShellRoute.name, initialChildren: children);

  static const String name = 'AppShellRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const AppShellPage();
    },
  );
}

/// generated route for
/// [BoardsPage]
class BoardsRoute extends PageRouteInfo<void> {
  const BoardsRoute({List<PageRouteInfo>? children})
    : super(BoardsRoute.name, initialChildren: children);

  static const String name = 'BoardsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const BoardsPage();
    },
  );
}

/// generated route for
/// [FilesPage]
class FilesRoute extends PageRouteInfo<void> {
  const FilesRoute({List<PageRouteInfo>? children})
    : super(FilesRoute.name, initialChildren: children);

  static const String name = 'FilesRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const FilesPage();
    },
  );
}

/// generated route for
/// [FlywheelPage]
class FlywheelRoute extends PageRouteInfo<void> {
  const FlywheelRoute({List<PageRouteInfo>? children})
    : super(FlywheelRoute.name, initialChildren: children);

  static const String name = 'FlywheelRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const FlywheelPage();
    },
  );
}

/// generated route for
/// [GatePage]
class GateRoute extends PageRouteInfo<void> {
  const GateRoute({List<PageRouteInfo>? children})
    : super(GateRoute.name, initialChildren: children);

  static const String name = 'GateRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const GatePage();
    },
  );
}

/// generated route for
/// [MailComposePage]
class MailComposeRoute extends PageRouteInfo<MailComposeRouteArgs> {
  MailComposeRoute({
    Key? key,
    String? replyToId,
    bool replyAll = false,
    String? forwardId,
    List<PageRouteInfo>? children,
  }) : super(
         MailComposeRoute.name,
         args: MailComposeRouteArgs(
           key: key,
           replyToId: replyToId,
           replyAll: replyAll,
           forwardId: forwardId,
         ),
         rawQueryParams: {
           'replyTo': replyToId,
           'replyAll': replyAll,
           'forward': forwardId,
         },
         initialChildren: children,
       );

  static const String name = 'MailComposeRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final queryParams = data.queryParams;
      final args = data.argsAs<MailComposeRouteArgs>(
        orElse: () => MailComposeRouteArgs(
          replyToId: queryParams.optString('replyTo'),
          replyAll: queryParams.getBool('replyAll', false),
          forwardId: queryParams.optString('forward'),
        ),
      );
      return MailComposePage(
        key: args.key,
        replyToId: args.replyToId,
        replyAll: args.replyAll,
        forwardId: args.forwardId,
      );
    },
  );
}

class MailComposeRouteArgs {
  const MailComposeRouteArgs({
    this.key,
    this.replyToId,
    this.replyAll = false,
    this.forwardId,
  });

  final Key? key;

  final String? replyToId;

  final bool replyAll;

  final String? forwardId;

  @override
  String toString() {
    return 'MailComposeRouteArgs{key: $key, replyToId: $replyToId, replyAll: $replyAll, forwardId: $forwardId}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MailComposeRouteArgs) return false;
    return key == other.key &&
        replyToId == other.replyToId &&
        replyAll == other.replyAll &&
        forwardId == other.forwardId;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      replyToId.hashCode ^
      replyAll.hashCode ^
      forwardId.hashCode;
}

/// generated route for
/// [MailDetailPage]
class MailDetailRoute extends PageRouteInfo<MailDetailRouteArgs> {
  MailDetailRoute({
    Key? key,
    required String emailId,
    List<PageRouteInfo>? children,
  }) : super(
         MailDetailRoute.name,
         args: MailDetailRouteArgs(key: key, emailId: emailId),
         rawPathParams: {'id': emailId},
         initialChildren: children,
       );

  static const String name = 'MailDetailRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<MailDetailRouteArgs>(
        orElse: () => MailDetailRouteArgs(emailId: pathParams.getString('id')),
      );
      return MailDetailPage(key: args.key, emailId: args.emailId);
    },
  );
}

class MailDetailRouteArgs {
  const MailDetailRouteArgs({this.key, required this.emailId});

  final Key? key;

  final String emailId;

  @override
  String toString() {
    return 'MailDetailRouteArgs{key: $key, emailId: $emailId}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MailDetailRouteArgs) return false;
    return key == other.key && emailId == other.emailId;
  }

  @override
  int get hashCode => key.hashCode ^ emailId.hashCode;
}

/// generated route for
/// [MailListPage]
class MailListRoute extends PageRouteInfo<void> {
  const MailListRoute({List<PageRouteInfo>? children})
    : super(MailListRoute.name, initialChildren: children);

  static const String name = 'MailListRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const MailListPage();
    },
  );
}

/// generated route for
/// [MailPage]
class MailRoute extends PageRouteInfo<void> {
  const MailRoute({List<PageRouteInfo>? children})
    : super(MailRoute.name, initialChildren: children);

  static const String name = 'MailRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const MailPage();
    },
  );
}

/// generated route for
/// [ProfilePage]
class ProfileRoute extends PageRouteInfo<void> {
  const ProfileRoute({List<PageRouteInfo>? children})
    : super(ProfileRoute.name, initialChildren: children);

  static const String name = 'ProfileRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const ProfilePage();
    },
  );
}

/// generated route for
/// [SettingsPage]
class SettingsRoute extends PageRouteInfo<void> {
  const SettingsRoute({List<PageRouteInfo>? children})
    : super(SettingsRoute.name, initialChildren: children);

  static const String name = 'SettingsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const SettingsPage();
    },
  );
}

/// generated route for
/// [TaskBoardPage]
class TaskBoardRoute extends PageRouteInfo<TaskBoardRouteArgs> {
  TaskBoardRoute({
    Key? key,
    required String broadId,
    required String broadName,
    List<PageRouteInfo>? children,
  }) : super(
         TaskBoardRoute.name,
         args: TaskBoardRouteArgs(
           key: key,
           broadId: broadId,
           broadName: broadName,
         ),
         rawPathParams: {'broadId': broadId},
         initialChildren: children,
       );

  static const String name = 'TaskBoardRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<TaskBoardRouteArgs>();
      return TaskBoardPage(
        key: args.key,
        broadId: args.broadId,
        broadName: args.broadName,
      );
    },
  );
}

class TaskBoardRouteArgs {
  const TaskBoardRouteArgs({
    this.key,
    required this.broadId,
    required this.broadName,
  });

  final Key? key;

  final String broadId;

  final String broadName;

  @override
  String toString() {
    return 'TaskBoardRouteArgs{key: $key, broadId: $broadId, broadName: $broadName}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TaskBoardRouteArgs) return false;
    return key == other.key &&
        broadId == other.broadId &&
        broadName == other.broadName;
  }

  @override
  int get hashCode => key.hashCode ^ broadId.hashCode ^ broadName.hashCode;
}
