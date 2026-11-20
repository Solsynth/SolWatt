import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/theme.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_state.dart';

/// Full-width interactive block card inside Pages, Mail bodies, Mail
/// attachments, Drive previews, or Peek drawers.
///
/// Mail attachments and Drive files render with this exact same [EntityCard]
/// layout; unsaved Mail attachments show a subtle `Attachment` badge alongside
/// a 1-tap `Save to Drive` button without altering the card structure.
class EntityCard extends ConsumerWidget {
  final WorkspaceEntityRef entity;
  final VoidCallback? onTap;
  final VoidCallback? onToggleComplete;
  final VoidCallback? onSaveToDrive;
  final VoidCallback? onDownloadOrPreview;
  final bool compact;

  const EntityCard({
    super.key,
    required this.entity,
    this.onTap,
    this.onToggleComplete,
    this.onSaveToDrive,
    this.onDownloadOrPreview,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final savedAttachments = ref.watch(savedAttachmentIdsProvider);
    final isSaved =
        entity.isSavedToDrive || savedAttachments.contains(entity.id);
    final showAttachmentBadge =
        entity.domain == WorkspaceDomain.drive &&
        entity.isAttachment &&
        !isSaved;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SolRadius.sm),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(SolRadius.sm),
        onTap: onTap ?? () => ref.read(peekProvider.notifier).open(entity),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: SolSpace.md,
            vertical: compact ? SolSpace.sm : SolSpace.md,
          ),
          child: Row(
            children: [
              _buildLeading(context, scheme),
              const SizedBox(width: SolSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entity.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  decoration: entity.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                          ),
                        ),
                        if (showAttachmentBadge) ...[
                          const SizedBox(width: SolSpace.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(SolRadius.xs),
                            ),
                            child: Text(
                              'Attachment',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: scheme.onSecondaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ] else if (entity.badgeText != null) ...[
                          const SizedBox(width: SolSpace.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(SolRadius.xs),
                            ),
                            child: Text(
                              entity.badgeText!,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_buildSubtitleText() case final sub?) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: SolSpace.sm),
              ..._buildTrailingActions(context, ref, scheme, isSaved),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeading(BuildContext context, ColorScheme scheme) {
    if (entity.domain == WorkspaceDomain.todo) {
      return InkResponse(
        onTap: onToggleComplete,
        radius: 18,
        child: Icon(
          entity.isCompleted
              ? Symbols.check_box_rounded
              : Symbols.check_box_outline_blank_rounded,
          color: entity.isCompleted ? scheme.primary : scheme.onSurfaceVariant,
          size: 22,
        ),
      );
    }

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(SolRadius.xs),
      ),
      child: Icon(
        entity.domain == WorkspaceDomain.drive
            ? _fileIcon(entity.mimeType)
            : entity.domain.icon,
        size: 18,
        color: scheme.primary,
      ),
    );
  }

  String? _buildSubtitleText() {
    final parts = <String>[];
    if (entity.subtitle != null && entity.subtitle!.isNotEmpty) {
      parts.add(entity.subtitle!);
    }
    if (entity.byteSize != null && entity.byteSize! > 0) {
      parts.add(_formatBytes(entity.byteSize!));
    }
    if (entity.status != null && entity.status!.isNotEmpty) {
      parts.add(entity.status!);
    }
    if (parts.isEmpty) return entity.domain.label;
    return parts.join(' · ');
  }

  List<Widget> _buildTrailingActions(
    BuildContext context,
    WidgetRef ref,
    ColorScheme scheme,
    bool isSaved,
  ) {
    final actions = <Widget>[];
    if (entity.domain == WorkspaceDomain.drive &&
        entity.isAttachment &&
        !isSaved) {
      actions.add(
        FilledButton.tonalIcon(
          onPressed: () {
            HapticFeedback.selectionClick();
            ref.read(savedAttachmentIdsProvider.notifier).markSaved(entity.id);
            onSaveToDrive?.call();
          },
          icon: const Icon(Symbols.cloud_upload_rounded, size: 16),
          label: Text('saveToDrive'.tr()),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
        ),
      );
    } else if (entity.domain == WorkspaceDomain.drive &&
        onDownloadOrPreview != null) {
      actions.add(
        IconButton(
          onPressed: onDownloadOrPreview,
          icon: const Icon(Symbols.download_rounded, size: 18),
          tooltip: 'download'.tr(),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    actions.add(
      IconButton(
        onPressed: () => ref.read(peekProvider.notifier).open(entity),
        icon: const Icon(Symbols.dock_to_right_rounded, size: 18),
        tooltip: 'openInPeek'.tr(),
        visualDensity: VisualDensity.compact,
      ),
    );
    return actions;
  }

  static IconData _fileIcon(String? mime) {
    if (mime == null) return Symbols.description_rounded;
    if (mime.startsWith('image/')) return Symbols.image_rounded;
    if (mime.startsWith('video/')) return Symbols.movie_rounded;
    if (mime.startsWith('audio/')) return Symbols.audio_file_rounded;
    if (mime.contains('pdf')) return Symbols.picture_as_pdf_rounded;
    return Symbols.description_rounded;
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
