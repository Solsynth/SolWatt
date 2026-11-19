import 'package:flutter/foundation.dart';

import 'package:solwatt/workspace/workspace_models.dart';

enum PageBlockType {
  paragraph,
  heading1,
  heading2,
  todo,
  bullet,
  entityEmbed;

  String get label => switch (this) {
    PageBlockType.paragraph => 'Text',
    PageBlockType.heading1 => 'Heading 1',
    PageBlockType.heading2 => 'Heading 2',
    PageBlockType.todo => 'To-do',
    PageBlockType.bullet => 'Bullet',
    PageBlockType.entityEmbed => 'Embed',
  };
}

@immutable
class PageBlock {
  final String id;
  final PageBlockType type;
  final String text;
  final bool checked;
  final WorkspaceEntityRef? embeddedEntity;

  const PageBlock({
    required this.id,
    required this.type,
    this.text = '',
    this.checked = false,
    this.embeddedEntity,
  });

  PageBlock copyWith({
    String? id,
    PageBlockType? type,
    String? text,
    bool? checked,
    WorkspaceEntityRef? embeddedEntity,
  }) {
    return PageBlock(
      id: id ?? this.id,
      type: type ?? this.type,
      text: text ?? this.text,
      checked: checked ?? this.checked,
      embeddedEntity: embeddedEntity ?? this.embeddedEntity,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'text': text,
    'checked': checked,
    if (embeddedEntity != null) 'embeddedEntity': embeddedEntity!.toJson(),
  };

  factory PageBlock.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? 'paragraph';
    final type = PageBlockType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => PageBlockType.paragraph,
    );
    return PageBlock(
      id: json['id'] as String? ?? '',
      type: type,
      text: json['text'] as String? ?? '',
      checked: json['checked'] as bool? ?? false,
      embeddedEntity: json['embeddedEntity'] is Map
          ? WorkspaceEntityRef.fromJson(
              (json['embeddedEntity'] as Map).cast<String, dynamic>(),
            )
          : null,
    );
  }
}

@immutable
class WorkspacePageDoc {
  final String id;
  final String workspaceKey;
  final String? parentId;
  final String title;
  final String icon;
  final DateTime updatedAt;
  final List<PageBlock> blocks;
  final List<WorkspaceEntityRef> mentions;
  final bool commentsResolved;

  const WorkspacePageDoc({
    required this.id,
    required this.workspaceKey,
    this.parentId,
    required this.title,
    this.icon = '📄',
    required this.updatedAt,
    this.blocks = const [],
    this.mentions = const [],
    this.commentsResolved = false,
  });

  WorkspaceEntityRef toEntityRef() => WorkspaceEntityRef(
    id: id,
    domain: WorkspaceDomain.pages,
    title: title.isEmpty ? 'Untitled Page' : title,
    subtitle: blocks.isNotEmpty ? blocks.first.text : 'Workspace Page',
    status: commentsResolved ? 'Resolved' : null,
  );

  WorkspacePageDoc copyWith({
    String? id,
    String? workspaceKey,
    String? parentId,
    String? title,
    String? icon,
    DateTime? updatedAt,
    List<PageBlock>? blocks,
    List<WorkspaceEntityRef>? mentions,
    bool? commentsResolved,
  }) {
    return WorkspacePageDoc(
      id: id ?? this.id,
      workspaceKey: workspaceKey ?? this.workspaceKey,
      parentId: parentId ?? this.parentId,
      title: title ?? this.title,
      icon: icon ?? this.icon,
      updatedAt: updatedAt ?? this.updatedAt,
      blocks: blocks ?? this.blocks,
      mentions: mentions ?? this.mentions,
      commentsResolved: commentsResolved ?? this.commentsResolved,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'workspaceKey': workspaceKey,
    if (parentId != null) 'parentId': parentId,
    'title': title,
    'icon': icon,
    'updatedAt': updatedAt.toIso8601String(),
    'blocks': blocks.map((b) => b.toJson()).toList(),
    'mentions': mentions.map((m) => m.toJson()).toList(),
    'commentsResolved': commentsResolved,
  };

  factory WorkspacePageDoc.fromJson(Map<String, dynamic> json) {
    return WorkspacePageDoc(
      id: json['id'] as String? ?? '',
      workspaceKey: json['workspaceKey'] as String? ?? 'default',
      parentId: json['parentId'] as String?,
      title: json['title'] as String? ?? 'Untitled Page',
      icon: json['icon'] as String? ?? '📄',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      blocks: (json['blocks'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((m) => PageBlock.fromJson(m.cast<String, dynamic>()))
          .toList(),
      mentions: (json['mentions'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((m) => WorkspaceEntityRef.fromJson(m.cast<String, dynamic>()))
          .toList(),
      commentsResolved: json['commentsResolved'] as bool? ?? false,
    );
  }
}
