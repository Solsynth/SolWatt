import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The four core productivity domains in the unified workspace.
enum WorkspaceDomain {
  mail,
  todo,
  pages,
  drive;

  String get label => switch (this) {
    WorkspaceDomain.mail => 'Mail',
    WorkspaceDomain.todo => 'Todo',
    WorkspaceDomain.pages => 'Pages',
    WorkspaceDomain.drive => 'Drive',
  };

  String get filterChipLabel => switch (this) {
    WorkspaceDomain.mail => 'in:mail',
    WorkspaceDomain.todo => 'in:tasks',
    WorkspaceDomain.pages => 'in:pages',
    WorkspaceDomain.drive => 'in:drive',
  };

  IconData get icon => switch (this) {
    WorkspaceDomain.mail => Symbols.mail_rounded,
    WorkspaceDomain.todo => Symbols.check_box_rounded,
    WorkspaceDomain.pages => Symbols.article_rounded,
    WorkspaceDomain.drive => Symbols.folder_rounded,
  };

  Color accentColor(ColorScheme scheme) => switch (this) {
    WorkspaceDomain.mail => scheme.primary,
    WorkspaceDomain.todo => scheme.tertiary,
    WorkspaceDomain.pages => scheme.secondary,
    WorkspaceDomain.drive => scheme.primaryContainer,
  };
}

/// Top-level lenses inside [AdaptiveWorkspaceShell].
///
/// Ideask serves boards and pages from one tree, so they share one lens: the
/// Todo lens lists both and opens either as its own document.
enum WorkspaceLens {
  today,
  mail,
  todo,
  drive,
  flywheel,
  profile,
  settings;

  String get label => switch (this) {
    WorkspaceLens.today => 'Today',
    WorkspaceLens.mail => 'Mail',
    WorkspaceLens.todo => 'Todo',
    WorkspaceLens.drive => 'Drive',
    WorkspaceLens.flywheel => 'Flywheel',
    WorkspaceLens.profile => 'Profile',
    WorkspaceLens.settings => 'Settings',
  };

  IconData get icon => switch (this) {
    WorkspaceLens.today => Symbols.star_rounded,
    WorkspaceLens.mail => Symbols.mail_rounded,
    WorkspaceLens.todo => Symbols.check_box_rounded,
    WorkspaceLens.drive => Symbols.cloud_rounded,
    WorkspaceLens.flywheel => Symbols.bolt_rounded,
    WorkspaceLens.profile => Symbols.person_rounded,
    WorkspaceLens.settings => Symbols.settings_rounded,
  };

  WorkspaceDomain? get domain => switch (this) {
    WorkspaceLens.mail => WorkspaceDomain.mail,
    WorkspaceLens.todo => WorkspaceDomain.todo,
    WorkspaceLens.drive => WorkspaceDomain.drive,
    _ => null,
  };

  /// Generated route name of the lens' page, as listed in [AppShellPage].
  String get routeName => switch (this) {
    WorkspaceLens.today => 'TodayFocusRoute',
    WorkspaceLens.mail => 'MailRoute',
    WorkspaceLens.todo => 'BoardsRoute',
    WorkspaceLens.drive => 'FileListRoute',
    WorkspaceLens.flywheel => 'FlywheelRoute',
    WorkspaceLens.profile => 'ProfileRoute',
    WorkspaceLens.settings => 'AppSettingsRoute',
  };
}

/// Polymorphic cross-domain entity reference used by [EntityPill],
/// [EntityCard], [RelatedItemsStrip], [PeekSurface], and [PinnedItemsNotifier].
@immutable
class WorkspaceEntityRef {
  final String id;
  final WorkspaceDomain domain;
  final String title;
  final String? subtitle;
  final String? status;
  final bool isCompleted;
  final bool isAttachment;
  final bool isSavedToDrive;
  final String? badgeText;
  final String? mimeType;
  final int? byteSize;
  final Map<String, dynamic> metadata;

  const WorkspaceEntityRef({
    required this.id,
    required this.domain,
    required this.title,
    this.subtitle,
    this.status,
    this.isCompleted = false,
    this.isAttachment = false,
    this.isSavedToDrive = true,
    this.badgeText,
    this.mimeType,
    this.byteSize,
    this.metadata = const {},
  });

  String get key => '${domain.name}:$id';

  WorkspaceEntityRef copyWith({
    String? id,
    WorkspaceDomain? domain,
    String? title,
    String? subtitle,
    String? status,
    bool? isCompleted,
    bool? isAttachment,
    bool? isSavedToDrive,
    String? badgeText,
    String? mimeType,
    int? byteSize,
    Map<String, dynamic>? metadata,
  }) {
    return WorkspaceEntityRef(
      id: id ?? this.id,
      domain: domain ?? this.domain,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      status: status ?? this.status,
      isCompleted: isCompleted ?? this.isCompleted,
      isAttachment: isAttachment ?? this.isAttachment,
      isSavedToDrive: isSavedToDrive ?? this.isSavedToDrive,
      badgeText: badgeText ?? this.badgeText,
      mimeType: mimeType ?? this.mimeType,
      byteSize: byteSize ?? this.byteSize,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'domain': domain.name,
    'title': title,
    if (subtitle != null) 'subtitle': subtitle,
    if (status != null) 'status': status,
    'isCompleted': isCompleted,
    'isAttachment': isAttachment,
    'isSavedToDrive': isSavedToDrive,
    if (badgeText != null) 'badgeText': badgeText,
    if (mimeType != null) 'mimeType': mimeType,
    if (byteSize != null) 'byteSize': byteSize,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  factory WorkspaceEntityRef.fromJson(Map<String, dynamic> json) {
    final domainName = json['domain'] as String? ?? 'pages';
    final domain = WorkspaceDomain.values.firstWhere(
      (d) => d.name == domainName,
      orElse: () => WorkspaceDomain.pages,
    );
    return WorkspaceEntityRef(
      id: json['id'] as String? ?? '',
      domain: domain,
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String?,
      status: json['status'] as String?,
      isCompleted: json['isCompleted'] as bool? ?? false,
      isAttachment: json['isAttachment'] as bool? ?? false,
      isSavedToDrive: json['isSavedToDrive'] as bool? ?? true,
      badgeText: json['badgeText'] as String?,
      mimeType: json['mimeType'] as String?,
      byteSize: json['byteSize'] as int?,
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceEntityRef &&
          id == other.id &&
          domain == other.domain &&
          title == other.title &&
          isCompleted == other.isCompleted &&
          isSavedToDrive == other.isSavedToDrive;

  @override
  int get hashCode =>
      Object.hash(id, domain, title, isCompleted, isSavedToDrive);
}

/// A cross-domain link between two entities for [RelatedItemsStrip].
@immutable
class CrossDomainLink {
  final WorkspaceEntityRef source;
  final WorkspaceEntityRef target;

  const CrossDomainLink({required this.source, required this.target});

  Map<String, dynamic> toJson() => {
    'source': source.toJson(),
    'target': target.toJson(),
  };

  factory CrossDomainLink.fromJson(Map<String, dynamic> json) =>
      CrossDomainLink(
        source: WorkspaceEntityRef.fromJson(
          (json['source'] as Map).cast<String, dynamic>(),
        ),
        target: WorkspaceEntityRef.fromJson(
          (json['target'] as Map).cast<String, dynamic>(),
        ),
      );
}
