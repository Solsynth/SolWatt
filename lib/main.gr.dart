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
/// [HomePage]
class HomeRoute extends PageRouteInfo<void> {
  const HomeRoute({List<PageRouteInfo>? children})
    : super(HomeRoute.name, initialChildren: children);

  static const String name = 'HomeRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const HomePage();
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
