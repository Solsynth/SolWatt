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
/// [AppSettingsHomePage]
class AppSettingsHomeRoute extends PageRouteInfo<void> {
  const AppSettingsHomeRoute({List<PageRouteInfo>? children})
    : super(AppSettingsHomeRoute.name, initialChildren: children);

  static const String name = 'AppSettingsHomeRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const AppSettingsHomePage();
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
/// [CollectionPage]
class CollectionRoute extends PageRouteInfo<CollectionRouteArgs> {
  CollectionRoute({
    Key? key,
    required String collectionId,
    List<PageRouteInfo>? children,
  }) : super(
         CollectionRoute.name,
         args: CollectionRouteArgs(key: key, collectionId: collectionId),
         rawPathParams: {'collectionId': collectionId},
         initialChildren: children,
       );

  static const String name = 'CollectionRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<CollectionRouteArgs>(
        orElse: () => CollectionRouteArgs(
          collectionId: pathParams.getString('collectionId'),
        ),
      );
      return CollectionPage(key: args.key, collectionId: args.collectionId);
    },
  );
}

class CollectionRouteArgs {
  const CollectionRouteArgs({this.key, required this.collectionId});

  final Key? key;

  final String collectionId;

  @override
  String toString() {
    return 'CollectionRouteArgs{key: $key, collectionId: $collectionId}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CollectionRouteArgs) return false;
    return key == other.key && collectionId == other.collectionId;
  }

  @override
  int get hashCode => key.hashCode ^ collectionId.hashCode;
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
/// [IdeaskBrowserPage]
class IdeaskBrowserRoute extends PageRouteInfo<void> {
  const IdeaskBrowserRoute({List<PageRouteInfo>? children})
    : super(IdeaskBrowserRoute.name, initialChildren: children);

  static const String name = 'IdeaskBrowserRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const IdeaskBrowserPage();
    },
  );
}

/// generated route for
/// [IdeaskLensPage]
class IdeaskLensRoute extends PageRouteInfo<void> {
  const IdeaskLensRoute({List<PageRouteInfo>? children})
    : super(IdeaskLensRoute.name, initialChildren: children);

  static const String name = 'IdeaskLensRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const IdeaskLensPage();
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
    String? draftId,
    List<PageRouteInfo>? children,
  }) : super(
         MailComposeRoute.name,
         args: MailComposeRouteArgs(
           key: key,
           replyToId: replyToId,
           replyAll: replyAll,
           forwardId: forwardId,
           draftId: draftId,
         ),
         rawQueryParams: {
           'replyTo': replyToId,
           'replyAll': replyAll,
           'forward': forwardId,
           'draft': draftId,
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
          draftId: queryParams.optString('draft'),
        ),
      );
      return MailComposePage(
        key: args.key,
        replyToId: args.replyToId,
        replyAll: args.replyAll,
        forwardId: args.forwardId,
        draftId: args.draftId,
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
    this.draftId,
  });

  final Key? key;

  final String? replyToId;

  final bool replyAll;

  final String? forwardId;

  final String? draftId;

  @override
  String toString() {
    return 'MailComposeRouteArgs{key: $key, replyToId: $replyToId, replyAll: $replyAll, forwardId: $forwardId, draftId: $draftId}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MailComposeRouteArgs) return false;
    return key == other.key &&
        replyToId == other.replyToId &&
        replyAll == other.replyAll &&
        forwardId == other.forwardId &&
        draftId == other.draftId;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      replyToId.hashCode ^
      replyAll.hashCode ^
      forwardId.hashCode ^
      draftId.hashCode;
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
/// [TaskListPage]
class TaskListRoute extends PageRouteInfo<TaskListRouteArgs> {
  TaskListRoute({
    Key? key,
    String? folderId,
    bool unfiled = false,
    List<PageRouteInfo>? children,
  }) : super(
         TaskListRoute.name,
         args: TaskListRouteArgs(
           key: key,
           folderId: folderId,
           unfiled: unfiled,
         ),
         rawQueryParams: {'folderId': folderId, 'unfiled': unfiled},
         initialChildren: children,
       );

  static const String name = 'TaskListRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final queryParams = data.queryParams;
      final args = data.argsAs<TaskListRouteArgs>(
        orElse: () => TaskListRouteArgs(
          folderId: queryParams.optString('folderId'),
          unfiled: queryParams.getBool('unfiled', false),
        ),
      );
      return TaskListPage(
        key: args.key,
        folderId: args.folderId,
        unfiled: args.unfiled,
      );
    },
  );
}

class TaskListRouteArgs {
  const TaskListRouteArgs({this.key, this.folderId, this.unfiled = false});

  final Key? key;

  final String? folderId;

  final bool unfiled;

  @override
  String toString() {
    return 'TaskListRouteArgs{key: $key, folderId: $folderId, unfiled: $unfiled}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TaskListRouteArgs) return false;
    return key == other.key &&
        folderId == other.folderId &&
        unfiled == other.unfiled;
  }

  @override
  int get hashCode => key.hashCode ^ folderId.hashCode ^ unfiled.hashCode;
}

/// generated route for
/// [WorkspaceDetailPage]
class WorkspaceDetailRoute extends PageRouteInfo<WorkspaceDetailRouteArgs> {
  WorkspaceDetailRoute({
    Key? key,
    required String slug,
    List<PageRouteInfo>? children,
  }) : super(
         WorkspaceDetailRoute.name,
         args: WorkspaceDetailRouteArgs(key: key, slug: slug),
         rawPathParams: {'slug': slug},
         initialChildren: children,
       );

  static const String name = 'WorkspaceDetailRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<WorkspaceDetailRouteArgs>(
        orElse: () =>
            WorkspaceDetailRouteArgs(slug: pathParams.getString('slug')),
      );
      return WorkspaceDetailPage(key: args.key, slug: args.slug);
    },
  );
}

class WorkspaceDetailRouteArgs {
  const WorkspaceDetailRouteArgs({this.key, required this.slug});

  final Key? key;

  final String slug;

  @override
  String toString() {
    return 'WorkspaceDetailRouteArgs{key: $key, slug: $slug}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! WorkspaceDetailRouteArgs) return false;
    return key == other.key && slug == other.slug;
  }

  @override
  int get hashCode => key.hashCode ^ slug.hashCode;
}

/// generated route for
/// [WorkspaceManagementPage]
class WorkspaceManagementRoute extends PageRouteInfo<void> {
  const WorkspaceManagementRoute({List<PageRouteInfo>? children})
    : super(WorkspaceManagementRoute.name, initialChildren: children);

  static const String name = 'WorkspaceManagementRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const WorkspaceManagementPage();
    },
  );
}
