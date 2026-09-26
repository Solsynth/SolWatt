// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

part of 'route.dart';

/// generated route for
/// [AboutPage]
class AboutRoute extends PageRouteInfo<void> {
  const AboutRoute({List<PageRouteInfo>? children})
    : super(AboutRoute.name, initialChildren: children);

  static const String name = 'AboutRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const AboutPage();
    },
  );
}

/// generated route for
/// [AppSettingsPage]
class AppSettingsRoute extends PageRouteInfo<void> {
  const AppSettingsRoute({List<PageRouteInfo>? children})
    : super(AppSettingsRoute.name, initialChildren: children);

  static const String name = 'AppSettingsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const AppSettingsPage();
    },
  );
}

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
/// [BoardsListPage]
class BoardsListRoute extends PageRouteInfo<void> {
  const BoardsListRoute({List<PageRouteInfo>? children})
    : super(BoardsListRoute.name, initialChildren: children);

  static const String name = 'BoardsListRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const BoardsListPage();
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
/// [FileDetailScreen]
class FileDetailRoute extends PageRouteInfo<FileDetailRouteArgs> {
  FileDetailRoute({
    Key? key,
    required String id,
    String? heroTag,
    List<PageRouteInfo>? children,
  }) : super(
         FileDetailRoute.name,
         args: FileDetailRouteArgs(key: key, id: id, heroTag: heroTag),
         initialChildren: children,
       );

  static const String name = 'FileDetailRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<FileDetailRouteArgs>();
      return FileDetailScreen(
        key: args.key,
        id: args.id,
        heroTag: args.heroTag,
      );
    },
  );
}

class FileDetailRouteArgs {
  const FileDetailRouteArgs({this.key, required this.id, this.heroTag});

  final Key? key;

  final String id;

  final String? heroTag;

  @override
  String toString() {
    return 'FileDetailRouteArgs{key: $key, id: $id, heroTag: $heroTag}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FileDetailRouteArgs) return false;
    return key == other.key && id == other.id && heroTag == other.heroTag;
  }

  @override
  int get hashCode => key.hashCode ^ id.hashCode ^ heroTag.hashCode;
}

/// generated route for
/// [FileListScreen]
class FileListRoute extends PageRouteInfo<void> {
  const FileListRoute({List<PageRouteInfo>? children})
    : super(FileListRoute.name, initialChildren: children);

  static const String name = 'FileListRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const FileListScreen();
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
/// [MailSettingsPage]
class MailSettingsRoute extends PageRouteInfo<void> {
  const MailSettingsRoute({List<PageRouteInfo>? children})
    : super(MailSettingsRoute.name, initialChildren: children);

  static const String name = 'MailSettingsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const MailSettingsPage();
    },
  );
}

/// generated route for
/// [ProfileHomePage]
class ProfileHomeRoute extends PageRouteInfo<void> {
  const ProfileHomeRoute({List<PageRouteInfo>? children})
    : super(ProfileHomeRoute.name, initialChildren: children);

  static const String name = 'ProfileHomeRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const ProfileHomePage();
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
/// [TaskBoardPage]
class TaskBoardRoute extends PageRouteInfo<TaskBoardRouteArgs> {
  TaskBoardRoute({
    Key? key,
    required String broadId,
    List<PageRouteInfo>? children,
  }) : super(
         TaskBoardRoute.name,
         args: TaskBoardRouteArgs(key: key, broadId: broadId),
         rawPathParams: {'broadId': broadId},
         initialChildren: children,
       );

  static const String name = 'TaskBoardRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<TaskBoardRouteArgs>(
        orElse: () =>
            TaskBoardRouteArgs(broadId: pathParams.getString('broadId')),
      );
      return TaskBoardPage(key: args.key, broadId: args.broadId);
    },
  );
}

class TaskBoardRouteArgs {
  const TaskBoardRouteArgs({this.key, required this.broadId});

  final Key? key;

  final String broadId;

  @override
  String toString() {
    return 'TaskBoardRouteArgs{key: $key, broadId: $broadId}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TaskBoardRouteArgs) return false;
    return key == other.key && broadId == other.broadId;
  }

  @override
  int get hashCode => key.hashCode ^ broadId.hashCode;
}
